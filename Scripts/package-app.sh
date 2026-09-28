#!/bin/bash
# Assemble KanataGUI.app from the SwiftPM release binary.
# Usage: VERSION=0.1.0 OUT=dist ./scripts/package-app.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.0.0-dev)}"
OUT="${OUT:-$ROOT/dist}"
APP="$OUT/KanataGUI.app"

swift build -c release --product KanataGUI --package-path "$ROOT"
BIN="$(swift build -c release --show-bin-path --package-path "$ROOT")/KanataGUI"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Scripts" "$APP/Contents/Resources/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
# Keep the Scripts <-> Resources sibling layout install.sh expects:
# SCRIPT_DIR=.../Resources/Scripts, REPO_ROOT=.../Resources.
# Only the runtime scripts ship (packaging helpers stay out of the bundle).
for f in install.sh switch-profile.sh uninstall.sh; do
  cp "$ROOT/Scripts/$f" "$APP/Contents/Resources/Scripts/"
done
cp "$ROOT"/Resources/* "$APP/Contents/Resources/Resources/" 2>/dev/null || true
sed -e "s/__VERSION__/$VERSION/g" "$ROOT/packaging/Info.plist" > "$APP/Contents/Info.plist"
# Ad-hoc seal so the bundle is self-consistent (still unsigned: no notarization).
codesign --force --deep --sign - "$APP"
echo "Built $APP ($VERSION)"
