import Foundation

/// English for the German fault texts in the E46 SGBDs (fault locations, fault types and environment
/// conditions from the FORTTEXTE / FARTTEXTE / FUMWELTTEXTE tables of mss54ds0, dsc57, dsc_mk60, zke5,
/// ihka46, ews3 and kombi46r). Texts not listed here are shown in German.
enum Translate {
    static func english(_ german: String) -> String {
        let key = german.trimmingCharacters(in: .whitespaces)
        if let hit = table[key] { return hit }
        if key.hasPrefix("frei ") { return "Unused (\(key.dropFirst(5)))" }
        if key.hasPrefix("interner Index ") { return "Internal index \(key.dropFirst(15))" }
        return german
    }

    /// SGBD units are German abbreviations
    static func unit(_ u: String) -> String {
        switch u.trimmingCharacters(in: .whitespaces) {
        case "Grad C", "Grad Celsius", "GradC": "°C"
        case "Grad KW", "Grad KW.", "GradKW": "° crank"
        case "Grad DK", "Grad": "°"
        case "1/min", "U/min": "rpm"
        case let other: other
        }
    }

    static func hasEnglish(_ german: String) -> Bool { english(german) != german }

    /// A readable label for an FS_LESEN_DETAIL result key (the freeze-frame / "conditions when
    /// stored" fields EDIABAS returns alongside each fault). Unknown keys are humanized.
    static func label(_ key: String) -> String {
        if let hit = detailLabels[key] { return hit }
        if let hit = ValueNames.lookup(key) { return hit.label }
        // F_SD_01 → "Stored data 01"; otherwise strip the F_ prefix and Title-case the words.
        if key.range(of: #"^F_SD_?\d+$"#, options: .regularExpression) != nil {
            return "Stored data \(key.filter(\.isNumber))"
        }
        let base = key.hasPrefix("F_") ? String(key.dropFirst(2)) : key
        return base.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static let detailLabels: [String: String] = [
        "F_HFK": "Occurrences", "F_LZ": "Logistic counter", "F_ANZ_LOG": "Occurrences",
        "F_VORHANDEN_NR": "Currently present (code)", "F_VORHANDEN_TEXT": "Currently present",
        "F_WARNUNG_NR": "Warning lamp (code)", "F_WARNUNG_TEXT": "Warning lamp",
        "F_READY_NR": "Readiness (code)", "F_READY_TEXT": "Readiness",
        "F_UW_KM": "Mileage (km)", "F_UWKM": "Mileage (km)", "F_UW_KM_WERT": "Mileage (km)",
        "F_UW_ZEIT": "Operating time", "F_UW_ZEIT_WERT": "Operating time",
        "F_UW_TEMP": "Temperature", "F_UW_SPANNUNG": "Battery voltage",
        "F_UW_DREHZAHL": "Engine speed", "F_UW_LAST": "Engine load",
    ]

    /// Whether a detail key is a freeze-frame "condition when stored" value (vs. a plain result).
    static func isCondition(_ key: String) -> Bool {
        let k = key.uppercased()
        return k.contains("UW") || k.contains("UMWELT") || k.contains("_SD_") || k.hasSuffix("_SD")
            || ["F_HFK", "F_LZ", "F_ANZ_LOG"].contains(k)
            || k.contains("WARNUNG") || k.contains("READY") || k.contains("VORHANDEN")
    }

    /// Practical pointers for faults that are common on the S54 / E46. General advice, not a diagnosis.
    static func note(for german: String) -> String? {
        let t = german.lowercased()
        for (keys, text) in notes where keys.contains(where: { t.contains($0) }) { return text }
        return nil
    }

    private static let notes: [([String], String)] = [
        (["vanos", "hallgeber"],
         "VANOS: check the oil level first (VANOS runs on engine oil pressure). Then the solenoid and its connector, and the cam position (Hall) sensor for that bank. Repeated VANOS faults with good wiring point at the VANOS unit itself. The VANOS tab shows target vs actual and can run the adjust-time and leak tests."),
        (["aussetzer"],
         "Misfire: swap that cylinder's coil with a neighbour, clear faults, and see whether the misfire follows the coil. If not, check the spark plug, then the injector. The Misfires tab shows per-cylinder roughness live."),
        (["zuendspule", "primaerkreis", "sekundaerkreis"],
         "Ignition coil circuit: check the coil connector and wiring, or swap the coil with another cylinder to confirm."),
        (["einspritzventil", "ev-treiber"],
         "Injector circuit: check the injector connector and wiring. Swapping injectors between cylinders confirms a bad injector."),
        (["lambda-adapt", "adaptionsoffset", "adaptionsfaktor", "lambdaregler", "lambda-regelfaktor", "kraftstoffsystemdiagnose", "teillast-", "leerlauf-max", "leerlauf-min"],
         "Mixture adaptation out of range: usually an unmetered air leak (intake boots, idle valve hoses, crankcase vent, oil filler cap), low fuel pressure or a weak oxygen sensor. Compare bank 1 and bank 2 trims on the Dashboard: a fault on one bank only narrows it down."),
        (["sondenhzg", "sondenheizwiderst", "heizung defekt"],
         "Oxygen sensor heater: usually the sensor itself has failed; also check its connector and fuse."),
        (["lambdasonde", "vorkatsonde", "nachkatsonde", "nach-kat-sonde", "sondenspannung", "sondenhub", "sprungzeit", "periodendauer"],
         "Oxygen sensor signal: often an aging sensor or an exhaust leak ahead of the sensor."),
        (["kat-konvertierung", "nkat-alterung"],
         "Catalyst efficiency: rule out misfires and oxygen sensor faults first; they can cause this on their own."),
        (["klopf"], "Knock sensor or its wiring. Also check for poor fuel quality."),
        (["sekundaerluft"],
         "Secondary air system (cold-start air injection): check the pump, its relay, the valve and the hoses. The Tests tab can run the secondary air check."),
        (["tankleck", "feinleck", "grobleck", "ldp-", "dmtl", "modul tankleckdiagnose", "ventil tankleckdiagnose", "tankdeckel"],
         "Evaporative leak: check the fuel cap seal first. Then the purge valve, the leak-detection pump and the hoses."),
        (["tankentlueftung", "funktionspruefung tev"], "Purge (tank vent) valve or its hoses."),
        (["leerlaufsteller", "leerlaufregler", "leerlaufsolldrehzahl", "abweichung leerlaufdrehzahl", "leckluft"],
         "Idle control: clean or check the idle control valve and its connector, and look for air leaks."),
        (["drosselklappe", "edk-", "egas", "pedalwert", "lageregler", "kfk-steller"],
         "Throttle actuator / pedal sensor: check connectors first. These faults can put the car in limp mode."),
        (["kuehlwassertemp", "kuehleraustritt", "kühleraustritt", "motortemperatur", "t-erhöhung"],
         "Coolant temperature: check the sensor and its connector; a slow warm-up can also mean the thermostat is stuck open."),
        (["oelniveau", "oeltemperatur", "tog"], "Oil level / temperature sensor: check the oil level first, then the sensor and wiring."),
        (["unterspannung", "bordnetzspannung", "versorgungsspannung", "ueberspannung"],
         "Supply voltage: test and charge the battery (and check the alternator) before anything else. Low voltage causes lots of unrelated faults."),
        (["ews", "wechselcode", "schluessel nr", "wc-toleranz"],
         "Immobilizer (EWS): related to the key/EWS/DME handshake. Don't clear or re-sync EWS without knowing why; it can leave the car unable to start."),
        (["can", "timeout", "botschaft", "k-bus"],
         "Communication fault between modules: often logged after a flat battery or with a module unplugged. Clear it and see whether it comes back."),
        (["drehzahlfuehler"], "Wheel speed sensor: check the sensor, its wiring and the tone ring at that wheel."),
        (["bremslichtschalter"], "Brake light switch: check it's adjusted and working (brake lights come on)."),
    ]

    private static let table: [String: String] = {
        var t: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { t[String(parts[0])] = String(parts[1]) }
        }
        return t
    }()

    private static let raw = """
--\t--
----\t--
0001 - Kurzschluss UBatt o. Wert zu gross\t0001 - Short to battery voltage or value too high
0010 - Kurzschluss Masse o. Wert zu klein\t0010 - Short to ground or value too low
0100 - Leitungsbruch o. Wert fehlt\t0100 - Open circuit or value missing
1000 - Zustand/Wert unplausibel o. Uebertemperatur\t1000 - State/value implausible or over-temperature
ABS-Regelung aktiv\tABS control active
Benzinmotor\tPetrol
Dieselmotor\tDiesel
4 Zylinder\t4 cylinders
6 Zylinder\t6 cylinders
8 Zylinder\t8 cylinders
12 Zylinder\t12 cylinders
unbekannter Code\tUnknown code
default\tDefault
bei elektrischen Verbrauchern\tWith electrical load
bei Unterspannung\tAt low voltage
Zuheizer konventionell\tConventional auxiliary heater
Zuheizer K-Bus\tK-bus auxiliary heater
Solarsensor\tSun sensor
Bordmonitor\tOn-board monitor
Kennfeldkuehlung\tMap-controlled cooling
Kompressortransportsperre\tA/C compressor transport lock
BELEGT\tStored
UNBELEGT\tEmpty
Sensor-Cluster Timeout CAN\tSensor cluster (yaw/lateral-g): CAN timeout
falscher Sensorcluster\tWrong sensor cluster fitted
Sensorcluster Fehler intern\tSensor cluster: internal fault
Sensor-Cluster CAN Bus-Off\tSensor cluster: CAN bus off
Sensorcluster Versorgungsspannung ausserhalb gueltigem Bereich\tSensor cluster: supply voltage out of range
Sensor-Cluster CAN Fehler\tSensor cluster: CAN fault
Drehzahlfuehler vorne links elektrisch defekt\tWheel speed sensor front left: electrical fault
Drehzahlfuehler vorne links Extrapolation\tWheel speed sensor front left: signal dropout
Drehzahlfuehler Impulsrad vorne links periodische Ueberwachung\tWheel speed sensor front left: tone ring check
Drehzahlfuehler vorne links Anfahrerkennung v_Vergleich\tWheel speed sensor front left: no/implausible signal when pulling away
Drehzahlfuehler vorne links Langzeitueberwachung\tWheel speed sensor front left: long-term monitoring
Drehzahlfuehler vorne links Check auf doppelte Impulsradfrequenz\tWheel speed sensor front left: double tone-ring frequency
Drehzahlfuehler vorne rechts elektrisch defekt\tWheel speed sensor front right: electrical fault
Drehzahlfuehler vorne rechts Extrapolation\tWheel speed sensor front right: signal dropout
Drehzahlfuehler Impulsrad vorne rechts periodische Ueberwachung\tWheel speed sensor front right: tone ring check
Drehzahlfuehler vorne rechts Anfahrerkennung v_Vergleich\tWheel speed sensor front right: no/implausible signal when pulling away
Drehzahlfuehler vorne rechts Langzeitueberwachung\tWheel speed sensor front right: long-term monitoring
Drehzahlfuehler vorne rechts Check auf doppelte Impulsradfrequenz\tWheel speed sensor front right: double tone-ring frequency
Drehzahlfuehler hinten links elektrisch defekt\tWheel speed sensor rear left: electrical fault
Drehzahlfuehler hinten links Extrapolation\tWheel speed sensor rear left: signal dropout
Drehzahlfuehler Impulsrad hinten links periodische Ueberwachung\tWheel speed sensor rear left: tone ring check
Drehzahlfuehler hinten links Anfahrerkennung v_Vergleich\tWheel speed sensor rear left: no/implausible signal when pulling away
Drehzahlfuehler hinten links Langzeitueberwachung\tWheel speed sensor rear left: long-term monitoring
Drehzahlfuehler hinten links Check auf doppelte Impulsradfrequenz\tWheel speed sensor rear left: double tone-ring frequency
Drehzahlfuehler hinten rechts elektrisch defekt\tWheel speed sensor rear right: electrical fault
Drehzahlfuehler hinten rechts Extrapolation\tWheel speed sensor rear right: signal dropout
Drehzahlfuehler Impulsrad hinten rechts periodische Ueberwachung\tWheel speed sensor rear right: tone ring check
Drehzahlfuehler hinten rechts Anfahrerkennung v_Vergleich\tWheel speed sensor rear right: no/implausible signal when pulling away
Drehzahlfuehler hinten rechts Langzeitueberwachung\tWheel speed sensor rear right: long-term monitoring
Drehzahlfuehler hinten rechts Check auf doppelte Impulsradfrequenz\tWheel speed sensor rear right: double tone-ring frequency
Pumpenmotor\tABS pump motor
Ventil/ECU_Hardware Fehler,ROM/RAM_Check Fehler\tValve / control unit hardware fault (ROM/RAM check)
Bordnetzspannung < 9 Volt\tSystem voltage below 9 V
Steuergeraet Fehler intern\tControl unit: internal fault
Bordnetzspannung > 18 Volt\tSystem voltage above 18 V
Bandendetest aktiv\tFactory end-of-line test active
Bandendetest Timeout\tFactory end-of-line test: timeout
Bandendetest Gierraten Sensor Justierung Fehler\tEnd-of-line test: yaw rate sensor alignment fault
Bandendetest Gierraten Sensor Fehler\tEnd-of-line test: yaw rate sensor fault
Bandendetest Querbeschleunigung Sensor Fehler\tEnd-of-line test: lateral acceleration sensor fault
Bandendetest Querbeschleunigung und Gierraten Fehler\tEnd-of-line test: lateral acceleration and yaw rate fault
Bandendetest Gierraten Sensor falsch montiert\tEnd-of-line test: yaw rate sensor mounted wrong
Bandendetest Querbeschleunigung und Gierraten Sensor falsch montiert\tEnd-of-line test: lateral acceleration / yaw rate sensor mounted wrong
Bandendetest Lenkwinkel Sensor Fehler\tEnd-of-line test: steering angle sensor fault
CAN-Bus Off, Interner Fehler CAN-Controller\tCAN bus off (internal CAN controller fault)
CAN Timeout DME/DDE\tCAN timeout: engine computer (DME)
CAN Timeout EGS\tCAN timeout: transmission (EGS/SMG)
CAN Timeout Instrumentenkombi\tCAN timeout: instrument cluster
CAN DME/DDE Botschaft unplausibel\tCAN message from engine computer implausible
CAN DME/DDE, Motormoment nicht einstellbar\tEngine computer can't apply requested engine torque
CAN DME/DDE Signal Fehler\tCAN signal fault from engine computer
CAN Timeout LWS\tCAN timeout: steering angle sensor
ABS/ASC/DSC: VIN nicht initialisiert, LWS-Abgleich durchfuehren\tVIN not initialised: do the steering angle sensor calibration
Druck Sensor 1 elektrisch defekt\tBrake pressure sensor 1: electrical fault
Druck Sensor 2 elektrisch defekt\tBrake pressure sensor 2: electrical fault
Druck Sensor 1/2 unplausibel\tBrake pressure sensors 1/2 implausible
Spannungsversorgung Sensoren\tSensor power supply
Temperatur Sensor\tTemperature sensor
Querbeschleunigung Sensor elektrisch defekt\tLateral acceleration sensor: electrical fault
Querbeschleunigung Sensor unplausibel\tLateral acceleration sensor implausible
Gierraten Sensor elektrisch defekt\tYaw rate sensor: electrical fault
Gierraten Sensor unplausibel\tYaw rate sensor implausible
Lenkwinkel Sensor Signal unplausibel,Offset\tSteering angle sensor signal implausible (offset)
Lenkwinkel Sensor intern\tSteering angle sensor: internal fault
DSC Sensor Offset Check\tDSC sensor offset check
DSC Dauerregelung\tDSC intervening continuously (too long)
ASC ECU empfaengt LWS CAN Botschaft\tASC unit is receiving steering-angle CAN messages (wrong coding?)
Codierfehler\tCoding fault
DSC Taster laenger als 10sec gedrueckt oder Fehler\tDSC button held over 10 s, or button fault
RPA Taster Fehler\tFlat-tyre warning (RPA) button fault
Bremsfluessigkeitsniveau Schalter Fehler\tBrake fluid level switch fault
Bremslichtschalter Fehler\tBrake light switch fault
Fehler DSC_Sport Taster am Lenkrad (nur Motorsport)\tDSC Sport button on steering wheel fault (M cars only)
kein passendes Fehlersymptom\tNo matching fault symptom
Signal oder Wert oberhalb Schwelle\tSignal or value above threshold
Signal oder Wert unterhalb Schwelle\tSignal or value below threshold
kein Signal oder Wert\tNo signal or value
unplausibles Signal oder Wert\tImplausible signal or value
Testbedingungen erfuellt\tTest conditions met
Testbedingungen noch nicht erfuellt\tTest conditions not yet met
Fehler bisher nicht aufgetreten\tFault has not occurred yet
Fehler momentan nicht vorhanden, aber bereits gespeichert\tFault not present now, but stored
Fehler momentan vorhanden, aber noch nicht gespeichert (Entprellphase)\tFault present now, not stored yet (debouncing)
Fehler momentan vorhanden und bereits gespeichert\tFault present now and stored
Fehler wuerde kein Aufleuchten einer Warnlampe verursachen\tFault would not turn on a warning lamp
Fehler wuerde das Aufleuchten einer Warnlampe verursachen\tFault would turn on a warning lamp
Bremsfluessigkeitsschalter\tBrake fluid switch
ASC/DSC_aktiv (Tasterfunktion)\tASC/DSC on (button)
Bremsdruck erkannt\tBrake pressure detected
ABS-Regelung\tABS intervention
ASC-Regelung (BMR)\tASC intervention (brakes)
ASC-Regelung (AMR)\tASC intervention (engine torque)
GMR-Regelung (GMR)\tYaw control (brakes)
GMR-Regelung (MMR)\tYaw control (engine torque)
CBC-Regelung\tCornering brake control (CBC)
MSR-Regelung\tEngine drag-torque control (MSR)
TDR-Regelung\tTDR control
SDR-Regelung\tSDR control
DBC-Regelung\tDynamic brake control (DBC)
RTA aktiv\tRTA active
Run-Up Mode\tRun-up mode
Batteriespannung: Unterbrechung\tBattery voltage: interrupted (battery disconnected or very flat)
ABS-Regelung passiv\tABS control inactive
ACB aktiv\tACB active
ACB passiv\tACB inactive
ACC CAN Botschaftsfehler\tACC CAN message error
ACC Fehler Bremslichtansteuerung\tACC brake light control fault
ACC Verzoegerungsanforderung Plausibilitaet\tACC deceleration request implausible
ACC hat abgeschaltet\tACC switched off
ACC kein Statuswechsel bei DSC passiv\tACC: no status change with DSC off
ADC-Register\tADC register
ASC Umschaltventil Hinterachse\tASC changeover valve, rear axle
ASC Umschaltventil Vorderachse\tASC changeover valve, front axle
ASC nicht passiv geschaltet\tASC not switched off
ASC passiv geschaltet\tASC switched off
ASC-Regelung aktiv\tASC control active
ASC-Regelung passiv\tASC control inactive
AUC Heizung\tAUC (air quality sensor) heater
AUC Sensor\tAUC (air quality) sensor
AVANOS 2 Ist\tExhaust VANOS bank 2 actual
AVANOS 2 Soll\tExhaust VANOS bank 2 target
AVANOS1-Fruehventil\tExhaust VANOS bank 1 advance solenoid
AVANOS1-Hallgeber\tExhaust cam sensor (Hall) bank 1
AVANOS1-Regelung\tExhaust VANOS bank 1 control
AVANOS1-Spaetventil\tExhaust VANOS bank 1 retard solenoid
AVANOS2-Fruehventil\tExhaust VANOS bank 2 advance solenoid
AVANOS2-Hallgeber\tExhaust cam sensor (Hall) bank 2
AVANOS2-Regelung\tExhaust VANOS bank 2 control
AVANOS2-Spaetventil\tExhaust VANOS bank 2 retard solenoid
Abbruch/Funktions-Timeout\tAborted / function timeout
Abgasklappe\tExhaust flap
Abgastemperatursensor\tExhaust temperature sensor
Abweich. Adaptionsoffset 1\tMixture adaptation offset bank 1 out of range
Abweich. Adaptionsoffset 2\tMixture adaptation offset bank 2 out of range
Abweichung Lambda-Adapt.fak. Bank1\tMixture adaptation factor bank 1 out of range
Abweichung Lambda-Adapt.fak. Bank2\tMixture adaptation factor bank 2 out of range
Abweichung Leerlaufdrehzahl\tIdle speed deviation
Abweichung gegen zweites Poti zu gross\tDeviation from second potentiometer too large
Adaptionslauf erfolgt nicht\tAdaptation run not completed
Aktuatorik\tActuator
Ansaugdruck > Umgebungsdruck bei laufendem Motor\tIntake pressure above ambient with engine running
Ansauglufttemperatur\tIntake air temperature
Ansauglufttemperaturfuehler\tIntake air temperature sensor
Anstiegsrampe unplausibel\tRise rate implausible
Aussentemperatur\tOutside temperature
Aussetzer Zyl.1 Abgas\tMisfire cylinder 1 (emissions-relevant)
Aussetzer Zyl.1 KAT-sch.\tMisfire cylinder 1 (catalyst-damaging)
Aussetzer Zyl.2 Abgas\tMisfire cylinder 2 (emissions-relevant)
Aussetzer Zyl.2 KAT-sch.\tMisfire cylinder 2 (catalyst-damaging)
Aussetzer Zyl.3 Abgas\tMisfire cylinder 3 (emissions-relevant)
Aussetzer Zyl.3 KAT-sch.\tMisfire cylinder 3 (catalyst-damaging)
Aussetzer Zyl.4 Abgas\tMisfire cylinder 4 (emissions-relevant)
Aussetzer Zyl.4 KAT-sch.\tMisfire cylinder 4 (catalyst-damaging)
Aussetzer Zyl.5 Abgas\tMisfire cylinder 5 (emissions-relevant)
Aussetzer Zyl.5 KAT-sch.\tMisfire cylinder 5 (catalyst-damaging)
Aussetzer Zyl.6 Abgas\tMisfire cylinder 6 (emissions-relevant)
Aussetzer Zyl.6 KAT-sch.\tMisfire cylinder 6 (catalyst-damaging)
Aussetzer Zyl.7 Abgas\tMisfire cylinder 7 (emissions-relevant)
Aussetzer Zyl.7 KAT-sch.\tMisfire cylinder 7 (catalyst-damaging)
Aussetzer Zyl.8 Abgas\tMisfire cylinder 8 (emissions-relevant)
Aussetzer Zyl.8 KAT-sch.\tMisfire cylinder 8 (catalyst-damaging)
Aussetzer mehr Zylinder Abgas\tMisfire, multiple cylinders (emissions-relevant)
Aussetzer mehr Zylinder KAT-sch.\tMisfire, multiple cylinders (catalyst-damaging)
BLS betaetigt\tBrake light switch pressed
BLS nicht betaetigt\tBrake light switch not pressed
Bandendetest\tEnd-of-line test
Bank 1 zu klein\tBank 1 too low
Bank 2 zu klein\tBank 2 too low
Beide Drosselklappenpotis\tBoth throttle position sensors
Beide V-Signalquellen\tBoth vehicle-speed signal sources
Beifahrerspiegel: Interner Fehler: Timer Watchdog\tPassenger mirror: internal fault (watchdog timer)
Beifahrerspiegel: Kurzschluss Heizung\tPassenger mirror: heater short circuit
Beifahrerspiegel: Kurzschluss Motor Achse 1/3\tPassenger mirror: motor axis 1/3 short circuit
Beifahrerspiegel: Kurzschluss Motor Achse 2/4\tPassenger mirror: motor axis 2/4 short circuit
Beifahrerspiegel: Kurzschluss Motor Einklappen\tPassenger mirror: fold motor short circuit
Beifahrerspiegel: Potentiometer Achse 1/3\tPassenger mirror: position sensor axis 1/3
Beifahrerspiegel: Potentiometer Achse 2/4\tPassenger mirror: position sensor axis 2/4
Beifahrerspiegel: Unterbrechung Heizung\tPassenger mirror: heater open circuit
Beifahrerspiegel: Unterbrechung Motor Achse 1/3\tPassenger mirror: motor axis 1/3 open circuit
Beifahrerspiegel: Unterbrechung Motor Achse 2/4\tPassenger mirror: motor axis 2/4 open circuit
Beifahrerspiegel: Unterbrechung Motor Einklappen\tPassenger mirror: fold motor open circuit
Belueftungsklappenmotor\tVent flap motor
Bereichsueberschreitung Momentenberechnung\tTorque calculation out of range
Bereichsueberwachung minimales Motormoment\tMinimum engine torque range check
Bordnetzspannung Hauptrelais\tSupply voltage at main relay
Bremsentemperatur Ueberhitzung\tBrake overheating
Bremslichtschalter\tBrake light switch
Bremslichtschalter Leitungsunterbrechung\tBrake light switch open circuit
Bremslichtschalter Plausibilitaet\tBrake light switch implausible
Bremsschalter Fehler\tBrake switch fault
Bus-Off lokaler SMG-CAN\tLocal SMG CAN bus off
CAN BUS OFF\tCAN bus off
CAN Fehler\tCAN fault
CAN Motorleistungssteuerung\tCAN engine power control
CAN-Bus DME\tCAN bus engine computer (DME)
CAN-Timeout ZSG\tCAN timeout, central module (ZSG)
Checksumme Fehler EEPROM BMW-Bereich\tEEPROM checksum error (BMW area)
Checksumme Fehler EEPROM Bosch-Bereich\tEEPROM checksum error (Bosch area)
Clock-Monitor-Reset\tClock monitor reset
Codierung Fehler\tCoding error
DME-Status\tEngine computer (DME) status
DME-Wechselcode XOR-Fehler\tDME rolling code XOR error
DME-Wechselcode verloren\tDME rolling code lost
DMER1 CAN Botschaftsfehler\tDME message 1 CAN error
DMER2 CAN Botschaftsfehler\tDME message 2 CAN error
DSC meldet V-Fehler\tDSC reports vehicle-speed fault
DSC passiv nach Uz wegen Einstreuung\tDSC off after ignition-on due to interference
DSC-Eingriff unplausibel\tDSC intervention implausible
Dauerhafter Bremslichtschalter\tBrake light switch stuck on
Dauerregelung\tContinuous control intervention
Diebstahlwarnanlage: Innenraumschutz\tAlarm: interior protection
Diebstahlwarnanlage: Innenraumschutz hinten\tAlarm: rear interior protection
Diebstahlwarnanlage: Neigungsgeber\tAlarm: tilt sensor
Diebstahlwarnanlage: Sirene, Funkinnenraumschutz, Neigungsgeber oder Leitung STDWA Kurzschluss gegen Masse oder Leitungsunterbrechung\tAlarm: siren, interior radar, tilt sensor or alarm wire shorted to ground or open
Diebstahlwarnanlage: Sirene, Funkinnenraumschutz, Neigungsgeber oder Leitung STDWA Kurzschluss gegen U-Batt\tAlarm: siren, interior radar, tilt sensor or alarm wire shorted to battery voltage
Differentialsperre\tDifferential lock
Drehraten Sensor\tYaw rate sensor
Drehraten Sensor Leitungsunterbrechung\tYaw rate sensor open circuit
Drehraten Sensor Plausibilitaet\tYaw rate sensor implausible
Drehzahlfuehler hinten links Leitungsunterbrechung\tWheel speed sensor rear left open circuit
Drehzahlfuehler hinten links Plausibilitaet\tWheel speed sensor rear left implausible
Drehzahlfuehler hinten rechts Leitungsunterbrechung\tWheel speed sensor rear right open circuit
Drehzahlfuehler hinten rechts Plausibilitaet\tWheel speed sensor rear right implausible
Drehzahlfuehler vorne links Leitungsunterbrechung\tWheel speed sensor front left open circuit
Drehzahlfuehler vorne links Plausibilitaet\tWheel speed sensor front left implausible
Drehzahlfuehler vorne rechts Leitungsunterbrechung\tWheel speed sensor front right open circuit
Drehzahlfuehler vorne rechts Plausibilitaet\tWheel speed sensor front right implausible
Drehzahlsignalausgang TD\tEngine speed signal output (TD)
Drosselklappenpoti 1\tThrottle position sensor 1
Drosselklappenpoti 2\tThrottle position sensor 2
Drosselklappenpoti 2 Slave\tThrottle position sensor 2 (slave)
Drosselklappenpotis Vergleich\tThrottle position sensors disagree
Drosselklappenwinkel\tThrottle angle
Druck Sensor (Offset)\tPressure sensor offset
Druck Sensor (Plausibilitaet Vorlade Pumpe)\tPressure sensor (precharge pump plausibility)
Druck Sensor Einstreuung\tPressure sensor interference
Druck Sensor Leitungsunterbrechung\tPressure sensor open circuit
Drucksensor\tPressure sensor
Drucksensor, AUC Versorgung\tPressure sensor / AUC supply
Durchfluss zu klein\tFlow too low
E-Box-Luefter\tElectronics box fan
ECD aktiv\tECD active
ECD passiv\tECD inactive
EDK-Geber\tElectronic throttle sensor
EDK-Hardware\tElectronic throttle hardware
EDK-Steller Istwert\tElectronic throttle actuator actual value
EGAS-Regelung\tElectronic throttle control
EGAS-Soll-Ist-Vergleich\tElectronic throttle target vs actual
EGAS-Steller\tElectronic throttle actuator
EGAS-Steller Selbsttest\tElectronic throttle actuator self-test
EHC Luftfeder CAN Botschaftsfehler\tEHC air suspension CAN message error
EKP-Crash-Abschaltung\tFuel pump crash cut-off
EVANOS1-Fruehventil\tIntake VANOS bank 1 advance solenoid
EVANOS1-Hallgeber\tIntake cam sensor (Hall) bank 1
EVANOS1-Regelung\tIntake VANOS bank 1 control
EVANOS1-Spaetventil\tIntake VANOS bank 1 retard solenoid
EVANOS2-Fruehventil\tIntake VANOS bank 2 advance solenoid
EVANOS2-Hallgeber\tIntake cam sensor (Hall) bank 2
EVANOS2-Regelung\tIntake VANOS bank 2 control
EVANOS2-Spaetventil\tIntake VANOS bank 2 retard solenoid
EWS-Schnittstelle\tImmobilizer (EWS) interface
EWS-Signalmanipulation\tImmobilizer (EWS) signal tampering
Einspritzventil 1\tInjector 1
Einspritzventil 2\tInjector 2
Einspritzventil 3\tInjector 3
Einspritzventil 4\tInjector 4
Einspritzventil 5\tInjector 5
Einspritzventil 6\tInjector 6
Einspritzventil 7\tInjector 7
Einspritzventil 8\tInjector 8
Einstreuung\tInterference
Elektroluefter\tElectric radiator fan
Energiesparmode gesetzt\tEnergy-saving mode set
Entfrostungsklappenmotor\tDefrost flap motor
Erkennung hängender Sensor nach längerer Fzg.-Standzeit\tStuck sensor detected after long standstill
Fahrerspiegel: Interner Fehler: Timer Watchdog\tDriver mirror: internal fault (watchdog timer)
Fahrerspiegel: Kurzschluss Heizung\tDriver mirror: heater short circuit
Fahrerspiegel: Kurzschluss Motor Achse 1/3\tDriver mirror: motor axis 1/3 short circuit
Fahrerspiegel: Kurzschluss Motor Achse 2/4\tDriver mirror: motor axis 2/4 short circuit
Fahrerspiegel: Kurzschluss Motor Einklappen\tDriver mirror: fold motor short circuit
Fahrerspiegel: Potentiometer Achse 1/3\tDriver mirror: position sensor axis 1/3
Fahrerspiegel: Potentiometer Achse 2/4\tDriver mirror: position sensor axis 2/4
Fahrerspiegel: Unterbrechung Heizung\tDriver mirror: heater open circuit
Fahrerspiegel: Unterbrechung Motor Achse 1/3\tDriver mirror: motor axis 1/3 open circuit
Fahrerspiegel: Unterbrechung Motor Achse 2/4\tDriver mirror: motor axis 2/4 open circuit
Fahrerspiegel: Unterbrechung Motor Einklappen\tDriver mirror: fold motor open circuit
Fahrstrecke seit Auftreten des Fehlers\tDistance driven since the fault occurred
Fahrzeuggeschwindigkeit\tVehicle speed
Falsches Zahnrad\tWrong tone wheel
Fehler Lenkwinkel Steuergeraet\tSteering angle module fault
Fehler Sicherheitsabschaltung\tSafety shutdown fault
Fehler Soll-Istvergleich\tTarget vs actual mismatch
Fehler abgasrelevant OBD\tEmissions-relevant (OBD) fault
Fehler bei leerem Tank\tFault with tank nearly empty
Fehler momentan nicht vorhanden\tFault not currently present
Fehler momentan vorhanden\tFault currently present
Fehler nach Entprellung abgespeichert\tFault stored after debounce
Fehlerkennzeichnung T_Umg. in CAN-Botschaft\tAmbient temperature flagged faulty in CAN message
Fehlerspeicher Pruefsumme falsch\tFault memory checksum wrong
Feinleck\tSmall leak
Fensterheber: Relais klebt bei Beifahrerseite hinten\tWindow: relay stuck, rear passenger side
Fensterheber: Relais klebt bei Beifahrertuer\tWindow: relay stuck, passenger door
Fensterheber: Relais klebt bei Fahrerseite hinten\tWindow: relay stuck, rear driver side
Fensterheber: Relais klebt bei Fahrertuer\tWindow: relay stuck, driver door
Fensterheber: Sicherung\tWindow: fuse
Fensterheber: Unterbrechung Einklemmschutzleiste oder Denormierung/Fehler EKS-Elektronik Beifahrerseite hinten\tWindow: anti-trap strip open or anti-trap electronics fault, rear passenger side
Fensterheber: Unterbrechung Einklemmschutzleiste oder Denormierung/Fehler EKS-Elektronik Beifahrertuer\tWindow: anti-trap strip open or anti-trap electronics fault, passenger door
Fensterheber: Unterbrechung Einklemmschutzleiste oder Denormierung/Fehler EKS-Elektronik Fahrerseite hinten\tWindow: anti-trap strip open or anti-trap electronics fault, rear driver side
Fensterheber: Unterbrechung Einklemmschutzleiste oder Denormierung/Fehler EKS-Elektronik Fahrertuer\tWindow: anti-trap strip open or anti-trap electronics fault, driver door
Fensterheber: Unterbrechung Motor oder Relais Beifahrerseite hinten\tWindow: motor or relay open circuit, rear passenger side
Fensterheber: Unterbrechung Motor oder Relais Beifahrertuer\tWindow: motor or relay open circuit, passenger door
Fensterheber: Unterbrechung Motor oder Relais Fahrerseite hinten\tWindow: motor or relay open circuit, rear driver side
Fensterheber: Unterbrechung Motor oder Relais Fahrertuer\tWindow: motor or relay open circuit, driver door
Fensterheberschalter HL Signal ungültig\tWindow switch rear left: invalid signal
Fensterheberschalter HR Signal ungültig\tWindow switch rear right: invalid signal
Fensterheberschalter VL Signal ungültig\tWindow switch front left: invalid signal
Fensterheberschalter VR Signal ungültig\tWindow switch front right: invalid signal
Fettsprungzeit zu lang\tRich switching time too long
Fettsprungzeitguete 1\tRich switching time quality, bank 1
Fettsprungzeitguete 2\tRich switching time quality, bank 2
Formatfehler\tFormat error
Frischluft/Umluftklappenmotor links\tFresh/recirculated air flap motor, left
Frischluft/Umluftklappenmotor rechts\tFresh/recirculated air flap motor, right
Fuellstandsplausibilisierung\tFuel level plausibility
Funktionspruefung TEV\tPurge valve function check
Fussraumklappenmotor\tFootwell flap motor
GKS Geräuschklappenwinkel\tIntake sound flap angle
GKS-Regler\tSound flap controller
GKS-Treiber\tSound flap driver
GKS_ST Status GKS\tSound flap status
Geblaesesteuerspannung\tBlower control voltage
Gesamtluftmasse\tTotal air mass
Geschwindigkeit CAN\tSpeed (CAN)
Geschwindigkeit diskret\tSpeed (direct signal)
Geschwindigkeitseingang direkt\tSpeed input (direct)
Getriebestatus\tTransmission status
Getriebesteuerung CAN Botschaftsfehler\tTransmission control CAN message error
Gierratensensor Verdacht auf falsche Einbaulage\tYaw rate sensor possibly installed wrongly
Gierratensensor falsche Einbaulage\tYaw rate sensor installed wrongly
Grenzwert ueberschritten\tLimit exceeded
Grenzwertueberschreitungen 1\tLimit exceeded, bank 1
Grenzwertueberschreitungen 2\tLimit exceeded, bank 2
Grobleck\tLarge leak
Grundmodul V: uncodiert oder Codierung verloren\tBody module: not coded or coding lost
Guete KAT-Konvertierung 1\tCatalyst efficiency quality, bank 1
Guete KAT-Konvertierung 2\tCatalyst efficiency quality, bank 2
HBA aktiv\tBrake assist active
HBA passiv\tBrake assist inactive
HDC aktiv\tHill descent control active
HDC nicht verfuegbar\tHill descent control unavailable
HDC passiv\tHill descent control inactive
Heizung defekt\tHeater faulty
Hochlauf n zu v\tEngine speed vs road speed run-up
Illegal-Opcode-Trap\tIllegal opcode trap
Info Tankdeckel fehlt\tInfo: fuel cap missing
Innenfuehlergeblaese\tInterior sensor fan
Innenlicht: Kurzschluss\tInterior light: short circuit
Innenlicht: Leitungsunterbrechung\tInterior light: open circuit
Innenraumtemperaturfuehler\tInterior temperature sensor
Integral TV-Versch. n. Kat 1\tDuty-cycle shift integral after catalyst, bank 1
Integral TV-Versch. n. Kat 2\tDuty-cycle shift integral after catalyst, bank 2
Interner Fehler im Grundmodul V: Checksum ROM\tBody module internal fault: ROM checksum
Interner Fehler im Grundmodul V: EEPROM\tBody module internal fault: EEPROM
Interner Fehler im Grundmodul V: Prozessor Interrupt\tBody module internal fault: processor interrupt
Interner Fehler im Grundmodul V: Prozessor ROM\tBody module internal fault: processor ROM
Interner Fehler im Grundmodul V: Prozessor Watchdog\tBody module internal fault: processor watchdog
Interner Fehler im Grundmodul V: Taktgeber\tBody module internal fault: clock
Interner Fehler im Grundmodul V: interne Spannung\tBody module internal fault: internal voltage
Istwert zu gross\tActual value too high
Istwert zu klein\tActual value too low
K-Bus\tK-bus
K-Bus oder Steuergeraet fuer Instrumenten-Kombination (Gateway)\tK-bus or instrument cluster (gateway)
KAT-Konvertierung 1\tCatalyst efficiency, bank 1
KAT-Konvertierung 2\tCatalyst efficiency, bank 2
KAT-Schutz aktiv bei leerem Tank\tCatalyst protection active with tank nearly empty
KAT-Temperatur\tCatalyst temperature
KAT-schaedigend\tCatalyst-damaging
KFK-Steller Istwert\tThrottle actuator actual value
KL50 Anlasserschalter0\tTerminal 50 (starter) signal
KW-Induktivgeber\tCrankshaft position sensor
Kein EWS-Wechselcode gespeichert\tNo EWS rolling code stored
Kein Fehlerspeicher gespeichert\tNo fault memory stored
Kein Kraftschluss bei Fahrt\tNo drive engagement while moving
Keine Adaptionen und Abgleichwerte gespeichert\tNo adaptations or calibration values stored
Klemme R\tTerminal R (accessory)
Klimakompressorrelais\tA/C compressor relay
Klopfbaustein 1\tKnock processing chip 1
Klopfbaustein 2\tKnock processing chip 2
Klopfsensor 1\tKnock sensor 1
Klopfsensor 2\tKnock sensor 2
Klopfsensor 3\tKnock sensor 3
Klopfsensor 4\tKnock sensor 4
Kombi-Relativzeit\tInstrument cluster relative time
Kraftschluss im Stillstand\tDrive engaged while stationary
Kraftstoffsystemdiagnose 1\tFuel system diagnosis bank 1
Kraftstoffsystemdiagnose 2\tFuel system diagnosis bank 2
Kuehleraustrittstemp.\tRadiator outlet temperature
Kuehleraustrittstemperaturfuehler\tRadiator outlet temperature sensor
Kuehlwassertemp.\tCoolant temperature
Kuehlwassertemperaturfuehler\tCoolant temperature sensor
Kurbelgehäuseentlüftung\tCrankcase ventilation
Kurzschluss gegen Masse\tShort to ground
Kurzschluss gegen U-Batt\tShort to battery voltage
LDP-Heizung\tLeak detection pump heater
LDP-Messstrom\tLeak detection pump measuring current
LDP-Messzeit\tLeak detection pump measuring time
LDP-Minimalstrom\tLeak detection pump minimum current
LDP-Referenzstrom\tLeak detection pump reference current
LED Fahrdynamikschalter\tSport/driving-dynamics switch LED
Laengsbeschleunigung\tLongitudinal acceleration
Lageregler reagiert nicht\tPosition controller not responding
Lambda-Adaptionsfaktor 1\tMixture adaptation factor bank 1
Lambda-Adaptionsfaktor 2\tMixture adaptation factor bank 2
Lambda-Adaptionsoffset 1\tMixture adaptation offset bank 1
Lambda-Adaptionsoffset 2\tMixture adaptation offset bank 2
Lambda-Regelfaktor 1\tLambda control factor bank 1
Lambda-Regelfaktor 2\tLambda control factor bank 2
Lambdaregler 1\tLambda controller bank 1
Lambdaregler 2\tLambda controller bank 2
Lambdasonde 1 nach Kat\tOxygen sensor bank 1 after catalyst
Lambdasonde 1 vor Kat\tOxygen sensor bank 1 before catalyst
Lambdasonde 2 nach Kat\tOxygen sensor bank 2 after catalyst
Lambdasonde 2 vor Kat\tOxygen sensor bank 2 before catalyst
Lambdasondenhzg. 1 nach Kat\tOxygen sensor heater bank 1 after catalyst
Lambdasondenhzg. 1 vor Kat\tOxygen sensor heater bank 1 before catalyst
Lambdasondenhzg. 2 nach Kat\tOxygen sensor heater bank 2 after catalyst
Lambdasondenhzg. 2 vor Kat\tOxygen sensor heater bank 2 before catalyst
Latentwaermespeicher Absperrventil\tHeat storage shut-off valve
Latentwaermespeicher Temperaturfuehler\tHeat storage temperature sensor
Latentwaermespeicher Umschaltventil\tHeat storage changeover valve
Leckluft\tAir leak
Leerlauf Verlustadapt.\tIdle loss adaptation
Leerlauf-MAX-Fehler\tIdle mixture too lean (adaptation at max)
Leerlauf-MIN-Fehler\tIdle mixture too rich (adaptation at min)
Leerlaufregler\tIdle speed controller
Leerlaufsolldrehzahl\tTarget idle speed
Leitungsunterbrechung\tOpen circuit
Lenkwinkel Botschaftsfehler\tSteering angle message error
Lenkwinkel Plausibilitaet\tSteering angle implausible
Lenkwinkel Sensor Aufsetzalgorithmus\tSteering angle sensor initialisation
Lenkwinkelabgleich notwendig\tSteering angle calibration required
Lichtmodul-EEPROM-Fehler\tLight module EEPROM fault
Luftmasse zu DKG-Stellung unplausibel\tAir mass implausible for throttle position
Luftmassenmesser 1\tAir mass meter 1
Luftmassenmesser 2\tAir mass meter 2
MFL-Schnittstelle\tSteering wheel controls interface
MIL-Anforderung durch SMG\tCheck-engine light requested by SMG
MIL-Extern-Info\tCheck-engine light, external info
Magersprungzeit zu lang\tLean switching time too long
Magersprungzeitguete 1\tLean switching time quality, bank 1
Magersprungzeitguete 2\tLean switching time quality, bank 2
Manipulation\tTampering
Maximaldrehzahl\tMaximum engine speed
Modul Tankleckdiagnose\tTank leak diagnosis module
Motordrehzahl\tEngine speed
Motorgeraeusch\tEngine noise
NW-Geber 1 Synchronisation gegen KW\tCam sensor 1 sync vs crankshaft
NW-Geber 2 Synchronisation gegen KW\tCam sensor 2 sync vs crankshaft
Nachkatsonde 1 Spannungsueberw.\tPost-catalyst oxygen sensor bank 1 voltage check
Nachkatsonde 2 Spannungsueberw.\tPost-catalyst oxygen sensor bank 2 voltage check
Notbremse drucklos\tEmergency brake unpressurised
Oberer Regleranschlag\tUpper control limit reached
Oeffnerwicklung Leerlaufsteller\tIdle control valve opening winding
Oelkreisventil links\tOil circuit valve left
Oelkreisventil rechts\tOil circuit valve right
Oeltemperatur TOG\tOil temperature (oil level/temp sensor)
P-Sprungzaehler 1\tP-jump counter bank 1
P-Sprungzaehler 2\tP-jump counter bank 2
Pedalwert 1 Vergleich\tPedal sensor 1 comparison
Pedalwert 2 Vergleich\tPedal sensor 2 comparison
Pedalwertgeber 1\tAccelerator pedal sensor 1
Pedalwertgeber 2\tAccelerator pedal sensor 2
Periodendauer zu gross\tPeriod too long
Periodendauer zu klein\tPeriod too short
Periodendauermessung 1\tPeriod measurement bank 1
Periodendauermessung 2\tPeriod measurement bank 2
Plausibilisierung Kühleraustrittstemp.\tRadiator outlet temperature plausibility
Plausibilisierung Motortemperatur\tEngine temperature plausibility
Plausibilität Lastsignal\tLoad signal plausibility
Poti Geräuschklappe GKS\tSound flap position sensor
Power-On-Reset\tPower-on reset
Primaerkreis\tPrimary circuit
Pruefwort nicht erkannt\tCheck word not recognised
Pulsbreite zu gross\tPulse width too long
Pulsbreite zu klein\tPulse width too short
Querbeschleunigung\tLateral acceleration
Querbeschleunigung Sensor\tLateral acceleration sensor
Querbeschleunigung Sensor Leitungsunterbrechung\tLateral acceleration sensor open circuit
Querbeschleunigung Sensor Plausibilitaet\tLateral acceleration sensor implausible
Quittierung ASC\tASC acknowledgement
RAM-Zelle\tRAM cell
ROM-Zelle/Manipulation\tROM cell / tampering
Redundanzvergleich\tRedundancy comparison
Referenzstrom zu gross\tReference current too high
Referenzstrom zu klein\tReference current too low
Reifendruck hinten links\tTyre pressure rear left
Reifendruck hinten rechts\tTyre pressure rear right
Reifendruck vorn links\tTyre pressure front left
Reifendruck vorn rechts\tTyre pressure front right
Relais Heckscheibenheizung\tRear window heater relay
Relais Kraftstoffpumpe\tFuel pump relay
Reset allgemein\tGeneral reset
Rueckfoerderpumpen Fehler\tReturn pump fault
SIA-Reset\tService indicator reset
SIM-Register\tSIM register
SMG Schaltablauf\tSMG shift sequence
SMG Sicherheitskonzept\tSMG safety concept
SN-Ueberwachung\tSN monitoring
Saugrohrdruck\tIntake manifold pressure
Saugstrahlpumpe\tSuction jet pump
Schalter klemmt\tSwitch stuck
Schalterkette Kraftschluss\tDrive engagement switch chain
Schliesserwicklung Leerlaufsteller\tIdle control valve closing winding
Schliessfedern defekt\tClosing springs faulty
Schluessel Nr.0 ungueltig wegen fehlerhaftem Passwort\tKey 0 invalid: wrong password
Schluessel Nr.0 ungueltig wegen fehlerhaftem Wechselcode\tKey 0 invalid: wrong rolling code
Schluessel Nr.0 ungueltig wegen fehlerhafter Identifikation\tKey 0 invalid: wrong identification
Schluessel Nr.1 ungueltig wegen fehlerhaftem Passwort\tKey 1 invalid: wrong password
Schluessel Nr.1 ungueltig wegen fehlerhaftem Wechselcode\tKey 1 invalid: wrong rolling code
Schluessel Nr.1 ungueltig wegen fehlerhafter Identifikation\tKey 1 invalid: wrong identification
Schluessel Nr.2 ungueltig wegen fehlerhaftem Passwort\tKey 2 invalid: wrong password
Schluessel Nr.2 ungueltig wegen fehlerhaftem Wechselcode\tKey 2 invalid: wrong rolling code
Schluessel Nr.2 ungueltig wegen fehlerhafter Identifikation\tKey 2 invalid: wrong identification
Schluessel Nr.3 ungueltig wegen fehlerhaftem Passwort\tKey 3 invalid: wrong password
Schluessel Nr.3 ungueltig wegen fehlerhaftem Wechselcode\tKey 3 invalid: wrong rolling code
Schluessel Nr.3 ungueltig wegen fehlerhafter Identifikation\tKey 3 invalid: wrong identification
Schluessel Nr.4 ungueltig wegen fehlerhaftem Passwort\tKey 4 invalid: wrong password
Schluessel Nr.4 ungueltig wegen fehlerhaftem Wechselcode\tKey 4 invalid: wrong rolling code
Schluessel Nr.4 ungueltig wegen fehlerhafter Identifikation\tKey 4 invalid: wrong identification
Schluessel Nr.5 ungueltig wegen fehlerhaftem Passwort\tKey 5 invalid: wrong password
Schluessel Nr.5 ungueltig wegen fehlerhaftem Wechselcode\tKey 5 invalid: wrong rolling code
Schluessel Nr.5 ungueltig wegen fehlerhafter Identifikation\tKey 5 invalid: wrong identification
Schluessel Nr.6 ungueltig wegen fehlerhaftem Passwort\tKey 6 invalid: wrong password
Schluessel Nr.6 ungueltig wegen fehlerhaftem Wechselcode\tKey 6 invalid: wrong rolling code
Schluessel Nr.6 ungueltig wegen fehlerhafter Identifikation\tKey 6 invalid: wrong identification
Schluessel Nr.7 ungueltig wegen fehlerhaftem Passwort\tKey 7 invalid: wrong password
Schluessel Nr.7 ungueltig wegen fehlerhaftem Wechselcode\tKey 7 invalid: wrong rolling code
Schluessel Nr.7 ungueltig wegen fehlerhafter Identifikation\tKey 7 invalid: wrong identification
Schluessel Nr.8 ungueltig wegen fehlerhaftem Passwort\tKey 8 invalid: wrong password
Schluessel Nr.8 ungueltig wegen fehlerhaftem Wechselcode\tKey 8 invalid: wrong rolling code
Schluessel Nr.8 ungueltig wegen fehlerhafter Identifikation\tKey 8 invalid: wrong identification
Schluessel Nr.9 ungueltig wegen fehlerhaftem Passwort\tKey 9 invalid: wrong password
Schluessel Nr.9 ungueltig wegen fehlerhaftem Wechselcode\tKey 9 invalid: wrong rolling code
Schluessel Nr.9 ungueltig wegen fehlerhafter Identifikation\tKey 9 invalid: wrong identification
Sekundaerkreis\tSecondary circuit
Sekundaerluft Mindestdurchfluss\tSecondary air minimum flow
Sekundaerluftpumpenrelais\tSecondary air pump relay
Sekundaerluftventil\tSecondary air valve
Sekundaerluftventil klemmt\tSecondary air valve stuck
Sensorversorgung 1\tSensor supply 1
Sensorversorgung 1 Master\tSensor supply 1 (master)
Sensorversorgung 2\tSensor supply 2
Sensorversorgung 2 Master\tSensor supply 2 (master)
Servotronik Geschwindigkeitssignal\tServotronic speed signal
Servotronikventil Strommessung\tServotronic valve current measurement
Sicherheitsabschaltung FGR\tCruise control safety shutdown
Signal TWEG+ (Tacho)\tSpeedometer signal (TWEG+)
Signal aktiver Oelniveaugeber\tActive oil level sensor signal
Signal unplausibel gegen Fuellung\tSignal implausible vs cylinder filling
Signallage unplausibel\tSignal level implausible
Signalpegel zu gross\tSignal level too high
Signalpegel zu niedrig\tSignal level too low
Software-Interrupt\tSoftware interrupt
Software-Reset\tSoftware reset
Sollwert nicht erreicht\tTarget not reached
Sondenheizwiderst. 1 n. Kat\tOxygen sensor heater resistance bank 1 after catalyst
Sondenheizwiderst. 1 v. Kat\tOxygen sensor heater resistance bank 1 before catalyst
Sondenheizwiderst. 2 n. Kat\tOxygen sensor heater resistance bank 2 after catalyst
Sondenheizwiderst. 2 v. Kat\tOxygen sensor heater resistance bank 2 before catalyst
Sondenhub 1 (max-min)\tOxygen sensor swing bank 1 (max-min)
Sondenhub 2 (max-min)\tOxygen sensor swing bank 2 (max-min)
Sondenhub zu klein\tOxygen sensor swing too small
Sondenspannung bei Wiedereinsetzen\tOxygen sensor voltage on fuel resume
Sondenspannung nach Schub unplausibel\tOxygen sensor voltage implausible after overrun
Sondenspannung zu fett nach Schubabschalten\tOxygen sensor reads rich after overrun cut-off
Sondenspannung zu mager nach Wiedereinsetzen\tOxygen sensor reads lean after fuel resume
Spannungsfehler aktive DF\tVoltage fault, active alternator signal
Spg. Lambdasonde 1 n. Kat\tOxygen sensor voltage bank 1 after catalyst
Spg. Lambdasonde 1 v. Kat\tOxygen sensor voltage bank 1 before catalyst
Spg. Lambdasonde 2 n. Kat\tOxygen sensor voltage bank 2 after catalyst
Spg. Lambdasonde 2 v. Kat\tOxygen sensor voltage bank 2 before catalyst
Spiegelverstellschalter (Horizontal) Signal ungültig\tMirror switch (horizontal): invalid signal
Spiegelverstellschalter (Vertikal) Signal ungültig\tMirror switch (vertical): invalid signal
Spoilerverstellung/TOG-Lampe\tSpoiler adjustment / oil level lamp
Startrelais\tStarter relay
Startwert defekt\tStart value faulty
Startwert leer\tStart value empty
Status DME Interner Fehler\tEngine computer internal fault
Status NKAT-Alterung\tPost-catalyst sensor aging status
Status Sicherheitsueberw.\tSafety monitoring status
Steuergeraete Fehler\tControl module fault
Stromverlauf unplausibel\tCurrent curve implausible
System Saugstrahlpumpe\tSuction jet pump system
Systemcheck Kurbelgehäuseentlüftung\tCrankcase ventilation system check
T-Erhöhung zu gering oder Kühler wärmer als Motor\tTemperature rise too small, or radiator hotter than engine
TOG\tOil level/temperature sensor
TV-Verschiebung nach KAT zu gross\tDuty-cycle shift after catalyst too large
TV-Verschiebung vor KAT zu gross\tDuty-cycle shift before catalyst too large
TV-Wert zu gross\tDuty-cycle value too high
TV-Wert zu klein\tDuty-cycle value too low
TXU Gelaendeuntersetzungsgetriebe CAN Botschaftsfehler\tTransfer case CAN message error
Tacho A\tSpeedometer A
Tank-Hebelgeber_links\tFuel level sender left
Tank-Hebelgeber_rechts\tFuel level sender right
Tankentlueftungsadaption 1\tPurge adaptation bank 1
Tankentlueftungsadaption 2\tPurge adaptation bank 2
Tankentlueftungsventil\tPurge (tank vent) valve
Tankfuellstand\tFuel level
Tankfuelstand (CAN)\tFuel level (CAN)
Tankleck\tFuel tank leak
Tastverh. Tankentlueftung\tPurge valve duty cycle
Teillast-MAX-Fehler\tPart-load mixture too lean (adaptation at max)
Teillast-MIN-Fehler\tPart-load mixture too rich (adaptation at min)
Telegramm nicht empfangen\tMessage not received
Telegramminhalt unplausibel\tMessage content implausible
Tempomatsystem\tCruise control system
Timeout\tTimeout
Timeout DSC-Botschaft\tDSC message timeout
Timeout KOMBI-Botschaft\tInstrument cluster message timeout
Timeout LWS-Botschaft\tSteering angle sensor message timeout
Timeout SMG-CAN\tSMG CAN timeout
Treiberabschaltung wegen Ueberlast\tDriver shut off due to overload
Ueberspannung\tOvervoltage
Ueberspannung (U>16V)\tOvervoltage (above 16 V)
Uebertemp. EV-Treiber 1\tInjector driver 1 over-temperature
Uebertemp. EV-Treiber 2\tInjector driver 2 over-temperature
Ueberwachung AD-Wandler\tA/D converter monitoring
Ueberwachung Momentenmanager\tTorque manager monitoring
Ueberwachung Nullmomentenvorgabe\tZero-torque request monitoring
Ueberwachung Soll-/Istmoment\tTarget/actual torque monitoring
Umgebungsdruck\tAmbient pressure
Umgebungstemp. CAN\tAmbient temperature (CAN)
Umgebungstemperatur\tAmbient temperature
Umweltbed. unbekannt\tConditions unknown
Unterbrechung o. Kurzschluss\tOpen or short circuit
Unterer Regleranschlag\tLower control limit reached
Unterspannung\tUndervoltage
V-Vergleich\tSpeed comparison
Vanos-Druckspeicherventil\tVANOS pressure accumulator valve
Ventil Auslass hinten links\tOutlet valve rear left
Ventil Auslass hinten rechts\tOutlet valve rear right
Ventil Auslass vorne links\tOutlet valve front left
Ventil Auslass vorne rechts\tOutlet valve front right
Ventil Einlass hinten links\tInlet valve rear left
Ventil Einlass hinten rechts\tInlet valve rear right
Ventil Einlass vorne links\tInlet valve front left
Ventil Einlass vorne rechts\tInlet valve front right
Ventil Tankleckdiagnose\tTank leak diagnosis valve
Ventil klemmt\tValve stuck
Ventilrelais Fehler\tValve relay fault
Verbraucherabschaltung 1: Kurzschluss gegen Masse\tLoad shedding 1: short to ground
Verbraucherabschaltung 2: Kurzschluss gegen Masse\tLoad shedding 2: short to ground
Verbraucherabschaltung 2: Kurzschluss gegen U-Batt\tLoad shedding 2: short to battery voltage
Verbrauchssignalausgang KVA\tFuel consumption signal output
Verdampferfuehler\tEvaporator temperature sensor
Versorgungsspannung HR\tSupply voltage, main relay
Verzoegerungsabschaltung\tDelayed switch-off
Vorkatsonde 1 Periodendauer\tPre-catalyst oxygen sensor bank 1 period
Vorkatsonde 1 Signalhub\tPre-catalyst oxygen sensor bank 1 signal swing
Vorkatsonde 1 Sprungzeit\tPre-catalyst oxygen sensor bank 1 switching time
Vorkatsonde 1 TV-Verschiebung\tPre-catalyst oxygen sensor bank 1 duty-cycle shift
Vorkatsonde 2 Periodendauer\tPre-catalyst oxygen sensor bank 2 period
Vorkatsonde 2 Signalhub\tPre-catalyst oxygen sensor bank 2 signal swing
Vorkatsonde 2 Sprungzeit\tPre-catalyst oxygen sensor bank 2 switching time
Vorkatsonde 2 TV-Verschiebung\tPre-catalyst oxygen sensor bank 2 duty-cycle shift
Vorlade Pumpe\tPrecharge pump
Vorlade Ventil Hinterachse\tPrecharge valve rear axle
Vorlade Ventil Vorderachse\tPrecharge valve front axle
WC-Toleranz erhoeht bei Schluessel Nummer 0\tRolling-code tolerance raised for key 0
WC-Toleranz erhoeht bei Schluessel Nummer 1\tRolling-code tolerance raised for key 1
WC-Toleranz erhoeht bei Schluessel Nummer 2\tRolling-code tolerance raised for key 2
WC-Toleranz erhoeht bei Schluessel Nummer 3\tRolling-code tolerance raised for key 3
WC-Toleranz erhoeht bei Schluessel Nummer 4\tRolling-code tolerance raised for key 4
WC-Toleranz erhoeht bei Schluessel Nummer 5\tRolling-code tolerance raised for key 5
WC-Toleranz erhoeht bei Schluessel Nummer 6\tRolling-code tolerance raised for key 6
WC-Toleranz erhoeht bei Schluessel Nummer 7\tRolling-code tolerance raised for key 7
WC-Toleranz erhoeht bei Schluessel Nummer 8\tRolling-code tolerance raised for key 8
WC-Toleranz erhoeht bei Schluessel Nummer 9\tRolling-code tolerance raised for key 9
Waermetauscherfuehler\tHeater core temperature sensor
Wasserventil\tHeater water valve
Watchdog-Reset\tWatchdog reset
Wechselcode verloren\tRolling code lost
Wischer: Pumpe fuer Scheibenwaschen oder Behaelter leer\tWipers: washer pump, or reservoir empty
Wischer: Relais Pumpe oder Leitung fuer Scheinwerferreinigung\tWipers: headlight washer pump relay or wiring
Wischer: Relais fehlt oder Relais / Leitung fuer Wischerstufe 2\tWipers: relay missing, or speed-2 relay/wiring
Wischer: Relais oder Leitung fuer Wischer ein\tWipers: wiper-on relay or wiring
Wischer: Sicherung fuer Pumpe, Innenlicht, Verbraucherabschaltung\tWipers: fuse for pump, interior light, load shedding
Wischer: blockiert oder Rueckstellkontakt\tWipers: blocked, or park contact
Wischerschalter (Potentiometer): Kurzschluss gegen Masse\tWiper switch (potentiometer): short to ground
Wischerschalter (Potentiometer): Leitungsunterbrechung oder Kurzschluss gegen U-Batt\tWiper switch (potentiometer): open circuit or short to battery voltage
Zentralverriegelung Relais Entriegeln: Oeffnerkontakt unterbricht oder Schliesserkontakt klebt\tCentral locking unlock relay: contact open or stuck
Zentralverriegelung Relais Sichern: Oeffnerkontakt unterbricht oder Schliesserkontakt klebt\tCentral locking deadlock relay: contact open or stuck
Zentralverriegelung Relais Verriegeln Fahrertuer: Oeffnerkontakt unterbricht oder Schliesserkontakt klebt\tCentral locking driver-door lock relay: contact open or stuck
Zentralverriegelung Relais Verriegeln: Oeffnerkontakt unterbricht oder Schliesserkontakt klebt\tCentral locking lock relay: contact open or stuck
Zentralverriegelung: Crash-Eingang dauernd aktiv\tCentral locking: crash input permanently active
Zentralverriegelung: Kurzschluss gegen Masse oder Leitungsunterbrechung bei Relais fuer Entriegeln Heckscheibe\tCentral locking: rear window unlock relay shorted to ground or open
Zentralverriegelung: Kurzschluss oder Leitungsunterbrechung bei Antrieb Heckklappe\tCentral locking: trunk actuator short or open circuit
Zentralverriegelung: Relais zieht nicht an bei Entriegeln\tCentral locking: relay doesn't pull in on unlock
Zentralverriegelung: Relais zieht nicht an bei Sichern\tCentral locking: relay doesn't pull in on deadlock
Zentralverriegelung: Relais zieht nicht an bei Verriegeln\tCentral locking: relay doesn't pull in on lock
Zentralverriegelung: Relais zieht nicht an bei Verriegeln Fahrertuer\tCentral locking: relay doesn't pull in on driver-door lock
Zentralverriegelung: Schlosskontakt Beifahrertuer\tCentral locking: passenger door lock contact
Zentralverriegelung: Schlosskontakt Fahrertuer\tCentral locking: driver door lock contact
Zentralverriegelung: Sicherung\tCentral locking: fuse
Zuendspule 1\tIgnition coil 1
Zuendspule 2\tIgnition coil 2
Zuendspule 3\tIgnition coil 3
Zuendspule 4\tIgnition coil 4
Zuendspule 5\tIgnition coil 5
Zuendspule 6\tIgnition coil 6
Zuendspule 7\tIgnition coil 7
Zuendspule 8\tIgnition coil 8
Zuheizer, Relais Frontscheibenheizung\tAuxiliary heater / windscreen heater relay
Zusatzwasserpumpe\tAuxiliary water pump
Zustand EGAS\tElectronic throttle state
Zustand Nach-Kat-Sonde 1\tPost-catalyst oxygen sensor bank 1 state
Zustand Nach-Kat-Sonde 2\tPost-catalyst oxygen sensor bank 2 state
Zustand Tankentlueftung\tPurge system state
abgasverschlechternd\tWorsens emissions
ausserhalb FTP-Zyklus\tOutside FTP test cycle
beide Baenke zu klein\tBoth banks too low
im 1. Messintervall\tIn first measuring interval
im 1. Messintervall Warmlauf\tIn first measuring interval, warm-up
im Betriebsintervall\tIn operating interval
im Betriebsintervall Warmlauf\tIn operating interval, warm-up
innerhalb FTP-Zyklus\tWithin FTP test cycle
intern: Adaptions-EEPROM Master\tInternal: adaptation EEPROM (master)
intern: Adaptions-EEPROM Slave\tInternal: adaptation EEPROM (slave)
intern: Klopfsignalpfad\tInternal: knock signal path
intern: Kommunikation Master\tInternal: master communication
intern: Prozessorkontrolle Master\tInternal: processor check (master)
intern: Prozessorkontrolle Slave\tInternal: processor check (slave)
intern: Resets Master\tInternal: resets (master)
intern: Resets Slave\tInternal: resets (slave)
intern: Speichertest Master\tInternal: memory test (master)
intern: Speichertest Slave\tInternal: memory test (slave)
intern: Steuergeraetetemperatur\tInternal: module temperature
intern: Treiberdiagnosekette\tInternal: driver diagnosis chain
intern: Umgebungsdrucksensor\tInternal: ambient pressure sensor
internes Interface gestoert\tInternal interface disturbed
kein Druck\tNo pressure
kein Togglebit\tNo toggle bit
kein negativer Gradient\tNo falling edge
kein positiver Gradient\tNo rising edge
keine Antwort Beifahrerspiegel\tNo response from passenger mirror
keine Antwort Fahrerspiegel\tNo response from driver mirror
keine Antwort Schalterblock\tNo response from switch block
keine CAN ID\tNo CAN ID
keine CAN ID ASC1\tNo CAN ID ASC1
keine CAN ID ASC3\tNo CAN ID ASC3
keine CAN ID DME1\tNo CAN ID DME1
keine CAN ID DME2\tNo CAN ID DME2
keine CAN ID DME4\tNo CAN ID DME4
keine CAN ID EGS1\tNo CAN ID EGS1
keine CAN ID SMG1\tNo CAN ID SMG1
klemmt geschlossen\tStuck closed
klemmt offen\tStuck open
nicht belegt\tNot used
relative Fuellung\tRelative cylinder filling
schliessen nicht richtig\tNot closing properly
sporadischer Fehler\tIntermittent fault
statischer Fehler\tPermanent fault
unbekannte Fehlerart\tUnknown fault type
unbekannte Umweltnummer\tUnknown condition number
unbekannter Fehlerort\tUnknown fault location
unerwarteter Code\tUnexpected code
ungueltiger Arbeitsbereich\tInvalid operating range
unplausible Fzg.-Standzeit\tImplausible vehicle standstill time
unplausible Relativzeit während Motor läuft\tImplausible relative time while engine running
unplausible SMG-Inhalte\tImplausible SMG contents
unplausibler Wert, ungueltiger Arbeitsbereich\tImplausible value, invalid operating range
v-Signal unplausibel\tSpeed signal implausible
zeitbegrenzte Passivschaltung\tTime-limited deactivation
zu viele Botschaften\tToo many messages
"""
}
