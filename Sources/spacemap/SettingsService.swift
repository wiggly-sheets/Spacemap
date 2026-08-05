import AppKit

/// Handles settings-related operations.
final class SettingsService: SettingsHandling {
    let yabaiService: YabaiService
    let checkForUpdates: () -> Void

    init(
        yabaiService: YabaiService,
        checkForUpdates: @escaping () -> Void
    ) {
        self.yabaiService = yabaiService
        self.checkForUpdates = checkForUpdates
    }

    func showSettingsWindow() {
        let controller = SettingsWindowController(yabaiService: yabaiService)
        controller.showWindow()
        if let window = controller.window {
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
        if let aboutWindowController = NSApp.delegate?.perform(NSSelectorFromString("aboutWindowController"))?.takeUnretainedValue() as? NSWindowController {
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

    private var aboutWindowController: AboutWindowController?
}