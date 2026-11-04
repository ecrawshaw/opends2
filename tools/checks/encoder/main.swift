import Foundation
let d = URL(fileURLWithPath: NSString(string: "~/Projects/e46diag/ncs-daten").expandingTildeInPath)
func t(_ f: String) -> [UInt16: String] { NCSDaten.keywordMap([UInt8](try! Data(contentsOf: d.appendingPathComponent(f)))) }
func hx(_ s: String) -> [UInt8] { s.split(separator: " ").map { UInt8($0, radix: 16)! } }
let blocks: [Int: [UInt8]] = [
  0: hx("0C 12 11 01 00 C2 17 04 A4 03 FF 03 0F 28 41 A4 00 08 00 00 60 07 10 01 00 02 72 00 00 AA"),
  1: hx("1A 0F 00 55 03 00 00 00 00 3C 00 00 00 69 D7 7C 7C D7 00 00 79 44 00 00 00 00 00 00 00 AA")]
let ps = NCSDaten.apply(NCSDaten.decode([UInt8](try! Data(contentsOf: d.appendingPathComponent("gm5.c04"))), fsw: t("swtfsw06.dat"), psw: t("swtpsw06.dat")), blocks: blocks)
var options = 0, tried = 0, bad = 0, notFit = 0
for p in ps where p.value != nil && p.choices.count > 1 && p.byteAddress + p.mask.count <= 29 {
    options += 1
    let raw = blocks[p.blockNumber]!
    for v in p.choices.keys.sorted() {
        tried += 1
        guard let out = NCSDaten.encode(p, value: v, into: raw) else { notFit += 1; print("does not fit:", p.name, v, p.mask); continue }
        var ok = out[29] == 0xAA && NCSDaten.apply([p], raw: out)[0].value == v
        for i in 0..<30 {
            let inSpan = i >= p.byteAddress && i < p.byteAddress + p.mask.count
            let m: UInt8 = inSpan ? p.mask[i - p.byteAddress] : 0
            if (out[i] ^ raw[i]) & ~m != 0 { ok = false }
        }
        // every OTHER option in the same block must decode unchanged
        for q in ps where q.blockNumber == p.blockNumber && q.id != p.id && q.value != nil {
            let overlaps = (q.byteAddress..<(q.byteAddress + q.mask.count)).contains { i in
                i >= p.byteAddress && i < p.byteAddress + p.mask.count && (q.mask[i - q.byteAddress] & p.mask[i - p.byteAddress]) != 0 }
            if !overlaps && NCSDaten.apply([q], raw: out)[0].value != q.value { ok = false; print("side effect on", q.name, "when setting", p.name) }
        }
        if !ok { bad += 1; print("BAD:", p.name, v) }
    }
}
print("options changeable: \(options) | encodings tried: \(tried) | failed checks: \(bad) | values not fitting mask: \(notFit)")
