# kanata-gui-mac

Native macOS menu-bar app for [kanata](https://github.com/jtroo/kanata): a Control-Center-style
dropdown with an On/Off switch plus `.kbd` profile switching, all without a password prompt
after a one-time setup. See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for the full design
(root `LaunchDaemon` + narrow NOPASSWD sudoers) and security notes.

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
