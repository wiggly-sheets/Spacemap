import AppKit
import ServiceManagement
import Sparkle

extension CLIToolsService {
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

        ConfigStore.updateConfig { $0.updateMode = updateMode }
        onUpdateSparkleConfig(updateMode)
    }

    func restartApp() {
        AppRestartPlan.relaunch()
    }

    static func compareVersions(_ installed: String?, _ source: String?) -> ComparisonResult {
        (installed ?? "").compare(source ?? "", options: .numeric)
    }

    func installedVersion(at url: URL) -> String? { bundleVersion(at: url) }

    func bundleVersion(at url: URL) -> String? {
        Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    func verifyBundleSignature(at url: URL) -> Bool {
        // Bounded like the yabai trust check: a wedged codesign must not block
        // the move forever. Output was already discarded; any failure is false.
        (try? ProcessRunner.run(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", url.path],
            timeout: 10
        )) != nil
    }

    func checkForUpdates() {
        sparkleController.checkForUpdates(nil)
    }
}
