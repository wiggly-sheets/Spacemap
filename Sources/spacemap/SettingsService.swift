import AppKit

final class SettingsService: SettingsHandling {
    let yabaiService: YabaiService
    let checkForUpdates: () -> Void
    private var settingsWindowController: SettingsWindowController?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private(set) var aboutWindowController: AboutWindowController?

    init(
        yabaiService: YabaiService,
        checkForUpdates: @escaping () -> Void
    ) {
        self.yabaiService = yabaiService
        self.checkForUpdates = checkForUpdates
    }

    deinit {
        removeSettingsWindowCloseObserver()
    }

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        if let controller = settingsWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SettingsWindowController(yabaiService: yabaiService)
        settingsWindowController = controller
        controller.showWindow()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = controller.window {
            removeSettingsWindowCloseObserver()
            settingsWindowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.settingsWindowController = nil
                self.removeSettingsWindowCloseObserver()
                DispatchQueue.main.async {
                    let hasOtherWindow = NSApp.windows.contains {
                        $0.isVisible && $0.canBecomeKey
                    }
                    if !hasOtherWindow {
                        NSApp.setActivationPolicy(.prohibited)
                    }
                }
            }
        }
    }

    func showAboutWindow() {
        NSApp.setActivationPolicy(.regular)
        if let controller = aboutWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = AboutWindowController(
            onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
            onClose: { [weak self] in
                self?.aboutWindowController = nil
                DispatchQueue.main.async {
                    let hasOtherWindow = NSApp.windows.contains {
                        $0.isVisible && $0.canBecomeKey
                    }
                    if !hasOtherWindow {
                        NSApp.setActivationPolicy(.prohibited)
                    }
                }
            }
        )
        aboutWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func removeSettingsWindowCloseObserver() {
        guard let settingsWindowCloseObserver else { return }
        NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
        self.settingsWindowCloseObserver = nil
    }
}
