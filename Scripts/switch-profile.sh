#!/bin/sh
# Atomically point the root LaunchDaemon at a new config and restart it.
# Installed to /usr/local/libexec/kanata-gui/switch-profile.sh, invoked via
# passwordless sudo (see Resources/kanata-gui.sudoers).
set -eu
CFG="$1"
PORT="${2:-10000}"
PLIST="/Library/LaunchDaemons/dev.kanata.gui.kanata.plist"
LABEL="dev.kanata.gui.kanata"

if [ ! -f "$CFG" ]; then echo "config not found: $CFG" >&2; exit 1; fi
if [ ! -f "$PLIST" ]; then echo "daemon plist missing: $PLIST" >&2; exit 1; fi

TMP="$(mktemp /tmp/dev.kanata.gui.kanata.XXXXXX)"
/usr/bin/python3 - "$PLIST" "$CFG" "$PORT" "$TMP" <<'EOF'
import plistlib, sys
plist_path, cfg, port, tmp = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(plist_path, 'rb') as f:
    pl = plistlib.load(f)
args = pl.get('ProgramArguments', [])
bin_ = args[0] if args else '/usr/local/bin/kanata'
pl['ProgramArguments'] = [bin_, '-c', cfg, '--port', str(port)]
with open(tmp, 'wb') as f:
    plistlib.dump(pl, f)
EOF
chmod 644 "$TMP"
chown root:wheel "$TMP"
mv "$TMP" "$PLIST"
/bin/launchctl kickstart -k "system/$LABEL" || /bin/launchctl bootstrap system "$PLIST"
echo "kanata daemon now using: $CFG (port $PORT)"
