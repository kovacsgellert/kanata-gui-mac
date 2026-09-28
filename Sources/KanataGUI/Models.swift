import Foundation

/// A named kanata configuration profile (a .kbd file on disk).
struct KanataProfile: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    /// Absolute path to the .kbd file.
    var configPath: String
    /// TCP port kanata exposes for this profile (for layer/status queries).
    var tcpPort: Int
    /// Where the profile was discovered. Defaults to `.managed` so profiles
    /// saved before this field existed still decode.
    var source: ProfileSource

    init(name: String, configPath: String, tcpPort: Int, source: ProfileSource = .managed) {
        self.name = name
        self.configPath = configPath
        self.tcpPort = tcpPort
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case name, configPath, tcpPort, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        configPath = try c.decode(String.self, forKey: .configPath)
        tcpPort = try c.decode(Int.self, forKey: .tcpPort)
        source = try c.decodeIfPresent(ProfileSource.self, forKey: .source) ?? .managed
    }
}

/// Where a profile's .kbd file lives.
enum ProfileSource: String, Codable {
    /// Copied into ~/Library/Application Support/kanata-gui/profiles/ via import.
    case managed
    /// Found in place under $XDG_CONFIG_HOME/kanata or ~/.config/kanata.
    case autoDetected
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
    /// Locates the kanata binary (Homebrew, /usr/local, ~/bin, or PATH).
    /// Never hardcode /usr/local/bin/kanata: brew installs to /opt/homebrew.
    static var kanataBinaryPath: String {
        let fm = FileManager.default
        var candidates = ["/usr/local/bin/kanata", "/opt/homebrew/bin/kanata"]
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            candidates.append((home as NSString).appendingPathComponent("bin/kanata"))
        }
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            candidates.append((dir as NSString).appendingPathComponent("kanata"))
        }
        for c in candidates where fm.isExecutableFile(atPath: c) {
            return c
        }
        return "/usr/local/bin/kanata" // fallback so errors name the expected path
    }
    static let installedSwitchScript = "/usr/local/libexec/kanata-gui/switch-profile.sh"
    static let vhidDaemonLabel = "org.pqrs.Karabiner-VirtualHIDDevice-Daemon"
    static let defaultTCPPort = 10000

    static var appSupportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/kanata-gui", isDirectory: true)
    }
    static var profilesDir: URL {
        appSupportDir.appendingPathComponent("profiles", isDirectory: true)
    }
    /// Directories auto-scanned for *.kbd files: $XDG_CONFIG_HOME/kanata when
    /// the variable is set, always falling back to ~/.config/kanata.
    /// Both are returned (deduped) when they differ so configs are found
    /// regardless of which location the user actually uses.
    static var kanataConfigDirs: [URL] {
        var dirs: [URL] = []
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
           !xdg.trimmingCharacters(in: .whitespaces).isEmpty
        {
            dirs.append(
                URL(fileURLWithPath: xdg, isDirectory: true)
                    .appendingPathComponent("kanata", isDirectory: true)
            )
        }
        dirs.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/kanata", isDirectory: true)
        )
        return Array(Set(dirs.map { $0.standardizedFileURL })).sorted { $0.path < $1.path }
    }
    static var activeProfileFile: URL {
        appSupportDir.appendingPathComponent("active-profile.json", isDirectory: false)
    }
    static var settingsFile: URL {
        appSupportDir.appendingPathComponent("settings.json", isDirectory: false)
    }
    static var logDir: URL {
        URL(fileURLWithPath: "/Library/Logs/Kanata", isDirectory: true)
    }
}
