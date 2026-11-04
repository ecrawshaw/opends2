import Foundation

/// One saved read of one module: kept in ~/Library/Application Support/OpenDS2/history
struct HistoryEntry: Codable, Identifiable, Hashable {
    struct FaultRecord: Codable, Hashable {
        let code: String
        let text: String
    }
    var id: String { "\(sgbd)-\(date.timeIntervalSince1970)" }
    let date: Date
    let sgbd: String
    let title: String
    let faults: [FaultRecord]
    let infoMemory: [FaultRecord]
    /// "JOB/NAME" → "value unit"
    let values: [String: String]
    var note: String?

    var label: String {
        "\(date.formatted(date: .abbreviated, time: .shortened)) · \(title) · \(faults.count) fault\(faults.count == 1 ? "" : "s")"
    }
}

/// Differences between two reads of the same module
struct HistoryDiff {
    let newFaults: [HistoryEntry.FaultRecord]
    let goneFaults: [HistoryEntry.FaultRecord]
    let stillFaults: [HistoryEntry.FaultRecord]
    let changedValues: [(name: String, before: String, after: String)]
}

enum HistoryStore {
    static var directory: URL {
        let dir = AppPaths.support.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @discardableResult
    static func save(_ module: Module, _ report: ModuleReport, note: String? = nil) -> HistoryEntry {
        let entry = HistoryEntry(
            date: Date(), sgbd: module.sgbd, title: module.title,
            faults: report.faults.map { .init(code: $0.code, text: $0.text) },
            infoMemory: report.infoMemory.map { .init(code: $0.code, text: $0.text) },
            values: Dictionary(report.live.map { ("\($0.job)/\($0.name)", [$0.value, $0.unit].filter { !$0.isEmpty }.joined(separator: " ")) },
                               uniquingKeysWith: { a, _ in a }),
            note: note)
        let name = "\(Int(entry.date.timeIntervalSince1970))-\(module.sgbd).json"
        if let data = try? encoder.encode(entry) {
            try? data.write(to: directory.appendingPathComponent(name))
        }
        return entry
    }

    static func load() -> [HistoryEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(HistoryEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    static func diff(from a: HistoryEntry, to b: HistoryEntry) -> HistoryDiff {
        let before = Set(a.faults.map(\.code)), after = Set(b.faults.map(\.code))
        let changed = Set(a.values.keys).union(b.values.keys).sorted().compactMap { key -> (String, String, String)? in
            let x = a.values[key] ?? "–", y = b.values[key] ?? "–"
            return x == y ? nil : (key.replacingOccurrences(of: "STATUS_", with: ""), x, y)
        }
        return HistoryDiff(
            newFaults: b.faults.filter { !before.contains($0.code) },
            goneFaults: a.faults.filter { !after.contains($0.code) },
            stillFaults: b.faults.filter { before.contains($0.code) },
            changedValues: changed.map { (name: $0.0, before: $0.1, after: $0.2) })
    }

    /// How often a fault code has turned up in earlier reads of this module
    static func occurrences(of code: String, sgbd: String, in history: [HistoryEntry]) -> (seen: Int, reads: Int, first: Date?) {
        let reads = history.filter { $0.sgbd == sgbd }
        let hits = reads.filter { $0.faults.contains { $0.code == code } }
        return (hits.count, reads.count, hits.map(\.date).min())
    }
}
