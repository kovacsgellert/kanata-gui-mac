# Changelog

## Unreleased

- Installer aborts up front when the installed Karabiner driver (e.g. the v8
  bundled with Karabiner-Elements) doesn't match kanata, instead of finishing
  a setup that only logs `connect_failed asio.system:2`
- Fix driver pkg download URL (asset names have no `v` prefix; was a 404)
- Don't install a second VHID daemon when Karabiner-Elements already runs one;
  warn that Karabiner-Elements conflicts with kanata
- Setup tab shows the installed driver version and flags a mismatch
- Copy files into system locations without xattrs (`cp -X`): the Homebrew
  quarantine flag on the bundled VHID daemon plist made launchd refuse it

## 0.1.0

- Menu-bar panel (Control-Center style) with a Kanata On/Off switch on top
- Kanata inactive by default: root LaunchDaemon ships with RunAtLoad/KeepAlive
  off, the toggle enables it on demand and the state survives reboots
- Start KanataGUI at login via SMAppService login item (Settings → General)
- Settings window: General, Profiles and Setup tabs in native grouped Form style
- Profiles auto-detected from `~/.config/kanata` (GNU-stow symlinks supported),
  import via file picker, remove hides without deleting (re-import restores)
- One-time privileged installer: kanata via Homebrew (pinned versions via
  GitHub releases), Karabiner driver pkg, daemon + narrow NOPASSWD sudoers
- Ship the app: `.app` bundle, DMG + PKG installers, tag-driven GitHub Release
