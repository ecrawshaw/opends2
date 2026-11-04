import KLine
import SwiftUI

struct CarView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                switch model.car {
                case .notConnected, .failed:
                    connectSection
                case .connecting:
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(model.progress ?? "Connecting").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Finding the car's protocol takes up to 20 seconds on older cars.")
                    }
                case .connected:
                    connectedSections
                }
            }
            .navigationTitle("Car")
            .toolbar {
                if model.car == .connected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.readCar() } }
                            .disabled(model.reading)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Disconnect") { model.disconnectCar() }
                    }
                }
            }
            .refreshable { if model.car == .connected { await model.readCar() } }
            .alert("Problem", isPresented: Binding(get: { model.lastError != nil && model.car == .connected },
                                                   set: { if !$0 { model.lastError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.lastError ?? "") }
        }
    }

    // MARK: not connected

    @ViewBuilder private var connectSection: some View {
        Section {
            Button {
                Task { await model.connectCar() }
            } label: {
                Label("Read car", systemImage: "car.side.front.open").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text("Plug the adapter in, switch the ignition on (the engine can run), then tap Read car. Works on cars from 1996 on (US) or about 2001 on (Europe) that use CAN or K-line.")
        }
        if case let .failed(message) = model.car {
            Section("Couldn't connect") {
                Text(message).foregroundStyle(.red)
            }
        }
        AdapterSummary()
    }

    // MARK: connected

    @ViewBuilder private var connectedSections: some View {
        Section("Vehicle") {
            LabeledContent("Protocol", value: model.protocolName ?? "")
            LabeledContent("VIN") {
                Text(model.vin ?? "not reported").textSelection(.enabled).monospaced()
            }
        }
        ForEach(model.readiness, id: \.ecu) { r in
            Section {
                HStack {
                    Image(systemName: "engine.combustion.fill")
                        .foregroundStyle(r.milOn ? .orange : .secondary)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text(r.milOn ? "Check-engine light ON" : "Check-engine light off").font(.headline)
                        Text("\(r.dtcCount) stored code\(r.dtcCount == 1 ? "" : "s")").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(model.readiness.count > 1 ? "Engine computer \(r.ecu)" : "Engine computer")
            }
        }
        ForEach([OBD.DTCKind.stored, .pending, .permanent], id: \.self) { kind in
            Section {
                let list = model.codes[kind] ?? []
                if list.isEmpty {
                    Text(model.reading ? "Reading…" : "None").foregroundStyle(.secondary)
                }
                ForEach(list) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.code).font(.headline.monospaced())
                            Spacer()
                            Text(c.ecu).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(DTCInfo.category(c.code)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(kind.title)
            } footer: {
                Text(kind.explanation)
            }
        }
        ForEach(model.readiness, id: \.ecu) { r in
            Section {
                ForEach(r.monitors, id: \.name) { m in
                    Label {
                        Text(m.name)
                    } icon: {
                        Image(systemName: m.complete ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(m.complete ? .green : .orange)
                    }
                    .badge(m.complete ? "Ready" : "Not ready")
                }
            } header: {
                Text("Readiness monitors")
            } footer: {
                Text("Self-tests the car runs while driving. Emissions inspections need most of them ready. They all reset when codes are cleared or the battery is disconnected.")
            }
        }
        Section {
            Button("Clear trouble codes…", role: .destructive) { confirmClear = true }
                .disabled(model.reading)
                .confirmationDialog("Clear trouble codes?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Clear codes", role: .destructive) { Task { await model.clearCodes() } }
                } message: {
                    Text("Turns the check-engine light off and erases the codes and their freeze-frame data. It also resets the readiness monitors, so the car will fail an emissions inspection until it has been driven enough to re-run them. If the fault is still there, the light comes back.\n\nDo this with the ignition on and the engine off.")
                }
        }
    }
}

/// One-line adapter state for the Car tab
struct AdapterSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Adapter") {
            if let s = model.adapter, let a = model.address {
                LabeledContent("Connected", value: a.host)
                if let v = s.batteryVolts { LabeledContent("Car battery", value: String(format: "%.1f V", v)) }
            } else if model.findingAdapter {
                HStack { ProgressView(); Text("Looking for the adapter").foregroundStyle(.secondary) }
            } else {
                Text("Not found. Is it plugged in, and is this phone on the same WiFi (or on the OBD-Adapter network)?")
                    .foregroundStyle(.secondary)
                Button("Look again") { Task { await model.findAdapter() } }
            }
        }
    }
}
