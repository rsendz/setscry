#!/bin/bash
# Builds Setscry.app and a zip anyone can download and double-click.
#
#   ./Scripts/make-app.sh [version]
#
# The signature is ad-hoc: no Apple Developer account, no notarization. That is
# enough for the app to run, but not enough for Gatekeeper to let it open the
# first time without a nudge — see the install notes in the README.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.1}"
APP="dist/Setscry.app"
ZIP="dist/Setscry-$VERSION.zip"

if [ ! -f Assets/Setscry.icns ]; then
    echo "Assets/Setscry.icns is missing. Restore it from the repository before building." >&2
    exit 1
fi

echo "Building (release, arm64)…"
swift build -c release

# MLX refuses to start without its compiled Metal kernels, and swift build never
# produces them. Idempotent, so re-running this script is cheap.
./Scripts/fetch-mlx-metallib.sh

BIN=".build/release/Setscry"
LIB=".build/release/mlx.metallib"
[ -f "$BIN" ] || { echo "No release binary at $BIN" >&2; exit 1; }
[ -f "$LIB" ] || { echo "No mlx.metallib at $LIB" >&2; exit 1; }

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Setscry"
# Stripping has to happen before signing; a signature over a binary that is
# then modified is invalid, and macOS kills the process rather than explaining.
strip -rSTx "$APP/Contents/MacOS/Setscry"

cp Assets/Setscry.icns "$APP/Contents/Resources/Setscry.icns"

# The kernels live in Resources, where a bundle's data belongs — but MLX finds
# them by asking dladdr where its own code is, which inside a bundle is
# Contents/MacOS. The symlink satisfies both without a second 125 MB copy.
# Without it the app passes MLXRuntime's availability check and then aborts from
# C++ the moment a model-backed view is opened.
cp "$LIB" "$APP/Contents/Resources/mlx.metallib"
ln -s ../Resources/mlx.metallib "$APP/Contents/MacOS/mlx.metallib"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.luisresendez.setscry</string>
    <key>CFBundleName</key><string>Setscry</string>
    <key>CFBundleDisplayName</key><string>Setscry</string>
    <key>CFBundleExecutable</key><string>Setscry</string>
    <key>CFBundleIconFile</key><string>Setscry</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Luis Resendez</string>

    <!-- Image folders usually live in exactly these places. Without a reason
         string macOS shows a bare permission prompt that reads like a warning. -->
    <key>NSDesktopFolderUsageDescription</key>
    <string>Setscry reads the folder of images you open.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Setscry reads the folder of images you open.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Setscry reads the folder of images you open.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Setscry reads the folder of images you open, including one on an external drive.</string>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc)…"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "Packing ${ZIP}…"
rm -f "$ZIP"
# ditto rather than zip: it keeps the symlink a symlink and the binary executable.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
echo "Packed $ZIP ($(du -h "$ZIP" | cut -f1))"
echo
echo "To install: unzip it and drag Setscry.app to /Applications."
echo "Downloaded copies are quarantined; the README explains how to open one."
