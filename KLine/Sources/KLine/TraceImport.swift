import Foundation

/// Reads an EDIABAS/EdiabasLib interface trace (ifh.trc) recorded on a real car and pairs each
/// request with the module's answer. This is the raw material for writing module definitions.
public struct TraceExchange: Sendable {
    public let job: String?
    public let request: [UInt8]
    public let response: [UInt8]?
}

public enum TraceImport {
    public static func exchanges(fromTrace text: String) -> [TraceExchange] {
        var out: [TraceExchange] = []
        var job: String?
        var pending: [UInt8]?
        func bytes(after marker: String, in line: String) -> [UInt8]? {
            guard let r = line.range(of: marker) else { return nil }
            return [UInt8](hex: String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if let r = line.range(of: "executeJob('") {
                // executeJob('mss54ds0.prg'): 'STATUS_UBATT' ''
                let rest = line[r.upperBound...]
                let parts = rest.components(separatedBy: "'")
                // INITIALISIERUNG is EDIABAS's automatic set-up call inside the real job: keep the outer name
                if parts.count > 2, parts[2] != "INITIALISIERUNG" { job = "\(parts[0].replacingOccurrences(of: ".prg", with: "")) \(parts[2])" }
            } else if let b = bytes(after: "(Send): ", in: line) ?? bytes(after: "(Send sim): ", in: line) {
                if let p = pending { out.append(TraceExchange(job: job, request: p, response: nil)) }
                pending = b
            } else if let b = bytes(after: "(Rec ): ", in: line) ?? bytes(after: "(Rec sim interface): ", in: line) {
                if let p = pending { out.append(TraceExchange(job: job, request: p, response: b)); pending = nil }
            }
        }
        if let p = pending { out.append(TraceExchange(job: job, request: p, response: nil)) }
        return out
    }
}
