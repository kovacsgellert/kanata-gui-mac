#!/bin/sh
# Uninstall everything install.sh created (requires root).
set -eu
if [ "$(id -u)" -ne 0 ]; then echo "must run as root" >&2; exit 1; fi
/bin/launchctl bootout system/dev.kanata.gui.kanata 2>/dev/null || true
rm -f /Library/LaunchDaemons/dev.kanata.gui.kanata.plist
rm -f /etc/sudoers.d/kanata-gui
rm -rf /usr/local/libexec/kanata-gui
echo "removed kanata-gui daemon + sudoers. kanata binary and Karabiner driver left in place."
