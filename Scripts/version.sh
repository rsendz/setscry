#!/bin/bash
# Prints Setscry's version, read from the one place it is written.
#
# Kept as a script rather than inlined into make-app.sh so a test can run it and
# assert it agrees with the Swift constant.

set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="Sources/SetscryCore/SetscryVersion.swift"
VERSION="$(sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' "$SOURCE")"

if [ -z "$VERSION" ]; then
    echo "No version found in $SOURCE." >&2
    exit 1
fi

echo "$VERSION"
