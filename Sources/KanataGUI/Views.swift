import SwiftUI

struct InstallerWizardView: View {
    @StateObject private var installer = PrivilegedInstaller()
    @State private var kanataVersion = "v1.12.0"
    @State private var driverVersion = "v6.2.0"
    @State private var checks: [(name: String, ok: Bool, hint: String)] = PrivilegedInstaller.preflight()

    /// Explicit manual steps (Apple-mandated, per kanata's docs/setup-macos.md).
    /// Nothing here is granted to Karabiner: the driver is approved via its
    /// Driver Extension entry, while BOTH privacy grants go to the kanata
    /// binary itself.
    private var manualStepsHint: String {
        let bin = PrivilegedInstaller.locateKanata() ?? "/usr/local/bin/kanata"
        return """
        Manual steps Apple does not allow automating (one time):
        1. Driver: System Settings → General → Login Items & Extensions → Driver Extensions → enable org.pqrs.Karabiner-DriverKit-VirtualHIDDevice (reboot if asked).
        2. Input Monitoring: System Settings → Privacy & Security → Input Monitoring → + → add \(bin) (press ⇧⌘G in the picker to paste the path).
        3. Accessibility: same pane → Accessibility → add \(bin) (or run `\(bin) --macos-request-permissions`).

        Re-installing or upgrading kanata (incl. `brew upgrade kanata`) replaces the binary and can silently invalidate steps 2–3 — toggle them off/on again if keys stop responding.
        """
    }

    var body: some View {
        Form {
            Section {
                Text("kanata-gui-mac setup").font(.title2).bold()
                Text("Installs kanata + Karabiner driver + root LaunchDaemon (inactive by default — flip On in the menu to start kanata) so the menu-bar app starts at login with no password prompt afterwards. Admin password is asked exactly once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                ForEach(checks.indices, id: \.self) { i in
                    HStack {
                        Image(systemName: checks[i].ok ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checks[i].ok ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(checks[i].name).font(.body)
                            Text(checks[i].hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Versions") {
                LabeledContent("kanata version") {
                    TextField("", text: $kanataVersion, prompt: Text("v1.12.0"))
                        .labelsHidden()
                        .frame(width: 110)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("driver version") {
                    TextField("", text: $driverVersion, prompt: Text("v6.2.0"))
                        .labelsHidden()
                        .frame(width: 110)
                        .multilineTextAlignment(.trailing)
                }
                Button("Re-check") { checks = PrivilegedInstaller.preflight() }
            }

            Section {
                Button(installer.isRunning ? "Installing…" : "Install everything (asks admin password once)") {
                    installer.runInstaller(kanataVersion: kanataVersion, driverVersion: driverVersion)
                }
                .buttonStyle(.borderedProminent)
                .disabled(installer.isRunning)

                ScrollView { Text(installer.log).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.3))

                Text(manualStepsHint)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var service: KanataService
    @ObservedObject var settings: AppSettings
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var loginError: String?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            profilesTab.tabItem { Label("Profiles", systemImage: "keyboard") }
            InstallerWizardView().tabItem { Label("Setup", systemImage: "wrench") }
        }
        .padding(16).frame(width: 600, height: 480)
    }

    private var generalTab: some View {
        Form {
            Section("Login") {
                Toggle("Start KanataGUI at login", isOn: Binding(
                    get: { settings.startAtLogin },
                    set: { v in
                        settings.startAtLogin = v
                        if let err = LoginItemManager.setRegistered(v) {
                            loginError = err.localizedDescription
                        } else {
                            loginError = nil
                        }
                    }
                ))
                .toggleStyle(.switch)
                if let err = loginError {
                    Text("Login item failed: \(err)").font(.caption).foregroundStyle(.red)
                        .help("Registering a login item requires a bundled .app (it no-ops under `swift run`).")
                } else {
                    Text(LoginItemManager.isRegistered ? "Login item: enabled" : "Login item: disabled")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Kanata") {
                Toggle("Kanata", isOn: service.enabledBinding(store: store, settings: settings))
                    .toggleStyle(.switch)
                Text("Current state: \(service.isRunning ? "on" : "off")\(store.activeProfileName.map { " (\($0))" } ?? "")")
                    .font(.callout)
                Text("Kanata starts off by default. Flip this On to activate it on demand with the selected profile (same switch as at the top of the menu-bar dropdown). Turning it Off stops the root daemon and it stays off across reboots until you turn it On again.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Button("Quit KanataGUI") { NSApplication.shared.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }

    private var profilesTab: some View {
        Form {
            Section {
                Text("Profiles auto-detected from $XDG_CONFIG_HOME/kanata or ~/.config/kanata, plus files imported below. Selecting one rewrites the root daemon and restarts kanata.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                if store.profiles.isEmpty {
                    Text("No .kbd profiles found — import one below.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(store.profiles) { p in
                    HStack {
                        Button {
                            store.activeProfileName = p.name; store.save()
                            _ = service.switchTo(profile: p)
                        } label: {
                            HStack {
                                Text(p.name)
                                if p.source == .autoDetected {
                                    Text("auto").font(.caption).foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15)).cornerRadius(4)
                                        .help(p.configPath)
                                }
                                Spacer()
                                Text(p.configPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                if p.name == store.activeProfileName { Image(systemName: "checkmark") }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            store.removeProfile(p)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from KanataGUI (file is kept)")
                    }
                    .contextMenu {
                        Button("Remove from KanataGUI", role: .destructive) {
                            store.removeProfile(p)
                        }
                    }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Removing a profile only hides it in KanataGUI — the file stays on disk. Import it again to restore it.")
            }

            Section {
                HStack {
                    Button("Import .kbd…") { showingImporter = true }
                    Button("Rescan") { store.rescan() }
                        .help("Re-scan ~/.config/kanata (or $XDG_CONFIG_HOME/kanata) for new .kbd files")
                    if let err = importError { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.init(filenameExtension: "kbd") ?? .plainText]) { result in
            switch result {
            case .success(let url):
                do {
                    _ = url.startAccessingSecurityScopedResource()
                    try store.importProfile(from: url)
                    url.stopAccessingSecurityScopedResource()
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let e):
                importError = e.localizedDescription
            }
        }
    }
}
