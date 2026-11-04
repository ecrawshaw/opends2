import Foundation
import KLine
import Observation

/// Everything the screens show. Talks to the car through `CarLink` and to the adapter's settings
/// over HTTP.
@MainActor @Observable
final class AppModel {
    // MARK: adapter

    /// Empty: try obdadapter.local (adapter on the same WiFi), then 192.168.4.1 (phone on the
    /// adapter's own network). Otherwise "host" or "host:kline:can:http", e.g. the Mac's fake adapter.
    var customAddress: String = UserDefaults.standard.string(forKey: "adapterAddress") ?? "" {
        didSet {
            UserDefaults.standard.set(customAddress, forKey: "adapterAddress")
            address = nil
            adapter = nil
        }
    }
    private(set) var address: AdapterAddress?
    private(set) var adapter: TcpLink.Status?
    private(set) var adapterProblem: String?
    private(set) var findingAdapter = false
    private(set) var networks: AdapterNetworks?

    var candidates: [String] {
        let custom = customAddress.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? ["obdadapter.local", AdapterAddress.defaultHost] : [custom]
    }

    /// Find whichever address answers and read its status
    @discardableResult
    func findAdapter() async -> Bool {
        findingAdapter = true
        defer { findingAdapter = false }
        var last = "No adapter found"
        for spec in [address].compactMap({ $0 }) + candidates.map(AdapterAddress.init(spec:)) {
            do {
                adapter = try await AdapterHTTP.status(spec)
                address = spec
                adapterProblem = nil
                return true
            } catch { last = "\(spec.host): \(error.localizedDescription)" }
        }
        address = nil
        adapter = nil
        adapterProblem = last
        return false
    }

    func loadNetworks() async {
        guard let a = address else { return }
        networks = try? JSONDecoder().decode(AdapterNetworks.self, from: await AdapterHTTP.get(a, "/wifi"))
    }

    func addNetwork(ssid: String, password: String) async throws {
        guard let a = address else { throw AdapterError("adapter not found") }
        let d = try await AdapterHTTP.get(a, "/wifi?" + AdapterHTTP.query(["ssid": ssid, "pass": password]))
        networks = try? JSONDecoder().decode(AdapterNetworks.self, from: d)
    }

    func forgetNetwork(_ ssid: String) async throws {
        guard let a = address else { throw AdapterError("adapter not found") }
        let d = try await AdapterHTTP.get(a, "/wifi?" + AdapterHTTP.query(["forget": ssid]))
        networks = try? JSONDecoder().decode(AdapterNetworks.self, from: d)
    }

    func setSleep(minutes: Int) async throws {
        guard let a = address else { throw AdapterError("adapter not found") }
        _ = try await AdapterHTTP.get(a, "/power?sleep_min=\(minutes)")
        await findAdapter()
    }

    // MARK: car

    enum CarState: Equatable { case notConnected, connecting, connected, failed(String) }
    private(set) var car: CarState = .notConnected
    private(set) var progress: String?
    private(set) var protocolName: String?
    private(set) var vin: String?
    private(set) var readiness: [Readiness] = []
    private(set) var codes: [OBD.DTCKind: [TroubleCode]] = [:]
    private(set) var reading = false
    var lastError: String?

    struct TroubleCode: Identifiable, Hashable {
        let code: String
        let ecu: String
        var id: String { ecu + code }
    }

    private let link = CarLink()

    func connectCar() async {
        guard car != .connecting else { return }
        car = .connecting
        progress = "Looking for the adapter"
        if address == nil { await findAdapter() }
        guard let a = address else {
            car = .failed(adapterProblem ?? "No adapter found")
            return
        }
        do {
            protocolName = try await link.connect(a) { msg in Task { @MainActor in self.progress = msg } }
            car = .connected
            await readCar()
        } catch {
            car = .failed("\(error)")
        }
        progress = nil
    }

    func disconnectCar() {
        stopLive()
        link.disconnect()
        car = .notConnected
        protocolName = nil
        supported = []
        values = [:]
    }

    /// VIN, check-engine light, readiness and all three kinds of trouble codes
    func readCar() async {
        reading = true
        defer { reading = false }
        do {
            vin = try await link.with { try $0.vin() }
            readiness = try await link.with { try $0.readiness() }
            var found: [OBD.DTCKind: [TroubleCode]] = [:]
            for kind in [OBD.DTCKind.stored, .pending, .permanent] {
                // Older cars don't support pending (07) or permanent (0A) codes; that's not an error
                let byECU = (try? await link.with { try $0.dtcs(kind) }) ?? [:]
                found[kind] = byECU.flatMap { ecu, list in list.map { TroubleCode(code: $0, ecu: ecu) } }.sorted { $0.code < $1.code }
            }
            codes = found
        } catch { lost(error) }
    }

    func clearCodes() async {
        do {
            let ok = try await link.with { try $0.clearDTCs() }
            if !ok { lastError = "The car didn't confirm the clear. Ignition on, engine off, then try again." }
            await readCar()
        } catch { lost(error) }
    }

    private func lost(_ error: Error) {
        lastError = "\(error)"
        if error is TcpError || error is CarLink.NotConnected {
            stopLive()
            car = .failed("Lost the connection: \(error)")
        }
    }

    // MARK: live data

    private(set) var supported: [UInt8] = []
    private(set) var values: [String: PIDValue] = [:]
    private(set) var liveRunning = false
    var favoritesOnly = UserDefaults.standard.bool(forKey: "favoritesOnly") {
        didSet { UserDefaults.standard.set(favoritesOnly, forKey: "favoritesOnly") }
    }
    private(set) var favorites: Set<UInt8> = Set((UserDefaults.standard.array(forKey: "favorites") as? [Int] ?? []).map(UInt8.init))
    private var liveTask: Task<Void, Never>?

    func toggleFavorite(_ pid: UInt8) {
        if favorites.contains(pid) { favorites.remove(pid) } else { favorites.insert(pid) }
        UserDefaults.standard.set(favorites.map(Int.init), forKey: "favorites")
    }

    /// What one polling round reads. Each value is a round trip to the car, so on slow K-line cars
    /// a few favorites update much faster than everything.
    var pollList: [UInt8] {
        let favs = supported.filter(favorites.contains)
        return favoritesOnly && !favs.isEmpty ? favs : supported
    }

    func startLive() {
        guard car == .connected, liveTask == nil else { return }
        liveRunning = true
        liveTask = Task {
            defer { liveRunning = false; liveTask = nil }
            do {
                if supported.isEmpty {
                    supported = try await link.with { o in
                        Set(try o.supportedPIDs().values.flatMap { $0 })
                            .filter { $0 != 0x01 && OBDPIDs.table[$0] != nil }  // 01 is the readiness status, shown on the Car tab
                            .sorted()
                    }
                }
                while !Task.isCancelled {
                    let list = pollList
                    if list.isEmpty { try await Task.sleep(for: .seconds(1)); continue }
                    for pid in list {
                        if Task.isCancelled { break }
                        for v in try await link.with({ try $0.read(pid) }) { values["\(v.pid)|\(v.ecu)"] = v }
                    }
                }
            } catch is CancellationError {
            } catch { lost(error) }
        }
    }

    func stopLive() {
        liveTask?.cancel()
        liveTask = nil
    }

    /// Latest values in PID order
    var liveRows: [PIDValue] {
        values.values.filter { pollList.contains($0.pid) }.sorted { ($0.pid, $0.ecu) < ($1.pid, $1.ecu) }
    }
}

extension OBD.DTCKind {
    var title: String {
        switch self {
        case .stored: "Stored codes"
        case .pending: "Pending codes"
        case .permanent: "Permanent codes"
        }
    }

    var explanation: String {
        switch self {
        case .stored: "Faults confirmed by the engine computer. These turn the check-engine light on."
        case .pending: "Faults seen once but not yet confirmed. They become stored if they happen again."
        case .permanent: "Can't be cleared with a scan tool. They go away by themselves once the car has re-tested the fault and found it fixed."
        }
    }
}

enum DTCInfo {
    /// What a code's first characters say about it (descriptions for individual codes come later)
    static func category(_ code: String) -> String {
        let chars = Array(code)
        guard chars.count == 5 else { return "" }
        let system = ["P": "Powertrain", "C": "Chassis", "B": "Body", "U": "Network"][String(chars[0])] ?? ""
        let generic = chars[1] == "0" || (chars[0] == "P" && chars[1] == "2") || (chars[0] == "P" && chars[1] == "3" && chars[2] >= "4")
        var area = ""
        if chars[0] == "P" {
            area = ["1": "fuel and air metering", "2": "fuel and air metering (injectors)", "3": "ignition and misfire",
                    "4": "emissions controls", "5": "speed, idle control", "6": "computer and outputs",
                    "7": "transmission", "8": "transmission", "0": "fuel, air and emissions"][String(chars[2])] ?? ""
        }
        return [system, generic ? "generic" : "manufacturer-specific", area].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension PIDValue {
    var valueText: String {
        if value == value.rounded() && abs(value) < 1e9 { return String(Int(value)) }
        return abs(value) >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
