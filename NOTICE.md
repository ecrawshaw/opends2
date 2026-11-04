# Notices

**OpenDS2** is free software under the GNU General Public License v3 (see `LICENSE`).

## Third-party code

- **EdiabasLib** by Ulrich Holeschak, GPLv3: <https://github.com/uholeschak/ediabaslib>.
  The engine (`Engine/`) compiles EdiabasLib's sources unmodified. Because OpenDS2 links it,
  OpenDS2 is distributed under GPLv3 as well.
- NuGet packages used by the engine: Newtonsoft.Json (MIT), System.IO.Ports (MIT),
  BouncyCastle.Cryptography (MIT).

## BMW data

OpenDS2 includes **no BMW files**. ECU description files (SGBD `.prg`/`.grp`) and NCS coding data
belong to BMW AG. Users provide their own copies, and the app reads them from folders they choose.

## Trademarks

BMW, the BMW logo and BMW model designations are trademarks of BMW AG. OpenDS2 is an independent
project and is not affiliated with, endorsed by or sponsored by BMW AG. Model names are used only
to describe compatibility.
