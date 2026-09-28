import SwiftUI

@main
struct KanataGUIApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var service = KanataService()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra("kanata", systemImage: menuIcon) {
            MenuBarView(store: store, service: service, settings: settings)
                .onAppear {
                    store.rescan()
                    service.refresh()
                    // Daemon state is source of truth; reflect it in the toggle.
                    settings.kanataEnabled = service.isRunning
                    // Best-effort: enforce "start app at login" (default true).
                    if let err = LoginItemManager.sync(startAtLogin: settings.startAtLogin) {
                        // Visible in Settings; menu-bar launch must not prompt.
                        service.lastError = "Login item: \(err.localizedDescription)"
                    }
                }
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(store: store, service: service, settings: settings)
        }
    }

    private var menuIcon: String {
        switch service.status {
        case .running: return "keyboard.fill"
        case .stopped: return "keyboard"
        case .error: return "keyboard.badge.exclamationmark"
        case .unknown: return "keyboard"
        }
    }
}
