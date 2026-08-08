import AppKit
import ServiceManagement
import Sparkle

/// The application delegate is now thin, delegating most of its responsibilities to the ApplicationLifecycleService.
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {

    // MARK: - Dependencies

    private let services: SpacemapServices
    private var lifecycleService: ApplicationLifecycleService

    // MARK: - UI State

    /// The settings window controller, if the settings window is currently shown.
    private var settingsWindowController: SettingsWindowController?

    // MARK: - Initialization

    init(services: SpacemapServices = SpacemapServices()) {
        self.services = services
        self.lifecycleService = ApplicationLifecycleService(services: services, hud: services.hud)
        super.init()
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleService.applicationDidFinishLaunching(notification)
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleService.applicationWillTerminate(notification)
    }

    // MARK: - Delegated Methods (minimal)

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        services.openDeepLinks(urls)
    }

    @objc func checkForUpdates() {
        services.checkForUpdates()
    }

    // MARK: - Private Helpers

    private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        let controller = SettingsWindowController(yabaiService: services.yabaiService)
        settingsWindowController = controller
        controller.showWindow()
        if let window = controller.window {
            // Observe window close to reset activation policy and nil out the controller
            let observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.settingsWindowController = nil
                NSApp.setActivationPolicy(.prohibited)
            }
            // We don't store the observer because it's tied to the window controller's lifetime.
            // When the window controller is deallocated, the observer will be removed automatically.
        }
    }
}

@main
struct SpacemapEntry {
    static func main() {
        #if !DEBUG
        Config.silentMode = true
        let yabai = YabaiClientImpl()
        let manager: YabaiService = yabai.isYabaiRunning(forceRefresh: true) ? yabai : AeroSpaceClient()
        if let status = CLI(yabaiService: manager).runIfRequested(arguments: CommandLine.arguments) {
            exit(status)
        }
        #endif

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
