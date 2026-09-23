import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var service: KanataService

    var body: some View {
        Group {
            statusSection
            Divider()
            profilesSection
            Divider()
            controlSection
            Divider()
            footerSection
        }
    }

    private var statusSection: some View {
        Group {
            switch service.status {
            case .unknown:
                Text("Kanata: checking…")
            case .stopped:
                Text("Kanata: stopped")
            case .running:
                Text("Kanata: running\(store.activeProfileName.map { " (\($0))" } ?? "")")
            case .error(let msg):
                Text("Kanata error")
                Text(msg).font(.caption).foregroundStyle(.red).lineLimit(4)
            }
        }
    }

    private var profilesSection: some View {
        Group {
            Text("Profiles").font(.caption).foregroundStyle(.secondary)
            if store.profiles.isEmpty {
                Text("No .kbd profiles yet — use Settings to import one.")
                    .font(.caption)
            }
            ForEach(store.profiles) { profile in
                Button {
                    store.activeProfileName = profile.name
                    store.save()
                    _ = service.switchTo(profile: profile)
                } label: {
                    HStack {
                        Text(profile.name)
                        if profile.name == store.activeProfileName {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    private var controlSection: some View {
        Group {
            Button("Start kanata") { _ = service.start() }
            Button("Stop kanata") { _ = service.stop() }
            Button("Refresh status") { service.refresh() }
            if let err = service.lastError, !err.isEmpty {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(5)
            }
        }
    }

    private var footerSection: some View {
        Group {
            SettingsLink { Text("Settings…") }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
