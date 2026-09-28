import Foundation

/// Persists profiles under ~/Library/Application Support/kanata-gui/.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [KanataProfile] = []
    @Published var activeProfileName: String?
    /// Config paths the user removed in the UI. Files are never deleted;
    /// entries stay hidden until the profile is imported again.
    @Published var ignoredPaths: Set<String> = []

    private let fm = FileManager.default

    init() {
        ensureDirs()
        if let data = try? Data(contentsOf: ignoredFile),
           let ignored = try? JSONDecoder().decode([String].self, from: data)
        {
            ignoredPaths = Set(ignored)
        }
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

    private var ignoredFile: URL {
        KanataConstants.appSupportDir.appendingPathComponent("ignored-profiles.json")
    }

    func load() {
        rescan()
        if let data = try? Data(contentsOf: KanataConstants.activeProfileFile),
           let name = try? JSONDecoder().decode(String.self, from: data),
           profiles.contains(where: { $0.name == name })
        {
            activeProfileName = name
        } else {
            activeProfileName = profiles.first?.name
        }
    }

    /// Re-scan managed + auto-detected locations and merge, preserving the
    /// active profile when it still exists. Safe to call on every menu open.
    func rescan() {
        var merged: [KanataProfile] = []
        var seenNames = Set<String>()

        // 1. Managed dir wins on name collisions (explicit imports take precedence).
        for profile in scanManaged() where seenNames.insert(profile.name).inserted {
            merged.append(profile)
        }
        // 2. Auto-detected *.kbd files fill in the rest, referenced in place.
        for profile in scanAutoDetected() where seenNames.insert(profile.name).inserted {
            merged.append(profile)
        }
        // 3. Keep stale index entries only if their file still exists on disk
        // (covers profiles imported before auto-detection existed).
        if let data = try? Data(contentsOf: indexFile),
           let saved = try? JSONDecoder().decode([KanataProfile].self, from: data)
        {
            for profile in saved where seenNames.insert(profile.name).inserted
                && fm.fileExists(atPath: profile.configPath)
            {
                merged.append(profile)
            }
        }

        merged.sort { $0.name < $1.name }
        // User-removed profiles stay hidden until imported again.
        merged.removeAll { ignoredPaths.contains($0.configPath) }
        profiles = merged
        if let active = activeProfileName, !profiles.contains(where: { $0.name == active }) {
            activeProfileName = profiles.first?.name
        } else if activeProfileName == nil {
            activeProfileName = profiles.first?.name
        }
        save()
    }

    private func scanManaged() -> [KanataProfile] {
        scanKbdFiles(in: KanataConstants.profilesDir).map {
            KanataProfile(
                name: $0.deletingPathExtension().lastPathComponent,
                configPath: $0.path,
                tcpPort: KanataConstants.defaultTCPPort,
                source: .managed
            )
        }
    }

    private func scanAutoDetected() -> [KanataProfile] {
        KanataConstants.kanataConfigDirs.flatMap { scanKbdFiles(in: $0) }.map {
            KanataProfile(
                name: $0.deletingPathExtension().lastPathComponent,
                configPath: $0.path,
                tcpPort: KanataConstants.defaultTCPPort,
                source: .autoDetected
            )
        }
    }

    /// Non-recursive top-level scan plus one level of subdirectories, skipping
    /// hidden files. Keeps discovery predictable (no deep-tree surprises).
    ///
    /// Symlink-aware: ~/.config/kanata is often a symlink (e.g. GNU stow),
    /// and the URL-based contentsOfDirectory fails with ENOTDIR across
    /// symlinked directories. So traversal uses resolved paths, while
    /// returned URLs keep the original base so displayed/stored config paths
    /// stay stable (and short).
    private func scanKbdFiles(in dir: URL) -> [URL] {
        let resolved = dir.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: resolved.path) else { return [] }
        var found: [URL] = []
        let top = (try? fm.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in top {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let displayURL = dir.appendingPathComponent(url.lastPathComponent)
            if isDir.boolValue {
                let nested = (try? fm.contentsOfDirectory(
                    at: url.resolvingSymlinksInPath(),
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                found += nested.filter { $0.pathExtension.lowercased() == "kbd" }
                    .map { displayURL.appendingPathComponent($0.lastPathComponent) }
            } else if url.pathExtension.lowercased() == "kbd" {
                found.append(displayURL)
            }
        }
        return found
    }

    func save() {
        try? JSONEncoder().encode(profiles).write(to: indexFile)
        try? JSONEncoder().encode(Array(ignoredPaths)).write(to: ignoredFile)
        if let name = activeProfileName {
            try? JSONEncoder().encode(name).write(to: KanataConstants.activeProfileFile)
        }
    }

    /// Hide a profile from KanataGUI without deleting its file.
    /// It stays hidden across rescans until imported again.
    func removeProfile(_ profile: KanataProfile) {
        ignoredPaths.insert(profile.configPath)
        profiles.removeAll { $0.configPath == profile.configPath }
        if activeProfileName == profile.name
            && !profiles.contains(where: { $0.name == profile.name })
        {
            activeProfileName = profiles.first?.name
        }
        save()
    }

    func importProfile(from url: URL) throws {
        ensureDirs()
        let dest = KanataConstants.profilesDir
            .appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: url, to: dest)
        // Importing restores a previously removed profile.
        ignoredPaths.remove(dest.path)
        ignoredPaths.remove(url.path)
        let profile = KanataProfile(
            name: dest.deletingPathExtension().lastPathComponent,
            configPath: dest.path,
            tcpPort: KanataConstants.defaultTCPPort,
            source: .managed
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
