#!/bin/zsh
# Offline checks. No car or cable needed. Run after any change, before ./build-app.sh.
#   ./tools/check.sh
set -euo pipefail
cd "${0:A:h}/.."
OUT="${TMPDIR:-/tmp}/opends2-checks"; mkdir -p "$OUT"
SRC=App/Sources/OpenDS2

echo "1/4 App compiles (debug)…"
(cd App && swift build 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | grep -v Compiling | tail -20)

echo "2/4 Engine compiles…"
(cd Engine && "${DOTNET:-$HOME/.dotnet/dotnet}" build -c Debug -v q -nologo 2>&1 | grep -E "error|Build succeeded" | tail -10)

echo "3/4 Coding encoder: every body-module option x every value, against real E46 body-module bytes…"
swiftc -O -o "$OUT/encoder" "$SRC/NCSCoding.swift" tools/checks/encoder/main.swift 2>&1 | grep -v "^$" || true
# The encoder test needs BMW's NCS files (never in the repo). Point NCS_DATEN at an E46 DATEN folder;
# CLAUDE.local.md says where the maintainer's copy is. Without it, the test reports SKIPPED.
"$OUT/encoder" | tail -5

echo "4/4 Engine refusal and gating tests…"
python3 tools/checks/refusals/test_refusals.py
