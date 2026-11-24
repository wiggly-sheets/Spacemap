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

    /// Starts a detached helper, then quits. The helper waits for this PID to
    /// exit before opening the bundle, so LaunchServices cannot re-activate the
    /// old instance and a failed launch leaves this process running.
    static func relaunch() {
        let plan = make(
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
            // Retain until process exit; the helper outlives this call.
            retainedRestartHelpers.append(helper)
        } catch {
            NSLog("Spacemap: relaunch helper failed — \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }

    static var retainedRestartHelpers: [Process] = []
}
final class CLIToolsService {
    let cliSymlinkPath = "/usr/local/bin/spacemap"
    let manPageSymlinkPath = "/usr/local/share/man/man1/spacemap.1"
    let applicationsPath = "/Applications"

    /// System Applications is the single install location. The CLI, updates,
    /// and the move prompt all resolve against it.
    static let applicationsPaths = ["/Applications"]

    static let askedLaunchAtLoginKey = "HasAskedLaunchAtLogin"
    static let askedUpdatePreferenceKey = "HasAskedUpdatePreference"
    static let declinedMoveToApplicationsKey = "HasDeclinedMoveToApplications"

    let onUpdateSparkleConfig: (UpdateMode) -> Void
    let sparkleController: SPUStandardUpdaterController

    var cliExecutablePath: String {
        Self.cliTargetPath(bundleURL: Bundle.main.bundleURL, executableURL: Bundle.main.executableURL)
    }

    var manPagePath: String {
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

}
