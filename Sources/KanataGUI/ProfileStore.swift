import Foundation

/// Persists profiles under ~/Library/Application Support/kanata-gui/.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [KanataProfile] = []
    @Published var activeProfileName: String?

    private let fm = FileManager.default

    init() {
        ensureDirs()
        load()
    }

    func ensureDirs() {
        for dir in [KanataConstants.appSupportDir, KanataConstants.profilesDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private var indexFile: URL {
        KanataConstants.appSupportDir.appendingPathComponent("profiles.json")
    }

    func load() {
        if fm.fileExists(atPath: KanataConstants.profilesDir.path) {
            let kbds = (try? fm.contentsOfDirectory(at: KanataConstants.profilesDir, includingPropertiesForKeys: nil)) ?? []
            let found = kbds.filter { $0.pathExtension == "kbd" }.map { url in
                KanataProfile(
                    name: url.deletingPathExtension().lastPathComponent,
                    configPath: url.path,
                    tcpPort: KanataConstants.defaultTCPPort
                )
            }.sorted { $0.name < $1.name }
            if !found.isEmpty {
                profiles = found
            }
        }
        if profiles.isEmpty, let data = try? Data(contentsOf: indexFile),
           let decoded = try? JSONDecoder().decode([KanataProfile].self, from: data)
        {
            profiles = decoded
        }
        if let data = try? Data(contentsOf: KanataConstants.activeProfileFile),
           let name = try? JSONDecoder().decode(String.self, from: data)
        {
            activeProfileName = name
        } else {
            activeProfileName = profiles.first?.name
        }
    }

    func save() {
        try? JSONEncoder().encode(profiles).write(to: indexFile)
        if let name = activeProfileName {
            try? JSONEncoder().encode(name).write(to: KanataConstants.activeProfileFile)
        }
    }

    func importProfile(from url: URL) throws {
        ensureDirs()
        let dest = KanataConstants.profilesDir
            .appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: url, to: dest)
        let profile = KanataProfile(
            name: dest.deletingPathExtension().lastPathComponent,
            configPath: dest.path,
            tcpPort: KanataConstants.defaultTCPPort
        )
        profiles.removeAll { $0.name == profile.name }
        profiles.append(profile)
        profiles.sort { $0.name < $1.name }
        if activeProfileName == nil { activeProfileName = profile.name }
        save()
    }

    func profile(named name: String?) -> KanataProfile? {
        guard let name else { return nil }
        return profiles.first { $0.name == name }
    }
}
