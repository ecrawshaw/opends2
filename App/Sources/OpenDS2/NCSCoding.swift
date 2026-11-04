import Foundation

// Decoder for BMW NCS Expert DATEN coding files (SP-DATEN), ported from the reference
// implementation (verified against ncsdummy.exe's own parser). Pure file parsing: given a
// folder of DATEN files the user points at, it turns a module's `.cXX` coding file into a
// named map — for each coding option: which byte, which bit mask, and the function name.
// Combined with the raw coding bytes the engine reads from the car (C_C_LESEN), this shows
// the car's actual settings. No BMW data is bundled; the files come from the user's folder.
//
// Container format (per ncsdummy DatenBuffer): a file is a stream of records. Each record is
//   [length:1][id:2 LE][data: `length` bytes][parity:1]   (total length+4 bytes)
// Fields inside `data` are read left-to-right with these helpers:
//   Word=UInt16 LE, LongWord=UInt32 LE, Byte=UInt8, String=NUL-terminated cp437,
//   XxxCollection(single): count = single ? 1 byte : UInt16 LE, then count elements.
enum NCSDaten {

    struct Record { let id: UInt16; let data: [UInt8] }

    /// Walk a DATEN file into its records.
    static func records(_ buf: [UInt8]) -> [Record] {
        var out: [Record] = []
        var i = 0
        while i < buf.count {
            let length = Int(buf[i])
            let total = length + 4
            guard i + total <= buf.count, i + 3 <= buf.count else { break }
            let id = UInt16(buf[i + 1]) | (UInt16(buf[i + 2]) << 8)
            let data = Array(buf[(i + 3)..<(i + 3 + length)])
            out.append(Record(id: id, data: data))
            i += total
        }
        return out
    }

    /// Cursor over a record's field region.
    struct Reader {
        let d: [UInt8]; var o = 0
        init(_ d: [UInt8]) { self.d = d }
        mutating func byte() -> UInt8 { defer { o += 1 }; return o < d.count ? d[o] : 0 }
        mutating func word() -> UInt16 {
            let v = UInt16(d[safe: o] ?? 0) | (UInt16(d[safe: o + 1] ?? 0) << 8); o += 2; return v
        }
        mutating func long() -> UInt32 {
            var v: UInt32 = 0
            for k in 0..<4 { v |= UInt32(d[safe: o + k] ?? 0) << (8 * k) }
            o += 4; return v
        }
        mutating func count(single: Bool) -> Int { single ? Int(byte()) : Int(word()) }
        mutating func longColl(single: Bool) -> [UInt32] {
            let n = count(single: single); return (0..<n).map { _ in long() }
        }
        mutating func byteColl(single: Bool) -> [UInt8] {
            let n = count(single: single); return (0..<n).map { _ in byte() }
        }
        mutating func charColl(single: Bool) -> [UInt8] {
            let n = count(single: single); return (0..<n).map { _ in byte() }
        }
        mutating func string() -> String {
            var bytes: [UInt8] = []
            while o < d.count, d[o] != 0 { bytes.append(d[o]); o += 1 }
            o += 1  // skip NUL
            return NCSDaten.cp437(bytes)
        }
    }

    // MARK: name tables (swtfsw/swtpsw: SWT_EINTRAG id 0x01 = identifier(Word) + keyword(String))
    static func keywordMap(_ buf: [UInt8]) -> [UInt16: String] {
        var m: [UInt16: String] = [:]
        for r in records(buf) where r.id == 0x01 {
            var rd = Reader(r.data); let ident = rd.word(); m[ident] = rd.string()
        }
        return m
    }

    // MARK: coding file (.cXX)
    struct Param: Identifiable {
        let id = UUID()
        let block: String      // coding block name (BEZEICHNUNG)
        var blockNumber = 0    // BLOCKNR: which coding block's bytes `byteAddress` indexes (gm5 has 0 and 1)
        let byteAddress: Int   // byte offset within the coding string
        let mask: [UInt8]      // bit mask (one byte for most E46 options)
        let function: UInt16   // FSW code
        var name: String       // resolved FSW keyword (or hex if unknown)
        var value: Int?        // current value from the car, masked and shifted (nil until read)
        /// Named parameter values (PSW) for this option: raw value → keyword ("aktiv", "mls"…).
        var choices: [Int: String] = [:]
        /// The PSW keyword for the current value, if the coding data names it.
        var meaning: String? { value.flatMap { choices[$0] } }
        /// True when this option is a single on/off bit (mask is one power-of-two bit).
        var isFlag: Bool { mask.count == 1 && (mask[0] & (mask[0] &- 1)) == 0 && mask[0] != 0 }
    }

    /// Overlay the car's raw coding bytes onto a block's parameters: for each option, read the
    /// masked, shifted value from `raw` at its byte address. `raw` is the coding bytes of the block
    /// the params belong to (byte 0 = the block's first coding byte).
    static func apply(_ params: [Param], raw: [UInt8], blockBase: Int = 0) -> [Param] {
        params.map { p in
            var p = p
            let start = p.byteAddress - blockBase
            guard start >= 0, p.mask.count > 0, start + p.mask.count <= raw.count else { return p }
            // Combine the masked bytes big-endian (first byte most significant — confirmed on the
            // cluster: KM_SERVICE_INTERVALL `61 A8` = 25,000), then shift past the mask's trailing zeros.
            var field: UInt64 = 0, maskAll: UInt64 = 0
            for k in 0..<p.mask.count {
                field = (field << 8) | UInt64(raw[start + k] & p.mask[k])
                maskAll = (maskAll << 8) | UInt64(p.mask[k])
            }
            let shift = maskAll == 0 ? 0 : maskAll.trailingZeroBitCount
            p.value = Int(field >> UInt64(shift))
            return p
        }
    }

    /// A directly assigned field (PARZUWEISUNG_DIR, record 0x11, "{L}LWW{B}(B)(A)B": block, address,
    /// length, FSW, …). Not a choice: NCS fills it from the car's own data — VIN characters, coding
    /// date, coding index, checksums, vehicle order. Its bytes are PROTECTED: a coding write must
    /// never change them (kmbe46m3.c23 has 89 of these covering 179 bytes; none overlap an option).
    struct Direct {
        let blockNumber: Int
        let byteAddress: Int
        let length: Int
        let function: UInt16
        let name: String
    }

    /// The direct fields of a `.cXX` file.
    static func directFields(_ buf: [UInt8], fsw: [UInt16: String] = [:]) -> [Direct] {
        records(buf).filter { $0.id == 0x11 }.map { r in
            var rd = Reader(r.data)
            let block = Int(rd.longColl(single: true).first ?? 0)
            let address = Int(rd.long())
            let length = max(1, Int(rd.word()))
            let function = rd.word()
            return Direct(blockNumber: block, byteAddress: address, length: length, function: function,
                          name: fsw[function] ?? String(format: "FSW_%04X", function))
        }
    }

    /// Protected byte offsets per coding block, from the file's direct fields.
    static func protectedBytes(_ directs: [Direct]) -> [Int: Set<Int>] {
        var out: [Int: Set<Int>] = [:]
        for d in directs { out[d.blockNumber, default: []].formUnion(d.byteAddress..<(d.byteAddress + d.length)) }
        return out
    }

    /// Whether an option's bytes include any protected byte. A write must refuse such an option.
    static func touchesProtected(_ p: Param, _ protected: [Int: Set<Int>]) -> Bool {
        guard let set = protected[p.blockNumber] else { return false }
        return (p.byteAddress..<(p.byteAddress + max(1, p.mask.count))).contains { set.contains($0) }
    }

    /// The inverse of `apply`: return `raw` with one option set to `value`, or nil if the value
    /// doesn't fit the option's mask or the option lies outside `raw`. Big-endian across the
    /// option's bytes; only bits inside the mask change. Callers still assert the result.
    static func encode(_ p: Param, value: Int, into raw: [UInt8], blockBase: Int = 0) -> [UInt8]? {
        let start = p.byteAddress - blockBase
        let n = p.mask.count
        guard n > 0, n <= 8, start >= 0, start + n <= raw.count, value >= 0 else { return nil }
        var maskAll: UInt64 = 0
        for m in p.mask { maskAll = (maskAll << 8) | UInt64(m) }
        guard maskAll != 0 else { return nil }
        let field = UInt64(value) << UInt64(maskAll.trailingZeroBitCount)
        guard field & ~maskAll == 0, field >> UInt64(maskAll.trailingZeroBitCount) == UInt64(value) else { return nil }
        var out = raw
        for k in 0..<n {
            let shift = UInt64(8 * (n - 1 - k))
            let fieldByte = UInt8((field >> shift) & 0xFF)
            out[start + k] = (raw[start + k] & ~p.mask[k]) | (fieldByte & p.mask[k])
        }
        return out
    }

    /// Overlay several coding blocks: each option reads the bytes of its own block (BLOCKNR), e.g.
    /// the body module's block 0 and block 1 both start at address 0. Blocks not read stay nil.
    static func apply(_ params: [Param], blocks: [Int: [UInt8]]) -> [Param] {
        params.map { p in
            guard let raw = blocks[p.blockNumber] else { return p }
            return apply([p], raw: raw)[0]
        }
    }

    /// Decode a `.cXX` file into its coding parameters, resolving option names via `fsw` and value
    /// names via `psw` (the swtfswNN/swtpswNN pair for this file's SWT index).
    static func decode(_ buf: [UInt8], fsw: [UInt16: String], psw: [UInt16: String] = [:]) -> [Param] {
        // CODIERDATENBLOCK (0x06): block list, address(LongWord), byteadr(Word), name(String).
        // The block's byteadr marks where it starts; following FSW records belong to the most
        // recent block (by file order).
        var currentBlock = ""
        var params: [Param] = []
        for r in records(buf) {
            switch r.id {
            case 0x06:
                var rd = Reader(r.data)
                _ = rd.longColl(single: true)   // block
                _ = rd.long()                   // wortadr
                _ = rd.word()                   // byteadr
                currentBlock = rd.string()
            case 0x12:  // PARZUWEISUNG_FSW: block,address,length,function,index,mask,unit,individual
                var rd = Reader(r.data)
                let blockNumbers = rd.longColl(single: true)
                let address = rd.long()
                _ = rd.word()                   // length
                let function = rd.word()
                _ = rd.charColl(single: true)   // index
                let mask = rd.byteColl(single: false)
                _ = rd.charColl(single: true)   // unit
                _ = rd.byteColl(single: true)   // individual
                let name = fsw[function] ?? String(format: "FSW_%04X", function)
                params.append(Param(block: currentBlock, blockNumber: Int(blockNumbers.first ?? 0),
                                    byteAddress: Int(address), mask: mask, function: function, name: name))
            case 0x10:  // PARZUWEISUNG_PSW1 "W(B)": PSW keyword id + the raw value(s) it stands for,
                        // following the FSW record it belongs to. Multi-byte values are big-endian.
                guard !params.isEmpty else { break }
                var rd = Reader(r.data)
                let pswID = rd.word()
                let bytes = rd.byteColl(single: false)
                guard !bytes.isEmpty, bytes.count <= 8 else { break }
                let v = bytes.reduce(0) { ($0 << 8) | Int($1) }
                if params[params.count - 1].choices[v] == nil {
                    params[params.count - 1].choices[v] = psw[pswID] ?? String(format: "PSW_%04X", pswID)
                }
            default:
                break
            }
        }
        return params
    }

    // MARK: module → coding file

    /// NCS coding-file families for an SGBD, from the E46 chassis folder of SP-DATEN. The link isn't
    /// derivable from the SGBD name (dsc_mk60 → mk60, zke5 → gm5), so map the E46 modules we know.
    /// A module can have several families — the cluster is kmbe46m3 on an M3 and kmb_e46 otherwise —
    /// and the coding index read from the car picks the file (their indexes don't overlap).
    /// Longest prefix wins; falls back to the SGBD name itself.
    static let basenames: [(String, [String])] = [
        ("dsc_mk60", ["mk60"]), ("mk60", ["mk60"]),
        ("zke5", ["gm5"]), ("zke", ["gm5"]), ("gm5", ["gm5"]),   // E46 body module: SGBD zke5 ↔ coding file gm5
        ("ews3", ["ews"]), ("ews", ["ews"]),
        ("kombi46", ["kmbe46m3", "kmb_e46"]), ("kmb", ["kmbe46m3", "kmb_e46"]),
        ("ihka46", ["ihk_e46"]), ("ihkr", ["ihkr_e46"]),
        ("sm46", ["sm_e46"]),
        ("lsz", ["lsz"]), ("lws5", ["lws5"]), ("lws", ["lws5"]),
        ("rdc", ["rdc"]), ("pdc", ["pdc"]),
        ("zae2", ["zae2"]), ("zae", ["zae2"]), ("fgr2", ["fgr2"]), ("fgr", ["fgr2"]),
    ]

    static func codingBasenames(_ sgbd: String) -> [String] {
        let s = sgbd.lowercased()
        if let hit = basenames.filter({ s.hasPrefix($0.0) }).max(by: { $0.0.count < $1.0.count }) {
            return hit.1
        }
        return [s]
    }

    /// Families whose coding lives in the module's EEPROM, read whole with EEPROM_LESEN and
    /// addressed by NCS as plain byte offsets (the E46 cluster).
    static let eepromFamilies: Set<String> = ["kmbe46m3", "kmb_e46"]

    /// The coding index of a coding filename, or nil if it isn't `base.cNN`. The two digits are
    /// HEX — `mk60.c25` is coding index 0x25 = 37, matching the file's own SGID_CODIERINDEX. Handles
    /// the duplicate suffixes a flattened extraction can leave (e.g. `gm5.c011`).
    /// The index of the swtfswNN/swtpswNN name tables a chassis folder uses (E46 = 06). Every file
    /// in one SP-DATEN chassis folder shares its folder's tables, so take the one present; files
    /// from another chassis' folder decode to nonsense with them (and vice versa).
    /// All name-table indexes present (swtfswNN.dat). A proper chassis folder has exactly one; more
    /// than one means folders were mixed and the names can't be trusted, so callers refuse that.
    static func swtIndexes(inFolder files: [String]) -> [Int] {
        Set(files.compactMap { f -> Int? in
            let n = f.lowercased()
            guard n.hasPrefix("swtfsw"), n.hasSuffix(".dat"), n.count == 12 else { return nil }
            return Int(n.dropFirst(6).prefix(2))
        }).sorted()
    }

    static func codingIndex(of filename: String, base: String) -> Int? {
        let n = filename.lowercased()
        let prefix = base + ".c"
        guard n.hasPrefix(prefix) else { return nil }
        return Int(n.dropFirst(prefix.count).prefix(2), radix: 16)
    }

    /// The coding index a `.cXX` file declares it serves (SGID_CODIERINDEX, record id 0x01). This
    /// is what NCS matches the ECU's coding index against; it equals the filename's hex digits.
    static func declaredIndex(_ buf: [UInt8]) -> Int? {
        for r in records(buf) where r.id == 0x01 { return r.data.first.map(Int.init) }
        return nil
    }

    /// Decode a coding file from disk, resolving names with the FSW table at `fswURL`.
    static func decodeFile(_ cxURL: URL, fswURL: URL) -> [Param] {
        guard let cx = try? Data(contentsOf: cxURL), let sw = try? Data(contentsOf: fswURL) else { return [] }
        return decode([UInt8](cx), fsw: keywordMap([UInt8](sw)))
    }

    // Code page 437 high range (0x80–0xFF); low range is ASCII. FSW keywords are ASCII; block
    // names occasionally carry umlauts, so decode them faithfully.
    private static let cp437High: [Character] = Array(
        "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ")
    static func cp437(_ bytes: [UInt8]) -> String {
        var s = ""
        for b in bytes { s.append(b < 0x80 ? Character(UnicodeScalar(b)) : cp437High[Int(b) - 0x80]) }
        return s
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
