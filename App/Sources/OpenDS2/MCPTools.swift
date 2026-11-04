import AppKit
import Foundation

/// The tools the in-app MCP server offers, and their implementations on top of AppState.
@MainActor
enum MCPTools {
    static let instructions = """
    Diagnostics for a BMW E-series car through the OpenDS2 app on the user's Mac, over a K+DCAN cable (K-line, DS2). \
    Modules are addressed by SGBD name (e.g. mss54ds0 = S54 engine computer of an E46 M3, kombi46r = E46 instrument cluster; names differ by chassis and engine).

    Workflow: list_modules (or scan_modules if none) → read_module on the relevant modules → read_live for values \
    while the engine runs → get_history / compare_history to see what changed since earlier reads. \
    Fault texts are translated to English; the module's German original is included. Notes are general pointers, not a diagnosis. \
    Live readings are converted to the unit system the user picked in Setup (metric or imperial — °C/°F, km·h/mph, km/mi, bar/psi, l/gal); the unit beside each value says which.

    Useful MSS54 live jobs: STATUS_MOTORDREHZAHL (rpm), STATUS_MOTORTEMPERATUR (coolant), STATUS_OEL_TEMPERATUR, \
    STATUS_UBATT, STATUS_AN_LUFTTEMPERATUR, STATUS_DKP_WINKEL (throttle), STATUS_LAST, STATUS_LAMBDA_INTEGRATOR_1/_2, \
    STATUS_ADD/_ADD_2 and STATUS_MUL/_MUL_2 (fuel trims per bank), STATUS_SYSTEMCHECK_LAUFUNRUHE (roughness per cylinder, \
    physical cylinder order 1-6, not firing order), VANOS target/actual: STATUS_EVANOS1_SOLL/_IST, STATUS_EVANOS2_SOLL/_IST \
    (intake), STATUS_AVANOS1_SOLL + STATUS_VANOS_NW_LAGE_EINLASS_BANK_1 and STATUS_AVANOS2_SOLL + \
    STATUS_VANOS_NW_LAGE_EINLASS_BANK_2 (exhaust target + actual; despite the name, the job comments say exhaust actual). \
    list_jobs shows every job a module supports.

    Coding: read_coding reads a module's coding from the car and decodes it to named options with current values \
    (on/off for flags), using the user's NCS data folder. decode_coding does the same from the data alone and can \
    overlay raw bytes you read yourself. Each option carries an English `label`, the German FSW keyword as `name` \
    (use it to cross-reference NCS Expert), and, for known enumerations, a `meaning` for the value. \
    To CHANGE an option, call request_coding_change with the option's `name` and the new value: the app re-reads \
    the module, checks the change, saves a backup and shows the user the exact byte diff. Nothing is written \
    until the user approves it at the car; the tool waits and returns the result. Only modules whose write \
    format is verified can be changed (currently the E46 body module and the DSC MK60).

    Access: run_job runs any job directly — reads, clearing faults (FS_LOESCHEN reads the faults first so \
    they're kept), adaptation and service resets, STEUERN_* actuator tests and system checks. Say what you're \
    about to do and the conditions it needs (engine off/idling, warm, stationary) before you run anything that \
    changes the car. Coding jobs are not run directly: use request_coding_change. The engine always refuses \
    programming/flashing, odometer, immobilizer alignment, module reboots, raw output control and raw \
    memory/coding writes, for every client including the app itself.
    """

    static let definitions: [[String: Any]] = [
        tool("list_modules", "Modules found by the last scan, with how many faults each had when last read.", [:], []),
        tool("scan_modules", "Scan the car for every module that answers (takes a minute). Ignition must be on.", [:], []),
        tool("read_module", "Read one module: identification, fault memory (with English text and notes), info memory and every no-argument STATUS value. Saves the read to history.",
             ["sgbd": ["type": "string", "description": "Module SGBD name, e.g. mss54ds0"]], ["sgbd"]),
        tool("read_live", "Read live values from one module, optionally several times, and report latest/min/max/average for each result.",
             ["sgbd": ["type": "string"],
              "jobs": ["type": "array", "items": ["type": "string"], "description": "STATUS_… job names"],
              "samples": ["type": "integer", "minimum": 1, "maximum": 30, "description": "How many reads (default 1). Each round takes a fraction of a second per job."]],
             ["sgbd", "jobs"]),
        tool("list_jobs", "List the jobs a module supports, with their (German) comments, whether they take arguments, and whether they are read-only. Works without the car.",
             ["sgbd": ["type": "string"], "filter": ["type": "string", "description": "Only jobs whose name or comment contains this text"]], ["sgbd"]),
        tool("run_job", "Run one job directly and return its result sets: reads (STATUS_*, *_LESEN*, IDENT, _JOBS/_TABLE metadata) and actions (FS_LOESCHEN, ADAPT_LOESCHEN, SIA_RESET, STEUERN_* tests, START_/STOP_SYSTEMCHECK_*…). Coding changes go through request_coding_change instead. The engine refuses programming, odometer, immobilizer alignment and raw writes.",
             ["sgbd": ["type": "string"], "job": ["type": "string"], "args": ["type": "string", "description": "Semicolon-separated arguments, if the job takes any"],
              "binary": ["type": "string", "description": "Binary argument as hex, for jobs with a binary ARG (e.g. C_C_LESEN's BINAER_BUFFER)"]],
             ["sgbd", "job"]),
        tool("request_coding_change", "Ask the user to approve changing ONE coding option. The app re-reads the module, checks the change (verified module, exact coding-data match, engine off, battery ≥ 12 V), saves a backup and shows the byte diff; it writes only after the user clicks, then reads back. Waits for the decision and returns the result.",
             ["sgbd": ["type": "string"],
              "option": ["type": "string", "description": "The option's `name` (German FSW keyword) from read_coding"],
              "value": ["type": "string", "description": "New value: its name from read_coding's choices (e.g. aktiv / nicht_aktiv), or the raw number"],
              "reason": ["type": "string", "description": "Shown to the user: what this changes and why"]],
             ["sgbd", "option", "value", "reason"]),
        tool("read_coding", "Read a module's coding from the car and decode it into named options with their current values, using the NCS coding data (set in Setup → Coding data). Read-only. Each option has an English `label`, the German FSW keyword as `name`, a `value`, and `state` (on/off) for flags or a `meaning` for known enumerations. Some modules read coding with C_C_LESEN (a per-block buffer) which isn't wired yet; those return the option map without live values.",
             ["sgbd": ["type": "string"]], ["sgbd"]),
        tool("decode_coding", "Decode a module's coding into named options from the NCS data without touching the car. Optionally overlay raw coding bytes (hex, e.g. from run_job CODIERDATEN_LESEN) to get current values, and pick the coding version by index.",
             ["sgbd": ["type": "string"],
              "raw": ["type": "string", "description": "Raw coding bytes as hex, optional"],
              "index": ["type": "integer", "description": "Coding index (.cNN) to use, optional"]], ["sgbd"]),
        tool("get_history", "Earlier saved reads (newest first), with fault lists. Use the ids with compare_history.",
             ["sgbd": ["type": "string", "description": "Only this module"], "limit": ["type": "integer", "minimum": 1, "maximum": 50]], []),
        tool("compare_history", "Compare two saved reads of the same module: new faults, gone faults, still present, changed values.",
             ["before": ["type": "string"], "after": ["type": "string"]], ["before", "after"]),
    ]

    private static func tool(_ name: String, _ description: String, _ props: [String: Any], _ required: [String]) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": props, "required": required, "additionalProperties": false]]
    }

    /// The only jobs a binary buffer may be passed to, as "sgbd/JOB". Disassembled: both send only
    /// read telegrams and the buffer sets just the address and length. The engine enforces the same
    /// list (Program.cs BinaryArgJobs); keep them in step.
    static let binaryArgJobs: Set<String> = ["zke5/C_C_LESEN", "kombi46r/C_S_LESEN"]

    /// Jobs that only read, and so run without asking. Name-based, so anything whose name also says
    /// it writes, clears, resets or drives an output is excluded even if it contains LESEN.
    static func isReadOnly(_ job: String) -> Bool {
        let j = job.uppercased()
        if ["SCHREIBEN", "LOESCHEN", "AUFTRAG", "RESET", "STEUERN"].contains(where: j.contains) { return false }
        // C_CHECKSUM writes; STATUS_CODIER_CHECKSUMME only reports the checksum state.
        if j.contains("CHECKSUM") && !j.hasPrefix("STATUS_") && !j.hasSuffix("_LESEN") { return false }
        if j.hasPrefix("_") || ["IDENT", "INFO"].contains(j) || j.hasPrefix("STATUS_") { return true }
        return j.contains("LESEN")
    }

    /// Coding jobs an AI client may not run directly: they go through request_coding_change, which
    /// builds the change itself and puts it in front of the user. Everything else is left to the
    /// engine's own refusal list (Program.cs DeniedReason), which applies to every client.
    static func codingJobReason(_ job: String) -> String? {
        let j = job.uppercased()
        if isReadOnly(j) { return nil }
        if j.hasPrefix("C_") || j.contains("AUFTRAG") || (j.contains("COD") && j.contains("SCHREIBEN")) {
            return "\(j) changes coding. Use request_coding_change: the user approves each coding change at the car."
        }
        return nil
    }

    static func call(_ name: String, _ args: [String: Any], state: AppState) async -> (String, Bool) {
        let sgbd = (args["sgbd"] as? String)?.lowercased() ?? ""
        state.note("Claude: \(name)\(sgbd.isEmpty ? "" : " " + sgbd)")
        do {
            let result: Any
            switch name {
            case "list_modules":
                let modules: [[String: Any]] = state.modules.map(moduleJSON(state))
                var out: [String: Any] = ["modules": modules]
                if modules.isEmpty { out["hint"] = "No scan yet: call scan_modules." }
                result = out
            case "scan_modules":
                guard state.configured else { throw ToolError("The app isn't set up yet: choose the ECU folder in Setup.") }
                await state.scan()
                if let e = state.lastError, state.modules.isEmpty { throw ToolError(e) }
                result = ["modules": state.modules.map(moduleJSON(state)), "status": state.status]
            case "read_module":
                let module = state.modules.first { $0.sgbd == sgbd } ?? Module(group: "", sgbd: sgbd, name: "", ident: [:])
                await state.read(module)
                guard let report = state.reports[sgbd] else { throw ToolError(state.lastError ?? "Read failed") }
                result = reportJSON(module, report)
            case "read_live":
                let jobs = (args["jobs"] as? [String] ?? []).map { $0.uppercased() }
                guard !jobs.isEmpty else { throw ToolError("jobs is empty") }
                if let bad = jobs.first(where: { !isReadOnly($0) }) { throw ToolError("\(bad) is not a read-only job") }
                let samples = min(max(args["samples"] as? Int ?? 1, 1), 30)
                result = try await live(state, sgbd, jobs, samples)
            case "list_jobs":
                let filter = (args["filter"] as? String ?? "").lowercased()
                let jobs = try await state.engineSend("jobs", ["sgbd": sgbd]) as? [[String: Any]] ?? []
                result = jobs.filter { j in
                    filter.isEmpty || "\(j["job"] ?? "") \(j["comment"] ?? "")".lowercased().contains(filter)
                }.map { j -> [String: Any] in
                    var j = j
                    let job = j["job"] as? String ?? ""
                    j["readOnly"] = isReadOnly(job)
                    if codingJobReason(job) != nil { j["blocked"] = "use request_coding_change" }
                    return j
                }
            case "run_job":
                result = try await runJob(state, sgbd, (args["job"] as? String ?? "").uppercased(),
                                          args["args"] as? String ?? "", args["binary"] as? String)
            case "request_coding_change":
                result = try await requestCodingChange(state, sgbd, args["option"] as? String ?? "",
                                                       "\(args["value"] ?? "")", args["reason"] as? String ?? "")
            case "read_coding":
                guard state.datenReady else { throw ToolError("No coding data: set the DATEN folder in Setup → Coding data.") }
                let module = state.modules.first { $0.sgbd == sgbd } ?? Module(group: "", sgbd: sgbd, name: "", ident: [:])
                guard !state.ncsCodingFiles(for: module).isEmpty else { throw ToolError("No coding file for \(sgbd) in the DATEN folder.") }
                // Make sure we know the module's coding index (ID_COD_INDEX) so decode picks the
                // right .cNN variant; a values-free read fetches the ident quickly if we don't.
                if state.codingIndexFromCar(module) == nil { await state.read(module, values: false) }
                state.decodeNCSCoding(module)
                var params = state.ncsCoding[sgbd] ?? []
                var note: String?
                var raw: [UInt8]?
                do { raw = try await state.rawCoding(module) } catch { note = "Couldn't read raw coding: \(Engine.shortError(error.localizedDescription))" }
                // No file for the car's coding index: choose the version that fits the car's bytes.
                var pickedByFit = false
                if let raw, state.ncsIndexMismatch(module) != nil, let fit = state.bestFitIndex(module, raw: raw) {
                    state.decodeNCSCoding(module, index: fit)
                    params = state.ncsCoding[sgbd] ?? []
                    pickedByFit = true
                }
                // Block 0 is what rawCoding read; read any further blocks the options use (body: 1).
                var blocks: [Int: [UInt8]] = [:]
                if let raw {
                    blocks[0] = raw
                    for n in Set(params.map(\.blockNumber)).subtracting([0]).sorted() {
                        if let b = try? await state.codingBlock(module, n) { blocks[n] = b }
                    }
                    params = NCSDaten.apply(params, blocks: blocks)
                }
                else if note == nil { note = "This module reads coding with C_C_LESEN (a per-block buffer), not yet wired — showing the option map without live values. Read the raw bytes yourself and pass them to decode_coding, or we finalize this on the car." }
                if let mm = state.ncsIndexMismatch(module) {
                    let have = mm.have.map { String(format: "%02X", $0) }.joined(separator: ", ")
                    let used = String(format: "%02X", mm.used)
                    let warn = pickedByFit
                        ? "Car reports coding index \(String(format: "%02X", mm.car)), which no DATEN file declares (have: \(have)); used index \(used), the version that best fits the bytes read from the car."
                        : "Car reports coding index \(String(format: "%02X", mm.car)), but the DATEN folder has no file for it (have: \(have)). Decoded with index \(used) — options may be wrong for this car."
                    note = note.map { "\(warn) \($0)" } ?? warn
                }
                // Options addressed beyond the bytes read (e.g. RAM-only settings) carry no value.
                if raw != nil {
                    params = params.filter { p in
                        guard let b = blocks[p.blockNumber] else { return false }   // block not readable
                        return p.byteAddress + p.mask.count <= b.count
                    }
                }
                result = codingJSON(params, index: state.ncsIndex[sgbd], raw: raw, note: note,
                                    direct: state.ncsDirect[sgbd] ?? [], blocks: blocks)
            case "decode_coding":
                guard state.datenReady else { throw ToolError("No coding data: set the DATEN folder in Setup → Coding data.") }
                let module = state.modules.first { $0.sgbd == sgbd } ?? Module(group: "", sgbd: sgbd, name: "", ident: [:])
                guard !state.ncsCodingFiles(for: module).isEmpty else { throw ToolError("No coding file for \(sgbd) in the DATEN folder.") }
                state.decodeNCSCoding(module, index: args["index"] as? Int)
                var params = state.ncsCoding[sgbd] ?? []
                var raw: [UInt8]?
                if let hex = args["raw"] as? String, !hex.isEmpty {
                    guard let bytes = AppState.hexBytes(hex) else { throw ToolError("raw isn't valid hex") }
                    raw = bytes; params = NCSDaten.apply(params, raw: bytes)
                }
                result = codingJSON(params, index: state.ncsIndex[sgbd], raw: raw, note: nil,
                                    direct: state.ncsDirect[sgbd] ?? [], blocks: raw.map { [0: $0] } ?? [:])
            case "get_history":
                let limit = min(max(args["limit"] as? Int ?? 10, 1), 50)
                result = state.history.filter { sgbd.isEmpty || $0.sgbd == sgbd }.prefix(limit).map { e -> [String: Any] in
                    ["id": e.id, "date": ISO8601DateFormatter().string(from: e.date), "sgbd": e.sgbd, "title": e.title,
                     "faults": e.faults.map { ["code": $0.code, "text": $0.text] }, "valueCount": e.values.count]
                }
            case "compare_history":
                guard let a = state.history.first(where: { $0.id == args["before"] as? String }),
                      let b = state.history.first(where: { $0.id == args["after"] as? String }) else { throw ToolError("Unknown history id; see get_history") }
                let d = HistoryStore.diff(from: a, to: b)
                func list(_ f: [HistoryEntry.FaultRecord]) -> [[String: String]] { f.map { ["code": $0.code, "text": $0.text] } }
                result = ["sameModule": a.sgbd == b.sgbd, "newFaults": list(d.newFaults), "goneFaults": list(d.goneFaults),
                          "stillPresent": list(d.stillFaults),
                          "changedValues": d.changedValues.map { ["name": $0.name, "before": $0.before, "after": $0.after] }]
            default:
                throw ToolError("Unknown tool \(name)")
            }
            return (json(result), false)
        } catch {
            state.note("Claude: \(name) failed", ok: false, error.localizedDescription)
            return (error.localizedDescription, true)
        }
    }

    private static func runJob(_ state: AppState, _ sgbd: String, _ job: String, _ args: String, _ binary: String?) async throws -> Any {
        guard !job.isEmpty else { throw ToolError("job is empty") }
        if let why = codingJobReason(job) { throw ToolError(why) }
        let module = state.modules.first { $0.sgbd == sgbd } ?? Module(group: "", sgbd: sgbd, name: "", ident: [:])
        if isReadOnly(job) {
            var jobParams: [String: Any] = ["sgbd": sgbd, "job": job, "args": args]
            if let bin = binary, !bin.isEmpty {
                guard binaryArgJobs.contains("\(sgbd)/\(job)") else {
                    throw ToolError("A binary argument is only accepted for \(binaryArgJobs.sorted().joined(separator: ", ")) — jobs verified to only read.")
                }
                guard AppState.hexBytes(bin) != nil else { throw ToolError("binary isn't valid hex") }
                jobParams["argbin"] = bin
            }
            let data = try await state.engineSend("job", jobParams) as? [ResultSet] ?? []
            return job.hasPrefix("_") ? data : AppState.jobSets(data)
        }
        guard binary?.isEmpty ?? true else { throw ToolError("Binary arguments are only accepted for read jobs.") }
        if job.hasPrefix("STEUERN_"), state.testCoolingDown {
            throw ToolError("Another test ran less than \(Int(AppState.testCooldown)) s ago; wait and try again.")
        }
        if job == "FS_LOESCHEN" {   // keep the evidence; if that read is stopped, don't clear
            await state.read(module)
            if state.stopping { return ["stopped": true, "message": "The user stopped the read, so the faults were not cleared."] }
        }
        if job.hasPrefix("STEUERN_") { state.lastTestAt = Date() }
        guard let sets = await state.perform("Claude: \(job) on \(module.title)", sgbd: sgbd, job: job, args: args) else {
            throw ToolError(state.lastError ?? "\(job) failed")
        }
        if job == "FS_LOESCHEN" { await state.read(module) }
        return ["results": sets]
    }

    /// Stage one coding change through the app's own flow (fresh read, checks, backup, diff), then
    /// wait for the user's decision on the confirm sheet. The write itself is the app's, never ours.
    private static func requestCodingChange(_ state: AppState, _ sgbd: String, _ option: String, _ value: String, _ reason: String) async throws -> Any {
        guard state.datenReady else { throw ToolError("No coding data: set the DATEN folder in Setup → Coding data.") }
        guard let module = state.modules.first(where: { $0.sgbd == sgbd }) else { throw ToolError("Unknown module \(sgbd); call list_modules or scan_modules.") }
        guard state.pending == nil, !state.busy else { throw ToolError("The app is busy or already waiting for the user; try again shortly.") }
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !why.isEmpty else { throw ToolError("reason is required: tell the user what this changes and why.") }

        let isDSC = module.isDSCMK60
        if (isDSC ? state.dscCodingWriteBlocker(module) : state.codingWriteBlocker(module)) != nil {
            // The coding-index check needs an ident read first; do it once, then re-check.
            await state.read(module, values: false)
            if let blocker = isDSC ? state.dscCodingWriteBlocker(module) : state.codingWriteBlocker(module) { throw ToolError(blocker) }
        }
        await state.readNCSValues(module)   // fresh values from the car
        guard let p = state.ncsCoding[sgbd]?.first(where: { $0.name.caseInsensitiveCompare(option) == .orderedSame }) else {
            throw ToolError("\(sgbd) has no coding option named \(option); use the `name` from read_coding.")
        }
        let changeable = isDSC ? state.dscCodingOptionChangeable(module, p) : state.isCodingOptionWritable(module, p)
        guard changeable else { throw ToolError("\(p.name) can't be changed (no named values, protected, or outside the writable coding).") }
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = Int(v).flatMap({ p.choices[$0] != nil ? $0 : nil })
                ?? p.choices.first(where: { $0.value.caseInsensitiveCompare(v) == .orderedSame
                    || Translate.codingChoice($0.value, option: p.name).caseInsensitiveCompare(v) == .orderedSame })?.key else {
            let names = p.choices.sorted { $0.key < $1.key }.map { "\($0.value) (\($0.key))" }.joined(separator: ", ")
            throw ToolError("\(v) isn't a value of \(p.name). Choices: \(names)")
        }
        guard target != p.value else { return ["changed": false, "message": "\(p.name) is already \(p.choices[target] ?? "\(target)")."] }

        state.lastError = nil
        if isDSC { await state.requestDscCodingChange(module, p, to: target) } else { await state.requestCodingChange(module, p, to: target) }
        guard let staged = state.pending else { throw ToolError(state.lastError ?? "The app refused the change.") }

        // Same sheet, same delay and no default button; we only add Claude's reason and learn the outcome.
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSSound.beep()
        let approved: Bool = await withCheckedContinuation { cont in
            state.pending = PendingAction(
                title: "Claude asks: \(staged.title)",
                message: "Claude's reason: \(why)\n\n\(staged.message)",
                confirm: staged.confirm,
                run: { await staged.run(); cont.resume(returning: true) },
                cancel: { staged.cancel?(); cont.resume(returning: false) },
                detail: staged.detail, delay: staged.delay, confirmIsDefault: staged.confirmIsDefault)
        }
        guard approved else {
            state.note("Claude: coding change declined", ok: false)
            return ["approved": false, "message": "The user declined. Nothing was written."]
        }
        let now = state.ncsCoding[sgbd]?.first(where: { $0.name == p.name })
        let ok = now?.value == target
        return ["approved": true, "verified": ok, "option": p.name,
                "value": now?.value.flatMap { p.choices[$0] } ?? "unknown",
                "message": ok ? "Written and read back." : (state.lastError ?? "The read-back didn't show the new value; check the app.")]
    }

    private static func live(_ state: AppState, _ sgbd: String, _ jobs: [String], _ samples: Int) async throws -> Any {
        var series: [String: [String: [Double]]] = [:], last: [String: Any] = [:]
        for _ in 0..<samples {
            let round = try await state.engineSend("poll", ["sgbd": sgbd, "jobs": jobs]) as? [String: Any] ?? [:]
            for (job, value) in round {
                last[job] = value
                guard let set = value as? ResultSet else { continue }
                for (k, v) in set { if let d = LiveMonitor.number(v) { series[job, default: [:]][k, default: []].append(d) } }
            }
        }
        return jobs.reduce(into: [String: Any]()) { out, job in
            if let err = (last[job] as? [String: Any])?["error"] as? String { out[job] = ["error": Engine.shortError(err)]; return }
            let set = last[job] as? ResultSet ?? [:]
            var entry: [String: Any] = [:]
            for (k, v) in set where k != "JOB_STATUS" {
                if let list = series[job]?[k], samples > 1 {
                    entry[k] = ["latest": list.last!, "min": list.min()!, "max": list.max()!, "avg": list.reduce(0, +) / Double(list.count)]
                } else {
                    entry[k] = k.hasSuffix("_EINH") ? Translate.unit(AppState.string(v)) : v
                }
            }
            out[job] = convertUnits(entry)
        }
    }

    /// Convert each `_WERT` reading (and its sibling `_EINH` unit) to imperial when that's the
    /// chosen system. Handles both a scalar reading and the {latest,min,max,avg} aggregate.
    private static func convertUnits(_ entry: [String: Any]) -> [String: Any] {
        guard Measure.system == .imperial else { return entry }
        var e = entry
        for k in entry.keys where k.hasSuffix("_WERT") {
            let einhKey = String(k.dropLast(5)) + "_EINH"
            guard let unit = e[einhKey] as? String else { continue }
            if let agg = e[k] as? [String: Any] {
                var nd = agg
                for sub in ["latest", "min", "max", "avg"] where nd[sub] != nil {
                    if let d = LiveMonitor.number(nd[sub]) {
                        nd[sub] = Measure.convert(number: d, text: "\(d)", unit: unit).number
                    }
                }
                e[k] = nd
                e[einhKey] = Measure.convert(number: 0, text: "0", unit: unit).unit
            } else {
                let c = Measure.convert(text: AppState.string(e[k]), unit: unit)
                e[k] = c.text
                e[einhKey] = c.unit
            }
        }
        return e
    }

    private static func moduleJSON(_ state: AppState) -> (Module) -> [String: Any] {
        { m in
            var d: [String: Any] = ["sgbd": m.sgbd, "group": m.group, "title": m.title]
            if let r = state.reports[m.sgbd] { d["faultsAtLastRead"] = r.faults.count }
            return d
        }
    }

    private static func reportJSON(_ m: Module, _ r: ModuleReport) -> [String: Any] {
        func faults(_ list: [Fault]) -> [[String: Any]] {
            list.map { f in
                var d: [String: Any] = ["code": f.code, "text": f.text, "details": Dictionary(f.details, uniquingKeysWith: { a, _ in a })]
                if !f.original.isEmpty { d["german"] = f.original }
                if let n = f.note { d["note"] = n }
                return d
            }
        }
        return ["sgbd": m.sgbd, "title": m.title,
                "faults": faults(r.faults), "infoMemory": faults(r.infoMemory),
                "ident": Dictionary(r.ident, uniquingKeysWith: { a, _ in a }),
                "values": r.live.map { v in let c = Measure.convert(text: v.value, unit: v.unit); return "\(v.job)/\(v.name) = \(c.text)\(c.unit.isEmpty ? "" : " " + c.unit)" },
                "jobsThatFailed": r.errors]
    }

    private static func codingJSON(_ params: [NCSDaten.Param], index: Int?, raw: [UInt8]?, note: String?,
                                   direct: [NCSDaten.Direct] = [], blocks: [Int: [UInt8]] = [:]) -> [String: Any] {
        let protected = NCSDaten.protectedBytes(direct)
        let options: [[String: Any]] = params.map { p in
            // `label` is the English translation; `name` keeps the German FSW keyword for NCS Expert.
            var d: [String: Any] = ["label": Translate.coding(p.name), "name": p.name,
                                    "block": p.block, "byte": p.byteAddress,
                                    "mask": p.mask.map { String(format: "%02X", $0) }.joined(),
                                    "fsw": String(format: "%04X", p.function)]
            if NCSDaten.touchesProtected(p, protected) { d["protected"] = true }   // overlaps a direct field
            if let v = p.value {
                d["value"] = v
                // A raw bit isn't the meaning when the data names the value (0 is often "aktiv").
                if p.isFlag, p.meaning == nil { d["state"] = v == 1 ? "on" : "off" }
                if let keyword = p.meaning {
                    // the coding data's own name for this value; English where we know it
                    d["meaning"] = Translate.codingChoice(keyword, option: p.name); d["meaningGerman"] = keyword
                } else if !p.isFlag, let meaning = Translate.codingValue(p.name, v) { d["meaning"] = meaning }
            }
            return d
        }
        var out: [String: Any] = ["options": options, "optionCount": options.count, "readOnly": true,
                                  "valuesRead": raw != nil]
        if let index { out["codingIndex"] = String(format: "%02X", index) }   // hex, as in the .cNN name
        // Directly assigned fields (VIN, coding date, checksums…): not options, and protected from
        // writes. Shown with their raw bytes where the block was read.
        if !direct.isEmpty {
            out["directFields"] = direct.map { f -> [String: Any] in
                var d: [String: Any] = ["name": f.name, "label": Translate.coding(f.name), "block": f.blockNumber,
                                        "byte": f.byteAddress, "length": f.length]
                if let b = blocks[f.blockNumber], f.byteAddress + f.length <= b.count {
                    d["raw"] = b[f.byteAddress..<(f.byteAddress + f.length)].map { String(format: "%02X", $0) }.joined(separator: " ")
                }
                return d
            }
            out["protectedByteCount"] = protected.values.reduce(0) { $0 + $1.count }
        }
        if let raw { out["rawBytes"] = raw.map { String(format: "%02X", $0) }.joined(separator: " ") }
        if let note { out["note"] = note }
        return out
    }

    private static func json(_ v: Any) -> String {
        guard JSONSerialization.isValidJSONObject(v) || v is [Any] || v is [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return "\(v)" }
        return String(decoding: data, as: UTF8.self)
    }

    struct ToolError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }
}
