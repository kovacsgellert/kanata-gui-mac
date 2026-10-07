#!/bin/sh
# One-time privileged installer for kanata-gui-mac.
#
# Safe to re-run: an existing kanata binary is NEVER overwritten (TCC privacy
# grants are per-binary-path, so replacing it would silently break Input
# Monitoring / Accessibility), an installed Karabiner driver is left alone,
# existing profiles are kept, the sudoers drop-in is only replaced after a
# backup, and an existing daemon config (active profile) is preserved.
#
# Run as root (the app invokes it via osascript "with administrator
# privileges", so the admin password is asked exactly once):
#   sudo ./Scripts/install.sh [--kanata-version v1.12.0] [--driver-version v6.2.0] [--no-brew]
# kanata itself is installed via Homebrew when possible (exact pinned
# versions not covered by the brew formula fall back to GitHub releases).
set -eu

KANATA_VERSION="v1.12.0"
DRIVER_VERSION="v6.2.0"
USE_BREW=1
while [ $# -gt 0 ]; do
  case "$1" in
    --kanata-version) KANATA_VERSION="${2:?missing value for --kanata-version}"; shift 2;;
    --driver-version) DRIVER_VERSION="${2:?missing value for --driver-version}"; shift 2;;
    --no-brew) USE_BREW=0; shift;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then echo "must run as root" >&2; exit 1; fi

# The user who will own app files. osascript "with administrator privileges"
# runs as root WITHOUT SUDO_USER, so prefer the console owner.
CONSOLE_USER="$(stat -f %Su /dev/console 2>/dev/null || true)"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  # shellcheck disable=SC2154
  CONSOLE_USER="${SUDO_USER:-${USER:-root}}"
fi
CONSOLE_HOME="$(eval echo "~$CONSOLE_USER")"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) KARCH="arm64"; KFILE_ARCH="arm64";;
  *) KARCH="x64"; KFILE_ARCH="x64";;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SUPPORT="$CONSOLE_HOME/Library/Application Support/kanata-gui"
PROFILES="$APP_SUPPORT/profiles"
LIBEXEC="/usr/local/libexec/kanata-gui"
KANATA_BIN="/usr/local/bin/kanata"
LABEL="dev.kanata.gui.kanata"
PLIST_DST="/Library/LaunchDaemons/$LABEL.plist"
SUDOERS_SRC="$REPO_ROOT/Resources/kanata-gui.sudoers"
SUDOERS_DST="/etc/sudoers.d/kanata-gui"
VHID_MANAGER="/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
VHID_EXT="org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
VHID_DAEMON_APP="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app"
VHID_PLIST="/Library/LaunchDaemons/org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist"
KE_APP="/Applications/Karabiner-Elements.app"
KE_VHID_SERVICE="system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

split_ver() { # "v1.12.0" -> "1 12 0"
  v="${1#v}"; v="${v#V}"
  major="${v%%.*}"; rest="${v#*.}"
  minor="${rest%%.*}"; patch="${rest#*.}"; patch="${patch%%[^0-9]*}"
  echo "${major:-0} ${minor:-0} ${patch:-0}"
}

echo "==> kanata-gui-mac installer (kanata $KANATA_VERSION, driver $DRIVER_VERSION, arch $KARCH, user $CONSOLE_USER)"

# 0. Sanity-check the kanata/driver version pairing. kanata >= 1.13 speaks
# driver protocol 7 (driver >= v8); older kanata needs the v6 driver.
# A mismatch installs cleanly but kanata can never connect -> fail fast.
# shellcheck disable=SC2046
set -- $(split_ver "$KANATA_VERSION"); KMAJ="$1"; KMIN="$2"
# shellcheck disable=SC2046
set -- $(split_ver "$DRIVER_VERSION"); DMAJ="$1"
if [ "$KMAJ" -gt 1 ] || { [ "$KMAJ" -eq 1 ] && [ "$KMIN" -ge 13 ]; }; then
  NEED_MAJOR=8
else
  NEED_MAJOR=6
fi
if [ "$DMAJ" -ne "$NEED_MAJOR" ]; then
  echo "ERROR: kanata $KANATA_VERSION requires Karabiner driver v${NEED_MAJOR}.x," >&2
  echo "but driver $DRIVER_VERSION was requested. Pass a matching pair, e.g." >&2
  echo "  --kanata-version v1.12.0 --driver-version v6.2.0" >&2
  exit 1
fi

# Version of an already-installed driver, from its daemon bundle (present for
# both the standalone pkg and Karabiner-Elements), else the pkg receipt.
# Empty when no driver is installed.
installed_driver_version() {
  v=""
  # PlistBuddy prints "File Doesn't Exist" on stdout, so only ask when it exists.
  if [ -f "$VHID_DAEMON_APP/Contents/Info.plist" ]; then
    v="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
      "$VHID_DAEMON_APP/Contents/Info.plist" 2>/dev/null || true)"
  fi
  if [ -z "$v" ]; then
    v="$(/usr/sbin/pkgutil --pkg-info "$VHID_EXT" 2>/dev/null | sed -n 's/^version: //p')"
  fi
  echo "$v"
}

# The same check against an already-installed driver. Karabiner-Elements
# bundles its own (currently v8) driver, so an existing KE install is the
# usual source of a mismatch: setup "succeeds" but kanata only logs
# "connect_failed asio.system:2" forever. Abort before changing anything.
HAVE_DRIVER="$(installed_driver_version)"
if [ -n "$HAVE_DRIVER" ]; then
  # shellcheck disable=SC2046
  set -- $(split_ver "$HAVE_DRIVER")
  if [ "$1" -ne "$NEED_MAJOR" ]; then
    echo "ERROR: Karabiner driver v$HAVE_DRIVER is installed, but kanata $KANATA_VERSION" >&2
    echo "requires driver v${NEED_MAJOR}.x; kanata would never connect to it." >&2
    if [ -d "$KE_APP" ]; then
      echo "That driver ships with Karabiner-Elements, which also grabs the keyboard" >&2
      echo "itself and conflicts with kanata. Uninstall it, reboot, then re-run:" >&2
      echo "  brew uninstall --cask karabiner-elements" >&2
    else
      echo "Deactivate it, reboot, then re-run this installer:" >&2
      echo "  sudo '$VHID_MANAGER/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager' deactivate" >&2
    fi
    exit 1
  fi
fi

find_existing_kanata() {
  for c in "$KANATA_BIN" /opt/homebrew/bin/kanata "$CONSOLE_HOME/bin/kanata"; do
    if [ -x "$c" ]; then echo "$c"; return 0; fi
  done
  p="$(sudo -u "$CONSOLE_USER" sh -c 'command -v kanata' 2>/dev/null || true)"
  if [ -n "$p" ] && [ -x "$p" ]; then echo "$p"; return 0; fi
  return 1
}

# Locate Homebrew. Never run brew as root -- it refuses and would create
# root-owned Cellar files. All brew invocations go through the console user.
find_brew() {
  for c in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$c" ]; then echo "$c"; return 0; fi
  done
  p="$(sudo -u "$CONSOLE_USER" sh -c 'command -v brew' 2>/dev/null || true)"
  if [ -n "$p" ] && [ -x "$p" ]; then echo "$p"; return 0; fi
  return 1
}

ensure_homebrew() {
  if BREW="$(find_brew)"; then
    echo "==> using Homebrew at $BREW ($(sudo -u "$CONSOLE_USER" "$BREW" --version 2>/dev/null | head -1 || echo unknown))"
    return 0
  fi
  echo "==> Homebrew not found, installing it as $CONSOLE_USER…"
  # Official installer, run as the console user (it refuses root).
  if sudo -u "$CONSOLE_USER" env HOME="$CONSOLE_HOME" \
      /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    if BREW="$(find_brew)"; then
      echo "==> Homebrew installed at $BREW"
      return 0
    fi
  fi
  echo "WARNING: Homebrew install failed; falling back to direct downloads." >&2
  return 1
}

# Does "kanata --version" report the requested version? "v1.12.0" matches
# "kanata 1.12.0".
kanata_version_matches() {
  want="${KANATA_VERSION#v}"; want="${want#V}"
  have="$("$1" --version 2>/dev/null | head -1 || true)"
  case "$have" in *"$want"*) return 0;; *) return 1;; esac
}

# Install kanata via Homebrew (as the console user). Returns 0 with the
# binary path on stdout when the installed version satisfies KANATA_VERSION.
brew_install_kanata() {
  if ! BREW="$(find_brew)"; then return 1; fi
  echo "==> installing kanata $KANATA_VERSION via Homebrew…"
  # NOTE: brew upgrades replace the Cellar binary, which invalidates its
  # Input Monitoring / Accessibility grants (TCC is per-binary-path).
  # After `brew upgrade kanata`, re-grant in System Settings.
  if ! sudo -u "$CONSOLE_USER" env HOME="$CONSOLE_HOME" "$BREW" install kanata; then
    echo "    (brew install failed, will try direct download…)"
    return 1
  fi
  if BIN="$(find_existing_kanata)" && kanata_version_matches "$BIN"; then
    echo "$BIN"
    return 0
  fi
  echo "    (brew provided $(BIN="$(find_existing_kanata)"; "$BIN" --version 2>/dev/null || echo unknown), want $KANATA_VERSION -- falling back to direct download…)"
  return 1
}

download_kanata_release() {
  echo "==> downloading kanata $KANATA_VERSION"
  # Asset names changed across releases; try the current scheme, then the old one.
  NEW_URL="https://github.com/jtroo/kanata/releases/download/$KANATA_VERSION/macos-binaries-${KARCH}.zip"
  OLD_URL="https://github.com/jtroo/kanata/releases/download/$KANATA_VERSION/kanata-macos-binaries-${KARCH}-${KANATA_VERSION}.zip"
  if ! /usr/bin/curl -fL --max-time 120 -o "$WORK/kanata.zip" "$NEW_URL"; then
    echo "    (new asset name not found, trying legacy name…)"
    /usr/bin/curl -fL --max-time 120 -o "$WORK/kanata.zip" "$OLD_URL"
  fi
  /usr/bin/unzip -o "$WORK/kanata.zip" -d "$WORK/kb"
  # Prefer the exact non-cmd variant (matches kanata's own docs); the zips
  # also contain a cmd_allowed sibling which we must NOT pick by accident.
  if [ -f "$WORK/kb/kanata_macos_${KFILE_ARCH}" ]; then
    BIN="$WORK/kb/kanata_macos_${KFILE_ARCH}"
  else
    BIN="$(find "$WORK/kb" -maxdepth 2 -type f -name 'kanata_macos*' ! -name '*cmd_allowed*' | head -1)"
  fi
  if [ -z "${BIN:-}" ] || [ ! -f "$BIN" ]; then
    echo "ERROR: no kanata binary found in $KANATA_VERSION asset" >&2; exit 1
  fi
  chmod +x "$BIN"
  mv "$BIN" "$KANATA_BIN"
  echo "==> installed $KANATA_BIN"
}

# 1. kanata binary -- never overwrite an existing one.
if EXISTING="$(find_existing_kanata)"; then
  KANATA_BIN="$EXISTING"
  echo "==> keeping existing kanata at $KANATA_BIN"
  echo "    ($("$KANATA_BIN" --version 2>/dev/null || echo "version unknown"))"
  echo "    (replacing it would invalidate its Input Monitoring / Accessibility grants)"
else
  INSTALLED=""
  if [ "$USE_BREW" -eq 1 ] && ensure_homebrew; then
    INSTALLED="$(brew_install_kanata || true)"
  fi
  if [ -n "$INSTALLED" ]; then
    KANATA_BIN="$INSTALLED"
    echo "==> using Homebrew kanata at $KANATA_BIN"
    echo "    ($("$KANATA_BIN" --version 2>/dev/null || echo "version unknown"))"
  else
    download_kanata_release
  fi
fi
"$KANATA_BIN" --macos-request-permissions || true

# 2. Karabiner driver -- never reinstall when a driver provider is present
# (its version was already checked against kanata in step 0).
# There is no Homebrew formula for the standalone
# Karabiner-DriverKit-VirtualHIDDevice pkg, so it is fetched from GitHub
# releases below; but an existing Karabiner-Elements install (app or brew
# cask, which bundles and manages the same driver) also satisfies this.
has_driver_provider() {
  if [ -d "$VHID_MANAGER" ] || [ -d "$KE_APP" ]; then
    return 0
  fi
  if BREW_CASK="$(find_brew)" \
    && sudo -u "$CONSOLE_USER" env HOME="$CONSOLE_HOME" "$BREW_CASK" list --cask karabiner-elements >/dev/null 2>&1; then
    return 0
  fi
  return 1
}
if [ -n "$HAVE_DRIVER" ]; then
  echo "==> keeping existing Karabiner driver v$HAVE_DRIVER (matches kanata $KANATA_VERSION)"
elif has_driver_provider; then
  echo "==> keeping existing Karabiner driver (standalone manager or Karabiner-Elements present; not touching it)"
  echo "    (version unknown; ensure it is v${NEED_MAJOR}.x to match kanata $KANATA_VERSION)"
else
  echo "==> downloading Karabiner-DriverKit-VirtualHIDDevice $DRIVER_VERSION"
  # Release tags carry a "v" prefix, the pkg file names do not.
  /usr/bin/curl -fL --max-time 180 -o "$WORK/driver.pkg" \
    "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/$DRIVER_VERSION/Karabiner-DriverKit-VirtualHIDDevice-${DRIVER_VERSION#v}.pkg"
  /usr/sbin/installer -pkg "$WORK/driver.pkg" -target /
  echo "NOTE: approve the driver in System Settings > General > Login Items & Extensions > Driver Extensions."
fi
if [ -d "$KE_APP" ]; then
  echo "WARNING: Karabiner-Elements is installed. Its Karabiner-Core-Service grabs the" >&2
  echo "keyboard too and conflicts with kanata; quit or uninstall it before turning kanata On." >&2
fi
if command -v systemextensionsctl >/dev/null 2>&1 \
  && systemextensionsctl list 2>/dev/null | grep -q "$VHID_EXT.*activated.*enabled"; then
  echo "==> driver system extension already activated, skipping forceActivate"
elif [ -x "$VHID_MANAGER/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager" ]; then
  "$VHID_MANAGER/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager" forceActivate || true
else
  echo "==> standalone VHID manager absent (Karabiner-Elements manages the driver); skipping forceActivate"
fi
# Persist the VHID daemon at boot (standalone-driver case only). When
# Karabiner-Elements already runs the daemon, a second copy would fight it
# over the same socket, so skip ours and remove one a previous run left
# behind (only if it is unmodified). Never overwrite an existing plist.
if [ -d "$KE_APP" ] || /bin/launchctl print "$KE_VHID_SERVICE" >/dev/null 2>&1; then
  if [ -f "$VHID_PLIST" ] && cmp -s "$REPO_ROOT/Resources/karabiner-vhid-daemon.plist" "$VHID_PLIST"; then
    /bin/launchctl bootout "system/org.pqrs.Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
    rm -f "$VHID_PLIST"
    echo "==> removed duplicate VHID daemon plist (Karabiner-Elements runs the daemon)"
  else
    echo "==> Karabiner-Elements runs the VHID daemon, not installing our own"
  fi
elif [ ! -f "$VHID_PLIST" ]; then
  if [ -f "$REPO_ROOT/Resources/karabiner-vhid-daemon.plist" ]; then
    cp -X "$REPO_ROOT/Resources/karabiner-vhid-daemon.plist" "$VHID_PLIST"
    chown root:wheel "$VHID_PLIST"
    /bin/launchctl bootstrap system "$VHID_PLIST" || true
  fi
else
  echo "==> VHID daemon plist already installed, leaving it alone"
  # Older installers cp'd it with the app bundle's quarantine xattr, which
  # makes launchd refuse it ("error = 155"); clearing it is always safe.
  xattr -d com.apple.quarantine "$VHID_PLIST" 2>/dev/null || true
fi

# 3. App dirs + starter profile (only when the user has no .kbd anywhere yet).
sudo -u "$CONSOLE_USER" mkdir -p "$PROFILES"
has_kbd() { for f in "$PROFILES"/*.kbd; do [ -e "$f" ] && return 0; done; return 1; }
if ! has_kbd; then
  cp -X "$REPO_ROOT/Resources/sample.kbd" "$PROFILES/starter.kbd"
  chown "$CONSOLE_USER" "$PROFILES/starter.kbd"
  echo "==> installed starter profile"
else
  echo "==> profiles already present, keeping them"
fi
FIRST_CFG=""
for f in "$PROFILES"/*.kbd; do
  [ -e "$f" ] || continue
  FIRST_CFG="$f"; break
done
if [ -z "$FIRST_CFG" ]; then echo "ERROR: no .kbd profile available" >&2; exit 1; fi

# 4. Helper scripts + sudoers. Back up a differing sudoers drop-in first.
mkdir -p "$LIBEXEC"
cp -X "$SCRIPT_DIR/switch-profile.sh" "$LIBEXEC/switch-profile.sh"
chmod 755 "$LIBEXEC/switch-profile.sh"
/usr/sbin/visudo -c -f "$SUDOERS_SRC"
if [ -f "$SUDOERS_DST" ] && ! cmp -s "$SUDOERS_SRC" "$SUDOERS_DST"; then
  BACKUP="$SUDOERS_DST.bak-$(date +%Y%m%d%H%M%S)"
  cp -p "$SUDOERS_DST" "$BACKUP"
  echo "==> backed up existing sudoers drop-in to $BACKUP"
fi
cp -X "$SUDOERS_SRC" "$SUDOERS_DST"
chmod 0440 "$SUDOERS_DST"
/usr/sbin/visudo -c -f "$SUDOERS_DST"

# 5. LaunchDaemon for kanata (root). Kanata is INACTIVE by default:
# fresh installs get RunAtLoad=false/KeepAlive=false and are left stopped;
# the menu-bar On toggle enables it on demand. Reinstalls preserve the
# currently configured profile, port, and enabled state.
EXIST_CFG=""; EXIST_PORT="10000"; EXIST_ENABLED="off"
if [ -f "$PLIST_DST" ]; then
  SAVED="$(python3 - "$PLIST_DST" <<'EOF' || true
import plistlib, sys
try:
    with open(sys.argv[1], 'rb') as f:
        pl = plistlib.load(f)
    args = pl.get('ProgramArguments', [])
    cfg, port = '', '10000'
    for i, a in enumerate(args):
        if a == '-c' and i + 1 < len(args):
            cfg = args[i + 1]
        if a == '--port' and i + 1 < len(args):
            port = args[i + 1]
    print(cfg)
    print(port)
    print('on' if pl.get('RunAtLoad') is True else 'off')
except Exception:
    pass
EOF
)"
  EXIST_CFG="$(printf '%s\n' "$SAVED" | sed -n '1p')"
  P2="$(printf '%s\n' "$SAVED" | sed -n '2p')"
  P3="$(printf '%s\n' "$SAVED" | sed -n '3p')"
  [ -n "$P2" ] && EXIST_PORT="$P2"
  [ -n "$P3" ] && EXIST_ENABLED="$P3"
fi
if [ -n "$EXIST_CFG" ] && [ -f "$EXIST_CFG" ]; then
  CFG="$EXIST_CFG"; PORT="$EXIST_PORT"; ENABLED="$EXIST_ENABLED"
  echo "==> keeping existing daemon config: $CFG (port $PORT, $ENABLED)"
else
  CFG="$FIRST_CFG"; PORT="10000"; ENABLED="off"
fi
mkdir -p /Library/Logs/Kanata
sed -e "s#__KANATA_BIN__#$KANATA_BIN#" \
    -e "s#__KANATA_CFG__#$CFG#" \
    -e "s#__KANATA_PORT__#$PORT#" \
    "$REPO_ROOT/Resources/dev.kanata.gui.kanata.plist.template" > "$PLIST_DST"
if [ "$ENABLED" = "on" ]; then
  # Template defaults to off; re-enable when preserving a previously-on setup.
  python3 - "$PLIST_DST" <<'EOF'
import plistlib, sys
p = sys.argv[1]
with open(p, 'rb') as f:
    pl = plistlib.load(f)
pl['RunAtLoad'] = True
pl['KeepAlive'] = True
with open(p, 'wb') as f:
    plistlib.dump(pl, f)
EOF
fi
chmod 644 "$PLIST_DST"
chown root:wheel "$PLIST_DST"
/usr/bin/plutil -lint "$PLIST_DST"
/bin/launchctl bootout "system/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap system "$PLIST_DST" || true
if [ "$ENABLED" = "on" ]; then
  /bin/launchctl kickstart -k "system/$LABEL" \
    || echo "WARNING: daemon plist updated but restart failed; reboot or run: sudo launchctl kickstart -k system/$LABEL" >&2
  echo "==> kanata daemon enabled (running)"
else
  echo "==> kanata daemon installed but INACTIVE (flip On in the menu-bar app to start)"
fi

echo "==> requesting Accessibility + Input Monitoring prompts"
sudo -u "$CONSOLE_USER" open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

echo "DONE. Next: approve driver extension, grant Input Monitoring + Accessibility to $KANATA_BIN, then flip On in the menu-bar app to start kanata."
