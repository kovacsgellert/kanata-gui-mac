import Foundation

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

    func refresh() {
        let r = Shell.run(["launchctl", "print", "system/\(KanataConstants.daemonLabel)"])
        if r.code == 0, r.out.contains("state = running") {
            status = .running(profile: nil)
        } else if r.code == 0 {
            status = .stopped
        } else {
            status = .stopped
        }
    }

    /// Point the daemon at a new .kbd config and (re)start it. Requires the
    /// sudoers file installed by Scripts/install.sh.
    func switchTo(profile: KanataProfile) -> Bool {
        // 1. Validate config as the current user (no sudo needed for --check).
        let check = Shell.run([KanataConstants.kanataBinaryPath, "--check", "-c", profile.configPath])
        guard check.code == 0 else {
            lastError = "Config check failed:\n\(check.err.isEmpty ? check.out : check.err)"
            status = .error(lastError ?? "check failed")
            return false
        }
        // 2. Rewrite daemon plist ProgramArguments via privileged helper script.
        let bundled = Bundle.main.url(forResource: "switch-profile", withExtension: "sh")
        let scriptPath: String
        if let h = bundled, FileManager.default.fileExists(atPath: h.path) {
            scriptPath = h.path
        } else {
            // Dev fallback: repo Scripts/ dir next to the built binary.
            scriptPath = "./Scripts/switch-profile.sh"
        }
        let r = Shell.runPrivileged(["/bin/sh", scriptPath, profile.configPath, String(profile.tcpPort)])
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
        let r = Shell.runPrivileged(["/bin/launchctl", "kickstart", "-k", "system/\(KanataConstants.daemonLabel)"])
        if r.code != 0 { lastError = r.err.isEmpty ? r.out : r.err; return false }
        refresh(); return true
    }

    func stop() -> Bool {
        let r = Shell.runPrivileged(["/bin/launchctl", "bootout", "system/\(KanataConstants.daemonLabel)"])
        // bootout returns non-zero when already stopped; treat as success.
        refresh(); return r.code == 0 || r.err.contains("No such process")
    }
}
