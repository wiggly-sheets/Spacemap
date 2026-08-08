import AppKit

class SettingsHandler {
    private let yabaiService: YabaiService
    private var aboutWindowController: AboutWindowController?
    private let checkForUpdates: () -> Void

    init(yabaiService: YabaiService, checkForUpdates: @escaping () -> Void) {
        self.yabaiService = yabaiService
        self.checkForUpdates = checkForUpdates
    }

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        let settingsWindowController = SettingsWindowController(yabaiService: yabaiService)
        settingsWindowController.showWindow()
        if let window = settingsWindowController.window {
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                NSApp.setActivationPolicy(.prohibited)
            }
        }
    }

    func showAboutWindow() {
        NSApp.setActivationPolicy(.regular)
        if let aboutWindowController {
            aboutWindowController.showWindow(nil)
            aboutWindowController.window?.makeKeyAndOrderFront(nil)
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
}
