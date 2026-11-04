import AppKit
import SwiftUI

@main
struct OpenDS2App: App {
    @StateObject private var state = AppState()

    init() {
        // If the engine dies (e.g. macOS blocks it on a downloaded copy), writing to its pipe would raise SIGPIPE
        // and kill the app with no crash report. Ignore it so the write fails and we can explain instead.
        signal(SIGPIPE, SIG_IGN)
        // Before AppState reads any setting: carry over backups and settings from "E46 Diagnostics".
        AppPaths.migrateFromE46Diag()
        // Launched from `swift run` there is no bundle telling AppKit this is a regular app
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("OpenDS2") {
            ContentView().environmentObject(state).frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        Settings { SetupView().environmentObject(state).padding().frame(width: 520) }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selection) {
                if state.modules.isEmpty {
                    Text(state.configured ? "Turn the ignition on (position 2), then Scan." : "Open Setup to choose the ECU folder.")
                        .foregroundStyle(.secondary).font(.callout)
                }
                Section("Modules") {
                    ForEach(state.modules) { module in
                        ModuleRow(module: module, report: state.reports[module.sgbd]).tag(module)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if !state.modules.isEmpty {
                    Button {
                        Task { if let url = await state.readAll() { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                    } label: {
                        Label("Read all \(state.modules.count) modules", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.busy || !state.configured)
                    .help("Read every module's fault and info memory (not live values, to save time) and save a report to the Desktop")
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let module = state.selection {
                ModuleDetail(module: module)
            } else {
                ContentUnavailableView("No module selected", systemImage: "car", description: Text("Scan the car to list its modules."))
            }
        }
        .alert("macOS blocked the diagnostic engine", isPresented: $state.engineBlocked) {
            Button("Copy command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Engine.unblockCommand, forType: .string)
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } message: {
            Text("This happens with downloaded copies of the app. Quit, open Terminal, paste and run this command, then open the app again:\n\n\(Engine.unblockCommand)" + (Engine.isTranslocated ? "\n\nIf you move the app (for example into Applications) before running it, the command must use the new location." : ""))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { state.showSetup = true } label: { Label("Setup", systemImage: "gearshape") }
                Menu {
                    Button("Quick scan (modules found before)") { Task { await state.scan() } }
                        .disabled(state.knownGroups.isEmpty)
                    Button("Full scan (every address, slow)") { Task { await state.scan(full: true) } }
                } label: {
                    Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
                } primaryAction: {
                    Task { await state.scan() }
                }
                .disabled(state.busy || !state.configured)
                .help(state.knownGroups.isEmpty ? "Scan every address for modules"
                      : "Quick scan of the modules found before; hold the arrow for a full scan")
                Button {
                    Task { if let url = await state.readEverything() { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                } label: { Label("Read everything", systemImage: "doc.text.magnifyingglass") }
                    .disabled(state.busy || !state.configured)
                    .help("Scan, read every module, and save a report to the Desktop")
                Button { state.clearAllFaults() } label: { Label("Clear all faults", systemImage: "trash") }
                    .disabled(state.busy || !state.configured)
                    .help("Read and save every module, then clear every module's fault memory")
                Button { state.showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    .help("Saved reads, and comparing two of them")
            }
        }
        .safeAreaInset(edge: .bottom) { StatusBar() }
        .sheet(isPresented: $state.showSetup) { SetupView().padding().frame(width: 520) }
        .sheet(isPresented: $state.showHistory) { HistoryView() }
        .sheet(item: $state.pending) { ConfirmSheet(action: $0) }
        .onChange(of: state.selection) { _, module in
            state.live.stop()
            if !(module?.isEngine ?? false), DetailTab(rawValue: state.tab)?.isEngineOnly == true { state.tab = DetailTab.faults.rawValue }
        }
        .onChange(of: state.tab) { _, _ in state.live.stop() }
        .onAppear {
            if !state.configured { state.showSetup = true }
            Task { await state.checkForUpdates(silent: true) }   // quiet unless a newer build exists
        }
    }
}

struct ModuleRow: View {
    let module: Module
    let report: ModuleReport?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).lineLimit(1)
                Text(module.sgbd.uppercased()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let report {
                if report.faults.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("\(report.faults.count)").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.red, in: Capsule()).foregroundStyle(.white)
                }
            }
        }
    }
}

struct ModuleDetail: View {
    @EnvironmentObject var state: AppState
    let module: Module

    var report: ModuleReport? { state.reports[module.sgbd] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(module.title).font(.title2.bold())
                    Text(([module.sgbd.uppercased(), module.group] + (module.name.isEmpty || module.name == module.title ? [] : [module.name]))
                        .joined(separator: " · ")).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button(report == nil ? "Read module" : "Read again") { Task { await state.read(module) } }
                    .buttonStyle(.borderedProminent).disabled(state.busy)
            }
            .padding()
            Picker("", selection: $state.tab) {
                ForEach(DetailTab.tabs(for: module)) { tab in
                    Text(tab == .faults ? "Faults\(report.map { " (\($0.faults.count))" } ?? "")" : tab.title).tag(tab.rawValue)
                }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal)
            Divider().padding(.top, 8)
            switch DetailTab(rawValue: state.tab) ?? .faults {
            case .dashboard: DashboardView(live: state.live, module: module)
            case .misfires: MisfireView(live: state.live, module: module)
            case .vanos: VanosView(live: state.live, module: module)
            case .tests: TestsView(module: module)
            case .actions: ActionsView(module: module)
            case .coding: CodingView(module: module)
            case let tab:
                if let report {
                    switch tab {
                    case .faults: FaultList(module: module, faults: report.faults, infoMemory: report.infoMemory)
                    case .live where !report.valuesRead:
                        ContentUnavailableView {
                            Label("Values not read yet", systemImage: "gauge.with.dots.needle.33percent")
                        } description: {
                            Text("\"Read all\" only reads fault and info memory, to save time. Read this module's live values now.")
                        } actions: {
                            Button("Read values") { Task { await state.read(module) } }
                                .buttonStyle(.borderedProminent).disabled(state.busy)
                        }
                    case .live: LiveTable(values: report.live.filter { state.filter.isEmpty || "\($0.job) \($0.name) \($0.label) \($0.help)".localizedCaseInsensitiveContains(state.filter) })
                        .searchable(text: $state.filter, prompt: "Filter values")
                    default: InfoList(report: report)
                    }
                } else {
                    ContentUnavailableView("Not read yet", systemImage: "arrow.down.circle",
                                           description: Text("Read this module to see its fault memory and live values."))
                }
            }
        }
    }
}

enum DetailTab: Int, CaseIterable, Identifiable {
    case faults, live, info, actions, dashboard, misfires, vanos, tests, coding
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .faults: "Faults"
        case .live: "All values"
        case .info: "Info"
        case .actions: "Actions"
        case .dashboard: "Dashboard"
        case .misfires: "Misfires"
        case .vanos: "VANOS"
        case .tests: "Tests"
        case .coding: "Coding"
        }
    }
    var isEngineOnly: Bool { self == .dashboard || self == .misfires || self == .vanos || self == .tests }
    static func tabs(for module: Module) -> [DetailTab] {
        module.isEngine ? [.faults, .dashboard, .misfires, .vanos, .tests, .live, .info, .coding, .actions] : [.faults, .live, .info, .coding, .actions]
    }
}

struct FaultList: View {
    @EnvironmentObject var state: AppState
    let module: Module
    let faults: [Fault]
    let infoMemory: [Fault]

    var body: some View {
        List {
            if faults.isEmpty {
                Label("No stored faults", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
            ForEach(faults) { FaultRow(fault: $0, sgbd: module.sgbd) }
            if !infoMemory.isEmpty {
                Section("Info memory (not faults, but useful history)") { ForEach(infoMemory) { FaultRow(fault: $0, sgbd: module.sgbd) } }
            }
        }
    }
}

struct FaultRow: View {
    @EnvironmentObject var state: AppState
    let fault: Fault
    let sgbd: String

    var body: some View {
        // History includes the read that produced this fault, so "seen" counts it
        let seen = HistoryStore.occurrences(of: fault.code, sgbd: sgbd, in: state.history)
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let note = fault.note {
                    Label(note, systemImage: "lightbulb").font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                if !fault.original.isEmpty {
                    Text("Module's text: \(fault.original)").font(.caption).foregroundStyle(.secondary)
                }
                if !fault.conditions.isEmpty {
                    Text("Conditions when stored").font(.caption.bold()).foregroundStyle(.secondary)
                    Grid(alignment: .leading, verticalSpacing: 4) {
                        ForEach(fault.conditions, id: \.0) { k, v in
                            GridRow { Text(k).foregroundStyle(.secondary).font(.caption); Text(v).textSelection(.enabled) }
                        }
                    }
                }
                if !fault.details.isEmpty {
                    Grid(alignment: .leading, verticalSpacing: 4) {
                        ForEach(fault.details, id: \.0) { k, v in
                            GridRow { Text(k).foregroundStyle(.secondary).font(.caption); Text(v).textSelection(.enabled) }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(fault.code).font(.body.monospaced().bold()).frame(width: 70, alignment: .leading)
                Text(fault.text)
                Spacer()
                if seen.reads > 1 {
                    Text("in \(seen.seen) of \(seen.reads) reads\(seen.first.map { " since " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LiveTable: View {
    let values: [LiveValue]
    var body: some View {
        Table(values) {
            TableColumn("Value") { v in
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.label)
                    if !v.help.isEmpty { Text(v.help).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                .help("\(v.key.isEmpty ? v.name : v.key) (from \(v.job))")
            }.width(min: 220, ideal: 380)
            TableColumn("Reading") { Text(Measure.convert(text: $0.value, unit: $0.unit).text).monospacedDigit().textSelection(.enabled) }.width(min: 80, ideal: 120)
            TableColumn("Unit") { Text(Measure.convert(text: $0.value, unit: $0.unit).unit) }.width(60)
        }
    }
}

struct InfoList: View {
    let report: ModuleReport
    var body: some View {
        List {
            Section("Identification") {
                ForEach(report.ident, id: \.0) { k, v in
                    LabeledContent {
                        Text(v).textSelection(.enabled)
                    } label: {
                        Text(ValueNames.label(k))
                        if let help = ValueNames.lookup(k)?.help, !help.isEmpty { Text(help) }
                    }
                    .help(k)
                }
            }
            if !report.errors.isEmpty {
                Section("Jobs that didn't answer") { ForEach(report.errors, id: \.self) { Text($0).font(.caption) } }
            }
        }
    }
}

/// Human description of MCP client activity (tooltip + Setup line). Works for any MCP client.
func mcpActivityText(_ last: Date?, tool: String?, count: Int, url: String) -> String {
    var s = "MCP server on \(url) (this Mac only)."
    if let last {
        let secs = Int(max(0, Date().timeIntervalSince(last)))
        let ago = secs < 2 ? "just now" : secs < 60 ? "\(secs)s ago" : "\(secs / 60)m ago"
        s += "\nLast request \(ago)" + (tool.map { " · \($0)" } ?? "") + " · \(count) total"
    } else {
        s += "\nNo client has connected yet."
    }
    return s
}

struct StatusBar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 8) {
            if state.busy {
                if let p = state.percent { ProgressView(value: Double(p), total: 100).frame(width: 120) } else { ProgressView().controlSize(.small) }
                if state.stoppable {
                    Button(state.stopping ? "Stopping…" : "Stop") { state.stop() }
                        .controlSize(.small)
                        .disabled(state.stopping)
                        .keyboardShortcut(.cancelAction)
                        .help("Stop reading (Esc). The current step finishes first.")
                }
            }
            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
            } else {
                Text(state.status).foregroundStyle(.secondary)
            }
            Spacer()
            if state.mcpRunning {
                TimelineView(.periodic(from: .now, by: 2)) { ctx in
                    let secs = state.mcpLastActivity.map { ctx.date.timeIntervalSince($0) }
                    let active = (secs ?? .infinity) < 90
                    Label(active ? "MCP connected" : "MCP", systemImage: active ? "sparkle" : "sparkle")
                        .foregroundStyle(active ? Color.green : Color.secondary)
                        .help(mcpActivityText(state.mcpLastActivity, tool: state.mcpLastTool, count: state.mcpRequestCount, url: state.mcpURL))
                }
            }
            if state.iface == "enet" {
                Label(state.enetHost.isEmpty ? "ENET (auto)" : "ENET \(state.enetHost)", systemImage: "network")
                    .foregroundStyle(.secondary)
            } else {
                Label(state.cableLooksPresent ? state.port.replacingOccurrences(of: "/dev/", with: "") : "No cable",
                      systemImage: state.cableLooksPresent ? "cable.connector" : "cable.connector.slash")
                    .foregroundStyle(state.cableLooksPresent ? Color.secondary : Color.orange)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}

struct SetupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Setup").font(.title2.bold()).padding(.bottom, 12)
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
            GroupBox("ECU description files") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(state.ecuPath.isEmpty ? "Not chosen" : state.ecuPath).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(state.ecuPath.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                    Text("The folder of .prg and .grp files (EDIABAS \"Ecu\" folder).").font(.caption).foregroundStyle(.secondary)
                }.padding(4)
            }
            GroupBox("App updates") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This app: \(state.currentVersionLabel)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("update URL", text: $state.updateURL).textFieldStyle(.roundedBorder)
                        Button("Check") { Task { await state.checkForUpdates(silent: false) } }
                            .disabled(state.updating)
                    }
                    Text("A link to version.json, or a direct link to the app .zip. For a Google Drive file, use its direct-download link: https://drive.google.com/uc?export=download&id=FILE_ID")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !state.updateStatus.isEmpty {
                        HStack(spacing: 6) {
                            if state.updating { ProgressView().controlSize(.small) }
                            Text(state.updateStatus).font(.caption)
                                .foregroundStyle(state.pendingUpdateZip != nil ? .primary : .secondary)
                        }
                    }
                    if state.pendingUpdateZip != nil && !state.updating {
                        Button("Download and install") {
                            state.ask("Install this update?",
                                      "The app will download the new version, replace itself, and relaunch. Don't unplug the cable or quit while it installs.",
                                      confirm: "Install") { state.installUpdate() }
                        }
                    }
                }.padding(4)
            }
            GroupBox("Units") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Show readings in", selection: $state.units) {
                        ForEach(UnitSystem.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }.pickerStyle(.segmented).frame(maxWidth: 260)
                    Text("The car reports metric. Imperial converts temperatures, speeds, distances, pressures and volumes to °F, mph, mi, psi and gal at display time — the same choice applies to the app and to MCP clients.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(4)
            }
            GroupBox("Coding data (optional)") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(state.datenPath.isEmpty ? "Not chosen" : state.datenPath).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(state.datenPath.isEmpty ? .secondary : .primary)
                        Spacer()
                        if !state.datenPath.isEmpty {
                            Button("Clear") { state.datenPath = ""; state.clearNCSCache() }
                        }
                        Button("Choose…") { chooseDatenFolder() }
                    }
                    Text("The car's chassis folder of NCS Expert DATEN files (for an E46: the .cXX coding files plus swtfsw06/swtpsw06.dat). When set, the Coding tab can decode each module's coding into named options. These are BMW's files; point at your own copy — nothing is bundled.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let problem = state.datenProblem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(4)
            }
            GroupBox("Cluster VIN write (advanced)") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Enable cluster VIN (chassis number) write — experimental", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: AppState.vinWriteDefaultsKey) },
                        set: { UserDefaults.standard.set($0, forKey: AppState.vinWriteDefaultsKey) }))
                    Text("Not working yet: the write hasn't taken effect on a real cluster so far. Only for aligning a swapped cluster's stored chassis number to the car it's in (the app checks the car's VIN and refuses anything else). Follow docs/CLUSTER-VIN-FIX.md: back up, run the reversible one-byte test, then the real change. Battery on a charger. Leave off unless you're doing that procedure.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(4)
            }
            GroupBox("Connection") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Interface", selection: $state.iface) {
                        Text("K+DCAN cable").tag("obd")
                        Text("Ethernet (ENET)").tag("enet")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: state.iface) {
                        if state.iface == "enet" { state.scanSet = "dcan" }   // F/G-series are Ethernet
                        Task { await state.configure() }
                    }
                    Picker("Modules", selection: $state.scanSet) {
                        Text("E-series (K-line)").tag("ds2")
                        Text("D-CAN / F-series").tag("dcan")
                    }
                    .pickerStyle(.segmented)
                    Text("Which module set to scan: E46 and older E-series are K-line (DS2); E8x/E9x (D-CAN) and F/G-series use the newer group set.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if state.iface == "enet" {
                        HStack {
                            Text("Vehicle IP")
                            TextField("auto-discover", text: $state.enetHost)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { Task { await state.configure() } }
                        }
                        Text("For F/G-series and later: an ENET (OBD-to-Ethernet) cable, or the car on the same network. Leave the IP blank to auto-discover.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack {
                            Picker("Port", selection: $state.port) {
                                if state.ports.isEmpty { Text("No serial ports").tag("") }
                                ForEach(state.ports, id: \.self) { Text($0.replacingOccurrences(of: "/dev/", with: "")).tag($0) }
                            }
                            Button { Task { await state.refreshPorts() } } label: { Image(systemName: "arrow.clockwise") }
                        }
                        Text("For E-series: plug in the K+DCAN cable; it shows up as cu.usbserial-… (or cu.wchusbserial…, cu.SLAB_USBtoUART, cu.usbmodem…). If the list stays empty with the cable plugged in, the cable needs a driver. On an E46, set the cable's switch to the position that bridges pins 7 and 8 (\"older cars\" / K-line).")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(4)
            }
            GroupBox("Record traffic") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Record everything sent to and from the car", isOn: Binding(
                        get: { state.recordTraffic },
                        set: { on in state.recordTraffic = on; Task { await state.applyRecording() } }))
                    Text("Saves a log of the raw diagnostic messages to a folder on the Desktop (\"OpenDS2 traffic\"). Turn it on, do a Scan and Read all (and open the All values / Dashboard tabs), then send the folder back. It helps build the app's own module support.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let folder = state.trafficFolder {
                        Button("Show folder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                }.padding(4)
            }
            GroupBox("MCP server (Claude, Codex…)") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Let an MCP client (Claude, Codex…) read the car through this app", isOn: Binding(
                        get: { state.mcpEnabled },
                        set: { on in state.mcpEnabled = on; if on { state.startMCP() } else { state.stopMCP() } }))
                    if state.mcpEnabled {
                        Text(state.mcpRunning ? "Running at \(state.mcpURL) (this Mac only)." : "Not running: \(state.mcpError ?? "unknown error")")
                            .font(.caption).foregroundStyle(state.mcpRunning ? Color.secondary : Color.orange)
                        if state.mcpRunning {
                            TimelineView(.periodic(from: .now, by: 2)) { ctx in
                                let secs = state.mcpLastActivity.map { ctx.date.timeIntervalSince($0) }
                                let active = (secs ?? .infinity) < 90
                                Label(active ? "MCP connected — a client is active"
                                      : state.mcpRequestCount > 0 ? "No client active (last request \(Int(secs ?? 0))s ago)"
                                      : "Waiting for a client to connect…",
                                      systemImage: active ? "sparkle" : "circle")
                                    .font(.caption)
                                    .foregroundStyle(active ? Color.green : Color.secondary)
                                    .help(state.mcpLastTool.map { "Last call: \($0)" } ?? "")
                            }
                        }
                        HStack {
                            Text(state.mcpAddCommand).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(state.mcpAddCommand, forType: .string)
                            }
                        }
                        Text("Run that once in Terminal to add the server to Claude Code. Claude can read freely; anything that changes the car asks you here first.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(4)
            }
            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
              }
              .padding(.trailing, 2)
            }
            Divider().padding(.vertical, 10)
            HStack {
                Spacer()
                Button("Done") { Task { await state.configure(); dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }
        .frame(height: 500)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use folder"
        if panel.runModal() == .OK, let url = panel.url {
            state.ecuPath = url.path
            Task { await state.configure() }
        }
    }

    func chooseDatenFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use folder"
        if panel.runModal() == .OK, let url = panel.url {
            state.datenPath = url.path
            state.clearNCSCache()
        }
    }
}

/// Read-only view of a module's coding, as far as the module's own SGBD can describe it.
/// Writing coding is deliberately not offered: that needs NCS Expert's data files and a wrong
/// write can disable a module.
struct CodingView: View {
    @EnvironmentObject var state: AppState
    let module: Module

    var sections: [CodingSection]? { state.coding[module.sgbd] }
    var codingFiles: [(index: Int, url: URL)] { state.ncsCodingFiles(for: module) }
    var ncsParams: [NCSDaten.Param]? { state.ncsCoding[module.sgbd] }
    /// NCS decoding is available for this module (DATEN folder set and a coding file exists).
    var hasNCS: Bool { state.datenReady && !codingFiles.isEmpty }
    var hasRead: Bool { if let s = sections { return !s.isEmpty }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Label(hasNCS
                      ? (NCSDaten.codingBasenames(module.sgbd).contains(where: AppState.writableCodingFamilies.contains)
                         ? "The options this module can be coded to, decoded from your NCS data. You can change them one at a time: each change is backed up, confirmed by you, and checked."
                         : "The options this module can be coded to, decoded from your NCS data. Read-only for this module: coding changes are only available for the body module so far.")
                      : "Read-only: what this module is set up to do. Changing coding needs BMW's NCS Expert (or BimmerCode/Carly); this app never writes it.",
                      systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(sections == nil ? "Read coding" : "Read again") { Task { await state.readCoding(module) } }
                    .disabled(state.busy || !state.configured)
            }
            .padding()
            if hasNCS || hasRead || module.isCluster {
                List {
                    if module.isCluster {
                        ClusterVinSection(module: module)
                    }
                    if hasNCS { ncsContent }
                    if hasRead, let sections { readContent(sections) }
                }
            } else if sections?.isEmpty == true {
                ContentUnavailableView("No readable coding", systemImage: "questionmark.folder",
                                       description: Text("This module doesn't describe its own coding. To decode it into named options, set a DATEN folder in Setup."))
            } else {
                ContentUnavailableView {
                    Label("Coding not read yet", systemImage: "slider.horizontal.3")
                } description: {
                    Text("Reads the settings this module stores (for example bulb monitoring, gong and seat-belt warnings, follow-me-home time), the VIN it was coded to, and the car's option codes where the module keeps them. Set a DATEN folder in Setup to also decode the full coding map into named options.")
                } actions: {
                    Button("Read coding") { Task { await state.readCoding(module) } }
                        .buttonStyle(.borderedProminent).disabled(state.busy || !state.configured)
                }
            }
        }
        .onAppear { decodeIfNeeded() }
        .onChange(of: module) { decodeIfNeeded() }
    }

    func decodeIfNeeded() {
        if hasNCS, state.ncsCoding[module.sgbd] == nil { state.decodeNCSCoding(module) }
    }

    /// Distinct coding-block names in file order.
    func orderedBlocks(_ params: [NCSDaten.Param]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in params where seen.insert(p.block).inserted { out.append(p.block) }
        return out
    }

    @ViewBuilder var ncsContent: some View {
        if let mm = state.ncsIndexMismatch(module) {
            Section {
                Label("The car reports coding index \(String(format: "%02X", mm.car)), but the coding data has no file for it (available: \(mm.have.map { String(format: "%02X", $0) }.joined(separator: ", "))). Showing index \(String(format: "%02X", mm.used)) — these options may not match this car. Pick the right version below if you know it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        if codingFiles.count > 1 {
            Section {
                Picker("Coding version", selection: Binding(
                    get: { state.ncsIndex[module.sgbd] ?? codingFiles.first!.index },
                    set: { state.decodeNCSCoding(module, index: $0) })) {
                    ForEach(codingFiles, id: \.index) { Text("Index \(String(format: "%02X", $0.index))").tag($0.index) }
                }
            } footer: {
                Text("This module has several coding versions (index shown in hex, matching the .cNN file). The app picks the one matching the module's coding index read from the car; override it here if needed. The wrong version shows the wrong options.")
            }
        }
        if let params = ncsParams, !params.isEmpty {
            let isDsc = module.isDSCMK60
            let isBody = NCSDaten.codingBasenames(module.sgbd).contains(where: AppState.writableCodingFamilies.contains)
            let canCode = isBody || isDsc
            let writeBlocker = isDsc ? state.dscCodingWriteBlocker(module) : state.codingWriteBlocker(module)
            Section {
                HStack {
                    Button(params.contains { $0.value != nil } ? "Read values again" : "Read current values") {
                        Task { await state.readNCSValues(module) }
                    }
                    .disabled(state.busy || !state.configured)
                    Spacer()
                    if canCode, writeBlocker == nil, !state.codingBackups(module).isEmpty {
                        Menu("Restore a backup") {
                            ForEach(state.codingBackups(module).prefix(10), id: \.url) { entry in
                                Button("\(entry.backup.date.formatted(date: .abbreviated, time: .shortened)) · before \(Translate.coding(entry.backup.option))") {
                                    Task { isDsc ? await state.requestDscCodingRestore(module, entry) : await state.requestCodingRestore(module, entry) }
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
            } footer: {
                if canCode {
                    Text(writeBlocker.map { "Coding changes: \($0)" }
                         ?? (isDsc
                             ? "ABS/DSC coding. Read the current values, then pick a new value from an option's menu. Every change is backed up, needs confirmation at the car, and is read back. Test the brakes and recheck for faults afterwards."
                             : "Read the current values, then pick a new value from an option's menu. Every change is backed up first, needs your confirmation at the car, and is read back to check it."))
                }
            }
            ForEach(orderedBlocks(params), id: \.self) { block in
                Section("Options · \(block)") {
                    ForEach(params.filter { $0.block == block }) { p in
                        LabeledContent {
                            if canCode, writeBlocker == nil, (isDsc ? state.dscCodingOptionChangeable(module, p) : state.codingOptionChangeable(module, p)) {
                                Menu(valueText(p)) {
                                    ForEach(p.choices.keys.sorted(), id: \.self) { v in
                                        Button(Translate.codingChoice(p.choices[v] ?? "\(v)", option: p.name) + (v == p.value ? "  (current)" : "")) {
                                            Task { isDsc ? await state.requestDscCodingChange(module, p, to: v) : await state.requestCodingChange(module, p, to: v) }
                                        }
                                        .disabled(v == p.value || state.busy)
                                    }
                                }
                                .fixedSize()
                            } else {
                                Text(valueText(p)).monospacedDigit()
                                    .foregroundStyle(p.value == nil ? .secondary : .primary)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Translate.coding(p.name))
                                Text(p.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .help("FSW \(String(format: "%04X", p.function)) · byte \(p.byteAddress) · \(maskText(p.mask))")
                    }
                }
            }
        } else if ncsParams == nil {
            Section { Text("Decoding…").foregroundStyle(.secondary) }
        } else {
            Section { Text("No coding file matched this module in the DATEN folder.").foregroundStyle(.secondary) }
        }
    }

    func maskText(_ mask: [UInt8]) -> String {
        mask.isEmpty ? "—" : "mask " + mask.map { String(format: "%02X", $0) }.joined()
    }

    /// The reading shown for a coding option: On/Off for a flag, a named meaning where we know the
    /// enumeration, otherwise the raw value. "—" until the car's bytes have been read.
    func valueText(_ p: NCSDaten.Param) -> String {
        guard let v = p.value else { return "—" }
        if let keyword = p.meaning { return Translate.codingChoice(keyword, option: p.name) }
        if p.isFlag { return v == 1 ? "On" : "Off" }
        if let meaning = Translate.codingValue(p.name, v) { return "\(meaning) (\(v))" }
        return String(v)
    }

    @ViewBuilder func readContent(_ sections: [CodingSection]) -> some View {
        if mismatchedVINs.count > 1 {
            Label("Modules carry different VINs: \(mismatchedVINs.map { "\($0.module): \($0.vin)" }.joined(separator: ", ")). A module with another car's VIN was probably swapped in and may need coding to this car.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        ForEach(sections) { section in
            Section(section.title) {
                if let error = section.error {
                    Text("Didn't answer: \(error)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(section.items, id: \.key) { item in
                    LabeledContent {
                        Text(Self.display(item.key, item.value)).textSelection(.enabled)
                    } label: {
                        Text(ValueNames.label(item.key))
                        if let help = ValueNames.lookup(item.key)?.help, !help.isEmpty { Text(help) }
                    }
                    .help(item.key)
                }
            }
        }
    }

    /// Distinct VINs (compared on the last 7 characters, which all modules store)
    var mismatchedVINs: [(module: String, vin: String)] {
        let all = state.codingVINs.filter { $0.vin.count >= 7 }
        var seen = Set<String>(), out: [(module: String, vin: String)] = []
        for v in all where seen.insert(String(v.vin.suffix(7))).inserted { out.append(v) }
        return out
    }

    /// On/off flags read as On/Off; German value texts translated
    static func display(_ key: String, _ value: String) -> String {
        let flag = ["_EIN", "_AKTIV", "_ENABLE", "_VERBAUT", "_CODIERT"].contains { key.hasSuffix($0) } || key.hasPrefix("COD_IHK_") || key == "KOMPRESSOR_SPERRE"
        if flag, value == "0" || value == "1" { return value == "1" ? "On" : "Off" }
        return Translate.english(value)
    }
}
