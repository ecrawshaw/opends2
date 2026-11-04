import Foundation

/// Which chassis the connected car and the chosen NCS data are, and which writes have been verified
/// on which chassis. A write runs only when the car, the coding data (where the write needs it) and
/// the write's verified list all agree. An SGBD such as `dsc_mk60` is shared by several cars (E46,
/// E85, R50); this gate stops a write verified on one of them from running on another.
extension AppState {
    /// Each coding write path and the chassis it has been verified on, at the car. Adding a chassis
    /// here needs an on-car round-trip test (see AGENTS.md "Coding writes").
    enum WritePath: String { case bodyCoding = "body module coding", dscCoding = "DSC coding", clusterVin = "cluster VIN write" }
    static let verifiedWriteChassis: [WritePath: Set<String>] = [
        .bodyCoding: ["E46"],
        .dscCoding: ["E46"],
        .clusterVin: ["E46"],
    ]

    /// Instrument-cluster SGBD prefix → chassis. The cluster SGBD is chassis-specific, unlike
    /// shared modules such as the DSC. Longest prefix wins.
    static let clusterChassis: [(String, String)] = [
        ("kombi36", "E36"), ("kombi39", "E39"), ("kombi46", "E46"), ("kombi52", "E52"),
        ("kombi65", "E65"), ("kombi85", "E85"), ("kombir50", "R50"),
    ]

    /// The connected car's chassis, from the cluster found in the last scan. nil when no cluster was
    /// found, or when two clusters disagree.
    var carChassis: String? {
        let found = Set(modules.compactMap { m -> String? in
            let s = m.sgbd.lowercased()
            return Self.clusterChassis.filter { s.hasPrefix($0.0) }.max { $0.0.count < $1.0.count }?.1
        })
        return found.count == 1 ? found.first : nil
    }

    /// The chassis of the chosen NCS DATEN folder, from its `<chassis>sgfam.dat` (e.g. e46sgfam.dat).
    /// nil when there is none, or more than one.
    var datenChassis: String? {
        let found = datenFiles.compactMap { n -> String? in
            let l = n.lowercased()
            guard l.hasSuffix("sgfam.dat"), l.count == "e46sgfam.dat".count else { return nil }
            return String(l.prefix(3)).uppercased()
        }
        return found.count == 1 ? found[0] : nil
    }

    /// Why `path` can't write on this car, or nil if the chassis checks pass.
    func chassisWriteBlocker(_ path: WritePath, needsData: Bool = true) -> String? {
        let verified = Self.verifiedWriteChassis[path] ?? []
        let list = verified.sorted().joined(separator: ", ")
        guard let car = carChassis else {
            return "Couldn't tell which car this is (no instrument cluster found in the last scan), so \(path.rawValue) is blocked. Scan the car first."
        }
        guard verified.contains(car) else {
            return "\(path.rawValue.prefix(1).uppercased() + path.rawValue.dropFirst()) is verified only on \(list); this car is an \(car). It stays read-only here until it's verified on an \(car)."
        }
        if needsData {
            guard let data = datenChassis else {
                return "The coding data folder doesn't say which chassis it's for (no single <chassis>sgfam.dat), so changes are blocked. Pick the \(car) folder."
            }
            guard data == car else {
                return "The coding data folder is for an \(data), but this car is an \(car). Pick the \(car) folder."
            }
        }
        return nil
    }
}
