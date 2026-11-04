import AppKit
import Foundation

// In-app updater. Fetches a build from an update source the user sets in Setup, swaps the running
// .app bundle, and relaunches. Because the app downloads the file itself (not a browser), the
// downloaded bundle carries no com.apple.quarantine flag, so Gatekeeper doesn't re-prompt on update.
//
// The source URL can be either:
//   • a version.json manifest  { "build": <int>, "shortVersion": "..", "url": "<zip url>", "notes": ".." }
//     → the app compares build numbers and only offers a newer one. (GitHub Releases; build-app.sh writes it.)
//   • a direct .zip URL         → the app installs whatever is there, after the user confirms.
//     (For a private build: any direct-download link.)
//
// This is the one place the app reaches the network other than the local MCP server; it's a
// deliberate, user-initiated fetch from a URL the user typed (see CLAUDE.md).
extension AppState {
    /// GitHub Releases: each release attaches version.json + OpenDS2.zip (build-app.sh writes both to dist/).
    static let defaultUpdateURL = "https://github.com/ecrawshaw/opends2/releases/latest/download/version.json"

    /// The running build, from CFBundleVersion. 0 when run from `swift run` (no bundle) — never "newer".
    var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }
    var currentVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return currentBuild > 0 ? "\(short) (build \(currentBuild))" : "\(short) (dev build)"
    }

    /// Check the update source. `silent` (launch check) stays quiet unless a newer build is found.
    func checkForUpdates(silent: Bool) async {
        let raw = updateURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw), url.scheme == "http" || url.scheme == "https" else {
            if !silent { updateStatus = "Enter a valid http(s) update URL first." }
            return
        }
        pendingUpdateZip = nil
        if !silent { updateStatus = "Checking…" }
        do {
            if raw.lowercased().hasSuffix(".json") {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let m = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let build = (m["build"] as? Int) ?? Int("\(m["build"] ?? "")"),
                      let zip = m["url"] as? String, let zipURL = URL(string: zip) else {
                    updateStatus = "The update manifest at that URL is malformed."; return
                }
                let notes = (m["notes"] as? String).flatMap { $0.isEmpty ? nil : " — \($0)" } ?? ""
                if build > currentBuild {
                    pendingUpdateZip = zipURL
                    updateStatus = "Update available: build \(build)\(notes)."
                } else if !silent {
                    updateStatus = "You're up to date (build \(currentBuild))."
                }
            } else {
                // Direct zip link (e.g. Google Drive). No build number to compare, so only offer on an
                // explicit check, never nag on launch.
                guard !silent else { return }
                pendingUpdateZip = url
                updateStatus = "Ready to download and install from this link."
            }
        } catch {
            if !silent { updateStatus = "Couldn't reach the update URL: \(error.localizedDescription)" }
        }
    }

    /// Download the pending zip, replace this app bundle, and relaunch.
    func installUpdate() {
        guard let zipURL = pendingUpdateZip else { return }
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else {
            updateStatus = "Updates only work on the installed app, not a dev build."; return
        }
        updating = true
        updateStatus = "Downloading…"
        Task {
            defer { updating = false }
            do {
                let (tmpFile, response) = try await URLSession.shared.download(from: zipURL)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    updateStatus = "Download failed (HTTP \(http.statusCode))."; return
                }
                // Guard against a URL that returns a web page (e.g. a Drive "can't scan this file"
                // interstitial) instead of the zip: a real zip starts with "PK".
                let head = (try? FileHandle(forReadingFrom: tmpFile))?.readData(ofLength: 2)
                guard head == Data([0x50, 0x4B]) else {
                    updateStatus = "That URL returned a web page, not the app. Use a direct-download link to the .zip."
                    return
                }
                updateStatus = "Installing…"
                let work = FileManager.default.temporaryDirectory
                    .appendingPathComponent("opends2-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: work) }

                // ditto -x -k matches how the zip was made (ditto -c -k) and preserves exec bits + signature.
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", tmpFile.path, work.path]
                try unzip.run(); unzip.waitUntilExit()
                guard unzip.terminationStatus == 0 else { updateStatus = "Couldn't unzip the download."; return }

                guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                        .first(where: { $0.pathExtension == "app" }) else {
                    updateStatus = "The download didn't contain an app."; return
                }

                // Hand the atomic swap + relaunch to a detached shell that waits for us to quit, then
                // replaces the bundle in place and reopens it. Paths are passed as argv, not interpolated
                // into the script body, so spaces and quotes can't break or inject into the command.
                let pid = ProcessInfo.processInfo.processIdentifier
                let swap = Process()
                swap.executableURL = URL(fileURLWithPath: "/bin/sh")
                swap.arguments = ["-c", """
                    while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
                    rm -rf "$2" && mv "$3" "$2" || exit 1
                    xattr -dr com.apple.quarantine "$2" 2>/dev/null
                    open "$2"
                    """, "sh", "\(pid)", bundlePath, newApp.path]
                try swap.run()
                updateStatus = "Restarting…"
                try? await Task.sleep(nanoseconds: 300_000_000)
                NSApp.terminate(nil)
            } catch {
                updateStatus = "Update failed: \(error.localizedDescription)"
            }
        }
    }
}
