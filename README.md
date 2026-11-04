# OpenDS2

**Open-source BMW diagnostics for the Mac.** Plug a K+DCAN cable into your E-series BMW, read and
clear fault codes, watch live data, and see how every module is coded, all in a native Mac app.

OpenDS2 is named after **DS2**, the diagnostic protocol BMW used over the K-line on E-series cars.
It runs on [EdiabasLib](https://github.com/uholeschak/ediabaslib), an open-source implementation of
BMW's EDIABAS.

> **Status: early.** It's developed and tested on an **E46** (2003 M3). Other E-series cars should
> work for reading, but haven't been tested yet. See [Supported cars](#supported-cars). If you
> have another chassis, a [read-out of your car](docs/VEHICLE-READOUT.md) is the most useful thing
> you can contribute.

---

## What it does

- **Scan** the car and list every module that answers
- **Faults:** read and clear fault memory, translated into English
- **Live values:** every sensor and status value a module reports, in metric or imperial
- **Info:** part numbers, software versions and coding index for each module
- **Coding:** see how each module is coded. With NCS data it decodes into named options
- **Actions:** the module's own tests and resets (service reset, activations, DSC bleed…)
- **History:** save a read and compare it with a later one
- **AI assistant (optional):** a local MCP server so Claude or another assistant can work on the car
  with you. Coding changes it suggests wait for your approval.

Changing coding is limited to a few modules that have been verified on a real car (see
[Safety](#safety)). Everything else is read-only.

## What you need

1. **A Mac** with macOS 14 (Sonoma) or newer, Apple Silicon or Intel.
2. **A K+DCAN USB cable** (the common "INPA K+DCAN" cable with an FTDI chip). Cars older than about
   2007 need the cable's switch set to the position that bridges **pins 7 and 8**.
3. **BMW's ECU description files** (the `Ecu` folder of `.prg` and `.grp` files). These are BMW's
   files, so OpenDS2 doesn't include them. They come with BMW Standard Tools / EDIABAS, usually in
   `C:\EDIABAS\Ecu`. Copy that folder to your Mac.
4. *Optional:* **NCS Expert coding data** (`DATEN` folder for your chassis, e.g. `DATEN\E46`). This
   is only needed to decode coding into named options.

## Install

1. Download **OpenDS2.zip** from the [latest release](https://github.com/ecrawshaw/opends2/releases/latest).
2. Unzip it and drag **OpenDS2.app** into **Applications**.
3. If macOS says it can't check the app for malware, open **Terminal** and run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/OpenDS2.app
   ```
   (The app shows this command too if macOS blocks it.)

The app checks for updates itself (**Setup → App updates**).

## Use it

1. **Connect:** plug the cable into the car's OBD port and your Mac. Ignition **on** (position 2,
   dash lit). The engine can be off.
2. **Open Setup** (first launch opens it for you):
   - **ECU description files:** pick your `Ecu` folder.
   - **Connection:** pick the cable's port (`cu.usbserial-…`). If the list is empty, your cable needs
     a driver.
   - **Modules:** *E-series (K-line)* for cars up to about 2007; *D-CAN / F-series* for E8x/E9x and later.
   - *Optional:* **Coding data:** pick your chassis's NCS `DATEN` folder.
3. **Scan.** The first full scan takes about a minute. After that, quick scans only check the modules
   your car has.
4. **Click a module** to see its faults, live values, info and coding.
   **Read all** reads every module and saves a report.

### Tips

- **Only one program can use the cable at a time.** Close INPA, ISTA and other apps first.
- Keep the battery healthy (a charger is ideal for long sessions). Low voltage causes odd errors.
- If a module doesn't answer, check the ignition and the cable switch, then **Scan** again.
- Units: **Setup → Units** switches between metric and imperial.

### Using it with Claude (optional)

Turn on **Setup → MCP server** and click **Copy** to get the `claude mcp add …` command. The assistant
can then do anything the app's buttons can: scan, read modules, explain faults, clear faults, run
tests and resets.

**Coding is different.** When the assistant wants to change a coding option, the app shows you the
change (option, old → new value, exact bytes) and waits. Nothing is written until you click
**Write to car**. Programming, the odometer and the immobilizer are off-limits to everyone, including
the assistant.

## Supported cars

| Chassis | Reading | Coding changes |
|---|---|---|
| **E46** (3 Series, 1998–2006) | ✅ tested (M3) | Body module (ZKE5/GM5) ✅ · DSC MK60 ✅ · Cluster VIN ⚠️ experimental, not working yet |
| E36, E38, E39, E53, E83, E85, E52 | should work, untested | read-only |
| E8x / E9x / E6x (D-CAN) | partial, untested | read-only |
| F / G series (ENET) | not yet | — |

Some screens are made for one engine: **Dashboard, Misfires, VANOS and Tests** are for the E46 M3's
S54 (MSS54) for now. Help adding other engines is welcome. See [AGENTS.md](AGENTS.md#adding-a-vehicle).

## Safety

**This software talks to a real car.** Reading is harmless. Writing is rare, narrow and guarded:

- A coding change is one option at a time, on a module verified on a real car. It needs the engine
  off and the battery ≥ 12 V. The app saves a backup first, then shows you the exact byte change to
  confirm, and reads it back afterwards to check it took.
- Programming/flashing, immobilizer and key data, and the odometer are **never** touched. There is
  no odometer function in this project.
- The **cluster VIN write** exists only to align a *swapped* instrument cluster with the car it's
  now in. It refuses unless the cluster's VIN differs from the car's own, and it only accepts the
  car's VIN. **It does not work yet** and is off by default. See
  [docs/CLUSTER-VIN-FIX.md](docs/CLUSTER-VIN-FIX.md).

Use at your own risk. There is no warranty (see [LICENSE](LICENSE)).

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`), Microsoft's
[.NET 10 SDK](https://dotnet.microsoft.com/download) installed to `~/.dotnet`, and EdiabasLib:

```sh
git clone https://github.com/ecrawshaw/opends2.git
cd opends2
git clone https://github.com/uholeschak/ediabaslib.git   # used as-is, not modified
./tools/check.sh    # offline checks, no car needed: must end with "failed: 0"
./build-app.sh      # → dist/OpenDS2.app and dist/OpenDS2.zip
```

To get started on the code, read **[AGENTS.md](AGENTS.md)**. It covers the layout, the safety rules
and how to add support for another chassis.

## Contributing

- **Have a car other than an E46?** Follow [docs/VEHICLE-READOUT.md](docs/VEHICLE-READOUT.md) (read-only)
  and open an issue. **Remove your VIN** before posting anything publicly.
- Bugs and ideas: open an issue with the module, what you clicked and the error text.
- Code: see [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPLv3. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). OpenDS2 is built on EdiabasLib by Ulrich
Holeschak (GPLv3).

*OpenDS2 is an independent project. It is not affiliated with, endorsed by or connected to
BMW AG. BMW and the names of BMW models are trademarks of BMW AG, used here only to say which cars
the software works with.*
