# WiFi OBD adapter (ESP32): K-line + CAN

A WiFi OBD-II adapter for the KLine package. It covers:
- **CAN** (ISO 15765-4): every US car from 2008 and most cars worldwide from ~2006
- **K-line** (ISO 9141-2, ISO 14230 KWP2000, BMW DS2/KWP2000*): most European and Asian cars ~1996–2008, and the BMW E-series modules

Not covered: J1850 PWM/VPW (Ford/GM ~1996–2007), CAN FD (some 2020+), Ethernet/DoIP.

The ESP32 is a bridge; all protocol handling (DS2, KWP, ISO-TP, OBD-II, protocol detection) lives in ../KLine.

## Parts
| Part | Notes |
|---|---|
| ESP32-C3 SuperMini (env `c3`) or classic ESP32 DevKit (env `esp32dev`) | |
| **L9637D** K-line transceiver (SO-8) + SOIC-8 to DIP adapter | Real ISO 9141 driver, no transmit timeout, so the 2-second 5-baud wake-up used by many 1996–2006 cars works. (LIN chips such as the TJA1021 cut off long transmissions and can't do it.) |
| 4-channel **BSS138 level shifter** board | The L9637D runs on 5 V and pulls its TX/RX pins up to 5 V; the ESP32 is 3.3 V |
| **SN65HVD230** CAN transceiver module (3.3 V) | **Remove its 120 Ω termination resistor** (usually marked 121 near the CANH/CANL pins); the car's bus is already terminated |
| 510 Ω resistor | K-line pull-up to battery (the tester supplies it) |
| 100 nF capacitor | L9637D VS decoupling |
| 100 kΩ + 15 kΩ | battery-voltage divider (keep the ~7.7:1 ratio if substituting, and tell the firmware) |
| 12 V -> 5 V buck module (MP1584, fixed 5 V), P6KE20A TVS diode, 1N5819 Schottky diode (both through-hole) | power, spike and reverse-polarity protection (P6KE20A clamps at 27.7 V, under the MP1584's 28 V limit) |
| OBD-II male pigtail | check the wire colours with a multimeter, they're often wrong |

## Wiring

### Power
OBD 16 (+12 V, always on) -> 1N5819 (stripe toward the circuit) = **VBAT**. P6KE20A from VBAT to ground (stripe to VBAT).
VBAT -> buck in; buck 5 V out -> ESP32 5V pin, L9637D VCC, level-shifter HV. ESP32 3.3 V -> level-shifter LV, SN65HVD230 3V3.
OBD 4 + 5 -> ground (everything shares it).

### K-line (L9637D)
| L9637D pin | Connect |
|---|---|
| 1 RX | level shifter HV1; LV1 -> ESP **K_RX** |
| 2 LI | not connected |
| 3 VCC | 5 V |
| 4 TX | level shifter HV2; LV2 -> ESP **K_TX** |
| 5 GND | ground |
| 6 K | OBD **7**, and **510 Ω up to VBAT**. Also link OBD 8 to OBD 7 for BMW E-series (some modules use pin 8; the USB cable's switch does the same). Leave 8 open for other makes. |
| 7 VS | VBAT, with 100 nF to ground |
| 8 LO | not connected |

### CAN (SN65HVD230 module)
| Module pin | Connect |
|---|---|
| 3V3 / GND | 3.3 V / ground |
| CTX (or TX/D) | ESP **CAN_TX** |
| CRX (or RX/R) | ESP **CAN_RX** |
| CANH | OBD **6** |
| CANL | OBD **14** |

### ESP32 pins
| Signal | C3 SuperMini | ESP32 DevKit |
|---|---|---|
| K_TX / K_RX | GPIO4 / GPIO5 | GPIO17 / GPIO16 |
| CAN_TX / CAN_RX | GPIO6 / GPIO7 | GPIO21 / GPIO22 |
| Battery sense (100 kΩ from VBAT, 15 kΩ to ground) | GPIO1 | GPIO34 |
| 5 V in | 5V | VIN |

Pin 16 is live with the car off, so the adapter sleeps when it isn't being used (see Power below).

## Build and flash
    pio run -e c3 -t upload        # or -e esp32dev

## Use
### Connecting
The adapter always runs its own network, `OBD-Adapter` (password `obdadapter`) at `192.168.4.1`. It also joins any saved network in range, where it shows up as `obdadapter.local`:

1. Join `OBD-Adapter` once and open `http://192.168.4.1`.
2. Add your home WiFi, and your phone's hotspot for use away from home (up to 4 networks). When it isn't connected, it rescans every 15 s and joins the strongest saved network in range. It doesn't rescan while an app is connected.
3. From then on, on home WiFi or the hotspot, use `obdadapter.local` instead of `192.168.4.1`. The phone and computer keep their internet.

The same settings over HTTP: `/wifi` (list), `/wifi?ssid=...&pass=...` (add), `/wifi?forget=...`, `/wifi?ap_pass=...` (change the adapter's own password; restarts).

### Reading a car
Ignition on, then:
- any car: `kline obd obdadapter.local` (protocol, VIN, check-engine light, codes, readiness), `kline obd obdadapter.local live`
- BMW E-series module: `kline ident obdadapter.local 12`

`http://obdadapter.local/status` shows battery voltage, K-line, CAN, WiFi and power state.

The CAN port speaks standard SLCAN, so python-can (`slcan` over `socket://obdadapter.local:3333`) and SavvyCAN work too.

### Power
It goes into deep sleep after **20 minutes with no app connected and the engine not running**. "Not running" means under 13.2 V, i.e. the alternator isn't charging. With the ignition on and the engine off, the voltage looks the same as a parked car, which is why it waits for idle time instead of going by voltage alone. If the battery is under 11.8 V, it sleeps after 2 idle minutes instead.

While asleep, it checks the voltage every 30 s and wakes when the engine starts. To wake it with the engine off, unplug it and plug it back in.

Change the settings at `http://obdadapter.local/power?sleep_min=20&run_volts=13.2&low_volts=11.8`; `sleep_min=0` turns sleep off. On USB power at the bench (no battery reading), it never sleeps.

Asleep, the ESP32 itself uses almost nothing, but the buck converter, CAN transceiver, level shifter and battery divider stay powered. The estimate is roughly 10–20 mA asleep vs ~80–100 mA awake (to be measured on the first build). For a car left parked for weeks, unplug it anyway.

Cars whose voltage stays low with the engine running (some hybrids and "smart" alternators) won't wake by themselves; replug the adapter.

## Protocol detection (done on the computer)
1. CAN: listen silently at 500k and 250k first, then send the standard "which PIDs do you support" request (11-bit, then 29-bit). Listening first means a wrong bitrate never disturbs a busy bus.
2. K-line: ISO 14230 fast init, then the 5-baud init (whose key bytes say ISO 9141-2 or ISO 14230).

## Not yet verified on a car
Everything is tested only against `kline fake-adapter`, which simulates the adapter and a CAN + K-line car. First live tests: `kline obd 192.168.4.1` on any 2008+ car (CAN), then on the E46 (K-line OBD and `kline ident`).
