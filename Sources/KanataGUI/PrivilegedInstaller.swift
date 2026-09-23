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
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/install.sh").path,
            "./Scripts/install.sh",
            "Scripts/install.sh",
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    func runInstaller(kanataVersion: String = "v1.10.1", driverVersion: String = "v8.0.0") {
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

    /// Non-privileged preflight checks shown in the installer wizard.
    static func preflight() -> [(name: String, ok: Bool, hint: String)] {
        let fm = FileManager.default
        let kanata = fm.fileExists(atPath: KanataConstants.kanataBinaryPath)
        let daemon = fm.fileExists(atPath: KanataConstants.daemonPlistPath)
        let sudoers = fm.fileExists(atPath: "/etc/sudoers.d/kanata-gui")
        let vhid = fm.fileExists(atPath: "/Applications/.Karabiner-VirtualHIDDevice-Manager.app")
        return [
            ("kanata binary (\(KanataConstants.kanataBinaryPath))", kanata, kanata ? "found" : "will be downloaded from GitHub releases"),
            ("Karabiner VirtualHIDDevice driver", vhid, vhid ? "found" : "installer will download driver pkg v8.0.0 — you approve the system extension"),
            ("LaunchDaemon (\(KanataConstants.daemonLabel))", daemon, daemon ? "installed, starts at boot as root" : "installer will create it (starts kanata at boot, no password)"),
            ("Passwordless control (/etc/sudoers.d/kanata-gui)", sudoers, sudoers ? "installed" : "installer adds NOPASSWD for launchctl kickstart/bootout + switch script only"),
        ]
    }
}
