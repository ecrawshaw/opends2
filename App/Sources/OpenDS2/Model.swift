import AppKit
import Foundation
import SwiftUI

typealias ResultSet = [String: Any]

struct Module: Identifiable, Hashable {
    var id: String { sgbd }
    let group: String
    let sgbd: String
    let name: String
    let ident: ResultSet

    static func == (a: Module, b: Module) -> Bool { a.sgbd == b.sgbd }
    func hash(into h: inout Hasher) { h.combine(sgbd) }

    /// Readable English name: from the SGBD file name, then the SGBD's own (German) comment, then
    /// what the address usually is on an E46
    var title: String {
        Module.englishName(sgbd) ?? (name.isEmpty ? (Module.knownAddresses[group] ?? sgbd.uppercased()) : name)
    }

    /// English names by SGBD file-name prefix (longest prefix wins). The SGBD comment EDIABAS
    /// returns is German ("3-Kanal Sitzmemory E46/E85"), so it's kept only as the subtitle.
    static func englishName(_ sgbd: String) -> String? {
        let s = sgbd.lowercased()
        return sgbdNames.filter { s.hasPrefix($0.0) }.max { $0.0.count < $1.0.count }?.1
    }

    static let sgbdNames: [(String, String)] = [
        ("mss5", "Engine (DME, S54)"), ("ms4", "Engine (DME)"), ("me7", "Engine (DME)"), ("me9", "Engine (DME)"),
        ("dde", "Engine (diesel DDE)"), ("d50", "Engine (diesel DDE)"),
        ("smg", "SMG transmission"), ("ssg", "SMG transmission"), ("gs", "Automatic transmission (EGS)"),
        ("egs", "Automatic transmission (EGS)"),
        ("dsc", "ABS / DSC"), ("abs", "ABS / DSC"), ("asc", "ABS / ASC"),
        ("ews", "Immobilizer (EWS)"), ("kombi", "Instrument cluster"), ("ike", "Instrument cluster"),
        ("ihka", "Climate control (IHKA)"), ("ihkr", "Heater controls (IHKR)"), ("ihk", "Climate control"),
        ("zke", "Body module (ZKE / GM5)"), ("gm5", "Body module (ZKE / GM5)"),
        ("lsz", "Light switch module (LSZ)"), ("lcm", "Light module (LCM)"), ("lm", "Light module"),
        ("lws", "Steering angle sensor"), ("mfl", "Steering wheel buttons (MFL)"),
        ("mrs", "Airbag (MRS)"), ("acsm", "Airbag (ACSM)"),
        ("sm", "Seat memory"), ("shd", "Sunroof"), ("cvm", "Convertible top (CVM)"),
        ("pdc", "Park distance control (PDC)"), ("rls", "Rain / light sensor"), ("rlss", "Rain / light sensor"),
        ("rad", "Radio"), ("bmbt", "On-board monitor"), ("mid", "Multi-info display (MID)"),
        ("nav", "Navigation"), ("tel", "Telephone"), ("cdc", "CD changer"), ("vm", "Video module"),
        ("ahm", "Trailer module"), ("lwr", "Headlight leveling"), ("aldw", "Headlight leveling"),
        ("szm", "Center console switches"), ("dwa", "Alarm (DWA)"), ("uss", "Alarm sensor"),
    ]

    static let knownAddresses: [String: String] = [
        "d_0000": "Body module (ZKE / GM5)", "d_0012": "Engine (DME)", "d_motor": "Engine (DME)",
        "d_0032": "SMG transmission", "d_0044": "Immobilizer (EWS)", "d_0056": "ABS / DSC",
        "d_005b": "Climate (IHKA)", "d_0060": "Park distance (PDC)", "d_0068": "Radio",
        "d_0080": "Instrument cluster (IKE)", "d_00a4": "Airbag (MRS)", "d_00d0": "Light module (LSZ)",
        "d_00e8": "Rain / light sensor", "d_0050": "Steering wheel controls (MFL)",
    ]
}

/// One block of a module's coding as the module itself describes it (Coding tab)
struct CodingSection: Identifiable {
    var id: String { job }
    let job: String
    var items: [(key: String, value: String)] = []
    var error: String?

    var title: String {
        switch job {
        case "CODIERUNG_LESEN", "CODIERDATEN_LESEN": "Settings"
        case "CODIERUNG_BLOCK_1_LESEN", "C_CI_LESEN": "Coding version"
        case "C_FG_LESEN", "FGNR_LESEN": "VIN stored in this module"
        case "C_ZCS_LESEN", "ZCS_LESEN": "Central coding key (ZCS)"
        case "C_AZCS_LESEN": "Additional coding key"
        case "C_FA_LESEN": "Vehicle order (FA)"
        case "CODIERUNG_CHECK", "STATUS_CODIER_CHECKSUMME": "Coding checksum"
        default: job
        }
    }
}

/// One fault-memory entry, from an FS_LESEN result set
struct Fault: Identifiable {
    let id = UUID()
    let code: String
    let text: String
    let details: [(String, String)]
    /// Freeze-frame "conditions when stored" (mileage, occurrences, warning lamp, environment),
    /// from FS_LESEN_DETAIL — ISTA's fault-detail view.
    var conditions: [(String, String)] = []
    /// The module's own (German) text, when `text` is a translation
    var original: String = ""
    /// Practical pointer for common faults
    var note: String? = nil
}

/// A write action waiting for the user to confirm it
struct PendingAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirm: String
    let run: () async -> Void
    var cancel: (() -> Void)? = nil
    /// Monospaced detail shown under the message (e.g. the exact byte change of a coding write).
    var detail: String? = nil
    /// Seconds before the confirm button can be pressed (coding writes: 3).
    var delay: TimeInterval = 0
    /// False: Return doesn't press confirm (coding writes need a deliberate click).
    var confirmIsDefault = true
    let created = Date()
}

struct LogLine: Identifiable {
    let id = UUID()
    let date = Date()
    let title: String
    let ok: Bool
    let detail: String
}

struct LiveValue: Identifiable {
    var id: String { job + "/" + name }
    let job: String
    let name: String
    let value: String
    let unit: String
    /// The full EDIABAS result name (e.g. STAT_RAD_GESCHW_VL_WERT), for the English label
    var key: String = ""
    var label: String { ValueNames.label(key.isEmpty ? name : key) }
    var help: String { ValueNames.lookup(key.isEmpty ? name : key)?.help ?? "" }
}

struct ModuleReport {
    var faults: [Fault] = []
    var infoMemory: [Fault] = []
    var ident: [(String, String)] = []
    var live: [LiveValue] = []
    var errors: [String] = []
    var raw: [String: Any] = [:]
    /// Live values (STATUS_* jobs) were read; "Read all" skips them to save time
    var valuesRead: Bool { raw["STATUS"] != nil }
}

@MainActor
final class AppState: ObservableObject {
    @AppStorage("ecuPath") var ecuPath: String = ""
    /// Folder of BMW NCS Expert DATEN files (the `.cXX` coding files + swtfsw01.dat). Optional:
    /// when set, the Coding tab can decode coding into named options. Not bundled; the user points
    /// at their own copy.
    @AppStorage("datenPath") var datenPath: String = ""
    /// Unit system for readings. The car reports metric; "imperial" converts at display time.
    /// Default imperial (this is a US-market car); the Setup picker flips it.
    @AppStorage("units") var units: String = "imperial"
    var unitSystem: UnitSystem { UnitSystem(rawValue: units) ?? .imperial }
    @AppStorage("port") var port: String = ""
    /// Group files that answered in the last full scan, comma-separated; a quick scan checks only these
    @AppStorage("knownGroups") var knownGroups: String = ""
    /// Record all K-line traffic to a folder on the Desktop (for writing our own module definitions)
    @AppStorage("recordTraffic") var recordTraffic: Bool = false
    @Published var trafficFolder: URL?
    /// "obd" = K+DCAN cable (E-series), "enet" = Ethernet (F/G-series and later)
    @AppStorage("iface") var iface: String = "obd"
    /// ENET vehicle IP; empty = auto-discover
    @AppStorage("enetHost") var enetHost: String = ""
    /// Which module group set to scan: "ds2" = E-series K-line (E46…), "dcan" = D-CAN / F-series (g_*)
    @AppStorage("scanSet") var scanSet: String = "ds2"
    @AppStorage("mcpEnabled") var mcpEnabled = false
    @AppStorage("mcpToken") var mcpToken: String = ""

    @Published var mcpRunning = false
    @Published var mcpError: String?
    /// When Claude last made an MCP request and what it called — drives the "Claude connected" indicator.
    @Published var mcpLastActivity: Date?
    @Published var mcpLastTool: String?
    /// Total MCP requests served since launch.
    @Published var mcpRequestCount = 0
    private var mcp: MCPServer?

    /// Called from the MCP server on every request (tool call, initialize, ping…).
    func recordMCPActivity(_ label: String) {
        mcpLastActivity = Date()
        mcpLastTool = label
        mcpRequestCount += 1
    }

    @Published var ports: [String] = []
    @Published var modules: [Module] = []
    @Published var reports: [String: ModuleReport] = [:]
    /// Read-only coding, per SGBD (Coding tab)
    @Published var coding: [String: [CodingSection]] = [:]
    @Published var selection: Module?
    @Published var busy = false
    /// The running operation is a read or scan, so it can be stopped
    @Published var stoppable = false
    /// Stop was pressed; stays true until the next operation starts so batch loops can see it
    @Published var stopping = false
    @Published var status = "Ready"
    @Published var percent: Int?
    @Published var lastError: String?
    @Published var configured = false
    @Published var engineBlocked = false

    // View state lives here: the Command Line Tools SDK lacks the SwiftUI macro plugin that @State needs
    @Published var showSetup = false
    @Published var tab = 0
    @Published var filter = ""
    @Published var showHistory = false
    @Published var compareA: String?
    @Published var compareB: String?

    @Published var history: [HistoryEntry] = HistoryStore.load()
    @Published var pending: PendingAction?
    @Published var log: [LogLine] = []
    /// When the last component test ran, so tests can't be fired back to back
    @Published var lastTestAt: Date?
    static let testCooldown: TimeInterval = 10

    /// In-app update source (set in Setup) and progress. See Updater.swift.
    @Published var updateURL: String = UserDefaults.standard.string(forKey: "updateURL") ?? AppState.defaultUpdateURL {
        didSet { UserDefaults.standard.set(updateURL, forKey: "updateURL") }
    }
    @Published var updateStatus = ""
    @Published var updating = false
    var pendingUpdateZip: URL?

    let live = LiveMonitor()

    private var engine: Engine?

    init() {
        do {
            let engine = try Engine()
            engine.onProgress = { [weak self] message, percent in
                self?.status = message
                self?.percent = percent
            }
            self.engine = engine
            live.poll = { sgbd, jobs in
                try await engine.send("poll", ["sgbd": sgbd, "jobs": jobs]) as? [String: Any] ?? [:]
            }
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
                engine.stop()
            }
        } catch {
            lastError = error.localizedDescription
        }
        Task { await refreshPorts(); await configure() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshPorts() }
        }
        if mcpEnabled { startMCP() }
        Snapshot.schedule(self)
    }

    /// The selected port exists right now and is named like a USB serial adapter.
    var cableLooksPresent: Bool { ports.contains(port) && Self.looksLikeCable(port) }

    /// K+DCAN clones use FTDI (cu.usbserial-…), CH340 (cu.wchusbserial…/cu.usbserial-…),
    /// CP210x (cu.SLAB_USBtoUART) or CDC-ACM (cu.usbmodem…) chips.
    static func looksLikeCable(_ path: String) -> Bool {
        let p = path.lowercased()
        return ["usbserial", "usbmodem", "slab_usbtouart", "wchusb"].contains { p.contains($0) }
    }

    /// Lists /dev/cu.* directly (no engine round trip), so it's cheap enough to poll and still
    /// works while the engine is busy or blocked. Called at launch and every 2 s, which picks up
    /// a cable plugged in after the app opened.
    func refreshPorts() async {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let list = names.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.hasSuffix("debug-console") }
            .map { "/dev/" + $0 }.sorted()
        if list != ports { ports = list }
        if !busy, !list.contains(port) || !Self.looksLikeCable(port), let cable = list.first(where: Self.looksLikeCable), cable != port {
            port = cable
            await configure()
        }
    }

    /// One folder per app session: ~/Desktop/OpenDS2 traffic/<date time>/ifh.trc
    func applyRecording() async {
        if recordTraffic, trafficFolder == nil {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"
            trafficFolder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/OpenDS2 traffic/\(f.string(from: Date()))")
        }
        if !recordTraffic { trafficFolder = nil }
        _ = try? await engine?.send("trace", ["path": recordTraffic ? (trafficFolder?.path ?? "") : ""])
    }

    func configure() async {
        guard !ecuPath.isEmpty else { configured = false; return }
        await applyRecording()
        do {
            _ = try await engine?.send("config", ["ecuPath": ecuPath, "port": port, "iface": iface, "host": enetHost])
            configured = true
            lastError = nil
        } catch {
            configured = false
            lastError = error.localizedDescription
        }
    }

    func run<T>(_ label: String, stoppable: Bool = false, _ work: () async throws -> T) async -> T? {
        await live.stopAndWait()
        busy = true
        stopping = false
        self.stoppable = stoppable
        status = label
        percent = nil
        defer { busy = false; self.stoppable = false; percent = nil }
        do {
            let result = try await work()
            lastError = nil
            if stopping { await clearStop() }
            return result
        } catch {
            if stopping {
                await clearStop()
                lastError = nil
                status = "Stopped"
            } else {
                lastError = error.localizedDescription
                status = "Failed"
            }
            return nil
        }
    }

    /// Stop the scan or read in progress. Batches ("Read everything", "Clear all faults") stop
    /// before the next module; the engine stops after the EDIABAS job it's running.
    func stop() {
        guard busy, stoppable, !stopping else { return }
        stopping = true
        status = "Stopping…"
        engine?.interrupt()
    }

    /// The engine keeps its stop flag until told otherwise, so a Stop that lands between two
    /// requests still stops the next one; clear it once the operation has ended.
    private func clearStop() async {
        _ = try? await engine?.send("clearstop")
    }

    /// Quick scan (default once a full scan has found modules) checks only the addresses that
    /// answered before: seconds instead of a minute or more, because every empty address costs a
    /// K-line timeout. A full scan checks every address and updates the remembered list.
    func scan(full: Bool = false) async {
        guard let engine else { return }
        await configure()
        let known = knownGroups.split(separator: ",").map(String.init)
        let quick = !full && !known.isEmpty
        var params: [String: Any] = ["set": scanSet]
        if quick { params["groups"] = known }
        let found: [Module]? = await run(quick ? "Quick scan (\(known.count) known modules)…" : "Full scan of every address…", stoppable: true) {
            let data = try await engine.send("scan", params) as? [[String: Any]] ?? []
            return data.map {
                Module(group: $0["group"] as? String ?? "", sgbd: $0["sgbd"] as? String ?? "",
                       name: $0["name"] as? String ?? "", ident: $0["ident"] as? ResultSet ?? [:])
            }
        }
        guard let found else { return }
        if !quick && !stopping && !found.isEmpty { knownGroups = found.map(\.group).joined(separator: ",") }
        modules = found.sorted { $0.title < $1.title }
        if stopping {
            status = "Scan stopped: found \(found.count) modules so far"
        } else if found.isEmpty {
            status = "No modules answered. Check the ignition and the cable switch."
        } else if quick {
            status = "Found \(found.count) of \(known.count) known modules. Use Full scan (Scan menu) to look for others."
        } else {
            status = "Found \(found.count) modules"
        }
        if selection == nil { selection = modules.first }
    }

    /// `values: false` reads only ident, fault and info memory (what "Read all" needs), skipping
    /// the live-value STATUS jobs that make up most of the time
    func read(_ module: Module, values: Bool = true) async {
        guard let engine else { return }
        let report: ModuleReport? = await run("Reading \(module.title)…", stoppable: true) {
            let data = try await engine.send("read", ["sgbd": module.sgbd, "values": values]) as? [String: Any] ?? [:]
            return AppState.parse(data)
        }
        if let report {
            reports[module.sgbd] = report
            status = "Read \(module.title)"
            history.insert(HistoryStore.save(module, report), at: 0)
        }
    }

    // MARK: Coding (read-only)

    /// Coding jobs that only READ and take no arguments. Anything that writes coding
    /// (C_*_SCHREIBEN, *_AUFTRAG, SPEICHER_SCHREIBEN…) is deliberately not here.
    static let codingReadJobs = ["CODIERUNG_LESEN", "CODIERDATEN_LESEN", "CODIERUNG_BLOCK_1_LESEN", "C_CI_LESEN",
                                 "C_FG_LESEN", "FGNR_LESEN", "C_ZCS_LESEN", "ZCS_LESEN", "C_AZCS_LESEN", "C_FA_LESEN",
                                 "CODIERUNG_CHECK", "STATUS_CODIER_CHECKSUMME"]

    func readCoding(_ module: Module) async {
        guard let engine else { return }
        let sections: [CodingSection]? = await run("Reading coding: \(module.title)…", stoppable: true) {
            let jobs = try await engine.send("jobs", ["sgbd": module.sgbd]) as? [[String: Any]] ?? []
            let available = Set(jobs.filter { ($0["hasArgs"] as? Bool) == false }.compactMap { $0["job"] as? String })
            var out: [CodingSection] = []
            var seenTitles = Set<String>()
            for job in AppState.codingReadJobs where available.contains(job) {
                if stopping { break }
                var section = CodingSection(job: job)
                // C_ZCS_LESEN and ZCS_LESEN (etc.) give the same data; keep the first that answers
                if seenTitles.contains(section.title) && section.title != "Settings" { continue }
                do {
                    let data = try await engine.send("job", ["sgbd": module.sgbd, "job": job, "args": ""])
                    for set in AppState.jobSets(data) {
                        for key in set.keys.sorted() where AppState.isLiveResult(key) {
                            let v = AppState.string(set[key])
                            if !v.isEmpty { section.items.append((key, v)) }
                        }
                    }
                    if section.items.isEmpty { continue }
                } catch {
                    if stopping { break }
                    section.error = Engine.shortError(error.localizedDescription)
                }
                seenTitles.insert(section.title)
                out.append(section)
            }
            return out
        }
        if let sections {
            coding[module.sgbd] = sections
            status = stopping ? "Stopped" : "Read coding: \(module.title)"
        }
    }

    // MARK: Coding (decoded with NCS DATEN data)

    /// Decoded NCS coding map per SGBD: the codeable options, each with its name, byte and bit mask.
    @Published var ncsCoding: [String: [NCSDaten.Param]] = [:]
    /// Chosen coding index (.cNN) per SGBD, when several versions exist for a module.
    @Published var ncsIndex: [String: Int] = [:]
    /// Directly assigned fields (VIN, coding date, checksums…) of the decoded file, per SGBD.
    /// Their bytes are protected from coding writes.
    @Published var ncsDirect: [String: [NCSDaten.Direct]] = [:]

    private var swtCache: [String: [UInt16: String]] = [:]

    /// A name table from the DATEN folder — `kind` "fsw" (option names) or "psw" (value names),
    /// e.g. swtfsw01.dat — loaded and cached. Missing tables come back empty.
    private func swtNames(_ kind: String, _ index: Int) -> [UInt16: String] {
        let file = "swt\(kind)\(String(format: "%02d", index)).dat"
        if let c = swtCache[file] { return c }
        guard !datenPath.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: datenPath).appendingPathComponent(file)) else { return [:] }
        let m = NCSDaten.keywordMap([UInt8](data))
        if !m.isEmpty { swtCache[file] = m }
        return m
    }

    private var datenFilesCache: [String]?

    /// File names in the DATEN folder, listed once and cached.
    var datenFiles: [String] {
        if let c = datenFilesCache { return c }
        guard !datenPath.isEmpty else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: datenPath)) ?? []
        datenFilesCache = names
        return names
    }

    /// The name-table index of the chosen chassis folder (E46 = 06) — only when exactly one
    /// swtfswNN.dat is present. Several means mixed chassis folders, and nothing is decoded.
    var datenSwtIndex: Int? {
        let found = NCSDaten.swtIndexes(inFolder: datenFiles)
        return found.count == 1 ? found[0] : nil
    }

    /// Why the DATEN folder can't be used, if it can't (for the Setup warning).
    var datenProblem: String? {
        guard !datenPath.isEmpty else { return nil }
        let found = NCSDaten.swtIndexes(inFolder: datenFiles)
        if found.isEmpty { return "No name table (swtfswNN.dat) in that folder — the names can't be resolved. Pick the chassis folder that contains the .cXX files and its swtfsw/swtpsw tables." }
        if found.count > 1 {
            let list = found.map { String(format: "swtfsw%02d", $0) }.joined(separator: ", ")
            return "That folder mixes several chassis folders (\(list)), so option names could be wrong. Use one chassis folder only (for an E46: the one with swtfsw06)."
        }
        if datenSwtIndex.map({ swtNames("fsw", $0).isEmpty }) ?? true { return "The name table in that folder couldn't be read." }
        return nil
    }

    /// True once the DATEN folder has exactly one readable name table.
    var datenReady: Bool { !datenPath.isEmpty && datenProblem == nil }

    /// Clear cached DATEN data (after the folder changes).
    func clearNCSCache() { swtCache = [:]; datenFilesCache = nil; ncsCoding = [:]; ncsIndex = [:]; ncsDirect = [:] }

    /// Coding files available for a module in the DATEN folder, as (coding index, file URL), sorted.
    func ncsCodingFiles(for module: Module) -> [(index: Int, url: URL)] {
        guard !datenPath.isEmpty else { return [] }
        let dir = URL(fileURLWithPath: datenPath)
        var byIndex: [Int: URL] = [:]
        // Families in priority order; their coding indexes don't overlap, so the first one wins
        // any (unexpected) clash.
        for base in NCSDaten.codingBasenames(module.sgbd).reversed() {
            for name in datenFiles {
                guard let idx = NCSDaten.codingIndex(of: name, base: base) else { continue }
                // Prefer the plain `base.cNN` (hex) over duplicate-suffixed copies (e.g. base.cNN1).
                let clean = name.lowercased() == "\(base).c\(String(format: "%02x", idx))"
                if byIndex[idx] == nil || clean { byIndex[idx] = dir.appendingPathComponent(name) }
            }
        }
        return byIndex.keys.sorted().map { ($0, byIndex[$0]!) }
    }

    /// Parse a hex string ("00 05 08 FF" or "000508ff") into bytes.
    static func hexBytes(_ s: String) -> [UInt8]? {
        // Strict: only hex digits and separators, so text like "korrekt codiert" isn't read as bytes.
        guard s.allSatisfy({ $0.isHexDigit || $0 == " " || $0 == ":" || $0 == "-" }) else { return nil }
        let hex = Array(s.filter { $0.isHexDigit })
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        for i in stride(from: 0, to: hex.count, by: 2) {
            guard let b = UInt8(String(hex[i...i+1]), radix: 16) else { return nil }
            out.append(b)
        }
        return out
    }

    /// Read the car's raw coding bytes via an argument-free coding read job (e.g. CODIERDATEN_LESEN).
    /// Returns nil for modules that read coding with C_C_LESEN (needs a per-block buffer — car work).
    func rawCoding(_ module: Module) async throws -> [UInt8]? {
        // The E46 cluster keeps its coding in EEPROM, and NCS addresses it as plain byte offsets.
        if !NCSDaten.eepromFamilies.isDisjoint(with: NCSDaten.codingBasenames(module.sgbd)) {
            return try await eepromImage(module)
        }
        let jobs = try await engineSend("jobs", ["sgbd": module.sgbd]) as? [[String: Any]] ?? []
        let argless = Set(jobs.filter { ($0["hasArgs"] as? Bool) == false }.compactMap { $0["job"] as? String })
        // COD_LESEN returns the coding block pre-framed (COD_DATEN) on DSC/EWS/body — confirmed on
        // the car. CODIERDATEN_LESEN/CODIERUNG_LESEN are fallbacks for other modules.
        // COD_LESEN's BLOCK argument (body module) is optional and defaults to block 0.
        let available = Set(jobs.compactMap { $0["job"] as? String })
        for job in ["COD_LESEN", "CODIERDATEN_LESEN", "CODIERUNG_LESEN"]
        where argless.contains(job) || (job == "COD_LESEN" && available.contains(job)) {
            let data = try await engineSend("job", ["sgbd": module.sgbd, "job": job, "args": ""]) as? [ResultSet] ?? []
            for set in AppState.jobSets(data) {
                // COD_DATEN / CODIER_DATEN first; other DATEN/CODIER fields only as a fallback
                // (sorted so the choice doesn't depend on dictionary order).
                let keys = set.keys.sorted { a, b in
                    let pa = ["COD_DATEN", "CODIER_DATEN"].contains(a.uppercased()), pb = ["COD_DATEN", "CODIER_DATEN"].contains(b.uppercased())
                    return pa != pb ? pa : a < b
                }
                for k in keys {
                    let key = k.uppercased()
                    guard key.contains("CODIER") || key.contains("DATEN") || key == "CODE" else { continue }
                    if let bytes = AppState.hexBytes(AppState.string(set[k])), bytes.count > 1 { return bytes }
                }
                // Some modules (the E46 DSC MK60) return no data field, only the raw KWP2000
                // telegram `B8 F1 <addr> <len> 62 <id hi> <id lo> <coding…> <checksum>`.
                if let tel = AppState.hexBytes(AppState.string(set["_TEL_ANTWORT"])), tel.count > 7, tel[0] == 0xB8,
                   tel.count >= 4 + Int(tel[3]), tel[4] == 0x62, tel[3] > 3 {
                    return Array(tel[7..<(4 + Int(tel[3]))])
                }
            }
        }
        return nil
    }

    /// Read one numbered coding block with COD_LESEN BLOCK=n (the body module has blocks 0 and 1).
    func codingBlock(_ module: Module, _ n: Int) async throws -> [UInt8]? {
        let data = try await engineSend("job", ["sgbd": module.sgbd, "job": "COD_LESEN", "args": "\(n)"]) as? [ResultSet] ?? []
        guard let set = AppState.jobSets(data).first, AppState.string(set["JOB_STATUS"]) == "OKAY" else { return nil }
        return AppState.hexBytes(AppState.string(set["COD_DATEN"]))
    }

    /// Read a module's whole EEPROM with the read-only EEPROM_LESEN job (word address, at most 16
    /// words = 32 bytes per request). The E46 cluster has 0x200 words; reading stops at the first
    /// request the module rejects, returning what came back before it.
    private func eepromImage(_ module: Module, words: Int = 0x200) async throws -> [UInt8]? {
        var out: [UInt8] = []
        for w in stride(from: 0, to: words, by: 16) {
            let data = try await engineSend("job", ["sgbd": module.sgbd, "job": "EEPROM_LESEN",
                                                    "args": String(format: "0x%04X;16", w)]) as? [ResultSet] ?? []
            guard let set = AppState.jobSets(data).first, AppState.string(set["JOB_STATUS"]) == "OKAY",
                  let bytes = AppState.hexBytes(AppState.string(set["DATEN"])), bytes.count == 32 else { break }
            out += bytes
        }
        return out.isEmpty ? nil : out
    }

    /// When the car's coding index matches no DATEN file, pick the version whose options land on
    /// programmed bytes of the car's coding rather than erased 0xFF. On the E46 cluster the right
    /// layout scores ~90% and the others under 40%.
    func bestFitIndex(_ module: Module, raw: [UInt8]) -> Int? {
        var best: (index: Int, score: Double)?
        for f in ncsCodingFiles(for: module) {
            guard let cx = try? Data(contentsOf: f.url) else { continue }
            let params = NCSDaten.decode([UInt8](cx), fsw: [:])
            guard !params.isEmpty else { continue }
            let hits = params.filter { $0.byteAddress < raw.count && raw[$0.byteAddress] != 0xFF }.count
            let score = Double(hits) / Double(params.count)
            if best == nil || score > best!.score { best = (f.index, score) }
        }
        return best?.index
    }

    /// The module's coding index as reported by the car (ID_COD_INDEX from its last read), if any.
    /// This is what NCS matches against each coding file's declared SGID_CODIERINDEX.
    func codingIndexFromCar(_ module: Module) -> Int? {
        guard let s = reports[module.sgbd]?.ident.first(where: { $0.0 == "ID_COD_INDEX" })?.1 else { return nil }
        // Reported as hex digits: the cluster's "23" is 0x23, matching kmbe46m3.c23 (index 35).
        return Int(s.trimmingCharacters(in: .whitespaces), radix: 16)
    }

    /// Non-nil when the car's coding index has no matching DATEN file — the decode fell back to
    /// another index and the options may be wrong. Carries the car's index, the one used, and the
    /// indexes available, for a warning. (All shown in hex, matching the .cNN filenames.)
    func ncsIndexMismatch(_ module: Module) -> (car: Int, used: Int, have: [Int])? {
        guard let ci = codingIndexFromCar(module) else { return nil }
        let files = ncsCodingFiles(for: module)
        guard !files.isEmpty, !files.contains(where: { $0.index == ci }), let used = ncsIndex[module.sgbd]
        else { return nil }
        return (ci, used, files.map(\.index))
    }

    /// Decode a module's coding into named options using the DATEN folder. `index` picks the `.cNN`
    /// file explicitly; otherwise a remembered choice, then the car's reported coding index
    /// (ID_COD_INDEX), then the lowest index available. Falls back to lowest if the wanted index
    /// has no file (e.g. the DATEN set is missing that variant).
    func decodeNCSCoding(_ module: Module, index: Int? = nil) {
        let files = ncsCodingFiles(for: module)
        guard let first = files.first else { ncsCoding[module.sgbd] = []; return }
        let wanted = index ?? ncsIndex[module.sgbd] ?? codingIndexFromCar(module) ?? first.index
        let file = files.first { $0.index == wanted } ?? first
        ncsIndex[module.sgbd] = file.index
        guard let cx = try? Data(contentsOf: file.url) else { ncsCoding[module.sgbd] = []; return }
        let swt = datenSwtIndex ?? 0
        let fsw = swtNames("fsw", swt)
        ncsCoding[module.sgbd] = NCSDaten.decode([UInt8](cx), fsw: fsw, psw: swtNames("psw", swt))
        ncsDirect[module.sgbd] = NCSDaten.directFields([UInt8](cx), fsw: fsw)
    }

    /// VINs found in coding reads so far, by module title (for the mismatch check)
    var codingVINs: [(module: String, vin: String)] {
        modules.compactMap { m in
            guard let vin = coding[m.sgbd]?.flatMap(\.items).first(where: { $0.key == "FG_NR" })?.value else { return nil }
            return (m.title, vin)
        }
    }

    // MARK: Actions that change the car

    func ask(_ title: String, _ message: String, confirm: String, run: @escaping () async -> Void) {
        pending = PendingAction(title: title, message: message, confirm: confirm, run: run)
    }

    /// Ask the person at the car to approve something Claude wants to do; false if they cancel
    func approve(_ title: String, _ message: String, confirm: String) async -> Bool {
        guard pending == nil else { return false }
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSSound.beep()
        return await withCheckedContinuation { cont in
            pending = PendingAction(title: title, message: message, confirm: confirm,
                                    run: { cont.resume(returning: true) },
                                    cancel: { cont.resume(returning: false) })
        }
    }

    // MARK: MCP server for Claude

    var mcpURL: String { "http://127.0.0.1:\(MCPServer.defaultPort)/mcp" }
    var mcpAddCommand: String {
        "claude mcp add --transport http opends2 \(mcpURL) --header \"Authorization: Bearer \(mcpToken)\""
    }

    func startMCP() {
        if mcpToken.isEmpty { mcpToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
        mcp?.stop()
        let server = MCPServer(state: self, port: MCPServer.defaultPort, token: mcpToken)
        do {
            try server.start()
            mcp = server
            mcpRunning = true
            mcpError = nil
        } catch {
            mcpRunning = false
            mcpError = error.localizedDescription
        }
    }

    func stopMCP() {
        mcp?.stop()
        mcp = nil
        mcpRunning = false
    }

    /// Raw engine access for the MCP server (requests are serialized by the engine either way)
    func engineSend(_ command: String, _ params: [String: Any] = [:]) async throws -> Any? {
        guard let engine else { throw Engine.EngineError.failed(lastError ?? "Diagnostic engine not running") }
        return try await engine.send(command, params)
    }

    func note(_ title: String, ok: Bool = true, _ detail: String = "") {
        log.insert(LogLine(title: title, ok: ok, detail: detail), at: 0)
    }

    /// Run one job and log its outcome. Returns the job's result sets (without the system set) or nil.
    @discardableResult
    func perform(_ title: String, sgbd: String, job: String, args: String = "") async -> [ResultSet]? {
        guard let engine else { return nil }
        let sets: [ResultSet]? = await run(title + "…") {
            let data = try await engine.send("job", ["sgbd": sgbd, "job": job, "args": args]) as? [ResultSet] ?? []
            return AppState.jobSets(data)
        }
        if let sets {
            let status = sets.compactMap { $0["JOB_STATUS"] as? String }.first ?? ""
            let ok = status.isEmpty || status == "OKAY"
            let detail = sets.flatMap { set in
                set.keys.sorted().filter { $0 != "JOB_STATUS" }.map { "\($0) = \(AppState.string(set[$0]))" }
            }.joined(separator: "\n")
            log.insert(LogLine(title: title, ok: ok, detail: [status, detail].filter { !$0.isEmpty }.joined(separator: "\n")), at: 0)
            self.status = ok ? "\(title): done" : "\(title): \(status)"
        } else {
            log.insert(LogLine(title: title, ok: false, detail: lastError ?? "Failed"), at: 0)
        }
        return sets
    }

    /// Make sure there is a saved read of the module from just before a change
    /// Read and save the module before changing it; false if that read was stopped, so the change is skipped
    private func readBeforeChange(_ module: Module) async -> Bool {
        await read(module, values: false)
        if stopping { status = "Stopped: nothing was changed" }
        return !stopping
    }

    func clearFaults(_ module: Module) {
        ask("Clear fault memory: \(module.title)?",
            "The module is read and saved to History first, so the faults aren't lost. Faults that are still present will come back.",
            confirm: "Clear faults") { [self] in
            guard await readBeforeChange(module) else { return }
            if await perform("Clear faults: \(module.title)", sgbd: module.sgbd, job: "FS_LOESCHEN") != nil {
                await read(module)
            }
        }
    }

    func clearAllFaults() {
        ask("Clear fault memory in every module?",
            "Scans the car, reads and saves every module (History, plus a report on the Desktop), clears each module's faults, then reads them all again.",
            confirm: "Clear all") { [self] in
            guard await readEverything() != nil, !stopping else { status = "Stopped: nothing was cleared"; return }
            for module in modules {
                if stopping { status = "Stopped"; return }
                if await perform("Clear faults: \(module.title)", sgbd: module.sgbd, job: "FS_LOESCHEN") != nil {
                    await read(module, values: false)
                }
            }
            status = "Cleared faults in \(modules.count) modules"
        }
    }

    func resetAdaptations(_ module: Module) {
        ask("Reset all engine adaptations?",
            "Clears the engine computer's learned values (fuel trims, idle, throttle). Do this after replacing parts such as oxygen sensors, the idle valve or throttle parts, not as a routine fix. Afterwards, let the engine idle until warm, then drive normally so it relearns; idle can be uneven at first.",
            confirm: "Reset adaptations") { [self] in
            guard await readBeforeChange(module) else { return }
            await perform("Reset adaptations", sgbd: module.sgbd, job: "ADAPT_LOESCHEN")
        }
    }

    enum ServiceReset: String, CaseIterable, Identifiable {
        case oil = "Oel_Reset", distance = "Weg_Reset", time = "Zeit_Reset"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .oil: "Oil service"
            case .distance: "Inspection (distance)"
            case .time: "Inspection (time)"
            }
        }
    }

    func serviceReset(_ module: Module, _ kind: ServiceReset) {
        ask("Reset \(kind.label.lowercased()) reminder?",
            "Resets the service indicator in the instrument cluster. Ignition on (position 2), engine off.",
            confirm: "Reset") { [self] in
            await perform("Service reset: \(kind.label)", sgbd: module.sgbd, job: "SIA_RESET", args: kind.rawValue)
        }
    }

    // MARK: Brake bleeding (DSC MK60)

    /// BMW's bleeding routines in dsc_mk60.prg. Run through the engine in an EDIABAS simulation,
    /// each one: starts a diagnostic session, holds the inlet valves of two wheels shut, then 10×
    /// [pump on, open the other two wheels' outlet valves, close, pump to those wheels], 20 pulses,
    /// a 2 s flush with the separating/changeover valves, then everything off. The routine name
    /// is the side held shut; the opposite wheels are the ones cycled.
    enum BleedRoutine: String, CaseIterable, Identifiable {
        case rear = "R50_ASC_DSC_BLEEDMASTER_FA"
        case front = "R50_ASC_DSC_BLEEDMASTER_RA"
        case left = "NA_ENTLUEFTUNG_RE"
        case right = "NA_ENTLUEFTUNG_LI"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .rear: "Rear wheels"
            case .front: "Front wheels"
            case .left: "Left side"
            case .right: "Right side"
            }
        }
        var wheels: String {
            switch self {
            case .rear: "both REAR wheels"
            case .front: "both FRONT wheels"
            case .left: "both LEFT wheels (front and rear)"
            case .right: "both RIGHT wheels (front and rear)"
            }
        }
        var held: String {
            switch self {
            case .rear: "front"
            case .front: "rear"
            case .left: "right-side"
            case .right: "left-side"
            }
        }
        var detail: String { "Holds the \(held) wheels shut and cycles the pump and valves through \(wheels)." }
    }

    @Published var lastBleedAt: Date?
    static let bleedCooldown: TimeInterval = 60
    var bleedCoolingDown: Bool { lastBleedAt.map { Date().timeIntervalSince($0) < AppState.bleedCooldown } ?? false }

    func runBleed(_ routine: BleedRoutine, on module: Module) {
        ask("Bleed: \(routine.title.lowercased())?",
            """
            Before you start:
            • Car stationary, engine OFF, ignition ON (position 2).
            • Brake fluid reservoir full. Use a pressure bleeder at about 2 bar, or have a helper keep the reservoir topped up. Never let it run low.
            • Bleed screws OPEN on \(routine.wheels), with hoses into a catch bottle.

            What happens: \(routine.detail) It takes about 10–15 seconds and you'll hear the pump. Then close the bleed screws.

            Repeat until no more bubbles come out, then bleed all four wheels the normal way again. The DSC may store faults during this; clear them afterwards. Check the pedal is firm before driving.
            """,
            confirm: "Start bleeding") { [self] in
            guard !bleedCoolingDown else { status = "Let the pump cool: wait a minute between runs"; return }
            // Interlock: only with the car standing still
            guard let sets = await perform("Bleed check: wheel speeds", sgbd: module.sgbd, job: "STATUS_RADGESCHWINDIGKEIT"),
                  let speeds = sets.first.map({ set in ["VL", "VR", "HL", "HR"].compactMap { Double(AppState.string(set["STAT_RAD_GESCHW_\($0)_WERT"])) } }),
                  speeds.count == 4 else {
                status = "Didn't start: couldn't read the wheel speeds from the DSC"
                return
            }
            guard speeds.allSatisfy({ abs($0) < 1 }) else {
                status = "Didn't start: the car is moving (wheel speeds \(speeds.map { String(Int($0)) }.joined(separator: "/")) km/h)"
                return
            }
            lastBleedAt = Date()
            await perform("Bleed: \(routine.title.lowercased())", sgbd: module.sgbd, job: routine.rawValue)
            lastBleedAt = Date()   // cool-down counts from the end of the run
        }
    }

    // MARK: DSC / steering calibration

    /// Self-calibration service routines. Each one makes the module measure its own sensors and
    /// store its own offsets (no arbitrary data is written), the same category as brake bleeding.
    /// MCP clients can run these with run_job too (the engine allows them); explain the conditions first.
    enum CalibrationRoutine: String, CaseIterable, Identifiable {
        case steeringAngle = "LENKWINKEL_DSC_ABGLEICHEN"
        case lateralAccel = "QUERBESCHLEUNIGUNG_DSC_ABGLEICHEN"
        case pressure = "DRUCKSENSOR_DSC_ABGLEICHEN"
        case steeringSensor = "ABGLEICH_SCHREIBEN"   // lws5_1b
        var id: String { rawValue }
        var sgbd: String { self == .steeringSensor ? "lws5_1b" : "dsc_mk60" }
        /// The read-only job that shows the stored offsets before/after.
        var offsetJob: String { self == .steeringSensor ? "ABGLEICH_LESEN" : "STATUS_SENSOREN_OFFSET" }
        var title: String {
            switch self {
            case .steeringAngle: "Steering angle (DSC)"
            case .lateralAccel: "Lateral-acceleration sensor (DSC)"
            case .pressure: "Brake-pressure sensor (DSC)"
            case .steeringSensor: "Steering-angle sensor zero (LWS)"
            }
        }
        var preconditions: String {
            switch self {
            case .steeringAngle, .steeringSensor:
                """
                Before you start:
                • Car stationary on level ground, ignition ON (engine may be running or off).
                • Front wheels pointed DEAD STRAIGHT ahead (steering wheel centered).

                The module learns the current steering position as zero. Do a short test drive afterwards and recheck for faults.
                """
            case .lateralAccel:
                """
                Before you start:
                • Car stationary on LEVEL ground, ignition ON, engine off.
                • Do not rock or load the car during the routine.

                The DSC learns the lateral-acceleration sensor's zero point.
                """
            case .pressure:
                """
                Before you start:
                • Car stationary, ignition ON, engine off.
                • Brake pedal fully RELEASED (no foot on the pedal).

                The DSC learns the brake-pressure sensor's zero point.
                """
            }
        }
    }

    @Published var lastCalibrationAt: Date?
    var calibrationCoolingDown: Bool { lastCalibrationAt.map { Date().timeIntervalSince($0) < AppState.bleedCooldown } ?? false }

    /// Are all four wheels standing still, per the DSC? nil if we couldn't read them.
    private func wheelsStationary() async -> Bool? {
        guard let dsc = modules.first(where: { $0.sgbd.lowercased() == "dsc_mk60" }),
              let sets = await perform("Calibration check: wheel speeds", sgbd: dsc.sgbd, job: "STATUS_RADGESCHWINDIGKEIT"),
              let speeds = sets.first.map({ set in ["VL", "VR", "HL", "HR"].compactMap { Double(AppState.string(set["STAT_RAD_GESCHW_\($0)_WERT"])) } }),
              speeds.count == 4 else { return nil }
        return speeds.allSatisfy { abs($0) < 1 }
    }

    func runCalibration(_ routine: CalibrationRoutine) {
        ask("Calibrate: \(routine.title.lowercased())?",
            routine.preconditions,
            confirm: "Start calibration") { [self] in
            guard !calibrationCoolingDown else { status = "Wait a moment between calibrations"; return }
            // Interlock: only with the car standing still (read from the DSC, which has wheel speeds).
            if let stationary = await wheelsStationary() {
                guard stationary else { status = "Didn't start: the car is moving"; return }
            }
            await perform("Offsets before: \(routine.title)", sgbd: routine.sgbd, job: routine.offsetJob)
            lastCalibrationAt = Date()
            await perform("Calibrate: \(routine.title)", sgbd: routine.sgbd, job: routine.rawValue)
            lastCalibrationAt = Date()
            await perform("Offsets after: \(routine.title)", sgbd: routine.sgbd, job: routine.offsetJob)
        }
    }

    var testCoolingDown: Bool { lastTestAt.map { Date().timeIntervalSince($0) < AppState.testCooldown } ?? false }

    func runTest(_ test: ComponentTest, on module: Module) {
        ask("Run test: \(test.title)?", test.conditions, confirm: "Run test") { [self] in
            guard !testCoolingDown else { status = "Wait a few seconds between tests"; return }
            lastTestAt = Date()
            await perform(test.title, sgbd: module.sgbd, job: test.job, args: test.args)
        }
    }

    /// Scan, read every module, and save one report file to the Desktop
    func readEverything() async -> URL? {
        await scan()
        if stopping { return nil }
        return await readAll()
    }

    /// Read every module already found (no rescan), then save one report file to the Desktop
    func readAll() async -> URL? {
        var done = 0
        for module in modules {
            await read(module, values: false)
            if stopping { break }
            done += 1
        }
        guard done > 0 else { return nil }
        let url = saveReport()
        status = stopping ? "Stopped after \(done) of \(modules.count) modules (report saved)"
                          : "Read all \(done) modules\(url == nil ? "" : " (report saved to the Desktop)")"
        return url
    }

    func saveReport() -> URL? {
        var doc: [String: Any] = ["generated": ISO8601DateFormatter().string(from: Date()), "port": port]
        doc["modules"] = modules.map { m -> [String: Any] in
            ["group": m.group, "sgbd": m.sgbd, "name": m.title, "ident": m.ident, "data": reports[m.sgbd]?.raw ?? [:]]
        }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/OpenDS2 report \(stamp).json")
        guard let json = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        do {
            try json.write(to: url)
            status = "Saved \(url.lastPathComponent) to the Desktop"
            return url
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: Parsing EDIABAS results

    /// Result set 0 holds EDIABAS system values (VARIANTE, JOBNAME…); job results start at 1
    static func jobSets(_ any: Any?) -> [ResultSet] {
        guard let sets = any as? [ResultSet], sets.count > 1 else { return [] }
        return Array(sets.dropFirst())
    }

    static func string(_ v: Any?) -> String {
        switch v {
        case let s as String: return s.trimmingCharacters(in: .whitespaces)
        case let d as Double: return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(format: "%.3g", d)
        case let n as NSNumber: return n.stringValue
        case nil: return ""
        default: return "\(v!)"
        }
    }

    static func faults(_ any: Any?) -> [Fault] {
        jobSets(any).compactMap { set in
            guard let code = set["F_ORT_NR"] ?? set["F_CODE"] else { return nil }
            let german = string(set["F_ORT_TEXT"] ?? set["F_TEXT"])
            let skip: Set<String> = ["F_ORT_NR", "F_ORT_TEXT", "F_CODE", "F_TEXT", "JOB_STATUS"]
            var details: [(String, String)] = []
            var conditions: [(String, String)] = []
            for key in set.keys.sorted() where !skip.contains(key) {
                let raw = string(set[key])
                guard !raw.isEmpty else { continue }
                let value = key.hasSuffix("_TEXT") ? Translate.english(raw) : raw
                let row = (Translate.label(key), value)
                if Translate.isCondition(key) { conditions.append(row) } else { details.append(row) }
            }
            let english = Translate.english(german)
            return Fault(code: string(code), text: german.isEmpty ? "Unknown fault" : english,
                         details: details, conditions: conditions,
                         original: english == german ? "" : german, note: Translate.note(for: german))
        }
    }

    /// Status-job results worth showing: not units, raw telegrams or the job status
    static func isLiveResult(_ key: String) -> Bool {
        !key.hasSuffix("_EINH") && !key.hasPrefix("_") && key != "JOB_STATUS"
            && !["VARIANTE", "OBJECT", "SAETZE", "JOBNAME", "GRUPPE", "FAMILIE", "JOBSTATUS", "ANTWORT", "TELEGRAMM", "TELEGRAMM2"].contains(key)
            && !key.hasPrefix("UBATT") && !key.hasPrefix("IGNITION")
    }

    static func parse(_ data: [String: Any]) -> ModuleReport {
        var report = ModuleReport(raw: data)
        // Prefer FS_LESEN_DETAIL (carries the freeze-frame conditions); fall back to FS_LESEN.
        let detail = data["FS_LESEN_DETAIL"]
        report.faults = jobSets(detail).isEmpty ? faults(data["FS_LESEN"]) : faults(detail)
        report.infoMemory = faults(data["IS_LESEN"])
        if let set = jobSets(data["IDENT"]).first {
            report.ident = set.keys.sorted().filter { $0 != "JOB_STATUS" }.map { ($0, string(set[$0])) }
        }
        for (job, value) in (data["STATUS"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
            if let err = (value as? [String: Any])?["error"] as? String {
                report.errors.append("\(job): \(Engine.shortError(err))")
                continue
            }
            for set in jobSets(value) {
                // Values come as STAT_<name>_WERT with the unit in STAT_<name>_EINH (or plain STAT_<name>, or
                // _TEXT); a few SGBDs (DSC MK60 flat-tyre data, MSS54 leak test) use names without STAT_.
                for key in set.keys.sorted() where Self.isLiveResult(key) {
                    let base = key.hasSuffix("_WERT") ? String(key.dropLast(5)) : key
                    report.live.append(LiveValue(job: job, name: base.replacingOccurrences(of: "STAT_", with: ""),
                                                 value: string(set[key]), unit: Translate.unit(string(set[base + "_EINH"])),
                                                 key: key))
                }
            }
        }
        return report
    }
}
