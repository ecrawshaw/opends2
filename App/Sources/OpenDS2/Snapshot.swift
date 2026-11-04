import AppKit
import Foundation

/// `OPENDS2_SNAPSHOT=/path/out.png` renders the app's own window to a PNG and quits.
/// The app draws itself, so no Screen Recording permission is needed.
/// `OPENDS2_SNAPSHOT_SAMPLE=1` fills the window with made-up sample data first (no car needed).
/// `OPENDS2_SNAPSHOT_TAB=dashboard|live|info|coding|bleed|misfires|vanos|tests|actions|faults|history|confirm|cluster` picks the screen.
enum Snapshot {
    static var path: String? { ProcessInfo.processInfo.environment["OPENDS2_SNAPSHOT"] }
    static var sample: Bool { ProcessInfo.processInfo.environment["OPENDS2_SNAPSHOT_SAMPLE"] == "1" }
    static var tab: String { ProcessInfo.processInfo.environment["OPENDS2_SNAPSHOT_TAB"] ?? "faults" }

    @MainActor
    static func schedule(_ state: AppState) {
        guard let path else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if sample { fillSample(state) }
            state.showSetup = (tab == "setup")   // snapshot the Setup sheet itself
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                capture(to: path)
                exit(0)  // terminate() waits on an open sheet
            }
        }
    }

    @MainActor
    static func capture(to path: String) {
        // A sheet is its own window; capture it when one is up
        let main = NSApplication.shared.windows.first(where: { $0.title == "OpenDS2" }) ?? NSApplication.shared.windows.first
        guard let window = main?.attachedSheet ?? main,
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// A minute of made-up readings so the live screens have something to draw
    @MainActor
    static func fillLive(_ live: LiveMonitor) {
        let start = Date().addingTimeInterval(-60)
        for i in 0..<60 {
            let t = Double(i)
            func v(_ job: String, _ key: String, _ value: Double, _ unit: String) -> (String, ResultSet) {
                (job, ["STAT_\(key)_WERT": value, "STAT_\(key)_EINH": unit])
            }
            var result: [String: Any] = Dictionary(uniqueKeysWithValues: [
                v("STATUS_MOTORDREHZAHL", "MOTORDREHZAHL", 880 + 30 * sin(t / 4), "1/min"),
                v("STATUS_MOTORTEMPERATUR", "MOTORTEMPERATUR", 70 + t / 3, "Grad C"),
                v("STATUS_OEL_TEMPERATUR", "OEL_TEMPERATUR", 60 + t / 4, "Grad C"),
                v("STATUS_UBATT", "UBATT", 14.1 + 0.05 * sin(t), "V"),
                v("STATUS_LAMBDA_INTEGRATOR_1", "LAMBDA_INTEGRATOR_1", 1 + 0.03 * sin(t / 2), ""),
                v("STATUS_LAMBDA_INTEGRATOR_2", "LAMBDA_INTEGRATOR_2", 1 + 0.03 * cos(t / 2), ""),
                v("STATUS_EVANOS1_SOLL", "EVANOS1_SOLL", 80, "Grad KW"),
                v("STATUS_EVANOS1_IST", "EVANOS1_IST", 79 + sin(t), "Grad KW"),
                v("STATUS_EVANOS2_SOLL", "EVANOS2_SOLL", 80, "Grad KW"),
                v("STATUS_EVANOS2_IST", "EVANOS2_IST", 72 + sin(t), "Grad KW"),
                v("STATUS_AVANOS1_SOLL", "AVANOS1_SOLL", 95, "Grad KW"),
                v("STATUS_VANOS_NW_LAGE_EINLASS_BANK_1", "VANOS_NW_LAGE_EINLASS_BANK_1", 94.5, "Grad KW"),
                v("STATUS_AVANOS2_SOLL", "AVANOS2_SOLL", 95, "Grad KW"),
                v("STATUS_VANOS_NW_LAGE_EINLASS_BANK_2", "VANOS_NW_LAGE_EINLASS_BANK_2", 95.2, "Grad KW"),
            ])
            var rough: ResultSet = ["STAT_SYSTEMCHECK_LAUFUNRUHE_EINH": "%"]
            for c in 1...6 { rough["STAT_SYSTEMCHECK_LAUFUNRUHE_ZYL\(c)_WERT"] = (c == 4 ? 6.0 : 1.0) + 0.5 * sin(t + Double(c)) }
            result["STATUS_SYSTEMCHECK_LAUFUNRUHE"] = rough
            live.ingest(result, at: start.addingTimeInterval(t))
        }
    }

    @MainActor
    static func fillSample(_ state: AppState) {
        let dme = Module(group: "d_motor", sgbd: "mss54ds0", name: "", ident: [:])
        state.modules = [
            Module(group: "dsc_mk60", sgbd: "dsc_mk60", name: "", ident: [:]),
            dme,
            Module(group: "d_0080", sgbd: "kombi46r", name: "", ident: [:]),
            Module(group: "d_0000", sgbd: "zke5", name: "", ident: [:]),
        ]
        state.reports["dsc_mk60"] = ModuleReport()
        state.reports["kombi46r"] = ModuleReport()
        state.reports["mss54ds0"] = ModuleReport(
            faults: [
                Fault(code: "SAMPLE", text: "Sample data: not read from a car",
                      details: [("Fault type", "Signal implausible")],
                      conditions: [("Mileage (km)", "142,350"), ("Occurrences", "3"), ("Currently present", "yes"),
                                   ("Battery voltage", "12.4 V"), ("Engine speed", "760 rpm"), ("Temperature", "92 °C")]),
                Fault(code: "SAMPLE", text: "Second sample fault", details: []),
            ],
            ident: [("ID_BMW_NR", "sample"), ("ID_SW_NR", "sample")],
            live: [LiveValue(job: "STATUS_MOTORTEMPERATUR", name: "MOTORTEMPERATUR", value: "88", unit: "°C", key: "STAT_MOTORTEMPERATUR_WERT"),
                   LiveValue(job: "STATUS_DIGITAL", name: "KUP_EIN", value: "0", unit: "", key: "STAT_KUP_EIN"),
                   LiveValue(job: "STATUS_ADAPTIONSBLOCK_06", name: "LAA_OFFSET1", value: "0.12", unit: "ms", key: "STAT_LAA_OFFSET1_WERT"),
                   LiveValue(job: "STATUS_TANK_DICHTHEIT", name: "LDP_STROM", value: "21", unit: "mA", key: "LDP_STROM")],
            raw: ["STATUS": [:]])
        state.selection = dme
        state.tab = 0
        state.reports["mss54ds0"]?.faults.append(Fault(code: "SAMPLE", text: "Misfire cylinder 4 (emissions-relevant)", details: [],
                                                        original: "Aussetzer Zyl.4 Abgas", note: Translate.note(for: "Aussetzer Zyl.4 Abgas")))
        fillLive(state.live)
        switch tab {
        case "dashboard": state.tab = DetailTab.dashboard.rawValue
        case "live": state.tab = DetailTab.live.rawValue
        case "coding":
            state.tab = DetailTab.coding.rawValue
            state.coding["mss54ds0"] = [
                CodingSection(job: "CODIERUNG_LESEN", items: [("COD_DAUER_FOLLOW_ME_HOME_SCHALTUNG", "40"), ("COD_AL_KALTUEBERWACHUNG_EIN", "1"),
                                                             ("COD_GEDIMMTE_BLINKER_FUER_STANDLICHT_EIN", "0"), ("ZYLINDERZAHL", "6 Zylinder")]),
                CodingSection(job: "C_FG_LESEN", items: [("FG_NR", "WBAXX00000XX12345")]),
                CodingSection(job: "C_ZCS_LESEN", error: "no response"),
            ]
        case "info": state.tab = DetailTab.info.rawValue
        case "misfires": state.tab = DetailTab.misfires.rawValue
        case "vanos": state.tab = DetailTab.vanos.rawValue
        case "tests":
            state.tab = DetailTab.tests.rawValue
            state.log = [LogLine(title: "Sample: Ignition coil 4", ok: true, detail: "OKAY")]
        case "actions":
            state.tab = DetailTab.actions.rawValue
        case "bleed", "bleedconfirm":
            state.tab = DetailTab.actions.rawValue
            state.selection = state.modules.first { $0.sgbd == "dsc_mk60" }
            if tab == "bleedconfirm", let dsc = state.selection { state.runBleed(.rear, on: dsc) }
            state.log = [LogLine(title: "Sample: Clear faults: Engine (DME)", ok: true, detail: "OKAY")]
        case "history":
            let a = HistoryEntry(date: Date().addingTimeInterval(-86400 * 3), sgbd: "mss54ds0", title: "Engine (DME)",
                                 faults: [.init(code: "SAMPLE1", text: "Sample: Intake VANOS bank 1 control"), .init(code: "SAMPLE2", text: "Sample: Oxygen sensor heater bank 2 before catalyst")],
                                 infoMemory: [], values: ["STATUS_UBATT/UBATT": "12.1 V"], note: nil)
            let b = HistoryEntry(date: Date(), sgbd: "mss54ds0", title: "Engine (DME)",
                                 faults: [.init(code: "SAMPLE1", text: "Sample: Intake VANOS bank 1 control")],
                                 infoMemory: [], values: ["STATUS_UBATT/UBATT": "14.2 V"], note: nil)
            state.history = [b, a]
            state.compareA = a.id
            state.compareB = b.id
            state.showHistory = true
        case "cluster":
            state.selection = state.modules.first { $0.sgbd == "kombi46r" }
            state.tab = DetailTab.coding.rawValue
            state.reports["kombi46r"] = ModuleReport(
                faults: [],
                ident: [("ID_BMW_NR", "6938290"), ("ID_SW_NR", "23")],
                live: [],
                raw: ["STATUS": [:]]
            )
        case "confirm":
            state.clearFaults(dme)
        default: break
        }
        state.status = "Sample data (no car connected)"
    }
}
