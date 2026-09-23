import SwiftUI

struct InstallerWizardView: View {
    @StateObject private var installer = PrivilegedInstaller()
    @State private var kanataVersion = "v1.10.1"
    @State private var driverVersion = "v8.0.0"
    @State private var checks: [(name: String, ok: Bool, hint: String)] = PrivilegedInstaller.preflight()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("kanata-gui-mac setup").font(.title2).bold()
            Text("Installs kanata + Karabiner driver + root LaunchDaemon so kanata starts at login with no password prompt afterwards. Admin password is asked exactly once.")
                .font(.callout).foregroundStyle(.secondary)

            ForEach(checks.indices, id: \.self) { i in
                HStack {
                    Image(systemName: checks[i].ok ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(checks[i].ok ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(checks[i].name).font(.body)
                        Text(checks[i].hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                TextField("kanata version", text: $kanataVersion).frame(width: 110)
                TextField("driver version", text: $driverVersion).frame(width: 110)
                Button("Re-check") { checks = PrivilegedInstaller.preflight() }
            }.font(.callout)

            Button(installer.isRunning ? "Installing…" : "Install everything (asks admin password once)") {
                installer.runInstaller(kanataVersion: kanataVersion, driverVersion: driverVersion)
            }
            .buttonStyle(.borderedProminent)
            .disabled(installer.isRunning)

            ScrollView { Text(installer.log).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: 160)
                .border(Color.secondary.opacity(0.3))

            Text("After install: approve the driver in System Settings → General → Login Items & Extensions → Driver Extensions, then grant Input Monitoring + Accessibility to /usr/local/bin/kanata.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 560)
    }
}

struct SettingsView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var service: KanataService
    @State private var showingImporter = false
    @State private var importError: String?

    var body: some View {
        TabView {
            profilesTab.tabItem { Label("Profiles", systemImage: "keyboard") }
            InstallerWizardView().tabItem { Label("Setup", systemImage: "gearshape") }
        }
        .padding(16).frame(width: 600, height: 480)
    }

    private var profilesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profiles are .kbd files stored in ~/Library/Application Support/kanata-gui/profiles/. Selecting one rewrites the root daemon and restarts kanata.")
                .font(.callout).foregroundStyle(.secondary)
            List(store.profiles) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Text(p.configPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if p.name == store.activeProfileName { Image(systemName: "checkmark") }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    store.activeProfileName = p.name; store.save()
                    _ = service.switchTo(profile: p)
                }
            }
            HStack {
                Button("Import .kbd…") { showingImporter = true }
                if let err = importError { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .padding(8)
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
