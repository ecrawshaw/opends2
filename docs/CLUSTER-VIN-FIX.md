# Aligning a swapped cluster's VIN (E46): experimental

> **Status: does not work yet.** The write has not yet taken effect on a real cluster. The feature
> is off by default, and this page documents how it's meant to work so it can be debugged. Don't
> use it on a car you depend on.

**What it's for.** A used instrument cluster from a donor car still reports the **donor's** chassis
number (FG_NR, the last 7 characters of the VIN). This feature changes the cluster's stored FG_NR so
it matches the car it's now in. It's the "align identity after a cluster replacement" repair, and
that's the only thing it does:

- The app reads the car's own VIN from the **body module or immobilizer** (modules that stay with the
  car) and **refuses** if the cluster already matches.
- The only new VIN it accepts is **the car's own**. You can't type in an arbitrary VIN.
- It's **human-only**. The AI/MCP tools can't run it.
- It never touches the odometer: there is no odometer function in OpenDS2.

Keep a record of the swap: donor VIN, car VIN, date and mileage on both.

## How the write works

- The FG_NR is in the cluster EEPROM at **word `0x3D`** (byte `0x7A`), stored as **2 ASCII letters +
  3 BCD digit bytes**: `AB12345` → `41 42 12 34 50`. The next byte (`0x7F`) is a different value and
  is written back exactly as read.
- The change is a **raw `07 03` EEPROM memory write**, not a coding job. The coding job `C_S_SCHREIBEN`
  masks the write, so FG_NR bytes written through it never take.
- A **checksum at `0x16E`** (XOR of bytes `0x5A–0xFF`) covers the FG_NR. The engine updates it with
  each write.
- A **second copy** of the FG_NR at byte `0x358` (checksum at `0x3CD`) is **not written yet**. That's
  one of the open questions, and may be why the write doesn't take.

## Procedure (for debugging, with a maintainer)

**Before you start:** ignition at position 2 with the engine off, a battery charger connected, nothing
else on the cable, and Setup → **Cluster VIN write** turned on. **Scan** first, so the app knows the
body module and immobilizer.

1. **Read.** In the cluster's Coding tab, **Read** shows the cluster's current VIN.
2. **Prove raw channel** (read-only). The app reads the FG_NR two ways, the read job and a raw memory
   telegram, and compares them. Green ✓ means the write path's framing is right. Orange ✗ means stop.
   The write itself runs this check again and refuses if it fails.
3. **Test (one byte).** Write one FG_NR digit, read it back, and restore it at once. Then check the
   cluster for a new checksum/EEPROM fault.
4. **Write VIN.** Enter the car's VIN (last 7) and a reason. The app checks it against the car, saves a
   backup to `~/Library/Application Support/OpenDS2/cluster-coding-backups/`, shows the exact byte
   change, waits 3 s, writes, and reads back.
5. **Restore** (if anything looks wrong): pick the backup from **Restore**. It writes the saved
   original bytes back.

Report what you saw (the exact messages, and the bytes before and after) in an issue. Remove the real VIN first.
