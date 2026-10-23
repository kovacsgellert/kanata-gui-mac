import AppKit

/// Brings the Settings window of this menu-bar agent to the front.
///
/// KanataGUI ships as an `LSUIElement` app: it lives in the menu bar and has no
/// Dock icon and no app-switcher entry. When the SwiftUI `Settings` scene opens
/// its window, macOS leaves the app inactive, so the window is ordered *behind*
/// the frontmost app's windows — and since nothing can activate the app, there
/// is no way to click it and pull it forward again (the window is simply lost
/// until the app is relaunched).
///
/// Activating the app is the fix: its windows are raised above every other
/// app's windows and the window becomes clickable. `activate(ignoringOtherApps:)`
/// does not add a Dock icon to an accessory app, so the menu-bar-only behaviour
/// is preserved.
@MainActor
enum SettingsWindowPresenter {
    /// Call whenever Settings is opened or re-requested from the menu-bar panel.
    ///
    /// Safe to call before the window exists: SwiftUI builds it asynchronously
    /// after `openSettings()`, and activating the app again once the window is
    /// on screen is what reliably lifts it above other apps.
    static func present() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
