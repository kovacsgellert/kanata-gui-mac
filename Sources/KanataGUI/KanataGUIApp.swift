import SwiftUI

@main
struct KanataGUIApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var service = KanataService()

    var body: some Scene {
        MenuBarExtra("kanata", systemImage: menuIcon) {
            MenuBarView(store: store, service: service)
                .onAppear { service.refresh() }
        }
        Settings {
            SettingsView(store: store, service: service)
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
