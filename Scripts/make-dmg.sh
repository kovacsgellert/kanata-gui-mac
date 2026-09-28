#!/bin/bash
# Build a drag-to-Applications DMG from dist/KanataGUI.app.
# Usage: ./scripts/make-dmg.sh   (run package-app.sh first)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/dist}"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.0.0-dev)}"
APP="$OUT/KanataGUI.app"
STAGE="$OUT/dmg-stage"
DMG="$OUT/kanata-gui-$VERSION-macos-arm64.dmg"

test -d "$APP" || { echo "ERROR: $APP not found, run scripts/package-app.sh first" >&2; exit 1; }
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "KanataGUI" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Wrote $DMG"
