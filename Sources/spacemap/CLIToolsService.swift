import AppKit
import ServiceManagement
import Sparkle

/// Handles CLI tools-related operations.
final class CLIToolsService: CLIToolsHandling {
    private let onUpdateSparkleConfig: (UpdateMode) -> Void
    private let sparkleController: SPUStandardUpdaterController

    init(onUpdateSparkleConfig: @escaping (UpdateMode) -> Void, sparkleController: SPUStandardUpdaterController) {
        self.onUpdateSparkleConfig = onUpdateSparkleConfig
        self.sparkleController = sparkleController
    }

    func checkApplicationLocation() {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).checkApplicationLocation()
    }

    func showMoveToApplicationsDialog() {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).showMoveToApplicationsDialog()
    }

    func moveToApplications() {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).moveToApplications()
    }

    func showFirstLaunchLaunchAtLoginPrompt() {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).showFirstLaunchLaunchAtLoginPrompt()
    }

    func showFirstLaunchUpdatePreferencePrompt() {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).showFirstLaunchUpdatePreferencePrompt()
    }

    func setLoginAtLogin(enabled: Bool) {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).setLoginAtLogin(enabled: enabled)
    }

    func ensureCommandLineTools(
        allowAuthorizationPrompt: Bool,
        showSuccessAlert: Bool = false,
        forceAuthorizationPrompt: Bool = false
    ) {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).ensureCommandLineTools(
            allowAuthorizationPrompt: allowAuthorizationPrompt,
            showSuccessAlert: showSuccessAlert,
            forceAuthorizationPrompt: forceAuthorizationPrompt
        )
    }

    func promptForCLIInstallAuthorization() {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).promptForCLIInstallAuthorization()
    }

    func installCLISymlinkWithAuthorization() {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).installCLISymlinkWithAuthorization()
    }

    func showCLIInstallAlert(style: NSAlert.Style, message: String, information: String) {
        CLIToolsHandler(onUpdateSparkleConfig: onUpdateSparkleConfig).showCLIInstallAlert(style: style, message: message, information: information)
    }

    // MARK: - Private Helpers (moved from SpacemapServices)

    func installCommandLineTools() {
        ensureCommandLineTools(
            allowAuthorizationPrompt: true,
            showSuccessAlert: true,
            forceAuthorizationPrompt: true
        )
    }

    func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open \"\(bundlePath)\" --args --restarting"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        NSApp.terminate(nil)
    }

    func toggleLoginAtLogin() {
        let service = SMAppService.mainApp
        let newEnabled = service.status != .enabled
        setLoginAtLogin(enabled: newEnabled)
    }

    func checkForUpdates() {
        sparkleController.checkForUpdates(nil)
    }
}