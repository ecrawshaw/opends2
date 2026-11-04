# Contributing to OpenDS2

Thanks for helping. The short version:

1. **Read [AGENTS.md](AGENTS.md).** It covers the layout, the safety rules and how to add a vehicle.
   (It's written for coding agents but it's the developer guide for humans too.)
2. **Run `./tools/check.sh` before every PR.** It must end with `failed: 0`.
3. **Keep PRs small and in one layer:** reading support, UI, coding decode, or a write path.
4. **Anything that can write to a car needs a maintainer and an on-car test plan**
   (see "When to stop and ask a maintainer" in AGENTS.md).
5. **No BMW files and no personal data:** no SGBDs, NCS data, real VINs, IPs or tokens in commits,
   issues or screenshots.

**Have a car other than an E46?** A [vehicle read-out](docs/VEHICLE-READOUT.md) is the most useful
contribution. It's read-only, and you don't need to write code.

By contributing you agree your contribution is licensed under GPLv3.
