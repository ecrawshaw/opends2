import Charts
import SwiftUI

// Screens for the S54 engine computer (MSS54): live dashboard, misfires, VANOS and component tests,
// plus the Actions tab every module gets and the History / compare sheet.

extension Module {
    var isEngine: Bool { sgbd.lowercased().hasPrefix("mss54") }
    /// Teves MK60 ABS/DSC (E46 incl. M3, E85, R50): has the bleeding routines
    var isDSCMK60: Bool { sgbd.lowercased() == "dsc_mk60" }
    var isCluster: Bool { sgbd.lowercased().hasPrefix("kombi") }
}

/// Start / stop bar shared by the live screens
struct LiveControls: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var live: LiveMonitor
    let module: Module
    let jobs: [String]
    let hint: String

    var isMine: Bool { live.running && live.jobs == jobs }

    var body: some View {
        HStack {
            Button {
                if isMine { live.stop() } else { live.start(sgbd: module.sgbd, jobs: jobs) }
            } label: {
                Label(isMine ? "Stop" : "Start live", systemImage: isMine ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.busy || !state.configured || jobs.isEmpty)
            if isMine, let s = live.cycleSeconds {
                Text(String(format: "refresh every %.1f s", s)).font(.caption).foregroundStyle(.secondary)
            }
            if let err = live.errors["_poll"] {
                Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption).lineLimit(1)
            }
            Spacer()
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}

// MARK: 1. Dashboard

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var live: LiveMonitor
    let module: Module

    var selected: [Signal] { Signals.dashboard.filter { live.dashboardSelection.contains($0.job) } }

    var body: some View {
        VStack(spacing: 0) {
            LiveControls(live: live, module: module, jobs: selected.map(\.job),
                         hint: "Fewer values refresh faster (the K-line is slow).")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Signals.dashboard) { signal in
                        let on = live.dashboardSelection.contains(signal.job)
                        Button(signal.label) {
                            if on { live.dashboardSelection.remove(signal.job) } else { live.dashboardSelection.insert(signal.job) }
                            if live.running { live.start(sgbd: module.sgbd, jobs: selected.map(\.job)) }
                        }
                        .buttonStyle(.bordered).tint(on ? .accentColor : .secondary).controlSize(.small)
                    }
                }.padding(.horizontal)
            }
            Divider().padding(.top, 8)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(selected) { SignalCard(live: live, signal: $0) }
                }.padding()
            }
        }
    }
}

struct SignalCard: View {
    @ObservedObject var live: LiveMonitor
    let signal: Signal

    var body: some View {
        let v = live.value(signal.job)
        VStack(alignment: .leading, spacing: 6) {
            Text(signal.label).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v.text).font(.title2.monospacedDigit().bold())
                Text(v.unit).foregroundStyle(.secondary)
            }
            if let err = live.errors[signal.job] {
                Text(err).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            Chart(live.samples[signal.job] ?? []) {
                LineMark(x: .value("Time", $0.time), y: .value(signal.label, $0.value))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 80)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: 2. Misfires

struct MisfireView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var live: LiveMonitor
    let module: Module

    struct Bar: Identifiable {
        var id: Int { cylinder }
        let cylinder: Int
        let value: Double
    }

    func bars(_ job: String, _ prefix: String) -> [Bar] {
        (1...6).compactMap { n in live.average(job, key: "\(prefix)_ZYL\(n)_WERT").map { Bar(cylinder: n, value: $0) } }
    }

    var body: some View {
        let rough = bars("STATUS_SYSTEMCHECK_LAUFUNRUHE", "STAT_SYSTEMCHECK_LAUFUNRUHE")
        let segment = bars("LESEN_SYSTEMCHECK_LAUFUNRUHE", "LESEN_SYSTEMCHECK_LAUFUNRUHE")
        let worst = rough.max { abs($0.value) < abs($1.value) }?.cylinder
        let misfireFaults = (state.reports[module.sgbd]?.faults ?? []).filter { $0.original.contains("Aussetzer") || $0.text.contains("Misfire") }
        VStack(spacing: 0) {
            LiveControls(live: live, module: module, jobs: Signals.misfire, hint: "Engine idling and warm. Values are averaged over the last 10 readings.")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Running roughness per cylinder (cylinders numbered 1–6 front to back, not firing order)") {
                        if rough.isEmpty {
                            Text("Start live to measure.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            Chart(rough) { bar in
                                BarMark(x: .value("Cylinder", "Cyl \(bar.cylinder)"), y: .value("Roughness", bar.value))
                                    .foregroundStyle(bar.cylinder == worst ? Color.red : Color.accentColor)
                            }
                            .frame(height: 200)
                            Text("A healthy engine shows all six bars close together. One bar standing well clear of the rest is the cylinder to look at: swap its coil with a neighbour and see whether the bar moves.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !segment.isEmpty {
                        GroupBox("Crank segment time deviation (raw)") {
                            Chart(segment) { BarMark(x: .value("Cylinder", "Cyl \($0.cylinder)"), y: .value("Deviation", $0.value)) }
                                .frame(height: 140)
                        }
                    }
                    GroupBox("Misfire faults stored in the engine computer") {
                        if state.reports[module.sgbd] == nil {
                            Text("Read the module to check.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        } else if misfireFaults.isEmpty {
                            Label("None", systemImage: "checkmark.circle").foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(misfireFaults) { Text("\($0.code)  \($0.text)").frame(maxWidth: .infinity, alignment: .leading) }
                        }
                    }
                }.padding()
            }
        }
    }
}

// MARK: 3. VANOS

struct VanosView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var live: LiveMonitor
    let module: Module

    static let jobs = Signals.vanos.flatMap { [$0.target, $0.actual] }

    struct Point: Identifiable {
        let id = UUID()
        let time: Date
        let value: Double
        let series: String
    }

    var body: some View {
        VStack(spacing: 0) {
            LiveControls(live: live, module: module, jobs: VanosView.jobs, hint: "Engine running and warm. Actual should follow target closely.")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            Text("Unit").bold(); Text("Target").bold(); Text("Actual").bold(); Text("Difference").bold()
                        }
                        Divider()
                        ForEach(Signals.vanos) { unit in
                            let t = live.value(unit.target), a = live.value(unit.actual)
                            let diff = (t.number != nil && a.number != nil) ? a.number! - t.number! : nil
                            GridRow {
                                Text(unit.label)
                                Text("\(t.text) \(t.unit)").monospacedDigit()
                                Text("\(a.text) \(a.unit)").monospacedDigit()
                                Text(diff.map { String(format: "%+.1f", $0) } ?? "–").monospacedDigit()
                                    .foregroundStyle(diff.map { abs($0) > 5 ? Color.orange : Color.primary } ?? .secondary)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                        ForEach(Signals.vanos) { unit in
                            let points = (live.samples[unit.target] ?? []).map { Point(time: $0.time, value: $0.value, series: "Target") }
                                + (live.samples[unit.actual] ?? []).map { Point(time: $0.time, value: $0.value, series: "Actual") }
                            VStack(alignment: .leading) {
                                Text(unit.label).font(.callout).foregroundStyle(.secondary)
                                Chart(points) {
                                    LineMark(x: .value("Time", $0.time), y: .value("Angle", $0.value))
                                        .foregroundStyle(by: .value("Series", $0.series))
                                }
                                .chartXAxis(.hidden)
                                .chartYScale(domain: .automatic(includesZero: false))
                                .frame(height: 110)
                            }
                            .padding(12)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Text("Orange difference: more than 5° from target. A difference that stays large while the engine is steady points at that unit (solenoid, sensor, or the VANOS itself).")
                        .font(.caption).foregroundStyle(.secondary)
                    GroupBox("VANOS tests (engine computer's built-in checks)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Engine running, warm, idling, car stationary. The engine computer refuses a test when its conditions aren't met; the reason shows in the log below.")
                                .font(.caption).foregroundStyle(.secondary)
                            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                                ForEach(Signals.vanos) { unit in
                                    GridRow {
                                        Text(unit.label)
                                        ForEach(ComponentTest.vanos(unit.key)) { test in
                                            Button(test.short) { state.runTest(test, on: module) }
                                                .disabled(state.busy || !state.configured)
                                        }
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LogList()
                }.padding()
            }
        }
    }
}

// MARK: 8. Component tests

struct ComponentTest: Identifiable {
    var id: String { job + args }
    let title: String
    let short: String
    let job: String
    var args: String = ""
    let conditions: String

    static let engineIdleNote = "What the test does is decided by the engine computer's built-in routine; watch and listen for a change."

    static func vanos(_ unit: String) -> [ComponentTest] {
        let name = Signals.vanos.first { $0.key == unit }?.label ?? unit
        let cond = "Engine running, warm, idling; car stationary in neutral with the handbrake on."
        return [
            ComponentTest(title: "\(name): adjust time", short: "Adjust time", job: "STEUERN_\(unit)_VERSTELLZEIT",
                          conditions: "\(cond) Measures how long the cam takes to move between its end stops."),
            ComponentTest(title: "\(name): leak test", short: "Leak test", job: "STEUERN_\(unit)_DICHTHEIT",
                          conditions: "\(cond) Checks whether the unit holds its position (internal leakage)."),
            ComponentTest(title: "\(name): advance stop", short: "Advance stop", job: "STEUERN_\(unit)_FRUEHANSCHLAG",
                          conditions: "\(cond) Moves the cam to its fully-advanced stop and reports target vs actual."),
            ComponentTest(title: "\(name): retard stop", short: "Retard stop", job: "STEUERN_\(unit)_SPAETANSCHLAG",
                          conditions: "\(cond) Moves the cam to its fully-retarded stop and reports target vs actual."),
        ]
    }

    static let coils = (1...6).map {
        ComponentTest(title: "Ignition coil \($0)", short: "Cyl \($0)", job: "STEUERN_ZS\($0)",
                      conditions: "Engine idling. Drives ignition coil \($0). \(engineIdleNote)")
    }
    static let injectors = (1...6).map {
        ComponentTest(title: "Injector \($0)", short: "Cyl \($0)", job: "STEUERN_EV\($0)",
                      conditions: "Engine idling. Drives injector \($0). Don't repeat this with the engine off: it could put fuel into a stopped cylinder. \(engineIdleNote)")
    }
    static let other: [ComponentTest] = [
        ComponentTest(title: "Radiator fan", short: "Fan", job: "STEUERN_E_LUEFTER",
                      conditions: "Ignition on. Keep hands, tools and clothing clear of the fan."),
        ComponentTest(title: "Fuel pump on", short: "Pump on", job: "STEUERN_EKP",
                      conditions: "Ignition on, engine off. You should hear the fuel pump run. No fuel lines open."),
        ComponentTest(title: "Fuel pump off", short: "Pump off", job: "STEUERN_EKP_AUS",
                      conditions: "Switches the fuel pump relay off. With the engine running this stalls it."),
        ComponentTest(title: "Secondary air check: start", short: "Start", job: "START_SYSTEMCHECK_SEK_LUFT",
                      conditions: "Engine running. Starts the engine computer's secondary air check; read the result after about a minute."),
        ComponentTest(title: "Secondary air check: result", short: "Result", job: "LESEN_SYSTEMCHECK_SEK_LUFT",
                      conditions: "Reads the result of the secondary air check."),
        ComponentTest(title: "Secondary air check: stop", short: "Stop", job: "STOP_SYSTEMCHECK_SEK_LUFT",
                      conditions: "Stops the secondary air check."),
        ComponentTest(title: "Tank leak check: start", short: "Start", job: "START_SYSTEMCHECK_DMTL",
                      conditions: "Ignition on, engine off, fuel cap tight. Starts the engine computer's tank leak check; it takes a few minutes. Only works if the car has the electric leak-check pump (DMTL)."),
        ComponentTest(title: "Tank leak check: result", short: "Result", job: "LESEN_SYSTEMCHECK_DMTL",
                      conditions: "Reads the result of the tank leak check."),
    ]
}

struct TestsView: View {
    @EnvironmentObject var state: AppState
    let module: Module

    func row(_ label: String, _ tests: [ComponentTest]) -> some View {
        GridRow {
            Text(label).bold()
            HStack {
                ForEach(tests) { test in
                    Button(test.short) { state.runTest(test, on: module) }.disabled(state.busy || !state.configured)
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("These tests switch real parts on. Each one asks for confirmation and tells you the conditions first. There is a \(Int(AppState.testCooldown)) s pause between tests.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    row("Ignition coils", ComponentTest.coils)
                    row("Injectors", ComponentTest.injectors)
                    row("Cooling / fuel", Array(ComponentTest.other[0...2]))
                    row("Secondary air", Array(ComponentTest.other[3...5]))
                    row("Tank leak", Array(ComponentTest.other[6...7]))
                }
                LogList()
            }.padding()
        }
    }
}

// MARK: 6, 7, 9. Actions

struct ActionsView: View {
    @EnvironmentObject var state: AppState
    let module: Module

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Fault memory") {
                    HStack {
                        Text("Clears this module's stored faults. It's read and saved to History first.")
                        Spacer()
                        Button("Clear faults…") { state.clearFaults(module) }.disabled(state.busy || !state.configured)
                    }.padding(4)
                }
                if module.isEngine {
                    GroupBox("Adaptations") {
                        HStack {
                            Text("Clears learned fuel trims, idle and throttle values. Use after replacing related parts.")
                            Spacer()
                            Button("Reset adaptations…") { state.resetAdaptations(module) }.disabled(state.busy || !state.configured)
                        }.padding(4)
                    }
                }
                if module.isCluster {
                    GroupBox("Service indicator") {
                        HStack {
                            Text("Ignition on, engine off.")
                            Spacer()
                            ForEach(AppState.ServiceReset.allCases) { kind in
                                Button("\(kind.label)…") { state.serviceReset(module, kind) }.disabled(state.busy || !state.configured)
                            }
                        }.padding(4)
                    }
                }
                if module.isDSCMK60 {
                    GroupBox("Brake bleeding (ABS/DSC unit)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("For air trapped inside the ABS/DSC unit (after it was replaced dry, or the reservoir ran empty). Bleed the brakes the normal way first, then run these with the bleed screws open on the wheels being cycled. Each run is BMW's own routine from the DSC unit's file: it holds two wheels shut and runs the pump and valves through the other two for about 10 seconds.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                ForEach(AppState.BleedRoutine.allCases) { routine in
                                    Button("\(routine.title)…") { state.runBleed(routine, on: module) }
                                        .disabled(state.busy || !state.configured || state.bleedCoolingDown)
                                        .help(routine.detail)
                                }
                            }
                            if state.bleedCoolingDown {
                                Text("Letting the pump cool: wait a minute between runs.").font(.caption).foregroundStyle(.orange)
                            }
                        }.padding(4)
                    }
                    GroupBox("Calibration (ABS/DSC sensors)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Run after replacing a sensor, after suspension or alignment work, or after a steering-sensor fault. Each one makes the DSC measure its own sensor and store the offset — do it with the car stationary on level ground and the front wheels dead straight. Read the DSC again afterwards to check the fault cleared.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                ForEach([AppState.CalibrationRoutine.steeringAngle, .lateralAccel, .pressure]) { routine in
                                    Button("\(routine.title)…") { state.runCalibration(routine) }
                                        .disabled(state.busy || !state.configured || state.calibrationCoolingDown)
                                }
                            }
                        }.padding(4)
                    }
                }
                if module.sgbd.lowercased() == "lws5_1b" {
                    GroupBox("Steering-angle sensor") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Zero the steering-angle sensor: with the front wheels dead straight and the car stationary, the sensor learns the centered position. Do this after replacing the sensor or when the DSC reports a steering-angle fault.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Calibrate steering sensor…") { state.runCalibration(.steeringSensor) }
                                .disabled(state.busy || !state.configured || state.calibrationCoolingDown)
                        }.padding(4)
                    }
                }
                LogList()
            }.padding()
        }
    }
}

struct LogList: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        GroupBox("Log") {
            if state.log.isEmpty {
                Text("Nothing run yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.log.prefix(30)) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Label("\(line.date.formatted(date: .omitted, time: .standard))  \(line.title)",
                                  systemImage: line.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(line.ok ? Color.green : Color.red)
                            if !line.detail.isEmpty {
                                Text(line.detail).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ConfirmSheet: View {
    @EnvironmentObject var state: AppState
    let action: PendingAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(action.title, systemImage: "exclamationmark.triangle.fill").font(.title3.bold()).foregroundStyle(.orange)
            Text(action.message).fixedSize(horizontal: false, vertical: true)
            if let detail = action.detail {
                Text(detail).font(.callout.monospaced()).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            // Re-render each half second so a delayed confirm button unlocks on time.
            TimelineView(.periodic(from: action.created, by: 0.5)) { ctx in
                let wait = max(0, Int((action.delay - ctx.date.timeIntervalSince(action.created)).rounded(.up)))
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { state.pending = nil; action.cancel?() }.keyboardShortcut(.cancelAction)
                    if action.confirmIsDefault {
                        confirmButton(wait).keyboardShortcut(.defaultAction)
                    } else {
                        confirmButton(wait)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: action.detail == nil ? 460 : 560)
    }

    func confirmButton(_ wait: Int) -> some View {
        Button(wait > 0 ? "\(action.confirm) (\(wait))" : action.confirm) {
            state.pending = nil
            Task { await action.run() }
        }
        .disabled(wait > 0)
    }
}

// MARK: 4, 5. History and compare

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var a: HistoryEntry? { state.history.first { $0.id == state.compareA } }
    var b: HistoryEntry? { state.history.first { $0.id == state.compareB } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History").font(.title2.bold())
                Spacer()
                Button("Show folder") { NSWorkspace.shared.open(HistoryStore.directory) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Every module read is saved here. Pick two reads of the same module to compare them.")
                .font(.callout).foregroundStyle(.secondary)
            if state.history.isEmpty {
                ContentUnavailableView("No reads yet", systemImage: "clock", description: Text("Read a module and it shows up here."))
            } else {
                HStack {
                    Picker("Before", selection: $state.compareA) {
                        Text("Choose…").tag(String?.none)
                        ForEach(state.history) { Text($0.label).tag(Optional($0.id)) }
                    }
                    Picker("After", selection: $state.compareB) {
                        Text("Choose…").tag(String?.none)
                        ForEach(state.history.filter { a == nil || $0.sgbd == a!.sgbd }) { Text($0.label).tag(Optional($0.id)) }
                    }
                }
                if let a, let b {
                    DiffView(diff: HistoryStore.diff(from: a, to: b), sameModule: a.sgbd == b.sgbd)
                } else {
                    List(state.history) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.label)
                            if !entry.faults.isEmpty {
                                Text(entry.faults.map { "\($0.code) \($0.text)" }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
    }
}

struct DiffView: View {
    let diff: HistoryDiff
    let sameModule: Bool

    var body: some View {
        List {
            if !sameModule {
                Label("These reads are from different modules.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Section("New faults (\(diff.newFaults.count))") {
                ForEach(diff.newFaults, id: \.self) { Text("\($0.code)  \($0.text)").foregroundStyle(.red) }
            }
            Section("Gone (\(diff.goneFaults.count))") {
                ForEach(diff.goneFaults, id: \.self) { Text("\($0.code)  \($0.text)").foregroundStyle(.green) }
            }
            Section("Still there (\(diff.stillFaults.count))") {
                ForEach(diff.stillFaults, id: \.self) { Text("\($0.code)  \($0.text)") }
            }
            Section("Values that changed (\(diff.changedValues.count))") {
                ForEach(diff.changedValues, id: \.name) { change in
                    HStack {
                        Text(change.name).font(.caption.monospaced())
                        Spacer()
                        Text(change.before).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(change.after)
                    }
                }
            }
        }
    }
}
