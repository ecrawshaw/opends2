import Foundation
import SwiftUI

/// One live value to poll: an MSS54 STATUS job and how to label it
struct Signal: Identifiable, Hashable {
    var id: String { job }
    let job: String
    let label: String
}

enum Signals {
    static let dashboard: [Signal] = [
        Signal(job: "STATUS_MOTORDREHZAHL", label: "Engine speed"),
        Signal(job: "STATUS_MOTORTEMPERATUR", label: "Coolant temp"),
        Signal(job: "STATUS_OEL_TEMPERATUR", label: "Oil temp"),
        Signal(job: "STATUS_KUEHLW_AUSL_TEMPERATUR", label: "Radiator outlet temp"),
        Signal(job: "STATUS_AN_LUFTTEMPERATUR", label: "Intake air temp"),
        Signal(job: "STATUS_UBATT", label: "Battery voltage"),
        Signal(job: "STATUS_DKP_WINKEL", label: "Throttle angle"),
        Signal(job: "STATUS_LAST", label: "Engine load"),
        Signal(job: "STATUS_LMM_MASSE", label: "Air mass"),
        Signal(job: "STATUS_GESCHWINDIGKEIT", label: "Road speed"),
        Signal(job: "STATUS_EINSPRITZZEIT", label: "Injection time (cyl 1)"),
        Signal(job: "STATUS_TZ1", label: "Ignition timing (cyl 1)"),
        Signal(job: "STATUS_LAMBDA_INTEGRATOR_1", label: "Lambda control bank 1"),
        Signal(job: "STATUS_LAMBDA_INTEGRATOR_2", label: "Lambda control bank 2"),
        Signal(job: "STATUS_ADD", label: "Fuel trim additive bank 1"),
        Signal(job: "STATUS_ADD_2", label: "Fuel trim additive bank 2"),
        Signal(job: "STATUS_MUL", label: "Fuel trim multiplicative bank 1"),
        Signal(job: "STATUS_MUL_2", label: "Fuel trim multiplicative bank 2"),
    ]
    static let dashboardDefault: Set<String> = [
        "STATUS_MOTORDREHZAHL", "STATUS_MOTORTEMPERATUR", "STATUS_OEL_TEMPERATUR", "STATUS_UBATT",
        "STATUS_LAMBDA_INTEGRATOR_1", "STATUS_LAMBDA_INTEGRATOR_2",
    ]

    static let misfire = ["STATUS_SYSTEMCHECK_LAUFUNRUHE", "LESEN_SYSTEMCHECK_LAUFUNRUHE"]

    /// Target and actual cam position for each VANOS unit. The exhaust actual values come from jobs named
    /// STATUS_VANOS_NW_LAGE_EINLASS_BANK_n, whose own comments say they are the exhaust (AVANOS) actuals.
    struct VanosUnit: Identifiable {
        var id: String { key }
        let key: String, label: String, target: String, actual: String
    }
    static let vanos: [VanosUnit] = [
        VanosUnit(key: "EVANOS1", label: "Intake bank 1", target: "STATUS_EVANOS1_SOLL", actual: "STATUS_EVANOS1_IST"),
        VanosUnit(key: "EVANOS2", label: "Intake bank 2", target: "STATUS_EVANOS2_SOLL", actual: "STATUS_EVANOS2_IST"),
        VanosUnit(key: "AVANOS1", label: "Exhaust bank 1", target: "STATUS_AVANOS1_SOLL", actual: "STATUS_VANOS_NW_LAGE_EINLASS_BANK_1"),
        VanosUnit(key: "AVANOS2", label: "Exhaust bank 2", target: "STATUS_AVANOS2_SOLL", actual: "STATUS_VANOS_NW_LAGE_EINLASS_BANK_2"),
    ]
}

struct Sample: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

/// Polls a set of status jobs on one module over and over, keeping a short history for the charts.
@MainActor
final class LiveMonitor: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var jobs: [String] = []
    @Published private(set) var latest: [String: ResultSet] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var samples: [String: [Sample]] = [:]
    @Published private(set) var cycleSeconds: Double?
    @Published var dashboardSelection: Set<String> = Signals.dashboardDefault

    static let historyLength = 150
    var poll: ((String, [String]) async throws -> [String: Any])?
    private var task: Task<Void, Never>?

    func start(sgbd: String, jobs: [String]) {
        stop()
        self.jobs = jobs
        samples = [:]
        keyed = [:]
        latest = [:]
        errors = [:]
        running = true
        task = Task { [weak self] in
            while let self, !Task.isCancelled, self.running {
                let began = Date()
                do {
                    guard let poll = self.poll else { break }
                    let result = try await poll(sgbd, jobs)
                    self.ingest(result, at: Date())
                    // Every job failing usually means no cable or ignition off: back off instead of hammering the port
                    if !jobs.isEmpty, jobs.allSatisfy({ self.errors[$0] != nil }) {
                        self.errors["_poll"] = "No values came back. Check the ignition and the cable."
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                } catch {
                    self.errors["_poll"] = error.localizedDescription
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                self.cycleSeconds = Date().timeIntervalSince(began)
            }
        }
    }

    func stop() {
        running = false
        task?.cancel()
        task = nil
    }

    /// Stop and wait for the in-flight poll to finish, so the next request has the cable to itself
    func stopAndWait() async {
        let t = task
        stop()
        await t?.value
    }

    func ingest(_ result: [String: Any], at time: Date) {
        errors["_poll"] = nil
        for (job, value) in result {
            if let err = (value as? [String: Any])?["error"] as? String {
                errors[job] = Engine.shortError(err)
                continue
            }
            guard let set = value as? ResultSet else { continue }
            errors[job] = nil
            latest[job] = set
            for (k, raw) in set {
                guard let d = LiveMonitor.number(raw) else { continue }
                var list = keyed[job + "/" + k] ?? []
                list.append(d)
                if list.count > LiveMonitor.historyLength { list.removeFirst() }
                keyed[job + "/" + k] = list
            }
            if let v = LiveMonitor.mainValue(set).number {
                var list = samples[job] ?? []
                list.append(Sample(time: time, value: v))
                if list.count > LiveMonitor.historyLength { list.removeFirst(list.count - LiveMonitor.historyLength) }
                samples[job] = list
            }
        }
    }

    /// The main reading of a STATUS job: its STAT_…_WERT result (or any …_WERT), with the unit beside it
    static func mainValue(_ set: ResultSet?) -> (number: Double?, text: String, unit: String) {
        guard let set else { return (nil, "–", "") }
        let keys = set.keys.sorted()
        guard let key = keys.first(where: { $0.hasPrefix("STAT_") && $0.hasSuffix("_WERT") })
            ?? keys.first(where: { $0.hasSuffix("_WERT") }) else { return (nil, "–", "") }
        let base = String(key.dropLast(5))
        let unit = Translate.unit(AppState.string(set[base + "_EINH"]))
        return Measure.convert(number: number(set[key]), text: AppState.string(set[key]), unit: unit)
    }

    static func number(_ v: Any?) -> Double? {
        switch v {
        case let d as Double: return d
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    func value(_ job: String) -> (number: Double?, text: String, unit: String) { LiveMonitor.mainValue(latest[job]) }

    /// Average of the last few readings of one result, to steady jumpy values like per-cylinder roughness
    func average(_ job: String, key: String, last n: Int = 10) -> Double? {
        guard let list = keyed[job + "/" + key], !list.isEmpty else { return nil }
        let tail = list.suffix(n)
        return tail.reduce(0, +) / Double(tail.count)
    }

    /// Every numeric result of every polled job, newest last
    @Published private(set) var keyed: [String: [Double]] = [:]
}
