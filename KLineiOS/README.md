# KLine for iOS

iPhone/iPad app for the WiFi OBD adapter (../adapter-esp32), built on the KLine package (../KLine).

- **Car:** protocol detection (CAN, then K-line), VIN, check-engine light, stored/pending/permanent codes, readiness monitors, clear codes (with a confirmation)
- **Live:** every value the car supports, refreshed continuously; star favorites to update just those (much faster on K-line cars)
- **Adapter:** status, battery voltage, the networks it joins, sleep time

iPhones can't use USB cables, so the app only works through the WiFi adapter. It finds it at `obdadapter.local` (adapter and phone on the same WiFi), then `192.168.4.1` (phone on the adapter's own `OBD-Adapter` network).

## Build
    brew install xcodegen
    xcodegen                 # makes KLineiOS.xcodeproj from project.yml
    open KLineiOS.xcodeproj

To run on a phone: Xcode › Settings › Accounts › add your Apple ID, then pick your team under the target's Signing & Capabilities. A free Apple ID works; the app then expires after 7 days and needs re-running from Xcode.

## Testing without a car
On the Mac, `kline fake-adapter` (from ../KLine) simulates the adapter and a CAN + K-line car. In the simulator, set the adapter address on the Adapter tab to `127.0.0.1:2323:2333:2380`.

Debug builds take launch arguments that skip the tapping:
`-adapterAddress 127.0.0.1:2323:2333:2380 -autoConnect YES -tab live` (tabs: car, live, adapter).

## Not yet
- BMW E-series module screens (identify, live values, faults); these need definitions from recorded traffic first
- Code descriptions (only the category is shown, e.g. "Powertrain, generic, ignition and misfire")
- Joining the OBD-Adapter network from inside the app (needs a paid developer account's Hotspot capability)
