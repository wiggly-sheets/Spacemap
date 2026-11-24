import AppKit
import ServiceManagement
import Sparkle

extension CLIToolsService {
    @discardableResult
    func showFirstLaunchLaunchAtLoginPrompt() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Launch at Login?", comment: "")
        alert.informativeText = NSLocalizedString("Would you like Spacemap to start automatically when you log in?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("No", comment: ""))

        let response = presentAlert(alert)
        if response == .alertFirstButtonReturn {
            return setLoginAtLogin(enabled: true)
        }
        return true
    }

    /// Returns false when the system rejected the request or did not reach the
    /// expected status, so callers can avoid persisting a "asked" flag.
    @discardableResult
    func setLoginAtLogin(enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            presentLaunchAtLoginFailure(enabled: enabled, detail: error.localizedDescription)
            return false
        }

        guard Self.launchAtLoginSucceeded(enabled: enabled, status: service.status) else {
            presentLaunchAtLoginFailure(enabled: enabled, detail: nil)
            return false
        }
        if Self.launchAtLoginNeedsApproval(enabled: enabled, status: service.status) {
            presentLaunchAtLoginApprovalNote()
        }
        return true
    }

    static func launchAtLoginSucceeded(enabled: Bool, status: SMAppService.Status) -> Bool {
        if enabled {
            // requiresApproval is the normal pending state for a newly
            // registered login item; persisting the answer prevents a prompt
            // loop while macOS waits for the user.
            return status == .enabled || status == .requiresApproval
        }
        return status != .enabled
    }

    static func launchAtLoginNeedsApproval(enabled: Bool, status: SMAppService.Status) -> Bool {
        enabled && status == .requiresApproval
    }

    func presentLaunchAtLoginApprovalNote() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Approve Launch at Login", comment: "")
        alert.informativeText = NSLocalizedString("macOS is waiting for approval. Enable Spacemap in System Settings > General > Login Items.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        presentAlert(alert)
    }

    func presentLaunchAtLoginFailure(enabled: Bool, detail: String?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = enabled
            ? NSLocalizedString("Couldn’t Enable Launch at Login", comment: "")
            : NSLocalizedString("Couldn’t Disable Launch at Login", comment: "")
        alert.informativeText = detail
            ?? NSLocalizedString("macOS did not report the expected login item status. Check System Settings > General > Login Items.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        presentAlert(alert)
    }

    static func launchAtLoginIsEnabled(status: SMAppService.Status) -> Bool {
        // requiresApproval is a pending-enabled state; toggling should offer
        // "disable", not register again.
        status == .enabled || status == .requiresApproval
    }

    func toggleLoginAtLogin() {
        setLoginAtLogin(enabled: !Self.launchAtLoginIsEnabled(status: SMAppService.mainApp.status))
    }
}
