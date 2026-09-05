#!/bin/bash
# Builds Setscry.app and the .dmg anyone can download and double-click.
#
#   ./Scripts/bundle.sh [expected version]
#
# The version comes from Sources/SetscryCore/SetscryVersion.swift. An argument,
# if given, is checked against it rather than used.
#
# The signature is ad-hoc: no Apple Developer account, no notarization. That is
# enough for the app to run, but not enough for Gatekeeper to let it open the
# first time without a nudge. See the install notes in the README.

set -euo pipefail
cd "$(dirname "$0")/.."

# One source of truth: the version lives in Swift so an unbundled build can
# report it too. Read here rather than passed in, so the plist cannot disagree
# with what the app itself prints.
VERSION="$(./Scripts/version.sh)"

# A tag argument is a check, not an input: a release cannot be cut from a
# working copy that was never bumped, and a manual workflow run cannot stamp a
# branch name into CFBundleShortVersionString.
if [ $# -gt 0 ] && [ "$1" != "$VERSION" ]; then
    echo "Tag says $1 but Sources/SetscryCore/SetscryVersion.swift says $VERSION." >&2
    exit 1
fi

APP="dist/Setscry.app"
DMG="dist/Setscry-$VERSION.dmg"
STAGE="dist/dmg"

if [ ! -f Assets/Setscry.icns ]; then
    echo "Assets/Setscry.icns is missing. Restore it from the repository before building." >&2
    exit 1
fi

ARM=".build/arm64-apple-macosx/release"
X86=".build/x86_64-apple-macosx/release"

# Universal, so the app opens on an Intel Mac instead of refusing to launch.
# Only the deterministic half works there: MLX has no Metal backend on x86_64,
# so search, clusters and the label check report themselves unavailable rather
# than working. Everything the scan finds is deterministic and works on both.
#
# One slice at a time, then lipo, rather than passing both --arch flags at once:
# that path switches SwiftPM to the Xcode build system, which cannot resolve
# mlx-swift's CudaBuild target and fails before compiling anything.
echo "Building (release, arm64)…"
swift build -c release --arch arm64
echo "Building (release, x86_64)…"
swift build -c release --arch x86_64

# MLX refuses to start without its compiled Metal kernels, and swift build never
# produces them. Idempotent, so re-running this script is cheap.
./Scripts/fetch-mlx-metallib.sh

# The weights go inside the app, so an installed copy never downloads anything.
# Fetched and converted once, then reused on later builds. Run from the native
# slice: converting the checkpoint needs MLX, which needs Metal.
MODEL="Build/CLIPModel"
if [ ! -f "$MODEL/model.safetensors" ]; then
    "$ARM/prepare-model" "$MODEL"
fi

# The kernels are Metal, so there is one copy and it comes from the arm64 slice.
# The Intel slice has nothing to load and never asks.
LIB="$ARM/mlx.metallib"
for F in "$ARM/Setscry" "$X86/Setscry" "$LIB"; do
    [ -f "$F" ] || { echo "Missing $F" >&2; exit 1; }
done
[ -f "$MODEL/model.safetensors" ] || { echo "No weights at $MODEL" >&2; exit 1; }

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

lipo -create -output "$APP/Contents/MacOS/Setscry" "$ARM/Setscry" "$X86/Setscry"
lipo -info "$APP/Contents/MacOS/Setscry" | sed 's/^/  /' 
# Stripping has to happen before signing; a signature over a binary that is
# then modified is invalid, and macOS kills the process rather than explaining.
strip -rSTx "$APP/Contents/MacOS/Setscry"

cp Assets/Setscry.icns "$APP/Contents/Resources/Setscry.icns"

# The kernels live in Resources, where a bundle's data belongs, but MLX finds
# them by asking dladdr where its own code is, which inside a bundle is
# Contents/MacOS. The symlink satisfies both without a second 125 MB copy.
# Without it the app passes MLXRuntime's availability check and then aborts from
# C++ the moment a model-backed view is opened.
cp "$LIB" "$APP/Contents/Resources/mlx.metallib"
ln -s ../Resources/mlx.metallib "$APP/Contents/MacOS/mlx.metallib"

cp -R "$MODEL" "$APP/Contents/Resources/CLIPModel"

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

echo "Packing ${DMG}…"
rm -f "$DMG"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# ditto rather than cp -R: it is the only copy that reproduces a bundle exactly,
# extended attributes and all, which is what a signature is verified against.
# cp -R makes no such guarantee, and a bundle whose signature no longer verifies
# is killed on launch rather than merely warned about.
ditto "$APP" "$STAGE/Setscry.app"

# The drag-to-install target, which is the whole convention a .dmg carries.
ln -s /Applications "$STAGE/Applications"

# hdiutil only, no styling: a background image and a set window position need a
# read-write image, AppleScript to place the icons, and a second conversion
# pass, none of which help anyone install this.
hdiutil create -volname "Setscry $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

codesign --force --sign - --timestamp=none "$DMG"

echo
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
echo "Packed $DMG ($(du -h "$DMG" | cut -f1))"
echo
echo "To install: open it and drag Setscry.app onto Applications."
echo "Downloaded copies are quarantined; the README explains how to open one."
