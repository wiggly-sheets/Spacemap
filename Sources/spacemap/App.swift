import AppKit
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {


    private let services: SpacemapServices
    private var lifecycleService: ApplicationLifecycleService


    private var settingsWindowController: SettingsWindowController?


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
        showSettingsWindow()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        services.openDeepLinks(urls)
    }

    @objc func checkForUpdates() {
        services.checkForUpdates()
    }


    private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        let controller = SettingsWindowController(yabaiService: services.yabaiService)
        settingsWindowController = controller
        controller.showWindow()
        if let window = controller.window {
            let observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.settingsWindowController = nil
                NSApp.setActivationPolicy(.prohibited)
            }
        }
    }
}

@main
struct SpacemapEntry {
    static func main() {
        #if !DEBUG
        Config.silentMode = true
        if let status = CLI(yabaiService: YabaiClientImpl()).runIfRequested(arguments: CommandLine.arguments) {
            exit(status)
        }
        #endif

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
