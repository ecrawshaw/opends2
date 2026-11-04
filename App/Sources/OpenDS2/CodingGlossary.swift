import Foundation

/// English for NCS coding options. The FSW keywords in the SP-DATEN are German engineering
/// abbreviations with no translation in the files, so we curate the owner-facing options and
/// fall back to expanding the German word-parts for the rest. The German keyword is always kept
/// alongside (in parentheses) so a reading can be matched back to NCS Expert / Tool32.
extension Translate {
    /// English label for an FSW coding keyword (e.g. "SPERRDIFFERENZREGELUNG" → "Locking
    /// differential control"). Falls back to an expansion of the German parts.
    static func coding(_ fsw: String) -> String {
        if let hit = optionEnglish[fsw] ?? codingLabels[fsw] ?? clusterLabels[fsw] { return hit }
        return expandGerman(fsw)
    }

    /// English for a parameter-value keyword (PSW) from the coding data — "aktiv", "mls",
    /// "handschaltung", "25.000_km"… `option` gives context where a word means different things
    /// ("us" is the US market for a window rule but US English for the display language).
    static func codingChoice(_ psw: String, option: String? = nil) -> String {
        let k = psw.lowercased()
        if option == "SPRACHE", k == "us" { return "English (US)" }
        if let hit = valueEnglish[k] ?? choiceWords[k] { return hit }
        if let hit = valueWithUnit(k) { return hit }
        if k.hasPrefix("wert_") { return "value set \(k.dropFirst(5))" }
        if k.hasPrefix("typ_") { return "type \(k.dropFirst(4))" }
        return psw.replacingOccurrences(of: "_", with: " ")
    }

    private static let choiceWords: [String: String] = [
        "aktiv": "active", "nicht_aktiv": "not active", "ein": "on", "aus": "off",
        "vorhanden": "fitted", "nicht_vorhanden": "not fitted",
        "km": "kilometres", "mls": "miles", "kmh": "km/h", "mph": "mph",
        "grad_c": "°C", "grad_f": "°F", "12_stunden": "12-hour", "24_stunden": "24-hour",
        "mpg_us": "mpg (US)", "mpg_uk": "mpg (UK)", "l/100km": "l/100 km", "km/l": "km/l",
        "linkslenker": "left-hand drive", "rechtslenker": "right-hand drive",
        "benziner": "petrol", "diesel": "diesel",
        "handschaltung": "manual", "automatik": "automatic", "smg": "SMG",
        "mit_gurtschlosskontakt": "with seat-belt buckle switch",
        "ohne_gurtschlosskontakt": "without seat-belt buckle switch",
        "piezo": "piezo buzzer", "gong": "chime", "k_bus": "K-bus", "can": "CAN",
        "deutsch": "German", "englisch": "English (UK)", "us": "English (US)", "italienisch": "Italian",
        "spanisch": "Spanish", "japan": "Japanese", "franzoesisch": "French", "kanada": "French (Canada)",
        "golf": "Gulf states", "hollaendisch": "Dutch",
        "ohne_zeitinspektion": "without time-based inspection", "mit_zeitinspektion": "with time-based inspection",
    ]

    /// Instrument-cluster options (kmb_e46), kept apart from `codingLabels` so a key can't be
    /// duplicated across the two literals (that traps at launch).
    private static let clusterLabels: [String: String] = [
        "LL/RL": "Left/right-hand drive", "MOTOR_ART": "Engine type", "GETRIEBEART": "Transmission type",
        "ANZEIGE_EML": "EML warning display", "WEG_EINHEIT": "Distance unit", "ZEIT_EINHEIT": "Clock format",
        "TEMPERATUR_EINHEIT": "Temperature unit", "WEG_DURCHSCHNITT": "Average-speed unit",
        "VERBRAUCH_D1": "Consumption unit", "WEG_REICHWEITE": "Range unit", "WEG_LIMIT": "Speed-limit unit",
        "SPRACHE": "Language", "LICHTWARNUNG": "Lights-on warning",
        "ZUENDSCHLUESSEL_WARNUNG": "Key-in-ignition warning", "BC": "On-board computer",
        "AUSSENTEMP_SENSOR": "Outside-temperature sensor", "AUSSENTEMP_WARN_AKUSTIK": "Ice-warning chime",
        "AKUSTIK_PARKBREMSE": "Handbrake chime", "AKUSTIK_GURT_WARN": "Seat-belt chime",
        "GURTWARNUNG": "Seat-belt warning", "RUECKWAERTSGANG_WARNUNG": "Reverse-gear warning",
        "RDKS": "Tire-pressure monitor (RDKS)", "AKUSTIK_RDKS": "Tire-pressure warning chime",
        "AKUSTIK_ASC": "ASC/DSC chime", "SMG_ALT_NEU": "SMG generation", "HBA": "Brake assist (HBA) display",
        "K_ZAHL_WEG": "K-number (distance)", "K_ZAHL_WEG_KOMPL": "K-number (distance), complement",
        "K_ZAHL_TACHO": "K-number (speedometer)", "K_ZAHL_TACHO_KOMPL": "K-number (speedometer), complement",
        "OFFSET_GESAMTWEGSTRECKE": "Odometer offset", "PRUEFSTEMPEL": "Test stamp",
        "SIA_LITER_GRENZE": "Service: fuel-used limit", "SIA_GRENZE_ZEIT": "Service: time limit",
        "SIA_ANZEIGEPARAMETER": "Service display mode", "TANK_SCHWELLE_RESERVE": "Fuel reserve threshold",
        "CODIERUNG_ERFOLGT": "Coding done", "WARNUNG_GESCHW_LIMIT": "Speed-limit warning",
    ]

    /// Plain-English meaning of a coding value, where we know the enumeration. Flags are handled
    /// by the caller (on/off). Returns nil when the value is just a number with no named meaning.
    static func codingValue(_ fsw: String, _ value: Int) -> String? {
        codingEnums[fsw]?[value]
    }

    // MARK: curated labels (the options an owner actually codes or reads)

    private static let codingLabels: [String: String] = [
        // DSC / brakes
        "MOTOR_ART_DSC": "Engine type (DSC)", "MOTOR_ART_ASC": "Engine type (ASC)",
        "BAUART_MK60": "MK60 build type", "GETRIEBE": "Transmission",
        "DRUCKMODELL_HINTERACHSE": "Pressure model, rear axle",
        "DRUCKMODELL_VORDERACHSE": "Pressure model, front axle",
        "LOGIK_HA_SPERRE": "Rear-axle lock logic", "EBV_LAMPE": "EBD warning lamp",
        "BREMSLICHTSCHALTER": "Brake-light switch", "PRE_VLABS": "ABS pre-fill",
        "SPERRDIFFERENZREGELUNG": "Locking-differential control",
        "TRAKTIONDIFFERENZREGELUNG": "Traction-differential control",
        "DYN_BREMS_UNTERSTUETZUNG": "Dynamic brake assist",
        "MAX_BREMS_UNTERSTUETZUNG": "Max brake assist",
        "HBA_VARIANTEN": "Hydraulic brake-assist variant",
        "HBA_SCHWELLANHEBUNG": "Brake-assist threshold raise",
        "ERKENNUNG_BREMSLICHT": "Brake-light detection",
        "LENKWINKELKENNLINIE": "Steering-angle curve",
        "REIFENDRUCKWARNSYSTEM": "Tire-pressure warning (RPA/RDC)",
        // Body (GM5/ZKE) — comfort/convenience
        "ZV": "Central locking", "DWA_NOTENTSCHAERFEN": "Alarm emergency disarm",
        "VERRIEGELN_AUT_AB_X_KM/H": "Auto-lock above set speed",
        "ZEIT_BIS_AUTOM_SPERREN": "Delay before auto-lock",
        "FH_FAHRERTUER_TIPP_ZU": "One-touch up, driver window",
        "FH_BEIFAHRERTUER_TIPP_AUF": "One-touch down, passenger window",
        "FH_ZTR_SCHALTER_TIPP_AUF": "One-touch down, center-console switch",
        "FH_VORN_GESAMTWEG": "Front-window total travel",
        "IB_BEI_KL.R_AUS": "Interior light off at terminal R",
        "IB_EIN_TUERGRIFF": "Interior light on at door handle",
        "I_GONG_PARKBREMSE": "Parking-brake chime",
        "EKS_ABSCHALTPUNKT": "Anti-trap cut-off point",
        "EKS_EMPFINDLICHKEIT": "Anti-trap sensitivity",
        "UMLUFT_MEMORY": "Recirculation memory",
        // Airbag (MRS)
        "GURTSTRAFFER_FAHRER_1": "Belt tensioner, driver (1)",
        "GURTSTRAFFER_FAHRER_2": "Belt tensioner, driver (2)",
        "GURTSCHLOSS_HINTEN_RE_1": "Belt buckle, rear right (1)",
        "SIDEBAG_LINKS_2": "Side airbag, left (2)", "SIDEBAG_RECHTS_1": "Side airbag, right (1)",
        "SIDEBAG_RECHTS_2": "Side airbag, right (2)",
        "BEIFAHRERBAG_STUFE2_2": "Passenger airbag, stage 2 (2)",
        "B_SATELLIT_1": "Satellite sensor (1)", "B_SATELLIT_2": "Satellite sensor (2)",
        "CRASHPARAMETER": "Crash parameter",
        // Cluster
        "DZM_SKALA_ENDWERT": "Tachometer scale end value",
        "DZM_AUF_AB_DAEMPFUNG": "Tachometer needle damping",
        "SCHWELLE_UEBERDREHZAHL": "Over-rev warning threshold",
        "ABSCHALTDREHZAHL_ANLASSER": "Starter cut-off rpm",
        "KM_SERVICE_INTERVALL": "Service interval (distance)",
        "KUEHLMITTELTEMP_WERT": "Coolant-temperature value",
        "GRENZTEMPERATUR": "Temperature limit",
        "KUEHLMITTELUEBERTEMP_CAN": "Coolant over-temp (CAN)",
        "SCHLUESSELAUSWERTUNG": "Key evaluation",
        "FAHRGESTELL_NR_PRUEFSUMME": "Chassis-number checksum",
        "SOFTWARE_STAND": "Software version", "BAUREIHE": "Model series",
        "MOTORDIAGNOSE": "Engine diagnosis", "DME_FREIGABE": "DME enable",
        "PARK/NEUTRAL_EINGANG": "Park/neutral input",
    ]

    // MARK: curated value meanings — only a fallback for files without PSW value records. The
    // coding data's own value names win; raw bits are NOT on/off (DSC SPERRDIFFERENZREGELUNG
    // raw 1 = "nicht_aktiv"), so don't guess polarity here.

    private static let codingEnums: [String: [Int: String]] = [:]

    // MARK: algorithmic fallback

    /// Expand a German coding keyword into readable English by translating its word-parts.
    /// Leaves array/index suffixes like "[2]" in place. Imperfect but readable; the German is
    /// always shown too, so this only has to orient the reader.
    static func expandGerman(_ fsw: String) -> String {
        // keep a trailing [n] or _n index out of the translation
        var name = fsw, suffix = ""
        if let r = name.range(of: #"(\[\d+\]|_\d+)$"#, options: .regularExpression) {
            suffix = " " + name[r].trimmingCharacters(in: CharacterSet(charactersIn: "[]_"))
            name = String(name[..<r.lowerBound])
        }
        let parts = name.split(whereSeparator: { $0 == "_" || $0 == "/" })
        let words = parts.map { part -> String in
            let p = String(part).uppercased()
            return germanParts[p] ?? String(part).capitalized
        }
        return words.joined(separator: " ") + suffix
    }

    private static let germanParts: [String: String] = [
        "MOTOR": "Engine", "GETRIEBE": "Transmission", "BREMS": "Brake", "BREMSLICHT": "Brake light",
        "LICHT": "Light", "TUER": "Door", "TUERGRIFF": "Door handle", "FAHRER": "Driver",
        "BEIFAHRER": "Passenger", "VORN": "Front", "VORDER": "Front", "VORDERACHSE": "Front axle",
        "HINTEN": "Rear", "HINTER": "Rear", "HINTERACHSE": "Rear axle", "LINKS": "Left", "RECHTS": "Right",
        "SCHALTER": "Switch", "VERRIEGELN": "Lock", "SPERRE": "Lock", "SPERREN": "Lock", "ZEIT": "Time",
        "TEMP": "Temperature", "TEMPERATUR": "Temperature", "KUEHLMITTEL": "Coolant", "DRUCK": "Pressure",
        "DRUCKMODELL": "Pressure model", "DREHZAHL": "Engine speed", "GESCHW": "Speed", "RAD": "Wheel",
        "ACHSE": "Axle", "GURT": "Belt", "GURTSTRAFFER": "Belt tensioner", "GURTSCHLOSS": "Belt buckle",
        "SATELLIT": "Satellite sensor", "CRASH": "Crash", "PARAMETER": "Parameter", "FILTER": "Filter",
        "FZG": "Vehicle", "BLOCK": "Block", "SCHLUESSEL": "Key", "AUSWERTUNG": "Evaluation",
        "REFERENZ": "Reference", "POSITION": "Position", "FAHRGESTELL": "Chassis", "NR": "No.",
        "PRUEFSUMME": "Checksum", "SERVICE": "Service", "INTERVALL": "Interval", "WERT": "Value",
        "OFFSET": "Offset", "KORREKTUR": "Correction", "TABELLE": "Table", "CHECKSUM": "Checksum",
        "DIAGNOSE": "Diagnosis", "FREIGABE": "Enable", "GRENZ": "Limit", "GRENZE": "Limit",
        "GRENZTEMPERATUR": "Temperature limit", "SCHWELLE": "Threshold", "UEBERDREHZAHL": "Over-rev",
        "ABSCHALT": "Cut-off", "ABSCHALTPUNKT": "Cut-off point", "ABSCHALTDREHZAHL": "Cut-off rpm",
        "ANLASSER": "Starter", "STUFE2": "Stage 2", "STUFE": "Stage", "EMPFINDLICHKEIT": "Sensitivity",
        "AUSTAUSCHPUNKT": "Changeover point", "REIFENDRUCK": "Tire pressure", "WARNSYSTEM": "Warning system",
        "WARN": "Warning", "LAMPE": "Lamp", "GONG": "Chime", "PARKBREMSE": "Parking brake",
        "UMLUFT": "Recirculation", "MEMORY": "Memory", "DAUER": "Duration", "DROSSEL": "Throttle",
        "KLAPPE": "Flap", "EICHLAUF": "Calibration run", "VOLUMENDURCHFLUSSPARA": "Volume-flow parameter",
        "VOLUMEN": "Volume", "DURCHFLUSS": "Flow", "PARA": "Parameter", "LENKWINKEL": "Steering angle",
        "KENNLINIE": "Curve", "STEIGUNG": "Gradient", "DELTA": "Delta", "DELTAWERTE": "Delta values",
        "DYN": "Dynamic", "UNTERSTUETZUNG": "Assist", "MAX": "Max", "MIN": "Min", "MAXIMALPOSITION": "Max position",
        "SCHRITT": "Step", "DIFF": "Difference", "UEBERSTEUERN": "Oversteer", "UNTERSTEUERN": "Understeer",
        "UNTERSTEUERSCHWELLE": "Understeer threshold", "UNTERSTEUERUNGSALGORYTHM": "Understeer algorithm",
        "MUE": "μ (grip)", "KALT": "Cold", "KALTUEBERWACHUNG": "Cold monitoring", "UEBERWACHUNG": "Monitoring",
        "OPENLOAD": "Open-load", "ANZAHL": "Count", "SENSOR": "Sensor", "UNTERGRENZE": "Lower limit",
        "POLLING": "Polling", "TIMEOUT": "Timeout", "INDEX": "Index", "ANSTEUERUNG": "Control",
        "MOTORANSTEUERUNG": "Engine control", "EKS": "Anti-trap", "SOFTWARE": "Software", "STAND": "Version",
        "BAUREIHE": "Model series", "BAUART": "Build type", "NNORM": "Norm", "AGRENZE": "A-limit",
        "BGRENZE": "B-limit", "HBA": "Hydraulic brake assist", "VARIANTEN": "Variant", "VARIANTE": "Variant",
        "DME": "DME", "PARK": "Park", "NEUTRAL": "Neutral", "EINGANG": "Input", "KL": "Terminal",
        "AUS": "Off", "EIN": "On", "AUF": "Up", "ZU": "Down", "TIPP": "One-touch", "GESAMTWEG": "Total travel",
        "FH": "Window", "IB": "Interior light", "DWA": "Alarm", "NOTENTSCHAERFEN": "Emergency disarm",
        "ZV": "Central locking", "DZM": "Tachometer", "DAEMPFUNG": "Damping", "SKALA": "Scale",
        "ENDWERT": "End value", "ERKENNUNG": "Detection", "REFERENZFAHRT": "Reference run",
        "PAUSE": "Pause", "GEARMOMENTREGLER": "Gear-torque controller", "MOMENTREGLER": "Torque controller",
        "MOTKALT": "Engine cold", "MOTORKALT": "Engine cold", "SCHNELLE": "Fast", "LANGSAM": "Slow",
        "REGELUNG": "Control", "ZTR": "Center console",
    ]
}
