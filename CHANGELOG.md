# Changelog

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
