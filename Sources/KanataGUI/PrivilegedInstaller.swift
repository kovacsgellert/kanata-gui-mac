import Foundation

/// One-time privileged setup. Prompts ONCE for an admin password via the
/// native macOS dialog (`osascript ... with administrator privileges`),
/// then runs Scripts/install.sh as root. After this, the menu-bar app and
/// the LaunchDaemon run passwordless.
@MainActor
final class PrivilegedInstaller: ObservableObject {
    @Published var isRunning = false
    @Published var log: String = ""
    @Published var lastExitCode: Int32?

    func locateInstallScript() -> String? {
        let candidates: [String?] = [
            Bundle.main.url(forResource: "install", withExtension: "sh")?.path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Scripts/install.sh").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/install.sh").path,
            "./Scripts/install.sh",
            "Scripts/install.sh",
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    func runInstaller(kanataVersion: String = "v1.12.0", driverVersion: String = "v6.2.0") {
        guard let script = locateInstallScript() else {
            log += "install.sh not found. Run from the repo root.\n"
            return
        }
        isRunning = true
        log += "$ install.sh (admin privileges requested once…)\n"
        Task.detached { [weak self] in
            let appleScript = "do shell script \"/bin/sh \(script) --kanata-version \(kanataVersion) --driver-version \(driverVersion)\" with administrator privileges"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", appleScript]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            do { try p.run() } catch {
                await MainActor.run { [weak self] in
                    self?.log += "Failed to launch osascript: \(error)\n"
                    self?.isRunning = false
                }
                return
            }
            p.waitUntilExit()
            let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            await MainActor.run { [weak self] in
                self?.log += o + e
                self?.lastExitCode = p.terminationStatus
                self?.isRunning = false
            }
        }
    }

    /// Locate the kanata binary (same order as the installer + KanataConstants).
    static func locateKanata() -> String? {
        let fm = FileManager.default
        for p in ["/usr/local/bin/kanata", "/opt/homebrew/bin/kanata"] where fm.isExecutableFile(atPath: p) {
            return p
        }
        let found = Shell.run(["sh", "-c", "command -v kanata"]).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !found.isEmpty, fm.isExecutableFile(atPath: found) {
            return found
        }
        return nil
    }

    /// Installed Karabiner VirtualHIDDevice driver version (same source as install.sh).
    static func installedDriverVersion() -> String? {
        let info = URL(fileURLWithPath: "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: info) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Non-privileged preflight checks shown in the installer wizard.
    static func preflight() -> [(name: String, ok: Bool, hint: String)] {
        let fm = FileManager.default
        let kanataPath = locateKanata()
        let kanata = kanataPath != nil
        let daemon = fm.fileExists(atPath: KanataConstants.daemonPlistPath)
        let sudoers = fm.fileExists(atPath: "/etc/sudoers.d/kanata-gui")
        let vhidPresent = fm.fileExists(atPath: "/Applications/.Karabiner-VirtualHIDDevice-Manager.app")
            || fm.fileExists(atPath: "/Applications/Karabiner-Elements.app")
        // kanata v1.12 speaks driver protocol 5, which only the v6 driver serves;
        // Karabiner-Elements bundles a newer (v8) one.
        let driverVersion = installedDriverVersion()
        let driverMatches = driverVersion.map { $0.hasPrefix("6.") } ?? true
        let vhid = vhidPresent && driverMatches
        let vhidHint: String
        if !vhidPresent {
            vhidHint = "installer will download driver pkg v6.2.0 — you approve the system extension"
        } else if let v = driverVersion, !driverMatches {
            vhidHint = "v\(v) installed, kanata needs v6.x — uninstall Karabiner-Elements / deactivate it first"
        } else {
            vhidHint = "found" + (driverVersion.map { " (v\($0))" } ?? "")
        }
        return [
            ("kanata binary" + (kanataPath.map { " (\($0))" } ?? ""), kanata, kanata ? "found" : "installer will add it via Homebrew (pinned versions via GitHub releases)"),
            ("Karabiner VirtualHIDDevice driver", vhid, vhidHint),
            ("LaunchDaemon (\(KanataConstants.daemonLabel))", daemon, daemon ? "installed, stays off until the menu-bar On toggle" : "installer will create it (inactive by default, On toggle starts it, no password)"),
            ("Passwordless control (/etc/sudoers.d/kanata-gui)", sudoers, sudoers ? "installed" : "installer adds NOPASSWD for launchctl kickstart/bootout + switch script only"),
        ]
    }
}
