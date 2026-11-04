import KLine
import SwiftUI

struct LiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.car != .connected {
                    ContentUnavailableView {
                        Label("Not connected", systemImage: "car")
                    } description: {
                        Text("Connect to the car on the Car tab first.")
                    } actions: {
                        Button("Read car") { Task { await model.connectCar() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.car == .connecting)
                    }
                } else {
                    List {
                        Section {
                            Picker("Show", selection: $model.favoritesOnly) {
                                Text("Everything").tag(false)
                                Text("Favorites").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        } footer: {
                            if model.favoritesOnly && model.favorites.isEmpty {
                                Text("Tap the star on a value to add it to favorites. Fewer values update faster.")
                            }
                        }
                        Section {
                            if model.liveRows.isEmpty {
                                HStack { ProgressView(); Text("Reading…").foregroundStyle(.secondary) }
                            }
                            ForEach(model.liveRows, id: \.self.key) { v in
                                row(v)
                            }
                        } footer: {
                            Text(model.supported.isEmpty ? "" : "The car reports \(model.supported.count) values.")
                        }
                    }
                }
            }
            .navigationTitle("Live data")
            .onAppear { model.startLive() }
            .onDisappear { model.stopLive() }
            .onChange(of: model.car) { _, state in if state == .connected { model.startLive() } }
        }
    }

    private func row(_ v: PIDValue) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name)
                if Set(model.liveRows.map(\.ecu)).count > 1 {
                    Text(v.ecu).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(v.valueText).font(.title2.monospacedDigit().weight(.semibold)).contentTransition(.numericText())
            Text(v.unit).foregroundStyle(.secondary).frame(minWidth: 36, alignment: .leading)
            Button {
                model.toggleFavorite(v.pid)
            } label: {
                Image(systemName: model.favorites.contains(v.pid) ? "star.fill" : "star")
                    .foregroundStyle(model.favorites.contains(v.pid) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
        }
        .animation(.default, value: v.value)
    }
}

extension PIDValue {
    var key: String { "\(pid)|\(ecu)" }
}
