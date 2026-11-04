import SwiftUI

@main
struct KLineApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    // Debug builds: launch with `-tab live -autoConnect YES` to open straight onto a screen
    @State private var tab = UserDefaults.standard.string(forKey: "tab") ?? "car"

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                CarView().tabItem { Label("Car", systemImage: "car") }.tag("car")
                LiveView().tabItem { Label("Live", systemImage: "gauge.with.dots.needle.33percent") }.tag("live")
                AdapterView().tabItem { Label("Adapter", systemImage: "antenna.radiowaves.left.and.right") }.tag("adapter")
            }
            .environment(model)
            .task {
                await model.findAdapter()
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "autoConnect") { await model.connectCar() }
                #endif
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS suspends the app soon after it leaves the screen; let go of the car cleanly so the
            // adapter gets off the CAN bus and can go to sleep
            if phase == .background { model.disconnectCar() }
        }
    }
}
