#!/bin/bash
# PortHawk one-command installer
#
# Why it exists: the app is ad-hoc signed (no Developer ID certificate, not
# notarized), so a browser-downloaded DMG carries a quarantine flag and
# Gatekeeper reports "damaged" or "unidentified developer". Files fetched with
# curl are never quarantined, so this installs and runs straight away.
#
# Usage: curl -fsSL https://volcanicll.github.io/PortHawk/install.sh | bash
#
# Downloads from releases/latest/download/<fixed name>, which avoids the
# anonymous GitHub API rate limit; every release publishes both versioned and
# unversioned copies.
set -euo pipefail

REPO="volcanicll/PortHawk"
APP="/Applications/PortHawk.app"

# Releases are built for Apple Silicon only; an Intel Mac would install a
# binary it cannot run, so stop with a clear message instead.
if [ "$(uname -m)" != "arm64" ]; then
  echo "!! PortHawk ships Apple Silicon (arm64) builds only."
  echo "   This Mac reports $(uname -m). Build from source instead:"
  echo "   git clone https://github.com/$REPO && cd PortHawk && ./build.sh"
  exit 1
fi

if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 13 ]; then
  echo "!! PortHawk requires macOS 13 or newer (this Mac runs $(sw_vers -productVersion))."
  exit 1
fi

URL="https://github.com/$REPO/releases/latest/download/PortHawk-arm64.dmg"

echo "==> Downloading the latest build from $URL"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fL --retry 3 -o "$TMP/PortHawk.dmg" "$URL"

echo "==> Mounting the image..."
# Resolve the exact volume path from this mount rather than globbing
# /Volumes/PortHawk*: a volume left over from an earlier install sorts first and
# would install the old version.
MOUNT=$(hdiutil attach "$TMP/PortHawk.dmg" -nobrowse | sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | tail -1)
if [ -z "$MOUNT" ] || [ ! -d "$MOUNT/PortHawk.app" ]; then
  echo "!! Mount failed. Open the DMG manually and drag PortHawk.app into Applications."
  exit 1
fi
echo "==> Mounted at $MOUNT"

echo "==> Installing to $APP ..."
rm -rf "$APP"
ditto "$MOUNT/PortHawk.app" "$APP"
hdiutil detach "$MOUNT" -quiet

# Belt and braces: drop any quarantine flag that might still be attached.
xattr -cr "$APP" 2>/dev/null || true

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  "$APP/Contents/Info.plist" 2>/dev/null || echo "?")

# A previously running copy keeps the old binary in memory; restart it so the
# user actually ends up on the new version.
if pgrep -f "PortHawk.app/Contents/MacOS/PortHawk" > /dev/null 2>&1; then
  echo "==> Stopping the running copy..."
  pkill -f "PortHawk.app/Contents/MacOS/PortHawk" || true
  sleep 1
fi

echo "==> Done. PortHawk $VERSION installed."
echo "==> Launch with: open $APP — the book icon appears in your menu bar."
