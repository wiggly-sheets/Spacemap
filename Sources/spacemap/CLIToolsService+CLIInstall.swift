import AppKit
import ServiceManagement
import Sparkle

extension CLIToolsService {
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

    /// Fixed allowlist script: mkdir/ln only. The target paths are derived from
    /// the running bundle, validated, and shell-quoted rather than interpolated
    /// raw. Proper long-term path is a privileged helper tool via SMJobBless;
    /// osascript admin prompt is the stopgap.
    func installCLISymlinkWithAuthorization() {
        guard let command = Self.authorizationScript(cliPath: cliExecutablePath, manPagePath: manPagePath) else {
            showCLIInstallAlert(
                style: .critical,
                message: NSLocalizedString("Command-Line Tools Not Installed", comment: ""),
                information: NSLocalizedString("Spacemap could not validate its install paths. The command-line tools were not linked.", comment: "")
            )
            return
        }
        let source = Self.appleScriptSource(forShellCommand: command)
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

    static func cliTargetPath(bundleURL: URL, executableURL: URL?) -> String {
        if let executableURL {
            return executableURL.standardizedFileURL.path
        }
        return bundleURL.appendingPathComponent("Contents/MacOS/Spacemap").standardizedFileURL.path
    }

    static func manPageTargetPath(bundleURL: URL, resourceURL: URL?) -> String {
        if let resourceURL {
            return resourceURL.standardizedFileURL.path
        }
        return bundleURL.appendingPathComponent("Contents/Resources/spacemap.1").standardizedFileURL.path
    }

    /// Absolute path, no control characters or AppleScript-breaking characters;
    /// single quotes are escaped for the shell.
    static func shellQuotedPath(_ path: String) -> String? {
        // Check the original first: URL(fileURLWithPath:).standardizedFileURL
        // would otherwise turn a relative path into something absolute.
        guard path.hasPrefix("/") else { return nil }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.hasPrefix("/") else { return nil }
        guard !standardized.unicodeScalars.contains(where: {
            $0.value < 0x20 || $0 == "\"" || $0 == "\\"
        }) else { return nil }
        return "'" + standardized.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func authorizationScript(cliPath: String, manPagePath: String) -> String? {
        guard let cli = shellQuotedPath(cliPath),
              let manPage = shellQuotedPath(manPagePath) else { return nil }
        return "/bin/mkdir -p /usr/local/bin /usr/local/share/man/man1; "
            + "if [ -x \(cli) ] && [ ! -e /usr/local/bin/spacemap ] && [ ! -L /usr/local/bin/spacemap ]; then /bin/ln -s \(cli) /usr/local/bin/spacemap; fi; "
            + "if [ -f \(manPage) ] && [ ! -e /usr/local/share/man/man1/spacemap.1 ] && [ ! -L /usr/local/share/man/man1/spacemap.1 ]; then /bin/ln -s \(manPage) /usr/local/share/man/man1/spacemap.1; fi"
    }

    static func appleScriptSource(forShellCommand command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    func showCLIInstallAlert(style: NSAlert.Style, message: String, information: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = information
        presentAlert(alert)
    }

    @discardableResult
    func presentAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let previousActivationPolicy = NSApp.activationPolicy()
        if previousActivationPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()

        let hasVisibleKeyWindow = (NSApp.keyWindow?.isVisible ?? false)
            || (NSApp.mainWindow?.isVisible ?? false)
        if ApplicationLifecycleService.shouldRestoreActivationPolicy(
            previous: previousActivationPolicy,
            hasVisibleKeyWindow: hasVisibleKeyWindow
        ) {
            NSApp.setActivationPolicy(previousActivationPolicy)
        }
        return response
    }

    func installCommandLineTools() {
        ensureCommandLineTools(
            allowAuthorizationPrompt: true,
            showSuccessAlert: true,
            forceAuthorizationPrompt: true
        )
    }
}
