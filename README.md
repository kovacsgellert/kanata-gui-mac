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

## Install

```sh
brew tap kovacsgellert/tap
brew install --cask kanata-gui
```

Or download `kanata-gui-<version>-macos-arm64.dmg` (drag **KanataGUI** into **Applications**)
or the `.pkg` from the [Releases page](https://github.com/kovacsgellert/kanata-gui-mac/releases).

Neither is notarized, so Gatekeeper blocks the first launch. On macOS 15 (Sequoia) and later,
try to open the app once, then go to `System Settings → Privacy & Security`, scroll down and
click **Open Anyway**. On macOS 14, right-click the app and choose **Open** instead.

### Updating

Update with `brew upgrade --cask kanata-gui`, or by dragging the new version over the old one in
Applications. The Input Monitoring and Accessibility permissions belong to the kanata binary, not
to KanataGUI, so app updates never touch them. Releases from 0.1.2 on are signed with the same
certificate, so macOS also recognizes each update as the same app. Coming from 0.1.1 or older,
macOS treats the update as a new app once: if **Start KanataGUI at login** stops working, toggle
it off and on again in Settings → General.

### Releasing

Pushing a version tag like `0.1.0` triggers the `Release` workflow, which packages the `.app`,
builds the DMG and PKG, and attaches them to the GitHub Release.

Releases are signed with a self-signed certificate (no paid Apple Developer ID), stored in the
`SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` repository secrets; the workflow refuses to
publish a release without it. A stable signature lets macOS recognize updates as the same app;
ad-hoc signatures change with every build. The certificate is shared by all of the author's Mac
apps (macOS keys permissions on bundle id + certificate, so apps stay separate); it was created
once with `Scripts/make-signing-cert.sh` into `~/.codesign/`. Keep its `.p12` and password backed
up: a new certificate makes every update look like a different app again. To sign a local build
the same way, run `SIGNING_P12=<path> SIGNING_P12_PASSWORD=<password> ./Scripts/package-app.sh`.

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
