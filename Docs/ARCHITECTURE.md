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

1. Driver extension: System Settings → General → Login Items & Extensions → Driver Extensions →
   enable `org.pqrs.Karabiner-DriverKit-VirtualHIDDevice` (reboot if toggled after `deactivate`).
2. Input Monitoring: add `/usr/local/bin/kanata`.
3. Accessibility: add `/usr/local/bin/kanata` (run `kanata --macos-request-permissions` to prompt).
4. Reinstalling kanata in place can invalidate TCC entries — toggle off/on again.

## Version pairing

- kanata ≥ v1.13 ↔ driver v8.0.0 (protocol 7).
- kanata < v1.13 ↔ driver v6.2.0 (protocol 5).
Mismatch symptom: `connect_failed asio.system:2` loop or `Karabiner-VirtualHIDDevice driver is
not activated`. The installer defaults to the new pair and accepts `--kanata-version` /
`--driver-version` overrides.

## Future work

TCP layer-status in the menu icon (kanata-tray shows per-layer icons via kanata's TCP feed —
subscribe to `{"LayerChange":…}` on `--port`); `SMJobBless` migration; signed `.pkg`/`.dmg`
distribution; Sparkle updates.
