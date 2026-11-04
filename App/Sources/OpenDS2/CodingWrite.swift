import Foundation

/// Coding writes: change ONE named option of the body module, with a fresh read, a saved backup,
/// the owner's approval at the car, the engine's own checks (`codewrite`) and a read-back verify.
/// See docs/CODING-SAFETY-REVIEW.md §6. Only the body module (coding file gm5), whose write format
/// was proven on the car; the cluster waits for its checksum algorithm. AI clients can't write.
extension AppState {
    /// Coding families writes are enabled for. Body module only, for now.
    static let writableCodingFamilies: Set<String> = ["gm5"]
    /// Cluster VIN (FG_NR) write — a raw word write to byte 0x7A (see docs/CLUSTER-VIN-FIX.md).
    /// Runtime toggle, OFF by default: the user enables it in Setup for the documented procedure, and
    /// can turn it back off. Human-only (never MCP). There is no odometer write path.
    static let vinWriteDefaultsKey = "clusterVinWriteEnabled"
    static var vinWriteEnabled: Bool { UserDefaults.standard.bool(forKey: vinWriteDefaultsKey) }
    /// Minimum battery voltage (DME STATUS_UBATT, ignition on, engine off) for a coding write.
    static let minCodingVoltage = 12.0
    /// The body module's coding blocks are 29 data bytes plus this "korrekt codiert" marker.
    static let bodyBlockLength = 30
    static let codedMarker: UInt8 = 0xAA

    struct CodingBackup: Codable {
        var date: Date
        var sgbd: String
        var vin: String
        var codingFile: String
        var codingIndex: Int
        var block: Int
        var bytes: String        // the 30 bytes before the change, hex
        var option: String       // FSW keyword
        var oldValue: Int
        var newValue: Int
        var result: String?      // filled in after the write
    }

    static var backupFolder: URL {
        AppPaths.support.appendingPathComponent("coding-backups", isDirectory: true)
    }

    /// Why this module's coding can't be changed right now, or nil if it can.
    func codingWriteBlocker(_ module: Module) -> String? {
        guard NCSDaten.codingBasenames(module.sgbd).contains(where: Self.writableCodingFamilies.contains) else {
            return "Coding changes are only available for the body module so far."
        }
        guard datenReady else { return "Set the coding data folder in Setup first." }
        guard let carIndex = codingIndexFromCar(module) else { return "Read this module first, so its coding index is known." }
        guard let used = ncsIndex[module.sgbd], used == carIndex,
              let file = ncsCodingFiles(for: module).first(where: { $0.index == carIndex }),
              let cx = try? Data(contentsOf: file.url), NCSDaten.declaredIndex([UInt8](cx)) == carIndex else {
            return "The coding data has no file that exactly matches this module's coding index (\(String(format: "%02X", carIndex))), so changes are blocked."
        }
        return nil
    }

    /// Whether this option can be offered for a change (named values, read from the car, not
    /// protected, block 0/1, never the AA marker byte). Cheap; pair with `codingWriteBlocker`.
    func codingOptionChangeable(_ module: Module, _ p: NCSDaten.Param) -> Bool {
        let protected = NCSDaten.protectedBytes(ncsDirect[module.sgbd] ?? [])
        return p.value != nil && p.choices.count > 1
            && (0...1).contains(p.blockNumber) && !NCSDaten.touchesProtected(p, protected)
            && p.byteAddress + p.mask.count <= Self.bodyBlockLength - 1
    }

    func isCodingOptionWritable(_ module: Module, _ p: NCSDaten.Param) -> Bool {
        codingWriteBlocker(module) == nil && codingOptionChangeable(module, p)
    }

    // MARK: reading

    /// Read one body-module coding block with C_C_LESEN: the 30 bytes including the AA marker.
    func readBodyBlock(_ module: Module, _ block: Int) async throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 0x16 + Self.bodyBlockLength)
        buf[0] = 1; buf[0x0D] = UInt8(Self.bodyBlockLength); buf[0x12] = UInt8(block)
        let data = try await engineSend("job", ["sgbd": module.sgbd, "job": "C_C_LESEN", "args": "",
                                                "argbin": buf.map { String(format: "%02X", $0) }.joined()]) as? [ResultSet] ?? []
        guard let set = AppState.jobSets(data).first, AppState.string(set["JOB_STATUS"]) == "OKAY",
              let raw = AppState.hexBytes(AppState.string(set["CODIER_DATEN"])), raw.count >= 0x15 + Self.bodyBlockLength
        else { throw CodingWriteError("Couldn't read coding block \(block) of \(module.title).") }
        return Array(raw[0x15..<(0x15 + Self.bodyBlockLength)])
    }

    /// Read the module's coding blocks and show the car's current values in the Coding tab.
    func readNCSValues(_ module: Module) async {
        _ = await run("Reading coding values…") { [self] in
            if codingIndexFromCar(module) == nil { await read(module, values: false) }
            decodeNCSCoding(module)
            guard let params = ncsCoding[module.sgbd], !params.isEmpty else { return }
            var blocks: [Int: [UInt8]] = [:]
            if NCSDaten.codingBasenames(module.sgbd).contains("gm5") {
                for n in Set(params.map(\.blockNumber)).sorted() where (0...1).contains(n) {
                    blocks[n] = try await readBodyBlock(module, n)
                }
            } else if let raw = try await rawCoding(module) {
                blocks[0] = raw
                for n in Set(params.map(\.blockNumber)).subtracting([0]).sorted() {
                    if let b = try? await codingBlock(module, n) { blocks[n] = b }
                }
            }
            ncsCoding[module.sgbd] = NCSDaten.apply(params, blocks: blocks)
            note("Coding values read: \(module.title)")
        }
    }

    // MARK: changing

    struct CodingWriteError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }

    /// Ask to change one option. Builds and checks the change, then asks the owner at the car.
    func requestCodingChange(_ module: Module, _ p: NCSDaten.Param, to value: Int) async {
        do {
            let plan = try await prepareCodingChange(module, p, to: value)
            let oldName = Translate.codingChoice(p.choices[p.value ?? -1] ?? "\(p.value ?? -1)", option: p.name)
            let newName = Translate.codingChoice(p.choices[value] ?? "\(value)", option: p.name)
            pending = PendingAction(
                title: "Change body module coding?",
                message: """
                \(Translate.coding(p.name)) (\(p.name))
                \(oldName)  →  \(newName)

                Battery \(String(format: "%.1f", plan.voltage)) V, engine off. The current coding was saved to \
                \(plan.backupURL.lastPathComponent) and can be restored. Only this option changes; the module \
                checks the write and the app reads it back. Keep the ignition on until it finishes.
                """,
                confirm: "Write to car",
                run: { [self] in await performCodingChange(module, p, plan) },
                detail: plan.diff,
                delay: 3,
                confirmIsDefault: false)
        } catch {
            lastError = error.localizedDescription
            note("Coding change refused: \(Translate.coding(p.name))", ok: false, error.localizedDescription)
        }
    }

    struct CodingPlan {
        let block: Int
        let before: [UInt8]
        let after: [UInt8]
        let diff: String
        let voltage: Double
        let backupURL: URL
        var backup: CodingBackup
    }

    private func prepareCodingChange(_ module: Module, _ p: NCSDaten.Param, to value: Int) async throws -> CodingPlan {
        if let why = codingWriteBlocker(module) { throw CodingWriteError(why) }
        guard !busy, pending == nil else { throw CodingWriteError("Something else is running; try again when it finishes.") }
        guard isCodingOptionWritable(module, p) else { throw CodingWriteError("This option can't be changed.") }
        guard let shown = p.value, shown != value, p.choices[value] != nil else {
            throw CodingWriteError("Pick one of the option's other values.")
        }
        let block = p.blockNumber

        // Fresh read: the change is built from what's on the car now, not from the screen.
        let fresh = try await readBodyBlock(module, block)
        guard fresh.count == Self.bodyBlockLength, fresh[Self.bodyBlockLength - 1] == Self.codedMarker else {
            throw CodingWriteError("Block \(block) isn't marked as correctly coded (no AA); not changing it.")
        }
        guard NCSDaten.apply([p], raw: fresh)[0].value == shown else {
            throw CodingWriteError("This option changed since you read it. Read the values again first.")
        }

        // Build the change and check it: only this option's mask bits, the marker untouched.
        guard let after = NCSDaten.encode(p, value: value, into: fresh) else {
            throw CodingWriteError("That value doesn't fit this option.")
        }
        let span = p.byteAddress..<(p.byteAddress + p.mask.count)
        for i in 0..<Self.bodyBlockLength {
            let maskBits: UInt8 = span.contains(i) ? p.mask[i - p.byteAddress] : 0
            guard (after[i] ^ fresh[i]) & ~maskBits == 0 else {
                throw CodingWriteError("Internal check failed: byte \(i) would change outside the option.")
            }
        }
        guard after[Self.bodyBlockLength - 1] == Self.codedMarker, after != fresh,
              NCSDaten.apply([p], raw: after)[0].value == value else {
            throw CodingWriteError("Internal check failed: the new bytes don't decode to the chosen value.")
        }

        // Preconditions: engine off, battery voltage (from the DME).
        let voltage = try await checkCodingPreconditions()

        // Backup before anything is written.
        let vin = await bodyVIN(module)
        let file = ncsCodingFiles(for: module).first { $0.index == ncsIndex[module.sgbd] }
        var backup = CodingBackup(date: Date(), sgbd: module.sgbd, vin: vin,
                                  codingFile: file?.url.lastPathComponent ?? "?", codingIndex: ncsIndex[module.sgbd] ?? -1,
                                  block: block, bytes: hex(fresh), option: p.name, oldValue: shown, newValue: value)
        let url = try saveBackup(&backup)

        let changed = span.map { i in
            String(format: "byte %2d: %02X → %02X   (mask %02X)", i, fresh[i], after[i], p.mask[i - p.byteAddress])
        }.joined(separator: "\n")
        let diff = "Block \(block), \(file?.url.lastPathComponent ?? "") index \(String(format: "%02X", ncsIndex[module.sgbd] ?? 0))\n\(changed)"
        return CodingPlan(block: block, before: fresh, after: after, diff: diff, voltage: voltage, backupURL: url, backup: backup)
    }

    private func performCodingChange(_ module: Module, _ p: NCSDaten.Param, _ plan: CodingPlan) async {
        var backup = plan.backup
        let ok: Bool? = await run("Writing coding: \(Translate.coding(p.name))…") { [self] in
            _ = try await engineSend("codewrite", ["sgbd": module.sgbd, "block": plan.block,
                                                   "data": hex(plan.after), "expect": hex(plan.before)])
            // Our own read-back on top of the engine's: every option in this block must be as planned.
            let now = try await readBodyBlock(module, plan.block)
            guard now == plan.after else {
                throw CodingWriteError("The module reads back \(hex(now)), not the planned bytes.")
            }
            return true
        }
        backup.result = ok == true ? "written and verified" : "failed: \(lastError ?? "unknown")"
        _ = try? saveBackup(&backup, url: plan.backupURL)
        if ok == true {
            note("Coding changed: \(Translate.coding(p.name))", ok: true, "Backup: \(plan.backupURL.path)")
            await readNCSValues(module)
        } else {
            note("Coding change failed: \(Translate.coding(p.name))", ok: false, lastError ?? "")
        }
    }

    // MARK: restore

    /// Saved backups for a module, newest first.
    func codingBackups(_ module: Module) -> [(url: URL, backup: CodingBackup)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.backupFolder, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return urls.compactMap { u in
            guard u.pathExtension == "json", let d = try? Data(contentsOf: u), let b = try? dec.decode(CodingBackup.self, from: d),
                  b.sgbd == module.sgbd else { return nil }
            return (u, b)
        }.sorted { $0.backup.date > $1.backup.date }
    }

    /// Put a backed-up block back, through the same checked path (one option's bytes at most).
    func requestCodingRestore(_ module: Module, _ entry: (url: URL, backup: CodingBackup)) async {
        do {
            if let why = codingWriteBlocker(module) { throw CodingWriteError(why) }
            guard let saved = AppState.hexBytes(entry.backup.bytes), saved.count == Self.bodyBlockLength,
                  saved[Self.bodyBlockLength - 1] == Self.codedMarker else { throw CodingWriteError("The backup is damaged.") }
            let vin = await bodyVIN(module)
            guard vin == entry.backup.vin else { throw CodingWriteError("This backup is from another car (VIN \(entry.backup.vin)).") }
            let block = entry.backup.block
            let fresh = try await readBodyBlock(module, block)
            guard fresh != saved else { throw CodingWriteError("The module already holds the backed-up coding.") }
            let differing = (0..<Self.bodyBlockLength).filter { fresh[$0] != saved[$0] }
            guard differing.count <= 4 else {
                throw CodingWriteError("\(differing.count) bytes differ from the backup; a restore only undoes one change.")
            }
            let voltage = try await checkCodingPreconditions()
            let diff = "Block \(block)\n" + differing.map { String(format: "byte %2d: %02X → %02X", $0, fresh[$0], saved[$0]) }.joined(separator: "\n")
            pending = PendingAction(
                title: "Restore body module coding?",
                message: "Puts back the coding saved \(entry.backup.date.formatted()) before \(Translate.coding(entry.backup.option)) was changed. Battery \(String(format: "%.1f", voltage)) V, engine off.",
                confirm: "Restore",
                run: { [self] in
                    let ok: Bool? = await run("Restoring coding…") { [self] in
                        _ = try await self.engineSend("codewrite", ["sgbd": module.sgbd, "block": block,
                                                                    "data": self.hex(saved), "expect": self.hex(fresh)])
                        guard try await self.readBodyBlock(module, block) == saved else { throw CodingWriteError("Restore didn't verify.") }
                        return true
                    }
                    note(ok == true ? "Coding restored" : "Coding restore failed", ok: ok == true, lastError ?? entry.url.path)
                    if ok == true { await readNCSValues(module) }
                },
                detail: diff, delay: 3, confirmIsDefault: false)
        } catch {
            lastError = error.localizedDescription
            note("Restore refused", ok: false, error.localizedDescription)
        }
    }

    // MARK: DSC coding change (dsc_mk60)

    /// The ABS/DSC coding block is 15 bytes: byte 0 is the checksum (the module recomputes it on
    /// write), bytes 1..14 are the data. The engine's `dsccodewrite` sends the 14 data bytes via
    /// COD_SCHREIBEN. Same safety flow as body coding: fresh read, single option, backup, engine-off
    /// + battery, confirm with diff, read-back verify. First real use should be a harmless round-trip.
    static let dscCodingLength = 15

    func dscCodingWriteBlocker(_ module: Module) -> String? {
        guard module.isDSCMK60 else { return "DSC coding changes are only for the ABS/DSC module." }
        guard datenReady else { return "Set the coding data folder in Setup first." }
        guard let carIndex = codingIndexFromCar(module) else { return "Read this module first, so its coding index is known." }
        guard let used = ncsIndex[module.sgbd], used == carIndex,
              let file = ncsCodingFiles(for: module).first(where: { $0.index == carIndex }),
              let cx = try? Data(contentsOf: file.url), NCSDaten.declaredIndex([UInt8](cx)) == carIndex else {
            return "The coding data has no file that exactly matches this module's coding index (\(String(format: "%02X", carIndex))), so changes are blocked."
        }
        return nil
    }

    /// Changeable DSC option: named values, read from the car, not protected, inside bytes 1..14
    /// (never the checksum byte 0).
    func dscCodingOptionChangeable(_ module: Module, _ p: NCSDaten.Param) -> Bool {
        let protected = NCSDaten.protectedBytes(ncsDirect[module.sgbd] ?? [])
        return p.value != nil && p.choices.count > 1
            && p.byteAddress >= 1 && p.byteAddress + p.mask.count <= Self.dscCodingLength
            && !NCSDaten.touchesProtected(p, protected)
    }

    func isDscCodingWritable(_ module: Module, _ p: NCSDaten.Param) -> Bool {
        dscCodingWriteBlocker(module) == nil && dscCodingOptionChangeable(module, p)
    }

    func requestDscCodingChange(_ module: Module, _ p: NCSDaten.Param, to value: Int) async {
        do {
            let plan = try await prepareDscCodingChange(module, p, to: value)
            let oldName = Translate.codingChoice(p.choices[p.value ?? -1] ?? "\(p.value ?? -1)", option: p.name)
            let newName = Translate.codingChoice(p.choices[value] ?? "\(value)", option: p.name)
            pending = PendingAction(
                title: "Change ABS/DSC coding?",
                message: """
                \(Translate.coding(p.name)) (\(p.name))
                \(oldName)  →  \(newName)

                ABS/DSC module. Battery \(String(format: "%.1f", plan.voltage)) V, engine off. The current coding was \
                saved to \(plan.backupURL.lastPathComponent) and can be restored. Only this option changes; the DSC \
                recomputes its own checksum and the app reads it back. Keep the ignition on until it finishes, then \
                test the brakes and recheck the DSC for faults.
                """,
                confirm: "Write to DSC",
                run: { [self] in await performDscCodingChange(module, p, plan) },
                detail: plan.diff, delay: 3, confirmIsDefault: false)
        } catch {
            lastError = error.localizedDescription
            note("DSC coding change refused: \(Translate.coding(p.name))", ok: false, error.localizedDescription)
        }
    }

    private func prepareDscCodingChange(_ module: Module, _ p: NCSDaten.Param, to value: Int) async throws -> CodingPlan {
        if let why = dscCodingWriteBlocker(module) { throw CodingWriteError(why) }
        guard !busy, pending == nil else { throw CodingWriteError("Something else is running; try again when it finishes.") }
        guard isDscCodingWritable(module, p) else { throw CodingWriteError("This option can't be changed.") }
        guard let shown = p.value, shown != value, p.choices[value] != nil else {
            throw CodingWriteError("Pick one of the option's other values.")
        }
        // Fresh read from the car: the change is built from what's on the DSC now.
        guard let fresh = try await rawCoding(module), fresh.count == Self.dscCodingLength else {
            throw CodingWriteError("Couldn't read the DSC coding (expected \(Self.dscCodingLength) bytes).")
        }
        guard NCSDaten.apply([p], raw: fresh)[0].value == shown else {
            throw CodingWriteError("This option changed since you read it. Read the values again first.")
        }
        guard let after = NCSDaten.encode(p, value: value, into: fresh) else {
            throw CodingWriteError("That value doesn't fit this option.")
        }
        // Only this option's mask bits may change, and never the checksum byte 0.
        let span = p.byteAddress..<(p.byteAddress + p.mask.count)
        for i in 0..<Self.dscCodingLength {
            let maskBits: UInt8 = span.contains(i) ? p.mask[i - p.byteAddress] : 0
            guard (after[i] ^ fresh[i]) & ~maskBits == 0 else {
                throw CodingWriteError("Internal check failed: byte \(i) would change outside the option.")
            }
        }
        guard after[0] == fresh[0] else {
            throw CodingWriteError("Internal check failed: the change would touch the checksum byte.")
        }
        guard after != fresh, NCSDaten.apply([p], raw: after)[0].value == value else {
            throw CodingWriteError("Internal check failed: the new bytes don't decode to the chosen value.")
        }
        let voltage = try await checkCodingPreconditions()
        let vin = await bodyVIN(module)
        let file = ncsCodingFiles(for: module).first { $0.index == ncsIndex[module.sgbd] }
        var backup = CodingBackup(date: Date(), sgbd: module.sgbd, vin: vin,
                                  codingFile: file?.url.lastPathComponent ?? "?", codingIndex: ncsIndex[module.sgbd] ?? -1,
                                  block: 0, bytes: hex(fresh), option: p.name, oldValue: shown, newValue: value)
        let url = try saveBackup(&backup)
        let changed = span.map { i in
            String(format: "byte %2d: %02X → %02X   (mask %02X)", i, fresh[i], after[i], p.mask[i - p.byteAddress])
        }.joined(separator: "\n")
        let diff = "ABS/DSC coding, \(file?.url.lastPathComponent ?? "") index \(String(format: "%02X", ncsIndex[module.sgbd] ?? 0))\n\(changed)"
        return CodingPlan(block: 0, before: fresh, after: after, diff: diff, voltage: voltage, backupURL: url, backup: backup)
    }

    private func performDscCodingChange(_ module: Module, _ p: NCSDaten.Param, _ plan: CodingPlan) async {
        var backup = plan.backup
        let ok: Bool? = await run("Writing DSC coding: \(Translate.coding(p.name))…") { [self] in
            let data = Array(plan.after[1...])   // 14 data bytes; the DSC recomputes byte 0 (checksum)
            _ = try await engineSend("dsccodewrite", ["sgbd": module.sgbd, "data": hex(data), "expect": hex(plan.before)])
            // Our own read-back on top of the engine's: the 14 data bytes must be as planned.
            guard let now = try await rawCoding(module), now.count == Self.dscCodingLength,
                  Array(now[1...]) == Array(plan.after[1...]) else {
                throw CodingWriteError("The DSC reads back differently from the planned bytes.")
            }
            return true
        }
        backup.result = ok == true ? "written and verified" : "failed: \(lastError ?? "unknown")"
        _ = try? saveBackup(&backup, url: plan.backupURL)
        if ok == true {
            note("DSC coding changed: \(Translate.coding(p.name))", ok: true, "Backup: \(plan.backupURL.path)")
            await readNCSValues(module)
        } else {
            note("DSC coding change failed: \(Translate.coding(p.name))", ok: false, lastError ?? "")
        }
    }

    /// Put a backed-up DSC coding block back, through the same checked path.
    func requestDscCodingRestore(_ module: Module, _ entry: (url: URL, backup: CodingBackup)) async {
        do {
            if let why = dscCodingWriteBlocker(module) { throw CodingWriteError(why) }
            guard let saved = AppState.hexBytes(entry.backup.bytes), saved.count == Self.dscCodingLength else {
                throw CodingWriteError("The backup is damaged.")
            }
            let vin = await bodyVIN(module)
            guard vin == entry.backup.vin else { throw CodingWriteError("This backup is from another car (VIN \(entry.backup.vin)).") }
            guard let fresh = try await rawCoding(module), fresh.count == Self.dscCodingLength else {
                throw CodingWriteError("Couldn't read the DSC coding.")
            }
            guard fresh != saved else { throw CodingWriteError("The module already holds the backed-up coding.") }
            let differing = (1..<Self.dscCodingLength).filter { fresh[$0] != saved[$0] }   // byte 0 is the checksum
            guard differing.count <= 4 else {
                throw CodingWriteError("\(differing.count) bytes differ from the backup; a restore only undoes one change.")
            }
            let voltage = try await checkCodingPreconditions()
            let diff = "ABS/DSC coding\n" + differing.map { String(format: "byte %2d: %02X → %02X", $0, fresh[$0], saved[$0]) }.joined(separator: "\n")
            pending = PendingAction(
                title: "Restore ABS/DSC coding?",
                message: "Puts back the DSC coding saved \(entry.backup.date.formatted()) before \(Translate.coding(entry.backup.option)) was changed. Battery \(String(format: "%.1f", voltage)) V, engine off.",
                confirm: "Restore",
                run: { [self] in
                    let ok: Bool? = await run("Restoring DSC coding…") { [self] in
                        _ = try await self.engineSend("dsccodewrite", ["sgbd": module.sgbd,
                            "data": self.hex(Array(saved[1...])), "expect": self.hex(fresh)])
                        guard let now = try await self.rawCoding(module), Array(now[1...]) == Array(saved[1...]) else {
                            throw CodingWriteError("Restore didn't verify.")
                        }
                        return true
                    }
                    note(ok == true ? "DSC coding restored" : "DSC coding restore failed", ok: ok == true, lastError ?? entry.url.path)
                    if ok == true { await readNCSValues(module) }
                },
                detail: diff, delay: 3, confirmIsDefault: false)
        } catch {
            lastError = error.localizedDescription
            note("DSC restore refused", ok: false, error.localizedDescription)
        }
    }

    // MARK: helpers

    /// Engine off and battery voltage, read from the engine computer. Throws if not safe.
    func checkCodingPreconditions() async throws -> Double {
        guard let dme = modules.first(where: { $0.sgbd.lowercased().hasPrefix("mss54") }) else {
            throw CodingWriteError("The engine computer wasn't found in the last scan, so battery voltage and engine speed can't be checked. Scan first.")
        }
        func value(_ job: String) async throws -> Double? {
            let data = try await engineSend("job", ["sgbd": dme.sgbd, "job": job, "args": ""]) as? [ResultSet] ?? []
            guard let set = AppState.jobSets(data).first,
                  let key = set.keys.first(where: { $0.hasPrefix("STAT_") && $0.hasSuffix("_WERT") }) else { return nil }
            return LiveMonitor.number(set[key])
        }
        guard let rpm = try await value("STATUS_MOTORDREHZAHL") else { throw CodingWriteError("Couldn't read engine speed.") }
        guard rpm < 50 else { throw CodingWriteError("The engine is running. Switch it off (ignition stays on) before changing coding.") }
        guard let volts = try await value("STATUS_UBATT") else { throw CodingWriteError("Couldn't read battery voltage.") }
        guard volts >= Self.minCodingVoltage else {
            throw CodingWriteError(String(format: "Battery is at %.1f V; coding needs at least %.1f V. Connect a charger.", volts, Self.minCodingVoltage))
        }
        return volts
    }

    func bodyVIN(_ module: Module) async -> String {
        let data = (try? await engineSend("job", ["sgbd": module.sgbd, "job": "C_FG_LESEN", "args": ""])) as? [ResultSet] ?? []
        return AppState.jobSets(data).first.map { AppState.string($0["FG_NR"]) } ?? ""
    }

    private func saveBackup(_ backup: inout CodingBackup, url: URL? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: Self.backupFolder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let target = url ?? Self.backupFolder.appendingPathComponent("\(f.string(from: backup.date))-\(backup.sgbd)-block\(backup.block).json")
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        try enc.encode(backup).write(to: target, options: .atomic)
        return target
    }

    func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }
}
