import SwiftUI

/// Control-Center-style panel (like the Wi-Fi dropdown): real switch at the
/// top, profile list, footer actions. Shown via `.menuBarExtraStyle(.window)`,
/// which is what allows an actual Toggle switch — menu-style extras only
/// render checkmarks.
struct MenuBarView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var service: KanataService
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kanata").font(.headline)
                Spacer()
                Toggle("", isOn: service.enabledBinding(store: store, settings: settings))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(toggleDisabled)
            }
            Divider()

            Text("Profiles")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.profiles.isEmpty {
                Text("No .kbd profiles found — add some to ~/.config/kanata or import via Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.profiles) { profile in
                Button {
                    store.activeProfileName = profile.name
                    store.save()
                    // Preserve on/off state: picking a profile while Off only
                    // changes the selection; while On it switches live.
                    let ok = service.switchTo(profile: profile)
                    if ok, service.isRunning {
                        settings.kanataEnabled = true
                    }
                } label: {
                    HStack {
                        if profile.name == store.activeProfileName {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: "checkmark").opacity(0)
                        }
                        Text(profile.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }

            Divider()

            Button("Refresh status") { service.refresh() }
                .buttonStyle(.plain)
            SettingsLink { Text("Settings…") }
                .buttonStyle(.plain)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit")
                    Spacer()
                    Text("⌘Q")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)

            if let err = service.lastError, !err.isEmpty {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Toggle

    private var toggleDisabled: Bool {
        if case .unknown = service.status { return true }
        return false
    }
}
