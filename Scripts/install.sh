#!/bin/sh
# One-time privileged installer for kanata-gui-mac.
# Run as root (the app invokes it via osascript "with administrator
# privileges", so the admin password is asked exactly once):
#   sudo ./Scripts/install.sh [--kanata-version v1.10.1] [--driver-version v8.0.0]
set -eu

KANATA_VERSION="v1.10.1"
DRIVER_VERSION="v8.0.0"
while [ $# -gt 0 ]; do
  case "$1" in
    --kanata-version) KANATA_VERSION="$2"; shift 2;;
    --driver-version) DRIVER_VERSION="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then echo "must run as root" >&2; exit 1; fi
ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] && KARCH="arm64" || KARCH="x64"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"
APP_SUPPORT="$REAL_HOME/Library/Application Support/kanata-gui"
PROFILES="$APP_SUPPORT/profiles"
LIBEXEC="/usr/local/libexec/kanata-gui"
KANATA_BIN="/usr/local/bin/kanata"
PLIST_DST="/Library/LaunchDaemons/dev.kanata.gui.kanata.plist"

echo "==> kanata-gui-mac installer (kanata $KANATA_VERSION, driver $DRIVER_VERSION, arch $KARCH)"

# 1. kanata binary
if [ ! -x "$KANATA_BIN" ]; then
  echo "==> downloading kanata $KANATA_VERSION"
  TMP="$(mktemp -d)"
  URL="https://github.com/jtroo/kanata/releases/download/$KANATA_VERSION/kanata_macos_${KARCH}.zip"
  /usr/bin/curl -fL -o "$TMP/kanata.zip" "$URL"
  /usr/bin/unzip -o "$TMP/kanata.zip" -d "$TMP"
  BIN="$(find "$TMP" -maxdepth 2 -name 'kanata*' -type f | head -1)"
  chmod +x "$BIN"
  mv "$BIN" "$KANATA_BIN"
  rm -rf "$TMP"
else
  echo "==> kanata already at $KANATA_BIN"
fi
"$KANATA_BIN" --macos-request-permissions || true

# 2. Karabiner driver (standalone pkg; system-extension approval is manual)
if [ ! -d "/Applications/.Karabiner-VirtualHIDDevice-Manager.app" ]; then
  echo "==> downloading Karabiner-DriverKit-VirtualHIDDevice $DRIVER_VERSION"
  TMP="$(mktemp -d)"
  /usr/bin/curl -fL -o "$TMP/driver.pkg" \
    "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/$DRIVER_VERSION/Karabiner-DriverKit-VirtualHIDDevice-$DRIVER_VERSION.pkg"
  /usr/sbin/installer -pkg "$TMP/driver.pkg" -target /
  rm -rf "$TMP"
  echo "NOTE: approve the driver in System Settings > General > Login Items & Extensions > Driver Extensions."
else
  echo "==> Karabiner driver manager already installed"
fi
"/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager" forceActivate || true
# Persist the VHID daemon at boot (standalone-driver case; harmless if KE manages it)
if [ -f "$REPO_ROOT/cfg_samples_placeholder" ]; then :; fi
if [ ! -f /Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist ]; then
  if [ -f "$REPO_ROOT/Resources/karabiner-vhid-daemon.plist" ]; then
    cp "$REPO_ROOT/Resources/karabiner-vhid-daemon.plist" /Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist
    chown root:wheel /Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist
    /bin/launchctl bootstrap system /Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist || true
  fi
fi

# 3. App dirs + starter profile
sudo -u "$REAL_USER" mkdir -p "$PROFILES"
if [ -z "$(ls -A "$PROFILES" 2>/dev/null)" ]; then
  cp "$REPO_ROOT/Resources/sample.kbd" "$PROFILES/starter.kbd"
  chown "$REAL_USER" "$PROFILES/starter.kbd"
fi
FIRST_CFG="$(ls "$PROFILES"/*.kbd | head -1)"

# 4. Helper scripts + sudoers (passwordless control after this point)
mkdir -p "$LIBEXEC"
cp "$SCRIPT_DIR/switch-profile.sh" "$LIBEXEC/switch-profile.sh"
chmod 755 "$LIBEXEC/switch-profile.sh"
cp "$REPO_ROOT/Resources/kanata-gui.sudoers" /etc/sudoers.d/kanata-gui
chmod 0440 /etc/sudoers.d/kanata-gui
/usr/sbin/visudo -c -f /etc/sudoers.d/kanata-gui

# 5. LaunchDaemon running kanata as root at boot
mkdir -p /Library/Logs/Kanata
sed -e "s#__KANATA_BIN__#$KANATA_BIN#" \
    -e "s#__KANATA_CFG__#$FIRST_CFG#" \
    -e "s#__KANATA_PORT__#10000#" \
    "$REPO_ROOT/Resources/dev.kanata.gui.kanata.plist.template" > "$PLIST_DST"
chmod 644 "$PLIST_DST"
chown root:wheel "$PLIST_DST"
/bin/launchctl bootout "system/dev.kanata.gui.kanata" 2>/dev/null || true
/bin/launchctl bootstrap system "$PLIST_DST"

echo "==> requesting Accessibility + Input Monitoring prompts"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

echo "DONE. Next: approve driver extension, grant Input Monitoring + Accessibility to $KANATA_BIN, then use the menu-bar app to switch profiles."
