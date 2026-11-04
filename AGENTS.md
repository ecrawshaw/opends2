# OpenDS2: guide for contributors and coding agents

OpenDS2 is a native Mac app that diagnoses, and for a few verified modules codes, BMW E-series
cars over a K+DCAN USB cable. It was built on an E46 and is being opened up to more chassis.

**This software talks to a real car.** A bug in a write path can disable locks, lights or windows,
or worse. Read [Safety rules](#safety-rules) before changing anything.

Contents: [Stop and ask](#when-to-stop-and-ask-a-maintainer) · [Safety rules](#safety-rules) ·
[How it works](#how-it-works) · [Layout](#layout) · [Build and test](#build-and-test) ·
[Adding a vehicle](#adding-a-vehicle) · [Domain facts](#domain-facts-verified-on-an-e46) ·
[Code style](#code-style)

---

## When to stop and ask a maintainer

Do UI, text, translations, read-only features, docs, new chassis *reading* support and build
fixes yourself. **Stop and ask a maintainer (open a draft PR or issue) before you:**

- Touch any code that can write to a car:
  - in `Engine/Program.cs`: `CodeWrite`, `DscCodeWrite`, `ClusterVinWrite`, the raw-telegram helpers
    (`BuildMemTel`, `ClusterRawXfer`, `ClusterRawWriteWords`), `DeniedReason`, `BinaryArgJobs`
  - in the app: `CodingWrite.swift` and `ClusterCoding.swift`
  - in `MCPTools.swift`: `isReadOnly`, `codingJobReason`, `binaryArgJobs`, `runJob` and
    `requestCodingChange`, plus `NCSDaten.encode`
- Add a job to any allow-list, or a module family to `writableCodingFamilies`.
- Run anything on a car that isn't a read.
- Change byte-level assumptions about a coding buffer, a checksum or byte order.

If you're unsure whether something is read-only, treat it as a write.

## Safety rules

Never break these.

1. **Reads are free. Writes are rare, narrow and gated.** Each write is its own engine command with
   its own guards: `codewrite` (E46 body module `zke5`), `dsccodewrite` (DSC MK60) and `clustervin`
   (E46 cluster VIN, experimental, see rule 4). Every write requires `expect` == a fresh read and
   reads back afterwards. Never let the generic `job` command run a write, never add a write path
   without review, and never weaken a guard.
2. **The engine's refusal list applies to everyone.** `DeniedReason` in `Program.cs` refuses, for every
   client including the app's own buttons, anything that writes coding through the generic job
   path, the VIN, the vehicle order, checksums, the odometer (`GWSZ_*`), service dates or power
   mode. It also refuses programming/flashing/seed-key, immobilizer alignment, module reboots and
   `STEUERN_DIGITAL`.
3. **MCP (AI clients) has the same reach as the app's buttons, except for coding.**
   - `run_job` runs any job the engine accepts, directly: reads, clearing faults (it reads them
     first so nothing is lost), resets, `STEUERN_*` tests, system checks and calibrations.
   - Coding jobs (`C_*`, `*AUFTRAG*`, `COD*SCHREIBEN`) are refused by `codingJobReason`. The only way
     to change coding is `request_coding_change`. It runs the app's own coding flow (rule 5) and
     puts the confirm sheet in front of the user: same diff, 3 s delay, no default button. Then it
     waits. **Nothing is written without a human click.**
   - MCP never calls `codewrite`, `dsccodewrite`, `clustervin` or `clustercode` itself. The
     cluster VIN write is human-only, and so are restores from backup.
4. **Cluster VIN write: swap-only, experimental, not working yet.** It exists only to make a
   *swapped* cluster match the car it's in. The app reads the car's own VIN from the body module or
   immobilizer and refuses if the cluster already matches. The only value it accepts is the car's
   VIN. It's off by default (Setup toggle) and human-only. It has not yet taken effect on a real
   cluster (see `docs/CLUSTER-VIN-FIX.md`). **Do not widen it.** General cluster coding
   (`clustercode`) is a stub; leave it refusing. **Never run `C_CHECKSUM` on its own.**
5. **There is no odometer function, and there never will be.** No mileage write, offset or
   "alignment". `GWSZ_*` writes are refused by the engine, and `clustervin` refuses the odometer ring
   (word < 0x10). Don't add one.
6. **Every coding change** needs, in order:
   - a fresh read from the car
   - the value on the car equal to the value the user saw
   - engine off (DME rpm < 50) and battery ≥ 12.0 V
   - a JSON backup with the VIN, in `~/Library/Application Support/OpenDS2/coding-backups/`
   - a confirm dialog showing the byte diff, with a 3 s delay and no default button
   - a read-back afterwards
7. **Hex parsing is strict** in both the app (`hexBytes`) and the engine (`HexBytes`): it throws on
   any non-hex character or an odd number of digits. Never make it lenient. A lenient parser once
   turned "korrekt codiert" into the bytes `EC DE`.
8. **Never probe with a dangerous job.** Don't run a job just to see what happens.
9. **One program on the cable at a time.** The app owns the cable while it's running.
10. **BMW's files never go into the repo or the app.** The `Ecu` folder (SGBDs `.prg`/`.grp`) and NCS
    `DATEN` are the user's own copies, picked in Setup. Never commit, bundle or publish them.
    `.gitignore` covers the usual folder names (`ecu-src/`, `ncs-daten*/`, `downloads/`, `uploads/`).
11. **No personal data in the repo.** No real VINs, IPs, tokens or names. Use made-up examples
    (`AB12345`, `WBAXX00000XX12345`).

## How it works

```
 SwiftUI app (App/)  ── JSON lines over stdin/stdout ──>  .NET engine (Engine/)  ──>  EdiabasLib  ──>  K+DCAN cable  ──>  car
   UI, state, MCP server                                   safety refusals,             EDIABAS            (serial, K-line
   coding decode (NCS)                                     write commands               interpreter         or D-CAN)
```

- **SGBD:** BMW's per-module description file (`.prg`), for example `zke5` for the E46 body module
  or `mss54ds0` for the S54 DME. It defines *jobs* such as `FS_LESEN` (read faults) and
  `STATUS_UBATT`. EdiabasLib interprets them, and the user supplies the files. Modules are
  addressed by SGBD name everywhere.
- **Group files (`d_00xx.grp`)** map a diagnostic address to the right SGBD variant. The engine's
  `scan` tries each group (`Ds2Groups` for K-line E-series, `DcanGroups` for D-CAN/F-series) and
  reports which ones answer. **This is already chassis-independent.**
- **NCS coding data** (`DATEN/<chassis>/`): `.cNN` coding files describe each module's coding bytes,
  and `swtfswNN`/`swtpswNN` name the options and values. `NCSDaten` (`NCSCoding.swift`) parses them.
  The `NN` index differs per chassis (E46 = 06), and the app detects it from the folder.
- **History** saves each read as JSON under Application Support so two reads can be compared.
- **MCP server** (`MCPServer.swift`, `MCPTools.swift`) serves `127.0.0.1:47146/mcp` with a bearer
  token, when enabled in Setup.

## Layout

| Path | What |
|---|---|
| `Engine/Program.cs` | .NET 10 engine. JSON lines on stdin/stdout, wraps EdiabasLib. Commands: `ports`, `config`, `scan`, `read`, `jobs`, `job`, `poll`, `codewrite`, `dsccodewrite`, read-only `clusterread`/`clusterrawprobe`, gated `clustercode` (stub) and `clustervin`. All safety refusals (`DeniedReason`) live here as well as in the app. |
| `Engine/MacStubs.cs` | Stubs for EdiabasLib's Windows/Bluetooth parts. |
| `Engine/OpenDS2Engine.csproj` | Compiles EdiabasLib's sources from `../ediabaslib` (cloned separately, **unmodified**, GPLv3) into `opends2-engine`. |
| `App/` | SwiftPM SwiftUI app (macOS 14+), target `OpenDS2`. |
| `App/Sources/OpenDS2/Model.swift` | `Module` (names, address table) and `AppState`: all state, engine calls, coding read/decode helpers. |
| `…/Engine.swift` | Starts the engine process, talks JSON lines, picks the per-arch binary. |
| `…/Views.swift` | Main window, module list, tabs (`DetailTab`), Setup sheet, Coding tab. |
| `…/EngineViews.swift` | Module-specific screens and predicates (`isEngine`, `isDSCMK60`, `isCluster`), Dashboard/Misfires/VANOS/Tests, DSC bleed, ConfirmSheet. |
| `…/Live.swift` | Live-value polling (`LiveMonitor`). |
| `…/CodingWrite.swift` | Body-module and DSC coding change/restore flows (rule 6), preconditions. |
| `…/ClusterCoding.swift` | Cluster VIN (FG_NR) write: swap-only, experimental (rule 4). |
| `…/NCSCoding.swift` | `NCSDaten`: parses NCS `.cNN` and `swtfsw/swtpsw`, decodes and encodes. Pure, builds standalone. |
| `…/CodingEnglish.swift`, `CodingGlossary.swift` | English names for coding options and values. |
| `…/Translations.swift`, `ValueNames.swift` | English for job results, fault texts and units. |
| `…/Units.swift` | Metric ↔ imperial (`Measure`). |
| `…/History.swift` | Saved reads and their diff. |
| `…/MCPServer.swift`, `MCPTools.swift` | MCP server and tools (rule 3). |
| `…/Updater.swift` | In-app updater (GitHub Releases `version.json`). |
| `…/AppPaths.swift` | Application Support folder, plus one-time migration from the old "E46 Diagnostics" app. |
| `…/Snapshot.swift` | Headless screenshots (see Testing). |
| `build-app.sh` | Universal `dist/OpenDS2.app`, `dist/OpenDS2.zip` and `dist/version.json`. |
| `tools/check.sh` | Offline checks. Run before every commit. |
| `tools/checks/encoder/` | Exhaustive NCS encoder test against real E46 body-module bytes. |
| `tools/checks/refusals/` | Engine refusal tests and static MCP-policy checks. |
| `docs/` | `VEHICLE-READOUT.md` (read-only data collection for a new chassis), `CLUSTER-VIN-FIX.md`. |
| `KLine/`, `KLineiOS/`, `adapter-esp32/` | Side projects: our own DS2/K-line protocol stack in Swift, an iOS app, and an ESP32 Wi-Fi K-line/CAN adapter. They share no code with the main app. |

## Build and test

```sh
git clone https://github.com/uholeschak/ediabaslib.git   # next to the code; don't modify it
./tools/check.sh      # app + engine compile, encoder test, refusal + MCP-policy tests → must end "failed: 0"
./build-app.sh        # → dist/OpenDS2.app, dist/OpenDS2.zip, dist/version.json
```

- Use **Microsoft's .NET 10 SDK in `~/.dotnet`** (or set `DOTNET=`), never Homebrew's `dotnet`.
  Homebrew's runtime links Homebrew's brotli, and the engine then fails on other Macs.
- Only the Command Line Tools are needed, not Xcode. SwiftUI macros (`@Observable`, and `@State` in
  some contexts) aren't available. Keep view state in `AppState` as `@Published`. `@AppStorage`,
  `@ObservedObject` and `@EnvironmentObject` work.
- Swift top-level code only works in `main.swift`. That matters for test harnesses.

**Testing:**

- **Offline first.** `tools/check.sh` must pass. When you change `NCSDaten`, add a case to
  `tools/checks/encoder/main.swift`. `NCSCoding.swift` compiles standalone:
  `swiftc App/Sources/OpenDS2/NCSCoding.swift your/main.swift`.
- **Engine without a car:** pipe JSON lines into `Engine/bin/Debug/net10.0/opends2-engine`:
  `{"cmd":"config","ecuPath":"/path/to/Ecu","port":""}` then `{"cmd":"jobs","sgbd":"zke5"}`. To test a
  refusal, send a malformed `codewrite` or a denied `job` and check that it errors.
- **Screenshots without screen-recording permission:**
  `OPENDS2_SNAPSHOT=out.png OPENDS2_SNAPSHOT_SAMPLE=1 dist/OpenDS2.app/Contents/MacOS/OpenDS2`.
  `OPENDS2_SNAPSHOT_TAB=setup|dashboard|live|info|coding|faults|history|confirm|cluster|…` picks a screen.
- **On a car, over MCP:** tools take `sgbd`, not `module`. An empty sgbd silently runs on whichever
  SGBD was loaded last, which gives plausible but wrong data. Timeouts usually mean the car fell
  asleep: turn the ignition on.
- **Writes are tested only by a human, at the car, in the app.** Plan it first: one harmless
  option, a known expected byte, then restore.

---

## Adding a vehicle

Support comes in layers, and each one is a separate, reviewable PR. **Reading is low-risk and very
welcome. Writing needs on-car verification and a maintainer.**

### 0. Get a read-out of the car

Follow [`docs/VEHICLE-READOUT.md`](docs/VEHICLE-READOUT.md). It's read-only and collects every
module's ident, faults, job list and coding bytes. All the steps below work from that data. Keep
real VINs out of commits and issues.

### 1. Reading works: scanning, names, faults, live values

Usually this needs no engine changes, because scanning goes through group files.

1. **Scan with the right set.** K-line cars (E36/E38/E39/E46/E52/E53/E83/E85) use `ds2`. E8x/E9x/E6x
   use `dcan`. If a module the car has never shows up, check whether its group is in `Ds2Groups`
   (`Engine/Program.cs:26`, list near the bottom of the file) or `DcanGroups` (`Program.cs:250`).
   Some modules don't answer through their group and need a direct probe (`DirectProbes`,
   `Program.cs:232`).
2. **Readable module names:** add the SGBD prefix to `Module.sgbdNames` (`Model.swift:30`) and, if
   useful, the address to `Module.knownAddresses` (`Model.swift:50`). The longest prefix wins.
3. **English text:** fault and value texts come from the SGBD in German. Add translations to
   `Translations.swift` / `ValueNames.swift`. If you aren't sure of a translation, leave the German.
4. **Units:** make sure new units go through `Measure` (`Units.swift`).

### 2. Engine-specific screens (Dashboard, Misfires, VANOS, Tests)

These are currently S54-only: `Module.isEngine` is `hasPrefix("mss54")` (`EngineViews.swift:8`), and
`DetailTab.isEngineOnly` (`Views.swift:217`) hides them for other engines. To add an engine (for
example `ms43*` for the M54, `me9*`, `dde*`):

1. Find that DME's equivalent `STATUS_*` jobs in its `list_jobs` (rpm, coolant, trims per bank,
   roughness per cylinder, VANOS target/actual).
2. Move the hard-coded MSS54 job names in `EngineViews.swift` into a per-engine profile (a small
   struct keyed by SGBD prefix), and make `isEngine` true for any module that has a profile.
3. Update the MCP `instructions` in `MCPTools.swift` (it lists MSS54 jobs) so the assistant gets the
   right job names.
4. `checkCodingPreconditions` (`CodingWrite.swift:444`) finds the DME by `mss54` to read rpm and
   voltage. Generalize it to the same profile. **This touches a write path: ask a maintainer.**

### 3. Coding decode (read-only)

Point Setup → Coding data at the chassis's `DATEN/<chassis>` folder. The app detects the name-table
index (`swtfswNN`) and refuses a folder that mixes several. Check the decode against the car: run
`read_coding` and compare a few options against what you know (NCS Expert's `FSW_PSW.TRC`, or the
car's actual behaviour). If a module reads coding differently, for example a per-block buffer like
`C_C_LESEN` or an EEPROM like the E46 cluster, add a reader in `Model.swift` (`rawCoding`, `codingBlock`)
and a case to the encoder test.

### 4. Coding writes (maintainers, on-car only)

Write support exists for exactly three SGBDs, hard-coded in **both** the app and the engine:

| Write | App gate | Engine gate |
|---|---|---|
| E46 body (`zke5`, family `gm5`) | `writableCodingFamilies` (`CodingWrite.swift:9`) | `CodeWrite` (`Program.cs:447`) |
| DSC MK60 (`dsc_mk60`) | `isDSCMK60` (`EngineViews.swift:10`) | `DscCodeWrite` (`Program.cs:494`) |
| E46 cluster VIN (`kombi46r`) | `ClusterCoding.swift` | `ClusterVinWrite` (`Program.cs:703`) |

> ⚠️ `dsc_mk60` is the same SGBD on the E46, E85 and Mini R50. Its write is verified only on an E46.
> The first job for multi-chassis write support is a **chassis gate**: detect the chassis (NCS
> folder index / VIN / FA) and allow each write only on the chassis where it was verified.

To add a writable module:

1. Prove the read is right: the coding bytes read back the same every time, and they match the
   NCS decode.
2. Work out the write job's buffer layout from the SGBD (disassemble it if needed; never guess),
   how the module checksums itself, and what the "correctly coded" marker is.
3. Add a narrow engine command with the same guards as `CodeWrite`: one SGBD, exact block size,
   `expect` == fresh read, at most N changed bytes, read-back. Add refusal tests for each guard.
4. Add the app flow (backup, preconditions, diff, confirm, read-back, restore), modelled on
   `requestCodingChange`, and make `request_coding_change` in `MCPTools.swift` aware of it.
5. Verify at the car with a human: one harmless option, a known byte, write, read back, restore.
   Record it in the PR.

### What's still E46-specific (quick reference)

- Engine screens and the DME lookup: `mss54` (`EngineViews.swift:8`, `CodingWrite.swift:444`)
- DSC bleed and calibrations: `dsc_mk60`, `lws5_1b` (`EngineViews.swift`, `Model.swift` `CalibrationRoutine`)
- Binary-argument read jobs: `zke5/C_C_LESEN`, `kombi46r/C_S_LESEN` (`MCPTools.swift:83`, `Program.cs:368`), kept in step
- Cluster EEPROM layout (FG_NR word `0x3D`, checksum `0x16E`): `ClusterCoding.swift:39`, `Program.cs`
- Setup help text that mentions the E46 (`Views.swift`, Setup sheet)

---

## Domain facts (verified on an E46)

- **SGBD names:** `kombi46r` cluster · `zke5` body module (coding family `gm5`) · `dsc_mk60` ABS/DSC ·
  `mss54ds0` S54 DME · `ews3` immobilizer · `lsz` lights.
- **NCS files:** E46 files come from the **swtfsw06/swtpsw06** tables, not 01/02. Filename digits are
  hex: `kmbe46m3.c23` is coding index 0x23. The car's index must exactly match the file's declared
  index (record 0x01) before writing.
- **Multi-byte coding values are big-endian.** Raw bits aren't on/off: the PSW value names decide.
  For example, DSC `SPERRDIFFERENZREGELUNG` raw 1 means `nicht_aktiv`.
- **Body coding (`zke5`):** the `C_C_LESEN`/`C_C_AUFTRAG` buffer has `buf[0]=1`, the length
  little-endian at 0x0D–0x0E, `buf[0x12]` = block, and data from 0x15. Each block is 30 bytes:
  29 data bytes plus the `AA` "correctly coded" marker.
- **DSC MK60 coding:** a 15-byte block. Byte 0 is a checksum the module recomputes; bytes 1–14 are
  data (`COD_LESEN` / `COD_SCHREIBEN`).
- **Cluster EEPROM (`C_S_LESEN`):** word count at 0x0F–0x10. **`buf[0x11]` is the address low byte and
  `buf[0x12]` the high byte.** The EEPROM is 1024 bytes (words `0x000–0x1FF`), an M35080-class chip.
  The first 0x20 bytes are the odometer ring, which the cable never writes.
- **Cluster FG_NR (VIN):** bytes `0x7A–0x7E` (word `0x3D`) as `[2 ASCII][3 BCD]`, e.g. `AB12345` →
  `41 42 12 34 50`. Byte `0x7F` is a different value (the mileage offset) and is always preserved.
  There's a second copy at byte `0x358`. `C_FG_LESEN` reports the primary copy.
- **Cluster raw memory telegrams:** read `80 09 06 03 00 00 <wordHi> <wordLo> <count>`; write
  `80 LEN 07 03 00 <wordHi> <wordLo> <count> <data…>` with LEN = `9 + 2·count`. Pass the **payload
  only** to `EdInterfaceObd.TransmitData`, because the DS2 path appends the XOR checksum itself.
  An extra checksum slot makes the frame one byte too long, and the cluster ignores it.
  `C_S_SCHREIBEN` masks writes with a coding mask, so FG_NR bytes written through it never take.
- **Cluster checksums:** `CHECKSUM`@0x16E = `XOR(bytes 0x5A–0xFF)`, `CHECKSUM_2`@0x3CD =
  `XOR(bytes 0x300–0x3CC)`. Both are single-byte XOR folds, maintained incrementally as
  `new = old ^ old_bytes ^ new_bytes`.
- **EdiabasLib:** `ArgString` and `ArgBinary` share storage, so set exactly one of them; never both,
  and never `ArgBinaryStd`. Setting both once wiped every job's text arguments.

## Code style

- Match the surrounding code: short doc comments that say *why*, not what. English UI text in plain
  words. Keep the German BMW name as a caption or tooltip.
- User-facing strings go through `Translate` / `CodingEnglish`. Don't guess at translations of
  coding values; leave the German if you aren't sure.
- Show units with `Measure`; don't hard-code km or °C.
- Errors shown to the user say what happened and what to do next.
- No new dependencies. No network calls except the local MCP server and the updater.
