import AppKit
import ServiceManagement
import Sparkle

/// Detached relaunch helper. It polls the old PID and only then asks
/// LaunchServices to open the bundle, so the old instance is gone by the time
/// the new one starts. Values are positional argv entries, never interpolated
/// into the script, so bundle paths with spaces are safe.
struct AppRestartPlan: Equatable {
    let executablePath: String
    let arguments: [String]

    static func make(bundlePath: String, parentPID: Int32) -> AppRestartPlan {
        // Bound the wait: a zombie/reused PID must not strand the helper.
        // 50 × 0.2s = 10s, then open anyway.
        let script = "i=0; while kill -0 \"$1\" 2>/dev/null && [ \"$i\" -lt 50 ]; "
            + "do i=$((i + 1)); sleep 0.2; done; "
            + "exec /usr/bin/open \"$2\" --args --restarting"
        return AppRestartPlan(
            executablePath: "/bin/sh",
            arguments: ["-c", script, "spacemap-restart", "\(parentPID)", bundlePath]
        )
    }
}

final class CLIToolsService {
    private let cliSymlinkPath = "/usr/local/bin/spacemap"
    private let manPageSymlinkPath = "/usr/local/share/man/man1/spacemap.1"
    private let applicationsPath = "/Applications"

    private static let askedLaunchAtLoginKey = "HasAskedLaunchAtLogin"
    private static let askedUpdatePreferenceKey = "HasAskedUpdatePreference"
    private static let declinedMoveToApplicationsKey = "HasDeclinedMoveToApplications"
    private static var retainedRestartHelpers: [Process] = []

    private let onUpdateSparkleConfig: (UpdateMode) -> Void
    private let sparkleController: SPUStandardUpdaterController

    private var cliExecutablePath: String {
        Self.cliTargetPath(bundleURL: Bundle.main.bundleURL, executableURL: Bundle.main.executableURL)
    }

    private var manPagePath: String {
        Self.manPageTargetPath(
            bundleURL: Bundle.main.bundleURL,
            resourceURL: Bundle.main.url(forResource: "spacemap", withExtension: "1")
        )
    }

    init(
        onUpdateSparkleConfig: @escaping (UpdateMode) -> Void,
        sparkleController: SPUStandardUpdaterController
    ) {
        self.onUpdateSparkleConfig = onUpdateSparkleConfig
        self.sparkleController = sparkleController
    }

    func checkApplicationLocation() {
        let appPath = Bundle.main.bundleURL.path
        let defaults = UserDefaults.standard

        if Self.shouldPromptToMove(
            appPath: appPath,
            hasDeclined: defaults.bool(forKey: Self.declinedMoveToApplicationsKey),
            applicationsPath: applicationsPath
        ) {
            showMoveToApplicationsDialog()
        }

        if !defaults.bool(forKey: Self.askedLaunchAtLoginKey) {
            // Persist "asked" only when the user actually answered and the
            // system accepted the choice; a failed SMAppService call should be
            // retried on the next launch.
            if showFirstLaunchLaunchAtLoginPrompt() {
                defaults.set(true, forKey: Self.askedLaunchAtLoginKey)
            }
        }

        if !defaults.bool(forKey: Self.askedUpdatePreferenceKey) {
            showFirstLaunchUpdatePreferencePrompt()
            defaults.set(true, forKey: Self.askedUpdatePreferenceKey)
        }
    }

    /// Component-wise check: `/Applications-old/Spacemap.app` is not inside
    /// `/Applications`, while nested builds under it are.
    static func isInApplications(appPath: String, applicationsPath: String = "/Applications") -> Bool {
        let appComponents = URL(fileURLWithPath: appPath).standardizedFileURL.pathComponents
        let applicationsComponents = URL(fileURLWithPath: applicationsPath).standardizedFileURL.pathComponents
        guard appComponents.count > applicationsComponents.count else { return false }
        return Array(appComponents.prefix(applicationsComponents.count)) == applicationsComponents
    }

    static func shouldPromptToMove(
        appPath: String,
        hasDeclined: Bool,
        applicationsPath: String = "/Applications"
    ) -> Bool {
        !hasDeclined && !isInApplications(appPath: appPath, applicationsPath: applicationsPath)
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
        } else {
            // Remember a decline so an app deliberately run from Downloads
            // does not prompt on every launch.
            UserDefaults.standard.set(true, forKey: Self.declinedMoveToApplicationsKey)
        }
    }

    private enum MoveToApplicationsResult {
        case moved
        case alreadyUpToDate
        case signatureFailed
        case failed(Error)
    }

    func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: applicationsPath).appendingPathComponent(source.lastPathComponent)

        // codesign and the bundle copy both block; keep them off the main
        // thread and only present the outcome on the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.performMoveToApplications(source: source, destination: destination)
            DispatchQueue.main.async {
                self.presentMoveToApplicationsResult(result)
            }
        }
    }

    private func performMoveToApplications(source: URL, destination: URL) -> MoveToApplicationsResult {
        guard verifyBundleSignature(at: source) else {
            return .signatureFailed
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            // Never clobber a newer install (downgrade = attacker rollback).
            if Self.compareVersions(installedVersion(at: destination), bundleVersion(at: source)) != .orderedAscending {
                return .alreadyUpToDate
            }
        }

        do {
            try Self.copyBundleAtomically(source: source, destination: destination)
            return .moved
        } catch {
            return .failed(error)
        }
    }

    /// Stage beside the destination, then rename/replace so the destination is
    /// never absent while a copy is in progress.
    static func copyBundleAtomically(
        source: URL,
        destination: URL,
        fileManager: FileManager = .default
    ) throws {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.copyItem(at: source, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    private func presentMoveToApplicationsResult(_ result: MoveToApplicationsResult) {
        switch result {
        case .moved:
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("Moved to Applications", comment: "")
            alert.informativeText = NSLocalizedString("Spacemap has been copied to the Applications folder. Please quit and relaunch from there.", comment: "")
            presentAlert(alert)
        case .alreadyUpToDate:
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("Already up to date", comment: "")
            alert.informativeText = NSLocalizedString("The Applications copy is the same version or newer. Nothing was overwritten.", comment: "")
            presentAlert(alert)
        case .signatureFailed:
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to move", comment: "")
            alert.informativeText = NSLocalizedString("Spacemap could not verify its own code signature. The install was refused.", comment: "")
            presentAlert(alert)
        case .failed(let error):
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to move", comment: "")
            alert.informativeText = String(format: NSLocalizedString("Could not move Spacemap to Applications: %@", comment: ""), error.localizedDescription)
            presentAlert(alert)
        }
    }

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

        AppConfig.updateConfig { $0.updateMode = updateMode }
        onUpdateSparkleConfig(updateMode)
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

    private func presentLaunchAtLoginApprovalNote() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Approve Launch at Login", comment: "")
        alert.informativeText = NSLocalizedString("macOS is waiting for approval. Enable Spacemap in System Settings > General > Login Items.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        presentAlert(alert)
    }

    private func presentLaunchAtLoginFailure(enabled: Bool, detail: String?) {
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
    private func presentAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
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

    func restartApp() {
        let plan = AppRestartPlan.make(
            bundlePath: Bundle.main.bundleURL.path,
            parentPID: ProcessInfo.processInfo.processIdentifier
        )
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: plan.executablePath)
        helper.arguments = plan.arguments
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
            // The helper waits for this PID to disappear before opening the
            // bundle, so retain it until process exit.
            Self.retainedRestartHelpers.append(helper)
        } catch {
            NSLog("spacemap/restart: helper launch failed — \(error.localizedDescription)")
        }
        // Terminate first; opening the bundle while the app is still running
        // makes LaunchServices just re-activate the old instance.
        NSApp.terminate(nil)
    }

    static func launchAtLoginIsEnabled(status: SMAppService.Status) -> Bool {
        // requiresApproval is a pending-enabled state; toggling should offer
        // "disable", not register again.
        status == .enabled || status == .requiresApproval
    }

    func toggleLoginAtLogin() {
        setLoginAtLogin(enabled: !Self.launchAtLoginIsEnabled(status: SMAppService.mainApp.status))
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
