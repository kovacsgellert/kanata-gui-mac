# kanata-gui-mac

Native macOS menu-bar app for [kanata](https://github.com/jtroo/kanata), in the spirit of
[kanata-tray](https://github.com/rszyma/kanata-tray): auto-start kanata at login **without a
password prompt**, plus a menu-bar dropdown to switch between `.kbd` profiles.

## Short answer: is this possible?

**Yes — with one design constraint.** On macOS kanata **must run as root** (the Karabiner
VirtualHIDDevice daemon IPC at `/Library/Application Support/org.pqrs/tmp/rootonly/` is
root-only). So unlike kanata-tray (which spawns kanata as a user-space child process), this app
uses a split architecture:

- **Root `LaunchDaemon`** (`dev.kanata.gui.kanata`) runs kanata at boot, `KeepAlive`, logs to
  `/Library/Logs/Kanata/`. This is what gives passwordless autostart.
- **Unprivileged menu-bar app** (SwiftUI `MenuBarExtra`) edits which config the daemon points at
  and kickstarts/restarts it via a **narrow NOPASSWD sudoers file** (only `launchctl
  kickstart/bootout/print` for that one label + the switch script).
- **One-time installer** (`Scripts/install.sh`, triggered from Settings → Setup via `osascript …
  with administrator privileges`) downloads kanata + the Karabiner driver, installs the daemon +
  sudoers, and asks for your admin password **exactly once**.

Manual steps Apple does not allow automating: approving the DriverKit system extension and
granting Input Monitoring + Accessibility to `/usr/local/bin/kanata`. The Setup tab walks you
through them.

## Layout

- `Sources/KanataGUI/` — SwiftUI app (`KanataGUIApp`, `MenuBarView`, `Views`,
  `KanataService`, `ProfileStore`, `PrivilegedInstaller`)
- `Resources/` — LaunchDaemon plist template, VHID daemon plist, sudoers file, sample `.kbd`
- `Scripts/` — `install.sh`, `switch-profile.sh`, `uninstall.sh`
- `Docs/ARCHITECTURE.md` — full design + security notes

## Quick start (dev)

```sh
swift build
swift run KanataGUI
# one-time privileged setup (asks admin password once):
sudo ./Scripts/install.sh
```

Then open the menu-bar icon → Settings → import `.kbd` profiles, click one to switch
(validated with `kanata --check`, daemon plist rewritten, daemon kickstarted as root).

## Requirements

- macOS 14+, Apple Silicon or Intel
- kanata v1.12.0 + Karabiner-DriverKit-VirtualHIDDevice v6.2.0 (verified protocol-5 pair;
  kanata ≥ v1.13 will need driver v8.0.0 — see `Docs/ARCHITECTURE.md`)
