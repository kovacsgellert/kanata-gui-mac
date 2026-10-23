# Changelog

## 0.1.4

- Settings opens in front of other windows instead of getting lost behind
  them: the app is a menu-bar agent (`LSUIElement`), so macOS left it inactive
  while the Settings window opened and the window was ordered behind the
  frontmost app's windows — with no Dock icon there was no way to bring it
  forward again. Opening Settings now activates the app (which keeps it out of
  the Dock) and raises the window above every other app

## 0.1.3

- Menu-bar icon reflects kanata's real state right after launch/login: the
  daemon is queried as part of app launch instead of only when the menu is
  first opened, so after a reboot it no longer shows the "disabled" icon
  while kanata is actually running (plus a delayed re-check for the boot
  race, and the stored toggle is synced from the daemon at launch)
- New menu-bar icons, drawn in code: the disabled icon is an outline keyboard
  struck through with a slash (`keyboard` vs `keyboard.fill` were nearly
  identical at 16px), and the error icon is a keyboard with a warning badge —
  the old `keyboard.badge.exclamationmark` symbol does not exist on current
  macOS and rendered a blank icon

## 0.1.2

- Releases are signed with a stable self-signed certificate (shared with the
  author's other apps) instead of ad-hoc, so macOS recognizes updates as the
  same app; tag builds fail without the certificate
- README: first-launch steps for macOS 15+ (Open Anyway), updating, releasing

## 0.1.1

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
