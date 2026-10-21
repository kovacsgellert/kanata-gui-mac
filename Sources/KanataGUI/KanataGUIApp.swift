import SwiftUI

@main
struct KanataGUIApp: App {
    @StateObject private var store: ProfileStore
    @StateObject private var service: KanataService
    @StateObject private var settings: AppSettings

    var body: some Scene {
        // Custom label instead of `MenuBarExtra("kanata", systemImage:)`: the
        // stock symbols could not tell "off" from "on" (see MenuBarIcon).
        MenuBarExtra {
            MenuBarView(store: store, service: service, settings: settings)
        } label: {
            MenuBarIconView(service: service)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(store: store, service: service, settings: settings)
        }
    }

    init() {
        let service = KanataService()
        let settings = AppSettings()
        _store = StateObject(wrappedValue: ProfileStore())
        _service = StateObject(wrappedValue: service)
        _settings = StateObject(wrappedValue: settings)

        // The menu-bar icon used to only become correct once the user opened
        // the menu for the first time: status stayed `.unknown` (rendered as
        // "disabled") until MenuBarView.onAppear ran its refresh. Query the
        // daemon as part of launch instead, so right after a reboot the icon
        // already shows whether kanata is running.
        Task { @MainActor in AppBootstrap.run(service: service, settings: settings) }
    }
}

/// Launch-time work, kept out of the App struct so it can be kicked off from a
/// nonisolated `init()` without capturing `self`.
@MainActor
private enum AppBootstrap {
    static func run(service: KanataService, settings: AppSettings) {
        // The daemon is the source of truth: RunAtLoad starts it at boot, so by
        // the time the menu-bar app is up the answer is already there.
        service.refresh()
        settings.kanataEnabled = service.isRunning

        // Best-effort: enforce "start app at login" (default true).
        if let err = LoginItemManager.sync(startAtLogin: settings.startAtLogin) {
            // Visible in Settings; menu-bar launch must not prompt.
            service.lastError = "Login item: \(err.localizedDescription)"
        }

        // Boot race: launchd may not have started the daemon yet when we get
        // here (RunAtLoad happens early in boot; this app starts at login).
        // Re-check once shortly after, so the icon self-corrects if the first
        // query landed too early.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            service.refresh()
            settings.kanataEnabled = service.isRunning
        }
    }
}
