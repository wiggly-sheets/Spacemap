import AppKit
import ServiceManagement
import Sparkle

final class CLIToolsService: CLIToolsHandling {
    private let cliSymlinkPath = "/usr/local/bin/spacemap"
    private let cliExecutablePath = "/Applications/Spacemap.app/Contents/MacOS/Spacemap"
    private let manPageSymlinkPath = "/usr/local/share/man/man1/spacemap.1"
    private let manPagePath = "/Applications/Spacemap.app/Contents/Resources/spacemap.1"

    private let onUpdateSparkleConfig: (UpdateMode) -> Void
    private let sparkleController: SPUStandardUpdaterController

    init(
        onUpdateSparkleConfig: @escaping (UpdateMode) -> Void,
        sparkleController: SPUStandardUpdaterController
    ) {
        self.onUpdateSparkleConfig = onUpdateSparkleConfig
        self.sparkleController = sparkleController
    }

    func checkApplicationLocation() {
        let appPath = Bundle.main.bundleURL.path
        let applicationsPath = "/Applications"
        let isInApplications = appPath.hasPrefix(applicationsPath)

        let defaults = UserDefaults.standard
        let hasAskedLaunchAtLogin = defaults.bool(forKey: "HasAskedLaunchAtLogin")
        let hasAskedUpdate = defaults.bool(forKey: "HasAskedUpdatePreference")

        guard !isInApplications || !hasAskedLaunchAtLogin || !hasAskedUpdate else { return }

        if !isInApplications {
            showMoveToApplicationsDialog()
        }

        if !hasAskedLaunchAtLogin {
            showFirstLaunchLaunchAtLoginPrompt()
            defaults.set(true, forKey: "HasAskedLaunchAtLogin")
        }

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

        let response = presentAlert(alert)
        if response == .alertFirstButtonReturn {
            moveToApplications()
        }
    }

    func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)

        guard verifyBundleSignature(at: source) else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to move", comment: "")
            alert.informativeText = NSLocalizedString("Spacemap could not verify its own code signature. The install was refused.", comment: "")
            presentAlert(alert)
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                // Never clobber a newer install (downgrade = attacker rollback).
                if Self.compareVersions(installedVersion(at: destination), bundleVersion(at: source)) != .orderedAscending {
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.messageText = NSLocalizedString("Already up to date", comment: "")
                    alert.informativeText = NSLocalizedString("The Applications copy is the same version or newer. Nothing was overwritten.", comment: "")
                    presentAlert(alert)
                    return
                }
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("Moved to Applications", comment: "")
            alert.informativeText = NSLocalizedString("Spacemap has been copied to the Applications folder. Please quit and relaunch from there.", comment: "")
            presentAlert(alert)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to move", comment: "")
            alert.informativeText = String(format: NSLocalizedString("Could not move Spacemap to Applications: %@", comment: ""), error.localizedDescription)
            presentAlert(alert)
        }
    }

    func showFirstLaunchLaunchAtLoginPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Launch at Login?", comment: "")
        alert.informativeText = NSLocalizedString("Would you like Spacemap to start automatically when you log in?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("No", comment: ""))

        let response = presentAlert(alert)
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

        let response = presentAlert(alert)
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

        if presentAlert(alert) == .alertFirstButtonReturn {
            installCLISymlinkWithAuthorization()
        }
    }

    /// Fixed allowlist script: mkdir/ln with absolute literal paths only, no
    /// user input interpolated. Proper long-term path is a privileged helper
    /// tool via SMJobBless; osascript admin prompt is the stopgap.
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
        presentAlert(alert)
    }

    @discardableResult
    private func presentAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let previousActivationPolicy = NSApp.activationPolicy()
        if previousActivationPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        defer {
            if previousActivationPolicy != .regular {
                NSApp.setActivationPolicy(previousActivationPolicy)
            }
        }
        return alert.runModal()
    }

    func installCommandLineTools() {
        ensureCommandLineTools(
            allowAuthorizationPrompt: true,
            showSuccessAlert: true,
            forceAuthorizationPrompt: true
        )
    }

    func restartApp() {
        // No shell: fixed argv, bundle path passed as one arg (spaces safe).
        // /bin/sleep holds the delay the old `sh -c "sleep 1 && open ..."`
        // provided; the opener fires from its termination handler.
        let bundlePath = Bundle.main.bundleURL.path
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["1"]
        sleeper.standardOutput = FileHandle.nullDevice
        sleeper.standardError = FileHandle.nullDevice
        sleeper.terminationHandler = { _ in
            let opener = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = [bundlePath, "--args", "--restarting"]
            opener.standardOutput = FileHandle.nullDevice
            opener.standardError = FileHandle.nullDevice
            try? opener.run()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        do {
            try sleeper.run()
        } catch {
            NSApp.terminate(nil)
        }
    }

    func toggleLoginAtLogin() {
        setLoginAtLogin(enabled: SMAppService.mainApp.status != .enabled)
    }

    private static func compareVersions(_ installed: String?, _ source: String?) -> ComparisonResult {
        (installed ?? "").compare(source ?? "", options: .numeric)
    }

    private func installedVersion(at url: URL) -> String? { bundleVersion(at: url) }

    private func bundleVersion(at url: URL) -> String? {
        Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func verifyBundleSignature(at url: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--verify", url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    func checkForUpdates() {
        sparkleController.checkForUpdates(nil)
    }
}
