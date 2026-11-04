# Vehicle read-out: help add support for your car

This is a **read-only** snapshot of every module in your car. With it, a developer can add proper
support for your chassis: module names, engine screens, coding decode, and eventually coding changes.
**Nothing in this guide changes the car.**

You can do it yourself in the app, or have an AI assistant (Claude, over the app's MCP server) do it
for you by giving it this page.

## Ground rules

- **Read only.** Don't clear faults (they're useful data), don't reset anything, don't change coding.
- **Skip immobilizer secrets.** Never run `ISN_LESEN`, `SCHLUESSEL_*`, `SCHL_DATEN_LESEN`, `PASSWORT_LESEN`,
  `WECHSELCODE*`, or anything that returns key, ISN or rolling-code data. It isn't needed.
- **One program on the cable.** Close INPA, ISTA and other apps.
- **Ignition at position 2** (dash lit, engine off) for the whole read-out, which takes 10–20 minutes.
  A battery charger helps.
- MCP tools take **`sgbd`**, never `module`, e.g. `{"sgbd":"kombi46r"}`.
- If something fails, write down the error and move on. Don't retry in a loop or try other job names.

## Setup

- Setup → **ECU description files**: your `Ecu` folder.
- Setup → **Coding data** (if you have it): your chassis's NCS `DATEN` folder, e.g. `DATEN/E39`.
- Setup → **Connection**: K+DCAN cable. **Modules**: *E-series (K-line)* or *D-CAN*, to suit your car.
- Setup → **Record traffic** on (saves raw messages to `~/Desktop/OpenDS2 traffic/`).
- For the AI route: Setup → **MCP server** on, then **Copy** the `claude mcp add …` command.

## Steps

**In the app (no AI):** **Scan**, then **Read all**. Open each module's **Info** and **Coding** tabs
(press **Read coding**). Then send the report **Read all** saved on the Desktop and the
`OpenDS2 traffic` folder.

**With an AI assistant (more complete):** save every tool response as JSON.

1. `scan_modules`, then `list_modules` → `modules.json`
2. For **each** module (its `sgbd`):
   1. `read_module` → `read_module.json` (ident incl. `ID_COD_INDEX`, faults, values)
   2. `list_jobs` (no filter) → `jobs.json`
   3. if `C_FG_LESEN` exists: `run_job` `C_FG_LESEN` → `vin.json`
   4. each of `C_FA_LESEN`, `ZCS_LESEN`, `C_ZCS_LESEN`, `C_AZCS_LESEN` that exists → `fa_<JOB>.json`
   5. `read_coding` → `read_coding.json` (fine if it says there's no coding file)
   6. if `COD_LESEN` exists: `run_job` with `args` `"0"`, `"1"`, `"2"`… until it errors →
      `cod_lesen_<n>.json`. If `CODIERDATEN_LESEN` or `CODIERUNG_LESEN` takes no arguments, run it too.
   7. if `C_CI_LESEN` exists → `ci.json`
3. Don't run anything that isn't a read (`STATUS_*`, `*_LESEN`, `IDENT`).

## Package and share

```
readout-<chassis>-<engine>-<YYYY-MM-DD>/      e.g. readout-E39-M62-2026-11-04/
  NOTES.md        chassis, model year, engine, gearbox, market, options you know of, anything odd
  modules.json
  <sgbd>/         one folder per module: read_module.json, jobs.json, read_coding.json, …
  errors.md       every failed call: module, tool, arguments, error text
```

**Before sharing publicly, remove your VIN.** Replace it in `vin.json`, the `FG_NR` fields and the
ident data with `XX00000`. Then zip the folder and attach it to a GitHub issue titled
"Vehicle read-out: <chassis> <engine>".
