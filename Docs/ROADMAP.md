# Roadmap

Checked against 0.1.0. Ordered roughly by value, not promised.

## Layer status in the menu icon

kanata publishes layer changes over its TCP feed (`--port 10000`; subscribe to
`{"LayerChange":…}`). The daemon already passes `--port` through on every
profile switch, but the app never connects. Goal: per-layer menu-bar icon.
Needs a small TCP client with reconnect handling.

## Signed + notarized distribution

Releases are signed with a self-signed certificate (stable identity across
updates) but not notarized, so first launch needs Open Anyway / right-click →
Open. Remaining: paid Apple Developer ID signing + notarization.

## SMJobBless privileged helper

Replace the NOPASSWD sudoers grant with Apple's blessed helper pattern
(helper in `Library/PrivilegedHelperTools`, code-signed, XPC). Most correct
long-term, but needs Developer ID + signing setup — pairs with the item above.

## Sparkle updates

In-app updates for the `.app` installs (DMG and PKG).

## App icon

No custom icon yet: SF Symbols throughout, nothing wired into the bundle.
Add an app icon plus a custom menu-bar glyph.
