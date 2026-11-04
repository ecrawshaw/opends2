#!/bin/zsh
# Regenerates AppIcon.icns from make-icon.swift (needs only the Command Line Tools).
set -euo pipefail
cd "${0:A:h}"
tmp=$(mktemp -d)
swift make-icon.swift "$tmp/icon.png"
set=$tmp/AppIcon.iconset
mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/icon.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$tmp/icon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o AppIcon.icns
cp "$tmp/icon.png" AppIcon.png
rm -rf "$tmp"
echo "Wrote $PWD/AppIcon.icns"
