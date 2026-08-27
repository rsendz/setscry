#!/bin/bash
#
# Puts MLX's compiled Metal kernels where a SwiftPM build can find them.
#
# MLX cannot run at all, not even on the CPU, without `mlx.metallib`. Xcode
# builds compile it from MLX's .metal sources; `swift build` never invokes the
# Metal compiler, so a command-line build has no kernels and aborts the first
# time it touches MLX.
#
# The alternative is installing the Metal compiler itself (~700 MB, via
# `xcodebuild -downloadComponent MetalToolchain`). This is the smaller path: it
# fetches the kernels Apple already publishes, prebuilt, in the official
# `mlx-metal` wheel (~50 MB), pinned to the exact MLX version mlx-swift vendors
# so the kernels always match the C++ that calls them.
#
# Usage:  ./Scripts/fetch-mlx-metallib.sh
# Then:   swift run -c release Setscry

set -euo pipefail

cd "$(dirname "$0")/.."

CHECKOUT=".build/checkouts/mlx-swift"
if [ ! -d "$CHECKOUT" ]; then
    echo "Resolving package dependencies…"
    swift package resolve
fi

# The C++ version vendored by mlx-swift, e.g. MLX_VERSION "0.31.1".
MLX_VERSION=$(grep -o 'MLX_VERSION", to: "\\"[0-9.]*' "$CHECKOUT/Package.swift" \
    | grep -o '[0-9][0-9.]*' | head -1)

if [ -z "$MLX_VERSION" ]; then
    echo "error: could not determine the MLX version vendored by mlx-swift" >&2
    exit 1
fi

MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
ARCH=$(uname -m)
echo "MLX $MLX_VERSION · macOS $MACOS_MAJOR · $ARCH"

WHEEL_URL=$(curl -fsSL "https://pypi.org/pypi/mlx-metal/json" | python3 -c "
import json, sys
version = '$MLX_VERSION'
macos = int('$MACOS_MAJOR')
arch = '$ARCH'

releases = json.load(sys.stdin)['releases'].get(version, [])
candidates = []
for file in releases:
    name = file['filename']
    if arch not in name or 'macosx' not in name:
        continue
    # Wheels are tagged with the minimum macOS they support; take the highest
    # tag this machine can still run.
    for part in name.split('-'):
        if part.startswith('macosx_'):
            major = int(part.split('_')[1])
            if major <= macos:
                candidates.append((major, file['url']))

if not candidates:
    sys.exit('no matching mlx-metal wheel for MLX %s on macOS %d (%s)' % (version, macos, arch))
print(max(candidates)[1])
")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $(basename "$WHEEL_URL")…"
curl -fsSL -o "$WORK/wheel.zip" "$WHEEL_URL"
unzip -q "$WORK/wheel.zip" -d "$WORK/wheel"

LIB=$(find "$WORK/wheel" -name "mlx.metallib" | head -1)
if [ -z "$LIB" ]; then
    echo "error: the wheel contained no mlx.metallib" >&2
    exit 1
fi

# MLX looks for the kernels next to the binary that loads them, so every build
# configuration needs its own copy.
INSTALLED=0
for DIR in .build/*/debug .build/*/release; do
    [ -d "$DIR" ] || continue
    cp "$LIB" "$DIR/mlx.metallib"
    echo "  installed → $DIR/mlx.metallib"
    INSTALLED=$((INSTALLED + 1))

    # The test runner resolves "next to the binary" inside the bundle. Globbed
    # rather than named, so renaming the package never silently skips this.
    for BUNDLE in "$DIR"/*.xctest/Contents/MacOS; do
        [ -d "$BUNDLE" ] || continue
        cp "$LIB" "$BUNDLE/mlx.metallib"
        echo "  installed → $BUNDLE/mlx.metallib"
    done
done

if [ "$INSTALLED" -eq 0 ]; then
    echo
    echo "No build directory yet. Run 'swift build' first, then re-run this script."
    exit 1
fi

echo
echo "Done. Semantic search, clusters and label checks are now available."
