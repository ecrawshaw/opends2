import Foundation

/// English names and one-line explanations for EDIABAS result names (STAT_*, ID_*, F_*, AIF_*…),
/// so the All values, Info and fault-detail views say what a value is. Written from the result
/// names and their German SGBD comments (`_RESULTS`) for the E46 modules: mss54ds0, dsc_mk60,
/// zke5, lsz, kombi46r, ihka46_2, lws5_1b, mrs3, ews3, shd46, sm46_3, mfl2. Unknown names fall
/// back to a tidied-up version of the raw name.
enum ValueNames {
    struct Entry { let label: String; let help: String }

    /// Look up a result name; also accepts the short form the All values table uses
    /// (STAT_ and _WERT stripped).
    static func lookup(_ key: String) -> Entry? {
        for k in [key, "STAT_\(key)_WERT", "STAT_\(key)", "\(key)_WERT"] {
            if let hit = table[k] { return hit }
        }
        return generic(key)
    }

    /// English label, or the raw name tidied up
    static func label(_ key: String) -> String {
        lookup(key)?.label ?? humanize(key)
    }

    static func humanize(_ key: String) -> String {
        var k = key
        for p in ["STAT_", "STATUS_", "F_", "ID_"] where k.hasPrefix(p) { k = String(k.dropFirst(p.count)); break }
        if k.hasSuffix("_WERT") { k = String(k.dropLast(5)) }
        return k.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Numbered fault-detail results that repeat per fault type / per stored condition
    private static func generic(_ key: String) -> Entry? {
        func match(_ pattern: String) -> String? {
            guard let r = key.range(of: pattern, options: .regularExpression) else { return nil }
            return String(key[r]).filter(\.isNumber)
        }
        if let n = match(#"^F_ART\d+_NR$"#) { return Entry(label: "Fault type \(n) (code)", help: "Code of the \(n). fault-type flag.") }
        if let n = match(#"^F_ART\d+_TEXT$"#) { return Entry(label: "Fault type \(n)", help: "What kind of fault this is (e.g. short to ground, open circuit), or -- if this flag isn't set.") }
        if let n = match(#"^F_UW\d+_NR$"#) { return Entry(label: "Condition \(n) (code)", help: "Which freeze-frame value this is.") }
        if let n = match(#"^F_UW\d+_TEXT$"#) { return Entry(label: "Condition \(n)", help: "Name of a value recorded when the fault was stored.") }
        if let n = match(#"^F_UW\d+_WERT$"#) { return Entry(label: "Condition \(n) value", help: "Value recorded when the fault was stored.") }
        if let n = match(#"^F_UW\d+_EINH$"#) { return Entry(label: "Condition \(n) unit", help: "Unit of the recorded value.") }
        if let n = match(#"^F_SD_?\d+"#) { return Entry(label: "Stored data \(n)", help: "Extra data the module stored with the fault.") }
        return nil
    }

    private static let table: [String: Entry] = {
        var t: [String: Entry] = [:]
        for line in raw.split(separator: "\n") {
            let p = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard p.count >= 2 else { continue }
            t[String(p[0])] = Entry(label: String(p[1]), help: p.count > 2 ? String(p[2]) : "")
        }
        return t
    }()

    // KEY<tab>English label<tab>explanation
    private static let raw = #"""
ID_BMW_NR	BMW part number	The module's BMW part number.
ID_HW_NR	Hardware number	Hardware version of the module.
ID_COD_INDEX	Coding index	Which coding data version the module expects.
ID_DIAG_INDEX	Diagnosis index	Selects the diagnostic file variant for this module.
ID_BUS_INDEX	Bus index	Bus/protocol version of the module.
ID_DATUM_KW	Build week	Calendar week the module was made.
ID_DATUM_JAHR	Build year	Year the module was made.
ID_LIEF_NR	Supplier number	Code of the company that made the module.
ID_LIEF_TEXT	Supplier	Company that made the module (Bosch, Siemens, VDO…).
ID_SW_NR	Software number	Software version in the module.
ID_CAN_INDEX	CAN index	CAN-bus message set version.
ID_AENDERUNGSINDEX	Change index	Hardware/software revision.
F_ANZ	Number of faults	Total faults stored in the module.
F_ORT_NR	Fault code	The module's own fault number.
F_ORT_TEXT	Fault	What the fault is about.
F_HFK	Occurrences	How many times the fault has been logged (counter usually tops out at 31).
F_ART_ANZ	Number of fault types	How many fault-type flags follow.
F_UW_ANZ	Number of conditions	How many freeze-frame values were stored with the fault.
F_HEX_CODE	Raw fault data	The fault record as raw bytes.
F_ZAHL	Serious faults	Faults in blocks 1–3 (the serious ones).
STAT_SCHALTER_SLV_VOR_EIN	Seat fore/aft switch: forward	1 = switch pressed.
STAT_SCHALTER_SLV_ZURUECK_EIN	Seat fore/aft switch: back	1 = switch pressed.
STAT_SCHALTER_SHV_AUF_EIN	Seat height switch: up	1 = switch pressed.
STAT_SCHALTER_SHV_AB_EIN	Seat height switch: down	1 = switch pressed.
STAT_SCHALTER_LEHNE_VOR_EIN	Backrest switch: forward	1 = switch pressed.
STAT_SCHALTER_LEHNE_ZURUECK_EIN	Backrest switch: back	1 = switch pressed.
STAT_TASTE_MEM_EIN	Memory (M) button	1 = pressed.
STAT_TASTE_POS1_EIN	Memory button 1	1 = pressed.
STAT_TASTE_POS2_EIN	Memory button 2	1 = pressed.
STAT_TASTE_POS3_EIN	Memory button 3	1 = pressed.
STAT_EASY_ENTRY_EIN	Easy-entry active	Seat slides forward for rear access (coupe).
STAT_RS_EIN	Reverse/park position input	1 = active.
STAT_EE_SCHALTER_POS	Easy-entry switch	0 = off, 1 = forward, 2 = back.
STAT_LED_EIN	Memory button LED	1 = on.
STAT_POS_SLV_WERT	Seat fore/aft position	Position sensor count.
STAT_POS_SHV_WERT	Seat height position	Position sensor count.
STAT_POS_LNV_WERT	Backrest position	Position sensor count.
STAT_SCHALTER_SITZLAENGE	Seat fore/aft switch	0 = off, 1 = forward, 2 = back.
STAT_SCHALTER_SITZHOEHE	Seat height switch	0 = off, 1 = up, 2 = down.
STAT_SCHALTER_SITZLEHNE	Backrest switch	0 = off, 1 = forward, 2 = back.
STAT_MEMORYSCHALTER	Memory buttons (bits)	Bit 0 = M, bit 1 = button 1, bit 2 = button 2, bit 3 = button 3.
STAT_SPANNUNG_HALLS_LNV_WERT	Backrest motor Hall sensor voltage	Position-sensor supply/signal voltage.
STAT_SPANNUNG_HALLS_SHV_WERT	Seat height motor Hall sensor voltage	Position-sensor supply/signal voltage.
STAT_SPANNUNG_HALLS_SLV_WERT	Seat fore/aft motor Hall sensor voltage	Position-sensor supply/signal voltage.
STAT_SPANNUNG_KL30_WERT	Battery voltage at module	Terminal 30 (permanent battery feed).
TELEGRAMM	Raw response	Raw bytes the module sent back.
STAT_ANLASSER_FREIGESCHALTET	Starter enabled	1 = immobilizer allows cranking.
STAT_ANLASSER_AUS_DREHZAHL	Starter blocked: engine running	1 = starter cut because engine speed detected.
STAT_ANLASSER_AUS_P_N	Starter blocked: not in P/N	1 = automatic not in Park/Neutral.
STAT_ANLASSER_AUS_ZV	Starter blocked: car locked	1 = central locking secured.
STAT_ANLASSER_AUS_BC	Starter blocked: code	1 = blocked by on-board computer code.
STAT_WEITERE_SELBSTINIT_KEYS	More keys to initialise	1 = not all keys released for self-initialisation have been learned yet.
STAT_DME_LEITUNG_FREI	Engine computer released	1 = immobilizer has sent the release to the DME.
STAT_EWS_JUNGFRAEULICH	Immobilizer is new (virgin)	1 = never matched to an engine computer.
STAT_P_N_EINGANG	Park/Neutral input	1 = gearbox in P/N (automatic).
STAT_KL_R_EINGANG	Ignition position 1 (terminal R)	1 = key in accessory position or beyond.
STAT_KL_R_EINGANG_KBUS	Ignition position 1 via K-bus	1 = reported on the K-bus.
STAT_ZV_GESICHERT	Car locked (double-locked)	1 = central locking secured.
STAT_BC_CODE	On-board computer code active	1 = BC code lock set.
STAT_KBUS_FREI_OHNE_KEY	Release via K-bus without key	1 = can be released by K-bus message alone.
STAT_FREI_KBUS_UND_KEY	Release needs key + K-bus	1 = needs a valid key and K-bus message.
STAT_MOTORDREHZAHL_KBUS	Engine speed (from K-bus)	Raw engine speed value the immobilizer sees.
STAT_AKTUELLE_SCHLUESSELNUMMER	Key number in ignition	Which programmed key (0–9) is being used.
STAT_SCHLUESSEL_SENDET	Key transponder answering	1 = the key's chip is read and recognised.
STAT_SCHLUESSEL_GESPERRT	Key disabled	1 = this key has been blocked.
STAT_SCHLUESSEL_NIO_ID	Key ID wrong	1 = key ID not accepted.
STAT_SCHLUESSEL_NIO_PW	Key password wrong	1 = key password not accepted.
STAT_SCHLUESSEL_NIO_WC	Key rolling code wrong	1 = key change code not accepted.
STAT_KBUS_NOTWENDIG	Key needs K-bus release too	1 = this key also needs a K-bus release.
STAT_AKTUELLE_SCHLUESSEL_ID	Key ID	ID bytes read from the key.
STAT_AKTUELLE_SCHLUESSEL_ID_TEXT	Key ID (text)	ID bytes read from the key.
STAT_AKTUELLER_WC	Key rolling code	Current change code.
STAT_AKTUELLER_WC_TEXT	Key rolling code (text)	Current change code.
STAT_VORGABE_DME	DME release requested	1 = release to engine computer requested.
STAT_VORGABE_ANLASSERRELAIS	Starter relay requested	1 = starter relay requested.
STAT_VORGABE_DME_AUSFUEHREN	DME release being sent	1 = active.
STAT_VORGABE_ANLASSERRELAIS_AUSFUEHREN	Starter relay being driven	1 = active.
BETRIEBSSYSTEM	Operating system version	Module firmware component.
EEPROM_TREIBER	EEPROM driver version	Module firmware component.
K_BUS_HANDLER	K-bus handler version	Module firmware component.
STAT_EWS3_CAPABLE	Supports EWS3	1 = module can run EWS 3.
STAT_EWS4_CAPABLE	Supports EWS4	1 = module can run EWS 4.
STAT_EWS3_ACTIVE	EWS3 active	1 = EWS 3 mode active (or can be activated).
STAT_EWS4_ACTIVE	EWS4 active	1 = EWS 4 mode active (or can be activated).
STAT_EWS4_SERVER_SK_LOCKED	EWS4 secret key locked	1 = key can no longer be read/written.
STAT_EWS4_SERVER_SK	EWS4 secret key	Immobilizer secret key data.
STAT_AUC_VERSORGUNG_WERT	Air-quality sensor supply	Supply voltage of the AUC (automatic recirculation) sensor.
STAT_KLEMME30_WERT	Battery voltage (terminal 30)	Permanent battery feed at the module.
STAT_AUC_HEIZUNG_WERT	Air-quality sensor heater supply	Heater voltage of the AUC sensor.
STAT_GEBLAESE_PWM_WERT	Blower control voltage	PWM control signal to the blower.
STAT_TINNEN_WERT	Interior temperature	Cabin temperature sensor.
STAT_TVERDAMPFER_WERT	Evaporator temperature	A/C evaporator sensor.
STAT_AUC_WERT	Air-quality sensor signal	AUC sensor reading (pollution level).
STAT_WT_WERT	Heater core temperature	Heat exchanger sensor.
STAT_KLEMME30G_WERT	Switched battery feed (terminal 30g)	Battery feed that is cut after a while with the car off.
STAT_UMSCHALTVENTIL_WERT	Changeover valve	State of the coolant changeover valve.
STAT_KLEMME15_WERT	Ignition voltage (terminal 15)	Voltage with ignition on.
STAT_ABSPERRVENTIL_WERT	Shut-off valve	State of the coolant shut-off valve.
STAT_TINNEN_SPANNUNG_WERT	Interior temp sensor voltage	Raw sensor voltage.
STAT_DRUCKSENSOR_WERT	A/C pressure sensor	Refrigerant pressure.
STAT_SOLARSENSOR_WERT	Sun sensor	Sunlight load on the cabin.
STAT_SOLL_WERT	Temperature setpoint	Temperature selected on the panel.
STAT_TAUSSEN_WERT	Outside temperature	As used by the climate control.
STAT_SOLL_KORRIGIERT_WERT	Corrected setpoint	Setpoint after corrections (sun, outside temp).
STAT_FUEHR_WERT	Control target	Internal target value of the climate control loop.
STAT_GEBLAESE_WERT	Blower voltage	Voltage driving the blower.
STAT_TINNEN_VERZOEGERT_WERT	Interior temperature (smoothed)	Delayed/filtered cabin temperature.
STAT_Y_WERT	Control output	Climate controller output value.
STAT_WTSOLL_WERT	Heater core target temperature	Target heat exchanger temperature.
STAT_YWT_WERT	Heater core control output	Controller output for the heater core.
STAT_WASSERVENTIL_WERT	Water valve opening time	How long the heater valve is open per cycle.
STAT_GESCHWINDIGKEIT_WERT	Vehicle speed	km/h.
STAT_DREHZAHL_WERT	Engine speed	rpm.
STAT_GEBLAESESTUFE_WERT	Blower speed setting	Selected fan step.
STAT_BITLISTE_WERT	Control panel data (raw)	Button states as a number.
STAT_FUNKTION_DEFROST_EIN	Defrost	1 = on.
STAT_FUNKTION_EIN	Climate control on	1 = on.
STAT_FUNKTION_AC_EIN	A/C	1 = on.
STAT_FUNKTION_HHS_EIN	Rear window heater	1 = on.
STAT_FUNKTION_UMLUFT_EIN	Recirculation	1 = on.
STAT_FUNKTION_AUC_EIN	Automatic recirculation (AUC)	1 = on.
STAT_FUNKTION_AUTO_EIN	Auto mode	1 = on.
STAT_FUNKTION_FUSS_EIN	Footwell vents	1 = selected.
STAT_FUNKTION_MITTE_EIN	Face vents	1 = selected.
STAT_FUNKTION_OBEN_EIN	Windscreen vents	1 = selected.
STAT_GEBLAESE_PLUS_EIN	Blower + button	1 = pressed.
STAT_GEBLAESE_MINUS_EIN	Blower − button	1 = pressed.
STAT_SOLLWERT_PLUS_EIN	Temperature + button	1 = pressed.
STAT_SOLLWERT_MINUS_EIN	Temperature − button	1 = pressed.
TELEGRAMM2	Raw response 2	Raw button-state bytes.
STAT_WASSERVENTIL_EIN	Heater water valve	1 = energised.
STAT_ZUSATZWASSERPUMPE_EIN	Auxiliary water pump	1 = running.
STAT_ZUHEIZER_EIN	Auxiliary heater	1 = on.
STAT_RELAIS_HECKSCHEIBE_EIN	Rear window heater relay	1 = on.
STAT_KLIMABEREITSCHAFT_EIN	A/C ready	1 = compressor has run in and A/C is available.
STAT_BELUEFTUNG_WERT	Face vent flap motor	Flap position.
STAT_ENTFROSTUNG_WERT	Defrost flap motor	Flap position.
STAT_FUSSRAUM_WERT	Footwell flap motor	Flap position.
STAT_FRISCHLUFT_LI_WERT	Fresh/recirc flap motor left	Flap position.
STAT_FRISCHLUFT_RE_WERT	Fresh/recirc flap motor right	Flap position.
STAT_GWSZ_WERT	Odometer	Total distance.
ANTWORT	Raw response	Raw bytes the module sent back.
STAT_AIF_FG_NR	VIN	Vehicle identification number stored in the cluster.
STAT_MOTORTYP_NR	Engine type	0 = petrol, 1 = diesel.
STAT_MOTORTYP_TEXT	Engine type	Petrol or diesel.
STAT_GETRIEBE_NR	Gearbox type	0 = manual, 1 = automatic, 2 = SMG.
STAT_GETRIEBE_TEXT	Gearbox type	Manual, automatic or SMG.
STAT_ZEITINSPEKTION	Time-based inspection	0 = no time-based inspection.
STAT_VORGEZOGENE_ZEITINSPEKTION	Early time inspection possible	1 = yes.
STAT_INSPEKTIONSGRENZE_WERT	Inspection limit	Service interval limit.
STAT_ZEITGRENZE_WERT	Time limit	Time-based service limit.
STAT_KRAFTSTOFFMENGE_WERT	Fuel used since service	Fuel consumed (drives the service indicator).
STAT_ZEIT_INSP_ZAEHLER_WERT	Time inspection counter	Counter for time-based service.
STAT_SERVICE_ART	Last service type	0 = inspection, 1 = oil service.
STAT_SERVICE_TEXT	Last service type	Inspection or oil service.
STAT_TANKINHALT_HEBEL1_WERT	Fuel level sender 1	Litres (left tank half).
STAT_TANKINHALT_HEBEL2_WERT	Fuel level sender 2	Litres (right tank half).
STAT_TANKINHALT_UNGEF_WERT	Fuel level (raw)	Total litres, unfiltered.
STAT_TANKINHALT_GEF_WERT	Fuel level (shown)	Total litres, filtered as the gauge shows it.
STAT_RESERVE	Fuel reserve reached	ON/OFF.
STAT_AUSSENTEMP_GEF_WERT	Outside temperature (shown)	°C, filtered.
STAT_AUSSENTEMP_UNGEF_WERT	Outside temperature (raw)	°C, unfiltered.
STAT_HANDBREMSE_EIN	Handbrake switch	1 = handbrake on.
STAT_GURTKONTAKT_EIN	Seat belt buckle	1 = buckled.
STAT_OELDRUCK_EIN	Oil pressure switch	1 = low oil pressure (switch closed).
STAT_KL30_EIN	Battery feed (terminal 30)	1 = present.
STAT_TASTE_UHR_EIN	Clock button	1 = pressed.
STAT_UHRTASTE_RUECKLAUF_EIN	Clock button back	1 = pressed.
STAT_KL50_EIN	Starter (terminal 50)	1 = cranking.
STAT_SIA_RESET_EIN	Service reset button	1 = pressed.
STAT_UHRTASTE_VORLAUF_EIN	Clock button forward	1 = pressed.
STAT_GONGT3_EIN	Gong	1 = sounding.
STAT_SUMMER_EIN	Buzzer	1 = sounding.
STAT_BREMSFLUESSIGKEIT_EIN	Brake fluid level switch	1 = low fluid warning.
STAT_KLR_EIN	Ignition position 1 (terminal R)	1 = on.
STAT_KL15_EIN	Ignition on (terminal 15)	1 = on.
STAT_KUEHLMITTELSTAND_EIN	Coolant level switch	1 = low coolant warning.
STAT_TASTE_TWSZ_EIN	Trip reset button	1 = pressed.
STAT_LSS_EIN	Light switch input	1 = active.
STAT_5V_WERT	5 V reference	Internal reference voltage (should be ~5 V).
STAT_5V_LONG_WERT	5 V reference (raw)	Raw A/D value.
STAT_HEBELGEBER1_WERT	Fuel sender 1 signal	Raw sender reading.
STAT_HEBELGEBER1_LONG_WERT	Fuel sender 1 signal (raw)	Raw A/D value.
STAT_HEBELGEBER2_WERT	Fuel sender 2 signal	Raw sender reading.
STAT_HEBELGEBER2_LONG_WERT	Fuel sender 2 signal (raw)	Raw A/D value.
STAT_BREMSVERSCHLEISS1_WERT	Brake pad wear sensor	Raw sensor reading.
STAT_BREMSVERSCHLEISS1_LONG_WERT	Brake pad wear sensor (raw)	Raw A/D value.
STAT_AUSSENTEMP_WERT	Outside temp sensor	Raw sensor reading.
STAT_AUSSENTEMP_LONG_WERT	Outside temp sensor (raw)	Raw A/D value.
STAT_MOTORDREHZAHL_WERT	Engine speed	rpm.
STAT_KUEHLMITTELTEMP_WERT	Coolant temperature	°C.
STAT_GANG_INFO_WERT	Current gear	Gear the transmission is in.
STAT_GANG_INFO_TEXT	Current gear	Gear the transmission is in.
STAT_GANG_WHL_ANZ_WERT	Selector position	1–6, D, N, R, P or in between.
STAT_GANG_WHL_ANZ_TEXT	Selector position	1–6, D, N, R, P or in between.
STAT_PRG_INF_ANZ_WERT	Gearbox program shown	E, M, S, W, A or off.
STAT_PRG_INF_ANZ_TEXT	Gearbox program shown	E, M, S, W, A or off.
STAT_L_GETR_STEUERUNG_WERT	Gearbox emergency mode	Whether the transmission is in limp mode.
STAT_L_GETR_STEUERUNG_TEXT	Gearbox emergency mode	Whether the transmission is in limp mode.
STAT_EINSPRITZMENGE_WERT	Injection quantity	Fuel per injection (µl), for the consumption display.
STAT_LAMPE_EBV_EIN	Brake force distribution lamp	1 = on.
STAT_LAMPE_ASC_EIN	ASC/DSC lamp	1 = on.
STAT_VORGLUEHLAMPE_EIN	Glow plug lamp (diesel)	1 = on.
STAT_LAMPE_CHECK_ENGINE_EIN	Check engine lamp	1 = on.
STAT_LAMPE_TEMPOMAT_EIN	Cruise control lamp	1 = on.
STAT_DDE_DIAGNOSELAMPE_EML_EIN	Engine warning lamp (EML)	1 = on.
STAT_LAMPE_UEBERTEMPERATUR_EIN	Overheat lamp	1 = on.
STAT_TOG_HIGH_WERT	Oil level sensor high time	Measured oil level sensor (TOENS) signal.
STAT_TOG_LOW_WERT	Oil level sensor low time	Measured oil level sensor (TOENS) signal.
STAT_STATUS_FLAG_WERT	Oil level status flags	Raw flags.
STAT_DELAY_EIN	Oil level: start delay done	1 = yes.
STAT_OELKALT_EIN	Oil level: cold oil detected	1 = yes.
STAT_OELWARM_EIN	Oil level: warm oil detected	1 = yes.
STAT_FKWREADY_EIN	Oil level: initial measurement done	1 = yes.
STAT_FIRSTAML_EIN	Oil level: first average ready	1 = yes.
STAT_IGNOREMW_EIN	Oil level: readings ignored	1 = readings currently suppressed (e.g. cornering).
STAT_TOG_IMP_COUNTER_WERT	Oil level short-term sample count	Samples in the short-term average.
STAT_MITTEL_LANG_COUNT_WERT	Oil level long-term sample count	Samples in the long-term average.
STAT_DREHZAHL_MITTEL_WERT	Average engine speed	rpm average during measurement.
STAT_TOG_HIGH_MITTEL_WERT	Oil level sensor heat time (avg)	Short-term average.
STAT_TOG_NIVEAU_MITTEL_1_WERT	Oil level (short-term)	Short-term average oil level.
STAT_TOG_NIVEAU_MITTEL_KORR_WERT	Oil level (rpm-corrected)	Short-term average corrected for engine speed.
STAT_TOG_NIVEAU_MITTEL_WERT	Oil level (long-term)	Long-term average oil level.
STAT_TOGINFO_WERT	Oil level info flags	Raw flags.
STAT_WARNUNGH_EIN	Oil loss warning	1 = warning active.
STAT_WARNUNGL_EIN	Oil consumption warning	1 = warning active.
STAT_NOSIGNAL_EIN	Oil level sensor: no signal	1 = no signal from the sensor.
STAT_LITER_WERT	Fuel used	Litres since last service reset.
STAT_TAGES_WERT	Days since time reset	Time since the last time-based service reset.
STAT_BITSTATUS_0x28	Service memory status bit	Internal.
SIA_SPEICHER_CHECK	Service memory check	Overall result of the service memory check.
STAT_U_CAN_TREIBER_AKTIV	CAN driver voltage OK	Status bit.
STAT_U_BASISSENSOR_AKTIV	Sensor supply voltage OK	Status bit.
STAT_SENSOR_U_SCHLEIFER_1_WERT	Sensor track 1 voltage	0–255 digits.
STAT_SENSOR_U_SCHLEIFER_2_WERT	Sensor track 2 voltage	0–255 digits.
STAT_SENSOR_I_WERT	Sensor current	0–4 mA.
STAT_U_KLEMME_87_WERT	Supply voltage (terminal 87)	0–18 V.
STAT_LWS_FABNEU_AKTIV	Sensor is factory-new	1 = never calibrated.
STAT_LWS_POR_AKTIV	Sensor had a power-on reset	1 = yes.
STAT_LWS_WDR_AKTIV	Sensor had a watchdog reset	1 = yes (internal crash/restart).
STAT_LWS_REL_AKTIV	Relative angle only	1 = not calibrated, only gives a relative angle.
STAT_LWS_FILTER_INIT_AKTIV	Filter not initialised	1 = yes.
STAT_LWS_ABGL_AKTIV	In calibration mode	1 = steering angle calibration running.
STAT_CAN_INIT_AKTIV	CAN initialising	1 = yes.
STAT_ASC2_RCV_AKTIV	DSC message received	1 = yes.
STAT_DIAG_RCV_AKTIV	DSC calibration message received	1 = yes.
STAT_PSI_PKT_RCV_AKTIV	DSC steering-rate message received	1 = yes.
STAT_CAN_STAND_RCV_AKTIV	DME CAN-version message received	1 = yes.
STAT_CAN_STAND_OK_AKTIV	CAN version OK	1 = yes.
STAT_CAN_TX_OFF_AKTIV	CAN sending disabled	1 = yes.
STAT_CAN_OFF_AKTIV	CAN bus disabled	1 = yes.
STAT_SDL_ZYKL_SYC_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_ZYKL_START_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_LWR_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_ASC2_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_PSI_PKT_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_VIR_SENS_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_KLASS_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_STAT_ERR_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_LWS1_TR_AKTIV	Scheduler state (internal)	Internal software state.
STAT_SDL_INIT_MOD_AKTIV	Scheduler mode (internal)	Internal software state.
STAT_ASC2_SYC1_MOD_AKTIV	Scheduler mode (internal)	Internal software state.
STAT_ASC2_SYC2_MOD_AKTIV	Scheduler mode (internal)	Internal software state.
STAT_ASC2_ASYC_MOD_AKTIV	Scheduler mode (internal)	Internal software state.
STAT_SDL_SLOW_MOD_AKTIV	Scheduler mode (internal)	Internal software state.
STAT_SDL_NACHLF_MOD_AKTIV	Scheduler mode (internal)	Internal software state.
STAT_SDL_CAN_ERR_MOD_AKTIV	Scheduler mode (internal)	Internal software state.
STAT_LWS_ERR_USPG_AKTIV	Error: battery feed	1 = terminal 30 fault.
STAT_LWS_ERR_I_SENS_AKTIV	Error: sensor current out of range	1 = active.
STAT_LWS_ERR_ABGL_90GR_AKTIV	Error: 90° fault during calibration	1 = active.
STAT_LWS_ERR_90GR_AKTIV	Error: 90° fault	1 = active.
STAT_LWS_ERR_EEPROM_AKTIV	Error: EEPROM	1 = active.
STAT_LWS_ERR_AD_AKTIV	Error: A/D converter	1 = active.
STAT_LWS_ERR_ROM_AKTIV	Error: ROM checksum	1 = active.
STAT_LWS_ERR_RAM_AKTIV	Error: RAM check	1 = active.
STAT_LWS_ERR_ASC_AKTIV	Error: DSC message missing/bad	1 = active.
STAT_LWS_ERR_CAN_STAND_AKTIV	Error: wrong CAN version	1 = active.
STAT_LWS_ERR_ID_AKTIV	Error: wrong vehicle assignment	1 = active.
STAT_LWS_ERR_SW_AKTIV	Error: invalid program flow	1 = active.
STAT_LWS_ERR_LRWPKT_AKTIV	Error: steering rate too high	1 = active.
STAT_LWS_ERR_LRWMAX_AKTIV	Error: steering angle beyond max	1 = active.
STAT_LWS_ERR_STACK_AKTIV	Error: stack	1 = active.
STAT_LWS_ERR_WDG_AKTIV	Error: watchdog reset	1 = active.
STAT_INLRW_G_WERT	Steering angle	Degrees (−1000 to +1000). 0 = straight ahead.
STAT_INLRWPKT_G_WERT	Steering rate	Degrees per second.
STAT_WVREF_G_WERT	Vehicle speed	km/h.
STAT_PRGDLZ_G_WERT	Program cycle time	Microseconds (internal).
STAT_UVRDLVASC_GV_WERT	Wheel speed front left	km/h, as received from DSC.
STAT_UVRDRVASC_GV_WERT	Wheel speed front right	km/h, as received from DSC.
STAT_UVRDLHASC_GV_WERT	Wheel speed rear left	km/h, as received from DSC.
STAT_UVRDRHASC_GV_WERT	Wheel speed rear right	km/h, as received from DSC.
STAT_UPSIPKTSYN_G_WERT	Yaw rate	rad/s.
STAT_UAYSYN_G_WERT	Lateral acceleration	m/s².
STAT_ULRWSYN_G_WERT	Calculated steering angle	Degrees, worked out from other sensors.
STAT_KL30_ZAEHLER	Low-voltage counter	How often the supply dropped too low.
F_ZAHL_BLOCK_1	Faults in block 1	Count.
F_ZAHL_BLOCK_2	Faults in block 2	Count.
F_ZAHL_BLOCK_3	Faults in block 3	Count.
F_ZAHL_BLOCK_4	Faults in block 4	Count.
F_ZAHL_BLOCK_5	Faults in block 5	Count.
F_ZAHL_BLOCK_6	Faults in block 6	Count.
F_ZAHL_BLOCK_7	Faults in block 7	Count.
F_ZAHL_BLOCK_8	Faults in block 8	Count.
STAT_KLEMME_15_EIN	Ignition on (terminal 15)	1 = on.
STAT_SCHALTER_WBL_EIN	Hazard switch	1 = pressed.
STAT_SCHALTER_BLS2_EIN	Brake light switch (2nd contact)	1 = brake pressed.
STAT_SCHALTER2_AL_EIN	Low beam switch (2nd contact)	1 = on.
STAT_SCHALTER_SL_EIN	Parking light switch	1 = on.
STAT_SCHALTER_AL_EIN	Low beam switch	1 = on.
STAT_LICHTSCHALTER_POS_NR	Light switch position	0 = off, 1 = parking, 2 = low beam, 3 = parking + low beam.
STAT_TASTER_NSW_EIN	Front fog light button	1 = pressed.
STAT_TASTER_NSL_EIN	Rear fog light button	1 = pressed.
STAT_EINGANG_BLS_EIN	Brake light switch	1 = brake pressed.
STAT_KLEMME_R_EIN	Ignition position 1 (terminal R)	1 = on.
STAT_FL_LH_POS_NR	High beam stalk position	0 = off, 1 = flash, 2 = high beam, 3 = short circuit.
STAT_SCHALTER_FL_LH_KURZSCHLUSS_MASSE_EIN	High beam stalk shorted to ground	1 = fault.
STAT_SCHALTER_FL_EIN	High beam switch	1 = on.
STAT_SCHALTER_LH_EIN	Headlight flash switch	1 = pulled.
STAT_SCHALTER_FL_LH_RUHE_EIN	High beam stalk at rest	1 = yes.
STAT_SCHALTER_FL_LH_WERT	High beam stalk signal	Raw value.
STAT_BLK_POS_NR	Indicator stalk position	0 = off, 1 = right, 2 = left, 3 = short circuit.
STAT_SCHALTER_BLK_KURZSCHLUSS_MASSE_EIN	Indicator stalk shorted to ground	1 = fault.
STAT_SCHALTER_BLK_LINKS_EIN	Indicator stalk left	1 = on.
STAT_SCHALTER_BLK_RECHTS_EIN	Indicator stalk right	1 = on.
STAT_SCHALTER_BLK_RUHE_EIN	Indicator stalk at rest	1 = yes.
STAT_SCHALTER_BLK_WERT	Indicator stalk signal	Raw value.
STAT_AUSGANG_BREMSLICHT_MITTE_EIN	Output: centre brake light	1 = on.
STAT_AUSGANG_SL_RECHTS_VORN_EIN	Output: parking light front right	1 = on.
STAT_AUSGANG_BREMSLICHT_LINKS_EIN	Output: brake light left	1 = on.
STAT_AUSGANG_BREMSLICHT_RECHTS_EIN	Output: brake light right	1 = on.
STAT_AUSGANG_BLK_LINKS_VORN_EIN	Output: indicator front left	1 = on.
STAT_AUSGANG_BLK_RECHTS_VORN_EIN	Output: indicator front right	1 = on.
STAT_AUSGANG_LWR_EIN	Output: headlight levelling	1 = on.
STAT_AUSGANG_AL_RECHTS_EIN	Output: low beam right	1 = on.
STAT_AUSGANG_AL_LINKS_EIN	Output: low beam left	1 = on.
STAT_AUSGANG_SL_LINKS_VORN_EIN	Output: parking light front left	1 = on.
STAT_AUSGANG_FL_LINKS_EIN	Output: high beam left	1 = on.
STAT_AUSGANG_FL_RECHTS_EIN	Output: high beam right	1 = on.
STAT_AUSGANG_SL_LINKS_HINTEN_EIN	Output: tail light left	1 = on.
STAT_AUSGANG_NSW_RELAIS_EIN	Output: front fog light relay	1 = on.
STAT_AUSGANG_KZL_EIN	Output: number plate light	1 = on.
STAT_AUSGANG_SL_RECHTS_HINTEN_EIN	Output: tail light right	1 = on.
STAT_AUSGANG_NSL_EIN	Output: rear fog light	1 = on.
STAT_AUSGANG_BLK_LINKS_HINTEN_EIN	Output: indicator rear left	1 = on.
STAT_AUSGANG_BLK_RECHTS_HINTEN_EIN	Output: indicator rear right	1 = on.
STAT_SPANNUNG_BELADUNGSSENSOR_VORN_WERT	Front ride-height sensor voltage	0–5 V (headlight levelling).
STAT_NOTFUNKTION_PER_DIAGNOSE_AKTIV	Emergency lights mode (diagnosis)	1 = active.
STAT_DIMMUNG_KL58g_EIN	Dash lighting dimmer (terminal 58g)	1 = on.
STAT_DIMMUNG_WBL_SUCHBELEUCHTUNG_EIN	Hazard button locator light	1 = on.
STAT_DIMMUNG_LICHTSCHALTERBELEUCHTUNG_EIN	Light switch illumination	1 = on.
STAT_NSL_ANHAENGER_EIN	Trailer rear fog light	1 = on.
STAT_WARNBLINKEN_AKTIV	Hazards flashing	1 = active.
STAT_U_BATT_WERT	Battery voltage	0–18 V.
STAT_BLINKLICHT_LINKS_ANHAENGER_EIN	Trailer indicator left	1 = on.
STAT_BLINKLICHT_RECHTS_ANHAENGER_EIN	Trailer indicator right	1 = on.
STAT_BREMSLICHT_ANHAENGER_EIN	Trailer brake light	1 = on.
STAT_STANDLICHT_LINKS_ANHAENGER_EIN	Trailer tail light left	1 = on.
STAT_STANDLICHT_RECHTS_ANHAENGER_EIN	Trailer tail light right	1 = on.
STAT_NSL_RFS_ANHAENGER_EIN	Trailer fog/reverse light	1 = on.
STAT_PARITY_AHM	Trailer module parity	Internal check bit.
STAT_BL_MITTE_DEFEKT	Bulb out: centre brake light	1 = failed.
STAT_SL_RECHTS_VORN_DEFEKT	Bulb out: parking light front right	1 = failed.
STAT_BL_LINKS_DEFEKT	Bulb out: brake light left	1 = failed.
STAT_BL_RECHTS_DEFEKT	Bulb out: brake light right	1 = failed.
STAT_BLK_LINKS_VORN_DEFEKT	Bulb out: indicator front left	1 = failed.
STAT_BLK_RECHTS_VORN_DEFEKT	Bulb out: indicator front right	1 = failed.
STAT_AL_RECHTS_DEFEKT	Bulb out: low beam right	1 = failed.
STAT_AL_LINKS_DEFEKT	Bulb out: low beam left	1 = failed.
STAT_SL_LINKS_VORN_DEFEKT	Bulb out: parking light front left	1 = failed.
STAT_FL_LINKS_DEFEKT	Bulb out: high beam left	1 = failed.
STAT_FL_RECHTS_DEFEKT	Bulb out: high beam right	1 = failed.
STAT_SL_LINKS_HINTEN_DEFEKT	Bulb out: tail light left	1 = failed.
STAT_BLK_ZUSATZ_LINKS_DEFEKT	Bulb out: side repeater left	1 = failed.
STAT_KZL_DEFEKT	Bulb out: number plate light	1 = failed.
STAT_BLK_ZUSATZ_RECHTS_DEFEKT	Bulb out: side repeater right	1 = failed.
STAT_SL_RECHTS_HINTEN_DEFEKT	Bulb out: tail light right	1 = failed.
STAT_NSL_DEFEKT	Bulb out: rear fog light	1 = failed.
STAT_BLK_LINKS_HINTEN_DEFEKT	Bulb out: indicator rear left	1 = failed.
STAT_BLK_RECHTS_HINTEN_DEFEKT	Bulb out: indicator rear right	1 = failed.
STAT_EINGANGSSPANNUNG_DIMMER_WERT	Dimmer wheel voltage	0–5 V.
STAT_EINGANGSSPANNUNG_LWR_POTI_WERT	Headlight levelling input voltage	0–5 V (rear ride-height sensor on xenon cars).
STAT_SPANNUNG_BELADUNGSSENSOR_HINTEN_WERT	Rear ride-height sensor voltage	0–5 V.
STAT_CRASH_WARNBLINKEN_AKTIV	Hazards from crash signal	1 = hazards triggered by the airbag crash signal.
STAT_DWA_WARNBLINKEN_AKTIV	Hazards from alarm	1 = alarm is flashing the hazards.
STAT_DWA_AL_BLINKEN_AKTIV	Alarm flashing low beams	1 = active.
STAT_DWA_FL_BLINKEN_AKTIV	Alarm flashing high beams	1 = active.
STAT_CRASHSENSOR_AKTIV	Crash signal received	1 = active.
STAT_DWA_AUSGELOEST	Alarm triggered	1 = alarm has gone off.
STAT_EINGANGSSPANNUNG_FOTOZELLE_WERT	Light sensor voltage	0–5 V.
STAT_TEST_SCHALTER_SL_EIN	Self-test: parking light switch	1 = test active.
STAT_TEST_SCHALTER_AL_EIN	Self-test: low beam switch	1 = test active.
STAT_TEST_TASTER_NSW_EIN	Self-test: front fog button	1 = test active.
STAT_TEST_TASTER_NSL_EIN	Self-test: rear fog button	1 = test active.
STAT_TEST_DIMMER_POTI_EIN	Self-test: dimmer wheel	1 = test active.
STAT_TEST_LWR_POTI_EIN	Self-test: headlight levelling wheel	1 = test active.
STAT_TEST_SCHALTER_FL_EIN	Self-test: high beam switch	1 = test active.
STAT_TEST_SCHALTER_LH_EIN	Self-test: flash switch	1 = test active.
STAT_TEST_SCHALTER_BLK_LINKS_EIN	Self-test: indicator left	1 = test active.
STAT_TEST_SCHALTER_BLK_RECHTS_EIN	Self-test: indicator right	1 = test active.
STAT_TEST_EINGANG_BLS_EIN	Self-test: brake light switch	1 = test active.
STAT_TEST_SCHALTER_WBL_EIN	Self-test: hazard switch	1 = test active.
STAT_RADIO_VARIANTE	Wheel has radio buttons	0 = no, 1 = yes.
STAT_TELEFON_VARIANTE	Wheel has phone buttons	0 = no, 1 = yes.
STAT_UMLUFT_VARIANTE	Wheel has recirculation button	0 = no, 1 = yes.
STAT_TEMPOMAT_VARIANTE	Wheel has cruise control	0 = no, 1 = yes.
STAT_LENKRADHEIZUNG_VARIANTE	Wheel has heating	0 = no, 1 = yes.
STAT_TEMP_WA_BETAETIGT	Cruise: resume button	1 = pressed.
STAT_TEMP_SB_BETAETIGT	Cruise: set/accelerate button	1 = pressed.
STAT_TEMP_VER_BETAETIGT	Cruise: decelerate button	1 = pressed.
STAT_TEMP_AUS_BETAETIGT	Cruise: off button	1 = pressed.
STAT_UMLUFT_BETAETIGT	Recirculation button	1 = pressed.
STAT_SEEK_UP_BETAETIGT	Seek up button	1 = pressed.
STAT_VOL_UP_BETAETIGT	Volume + button	1 = pressed.
STAT_VOL_DOWN_BETAETIGT	Volume − button	1 = pressed.
STAT_SEEK_DOWN_BETAETIGT	Seek down button	1 = pressed.
STAT_R_T_BETAETIGT	Radio/phone (R/T) button	1 = pressed.
STAT_TELEFON_BETAETIGT	Phone button	1 = pressed.
STAT_LENKRADHEIZUNG_BETAETIGT	Wheel heating button	1 = pressed.
STAT_U_SG_WERT	Supply voltage	Volts at the steering wheel module.
F_UW_SATZ	Number of condition sets	How many freeze-frame sets were stored.
STAT_ZK0	Igniter circuit 0	1 = OK, 0 = fault (wiring/connector).
STAT_ZK1	Igniter circuit 1	1 = OK, 0 = fault (wiring/connector).
STAT_ZK2	Igniter circuit 2	1 = OK, 0 = fault (wiring/connector).
STAT_ZK3	Igniter circuit 3	1 = OK, 0 = fault (wiring/connector).
STAT_ZK4	Igniter circuit 4	1 = OK, 0 = fault (wiring/connector).
STAT_ZK5	Igniter circuit 5	1 = OK, 0 = fault (wiring/connector).
STAT_ZK6	Igniter circuit 6	1 = OK, 0 = fault (wiring/connector).
STAT_ZK7	Igniter circuit 7	1 = OK, 0 = fault (wiring/connector).
STAT_ZK8	Igniter circuit 8	1 = OK, 0 = fault (wiring/connector).
STAT_ZK9	Igniter circuit 9	1 = OK, 0 = fault (wiring/connector).
STAT_ZK10	Igniter circuit 10	1 = OK, 0 = fault (wiring/connector).
STAT_ZK11	Igniter circuit 11	1 = OK, 0 = fault (wiring/connector).
STAT_ZK12	Igniter circuit 12	1 = OK, 0 = fault (wiring/connector).
STAT_ZK13	Igniter circuit 13	1 = OK, 0 = fault (wiring/connector).
STAT_ZK14	Igniter circuit 14	1 = OK, 0 = fault (wiring/connector).
STAT_ZK15	Igniter circuit 15	1 = OK, 0 = fault (wiring/connector).
STAT_SBE	Passenger seat occupied	0 = occupied, 1 = empty.
STAT_GURTSCHLOSS_F	Driver seat belt buckled	1 = buckled, 0 = not buckled/missing/faulty.
STAT_GURTSCHLOSS_BF	Passenger seat belt buckled	1 = buckled, 0 = not buckled/missing/faulty.
STAT_SBE_X_FEHLER	Seat occupancy sensor OK	1 = OK, 0 = faulty.
STAT_SACSR_FEHLER	Right side-impact sensor OK	1 = OK, 0 = faulty.
STAT_SACSL_FEHLER	Left side-impact sensor OK	1 = OK, 0 = faulty.
STAT_SBE2_KIND	Child seat detected	0 = child seat, 1 = no child seat.
STAT_SBE2_OOP	Passenger out of position	0 = out of position, 1 = normal.
STAT_F_LEHNE_NV	Driver backrest unlocked	1 = unlocked, −1 = not available.
STAT_F_LEHNE_V	Driver backrest locked	1 = locked, −1 = not available.
STAT_F_LEHNE_MODUL_FEHLER	Driver backrest module OK	1 = OK, 0 = fault, −1 = not available.
STAT_F_LEHNE_SYSTEM_FEHLER	Driver backrest system OK	1 = OK, 0 = fault, −1 = not available.
STAT_BF_LEHNE_NV	Passenger backrest unlocked	1 = unlocked, −1 = not available.
STAT_BF_LEHNE_V	Passenger backrest locked	1 = locked, −1 = not available.
STAT_BF_LEHNE_MODUL_FEHLER	Passenger backrest module OK	1 = OK, 0 = fault, −1 = not available.
STAT_BF_LEHNE_SYSTEM_FEHLER	Passenger backrest system OK	1 = OK, 0 = fault, −1 = not available.
ID_AI_NR	Change index	Revision of the engine computer.
ID_PROD_NR	Production number	Engine computer production number.
ID_AIF_VORHANDEN	Has vehicle data block	1 = vehicle information (VIN etc.) stored.
ID_MOTOR	Engine ID	Engine identifier used by BMW test equipment.
ID_LAMBDA_STEREO	Lambda layout	0 = one bank, 1 = two banks (stereo).
ID_EML	Throttle system type	0 = none, 1 = EML M70, 2 = EML M73.
ID_LU_MESSUNG	Misfire measurement	1 = supported.
ID_OBD2	OBD-II car	0 = Europe (ECE), 1 = OBD-II.
ID_SG_HERSTELLER	Engine computer maker	0 = Bosch, 1 = Siemens.
ID_EWS_SS	Immobilizer interface	Type of EWS link.
STATUS_CHECKSUMME_WERT	Coding checksum	Checksum of the coding data.
AIF_FG_NR	VIN	Vehicle identification number.
AIF_DATUM	Production date	When the car/module was built.
AIF_AENDERUNGS_INDEX	Change index	Revision.
AIF_SW_NR	Software number	Software version.
AIF_BEHOERDEN_NR	Emissions approval number	Authority (homologation) number.
AIF_ZB_NR	Assembly number	BMW assembly (ZB) number.
AIF_ANZAHL_PROG	Times programmed	How often the module has been flashed.
F_ANZ_NR	Number of faults	Total stored faults.
F_LZ	Logistic counter	How many drive cycles ago the fault was last seen (counts down).
F_VORHANDEN	Fault present now	1 = currently present.
F_ART_BYTE	Fault type byte	Raw fault type flags.
STAT_BA_EIN	Acceleration enrichment	1 = extra fuel for acceleration.
STAT_SA_EIN	Overrun fuel cut-off	1 = injectors off while coasting.
STAT_LSHV1_EIN	O2 sensor heater pre-cat bank 1	1 = on.
STAT_LSHV2_EIN	O2 sensor heater pre-cat bank 2	1 = on.
STAT_LSHN1_EIN	O2 sensor heater post-cat bank 1	1 = on.
STAT_LSHN2_EIN	O2 sensor heater post-cat bank 2	1 = on.
STAT_ZUENDUNG1_EIN	Ignition cylinder 1	1 = active.
STAT_ZUENDUNG2_EIN	Ignition cylinder 2	1 = active.
STAT_ZUENDUNG3_EIN	Ignition cylinder 3	1 = active.
STAT_ZUENDUNG4_EIN	Ignition cylinder 4	1 = active.
STAT_ZUENDUNG5_EIN	Ignition cylinder 5	1 = active.
STAT_ZUENDUNG6_EIN	Ignition cylinder 6	1 = active.
STAT_ZUENDUNG7_EIN	Ignition cylinder 7	1 = active.
STAT_ZUENDUNG8_EIN	Ignition cylinder 8	1 = active.
STAT_AKL_EIN	Exhaust flap	1 = flap open/energised.
STAT_SLP_EIN	Secondary air pump	1 = running.
STAT_SLV_EIN	Secondary air valve	1 = open.
STAT_ELU_EIN	Electric radiator fan	1 = on.
STAT_EKP_EIN	Fuel pump	1 = running.
STAT_NOISE_EIN	Noise reduction mode	1 = active.
STAT_SCHUTZ_EIN	Knock protection mode	1 = timing pulled back for protection.
STAT_KLOPFREGELUNG_EIN	Knock control	1 = active.
STAT_KLOPFREG_EIN	Knock control	1 = active.
STAT_KRAFTSCHLUSS_EIN	Drivetrain engaged	1 = clutch engaged / in gear.
STAT_KO_EIN	A/C compressor	1 = on.
STATUS_KO_EIN	A/C compressor	1 = on.
STATUS_AC_EIN	A/C compressor	1 = on.
STAT_AC_EIN	A/C compressor	1 = on.
STAT_LDP_EIN	Fuel tank leak test switch	1 = closed.
STAT_REEDSWITCH_EIN	Fuel tank leak test switch	1 = closed.
STAT_MOTOR_STEHT	Engine stopped	1 = not turning.
STAT_MOTOR_START	Engine starting	1 = cranking/start phase.
STAT_LL_EIN	Idle	1 = idling.
STATUS_LL_EIN	Idle	1 = idling.
STAT_VL_EIN	Part load	1 = part throttle.
STATUS_VL_EIN	Part load	1 = part throttle.
STAT_TL_EIN	Full load	1 = full throttle.
STAT_MOTOR_NACHLAUF	After-run	1 = engine computer still running after switch-off.
STAT_KATHEIZEN_EIN	Catalyst heating	1 = warming the cats after a cold start.
STAT_KUP_EIN	Clutch switch	1 = clutch pressed.
STAT_BLS_EIN	Brake light switch	1 = brake pressed.
STAT_BLTS_EIN	Brake test switch	1 = brake pressed (second contact).
STAT_EWS3_FREIGABE	Immobilizer release	1 = EWS has released the engine.
STAT_FDYN_EIN	Sport button	1 = pressed.
STAT_MIL_EIN	Check engine lamp	1 = on.
STAT_MFL1_EIN	Steering wheel button 1	1 = pressed.
STAT_MFL2_EIN	Steering wheel button 2	1 = pressed.
STAT_MFL3_EIN	Steering wheel button 3	1 = pressed.
STAT_MFL4_EIN	Steering wheel button 4	1 = pressed.
STAT_LLR_EIN	Idle speed control	1 = active.
STAT_LDR1_EIN	Lambda control bank 1	1 = closed-loop active.
STAT_LDR2_EIN	Lambda control bank 2	1 = closed-loop active.
STAT_FGRA_EIN	Cruise control	1 = active.
STATUS_SYNC_MODE_STATUS	Sync mode	Status flag.
STATUS_SYNC_MODE_TEXT	Sync mode	Status text.
STAT_ADD_WERT	Fuel trim additive bank 1	Idle mixture correction (adaptation).
STATUS_ADD_WERT	Fuel trim additive bank 1	Idle mixture correction (adaptation).
STAT_LAMBDA_ADD_1_WERT	Fuel trim additive bank 1	Idle mixture correction (adaptation).
STAT_ADD_2_WERT	Fuel trim additive bank 2	Idle mixture correction (adaptation).
STATUS_ADD_2_WERT	Fuel trim additive bank 2	Idle mixture correction (adaptation).
STAT_LAMBDA_ADD_2_WERT	Fuel trim additive bank 2	Idle mixture correction (adaptation).
STAT_VANOS_NW_LAGE_EINLASS_BANK_1_WERT	Exhaust cam position bank 1	Actual exhaust VANOS position (see VANOS tab).
STAT_VANOS_NW_LAGE_EINLASS_BANK_2_WERT	Exhaust cam position bank 2	Actual exhaust VANOS position (see VANOS tab).
STAT_AVANOS1_SOLL_WERT	Exhaust VANOS target bank 1	Target exhaust cam angle.
STAT_AVANOS2_SOLL_WERT	Exhaust VANOS target bank 2	Target exhaust cam angle.
STAT_AQREL_WERT	Relative cylinder charge	Air charge per stroke as % of maximum.
STAT_ISERV_WERT	Throttle servo current	Actual current to the throttle motor.
STAT_SSERV_WERT	Throttle servo target	Target current to the throttle motor.
STAT_SERVO_I_IST_WERT	Throttle servo current (actual)	Amps.
STAT_SERVO_I_SOLL_WERT	Throttle servo current (target)	Amps.
STAT_DKP_WINKEL_WERT	Throttle angle	Actual throttle opening.
STAT_DKP_WINKEL_SOLL_WERT	Throttle angle target	Requested throttle opening.
STAT_EVANOS1_IST_WERT	Intake VANOS actual bank 1	Intake cam angle.
STAT_EVANOS2_IST_WERT	Intake VANOS actual bank 2	Intake cam angle.
STAT_EVANOS1_SOLL_WERT	Intake VANOS target bank 1	Target intake cam angle.
STAT_EVANOS2_SOLL_WERT	Intake VANOS target bank 2	Target intake cam angle.
STAT_PWG_POTI_WINKEL_WERT	Accelerator pedal angle (sensor 1)	Pedal position.
STAT_PWG_POTI_WINKEL_2_WERT	Accelerator pedal angle (sensor 2)	Pedal position (second track).
STAT_LAMBDA_INTEGRATOR_1_WERT	Lambda integrator bank 1	Short-term fuel correction (1.0 = none).
STATUS_INT_WERT	Lambda integrator bank 1	Short-term fuel correction (1.0 = none).
STAT_INT_WERT	Lambda integrator bank 1	Short-term fuel correction (1.0 = none).
STAT_LAMBDA_INTEGRATOR_2_WERT	Lambda integrator bank 2	Short-term fuel correction (1.0 = none).
STATUS_INT_2_WERT	Lambda integrator bank 2	Short-term fuel correction (1.0 = none).
STAT_INT_2_WERT	Lambda integrator bank 2	Short-term fuel correction (1.0 = none).
STAT_LFR_KO_WERT	Idle control (A/C on)	Idle air adaptation with compressor on.
STAT_LFR_WERT	Idle control	Idle air adaptation.
STAT_LS_NKAT_SIGNAL_1_WERT	O2 sensor post-cat bank 1	Voltage.
STAT_L_SONDE_H_WERT	O2 sensor post-cat bank 1	Voltage.
STATUS_L_SONDE_H_WERT	O2 sensor post-cat bank 1	Voltage.
STAT_LS_NKAT_SIGNAL_2_WERT	O2 sensor post-cat bank 2	Voltage.
STAT_L_SONDE_2_H_WERT	O2 sensor post-cat bank 2	Voltage.
STATUS_L_SONDE_2_H_WERT	O2 sensor post-cat bank 2	Voltage.
STAT_LS_VKAT_SIGNAL_1_WERT	O2 sensor pre-cat bank 1	Voltage (switches ~0.1–0.9 V when warm).
STAT_L_SONDE_WERT	O2 sensor pre-cat bank 1	Voltage (switches ~0.1–0.9 V when warm).
STATUS_L_SONDE_WERT	O2 sensor pre-cat bank 1	Voltage (switches ~0.1–0.9 V when warm).
STAT_LS_VKAT_SIGNAL_2_WERT	O2 sensor pre-cat bank 2	Voltage (switches ~0.1–0.9 V when warm).
STAT_L_SONDE_2_WERT	O2 sensor pre-cat bank 2	Voltage (switches ~0.1–0.9 V when warm).
STATUS_L_SONDE_2_WERT	O2 sensor pre-cat bank 2	Voltage (switches ~0.1–0.9 V when warm).
STAT_PWG_POTI_SPANNUNG_1_WERT	Accelerator pedal sensor voltage	Volts.
STAT_ROHWERT1	Raw value 1	Raw sensor reading.
STAT_ROHWERT2	Raw value 2	Raw sensor reading.
STATUS_LMM_MASSE_WERT	Air mass	Air flow into the engine (kg/h).
STAT_LMM_MASSE_WERT	Air mass	Air flow into the engine (kg/h).
STATUS_LMM_WERT	Air mass sensor	Air flow meter reading.
STAT_LAMBDA_MUL_1_WERT	Fuel trim multiplicative bank 1	Mixture correction under load (adaptation, 1.0 = none).
STAT_MUL_WERT	Fuel trim multiplicative bank 1	Mixture correction under load (adaptation, 1.0 = none).
STATUS_MUL_WERT	Fuel trim multiplicative bank 1	Mixture correction under load (adaptation, 1.0 = none).
STAT_LAMBDA_MUL_2_WERT	Fuel trim multiplicative bank 2	Mixture correction under load (adaptation, 1.0 = none).
STAT_MUL_2_WERT	Fuel trim multiplicative bank 2	Mixture correction under load (adaptation, 1.0 = none).
STATUS_MUL_2_WERT	Fuel trim multiplicative bank 2	Mixture correction under load (adaptation, 1.0 = none).
STATUS_MOTORDREHZAHL_WERT	Engine speed	rpm.
STAT_NMAX_WERT	Rev limit	Current maximum engine speed.
STAT_N_LL_SOLL_WERT	Target idle speed	rpm.
STAT_PUMG_INTERN_WERT	Ambient pressure	Barometric pressure (internal sensor).
STAT_RF_WERT	Relative humidity / load factor	Internal load value.
STAT_TABG_WERT	Exhaust temperature (modelled)	Calculated exhaust gas temperature.
STATUS_AN_LUFTTEMPERATUR_WERT	Intake air temperature	°C.
STAT_AN_LUFTTEMPERATUR_WERT	Intake air temperature	°C.
STAT_EINSPRITZZEIT_WERT	Injection time cylinder 1	Milliseconds.
STAT_TI2_WERT	Injection time cylinder 2	Milliseconds.
STAT_TI3_WERT	Injection time cylinder 3	Milliseconds.
STAT_TI4_WERT	Injection time cylinder 4	Milliseconds.
STAT_TI5_WERT	Injection time cylinder 5	Milliseconds.
STAT_TI6_WERT	Injection time cylinder 6	Milliseconds.
STAT_TI7_WERT	Injection time cylinder 7	Milliseconds.
STAT_TI8_WERT	Injection time cylinder 8	Milliseconds.
STAT_TI_AUS_IST_WERT	Injection time (output)	Actual injection time, ms.
STAT_KUEHLW_AUSL_TEMPERATUR_WERT	Radiator outlet temperature	°C.
STAT_LAST_WERT	Engine load	%.
STATUS_MOTORTEMPERATUR_WERT	Coolant temperature	°C.
STAT_MOTORTEMPERATUR_WERT	Coolant temperature	°C.
STAT_TNMAX_WERT	Rev limit (temperature-based)	Max rpm allowed at current oil temp (cold-engine limit).
STAT_OEL_TEMPERATUR_WERT	Oil temperature	°C.
STAT_TUMG_WERT	Ambient temperature	°C.
STAT_TV_TEV_WERT	Purge valve duty	Fuel vapour (canister purge) valve opening.
STAT_TZ1_WERT	Ignition timing cylinder 1	Degrees before TDC.
STAT_TZ2_WERT	Ignition timing cylinder 2	Degrees before TDC.
STAT_TZ3_WERT	Ignition timing cylinder 3	Degrees before TDC.
STAT_TZ4_WERT	Ignition timing cylinder 4	Degrees before TDC.
STAT_TZ5_WERT	Ignition timing cylinder 5	Degrees before TDC.
STAT_TZ6_WERT	Ignition timing cylinder 6	Degrees before TDC.
STAT_TZ7_WERT	Ignition timing cylinder 7	Degrees before TDC.
STAT_TZ8_WERT	Ignition timing cylinder 8	Degrees before TDC.
STATUS_UBATT_WERT	Battery voltage	Volts at the engine computer.
STAT_UBATT_WERT	Battery voltage	Volts at the engine computer.
STAT_UEXT1_WERT	External voltage 1	Volts.
STAT_UEXT2_WERT	External voltage 2	Volts.
STATUS_GESCHWINDIGKEIT_WERT	Vehicle speed	km/h.
STAT_V_CAN_WERT	Vehicle speed (CAN)	km/h from DSC.
STAT_VMAX_WERT	Speed limiter	Maximum vehicle speed.
STATUS_GEBERRAD_ADAPTION_WERT	Crank sensor wheel adaptation	Whether the crank trigger wheel has been learned (needed for misfire detection).
STAT_GEBERRAD_ADAPTION_WERT	Crank sensor wheel adaptation	Whether the crank trigger wheel has been learned (needed for misfire detection).
STAT_SYSTEMCHECK_LAUFUNRUHE_ZYL1_WERT	Rough running cylinder 1	Crankshaft speed variation; higher = rougher (see Misfires tab).
STAT_SYSTEMCHECK_LAUFUNRUHE_ZYL2_WERT	Rough running cylinder 2	Crankshaft speed variation; higher = rougher (see Misfires tab).
STAT_SYSTEMCHECK_LAUFUNRUHE_ZYL3_WERT	Rough running cylinder 3	Crankshaft speed variation; higher = rougher (see Misfires tab).
STAT_SYSTEMCHECK_LAUFUNRUHE_ZYL4_WERT	Rough running cylinder 4	Crankshaft speed variation; higher = rougher (see Misfires tab).
STAT_SYSTEMCHECK_LAUFUNRUHE_ZYL5_WERT	Rough running cylinder 5	Crankshaft speed variation; higher = rougher (see Misfires tab).
STAT_SYSTEMCHECK_LAUFUNRUHE_ZYL6_WERT	Rough running cylinder 6	Crankshaft speed variation; higher = rougher (see Misfires tab).
LDP_STROM	Leak test pump current	Fuel tank leak test (DMTL) pump current.
LDP_REFSTROM	Leak test reference current	Current through the reference leak; the test compares against it.
STAT_UEBERGABE_WERT	Handover done	0 = not done, 1 = done (factory/dealer handover).
STAT_LAA_REGLER1_WERT	Lambda control adaptation bank 1	Learned mixture correction.
STAT_LAA_REGLER2_WERT	Lambda control adaptation bank 2	Learned mixture correction.
STAT_LAA_F1_WERT	Lambda adaptation factor bank 1	Learned multiplicative fuel correction (1.0 = none).
STAT_LAA_F2_WERT	Lambda adaptation factor bank 2	Learned multiplicative fuel correction (1.0 = none).
STAT_LAA_OFFSET1_WERT	Lambda adaptation offset bank 1	Learned additive fuel correction, ms (vacuum leaks show up here).
STAT_LAA_OFFSET2_WERT	Lambda adaptation offset bank 2	Learned additive fuel correction, ms (vacuum leaks show up here).
STAT_MD_LLRA_WERT	Idle control learned torque	Nm the idle controller has learned to add.
STAT_V_MAX_WERT	Highest speed reached	km/h, as recorded by the engine computer.
STAT_N_MAX_WERT	Highest rpm reached	As recorded by the engine computer.
STAT_T_NBEGR_WERT	Time over rev limit	Total seconds spent at over-speed.
STAT_PWG1_A0_WERT	Pedal sensor 1 rest voltage	Learned zero position, V.
STAT_PWG2_A0_WERT	Pedal sensor 2 rest voltage	Learned zero position, V.
STAT_WDK1_NORM_WERT	Throttle sensor 1 slope	%/V.
STAT_WDK2_NORM_WERT	Throttle sensor 2 slope	%/V.
STAT_KKOS_ST_VERBAUT_WERT	A/C detected	Whether air conditioning is fitted.
STAT_WDK1_A0_WERT	Throttle sensor 1 rest voltage	Learned closed position, V.
STAT_WDK2_A0_WERT	Throttle sensor 2 rest voltage	Learned closed position, V.
STAT_LFRA_MD_START_WERT	Idle control start torque	Nm.
STAT_LFRA_KO_MD_START_WERT	Idle control start torque (A/C on)	Nm.
STAT_FRA_ML_START_WERT	Idle control start air mass	kg/h.
STAT_TDME_MIN_WERT	Lowest engine computer temperature	°C recorded.
STAT_TDME_MAX_WERT	Highest engine computer temperature	°C recorded.
STAT_WDK_ADAPT_WERT	Throttle adaptation state	0 = OK.
STAT_WDK_MAX_DIFF_ADAPT_WERT	Throttle sensors learned difference	% difference between the two throttle pots.
STAT_PWG_MAX_DIFF_ADAPT_WERT	Pedal sensors learned difference	% difference between the two pedal pots.
STAT_LU_ADAPT1_WERT	Crank wheel segment cylinder 1	Learned trigger-wheel deviation, ppm.
STAT_LU_ADAPT2_WERT	Crank wheel segment cylinder 2	Learned trigger-wheel deviation, ppm.
STAT_LU_ADAPT3_WERT	Crank wheel segment cylinder 3	Learned trigger-wheel deviation, ppm.
STAT_LU_ADAPT4_WERT	Crank wheel segment cylinder 4	Learned trigger-wheel deviation, ppm.
STAT_LU_ADAPT5_WERT	Crank wheel segment cylinder 5	Learned trigger-wheel deviation, ppm.
STAT_LU_ADAPT6_WERT	Crank wheel segment cylinder 6	Learned trigger-wheel deviation, ppm.
STAT_LU_ADAPT7_WERT	Crank wheel segment cylinder 7	Learned trigger-wheel deviation, ppm.
STAT_LU_ADAPT8_WERT	Crank wheel segment cylinder 8	Learned trigger-wheel deviation, ppm.
STAT_LU_ADAP_CNT_WERT	Crank wheel learning cycles	Engine cycles used for the measurement.
STAT_FSP_BS_NOW_WERT	Engine computer hours	Internal operating time, minutes.
STAT_T_ML_WERT	Engine running time	Seconds.
STAT_TDME_TIME_ZAEHLER_WERT	Time engine computer ran hot	Seconds above its temperature threshold.
STAT_TDME_ZYKLEN_WERT	Hot engine computer drive cycles	Drive cycles with the computer above its temperature threshold.
STAT_VVDP_VERBAUT_WERT	Pressure accumulator valve fitted	Configuration flag.
STAT_LDPH_VERBAUT_WERT	Leak test pump heater fitted	Configuration flag.
STAT_EVAN1_ADAP_WERT	Intake VANOS adaptation	Learned intake cam offset, ° crank.
STAT_AVAN1_ADAP_WERT	Exhaust VANOS adaptation	Learned exhaust cam offset, ° crank.
STAT_VAN_ADAP_ST_WERT	VANOS adaptation status	Bit 0 = intake adapted, bit 1 = exhaust adapted.
STAT_FGR_MFL_VERBAUT_WERT	Cruise control fitted	Configuration flag.
STAT_EKP_CFG_VERBAUT_WERT	Fuel pump type	Which fuel pump is configured.
STAT_TI_EINFAHR_ST_WERT	Break-in rev limiter	Running-in limiter state.
STAT_GKS_A0_WERT	Intake noise flap rest voltage	Learned zero position, V.
STAT_PSAU_ADAPT_WERT	Intake pressure adaptation	mbar.
STAT_RF_ADAPT_OFFSET_WERT	Load adaptation offset	Learned value.
STAT_KG_VERBAUT_WERT	Crankcase ventilation type	Configuration flag.
STAT_AUSS_SUM_ADAP0_WERT	Lifetime misfires cylinder 1	Total misfires counted.
STAT_AUSS_SUM_ADAP1_WERT	Lifetime misfires cylinder 2	Total misfires counted.
STAT_AUSS_SUM_ADAP2_WERT	Lifetime misfires cylinder 3	Total misfires counted.
STAT_AUSS_SUM_ADAP3_WERT	Lifetime misfires cylinder 4	Total misfires counted.
STAT_AUSS_SUM_ADAP4_WERT	Lifetime misfires cylinder 5	Total misfires counted.
STAT_AUSS_SUM_ADAP5_WERT	Lifetime misfires cylinder 6	Total misfires counted.
STAT_AUSS_SUM_ADAP6_WERT	Lifetime misfires cylinder 7	Total misfires counted.
STAT_AUSS_SUM_ADAP7_WERT	Lifetime misfires cylinder 8	Total misfires counted.
STAT_AUSS_SUM_DC0_WERT	Misfires this drive, cylinder 1	Count for the current drive cycle.
STAT_AUSS_SUM_DC1_WERT	Misfires this drive, cylinder 2	Count for the current drive cycle.
STAT_AUSS_SUM_DC2_WERT	Misfires this drive, cylinder 3	Count for the current drive cycle.
STAT_AUSS_SUM_DC3_WERT	Misfires this drive, cylinder 4	Count for the current drive cycle.
STAT_AUSS_SUM_DC4_WERT	Misfires this drive, cylinder 5	Count for the current drive cycle.
STAT_AUSS_SUM_DC5_WERT	Misfires this drive, cylinder 6	Count for the current drive cycle.
STAT_AUSS_SUM_DC6_WERT	Misfires this drive, cylinder 7	Count for the current drive cycle.
STAT_AUSS_SUM_DC7_WERT	Misfires this drive, cylinder 8	Count for the current drive cycle.
STAT_KA_ADAP_TZ0_WERT	Knock retard cylinder 1	Learned timing pulled for knock, ° crank.
STAT_KA_ADAP_TZ1_WERT	Knock retard cylinder 2	Learned timing pulled for knock, ° crank.
STAT_KA_ADAP_TZ2_WERT	Knock retard cylinder 3	Learned timing pulled for knock, ° crank.
STAT_KA_ADAP_TZ3_WERT	Knock retard cylinder 4	Learned timing pulled for knock, ° crank.
STAT_KA_ADAP_TZ4_WERT	Knock retard cylinder 5	Learned timing pulled for knock, ° crank.
STAT_KA_ADAP_TZ5_WERT	Knock retard cylinder 6	Learned timing pulled for knock, ° crank.
STAT_KA_ADAP_TZ6_WERT	Knock retard cylinder 7	Learned timing pulled for knock, ° crank.
STAT_KA_ADAP_TZ7_WERT	Knock retard cylinder 8	Learned timing pulled for knock, ° crank.
STAT_A_QUER_L_SEC_WERT	Time cornering hard left	Seconds of high lateral g to the left (oil supply monitoring).
STAT_A_QUER_R_SEC_WERT	Time cornering hard right	Seconds of high lateral g to the right (oil supply monitoring).
STAT_LU_ST_WERT	Misfire detection state	0 = off, 1 = idle, 2 = detecting, 4 = adapting.
STAT_FF_FF_RDY_WERT	Emissions readiness	Bit mask of completed OBD readiness tests.
STAT_FF_FF_DCY_CNT_WERT	Drive cycles since reset	Count.
STAT_FF_FF_WUC_CNT_WERT	Warm-up cycles since reset	Count.
STAT_FF_FF_DCY_CLR_WERT	Drive cycles since faults cleared	Count.
STAT_FF_FF_WUC_CLR_WERT	Warm-up cycles since faults cleared	Count.
STAT_FF_FF_KM_WERT	Freeze frame mileage	km.
STAT_FF_FF_TIME_WERT	Freeze frame time	Engine computer time, minutes.
STAT_FF_FF_RDY_CNT0_WERT	Readiness count: test 1	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT1_WERT	Readiness count: test 2	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT2_WERT	Readiness count: test 3	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT3_WERT	Readiness count: test 4	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT4_WERT	Readiness count: test 5	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT5_WERT	Readiness count: test 6	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT6_WERT	Readiness count: test 7	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT7_WERT	Readiness count: test 8	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT8_WERT	Readiness count: test 9	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT9_WERT	Readiness count: test 10	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT10_WERT	Readiness count: test 11	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT11_WERT	Readiness count: test 12	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT12_WERT	Readiness count: test 13	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT13_WERT	Readiness count: test 14	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT14_WERT	Readiness count: test 15	Times this OBD test completed since reset.
STAT_FF_FF_RDY_CNT15_WERT	Readiness count: test 16	Times this OBD test completed since reset.
STAT_KSD_LAA_OFFSET1_WERT	Fuel system check: offset bank 1	Adaptation offset used by the fuel system diagnosis.
STAT_KSD_LAA_OFFSET2_WERT	Fuel system check: offset bank 2	Adaptation offset used by the fuel system diagnosis.
STAT_KSD_LAA_F1_WERT	Fuel system check: factor bank 1	Adaptation factor used by the fuel system diagnosis.
STAT_KSD_LAA_F2_WERT	Fuel system check: factor bank 2	Adaptation factor used by the fuel system diagnosis.
STAT_KSD_OEL_SPERR_WERT	Oil dilution counter	Fuel-in-oil suspicion counter (blocks the fuel system check).
STAT_TEA1_F_WERT	Purge adaptation bank 1	Fuel vapour purge correction.
STAT_TEA2_F_WERT	Purge adaptation bank 2	Fuel vapour purge correction.
STAT_KSD_LAM1_WERT	Total lambda deviation bank 1	Overall fuel system deviation.
STAT_KSD_LAM2_WERT	Total lambda deviation bank 2	Overall fuel system deviation.
STAT_KSD_OFFSET1_DELTA_WERT	Offset deviation bank 1	Change in additive adaptation.
STAT_KSD_OFFSET2_DELTA_WERT	Offset deviation bank 2	Change in additive adaptation.
STAT_KSD_F1_DELTA_WERT	Factor deviation bank 1	Change in multiplicative adaptation.
STAT_KSD_F2_DELTA_WERT	Factor deviation bank 2	Change in multiplicative adaptation.
STAT_KSD_LL_MAX_T1_WERT	Fuel check: idle too rich time bank 1	Seconds over the limit.
STAT_KSD_LL_MAX_T2_WERT	Fuel check: idle too rich time bank 2	Seconds over the limit.
STAT_KSD_LL_MIN_T1_WERT	Fuel check: idle too lean time bank 1	Seconds over the limit.
STAT_KSD_LL_MIN_T2_WERT	Fuel check: idle too lean time bank 2	Seconds over the limit.
STAT_KSD_TL_MAX_T1_WERT	Fuel check: part load too rich time bank 1	Seconds over the limit.
STAT_KSD_TL_MAX_T2_WERT	Fuel check: part load too rich time bank 2	Seconds over the limit.
STAT_KSD_TL_MIN_T1_WERT	Fuel check: part load too lean time bank 1	Seconds over the limit.
STAT_KSD_TL_MIN_T2_WERT	Fuel check: part load too lean time bank 2	Seconds over the limit.
STAT_KSD_LL_MAX_TRIG1_WERT	Fuel check: idle upper limit hits bank 1	Count.
STAT_KSD_LL_MAX_TRIG2_WERT	Fuel check: idle upper limit hits bank 2	Count.
STAT_KSD_LL_MIN_TRIG1_WERT	Fuel check: idle lower limit hits bank 1	Count.
STAT_KSD_LL_MIN_TRIG2_WERT	Fuel check: idle lower limit hits bank 2	Count.
STAT_KSD_TL_MAX_TRIG1_WERT	Fuel check: part load upper limit hits bank 1	Count.
STAT_KSD_TL_MAX_TRIG2_WERT	Fuel check: part load upper limit hits bank 2	Count.
STAT_KSD_TL_MIN_TRIG1_WERT	Fuel check: part load lower limit hits bank 1	Count.
STAT_KSD_TL_MIN_TRIG2_WERT	Fuel check: part load lower limit hits bank 2	Count.
STAT_KSD_OFFSET1_DELTA_MS_WERT	Offset change since start bank 1	ms.
STAT_KSD_OFFSET2_DELTA_MS_WERT	Offset change since start bank 2	ms.
STAT_LA_ALTER_ST_WERT	O2 sensor ageing check status	Internal status bits.
STAT_LA_ALT_P_ST_WERT	O2 sensor period check status	Internal status bits.
STAT_LA_ALT_P_MESS1_WERT	O2 sensor switching period bank 1	ms; slower = older sensor.
STAT_LA_ALT_P_MESS2_WERT	O2 sensor switching period bank 2	ms; slower = older sensor.
STAT_LA_ALT_P_ANZ_SPR1_WERT	O2 ageing: skipped periods bank 1	Count.
STAT_LA_ALT_P_ANZ_SPR2_WERT	O2 ageing: skipped periods bank 2	Count.
STAT_LA_ALT_P_ANZ_DIAG1_WERT	O2 ageing: measured periods bank 1	Count.
STAT_LA_ALT_P_ANZ_DIAG2_WERT	O2 ageing: measured periods bank 2	Count.
STAT_LA_ALT_NKAT_ST_WERT	Post-cat O2 ageing status	Internal status bits.
STAT_LA_ALTER_S_COUNT1_WERT	Post-cat O2 check error count bank 1	Count.
STAT_LA_ALTER_S_COUNT2_WERT	Post-cat O2 check error count bank 2	Count.
STAT_LA_ALT_SPR_ST_WERT	O2 response time check status	Internal status bits.
STAT_LA_ALT_SPR_ANZ_M1_WERT	Rich-to-lean switches bank 1	Count.
STAT_LA_ALT_SPR_ANZ_M2_WERT	Rich-to-lean switches bank 2	Count.
STAT_LA_ALT_SPR_ANZ_F1_WERT	Lean-to-rich switches bank 1	Count.
STAT_LA_ALT_SPR_ANZ_F2_WERT	Lean-to-rich switches bank 2	Count.
STAT_USV_SPR_MAGER_GEM1_WERT	O2 rich→lean response bank 1	Quality figure; slower = worse.
STAT_USV_SPR_MAGER_GEM2_WERT	O2 rich→lean response bank 2	Quality figure; slower = worse.
STAT_USV_SPR_FETT_GEM1_WERT	O2 lean→rich response bank 1	Quality figure; slower = worse.
STAT_USV_SPR_FETT_GEM2_WERT	O2 lean→rich response bank 2	Quality figure; slower = worse.
STAT_USV_SPR_MAX_REF1_WERT	O2 upper reference bank 1	90% of signal swing, mV.
STAT_USV_SPR_MAX_REF2_WERT	O2 upper reference bank 2	90% of signal swing, mV.
STAT_USV_SPR_MIN_REF1_WERT	O2 lower reference bank 1	10% of signal swing, mV.
STAT_USV_SPR_MIN_REF2_WERT	O2 lower reference bank 2	10% of signal swing, mV.
STAT_LA_KONV1_AD_1_1_WERT	Catalyst check bank 1 (cell 1,1)	Internal catalyst efficiency adaptation.
STAT_LA_KONV1_AD_1_2_WERT	Catalyst check bank 1 (cell 1,2)	Internal catalyst efficiency adaptation.
STAT_LA_KONV1_AD_1_3_WERT	Catalyst check bank 1 (cell 1,3)	Internal catalyst efficiency adaptation.
STAT_LA_KONV1_AD_2_1_WERT	Catalyst check bank 1 (cell 2,1)	Internal catalyst efficiency adaptation.
STAT_LA_KONV1_AD_2_2_WERT	Catalyst check bank 1 (cell 2,2)	Internal catalyst efficiency adaptation.
STAT_LA_KONV1_AD_2_3_WERT	Catalyst check bank 1 (cell 2,3)	Internal catalyst efficiency adaptation.
STAT_LA_KONV1_AD_3_1_WERT	Catalyst check bank 1 (cell 3,1)	Internal catalyst efficiency adaptation.
STAT_LA_KONV1_AD_3_2_WERT	Catalyst check bank 1 (cell 3,2)	Internal catalyst efficiency adaptation.
STAT_LA_KONV1_AD_3_3_WERT	Catalyst check bank 1 (cell 3,3)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_1_1_WERT	Catalyst check bank 2 (cell 1,1)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_1_2_WERT	Catalyst check bank 2 (cell 1,2)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_1_3_WERT	Catalyst check bank 2 (cell 1,3)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_2_1_WERT	Catalyst check bank 2 (cell 2,1)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_2_2_WERT	Catalyst check bank 2 (cell 2,2)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_2_3_WERT	Catalyst check bank 2 (cell 2,3)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_3_1_WERT	Catalyst check bank 2 (cell 3,1)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_3_2_WERT	Catalyst check bank 2 (cell 3,2)	Internal catalyst efficiency adaptation.
STAT_LA_KONV2_AD_3_3_WERT	Catalyst check bank 2 (cell 3,3)	Internal catalyst efficiency adaptation.
STAT_LA_KONV_ST_WERT	Catalyst check status	Internal status bits.
STAT_LA_KONV_ANZ_GRENZ1_WERT	Catalyst check limit violations bank 1	Count.
STAT_LA_KONV_ANZ_GRENZ2_WERT	Catalyst check limit violations bank 2	Count.
STAT_LA_KONV_V_ERR_WERT	Catalyst check error status	Internal.
STAT_LA_KONV_DIAG_TIME1_WERT	Catalyst check time bank 1	Seconds.
STAT_LA_KONV_DIAG_TIME2_WERT	Catalyst check time bank 2	Seconds.
STAT_SLS_DIAG_WERT	Secondary air: flow checks	Number of minimum-flow measurements.
STAT_SLS_DIAG_USV1_WERT	Secondary air: lean checks bank 1	Count.
STAT_SLS_DIAG_USV2_WERT	Secondary air: lean checks bank 2	Count.
STAT_SLV_STARTS_WERT	Secondary air: repeat starts	Count.
STAT_SLV_STARTS_ADAPT_WERT	Secondary air: stored repeat starts	Count.
STAT_SLS_ST1_WERT	Secondary air status 1	Internal.
STAT_SLS_ST2_WERT	Secondary air status 2	Internal.
STAT_SLS_TI_F_DIAG_WERT	Secondary air check enrichment	Extra fuel used during the check.
STAT_LDP_ABBR_FEUCHT_WERT	Leak tests aborted (moisture)	Count.
STAT_LA_ALT_TV_MAX1_WERT	O2 delay check over-limit count bank 1	Count.
STAT_LA_ALT_TV_MAX2_WERT	O2 delay check over-limit count bank 2	Count.
STAT_LA_ALT_TV_MIN1_WERT	O2 delay check under-limit count bank 1	Count.
STAT_LA_ALT_TV_MIN2_WERT	O2 delay check under-limit count bank 2	Count.
STAT_LANK_I_TV_GEM1_WERT	Post-cat trim delay (I) bank 1	ms.
STAT_LANK_I_TV_GEM2_WERT	Post-cat trim delay (I) bank 2	ms.
STAT_LANK_TV1_WERT	Post-cat trim controller bank 1	ms.
STAT_LANK_TV2_WERT	Post-cat trim controller bank 2	ms.
STAT_LANK_I_AD1_WERT	Post-cat trim adaptation bank 1	ms.
STAT_LANK_I_AD2_WERT	Post-cat trim adaptation bank 2	ms.
STAT_LANK_I_TV1_WERT	Post-cat trim delay (I) bank 1	ms.
STAT_LANK_I_TV2_WERT	Post-cat trim delay (I) bank 2	ms.
STAT_LANK_P_TV1_WERT	Post-cat trim delay (P) bank 1	ms.
STAT_LANK_P_TV2_WERT	Post-cat trim delay (P) bank 2	ms.
STAT_SSHDH_AKTIV	Sunroof switch: tilt up	1 = pressed.
STAT_SSHDZ_AKTIV	Sunroof switch: close	1 = pressed.
STAT_DIAG_RMZ_AKTIV	Close relay check	Relay feedback.
STAT_SSHDA_AKTIV	Sunroof switch: open	1 = pressed.
STAT_DIAG_RMA_AKTIV	Open relay check	Relay feedback.
STAT_INKR_M_AKTIV	Motor position sensor (master)	Pulse signal.
STAT_INKR_S_AKTIV	Motor position sensor (slave)	Pulse signal.
STAT_W_TRIG_AKTIV	Watchdog signal	Internal.
STAT_V_INKR_AKTIV	Position sensor supply	1 = on.
STAT_RSHDZ_AKTIV	Close relay driven	1 = on.
STAT_RSHDA_AKTIV	Open relay driven	1 = on.
STAT_THERMO_AKTIV	Motor thermal protection	1 = motor too hot, blocked.
STAT_REV_ZU_AKTIV	Reversed while closing	1 = anti-trap reversed the roof.
STAT_POWER_ON_AKTIV	Sunroof power-on	1 = just powered up.
STAT_NORM_AKTIV	Sunroof initialised	1 = end positions learned.
STAT_HAND_H_AKTIV	Manual tilt	1 = active.
STAT_TIPP_H_AKTIV	One-touch tilt	1 = active.
STAT_HAND_Z_AKTIV	Manual close	1 = active.
STAT_TIPP_Z_AKTIV	One-touch close	1 = active.
STAT_HAND_A_AKTIV	Manual open	1 = active.
STAT_TIPP_A_AKTIV	One-touch open	1 = active.
STAT_HAND_S_AKTIV	Manual lower	1 = active.
STAT_KOMFORT_AKTIV	Comfort close/open	1 = active (from key).
STAT_DIAG_AKTIV	Diagnostic mode	1 = active.
STAT_U_LOW_AKTIV	Low voltage	1 = detected.
STAT_U_HIGH_AKTIV	High voltage	1 = detected.
STAT_DISABLE_AKTIV	Sunroof disabled	1 = disabled.
STAT_SICHER_AKTIV	In safety zone	1 = roof in the anti-trap zone.
STAT_EKS_AKTIV	Anti-trap enabled	1 = on.
STAT_HAND_TIPP	Sunroof operation mode	Manual or one-touch, and direction.
STAT_HAND_TIPP_TEXT	Sunroof operation mode	Manual or one-touch, and direction.
STAT_SHD_POSITION_WERT	Sunroof position	0 to ~500 motor turns.
ID_VARIANTE	Module variant	Body module version (low/high, with/without LIN).
F_LOESCHDATUM_KW	Faults last cleared (week)	Calendar week.
F_LOESCHDATUM_JAHR	Faults last cleared (year)	Year.
STAT_SIB	Interior light switch	Input.
STAT_TOEHK	Trunk release button	Input.
STAT_TZV	Central lock button	Input.
STAT_TOEHS	Rear window release button	Input (Touring).
STAT_TOEHKI	Trunk release button (inside)	Input.
STAT_HKK	Trunk lid contact	1 = open.
STAT_ERHK	Trunk unlock	Input.
STAT_RSK	Wiper park contact	Wiper parked switch.
STAT_SFFA	Driver window switch: down	Input.
STAT_SFFZ	Driver window switch: up	Input.
STAT_SFBA	Passenger window switch: down	Input.
STAT_SFBZ	Passenger window switch: up	Input.
STAT_SW2	Wiper switch 2	Input.
STAT_KISI	Rear window child lock	Input.
STAT_MHK	Hood contact	1 = open.
STAT_HFK	Glovebox contact	1 = open.
STAT_HSK	Rear window contact	1 = open (Touring).
STAT_INRS	Interior motion sensor	Input (alarm).
STAT_NG	Tilt sensor	Input (alarm).
STAT_INRS2	Interior motion sensor 2	Input (alarm).
STAT_KL_R_HW	Ignition position 1 (wired)	Terminal R.
STAT_REE1	Spare input 1	Unused.
STAT_REE3	Spare input 3	Unused.
STAT_CS	Crash sensor	Input from airbag system.
STAT_KL30BTS	Power feed: lights/washer/trunk	Supply present.
STAT_KL30ZV	Power feed: central locking	Supply present.
STAT_KL30FHV	Power feed: front windows	Supply present.
STAT_SFFHA	Rear left window switch: down	Input.
STAT_SFFHZ	Rear left window switch: up	Input.
STAT_SFBHA	Rear right window switch: down	Input.
STAT_SFBHZ	Rear right window switch: up	Input.
STAT_SFFHA2	Rear left window switch 2: down	Input.
STAT_SFFHZ2	Rear left window switch 2: up	Input.
STAT_SFBHA2	Rear right window switch 2: down	Input.
STAT_SFBHZ2	Rear right window switch 2: up	Input.
STAT_REE2	Spare input 2	Unused.
STAT_VRHK	Trunk lock	Input.
STAT_SWA	Washer switch	Input.
STAT_SW1	Wiper switch speed 1	Input.
STAT_DMVR	Lock motor feedback	Diagnosis input.
STAT_DMER	Unlock motor feedback	Diagnosis input.
STAT_DMZS	Deadlock motor feedback	Diagnosis input.
STAT_DMVRFT	Driver door lock feedback	Diagnosis input.
STAT_TKFT	Driver door contact	1 = open.
STAT_TKBT	Passenger door contact	1 = open.
STAT_TKFH	Rear left door contact	1 = open.
STAT_TKBH	Rear right door contact	1 = open.
STAT_VRFT	Driver door lock (key)	Input.
STAT_ERFT	Driver door unlock (key)	Input.
STAT_VRBT	Passenger door lock	Input.
STAT_ERBT	Passenger door unlock	Input.
STAT_DSTDWA	Alarm status feedback	Diagnosis input.
STAT_FZV	Remote central locking	Input from remote receiver.
STAT_DERHK	Trunk release feedback	Diagnosis input.
STAT_DWP	Washer pump feedback	Diagnosis input.
STAT_DVA	Load shedding feedback	Diagnosis input.
STAT_DIB	Interior light feedback	Diagnosis input.
STAT_SFF	Driver window switch	0 = off, 1 = down, 2 = up, 3 = auto.
STAT_SFF_TEXT	Driver window switch	Off, down, up or auto.
STAT_SFB	Passenger window switch	0 = off, 1 = down, 2 = up, 3 = auto.
STAT_SFB_TEXT	Passenger window switch	Off, down, up or auto.
STAT_SFFH	Rear left window switch	0 = off, 1 = down, 2 = up, 3 = auto.
STAT_SFFH_TEXT	Rear left window switch	Off, down, up or auto.
STAT_SFBH	Rear right window switch	0 = off, 1 = down, 2 = up, 3 = auto.
STAT_SFBH_TEXT	Rear right window switch	Off, down, up or auto.
STAT_SFFH2	Rear left window switch 2	0 = off, 1 = down, 2 = up, 3 = auto.
STAT_SFFH2_TEXT	Rear left window switch 2	Off, down, up or auto.
STAT_SFBH2	Rear right window switch 2	0 = off, 1 = down, 2 = up, 3 = auto.
STAT_SFBH2_TEXT	Rear right window switch 2	Off, down, up or auto.
STAT_SW	Wiper switch	0 = off, 1 = intermittent, 2 = speed 1, 3 = speed 2.
STAT_SW_TEXT	Wiper switch	Off, intermittent, speed 1 or speed 2.
STAT_VERFT	Driver door lock state	0 = idle, 1 = locking, 2 = unlocking, 3 = fault.
STAT_VERFT_TEXT	Driver door lock state	Idle, locking, unlocking or fault.
STAT_VERBT	Passenger door lock state	0 = idle, 1 = locking, 2 = unlocking, 3 = fault.
STAT_VERBT_TEXT	Passenger door lock state	Idle, locking, unlocking or fault.
STAT_MFFHA	Output: rear left window down	Motor driven.
STAT_MFFHZ	Output: rear left window up	Motor driven.
STAT_MFBHZ	Output: rear right window up	Motor driven.
STAT_MFBHA	Output: rear right window down	Motor driven.
STAT_MER	Output: unlock motor	Driven.
STAT_MZS	Output: deadlock motor	Driven.
STAT_MVRFT	Output: driver door lock motor	Driven.
STAT_REA3	Spare output 3	Unused.
STAT_WI1	Output: wiper relay speed 1	On.
STAT_WI2	Output: wiper relay speed 2	On.
STAT_SRA	Output: headlight washer relay	On.
STAT_RERHS	Output: rear window release relay	On.
STAT_SIRENE	Output: alarm siren/horn	On.
STAT_DWAL	Output: alarm LED	On.
STAT_MVR	Output: lock motor	Driven.
STAT_MFFA	Output: driver window down	Motor driven.
STAT_MFFZ	Output: driver window up	Motor driven.
STAT_MFBA	Output: passenger window down	Motor driven.
STAT_MFBZ	Output: passenger window up	Motor driven.
STAT_STDWA	Alarm armed	Output status.
STAT_ENEKS	Window anti-trap supply	On.
STAT_ENPU	Input pull-up enabled	Internal.
STAT_REA1	Spare output 1	Unused.
STAT_REA2	Spare output 2	Unused.
STAT_ENANGR1	Analogue inputs group 1 enabled	Internal.
STAT_VA2	Load shedding 2	1 = accessories switched off to save battery.
STAT_IB	Output: interior light	On.
STAT_VA	Load shedding	1 = accessories switched off to save battery.
STAT_WP	Output: washer pump	On.
STAT_MERHK	Output: trunk release motor	Driven.
STAT_CVM_FA	Convertible top: windows down request	From the top module (K-bus).
STAT_CVM_FZ	Convertible top: windows up request	From the top module (K-bus).
STAT_CVM_VKA	Convertible top: open lid request	From the top module (K-bus).
STAT_CVM_VKZ	Convertible top: close lid request	From the top module (K-bus).
STAT_KL_R	Ignition position 1 (K-bus)	Terminal R.
STAT_KL15	Ignition on (K-bus)	Terminal 15.
STAT_KL58	Lights on (K-bus)	Terminal 58.
STAT_EWS_FREE	Immobilizer released (K-bus)	1 = yes.
STAT_EWS_KEY	Valid key inserted (K-bus)	1 = yes.
STAT_RDC	Tyre pressure warning active (K-bus)	1 = yes.
STAT_CSMODE	Crash mode (K-bus)	1 = system in crash mode.
STAT_DIAGMOD	Diagnosis mode (K-bus)	1 = yes.
STAT_ZV	Car locked	1 = locked.
STAT_ZS	Car double-locked	1 = deadlocked.
STAT_SER	Selective unlock	1 = only driver door unlocked.
STAT_WB	Hazard flash (crash/alarm acknowledge)	1 = active.
STAT_OA	Visual alarm	1 = lights flashing for alarm.
STAT_ES	Deadlock released	1 = yes.
STAT_QFFZ	Driver window confirmed closed	1 = yes.
STAT_QFBZ	Passenger window confirmed closed	1 = yes.
STAT_QFFHZ	Rear left window confirmed closed	1 = yes.
STAT_QFBHZ	Rear right window confirmed closed	1 = yes.
STAT_SOFTON	Interior light on/fading	1 = yes.
STAT_KB_FSHD	Sunroof manual control (K-bus)	1 = active.
STAT_KB_KOE	Comfort open (K-bus)	1 = active (hold key to open windows).
STAT_KB_KS	Comfort close (K-bus)	1 = active (hold key to close windows).
STAT_FB_BAT	Remote key battery low	1 = low.
STAT_FB_NR	Valid remote number	1 = key identified (for personalisation).
STAT_FB_SEND_L	Remote key number (low bit)	Which key last pressed unlock.
STAT_FB_SEND_H	Remote key number (high bit)	Which key last pressed unlock.
STAT_FB_VR	Remote lock button	1 = pressed.
STAT_FB_ER	Remote unlock button	1 = pressed.
STAT_FB_HK	Remote trunk button	1 = pressed.
STAT_KB_VKER	Convertible top lid unlocked	1 = yes.
STAT_SEND_L	Remote: key number (low bit)	Which remote is transmitting.
STAT_SEND_H	Remote: key number (high bit)	Which remote is transmitting.
STAT_FZVSIG	Remote: radio signal received	1 = yes.
STAT_FZVKEY	Remote: key signal received	1 = a remote key's signal was decoded.
STAT_TASTE1	Remote: button 1	1 = pressed.
STAT_TASTE2	Remote: button 2	1 = pressed.
STAT_TASTE3	Remote: button 3	1 = pressed.
STAT_FUINIT	Remote: key pairing possible	1 = ready to learn a remote.
STAT_LOBAT1	Remote 1 battery low	1 = low.
STAT_LOBAT2	Remote 2 battery low	1 = low.
STAT_LOBAT3	Remote 3 battery low	1 = low.
STAT_LOBAT4	Remote 4 battery low	1 = low.
STAT_FSIB	Remote: interior light command	1 = received.
STAT_FSAHK	Remote: trunk button	1 = pressed.
STAT_ZV1FS	Remote: unlock command	1 = received.
STAT_ZV0FS	Remote: lock command	1 = received.
STAT_EKSFT	Driver window anti-trap strip	0 = pressed, 1 = not pressed, 2 = open circuit.
STAT_EKSFT_TEXT	Driver window anti-trap strip	Pressed, not pressed or open circuit.
STAT_EKSBT	Passenger window anti-trap strip	0 = pressed, 1 = not pressed, 2 = open circuit.
STAT_EKSBT_TEXT	Passenger window anti-trap strip	Pressed, not pressed or open circuit.
STAT_EKSFH	Rear left window anti-trap strip	0 = pressed, 1 = not pressed, 2 = open circuit.
STAT_EKSFH_TEXT	Rear left window anti-trap strip	Pressed, not pressed or open circuit.
STAT_EKSBH	Rear right window anti-trap strip	0 = pressed, 1 = not pressed, 2 = open circuit.
STAT_EKSBH_TEXT	Rear right window anti-trap strip	Pressed, not pressed or open circuit.
STAT_V30E_WERT	Battery voltage (30E)	0–25.5 V.
STAT_V30P_WERT	Battery voltage (30 pull-up)	0–25.5 V.
STAT_IFFH_WERT	Rear left window motor current	Amps.
STAT_IFBH_WERT	Rear right window motor current	Amps.
STAT_IFFHMAX_WERT	Rear left window start current	Peak amps when starting.
STAT_IFBHMAX_WERT	Rear right window start current	Peak amps when starting.
STAT_IFHF_WERT	Driver window motor current	Amps; high = stiff window regulator.
STAT_IFHB_WERT	Passenger window motor current	Amps; high = stiff window regulator.
STAT_IFHFMAX_WERT	Driver window start current	Peak amps when starting.
STAT_IFHBMAX_WERT	Passenger window start current	Peak amps when starting.
STAT_SWINT_WERT	Wiper interval dial voltage	Volts.
STAT_I_ULQ_WERT	Output driver total current	Amps (internal driver chip).
STAT_KMH_WERT	Vehicle speed (K-bus)	km/h.
STAT_GKL_WERT	Speed band for wipers	0–5, used for speed-dependent wiping.
STAT_POTI_STUFE_WERT	Wiper interval setting	0–5.
STAT_EKSFT_WERT	Driver anti-trap strip signal	0–255 ratio.
STAT_EKSBT_WERT	Passenger anti-trap strip signal	0–255 ratio.
STAT_EKSFH_WERT	Rear left anti-trap strip signal	0–255 ratio.
STAT_EKSBH_WERT	Rear right anti-trap strip signal	0–255 ratio.
STAT_V_KL30_EKS_WERT	Anti-trap supply voltage	Volts.
STAT_V_VA1_WERT	Load shedding output voltage	Volts.
STAT_NR	Remote used to unlock	1–4 = which remote, 0 = unlocked by key/other.
STAT_NR_AKTUELL_CODE	Current remote code	Random code of the key being read.
STAT_NR_AKTUELL	Current remote number	1–4 = belongs to this car, 0 = not this car's key.
STAT_INIT_ANZ	Remotes paired	0–4.
STAT_NR_1	Stored remote 1 code	0–255.
STAT_NR_2	Stored remote 2 code	0–255.
STAT_NR_3	Stored remote 3 code	0–255.
STAT_NR_4	Stored remote 4 code	0–255.
ID_VAR_INDEX	Variant index	Selects the DSC software variant.
ID_DATUM_MONAT	Build month	Month the unit was made.
ID_DATUM_TAG	Build day	Day the unit was made.
ID_DATUM	Build date	DD.MM.YYYY.
ID_SW_NR_FSV	Function software number	DSC control software version.
ID_SW_NR_OSV	Operating system number	DSC OS version.
ID_SW_NR_MCV	Message catalogue number	CAN message set version.
ID_SW_NR_RES	Reserve software number	Not used.
F_VERSION	Fault memory type	2 = KWP2000.
F_SYMPTOM_NR	Fault symptom	Type of fault (number).
F_SYMPTOM_TEXT	Fault symptom	Type of fault, e.g. no signal, implausible.
F_READY_NR	Test complete	Readiness flag (number).
F_READY_TEXT	Test complete	Whether the check has run since faults were cleared.
F_VORHANDEN_NR	Present now	Number.
F_VORHANDEN_TEXT	Present now	Whether the fault is active right now or only stored.
F_WARNUNG_NR	Warning lamp	Number.
F_WARNUNG_TEXT	Warning lamp	Whether this fault turns on a warning lamp.
F_UW_KM	Mileage when stored	km.
STAT_RAD_GESCHW_VL_WERT	Wheel speed front left	km/h. All four should match when driving straight.
STAT_RAD_GESCHW_VR_WERT	Wheel speed front right	km/h. All four should match when driving straight.
STAT_RAD_GESCHW_HL_WERT	Wheel speed rear left	km/h. All four should match when driving straight.
STAT_RAD_GESCHW_HR_WERT	Wheel speed rear right	km/h. All four should match when driving straight.
STAT_BREMSLICHT_SCHALTER_EIN	Brake light switch	1 = brake pressed.
STAT_HANDBREMSE_SCHALTER_EIN	Handbrake switch	1 = handbrake on.
STAT_DSC_TASTER_EIN	DSC button	1 = pressed.
STAT_BREMSFLUESSIGKEIT_SCHALTER_EIN	Brake fluid level switch	1 = low fluid.
STAT_RPA_RESET_TASTER_EIN	Flat tyre warning reset button	1 = pressed.
STAT_RPA_EOL_PASSIV	Flat tyre warning disabled (factory)	1 = passive.
STAT_DREHRATENSENSOR_GESCHW_WERT	Yaw rate	°/s; about 0 when stationary.
STAT_QUERBESCHLEUNIGUNGSSENSOR_WERT	Lateral acceleration	g; about 0 when level and stationary.
STAT_DRUCKSENSOR_DRUCKSTANGENKREIS_DRUCK_WERT	Brake pressure (primary circuit)	bar; rises with pedal pressure.
STAT_DRUCKSENSOR_SCHWIMMKREIS_DRUCK_WERT	Brake pressure (secondary circuit)	bar; rises with pedal pressure.
STAT_SENSOR_TEMPERATUR_WERT	DSC unit temperature	°C inside the module.
STAT_SPANNUNG_UREF_WERT	Reference voltage	Volts (internal sensor reference).
STAT_SPANNUNG_PUMPE_WERT	Pump motor voltage	Volts.
STAT_SPANNUNG_KLEMME_30_WERT	Battery voltage	Volts at the DSC unit.
STAT_SPANNUNG_VCC_WERT	Internal supply voltage	Volts.
STAT_OFFSET_LENKWINKEL_WERT	Steering angle offset	Learned zero correction.
STAT_OFFSET_QUERBESCHLEUNIGUNG_WERT	Lateral acceleration offset	Learned zero correction.
STAT_OFFSET_DREHRATE_WERT	Yaw rate offset	Learned zero correction.
STAT_OFFSET_DRUCKSENSOR_1_WERT	Brake pressure sensor 1 offset	Learned zero correction.
STAT_OFFSET_DRUCKSENSOR_2_WERT	Brake pressure sensor 2 offset	Learned zero correction.
STAT_MD_IND_NE_WERT	Engine torque after DSC intervention	% of rated torque.
STAT_MD_IND_WERT	Engine torque	% of rated torque.
STAT_MD_REIB_WERT	Engine friction torque	% of rated torque.
STAT_LENKWINKEL_WERT	Steering angle	Degrees; 0 = straight ahead.
STAT_LENKWINKEL_GESCHW_WERT	Steering rate	°/s.
STAT_ID_LWS	Steering angle sensor ID	Which sensor is fitted.
STATUS_KM_RESET	Flat tyre warning: last reset	Mileage at the last reset.
STATUS_KM_WARNUNG	Flat tyre warning: last warning	Mileage at the last warning.
STATUS_KM_RESET_MINUS_1	Flat tyre warning: reset before last	Mileage.
STATUS_KM_WARNUNG_MINUS_1	Flat tyre warning: warning before last	Mileage.
STATUS_KM_RESET_MINUS_2	Flat tyre warning: third-last reset	Mileage.
STATUS_KM_WARNUNG_MINUS_2	Flat tyre warning: third-last warning	Mileage.
DRUCKSCHWELLE_GROB_15_70_KMH	Flat tyre threshold (coarse) 15–70 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_GROB_70_110_KMH	Flat tyre threshold (coarse) 70–110 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_GROB_110_150_KMH	Flat tyre threshold (coarse) 110–150 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_GROB_150_190_KMH	Flat tyre threshold (coarse) 150–190 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_GROB_190_220_KMH	Flat tyre threshold (coarse) 190–220 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_GROB_220_250_KMH	Flat tyre threshold (coarse) 220–250 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_FEIN_15_70_KMH	Flat tyre threshold (fine) 15–70 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_FEIN_70_110_KMH	Flat tyre threshold (fine) 70–110 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_FEIN_110_150_KMH	Flat tyre threshold (fine) 110–150 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_FEIN_150_190_KMH	Flat tyre threshold (fine) 150–190 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_FEIN_190_220_KMH	Flat tyre threshold (fine) 190–220 km/h	Learned wheel-speed threshold.
DRUCKSCHWELLE_FEIN_220_250_KMH	Flat tyre threshold (fine) 220–250 km/h	Learned wheel-speed threshold.
MOMENTENKOMPENSATION_1	Flat tyre: torque compensation 1	Learned correction.
MOMENTENKOMPENSATION_2	Flat tyre: torque compensation 2	Learned correction.
MOMENTENKOMPENSATION_3	Flat tyre: torque compensation 3	Learned correction.
MOMENTENKOMPENSATION_4	Flat tyre: torque compensation 4	Learned correction.
MOMENTENKOMPENSATION_5	Flat tyre: torque compensation 5	Learned correction.
MOMENTENKOMPENSATION_6	Flat tyre: torque compensation 6	Learned correction.
KURVENKOMPENSATION_RECHTS_50_PROZ	Flat tyre: right-curve compensation 50%	Learned correction.
KURVENKOMPENSATION_RECHTS_100_PROZ	Flat tyre: right-curve compensation 100%	Learned correction.
KURVENKOMPENSATION_LINKS_50_PROZ	Flat tyre: left-curve compensation 50%	Learned correction.
KURVENKOMPENSATION_LINKS_100_PROZ	Flat tyre: left-curve compensation 100%	Learned correction.
KURVENKOMPENSATION_V_INT_GLEICH_0_RE_HALB	Flat tyre: curve compensation (internal)	Learned correction.
KURVENKOMPENSATION_V_INT_GLEICH_0_RE	Flat tyre: curve compensation (internal)	Learned correction.
KURVENKOMPENSATION_V_INT_GLEICH_0_LI_HALB	Flat tyre: curve compensation (internal)	Learned correction.
KURVENKOMPENSATION_V_INT_GLEICH_0_LI	Flat tyre: curve compensation (internal)	Learned correction.
KURVENKOMPENSATION_V_INT_GROESSER_0_RE_HALB	Flat tyre: curve compensation (internal)	Learned correction.
KURVENKOMPENSATION_V_INT_GROESSER_0_RE	Flat tyre: curve compensation (internal)	Learned correction.
KURVENKOMPENSATION_V_INT_GROESSER_0_LI_HALB	Flat tyre: curve compensation (internal)	Learned correction.
KURVENKOMPENSATION_V_INT_GROESSER_0_LI	Flat tyre: curve compensation (internal)	Learned correction.
WARNUNG_AKTUELL	Flat tyre warning active	1 = warning on now.
LERNZAEHLERSTAND	Flat tyre learning progress	Learning counter after a reset.
STAT_LENKWINKEL_WERT_LI_MAX	Max steering angle left	Degrees (full lock).
STAT_LENKWINKEL_WERT_RE_MAX	Max steering angle right	Degrees (full lock).
STAT_LENKWINKEL_WERT_LI_MAX_SAR	Max steering angle left (test rig)	Degrees ÷ 10.
STAT_LENKWINKEL_WERT_RE_MAX_SAR	Max steering angle right (test rig)	Degrees ÷ 10.
COD_TIPPTASTEN_BETRIEB_EIN	One-touch seat buttons	On = a tap on a memory button moves the seat all the way.
COD_PERSONALISIERUNG_EIN	Key memory (personalisation)	On = seat position follows the remote key used to unlock.
COD_SITZ_VERFAHREN_NACH_TUER_AUF_EIN	Seat moves when door opens	On = memory recall/move allowed with the door open.
CODE	Raw coding bytes	The module's coding as hex.
LAENDERVARIANTE	Country variant	Market the module is coded for (e.g. ECE = Europe, US).
MOTORVARIANTE	Engine type	Petrol or diesel.
ZYLINDERZAHL	Cylinders	Number of cylinders coded.
LEERLAUFANHEBUNG_1	Idle boost 1	When the climate control asks the engine to raise idle.
LEERLAUFANHEBUNG_2	Idle boost 2	Second idle-boost condition.
AUSSTATTUNG_1	Equipment: air-quality sensor	AUC (automatic recirculation) coded or default.
AUSSTATTUNG_2	Equipment: auxiliary heater	Type of auxiliary heater coded.
AUSSTATTUNG_3	Equipment: sun sensor	Coded if fitted.
AUSSTATTUNG_4	Equipment: on-board monitor	Coded if the car has the navigation/monitor screen.
ALLGEMEIN_1	General setting 1	Default, or map-controlled engine cooling.
ALLGEMEIN_2	General setting 2	Shows "compressor transport lock" if the A/C compressor is locked out (factory transport mode).
COD_IHK_AUC	Air-quality sensor (AUC) coded	1 = yes.
COD_IHK_SOL	Sun sensor coded	1 = yes.
COD_IHK_ZHZ	Auxiliary heater coded	1 = yes.
KOMPRESSOR_SPERRE	A/C compressor disabled	1 = compressor locked out.
STAT_KOMBI_CODIERT	Cluster is coded	1 = coding present.
STAT_BC_FUNKTION_AKTIV	On-board computer enabled	1 = yes.
STAT_ATEMP_SENSOR_VERBAUT	Outside temp sensor fitted	1 = yes.
STAT_GONG_FUNKTION_AKTIV	Gong warnings	1 = warnings use the gong.
STAT_OPT_GURTWARNUNG_AKTIV	Seat belt reminder (continuous)	1 = warns as long as the belt is open.
STAT_ZUENDSCHLUESSELWARNUNG_AKTIV	Key-in-ignition warning	1 = warns when the door opens with the key in.
STAT_AKUSTIKWARNUNG_HANDBREMSE_AKTIV	Handbrake-on warning sound	1 = sounds when driving with the handbrake on.
COD_BL_LI_RE_KALTUEBERWACHUNG_EIN	Cold bulb check: brake lights	On = checks the bulbs even when they're off.
COD_SL_VORN_KALTUEBERWACHUNG_EIN	Cold bulb check: front parking lights	On = checks the bulbs even when they're off.
COD_SL_HINTEN_KALTUEBERWACHUNG_EIN	Cold bulb check: tail lights	On = checks the bulbs even when they're off.
COD_KZL_KALTUEBERWACHUNG_EIN	Cold bulb check: number plate light	On = checks the bulbs even when they're off.
COD_NSL_KALTUEBERWACHUNG_EIN	Cold bulb check: rear fog light	On = checks the bulb even when it's off.
COD_SL_HINTEN_FEHLERMELDUNG_EIN	Bulb warning: tail lights	On = cluster warns when a bulb fails.
COD_SL_VORN_FEHLERMELDUNG_EIN	Bulb warning: front parking lights	On = cluster warns when a bulb fails.
COD_AL_FEHLERMELDUNG_EIN	Bulb warning: low beams	On = cluster warns when a bulb fails.
COD_FL_FEHLERMELDUNG_EIN	Bulb warning: high beams	On = cluster warns when a bulb fails.
COD_BSZ_LOESCHUNG_BEI_LAMPENWECHSEL_EIN	Reset bulb hours on bulb change	On = operating-hours counter resets when a bulb is replaced.
COD_NSL_L_FEHLERMELDUNG_EIN	Bulb warning: rear fog left	On = cluster warns when the bulb fails.
COD_NSL_R_FEHLERMELDUNG_EIN	Bulb warning: rear fog right	On = cluster warns when the bulb fails.
COD_BL_FEHLERMELDUNG_EIN	Bulb warning: brake lights	On = cluster warns when a bulb fails.
COD_BL_MITTE_FEHLERMELDUNG_EIN	Bulb warning: centre brake light	On = cluster warns when it fails.
COD_KZL_FEHLERMELDUNG_EIN	Bulb warning: number plate light	On = cluster warns when it fails.
COD_ZYKLUSZEIT_STATUSTELEGRAMM_WIE_E38_E39_EIN	Status message timing like E38/E39	Internal bus timing option.
COD_ANHAENGERLICHT_FEHLERMELDUNG_EIN	Bulb warning: trailer lights	On = warns about trailer bulb failures.
COD_GEDIMMTE_BLINKER_FUER_STANDLICHT_EIN	Dimmed indicators as parking lights	On = if a parking bulb fails, the indicator glows dimly instead.
COD_BLS2_ABFRAGE_EIN	Second brake switch checked	On = the second brake light switch contact is monitored.
COD_BLS_FEHLERMELDUNG_EIN	Brake switch warning	On = warns about a brake light switch fault.
COD_BLS_B_SCHWELL_WERT	Brake switch check threshold	Deceleration (km/h per s) used to check the brake switch.
COD_T_WARTE_FEHLER_BLS_WERT	Brake switch warning delay	Seconds before a brake switch fault is reported.
COD_WERT_ABSCHALTUNG_STAND_PARKLICHT	Parking light cut-off voltage	Battery voltage at which the parking lights switch off.
COD_WARNBLINKEN_ENABLE	Hazard flashing enabled	1 = yes (e.g. on crash/alarm).
COD_AL_KALTUEBERWACHUNG_EIN	Cold bulb check: low beams	On = checks the bulbs even when they're off (turn off for HIDs).
COD_FL_KALTUEBERWACHUNG_EIN	Cold bulb check: high beams	On = checks the bulbs even when they're off.
COD_BLK_HINTEN_KALTUEBERWACHUNG_EIN	Cold bulb check: rear indicators	On = checks the bulbs even when they're off.
COD_BLK_VORN_KALTUEBERWACHUNG_EIN	Cold bulb check: front indicators	On = checks the bulbs even when they're off.
COD_PERIODENDAUER_KALTUEBERWACHUNG_WERT	Cold check interval	Seconds between cold bulb checks.
COD_ENTPRELLZAHL_FEHLERERKENNUNG	Bulb fault confirmation count	How many checks before a bulb is reported failed.
COD_TASTVERHAELTNIS_SPANNUNG_KLEMME58g_BEI_MIN_DIMMER	Dash lighting at minimum dimmer	Brightness with the dimmer wheel all the way down.
COD_TASTVERHAELTNISZUWACHS_KLEMME58g_BEI_MAX_DIMMER	Dash lighting increase to max dimmer	Brightness gain up to the top of the dimmer wheel.
COD_ABFRAGEZEIT_AHM_IN_LOW_POWER_MODE	Trailer module poll time (sleep)	ms.
COD_SCHWELLE_AENDERUNG_DIMMER_AN_K_BUS	Dimmer change threshold	How far the dimmer must move before it's sent on the bus.
COD_DAUER_FOLLOW_ME_HOME_SCHALTUNG	Follow-me-home duration	Seconds the headlights stay on after locking (pull the flash stalk after switching off).
COD_EINSCHALTZEIT_GEDIMMTE_BLK_VORN	Dimmed front indicator on-time	Brightness of indicators used as parking lights.
COD_EINSCHALTZEIT_GEDIMMTES_BREMSLICHT	Dimmed brake light on-time	Brightness of brake bulbs used as tail lights.
COD_PERIODENDAUER_DIMMUNG_BLK_BL	Indicator/brake dimming period	PWM period.
COD_EINSCHALTZEIT_GEDIMMTES_AL	Dimmed low beam on-time	Brightness of low beams when dimmed (daytime running lights).
COD_PERIODENDAUER_DIMMUNG_AL	Low beam dimming period	PWM period.
COD_MINIMALE_AUSTASTZEIT_FUER_SL	Minimum parking light off-time	PWM setting.
COD_LWR_AUTOMATISCH_CODIERT	Automatic headlight levelling	1 = coded (xenon cars).
CODIER_INDEX	Coding index	Coding data version.
CODIER_VARIANTE	Coding variant	Coding data variant.
GM	Central code: base model (GM)	Part of the car's central coding key.
SA	Central code: options (SA)	Factory options, as part of the central coding key.
VM	Central code: version (VN)	Market/version part of the central coding key.
VN	Central code: version (VN)	Market/version part of the central coding key.
C3	Central code C3	Version code without prefix.
AGM	Additional central code (GM)	Not used.
ASA	Additional central code (options)	Additional option codes.
AVN	Additional central code (market)	Additional market code.
FAHRZEUGAUFTRAG	Vehicle order	The car's build data: model, paint, upholstery and factory option codes.
SPEICHER_STATUS	Vehicle order stored	BELEGT = stored, UNBELEGT = empty.
FG_NR	VIN stored in module	Should match the car's VIN; a different VIN means a used/swapped module.
FG_PZ	VIN check digit	Check digit.
COD_DATEN	Raw coding data	Coding bytes.
COD_CHECK	Coding checksum	Checksum of the coding.
COD_CHECK_HIGH	Coding checksum (high byte)	Checksum.
COD_CHECK_LOW	Coding checksum (low byte)	Checksum.
"""#
}
