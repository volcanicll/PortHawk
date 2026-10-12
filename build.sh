#!/bin/bash
# Build PortHawk: compile -> assemble .app -> ad-hoc sign
set -euo pipefail
cd "$(dirname "$0")"

APP=build/PortHawk.app
MIN_MACOS=13.0
# Pin the deployment target explicitly. Without -target, swiftc uses the SDK's
# default (DefaultDeploymentTarget in SDKSettings.plist), which tracks the
# toolchain: a newer Xcode/CLT on CI silently raises the floor and the shipped
# binary refuses to launch on the macOS versions we advertise.
TARGET="$(uname -m)-apple-macos${MIN_MACOS}"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling with swiftc (target ${TARGET})..."
swiftc -O -swift-version 5 \
    -target "$TARGET" \
    -Xlinker -dead_strip \
    Sources/main.swift \
    Sources/Core/*.swift \
    Sources/UI/*.swift \
    -o "$APP/Contents/MacOS/PortHawk"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force -s - "$APP" 2>/dev/null || true

BIN="$APP/Contents/MacOS/PortHawk"
ACTUAL=$(otool -l "$BIN" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')
SIZE=$(du -sh "$APP" | cut -f1 | tr -d '\t')
echo "Done -> ${APP} (${SIZE}, minos ${ACTUAL})"
echo "Run: open ${APP}"

# Guard the advertised floor: fail loudly rather than shipping a binary that
# claims macOS 13 in Info.plist but requires a newer OS at load time.
if [ "$ACTUAL" != "$MIN_MACOS" ]; then
    echo "!! deployment target mismatch: built minos ${ACTUAL}, expected ${MIN_MACOS}" >&2
    exit 1
fi
