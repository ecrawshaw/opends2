#!/bin/zsh
# Builds a UNIVERSAL OpenDS2.app: the SwiftUI front end (arm64+x86_64) plus the EdiabasLib engine
# shipped once per architecture (opends2-engine-arm64 / -x64), because .NET can't emit a universal
# binary and `lipo` corrupts single-file bundles. The app picks the matching engine at runtime
# (see Engine.locate()).
#
# Output, in dist/:  OpenDS2.app, OpenDS2.zip, version.json  (attach the zip + json to a GitHub Release;
# the in-app updater reads releases/latest/download/version.json).
#
#   ./build-app.sh                 # version 0.1
#   VERSION=0.2.0 ./build-app.sh
set -euo pipefail
cd "${0:A:h}"

# EdiabasLib is not vendored: clone it next to the code (unmodified, GPLv3).
[[ -d ediabaslib/EdiabasLib ]] || { echo "Missing ediabaslib/. Run: git clone https://github.com/uholeschak/ediabaslib.git" >&2; exit 1 }

# Use Microsoft's .NET build, not Homebrew's: Homebrew's runtime links /opt/homebrew/opt/brotli, so the engine
# fails to load on any Mac without Homebrew brotli. Install with dotnet-install.sh --channel 10.0 --install-dir ~/.dotnet
DOTNET="${DOTNET:-$HOME/.dotnet/dotnet}"
[[ -x "$DOTNET" ]] || { echo "Missing $DOTNET (official .NET 10 SDK)" >&2; exit 1 }

# Monotonic build number (CFBundleVersion) so the in-app updater can tell newer from older.
BUILD="$(date +%Y%m%d%H%M)"
SHORT_VERSION="${VERSION:-0.1}"
REPO_URL="${REPO_URL:-https://github.com/ecrawshaw/opends2}"
DIST=dist
mkdir -p "$DIST"

# .NET engine, one single-file self-contained build per macOS architecture.
typeset -A RIDS=( osx-arm64 arm64 osx-x64 x64 )
for rid in ${(k)RIDS}; do
  arch=${RIDS[$rid]}
  echo "Publishing engine for $arch…"
  (cd Engine && rm -rf obj "bin/publish-$arch" && "$DOTNET" publish -c Release -r "$rid" --self-contained \
     -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none \
     -o "bin/publish-$arch" >/dev/null)
done

# Universal SwiftUI front end (arm64 + x86_64).
echo "Building universal app front end…"
(cd App && swift build -c release --arch arm64 --arch x86_64 >/dev/null)
SWIFT_BIN="$(cd App && swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="$DIST/OpenDS2.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SWIFT_BIN/OpenDS2"                         "$APP/Contents/MacOS/OpenDS2"
cp Engine/bin/publish-arm64/opends2-engine      "$APP/Contents/MacOS/opends2-engine-arm64"
cp Engine/bin/publish-x64/opends2-engine        "$APP/Contents/MacOS/opends2-engine-x64"
cp App/Icon/AppIcon.icns                        "$APP/Contents/Resources/AppIcon.icns"   # regenerate with App/Icon/make-icon.sh

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>OpenDS2</string>
  <key>CFBundleDisplayName</key><string>OpenDS2</string>
  <key>CFBundleIdentifier</key><string>io.github.ecrawshaw.opends2</string>
  <key>CFBundleExecutable</key><string>OpenDS2</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>GPLv3. Not affiliated with or endorsed by BMW AG.</string>
</dict></plist>
PLIST

# Sign nested code first, then the bundle (never the deprecated --deep). Use a real Developer ID
# if one is installed (then it can be notarized); otherwise fall back to ad-hoc.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/{print $2; exit}')"
SIGN="${IDENTITY:--}"
HARDENED=(); [[ -n "$IDENTITY" ]] && HARDENED=(--options runtime --timestamp)
for bin in opends2-engine-arm64 opends2-engine-x64; do
  codesign --force $HARDENED -s "$SIGN" "$APP/Contents/MacOS/$bin"
done
codesign --force $HARDENED -s "$SIGN" "$APP"

# Transfer-safe archive (preserves the signature and exec bits; a plain Finder zip can break them).
rm -f "$DIST/OpenDS2.zip"
ditto -c -k --keepParent "$APP" "$DIST/OpenDS2.zip"

# Manifest for the in-app updater.
cat > "$DIST/version.json" <<JSON
{ "build": $BUILD, "shortVersion": "$SHORT_VERSION", "url": "$REPO_URL/releases/latest/download/OpenDS2.zip", "notes": "" }
JSON

echo
echo "Built $PWD/$APP (version $SHORT_VERSION, build $BUILD)"
echo "Release assets: $DIST/OpenDS2.zip and $DIST/version.json"
file "$APP/Contents/MacOS/OpenDS2" | sed 's/^/  /'
if [[ -z "$IDENTITY" ]]; then
  cat <<NOTE

Signed ad-hoc (no Developer ID on this machine, so not notarized). After downloading and
unzipping, Gatekeeper blocks it until the user runs:

    xattr -dr com.apple.quarantine "/path/to/OpenDS2.app"

(The app also shows this exact command if its engine is blocked on launch.)
With a "Developer ID Application" identity installed, this script signs with it, and you can
notarize with: xcrun notarytool submit dist/OpenDS2.zip --keychain-profile <profile> --wait
NOTE
fi
