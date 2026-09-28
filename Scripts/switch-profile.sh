#!/bin/sh
# Point the root LaunchDaemon at a new config and start/stop it.
# Installed to /usr/local/libexec/kanata-gui/switch-profile.sh, invoked via
# passwordless sudo (see Resources/kanata-gui.sudoers).
#
# Kanata is INACTIVE by default (RunAtLoad=false, KeepAlive=false). The
# menu-bar On/Off toggle enables/disables it on demand:
#
#   switch-profile.sh <cfg> <port> [on|off]  # switch config (default: on)
#   switch-profile.sh --disable               # keep config, stop, stay off at boot
#   switch-profile.sh --enable                # keep config, start, start at boot
set -eu
PLIST="/Library/LaunchDaemons/dev.kanata.gui.kanata.plist"
LABEL="dev.kanata.gui.kanata"

MODE="switch"
CFG=""
PORT="10000"
ENABLED="on"

usage() { echo "usage: $0 <cfg> <port> [on|off] | $0 --disable | $0 --enable" >&2; exit 1; }

if [ "${1:-}" = "--disable" ]; then
  MODE="disable"
elif [ "${1:-}" = "--enable" ]; then
  MODE="enable"
elif [ $# -eq 2 ] || [ $# -eq 3 ]; then
  MODE="switch"
  CFG="$1"
  PORT="$2"
  ENABLED="${3:-on}"
  case "$ENABLED" in on|off) ;; *) usage;; esac
  if [ ! -f "$CFG" ]; then echo "config not found: $CFG" >&2; exit 1; fi
else
  usage
fi

if [ ! -f "$PLIST" ]; then echo "daemon plist missing: $PLIST" >&2; exit 1; fi

TMP="$(mktemp /tmp/dev.kanata.gui.kanata.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
if [ "$MODE" = "switch" ]; then
  /usr/bin/python3 - "$PLIST" "$CFG" "$PORT" "$ENABLED" "$TMP" <<'EOF'
import plistlib, sys
plist_path, cfg, port, enabled, tmp = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
with open(plist_path, 'rb') as f:
    pl = plistlib.load(f)
args = pl.get('ProgramArguments', [])
bin_ = args[0] if args else '/usr/local/bin/kanata'
pl['ProgramArguments'] = [bin_, '-c', cfg, '--port', str(port)]
on = (enabled == 'on')
pl['RunAtLoad'] = on
pl['KeepAlive'] = on
with open(tmp, 'wb') as f:
    plistlib.dump(pl, f)
EOF
else
  WANT="$([ "$MODE" = "enable" ] && echo on || echo off)"
  /usr/bin/python3 - "$PLIST" "$WANT" "$TMP" <<'EOF'
import plistlib, sys
plist_path, enabled, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
with open(plist_path, 'rb') as f:
    pl = plistlib.load(f)
on = (enabled == 'on')
pl['RunAtLoad'] = on
pl['KeepAlive'] = on
with open(tmp, 'wb') as f:
    plistlib.dump(pl, f)
EOF
fi
# Validate before installing: a broken plist + bootout would leave kanata down.
/usr/bin/plutil -lint "$TMP"
chmod 644 "$TMP"
chown root:wheel "$TMP"
mv "$TMP" "$PLIST"
# NOTE: kickstart -k restarts with the already-loaded config, so it does NOT
# reliably apply ProgramArguments changes. bootout + bootstrap re-reads the
# plist from disk, which is what a profile switch needs.
trap - EXIT
case "$MODE" in
  disable)
    /bin/launchctl bootout "system/$LABEL" 2>/dev/null || true
    echo "kanata disabled (stopped, will not start at boot)"
    ;;
  enable)
    /bin/launchctl bootout "system/$LABEL" 2>/dev/null || true
    /bin/launchctl bootstrap system "$PLIST"
    echo "kanata enabled (starts now and at boot)"
    ;;
  switch)
    if [ "$ENABLED" = "on" ]; then
      /bin/launchctl bootout "system/$LABEL" 2>/dev/null || true
      /bin/launchctl bootstrap system "$PLIST"
      echo "kanata daemon now using: $CFG (port $PORT)"
    else
      /bin/launchctl bootout "system/$LABEL" 2>/dev/null || true
      echo "kanata daemon now using: $CFG (port $PORT), disabled (stopped)"
    fi
    ;;
esac
