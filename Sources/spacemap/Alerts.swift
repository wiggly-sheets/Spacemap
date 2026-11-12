import AppKit

protocol AlertsService {
    func showYabaiAlert()
    func showYabaiUntrustedAlert(detail: String, refusing: Bool)
    func isMRUSpacesEnabled() -> Bool
    func showMRUAlert()
    func showSeparateSpacesAlert()
}

final class AlertsServiceImpl: AlertsService {
    private let process: ProcessProtocol
    private let workspace: WorkspaceProtocol

    init(process: ProcessProtocol = Process(), workspace: WorkspaceProtocol = NSWorkspace.shared as WorkspaceProtocol) {
        self.process = process
        self.workspace = workspace
    }

    func showYabaiAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("yabai is not running", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap requires yabai to be running. Please start yabai and relaunch Spacemap. See https://github.com/koekeishiya/yabai for installation instructions.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open yabai", comment: ""))

        let response = present(alert)
        if response == .alertSecondButtonReturn {
            // Fixed allowlist destination — never open a computed URL here.
            if let url = URL(string: "https://github.com/koekeishiya/yabai"),
               url.scheme == "https", url.host == "github.com" {
                _ = workspace.open(url)
            }
        }
        NSApp.terminate(nil)
    }

    func showYabaiUntrustedAlert(detail: String, refusing: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("yabai binary is untrusted", comment: "")
        let action = refusing
            ? "Spacemap is refusing to run it (refuseUntrustedYabai is set)."
            : "Spacemap will still run it, but verify your install source."
        alert.informativeText = "\(detail). \(action)"
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open yabai", comment: ""))
        let response = present(alert)
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/koekeishiya/yabai"),
               url.scheme == "https", url.host == "github.com" {
                _ = workspace.open(url)
            }
        }
    }

    func isMRUSpacesEnabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["read", "com.apple.dock", "mru-spaces"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return false
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    func showMRUAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Spaces Auto-Rearrange Enabled", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs this disabled for stable grid layout. Spaces must stay in a fixed order or the grid becomes unreliable.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Leave as Is", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Fix It", comment: ""))

        let response = present(alert)
        if response == .alertSecondButtonReturn {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            task.arguments = ["write", "com.apple.dock", "mru-spaces", "-bool", "false"]
            try? task.run()
            task.waitUntilExit()
            let dock = Process()
            dock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            dock.arguments = ["Dock"]
            try? dock.run()
        }
    }

    func showSeparateSpacesAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Displays Have Separate Spaces Disabled", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs Displays have separate Spaces enabled to show and navigate each monitor independently. Enable it in System Settings, then log out and back in before using multi-monitor HUD modes.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Leave as Is", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open System Settings", comment: ""))

        if present(alert) == .alertSecondButtonReturn {
            _ = workspace.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    /// Temporarily regular only when needed, then restore the previous policy.
    /// If a Settings window is open, demoting to `.prohibited` would hide it,
    /// so `shouldRestoreActivationPolicy` vetoes the restore in that case.
    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let previous = NSApp.activationPolicy()
        if previous != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()

        let hasVisibleKeyWindow = (NSApp.keyWindow?.isVisible ?? false)
            || (NSApp.mainWindow?.isVisible ?? false)
        if ApplicationLifecycleService.shouldRestoreActivationPolicy(
            previous: previous,
            hasVisibleKeyWindow: hasVisibleKeyWindow
        ) {
            NSApp.setActivationPolicy(previous)
        }
        return response
    }
}

typealias Alerts = AlertsServiceImpl
