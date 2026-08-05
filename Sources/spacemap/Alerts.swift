import AppKit

protocol AlertsService {
    func showYabaiAlert()
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("yabai is not running", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap requires yabai to be running. Please start yabai and relaunch Spacemap. See https://github.com/koekeishiya/yabai for installation instructions.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open yabai", comment: ""))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            workspace.open(URL(string: "https://github.com/koekeishiya/yabai")!)
        }
        NSApp.terminate(nil)
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Spaces Auto-Rearrange Enabled", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs this disabled for stable grid layout. Spaces must stay in a fixed order or the grid becomes unreliable.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Leave as Is", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Fix It", comment: ""))

        let response = alert.runModal()
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
        NSApp.setActivationPolicy(.prohibited)
    }

    func showSeparateSpacesAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Displays Have Separate Spaces Disabled", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs Displays have separate Spaces enabled to show and navigate each monitor independently. Enable it in System Settings, then log out and back in before using multi-monitor HUD modes.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Leave as Is", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open System Settings", comment: ""))

        if alert.runModal() == .alertSecondButtonReturn {
            workspace.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
        NSApp.setActivationPolicy(.prohibited)
    }
}

// Backward-compatible typealias for existing code that references `Alerts`
typealias Alerts = AlertsServiceImpl