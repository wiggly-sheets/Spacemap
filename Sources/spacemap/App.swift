import AppKit
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {


    private let services: SpacemapServices
    private var lifecycleService: ApplicationLifecycleService


    init(services: SpacemapServices = SpacemapServices()) {
        self.services = services
        self.lifecycleService = ApplicationLifecycleService(services: services, hud: services.hud)
        super.init()
    }


    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleService.applicationDidFinishLaunching(notification)
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleService.applicationWillTerminate(notification)
    }


    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services.showSettingsWindow()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        services.openDeepLinks(urls)
    }

    @objc func checkForUpdates() {
        services.checkForUpdates()
    }

}

/// One instance per user: a direct CLI-symlink/binary launch must not start a
/// second NSApplication (duplicate status items, taps, and a stolen socket).
/// Deep links are the forwarding channel because `spacemap://` already routes
/// to the running app through LaunchServices.
enum SingleInstanceGuard {
    static func existingInstance() -> NSRunningApplication? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != getpid() }
    }

    static func shouldExitForExistingInstance() -> Bool {
        existingInstance() != nil || SocketListener.isSocketLive(path: SpacemapCommand.socketPath)
    }

    static func forwardingURL(for argument: String) -> URL? {
        switch argument {
        case "--settings": return URL(string: "spacemap://settings")
        case "--show-menu": return URL(string: "spacemap://menu")
        default: return nil
        }
    }

    /// Commands that can be delivered straight over the live socket; the deep
    /// link stays as a fallback when the probe or write fails.
    static func socketCommand(for argument: String) -> SpacemapCommand? {
        switch argument {
        case "--settings": return .settings
        default: return nil
        }
    }

    static func forward(arguments: [String], socketPath: String = SpacemapCommand.socketPath) {
        let socketIsLive = SocketListener.isSocketLive(path: socketPath)
        for argument in arguments {
            if socketIsLive, let command = socketCommand(for: argument) {
                if SocketListener.sendCommand(to: socketPath, command: command.rawValue) {
                    continue
                }
                NSLog("spacemap/single-instance: socket forward failed for %@", argument)
            }
            guard let url = forwardingURL(for: argument) else { continue }
            if !NSWorkspace.shared.open(url) {
                NSLog("spacemap/single-instance: deep-link forward failed for %@", argument)
            }
        }
    }
}

@main
struct SpacemapEntry {
    // `NSApplication.delegate` is weak. Keep a guaranteed strong reference for
    // the whole lifetime of `app.run()`.
    private static var appDelegate: AppDelegate?

    static func main() {
        // DEBUG builds skip CLI handling so Xcode runs always launch the HUD;
        // release builds exit early for --version/--trigger/--space/--config.
        #if !DEBUG
        AppConfig.silentMode = true
        if let status = CLI(yabaiService: YabaiClientImpl()).runIfRequested(arguments: CommandLine.arguments) {
            exit(status)
        }
        #endif

        if SingleInstanceGuard.shouldExitForExistingInstance() {
            SingleInstanceGuard.forward(arguments: CommandLine.arguments)
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
