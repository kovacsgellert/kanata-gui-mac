import Foundation
import ServiceManagement

/// Persisted UI-level preferences.
/// - `startAtLogin`: menubar app registers as a login item (default true).
/// - `kanataEnabled`: whether kanata daemon should be running (default false,
///   i.e. kanata is inactive until the user flips the On/Off toggle).
@MainActor
final class AppSettings: ObservableObject {
    @Published var startAtLogin: Bool = true {
        didSet { save() }
    }
    @Published var kanataEnabled: Bool = false {
        didSet { save() }
    }

    private struct Stored: Codable {
        var startAtLogin: Bool?
        var kanataEnabled: Bool?
    }

    init() {
        if let data = try? Data(contentsOf: KanataConstants.settingsFile),
           let s = try? JSONDecoder().decode(Stored.self, from: data)
        {
            // Absent keys keep the defaults above (login=true, enabled=false).
            if let v = s.startAtLogin { startAtLogin = v }
            if let v = s.kanataEnabled { kanataEnabled = v }
        }
    }

    func save() {
        try? FileManager.default.createDirectory(
            at: KanataConstants.appSupportDir, withIntermediateDirectories: true)
        let s = Stored(startAtLogin: startAtLogin, kanataEnabled: kanataEnabled)
        try? JSONEncoder().encode(s).write(to: KanataConstants.settingsFile)
    }
}

/// Thin wrapper around SMAppService for "start menubar app at login".
/// No-ops gracefully when not running from an app bundle (e.g. `swift run`).
enum LoginItemManager {
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setRegistered(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error
        }
    }

    /// Best-effort enforcement of the stored preference. Called on app launch.
    /// Returns an error only for logging; the Settings tab surfaces it.
    @discardableResult
    static func sync(startAtLogin: Bool) -> Error? {
        let currently = isRegistered
        // Avoid spurious register/unregister calls (which can prompt).
        if startAtLogin == currently { return nil }
        return setRegistered(startAtLogin)
    }
}
