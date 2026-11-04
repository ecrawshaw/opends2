import Foundation

/// Hand-written English for every coding option (FSW) and value name (PSW) in the E46 coding files
/// this car uses — instrument cluster (kmbe46m3), DSC (mk60), body module (gm5) and immobilizer
/// (ews). Options in other files fall back to `Translate.expandGerman`.
extension Translate {
    static let optionEnglish: [String: String] = parseTSV(optionTSV)
    static let valueEnglish: [String: String] = parseTSV(valueTSV)

    private static func parseTSV(_ s: String) -> [String: String] {
        var m: [String: String] = [:]
        for line in s.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { m[String(parts[0])] = String(parts[1]) }
        }
        return m
    }

    /// English for a value name with a number and unit, e.g. "25.000_km", "16_min", "plus_0.2s",
    /// "4797_imp/km", "6_zylinder_benziner". Nil when it isn't one of these shapes.
    static func valueWithUnit(_ v: String) -> String? {
        let units: [(String, String)] = [
            ("_imp/km", " pulses/km"), ("_tage", " days"), ("_stunden", " hours"), ("_min", " min"),
            ("_sec", " s"), ("_l/min", " l/min"), ("_l/sec", " l/s"), ("_km/h", " km/h"), ("_km", " km"),
            ("_l", " l"), ("_zylinder_benziner", "-cylinder petrol"), ("_zylinder_diesel", "-cylinder diesel"),
        ]
        var s = v
        var sign = ""
        if s.hasPrefix("plus_") { sign = "+"; s.removeFirst(5) }
        if s.hasPrefix("minus_") { sign = "−"; s.removeFirst(6) }
        guard let first = s.first, first.isNumber else { return nil }
        for (suffix, english) in units where s.hasSuffix(suffix) {
            let num = String(s.dropLast(suffix.count))
            guard num.allSatisfy({ $0.isNumber || $0 == "." }) else { continue }
            return sign + num + english
        }
        if s.range(of: #"^[\d.]+(ms|s)$"#, options: .regularExpression) != nil {   // 300ms, 16s, 0.2s
            let unit = s.hasSuffix("ms") ? "ms" : "s"
            return sign + s.dropLast(unit.count) + " " + unit
        }
        if s.allSatisfy({ $0.isNumber || $0 == "." }) { return sign + s }
        return nil
    }

    // Option names: FSW keyword → English.
    private static let optionTSV = """
FEHLERZAEHLER\tStored-fault counter
FEHLER_1_CODE\tStored fault 1: code
FEHLER_1_ART\tStored fault 1: type
FEHLER_1_HAEUFIGKEIT\tStored fault 1: occurrences
FEHLER_2_CODE\tStored fault 2: code
FEHLER_2_ART\tStored fault 2: type
FEHLER_2_HAEUFIGKEIT\tStored fault 2: occurrences
FEHLER_3_CODE\tStored fault 3: code
FEHLER_3_ART\tStored fault 3: type
FEHLER_3_HAEUFIGKEIT\tStored fault 3: occurrences
FEHLER_4_CODE\tStored fault 4: code
FEHLER_4_ART\tStored fault 4: type
FEHLER_4_HAEUFIGKEIT\tStored fault 4: occurrences
FEHLER_5_CODE\tStored fault 5: code
FEHLER_5_ART\tStored fault 5: type
FEHLER_5_HAEUFIGKEIT\tStored fault 5: occurrences
SIA_LITER_ZAEHLER_0\tService: fuel-used counter (copy 1)
SIA_LITER_ZAEHLER_1\tService: fuel-used counter (copy 2)
SIA_LITER_ZAEHLER_2\tService: fuel-used counter (copy 3)
ZEITINSPEKTIONS_ZAEHLER_0\tService: time-inspection counter (copy 1)
ZEITINSPEKTIONS_ZAEHLER_1\tService: time-inspection counter (copy 2)
ZEITINSPEKTIONS_ZAEHLER_2\tService: time-inspection counter (copy 3)
SIA_INSPECTION_COUNTER\tService: inspection count
SIA_TIME_SERVICE_COUNTER\tService: time-service count
LETZTER_SERVICE\tLast service type
SIA_KM_ZAEHLER_SERVICE\tService: distance counter
LL/RL\tLeft/right-hand drive
MOTOR_ART\tEngine fuel type
ANZEIGE_EML\tEML (throttle) warning light
GETRIEBEART\tTransmission type
GENERATOR_UEBER_CAN\tCharging warning via CAN
KLEMME_50_UEBER_CAN\tStarter signal (terminal 50) via CAN
ANZEIGE_HOCHLADEN\tDisplay start-up animation
WEG_EINHEIT\tDistance unit
ZEIT_EINHEIT\tClock format
TEMPERATUR_EINHEIT\tTemperature unit
WEG_DURCHSCHNITT\tAverage-speed unit
VERBRAUCH_D1\tFuel-consumption unit
WEG_REICHWEITE\tRange unit
WEG_LIMIT\tSpeed-limit unit
SPRACHE\tDisplay language
SIA_ANZEIGEPARAMETER\tService display mode
LICHTWARNUNG\tLights-on warning
SMG_ALT_NEU\tSMG generation
TOG_UEBER_CAN\tOil-level sensor via CAN
AKUST_WARNUNG_OELVERL\tOil-loss warning chime
AKUST_WARNUNG_OELVERBR\tOil-consumption warning chime
WARN_MEDIUM_TOG\tOil-level warning sounder
ZUENDSCHLUESSEL_WARNUNG\tKey-in-ignition warning
WARN_MEDIUM_ZUENDSCHL\tKey warning sounder
RDKS\tTire-pressure monitoring (RDKS)
CAN_RDC\tTire-pressure control via CAN
AKUSTIK_RDKS\tTire-pressure warning chime
WARN_MEDIUM_RDKS\tTire-pressure warning sounder
DBC_PREDRIVE\tBrake check at start-up
ANZEIGE_OELSTAND_PREDRIVE\tOil-level check at start-up
AKUSTIK_ASC\tASC/DSC warning chime
WARN_MEDIUM_ASC\tASC/DSC warning sounder
RUECKWAERTSGANG_WARNUNG\tReverse-gear warning
RUECKWAERTSGANG_WARN_MED\tReverse-gear warning sounder
AKUSTIK_PARKBREMSE\tHandbrake warning chime
WARN_MEDIUM_PARKBREMSE\tHandbrake warning sounder
BC\tOn-board computer
LENKSTOCKSCHALTER_KLR\tStalk button works at terminal R
QUITT_A_TEMP_WARNUNG_LSS\tAcknowledge ice warning with stalk button
OELNIVEAU_M3\tM3 oil-level display
CAN_BREMSFLUESSIGKEIT\tBrake-fluid warning via CAN
AUSSENTEMP_SENSOR\tOutside-temperature sensor
AUSSENTEMP_WARN_AKUSTIK\tIce-warning chime
WARN_MEDIUM_AUSSENTEMP\tIce-warning sounder
CC_AUSSENTEMPERATUR\tIce warning in check control
GURTKONTAKT_MELDUNG_UEBER\tSeat-belt buckle signal via
GURTWARNUNG\tSeat-belt warning
AKUSTIK_GURT_WARN\tSeat-belt warning chime
WARN_MEDIUM_GURT\tSeat-belt warning sounder
ANZEIGE_SITZLEHNE_VER\tSeatback-unlatched warning
BC_V_KORREKTUR\tOn-board computer speed correction
WARN_MEDIUM_LIMIT\tSpeed-limit warning sounder
NAVI_DIST_TO_JUNCTION\tNavigation distance-to-turn display
HBA\tBrake-assist (HBA) warning
ANZEIGE_CFC\tFuel-consumption display
TANK_ZERO_EVAP\tZero-evaporation fuel tank
FZG_VERZOEGERUNG\tVehicle deceleration signal
SULEV_GATEWAY\tSULEV gateway
SMG_S_ANZEIGE\tSMG "S" mode display
CAN_OELDRUCKSCHALTER\tOil-pressure switch via CAN
OFFSET_GESAMTWEGSTRECKE\tOdometer offset
K_ZAHL_WEG\tK-number (distance)
K_ZAHL_WEG_KOMPL\tK-number (distance), check copy
K_ZAHL_TACHO\tK-number (speedometer)
K_ZAHL_TACHO_KOMPL\tK-number (speedometer), check copy
PRUEFSTEMPEL\tTest stamp
VERZ_RWGANG_WRN\tReverse-gear warning delay
KM_SERVICE_INTERVALL\tService interval (distance)
SIA_GRENZE_ZEIT\tService time limit
SIA_LITER_GRENZE\tService fuel-used limit
TAGEGRENZE_SIA_RESET\tService reset: days limit
LITERGRENZ_SIA_RESET\tService reset: fuel limit
KUEHLMITTELNIV_FILTERZEIT\tCoolant-level filter time
ZEIT_SITZLEHNENANZEIGE\tSeatback warning duration
WARNUNG_GESCHW_LIMIT\tSpeed-limit warning
DELTA_LIMIT_GESETZ\tSpeed-limit tolerance
GRENZWERT_GRUND_SCHWELLE\tLimit: base threshold
GRENZWERT_VERZ_SCHWELLE_1\tLimit: delay threshold 1
GRENZWERT_VERZ_SCHWELLE_2\tLimit: delay threshold 2
AUSSENTEMP_CODIER_FAKTOR\tOutside-temperature calibration factor
AUSSENTEMP_CODIER_OFFSET\tOutside-temperature calibration offset
AUSSENTEMP_DELTA_K1\tOutside-temperature correction K1
AUSSENTEMP_DELTA_K2\tOutside-temperature correction K2
AUSSENTEMP_ZEITKONST_Z1\tOutside-temperature time constant 1
AUSSENTEMP_ZEITKONST_Z2\tOutside-temperature time constant 2
AUSSENTEMP_ZEITKONST_Z3\tOutside-temperature time constant 3
AUSSENTEMP_ZEITKONST_Z4\tOutside-temperature time constant 4
AUSSENTEMP_ZEITKONST_Z5\tOutside-temperature time constant 5
AUSSENTEMP_ZEITKONST_Z6\tOutside-temperature time constant 6
AUSSENTEMP_ABKUEHLZEIT\tOutside-temperature cool-down time
AUSSENTEMP_V_FILTERZEIT\tOutside-temperature speed filter
AKUSTIK_WARNUNG_T1\tWarning chime timing 1
AKUSTIK_WARNUNG_T2\tWarning chime timing 2
AKUSTIK_WARNUNG_T3\tWarning chime timing 3
AKUSTIK_WARNUNG_T1_SMG\tSMG warning chime timing 1
AKUSTIK_WARNUNG_T2_SMG\tSMG warning chime timing 2
TANK_VORHALT_REICHW\tRange reserve allowance
TANK_SCHWELLE_RESERVE\tFuel reserve warning threshold
TANK_FILTER_FALLEND\tFuel gauge filter (falling)
TANK_FILTER_STEIGEND\tFuel gauge filter (rising)
TANK_FILTER_NACHTANKERK\tRefuelling detection
TANK_BERUHIGUNGSZEIT\tFuel gauge settling time
TANK_MITTLUNGSZEIT\tFuel gauge averaging time
TANK_SCHWELLE_AUF/AB\tFuel gauge up/down threshold
TANK_SICHERHEITSFAKTOR\tRange safety factor
TANK_KENNLINIE\tFuel tank sender curve
CODIERUNG_ERFOLGT\tCoding done (marker)
CODIERUNG_ERFOLGT_1\tCoding done (marker 2)
CODIERUNG_ERFOLGT_2\tCoding done (marker 3)
DIAGNOSE_DELAY_ZEIT\tDiagnostic delay time
SCHRITTMOTOR\tStepper-motor gauges
GLATTEIS\tIce warning
KVA_OELTEMP\tOil temperature from engine
MOTOR_ART_DSC_2\tEngine variant
BAUART_MK60\tBody / model variant
DRUCKMODELL_HINTERACHSE\tBrake pressure model, rear axle
DRUCKMODELL_VORDERACHSE\tBrake pressure model, front axle
GETRIEBE\tTransmission
LOGIK_HA_SPERRE\tRear-differential lock logic
PRE_MSR\tEngine-drag control (MSR) pre-fill
DBC_DBS\tDynamic brake control (DBC/DBS)
DBC_MSB\tDynamic brake control (MSB)
PRE_VLABS\tABS pre-fill
SPERRDIFFERENZREGELUNG\tLocking-differential control
TRAKTIONDIFFERENZREGELUNG\tTraction-differential control
UNTERSTEUERUNGSALGORYTHM\tUndersteer algorithm
UEBERSTEUERN_MUE_0_2\tOversteer threshold, low grip
UEBERSTEUERN_MUE_1_2\tOversteer threshold, high grip
UNTERSTEUERN_MUE_0_2\tUndersteer threshold, low grip
UNTERSTEUERN_MUE_1_2\tUndersteer threshold, high grip
UNTERSTEUERSCHWELLE_2\tUndersteer threshold
GEARMOMENTREGLER_MAX_HA_2\tYaw-moment control maximum (rear)
GEARMOMENTREGLER_MIN_HA_2\tYaw-moment control minimum (rear)
DELTA_PSI_BETA_LIMITKORR2\tYaw / slip-angle limit correction
DROSSEL\tThrottle intervention
REIFENDRUCKWARNSYSTEM\tTire-pressure warning (RPA)
DTC_LAMPE\tDTC indicator light
VOLUMENDURCHFLUSSPARA_2\tHydraulic flow parameter
DBC_MIN_AUSLOESEDRUCK\tBrake-assist minimum trigger pressure
LENKWINKELKENNLINIE_2\tSteering-angle curve
OHNE_INTERVALLBETRIEB\tNo intermittent wipe
WISCHERPOTI\tWiper interval dial
STANDRUECKSCHALTUNG\tWiper slows down when stopped
WISCHERINTERVALL\tWiper interval
INTERVALLZEIT_GESCHWABH\tSpeed-dependent wiper interval
KENNLINIENFELD2_AKTIV\tAlternate wiper map
BLOCKIERSCHUTZ_AKT_XXS\tWiper stall protection after
MIT_WISCHER_SERVICEPOS\tWiper service position
WISCHER_VOLLEND_KLR_AUS\tFinish wipe when switched off
SENSOR_REGEN\tRain sensor
SENSOR_REGEN_N_STUFE2\tRain sensor at wiper speed 2
WISCHEN_ERST_XXS_WASCH\tWipe starts after washing for
OHNE_WISCH_BEI_WASCH\tNo wipe while washing
ANZAHL_NACHWISCHZYKLEN\tWipes after washing
ANZAHL_WASCHBET_ZUR_SRA\tWashes before headlight wash
MIT_SRA_EIN_LENKSTOCK\tHeadlight wash from stalk
SRA_MIT_WASCH_WISCH_SW\tHeadlight wash with wash/wipe switch
ANZAHL_SPRITZIMPULSE\tHeadlight-wash spray pulses
DAUER_SPRITZIMPULSE\tSpray pulse length
PAUSE_ZW_SPRITZIMPULSE\tPause between spray pulses
SCHEINWERFERREINIGUNG\tHeadlight washers
FH_ABSCHALTKRITERIUM\tWindow auto-stop rule
FH_NACH_TUERE_AUF\tWindows work after a door opens
MAUT_N_ABBRECH_N_TUER_AUF\tToll-window mode kept after door opens
OHNE_SCHEIBENABSENKUNG\tNo window drop on door open
MAUT_NUR_BEI_KL15EIN\tToll-window mode only with ignition on
HUB_VERZOEGERUNG_FH_VORN\tFront window drop delay
FENSTERHEBER_VORNE\tFront power windows
FENSTERHEBER_HINTEN\tRear power windows
EINKLEMMSCH_VORNE\tAnti-trap, front windows
EINKLEMMSCH_HINTEN\tAnti-trap, rear windows
EKS_REVERSIERZEIT_ZUS\tAnti-trap extra reverse time
EINKLEMMSCH_REVERSIEREN\tAnti-trap reverse distance
FH_TIMEOUT\tWindow motor timeout
KISI_N_DEAKT_IM_CRASH\tChild lock kept after a crash
ANLAUFSTROMBEGRENZ_MEMO\tStart-current limit (memory)
AUSSTELLFENSTER\tRear pop-out windows
AUSSTELLFENSTER_ZEIT\tPop-out window run time
TAB_WIEDERHOLSPERRE_ASF_2\tPop-out window repeat lock
TAB_ANSTEURN_ASF_2\tPop-out window control table
KOMFORTOEFFNEN_FB_O_FH_HI\tRemote comfort-open: skip rear windows
KOMFORTOEFFNEN_FB_O_SHD\tRemote comfort-open: skip sunroof
KOMFORTSCHLIE_FB_O_FH_HI\tRemote comfort-close: skip rear windows
KOMFORTSCHLIE_FB_OHNE_SHD\tRemote comfort-close: skip sunroof
DIFFERENZ_ANLAUF_BLOCK\tWindow start/stall current difference
KOMFOEFFNEN_SPERRE_KEY_IN\tNo comfort-open with key in ignition
FH_INIT_TRANSPORTMODE\tWindow initialisation in transport mode
SCHEIBENABSENK_OHNE_EKS\tWindow drop without anti-trap
FH_FAHRERTUER_TIPP_AUF\tOne-touch down, driver window
FH_FAHRERTUER_TIPP_ZU\tOne-touch up, driver window
FH_BEIFAHRERTUER_TIPP_AUF\tOne-touch down, passenger window
FH_BEIFAHRERTUER_TIPP_ZU\tOne-touch up, passenger window
FH_TUEREN_HINTEN_TIPP_AUF\tOne-touch down, rear windows
FH_TUEREN_HINTEN_TIPP_ZU\tOne-touch up, rear windows
FH_ZTR_SCHALTER_TIPP_AUF\tOne-touch down, center-console switch
FH_ZTR_SCHALTER_TIPP_ZU\tOne-touch up, center-console switch
SCHEIBE_ABSENKZEIT\tWindow drop time
ZEIT_TUER/SCHLIESSZEIT\tDoor / lock timing
FUNKTIONTUERSCHLOSS\tDoor-lock unlock mode
EINSTIEG_FH_ZU_VER_SPERRE\tClose windows when locking
FUNKTIONEN_TOURING\tTouring (wagon) functions
VERRIEGELN_AUT_NACH_2_MIN\tRe-lock after 2 min if no door opened
HECKSCHEIBE_ENTRI_INNEN\tRear-window release from inside
ENTSICHERN_CENTERLOCK\tUnlock with center-lock button
CENT_LOCK_MGL_VO_TUER_AUF\tCenter lock works with front door open
VERRIEGELUNGSSCHWELLE\tAuto-lock speed
HECKSCHEIBEN_LOGIK\tRear-window logic
HECKKLAPPEN_LOGIK\tTrunk-lid logic
VERRIEGELN_AUT_AB_X_KM/H\tAuto-lock when driving
N_VER_B_ERN_GESCHW_SCHWEL\tNo re-lock at speed threshold
BEDIENSTELLE_BFT\tPassenger-door lock control
ANSTEUERZEIT_ZV_AGGREGATE\tCentral-locking motor run time
ENTR_HKL_MGL_WENN_VER\tTrunk release while locked
ENTR_HS_MGL_WENN_VER\tRear-window release while locked
SCHLIESSYSTEM\tLock system type
ENTRIEGELN_HKL\tTrunk release
POLLING_ZEIT_L_SCHLOSS\tLock polling time
BETAET_DAUER_WIPPTASTE\tRocker-switch press time
NOTENTRIEGELN_HKL\tTrunk emergency release
ANSTEUERZEIT_MOTOR_HKL\tTrunk motor run time
DELAY_MOTOR_ZV_ER\tCentral-locking motor delay
ANSTEUERZEIT_MOTOR_HS\tRear-window motor run time
SOFT_ON/OFF\tInterior light fade in/out
IB_EIN_SCHLOSS_ENTRIEGELN\tInterior light on when unlocking
IB_BEI_KL.R_AUS\tInterior light when ignition turned off
IB_EIN_BEI_HKK/HSK\tInterior light on with trunk / rear window open
IB_EIN_16MIN_WENN_STANDLI\tInterior light 16 min with parking lights
IB_AUS_NACH_X_SEKUNDEN\tInterior light off after
IB_EIN_N_KL_58G_MAX_1MIN\tInterior light after lights off (max 1 min)
VA1/VA2_AUS_NACH_X_MIN\tAccessory power off after
ABSCHALTUNG_VERBRAUCHER\tBattery-saver consumer cut-off
TAKTUNG_IB\tInterior light pulsing
TAKTUNG_VA1\tAccessory power pulsing
IB_SPERRE_BEI_FEHLER\tInterior light off on fault
VA1_SPERRE_BEI_FEHLER\tAccessory power 1 off on fault
VA2_SPERRE_BEI_FEHLER\tAccessory power 2 off on fault
DWA\tAlarm system
NEIGUNGSGEBER\tAlarm tilt sensor
FUNK_INNENRAUMSCHUTZ\tAlarm interior motion sensor
FUNKINNENRAUMSCHUTZ_HI\tAlarm interior motion sensor (rear)
DWA_HANDSCHUHFACHKONTAKT\tAlarm: glovebox contact
DWA_HECKKLAPPENKONTAKT\tAlarm: trunk contact
DWA_HECKSCHEIBENKONTAKT\tAlarm: rear-window contact
EINGANG_2\tAlarm input 2
EINGANG_2_KONTAKT_GESCHL\tAlarm input 2 normally closed
MIT_OPT_ALARM\tVisual alarm
SCHAERFEN/ENTSCHAERFEN\tAlarm armed / disarmed by
ALARM_AKUSTISCH\tAlarm sound
ALARM_AKUSTISCH_LANG\tLong alarm sound
ALARM_OPT_WARNBLINKER\tAlarm flashes hazard lights
ALARM_OPT_ABBLENDLICHT\tAlarm flashes low beams
ALARM_OPT_FERNLICHT\tAlarm flashes high beams
VERL_ALARMZEI_WAEHR_ALARM\tExtend alarm on repeat trigger
HEULTON\tSiren (wailing) tone
QUITIMP_SICHERN/ENTSICHER\tLock / unlock confirmation pulse
QUIT_OPT_SCHAERF\tArm confirmation: lights flash
QUIT_OPT_SCHAERF_KLAPPE\tArm confirmation with a lid open: lights flash
QUIT_AKUST_SCHAERF\tArm confirmation: chirp
QUIT_AKUST_SCHAERF_KLAPPE\tArm confirmation with a lid open: chirp
QUIT_OPT_ENTSCH\tDisarm confirmation: lights flash
QUIT_AKUST_ENTSCH\tDisarm confirmation: chirp
OFFENE_FENSTER\tOpen-window warning when locking
OHNE_FERNBEDIENUNG_0\tWithout remote key (variant 0)
OHNE_FERNBEDIENUNG_1\tWithout remote key (variant 1)
OHNE_FERNBEDIENUNG_2\tWithout remote key (variant 2)
OHNE_FERNBEDIENUNG_3\tWithout remote key (variant 3)
KOMFORTOEFFNUNG_FB\tComfort open by remote (hold unlock)
KOMFORTSCHLIESSUNG_FB\tComfort close by remote (hold lock)
PANIK_MODUS\tPanic mode
INNENLICHT_AN_MEHRFACH_ZV\tInterior light on repeated unlock
HKL_SPERREN_BEI_ZS\tLock trunk with valet key
IR_FERNBEDIENUNG\tInfrared remote
VERZUG_PANIK_MODUS_0.2_S\tPanic mode delay (×0.2 s)
VERZUG_ENTR_HECKKLAPPE\tTrunk release delay
FERNBEDIENUNG_1\tRemote key 1 unlock mode
FERNBEDIENUNG_2\tRemote key 2 unlock mode
FERNBEDIENUNG_3\tRemote key 3 unlock mode
FERNBEDIENUNG_4\tRemote key 4 unlock mode
VERRIEGELN_XKM/H_SENDER_1\tAuto-lock when driving, key 1
VERRIEGELN_XKM/H_SENDER_2\tAuto-lock when driving, key 2
VERRIEGELN_XKM/H_SENDER_3\tAuto-lock when driving, key 3
VERRIEGELN_XKM/H_SENDER_4\tAuto-lock when driving, key 4
HECKSCHEIBE_ENTR_SENDER_1\tRear-window release, key 1
HECKSCHEIBE_ENTR_SENDER_2\tRear-window release, key 2
HECKSCHEIBE_ENTR_SENDER_3\tRear-window release, key 3
HECKSCHEIBE_ENTR_SENDER_4\tRear-window release, key 4
FUNKTION_CABRIO\tConvertible functions
FH_ABSENKEN_VERDECK_OEFF\tLower windows when opening the top
E52_FUNKTIONEN\tZ8 functions
E85_FUNKTIONEN\tZ4 functions
E83_FUNKTIONEN\tX3 functions
TUER_HINTEN\tRear doors
RECHTSLENKER\tRight-hand drive
OHNE_FERTIGUNGSMODE\tFactory mode off
OHNE_TRANSPORTMODE\tTransport mode off
OHNE_SERVICEMODE\tService mode off
OHNE_POWERDOWNMODE\tPower-down mode off
BETRMODI_DEAKT_KL15_EIN\tClear special modes at ignition on
OHNE_IB_0\tWithout interior light (variant 0)
OHNE_IB_1\tWithout interior light (variant 1)
OHNE_IB_2\tWithout interior light (variant 2)
OHNE_CENTERLOCK_0\tWithout center-lock button (variant 0)
OHNE_CENTERLOCK_1\tWithout center-lock button (variant 1)
OHNE_CENTERLOCK_2\tWithout center-lock button (variant 2)
OHNE_VA_ZEITEN_0\tWithout accessory-power timers (variant 0)
OHNE_VA_ZEITEN_1\tWithout accessory-power timers (variant 1)
OHNE_VA_ZEITEN_2\tWithout accessory-power timers (variant 2)
OHNE_FH_FA_VORNE\tWithout driver front window
OHNE_FH_FA_HINTEN_0\tWithout driver-side rear window (variant 0)
OHNE_FH_FA_HINTEN_1\tWithout driver-side rear window (variant 1)
OHNE_FH_BF_VORNE_0\tWithout passenger front window (variant 0)
OHNE_FH_BF_VORNE_1\tWithout passenger front window (variant 1)
OHNE_FH_BF_HINTEN_0\tWithout passenger-side rear window (variant 0)
OHNE_FH_BF_HINTEN_1\tWithout passenger-side rear window (variant 1)
OHNE_SRA_0\tWithout headlight washers (variant 0)
OHNE_SRA_1\tWithout headlight washers (variant 1)
OHNE_DWA_0\tWithout alarm (variant 0)
OHNE_DWA_1\tWithout alarm (variant 1)
OHNE_FRONTSCH_REINIGUNG\tWithout windshield washers
OHNE_SCHEIBENWISCHER\tWithout wipers
OHNE_ZV\tWithout central locking
OHNE_ER_HECKKLAPPE\tWithout electric trunk release
WISCHER_RUECK_GESCHW\tWiper return speed
EKS_OFFEN/UNTERBRECHUNG\tAnti-trap strip: open-circuit level
EKS_GEDRUECKT/OFFEN\tAnti-trap strip: pressed level
SCHWELLE_OBEN\tUpper threshold
SCHWELLE_UNTEN\tLower threshold
VERDECK_VORNE_E85\tZ4 top front latch
MIT_LIN\tLIN bus fitted
MIT_LIN_SCHALTER\tLIN switches fitted
MEMORY_SP_ABKLAPPEN_GM\tMirror tilt-down memory
BEIKLAPP_B_KOMFORTSCHL_GM\tFold mirrors on comfort close
SPIEGELMEMORY_GM\tMirror memory
SITZMEMORY_VERBAUT_GM\tSeat memory fitted
SPIEGELABKLAPPEN_GM\tMirror tilt-down in reverse
SPIEGELHEIZUNG_VERBAUT_GM\tHeated mirrors fitted
ABKLAPPWERT_GM\tMirror tilt-down amount
MEMORY_POS_SPEICHERN\tMemory position store
MEMORY_POS_ANFAHREN\tMemory position recall
V_VAR_SPERRE_BEIKLAPP_GM\tMirror fold speed limit
MEMORYANFAHRGENAUIGKEIT\tMemory recall accuracy
BEIKLAPPEN_GM\tMirror folding
PARK/NEUTRAL_EINGANG\tPark/neutral input
EWS_3_SCHNITTSTELLE\tEWS 3 interface
K_BUS_FREI_OHNE\tStart enable without K-bus
ABSCHALTDREHZAHL_ANLASSER\tStarter cut-off engine speed
ZEITDAUER_BIS_ABSCHALTUNG\tTime until starter cut-off
ZEIT_BIS_AUTOM_SPERREN\tTime until immobilizer re-arms
SCHALT_KRITERIUM_EWS_3\tEWS 3 switching rule
"""

    // Value names: PSW keyword → English. Numbers with units go through `valueWithUnit`.
    private static let valueTSV = """
aktiv\tactive
nicht_aktiv\tnot active
aktiv_mit_kl.58\tactive with parking lights
automatik\tautomatic
benziner\tpetrol
diesel\tdiesel
cabrio_m\tM3 convertible
coupe_m\tM3 coupe
csl\tM3 CSL
codierung_erfolgt\tcoded
nicht_codiert\tnot coded
d_schloss\tdriver-door lock cylinder
l_schloss\tlock cylinder (L)
dad_tank_diesel\tdiesel tank
metalltank\tmetal tank
60_l_literskala\t60 l gauge scale
dauerton\tcontinuous tone
intervallton\tintermittent tone
gong\tchime
piezo\tpiezo buzzer
deutsch\tGerman
englisch\tEnglish (UK)
franzoesisch\tFrench
italienisch\tItalian
spanisch\tSpanish
japan\tJapan
kanada\tCanada
golf\tGulf states
us\tUS
ece\tECE (Europe)
einstiegshilfe\tentry aid
ganz_auf\tfully open
offen\topen
geschlossen\tclosed
grad_c\t°C
grad_f\t°F
12_stunden\t12-hour
24_stunden\t24-hour
grundcode_var\tbase code variant
handschaltung\tmanual
sequentiell_ag\tsequential (SMG)
sequentiell_msport\tsequential (M Sport)
high\thigh
standard\tstandard
konventionell\tconventional
k_bus\tK-bus
klemme_r\tignition position 1 (terminal R)
km\tkilometres
mls\tmiles
km/h\tkm/h
mph\tmph
km/l\tkm/l
l/100km\tl/100 km
mpg_uk\tmpg (UK)
mpg_us\tmpg (US)
kurz\tshort
lang\tlong
linkslenker\tleft-hand drive
rechtslenker\tright-hand drive
mit_gurtschlosskontakt\twith seat-belt buckle switch
ohne_gurtschlosskontakt\twithout seat-belt buckle switch
mit_zeitinspektion\twith time-based inspection
mit_zeitinspektion_japan\twith time-based inspection (Japan)
ohne_zeitinspektion\twithout time-based inspection
nur_fernbedienung\tremote only
nur_mit_fernbedienung\tonly with remote
schloss_und_fernbedienung\tkey lock and remote
zv_selektiv\tselective (driver door first)
1x_tastendruck\tone press
2x_tastendruck\ttwo presses
zeit\ttime
s54b32\tS54 3.2 l
s54b32_aut\tS54 3.2 l, SMG
s54b32_sa8st\tS54 3.2 l (option 8ST)
s54b32_sa988\tS54 3.2 l (option 988)
s54b32_aut_sa8st\tS54 3.2 l, SMG (option 8ST)
s54b32_aut_sa988\tS54 3.2 l, SMG (option 988)
"""
}
