import KLine
import SwiftUI

struct AdapterView: View {
    @Environment(AppModel.self) private var model
    @State private var newSSID = ""
    @State private var newPassword = ""
    @State private var sleepMinutes = 20
    @State private var message: String?
    @State private var working = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    if let s = model.adapter, let a = model.address {
                        LabeledContent("Address", value: a.host)
                        LabeledContent("Firmware", value: s.firmware)
                        LabeledContent("Car battery", value: s.batteryVolts.map { String(format: "%.1f V", $0) } ?? "not measured")
                        LabeledContent("WiFi") { Text(s.wifi).multilineTextAlignment(.trailing) }
                        if let p = s.power { LabeledContent("Sleep", value: sleepSummary(p)) }
                        LabeledContent("Awake for", value: Duration.seconds(s.uptime).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                    } else if model.findingAdapter {
                        HStack { ProgressView(); Text("Looking for the adapter").foregroundStyle(.secondary) }
                    } else {
                        Text(model.adapterProblem ?? "Not found").foregroundStyle(.secondary)
                    }
                    Button("Check again") { Task { await model.findAdapter(); await model.loadNetworks() } }
                        .disabled(model.findingAdapter)
                } header: {
                    Text("Adapter")
                } footer: {
                    Text("First time: in Settings › Wi-Fi, join **OBD-Adapter** (password obdadapter), come back here and add your home WiFi below. After that the adapter joins your WiFi by itself.")
                }

                if model.address != nil {
                    networksSection
                    sleepSection
                }

                Section {
                    TextField("Automatic", text: $model.customAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Adapter address")
                } footer: {
                    Text("Leave empty to find it automatically (obdadapter.local, then 192.168.4.1). For the Mac's test adapter: 127.0.0.1:2323:2333:2380")
                }
            }
            .navigationTitle("Adapter")
            .task { await model.loadNetworks() }
            .onChange(of: model.address?.host) { _, _ in Task { await model.loadNetworks() } }
            .alert("Adapter", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    @ViewBuilder private var networksSection: some View {
        Section {
            ForEach(model.networks?.saved ?? [], id: \.self) { ssid in
                HStack {
                    Text(ssid)
                    Spacer()
                    if model.networks?.joined == ssid { Text("joined").foregroundStyle(.green) }
                }
            }
            .onDelete { idx in
                let names = idx.compactMap { model.networks?.saved[$0] }
                Task {
                    for n in names {
                        do { try await model.forgetNetwork(n) } catch { message = "\(error)" }
                    }
                }
            }
            TextField("Network name", text: $newSSID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $newPassword)
            Button("Add network") {
                working = true
                Task {
                    defer { working = false }
                    do {
                        try await model.addNetwork(ssid: newSSID, password: newPassword)
                        message = "Saved. The adapter joins \(newSSID) within about 15 seconds when it's in range. Then put this phone on the same network."
                        newSSID = ""
                        newPassword = ""
                    } catch { message = "\(error)" }
                }
            }
            .disabled(newSSID.isEmpty || working)
        } header: {
            Text("Networks the adapter joins")
        } footer: {
            Text("Add your home WiFi and your phone's hotspot (for using it away from home), up to 4. It joins the strongest one in range. Swipe to remove.")
        }
    }

    /// "sleeps after 20 min idle below 13.2 V (…)" -> "after 20 min unused"
    private func sleepSummary(_ power: String) -> String {
        if power.hasPrefix("never") { return "never" }
        if let n = power.split(separator: " ").compactMap({ Int($0) }).first { return "after \(n) min unused" }
        return power
    }

    @ViewBuilder private var sleepSection: some View {
        Section {
            Stepper(sleepMinutes == 0 ? "Never sleep" : "Sleep after \(sleepMinutes) min", value: $sleepMinutes, in: 0...120, step: 5)
            Button("Save") {
                Task {
                    do { try await model.setSleep(minutes: sleepMinutes) } catch { message = "\(error)" }
                }
            }
        } header: {
            Text("Sleep")
        } footer: {
            Text("The OBD port has power with the car off. The adapter sleeps after this long with no app connected and the engine off, and wakes when the engine starts or when it's unplugged and plugged back in.")
        }
        .onAppear {
            // "sleeps after 20 min idle …" -> 20
            if let p = model.adapter?.power {
                if p.hasPrefix("never") { sleepMinutes = 0 }
                else if let n = p.split(separator: " ").compactMap({ Int($0) }).first { sleepMinutes = n }
            }
        }
    }
}
