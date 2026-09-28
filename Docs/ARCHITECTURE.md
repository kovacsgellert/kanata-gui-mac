# Architecture

## Why not just port kanata-tray?

kanata-tray (Go) spawns kanata as a child process of the tray app and talks to it over TCP
(`--port`, layer notifications, start/stop/pause, per-preset icons, hooks). That works on
Windows/Linux where user-space key grabbing is possible. On macOS it breaks: kanata must run as
**root** (Karabiner VHID `rootonly` IPC), but a menu-bar app runs as the logged-in user. A
user-space tray app therefore cannot own the kanata process.

## Chosen design: LaunchDaemon + narrow sudoers

```
┌─ Menu-bar app (user, SwiftUI MenuBarExtra) ─────────────┐
│ profiles/*.kbd │ kanata --check │ sudo -n launchctl ... │
└───────────────┬─────────────────────────────────────────┘
                │ sudoers: /etc/sudoers.d/kanata-gui (NOPASSWD, 5 lines)
┌───────────────▼─────────────────────────────────────────┐
│ LaunchDaemon system/dev.kanata.gui.kanata (root)        │
│ /usr/local/bin/kanata -c <active.kbd> --port 10000      │
│ RunAtLoad + KeepAlive → starts at boot, no password     │
└───────────────┬─────────────────────────────────────────┘
                │ grabs keyboard via
┌───────────────▼─────────────────────────────────────────┐
│ Karabiner-DriverKit-VirtualHIDDevice v8.0.0 (DriverKit) │
│ daemon: org.pqrs.Karabiner-VirtualHIDDevice-Daemon      │
└─────────────────────────────────────────────────────────┘
```

Profile switch = `kanata --check` (user) → privileged `switch-profile.sh` rewrites the daemon
plist `ProgramArguments` atomically (plistlib, `mktemp` + `mv`, `root:wheel`) → `launchctl
kickstart -k`. Start/stop = `launchctl kickstart/bootout` via the same sudoers grant.

## Alternatives considered

- **SMJobBless privileged helper**: Apple's blessed pattern (helper in
  `Library/PrivilegedHelperTools`, code-signed, XPC). Most correct long-term, but needs a
  Developer ID + signing setup. Migrate here once the app is signed for distribution.
- **sudoers + Login Item running `sudo -n kanata`**: simpler, but no `KeepAlive`, dies with the
  login session, and needs a user LaunchAgent instead of a system daemon. Kept as fallback.

## Permissions checklist (manual, Apple-mandated)

Per kanata's `docs/setup-macos.md`: nothing in Privacy & Security is granted
to Karabiner — the driver is approved via its Driver Extension entry, while
BOTH privacy grants go to the kanata binary itself (at its exact path,
e.g. `/opt/homebrew/bin/kanata` for Homebrew installs):

1. Driver extension: System Settings → General → Login Items & Extensions → Driver Extensions →
   enable `org.pqrs.Karabiner-DriverKit-VirtualHIDDevice` (reboot if toggled after `deactivate`).
2. Input Monitoring: add the kanata binary (`+`, press ⇧⌘G to paste a Homebrew path).
3. Accessibility: add the kanata binary (or run `kanata --macos-request-permissions` to prompt).
4. Reinstalling/upgrading kanata in place (incl. `brew upgrade kanata`) can invalidate TCC entries — toggle off/on again.

## Version pairing

- kanata ≤ v1.12 ↔ driver v6.2.0 (protocol 5). This is the current default
  (`--kanata-version v1.12.0 --driver-version v6.2.0`); the installer aborts on
  a mismatched pair instead of installing a setup that can never connect.
- kanata ≥ v1.13 ↔ driver v8.0.0 (protocol 7, breaking IPC change).
Mismatch symptom: `connect_failed asio.system:2` loop or `Karabiner-VirtualHIDDevice driver is
not activated`. Note kanata's per-release asset names change shape (older: 
`kanata-macos-binaries-<arch>-<version>.zip`, newer: `macos-binaries-<arch>.zip`) —
the installer tries both.

## Future work

See [ROADMAP.md](ROADMAP.md).
