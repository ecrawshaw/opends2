import Foundation

/// Talks to the bundled EdiabasLib engine (`opends2-engine`) over JSON lines on stdin/stdout.
/// One request at a time: the K-line is a single shared bus, so requests are serialized anyway.
final class Engine: @unchecked Sendable {
    enum EngineError: LocalizedError {
        case notFound(String), exited, failed(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let p): "Diagnostic engine not found at \(p)"
            case .exited: "The diagnostic engine stopped unexpectedly"
            case .failed(let m): m
            }
        }
    }

    /// What to tell someone whose engine dies on launch: almost always macOS blocking the self-signed helper
    /// inside a downloaded copy, which "Open Anyway" on the app doesn't cover.
    /// The command has to name the app where it really sits: a quarantined app opened from Downloads runs from a
    /// read-only copy under AppTranslocation, and xattr on that copy fails.
    static let unblockCommand = "xattr -dr com.apple.quarantine \"\(originalBundlePath)\""

    static var isTranslocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }

    private static var originalBundlePath: String {
        let path = Bundle.main.bundlePath
        guard isTranslocated else { return path }
        typealias Resolve = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        if let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
           let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL"),
           let original = unsafeBitCast(sym, to: Resolve.self)(Bundle.main.bundleURL as CFURL, nil)?.takeRetainedValue() {
            return (original as URL).path
        }
        return "/Applications/" + (path as NSString).lastPathComponent
    }

    var onProgress: ((String, Int?) -> Void)?

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<Any?, Error>] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "engine.serial")
    private let gate = AsyncGate()

    /// The app ships a .NET engine per architecture (opends2-engine-arm64 / -x64) because
    /// .NET can't emit a universal binary and `lipo` corrupts single-file bundles. Pick the
    /// one matching the slice we're running as (uname reports the process arch, Rosetta included).
    static func currentArchSuffix() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return machine == "x86_64" ? "x64" : "arm64"
    }

    static func locate() -> URL {
        let arch = currentArchSuffix()
        // Per-arch engine first; fall back to a plain name for older builds.
        for name in ["opends2-engine-\(arch)", "opends2-engine"] {
            if let bundled = Bundle.main.url(forAuxiliaryExecutable: name) { return bundled }
        }
        // Running from `swift run`: use the published engine next to the package
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for rel in ["../Engine/bin/publish-\(arch)/opends2-engine", "../Engine/bin/publish/opends2-engine"] {
            let url = base.appendingPathComponent(rel).standardized
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return base.appendingPathComponent("../Engine/bin/publish/opends2-engine").standardized
    }

    init() throws {
        let url = Engine.locate()
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw EngineError.notFound(url.path) }
        process.executableURL = url
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { self.failAll(EngineError.exited); return }
            self.queue.async { self.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in self?.failAll(EngineError.exited) }
        try process.run()
    }

    deinit { stop() }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    /// Ask the engine to stop the scan/read in progress (SIGINT; it finishes the current EDIABAS job first)
    func interrupt() {
        if process.isRunning { process.interrupt() }
    }

    func send(_ command: String, _ params: [String: Any] = [:]) async throws -> Any? {
        await gate.enter()
        defer { Task { await gate.leave() } }
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            let id = nextId
            nextId += 1
            pending[id] = cont
            lock.unlock()
            var body = params
            body["id"] = id
            body["cmd"] = command
            do {
                var line = try JSONSerialization.data(withJSONObject: body)
                line.append(0x0A)
                try input.fileHandleForWriting.write(contentsOf: line)
            } catch {
                // The engine may already have died and failAll() resumed this request; resuming twice traps
                lock.lock(); let mine = pending.removeValue(forKey: id); lock.unlock()
                mine?.resume(throwing: process.isRunning ? error : EngineError.exited)
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if obj["event"] as? String == "progress" {
                let message = obj["message"] as? String ?? ""
                let percent = obj["percent"] as? Int
                DispatchQueue.main.async { self.onProgress?(message, percent) }
                continue
            }
            guard let id = obj["id"] as? Int else { continue }
            lock.lock()
            let cont = pending.removeValue(forKey: id)
            lock.unlock()
            if obj["ok"] as? Bool == true {
                cont?.resume(returning: obj["data"] is NSNull ? nil : obj["data"])
            } else {
                cont?.resume(throwing: EngineError.failed(Engine.shortError(obj["error"] as? String ?? "Unknown error")))
            }
        }
    }

    /// EdiabasLib errors carry a stack trace; keep the first line plus the EDIABAS error description
    static func shortError(_ text: String) -> String {
        let first = text.components(separatedBy: "\n").first ?? text
        if let range = text.range(of: #"\((IFH|SYS|BIP|API|NET)-\d+: [^)]*\)"#, options: .regularExpression) {
            return "\(first.trimmingCharacters(in: .whitespaces)) \(text[range])"
        }
        return first
    }

    private func failAll(_ error: Error) {
        lock.lock()
        let all = pending
        pending.removeAll()
        lock.unlock()
        all.values.forEach { $0.resume(throwing: error) }
    }
}

/// A tiny async mutex so only one request is on the wire at a time
actor AsyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func enter() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func leave() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}
