import AppKit
import ServiceManagement

class CLIToolsHandler {
    private let cliSymlinkPath = "/usr/local/bin/spacemap"
    private let cliExecutablePath = "/Applications/Spacemap.app/Contents/MacOS/Spacemap"
    private let manPageSymlinkPath = "/usr/local/share/man/man1/spacemap.1"
    private let manPagePath = "/Applications/Spacemap.app/Contents/Resources/spacemap.1"

    private let onUpdateSparkleConfig: (UpdateMode) -> Void

    init(onUpdateSparkleConfig: @escaping (UpdateMode) -> Void) {
        self.onUpdateSparkleConfig = onUpdateSparkleConfig
    }

    func checkApplicationLocation() {
        let appPath = Bundle.main.bundleURL.path
        let applicationsPath = "/Applications"
        let isInApplications = appPath.hasPrefix(applicationsPath)

        let defaults = UserDefaults.standard
        let hasAskedLaunchAtLogin = defaults.bool(forKey: "HasAskedLaunchAtLogin")

        if !isInApplications {
            showMoveToApplicationsDialog()
        }

        if !hasAskedLaunchAtLogin {
            showFirstLaunchLaunchAtLoginPrompt()
            defaults.set(true, forKey: "HasAskedLaunchAtLogin")
        }

        let hasAskedUpdate = defaults.bool(forKey: "HasAskedUpdatePreference")
        if !hasAskedUpdate {
            showFirstLaunchUpdatePreferencePrompt()
            defaults.set(true, forKey: "HasAskedUpdatePreference")
        }
    }

    func showMoveToApplicationsDialog() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Move Spacemap to Applications?", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap should be run from the Applications folder for best performance. Would you like to move it there now?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Move to Applications", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            moveToApplications()
        }
    }

    func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("Moved to Applications", comment: "")
            alert.informativeText = NSLocalizedString("Spacemap has been copied to the Applications folder. Please quit and relaunch from there.", comment: "")
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to move", comment: "")
            alert.informativeText = String(format: NSLocalizedString("Could not move Spacemap to Applications: %@", comment: ""), error.localizedDescription)
            alert.runModal()
        }
    }

    func showFirstLaunchLaunchAtLoginPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Launch at Login?", comment: "")
        alert.informativeText = NSLocalizedString("Would you like Spacemap to start automatically when you log in?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("No", comment: ""))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            setLoginAtLogin(enabled: true)
        }
    }

    func showFirstLaunchUpdatePreferencePrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Automatic Updates?", comment: "")
        alert.informativeText = NSLocalizedString("How would you like Spacemap to check for updates?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Auto (Download & Install)", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Notify (Check & Prompt)", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Off", comment: ""))

        let response = alert.runModal()
        let updateMode: UpdateMode
        switch response {
        case .alertFirstButtonReturn:
            updateMode = .auto
        case .alertSecondButtonReturn:
            updateMode = .notify
        default:
            updateMode = .off
        }

        var config = Config.load()
        config.updateMode = updateMode
        Config.saveConfig(config)
        onUpdateSparkleConfig(updateMode)
    }

    func setLoginAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let actionString = enabled ? "enable" : "disable"
            print("Failed to \(actionString) launch at login: \(error)")
        }
    }

    func ensureCommandLineTools(
        allowAuthorizationPrompt: Bool,
        showSuccessAlert: Bool = false,
        forceAuthorizationPrompt: Bool = false
    ) {
        let cliResult = CLISymlinkInstaller.install(
            symlinkPath: cliSymlinkPath,
            targetPath: cliExecutablePath
        )
        let manPageResult = CLISymlinkInstaller.install(
            symlinkPath: manPageSymlinkPath,
            targetPath: manPagePath,
            targetMustBeExecutable: false
        )
        let results = [cliResult, manPageResult]

        if results.contains(.authorizationRequired) {
            guard allowAuthorizationPrompt else {
                print("Spacemap: administrator authorization is required to install CLI documentation links")
                return
            }
            let defaults = UserDefaults.standard
            let authorizationPromptKey = "HasAskedCLIAndManPageInstallAuthorization"
            if forceAuthorizationPrompt || !defaults.bool(forKey: authorizationPromptKey) {
                defaults.set(true, forKey: authorizationPromptKey)
                promptForCLIInstallAuthorization()
            }
            return
        }

        if cliResult == .targetUnavailable {
            print("Spacemap: CLI target is unavailable at \(cliExecutablePath)")
        } else if cliResult == .conflictingItem {
            print("Spacemap: preserving existing item at \(cliSymlinkPath)")
        } else if cliResult == .failed {
            print("Spacemap: failed to create CLI symlink at \(cliSymlinkPath)")
        }

        if manPageResult == .targetUnavailable {
            print("Spacemap: man page target is unavailable at \(manPagePath)")
        } else if manPageResult == .conflictingItem {
            print("Spacemap: preserving existing item at \(manPageSymlinkPath)")
        } else if manPageResult == .failed {
            print("Spacemap: failed to create man page symlink at \(manPageSymlinkPath)")
        }

        guard showSuccessAlert else { return }
        if results.contains(.conflictingItem) {
            showCLIInstallAlert(
                style: .warning,
                message: NSLocalizedString("Command-Line Tools Partially Installed", comment: ""),
                information: NSLocalizedString("Spacemap installed available links but preserved an unrelated item at a destination path.", comment: "")
            )
        } else if results.contains(.failed) || results.contains(.targetUnavailable) {
            showCLIInstallAlert(
                style: .critical,
                message: NSLocalizedString("Command-Line Tools Not Installed", comment: ""),
                information: NSLocalizedString("Spacemap could not install the command-line tool and manual page. You can try again from the menu bar.", comment: "")
            )
        } else {
            showCLIInstallAlert(
                style: .informational,
                message: NSLocalizedString("Command-Line Tools Ready", comment: ""),
                information: NSLocalizedString("You can now use `spacemap` and `man spacemap` from Terminal.", comment: "")
            )
        }
    }

    func promptForCLIInstallAuthorization() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Install Command-Line Tools?", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs administrator permission to link its command and manual page into /usr/local. This does not change your shell configuration.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Install", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Not Now", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            installCLISymlinkWithAuthorization()
        }
    }

    func installCLISymlinkWithAuthorization() {
        let command = "/bin/mkdir -p /usr/local/bin /usr/local/share/man/man1; if [ -x /Applications/Spacemap.app/Contents/MacOS/Spacemap ] && [ ! -e /usr/local/bin/spacemap ] && [ ! -L /usr/local/bin/spacemap ]; then /bin/ln -s /Applications/Spacemap.app/Contents/MacOS/Spacemap /usr/local/bin/spacemap; fi; if [ -f /Applications/Spacemap.app/Contents/Resources/spacemap.1 ] && [ ! -e /usr/local/share/man/man1/spacemap.1 ] && [ ! -L /usr/local/share/man/man1/spacemap.1 ]; then /bin/ln -s /Applications/Spacemap.app/Contents/Resources/spacemap.1 /usr/local/share/man/man1/spacemap.1; fi"
        let source = "do shell script \"\(command)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)

        if let error {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int
            if errorNumber != -128 {
                print("Spacemap: authorized command-line tools installation failed: \(error)")
                showCLIInstallAlert(
                    style: .critical,
                    message: NSLocalizedString("Command-Line Tools Not Installed", comment: ""),
                    information: NSLocalizedString("Spacemap could not install the command-line tool and manual page. You can try again from the menu bar.", comment: "")
                )
            }
            return
        }

        ensureCommandLineTools(allowAuthorizationPrompt: false, showSuccessAlert: true)
    }

    func showCLIInstallAlert(style: NSAlert.Style, message: String, information: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = information
        alert.runModal()
    }
}
