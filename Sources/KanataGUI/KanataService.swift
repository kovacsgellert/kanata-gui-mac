import Foundation
import SwiftUI

/// Runs shell commands. Privileged operations go through `sudo -n` so the
/// menu-bar app never prompts after the one-time installer step, which drops
/// a narrow NOPASSWD sudoers file (see Resources/kanata-gui.sudoers).
enum Shell {
    @discardableResult
    static func run(_ args: [String]) -> (code: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch {
            return (1, "", error.localizedDescription)
        }
        p.waitUntilExit()
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, o, e)
    }

    static func runPrivileged(_ args: [String]) -> (code: Int32, out: String, err: String) {
        run(["sudo", "-n"] + args)
    }
}

/// Manages the root LaunchDaemon that runs kanata.
///
/// Why a LaunchDaemon and not a child process (like kanata-tray does)?
/// On macOS kanata MUST run as root: the Karabiner VirtualHIDDevice daemon
/// exposes IPC under /Library/Application Support/org.pqrs/tmp/rootonly/,
/// readable only by root. A user-space tray app therefore cannot spawn kanata
/// directly. Instead the GUI (unprivileged) edits which config the system
/// daemon points at, then kickstarts it via passwordless sudo.
@MainActor
final class KanataService: ObservableObject {
    @Published var status: KanataStatus = .unknown
    @Published var lastError: String?

    /// Whether kanata is currently running (drives the On/Off toggle).
    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    /// Shared binding for the On/Off toggle, used by both the menu-bar panel
    /// and Settings → General so they can never disagree.
    func enabledBinding(store: ProfileStore, settings: AppSettings) -> Binding<Bool> {
        Binding(
            get: { self.isRunning },
            set: { wantOn in
                if wantOn {
                    guard let profile = store.profile(named: store.activeProfileName)
                        ?? store.profiles.first
                    else {
                        self.lastError = "No profile selected — import a .kbd profile first."
                        return
                    }
                    if self.setEnabled(true, profile: profile) {
                        settings.kanataEnabled = true
                        store.activeProfileName = profile.name
                        store.save()
                    } else {
                        settings.kanataEnabled = false
                    }
                } else {
                    if self.setEnabled(false, profile: nil) {
                        settings.kanataEnabled = false
                    }
                }
            }
        )
    }

    private func switchScriptPath() -> String {
        // Prefer the installed copy: it is the only path covered by the
        // passwordless sudoers grant. The bundled/dev copies are fallbacks
        // for pre-install development (they will prompt for a password).
        if FileManager.default.fileExists(atPath: KanataConstants.installedSwitchScript) {
            return KanataConstants.installedSwitchScript
        }
        // Shipped .app layout: Contents/Resources/Scripts/switch-profile.sh.
        let bundledScripts = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/Scripts/switch-profile.sh").path
        if FileManager.default.fileExists(atPath: bundledScripts) {
            return bundledScripts
        }
        let bundled = Bundle.main.url(forResource: "switch-profile", withExtension: "sh")
        if let h = bundled, FileManager.default.fileExists(atPath: h.path) {
            return h.path
        }
        // Dev fallback: repo Scripts/ dir next to the built binary.
        return "./Scripts/switch-profile.sh"
    }

    func refresh() {
        // `launchctl print system/…` needs root; use the passwordless sudoers
        // grant when available, falling back to a plain call in dev.
        var r = Shell.runPrivileged(["/bin/launchctl", "print", "system/\(KanataConstants.daemonLabel)"])
        if r.code != 0 {
            r = Shell.run(["launchctl", "print", "system/\(KanataConstants.daemonLabel)"])
        }
        if r.code == 0, r.out.contains("state = running") {
            status = .running(profile: nil)
        } else if r.code == 0 {
            status = .stopped
        } else {
            status = .stopped
        }
    }

    /// Enable/disable kanata on demand (the menu-bar On/Off toggle).
    /// - On requires a profile: validates with `kanata --check`, rewrites the
    ///   daemon plist (config + RunAtLoad/KeepAlive=true) and bootstraps it.
    /// - Off keeps the config but sets RunAtLoad/KeepAlive=false and bootouts,
    ///   so kanata stays stopped across reboots until toggled On again.
    func setEnabled(_ enabled: Bool, profile: KanataProfile?) -> Bool {
        let scriptPath = switchScriptPath()
        if enabled {
            guard let profile else {
                lastError = "No profile selected — import a .kbd profile first."
                return false
            }
            return switchTo(profile: profile, enableDaemon: true)
        } else {
            let r = Shell.runPrivileged(["/bin/sh", scriptPath, "--disable"])
            guard r.code == 0 else {
                lastError = "Disable failed (is the sudoers entry installed?):\n\(r.err.isEmpty ? r.out : r.err)"
                status = .error(lastError ?? "disable failed")
                return false
            }
            lastError = nil
            refresh()
            return true
        }
    }

    /// Point the daemon at a new .kbd config.
    /// Preserves the current on/off state: picking a profile while Off only
    /// rewrites the config (stays stopped); while On it restarts with it.
    /// Requires the sudoers file installed by Scripts/install.sh.
    func switchTo(profile: KanataProfile, enableDaemon: Bool? = nil) -> Bool {
        // 1. Validate config as the current user (no sudo needed for --check).
        let check = Shell.run([KanataConstants.kanataBinaryPath, "--check", "-c", profile.configPath])
        guard check.code == 0 else {
            lastError = "Config check failed:\n\(check.err.isEmpty ? check.out : check.err)"
            status = .error(lastError ?? "check failed")
            return false
        }
        // 2. Rewrite daemon plist ProgramArguments via privileged helper script.
        let scriptPath = switchScriptPath()
        let wantOn = enableDaemon ?? isRunning
        let r = Shell.runPrivileged(["/bin/sh", scriptPath, profile.configPath, String(profile.tcpPort), wantOn ? "on" : "off"])
        guard r.code == 0 else {
            lastError = "Switch failed (is the sudoers entry installed?):\n\(r.err.isEmpty ? r.out : r.err)"
            status = .error(lastError ?? "switch failed")
            return false
        }
        lastError = nil
        refresh()
        return true
    }

    func start() -> Bool {
        // Persist RunAtLoad=true via the helper so On survives reboots.
        let r = Shell.runPrivileged(["/bin/sh", switchScriptPath(), "--enable"])
        if r.code != 0 {
            // Fallback for older helper scripts without --enable: kickstart,
            // then bootstrap (re)loads it after a bootout/stop or fresh install.
            var f = Shell.runPrivileged(["/bin/launchctl", "kickstart", "-k", "system/\(KanataConstants.daemonLabel)"])
            if f.code != 0 {
                f = Shell.runPrivileged(["/bin/launchctl", "bootstrap", "system", KanataConstants.daemonPlistPath])
            }
            if f.code != 0 { lastError = f.err.isEmpty ? f.out : f.err; return false }
        }
        lastError = nil
        refresh(); return true
    }

    func stop() -> Bool {
        // Persist RunAtLoad=false via the helper so Off survives reboots.
        let r = Shell.runPrivileged(["/bin/sh", switchScriptPath(), "--disable"])
        if r.code != 0 {
            let f = Shell.runPrivileged(["/bin/launchctl", "bootout", "system/\(KanataConstants.daemonLabel)"])
            // bootout returns non-zero when already stopped; treat as success.
            refresh(); return f.code == 0 || f.err.contains("No such process")
        }
        lastError = nil
        refresh(); return true
    }
}
