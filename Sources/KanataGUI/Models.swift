import Foundation

/// A named kanata configuration profile (a .kbd file on disk).
struct KanataProfile: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    /// Absolute path to the .kbd file.
    var configPath: String
    /// TCP port kanata exposes for this profile (for layer/status queries).
    var tcpPort: Int
}

enum KanataStatus: Equatable {
    case unknown
    case running(profile: String?)
    case stopped
    case error(String)
}

/// Centralised constants. Keep in sync with Resources/*.plist and Scripts/*.
enum KanataConstants {
    static let daemonLabel = "dev.kanata.gui.kanata"
    static let daemonPlistPath = "/Library/LaunchDaemons/dev.kanata.gui.kanata.plist"
    static let kanataBinaryPath = "/usr/local/bin/kanata"
    static let vhidDaemonLabel = "org.pqrs.Karabiner-VirtualHIDDevice-Daemon"
    static let defaultTCPPort = 10000

    static var appSupportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/kanata-gui", isDirectory: true)
    }
    static var profilesDir: URL {
        appSupportDir.appendingPathComponent("profiles", isDirectory: true)
    }
    static var activeProfileFile: URL {
        appSupportDir.appendingPathComponent("active-profile.json", isDirectory: false)
    }
    static var logDir: URL {
        URL(fileURLWithPath: "/Library/Logs/Kanata", isDirectory: true)
    }
}
