import Foundation
import SwiftUI

/// Cluster VIN (FG_NR) write — align a swapped cluster's stored chassis number to the car it's in.
///
/// RE (verified on-car): the FG_NR is at bank-03 EEPROM byte 0x7A (word 0x3D) as [2 ASCII letters]
/// [3 BCD digit bytes]; byte 0x7F (the GWSZ offset) shares word 0x3F and is preserved. The change is a
/// raw 06/07-03 memory write (`clustervin`), NOT C_S_SCHREIBEN (coding-masked) and NOT the vehicle order;
/// the engine keeps CHECKSUM @0x16E consistent and self-checks the raw channel before writing. Prove the
/// raw channel first with "Prove raw channel" (read-only). Procedure: docs/CLUSTER-VIN-FIX.md.
///
/// Gated behind `AppState.vinWriteEnabled` (Setup toggle), false by default. Human-only (never MCP).
///
/// SWAP-ONLY: the write can only make a swapped cluster match the car it is in. The car's own chassis
/// number is read from the body module or immobilizer (modules that stay with the car); the write is
/// refused when the cluster already matches, and the only VIN it accepts is the car's.
///
/// STATUS: EXPERIMENTAL — NOT WORKING YET. The write has not yet taken effect on a real cluster
/// (see docs/CLUSTER-VIN-FIX.md). Keep it off unless you are helping debug it.
extension AppState {
    /// Shown wherever the VIN write is offered.
    static let vinWriteStatusNote = "Experimental: the cluster VIN write does not work yet. It has not taken effect on a real cluster so far. Reading the VIN works."

    /// The car's own chassis number (last 7 of the VIN, e.g. "JR12345"), read with C_FG_LESEN from a
    /// module that stays with the car — the body module (ZKE/GM) or the immobilizer (EWS). Read-only.
    func carChassisNumber() async -> (source: String, fg: String)? {
        let candidates = modules.filter {
            let s = $0.sgbd.lowercased()
            return s.hasPrefix("zke") || s.hasPrefix("gm") || s.hasPrefix("ews")
        }
        for m in candidates {
            let v = await bodyVIN(m).uppercased().filter { $0.isLetter || $0.isNumber }
            if v.count >= 7 { return (m.title, String(v.suffix(7))) }
        }
        return nil
    }

    /// FG_NR region: word 0x3D (byte 0x7A), 3 words = bytes 0x7A-0x7F (5 FG_NR bytes + preserved 0x7F).
    static let fgNrWord = 0x3D
    static let fgNrWords = 3

    struct FgNrBackup: Codable {
        var date: Date
        var sgbd: String
        var wordAddr: Int
        var beforeHex: String
        var afterHex: String
        var beforeVin: String
        var afterVin: String
        var reason: String
        var result: String?
    }

    struct FgNrPlan {
        let wordAddr: Int
        let beforeHex: String      // 6 bytes
        let afterHex: String       // 6 bytes
        let beforeVin: String
        let afterVin: String
        let voltage: Double
        let backupURL: URL
        var backup: FgNrBackup
        let diff: String
        let isTest: Bool
    }

    struct ClusterVinError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }

    static var vinBackupFolder: URL {
        AppPaths.support.appendingPathComponent("cluster-coding-backups", isDirectory: true)
    }

    func vinBackups(_ module: Module) -> [(url: URL, backup: FgNrBackup)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.vinBackupFolder, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return urls.compactMap { u in
            guard u.pathExtension == "json", let d = try? Data(contentsOf: u), let b = try? dec.decode(FgNrBackup.self, from: d),
                  b.sgbd.caseInsensitiveCompare(module.sgbd) == .orderedSame else { return nil }
            return (u, b)
        }.sorted { $0.backup.date > $1.backup.date }
    }

    func saveVinBackup(_ backup: inout FgNrBackup, url: URL? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: Self.vinBackupFolder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let target = url ?? Self.vinBackupFolder.appendingPathComponent("\(f.string(from: backup.date))-\(backup.sgbd)-vin.json")
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        try enc.encode(backup).write(to: target, options: .atomic)
        return target
    }

    // MARK: encoding

    static func hexString(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

    /// Encode a 7-char FG_NR ("AB12345") -> 5 bytes [2 ASCII][3 BCD]; nil if not 2 letters + 5 digits.
    static func encodeFgNr(_ fg: String) -> [UInt8]? {
        let chars = Array(fg.uppercased().trimmingCharacters(in: .whitespacesAndNewlines))
        guard chars.count == 7, chars[0].isLetter, chars[1].isLetter,
              chars[2...].allSatisfy({ $0.isNumber }), let a0 = chars[0].asciiValue, let a1 = chars[1].asciiValue else { return nil }
        let digits = Array(String(chars[2...]) + "0")   // 5 digits padded to 6 (dropped nibble)
        var bcd = [UInt8]()
        for i in stride(from: 0, to: 6, by: 2) {
            guard let hi = digits[i].wholeNumberValue, let lo = digits[i + 1].wholeNumberValue else { return nil }
            bcd.append(UInt8(hi << 4 | lo))
        }
        return [a0, a1] + bcd
    }

    /// Decode 5+ bytes [2 ASCII][3 BCD] -> "AB12345".
    static func decodeFgNr(_ b: [UInt8]) -> String {
        guard b.count >= 5 else { return "?" }
        let letters = String(bytes: b[0..<2], encoding: .ascii) ?? "??"
        let bcd = b[2..<5].map { String(format: "%02X", $0) }.joined()   // 6 hex chars
        return letters + String(bcd.prefix(5))
    }

    // MARK: reading

    /// Read `count` 2-byte words from `word` (read-only, via EEPROM_LESEN in the engine).
    func readWords(_ module: Module, word: Int, count: Int) async throws -> [UInt8] {
        let res = try await engineSend("clusterread", ["sgbd": module.sgbd, "wordAddr": word, "words": count])
        guard let dict = res as? [String: Any], let hex = dict["data"] as? String,
              let bytes = AppState.hexBytes(hex), bytes.count == count * 2 else {
            throw ClusterVinError("Couldn't read the cluster EEPROM (word 0x\(String(word, radix: 16))).")
        }
        return bytes
    }

    /// Read the 6-byte FG_NR region (bytes 0x7A-0x7F = words 0x3D-0x3F).
    func readFgNrWord(_ module: Module) async throws -> [UInt8] {
        try await readWords(module, word: Self.fgNrWord, count: Self.fgNrWords)
    }

    /// Read the current GWSZ offset byte (0x7F = high byte of word 0x3F).
    func readOffsetByte(_ module: Module) async throws -> UInt8 {
        let w = try await readWords(module, word: Self.fgNrWord + 2, count: 1)   // word 0x3F = bytes 0x7E,0x7F
        return w[1]
    }

    /// Read and decode the cluster's stored VIN (FG_NR) for display.
    func readClusterVin(_ module: Module) async -> String? {
        await run("Reading cluster VIN…") { [self] in
            let bytes = try await readFgNrWord(module)
            return AppState.decodeFgNr(Array(bytes.prefix(5)))
        }
    }

    /// READ-ONLY proof that the raw-telegram channel the VIN write uses is sound: a raw 06 03 read must
    /// echo the EEPROM_LESEN bytes. Run this on the car before trusting a write. Returns a short status.
    func proveClusterRawChannel(_ module: Module) async -> String? {
        await run("Proving the raw channel (read-only)…") { [self] in
            let res = try await engineSend("clusterrawprobe",
                                           ["sgbd": module.sgbd, "wordAddr": Self.fgNrWord, "words": Self.fgNrWords])
            guard let d = res as? [String: Any], let match = d["match"] as? Bool else {
                throw ClusterVinError("The raw-channel probe didn't return a result.")
            }
            let eeprom = (d["eepromLesen"] as? String) ?? "?"
            let raw = (d["rawResponse"] as? String) ?? "?"
            return match
                ? "✓ Raw channel OK — raw read echoes EEPROM_LESEN (\(eeprom)). The VIN write is proven on this car."
                : "✗ No match — EEPROM_LESEN \(eeprom) not found in raw reply \(raw). Do NOT write the VIN yet."
        }
    }

    // MARK: write flow

    /// Request a VIN change to `newVin` (or a reversible one-byte test when `test` is set).
    func requestClusterVinWrite(_ module: Module, newVin: String, reason: String, test: Bool = false) async {
        do {
            let plan = try await prepareVinWrite(module, newVin: newVin, reason: reason, test: test)
            pending = PendingAction(
                title: test ? "Run the one-byte VIN test?" : "Write the cluster VIN?",
                message: """
                \(test ? "This flips one byte, reads it back, then restores it — to see whether the cluster flags a checksum error." : "This changes the cluster's stored chassis number.")
                A backup was saved to \(plan.backupURL.lastPathComponent). The write is read back and verified. \
                Battery \(String(format: "%.1f", plan.voltage)) V, engine off. Keep ignition on.
                """,
                confirm: test ? "Run test" : "Write VIN",
                run: { [self] in await performVinWrite(module, plan) },
                detail: plan.diff,
                delay: 3,
                confirmIsDefault: false)
        } catch {
            lastError = error.localizedDescription
            note("Cluster VIN write refused", ok: false, error.localizedDescription)
        }
    }

    func prepareVinWrite(_ module: Module, newVin: String, reason: String, test: Bool) async throws -> FgNrPlan {
        guard Self.vinWriteEnabled else {
            throw ClusterVinError("Cluster VIN write is off. Enable it in Setup (“Cluster VIN write”) for the documented procedure — see docs/CLUSTER-VIN-FIX.md.")
        }
        guard module.isCluster || module.sgbd.lowercased() == "kombi46r" else {
            throw ClusterVinError("Cluster VIN write is only available for the instrument cluster (kombi46r).")
        }
        guard !busy, pending == nil else { throw ClusterVinError("Something else is running; try again when it finishes.") }
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !why.isEmpty else { throw ClusterVinError("Record what this change is and why before writing.") }

        // The GWSZ offset (byte 0x7F) shares word 0x3F with the last VIN byte (0x7E). It is never
        // changed: the test touches ONLY word 0x3E (bytes 0x7C-0x7D), and the real write keeps byte 0x7F.
        let beforeVin = AppState.decodeFgNr(Array(try await readFgNrWord(module).prefix(5)))

        // Swap-only: compare against the car's own VIN, read from a module that stays with the car.
        guard let car = await carChassisNumber() else {
            throw ClusterVinError("Couldn't read the car's VIN from the body module or immobilizer. The cluster VIN write is only for a swapped cluster, so it needs the car's own VIN to compare against. Scan the car, then try again.")
        }
        guard beforeVin != car.fg else {
            throw ClusterVinError("The cluster already matches this car (\(car.fg), read from \(car.source)). The VIN write is only for a swapped cluster whose VIN doesn't match.")
        }
        if !test {
            let wanted = newVin.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard wanted == car.fg else {
                throw ClusterVinError("The new VIN must be this car's own VIN, \(car.fg) (read from \(car.source)). The cluster can only be aligned to the car it's in.")
            }
        }

        let wordAddr: Int
        let current: [UInt8]
        var after: [UInt8]
        let afterVin: String
        if test {
            // One-byte test in word 0x3E (byte 0x7D, a FG_NR digit), writing ONLY that word — the offset
            // word 0x3F is not written at all, so the odometer offset cannot move.
            wordAddr = Self.fgNrWord + 1                          // 0x3E = bytes 0x7C,0x7D
            current = try await readWords(module, word: wordAddr, count: 1)   // 2 bytes
            after = current
            after[1] = current[1] ^ 0x11                          // flip bits of byte 0x7D (reversible)
            afterVin = "\(beforeVin)  (one-byte test on 0x7D only)"
        } else {
            // Real change: words 0x3D-0x3F; replace the 5 FG_NR bytes (0x7A-0x7E), KEEP byte 0x7F (offset).
            wordAddr = Self.fgNrWord                              // 0x3D
            current = try await readFgNrWord(module)              // 6 bytes (0x7A-0x7F)
            guard let fg = AppState.encodeFgNr(newVin) else {
                throw ClusterVinError("VIN must be 2 letters + 5 digits (e.g. AB12345).")
            }
            after = current
            for i in 0..<5 { after[i] = fg[i] }                   // index 5 (byte 0x7F offset) kept as-read
            afterVin = AppState.decodeFgNr(fg)
        }
        guard after != current else { throw ClusterVinError("Nothing to change at word 0x\(String(wordAddr, radix: 16)).") }

        let voltage = try await checkCodingPreconditions()

        var backup = FgNrBackup(date: Date(), sgbd: module.sgbd, wordAddr: wordAddr,
                                beforeHex: AppState.hexString(current), afterHex: AppState.hexString(after),
                                beforeVin: beforeVin, afterVin: afterVin, reason: why, result: nil)
        let backupURL = try saveVinBackup(&backup)

        let diff = """
        Module: \(module.title) (\(module.sgbd))
        VIN: \(beforeVin)  →  \(afterVin)
        Car's VIN (from \(car.source)): \(car.fg)
        Word 0x\(String(wordAddr, radix: 16)): \(AppState.hexString(current)) → \(AppState.hexString(after))\(test ? "" : "  (byte 0x7F offset unchanged)")
        Battery: \(String(format: "%.1f", voltage)) V
        """

        return FgNrPlan(wordAddr: wordAddr, beforeHex: backup.beforeHex, afterHex: backup.afterHex,
                        beforeVin: beforeVin, afterVin: afterVin, voltage: voltage,
                        backupURL: backupURL, backup: backup, diff: diff, isTest: test)
    }

    /// Execute via the gated `clustervin` engine command (which reads back and verifies).
    func performVinWrite(_ module: Module, _ plan: FgNrPlan) async {
        var backup = plan.backup
        let ok: Bool? = await run(plan.isTest ? "Running VIN test…" : "Writing cluster VIN…") { [self] in
            _ = try await engineSend("clustervin", [
                "sgbd": module.sgbd, "wordAddr": plan.wordAddr,
                "data": plan.afterHex, "expect": plan.beforeHex])
            // One-byte test restores immediately so the cluster is never left changed.
            if plan.isTest {
                _ = try await engineSend("clustervin", [
                    "sgbd": module.sgbd, "wordAddr": plan.wordAddr,
                    "data": plan.beforeHex, "expect": plan.afterHex])
            }
            return true
        }
        // Always confirm the GWSZ offset (byte 0x7F) afterwards — the odometer figure depends on it.
        let offsetAfter: UInt8? = ok == true ? (try? await readOffsetByte(module)) : nil
        let offTxt = offsetAfter.map { " Offset byte 0x7F now reads \(Int($0)) (0x\(String(format: "%02X", $0)))." } ?? ""
        backup.result = ok == true ? (plan.isTest ? "test written and restored" : "written and verified") : "failed: \(lastError ?? "unknown")"
        _ = try? saveVinBackup(&backup, url: plan.backupURL)
        if ok == true {
            if plan.isTest {
                note("VIN test complete — restored", ok: true, "One byte (0x7D) changed and put back; word 0x3F (offset) was never written.\(offTxt) Now check the cluster: did a checksum/warning indicator appear? Backup: \(plan.backupURL.lastPathComponent)")
            } else {
                let expectedOffset = AppState.hexBytes(plan.afterHex)?.last
                let offsetOK = offsetAfter != nil && offsetAfter == expectedOffset
                note(offsetOK ? "Cluster VIN written: \(plan.afterVin)" : "⚠️ VIN written but OFFSET MOVED — restore the backup now",
                     ok: offsetOK,
                     "\(offsetOK ? "Offset preserved." : "The GWSZ offset is not what it was — this changes the displayed mileage. Restore the backup immediately.")\(offTxt) Backup: \(plan.backupURL.path)")
            }
            await read(module)
        } else {
            note(plan.isTest ? "VIN test failed" : "Cluster VIN write failed", ok: false, lastError ?? "")
        }
    }

    /// Restore the FG_NR from a prior backup (writes the saved `before` bytes back).
    func requestVinRestore(_ module: Module, _ entry: (url: URL, backup: FgNrBackup)) async {
        guard Self.vinWriteEnabled else {
            note("Cluster VIN restore refused", ok: false, "VIN writes are disabled."); return
        }
        guard let before = AppState.hexBytes(entry.backup.beforeHex), let after = AppState.hexBytes(entry.backup.afterHex) else {
            note("Cluster VIN restore refused", ok: false, "Backup is unreadable."); return
        }
        let ok: Bool? = await run("Restoring cluster VIN…") { [self] in
            // expect = whatever the backup wrote (after); data = the saved original (before).
            _ = try await engineSend("clustervin", [
                "sgbd": module.sgbd, "wordAddr": entry.backup.wordAddr,
                "data": AppState.hexString(before), "expect": AppState.hexString(after)])
            return true
        }
        if ok == true { note("Cluster VIN restored: \(entry.backup.beforeVin)", ok: true); await read(module) }
        else { note("Cluster VIN restore failed", ok: false, lastError ?? "") }
    }
}

struct ClusterVinSection: View {
    @EnvironmentObject var state: AppState
    let module: Module
    @State private var newVin: String = ""
    @State private var reason: String = ""
    @State private var currentVin: String = "—"
    @State private var rawProbe: String?
    @AppStorage(AppState.vinWriteDefaultsKey) private var enabled = false

    var backups: [(url: URL, backup: AppState.FgNrBackup)] { state.vinBackups(module) }

    var body: some View {
        Section("Cluster VIN (chassis number)") {
            VStack(alignment: .leading, spacing: 10) {
                Label(AppState.vinWriteStatusNote, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
                if !enabled {
                    Label("VIN write is off. Turn on “Cluster VIN write” in Setup to enable it for the documented procedure (docs/CLUSTER-VIN-FIX.md). Reading the VIN works either way.", systemImage: "lock.shield.fill")
                        .foregroundStyle(.orange).font(.callout)
                    Text("Only for a swapped cluster: the app reads the car's own VIN from the body module or immobilizer, and the only change it allows is making the cluster match it. Keep a record of the change.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Text("Current VIN:").foregroundStyle(.secondary)
                    Text(currentVin).monospaced().bold()
                    Button("Read") { Task { if let v = await state.readClusterVin(module) { currentVin = v } } }
                        .buttonStyle(.bordered).disabled(state.busy || !state.configured)
                    Button("Prove raw channel") { Task { rawProbe = await state.proveClusterRawChannel(module) } }
                        .buttonStyle(.bordered).disabled(state.busy || !state.configured)
                        .help("Read-only: confirms the raw-telegram write path works on this car before any VIN write.")
                }
                if let rawProbe {
                    Text(rawProbe).font(.caption).monospaced()
                        .foregroundStyle(rawProbe.hasPrefix("✓") ? .green : .orange)
                        .textSelection(.enabled)
                }

                TextField("Reason (e.g. used cluster from a donor car, aligning to this car)", text: $reason)
                    .textFieldStyle(.roundedBorder).disabled(!enabled || state.busy)

                HStack {
                    TextField("Car's VIN (last 7, e.g. AB12345)", text: $newVin)
                        .textFieldStyle(.roundedBorder).frame(width: 160)
                        .disabled(!enabled || state.busy)

                    Button("Test (one byte)…") {
                        Task { await state.requestClusterVinWrite(module, newVin: newVin, reason: reason, test: true) }
                    }
                    .disabled(!enabled || state.busy || !state.configured || reason.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Write VIN…") {
                        Task { await state.requestClusterVinWrite(module, newVin: newVin, reason: reason) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!enabled || state.busy || !state.configured
                              || AppState.encodeFgNr(newVin) == nil
                              || reason.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !backups.isEmpty {
                        Menu("Restore") {
                            ForEach(backups.prefix(10), id: \.url) { entry in
                                Button("\(entry.backup.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.backup.beforeVin) → \(entry.backup.afterVin)") {
                                    Task { await state.requestVinRestore(module, entry) }
                                }
                            }
                        }
                        .disabled(!enabled || state.busy)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
