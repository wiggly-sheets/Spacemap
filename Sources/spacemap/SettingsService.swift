import AppKit

final class SettingsService {
    let yabaiService: YabaiService
    let themeStore: ThemeStore
    let themeCatalog: ThemeCatalogService
    let checkForUpdates: () -> Void
    /// Called after the app drops back to an accessory (menu-bar-only) policy,
    /// which orders status-level panels out. The strip re-presents itself here.
    private let restoreFloatingPanels: () -> Void
    /// Policy to return to when the last regular window closes. Dock presence
    /// keeps `.regular`; menu-bar-only and hidden modes use `.accessory`.
    private let restingActivationPolicy: () -> NSApplication.ActivationPolicy
    private var settingsWindowController: SettingsWindowController?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private var configReplacedObserver: NSObjectProtocol?
    private(set) var aboutWindowController: AboutWindowController?

    init(
        yabaiService: YabaiService,
        themeStore: ThemeStore,
        themeCatalog: ThemeCatalogService,
        checkForUpdates: @escaping () -> Void,
        restoreFloatingPanels: @escaping () -> Void = {},
        restingActivationPolicy: @escaping () -> NSApplication.ActivationPolicy = { .accessory }
    ) {
        self.yabaiService = yabaiService
        self.themeStore = themeStore
        self.themeCatalog = themeCatalog
        self.checkForUpdates = checkForUpdates
        self.restoreFloatingPanels = restoreFloatingPanels
        self.restingActivationPolicy = restingActivationPolicy
        configReplacedObserver = NotificationCenter.default.addObserver(
            forName: .configReplacedExternally,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildSettingsWindowIfOpen()
        }
    }

    deinit {
        removeSettingsWindowCloseObserver()
        if let configReplacedObserver {
            NotificationCenter.default.removeObserver(configReplacedObserver)
        }
    }

    /// A preset apply or import replaced config.toml under an open window. Every
    /// control still holds the old values, and the next change would save them
    /// back over the replacement. Rebuild the window from the new file.
    private func rebuildSettingsWindowIfOpen() {
        guard settingsWindowController != nil else { return }
        removeSettingsWindowCloseObserver()
        settingsWindowController?.discardPendingSettingsSave()
        settingsWindowController?.close()
        settingsWindowController = nil
        showSettingsWindow()
    }

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        if let controller = settingsWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SettingsWindowController(
            yabaiService: yabaiService,
            themeStore: themeStore,
            themeCatalog: themeCatalog
        )
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
                self.settingsWindowController?.flushSettings()
                self.settingsWindowController = nil
                self.removeSettingsWindowCloseObserver()
                DispatchQueue.main.async {
                    let hasOtherWindow = NSApp.windows.contains {
                        $0.isVisible && $0.canBecomeKey
                    }
                    if !hasOtherWindow {
                        NSApp.setActivationPolicy(self.restingActivationPolicy())
                        self.restoreFloatingPanels()
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
                guard let self else { return }
                self.aboutWindowController = nil
                let policy = self.restingActivationPolicy()
                let restore = self.restoreFloatingPanels
                DispatchQueue.main.async {
                    let hasOtherWindow = NSApp.windows.contains {
                        $0.isVisible && $0.canBecomeKey
                    }
                    if !hasOtherWindow {
                        NSApp.setActivationPolicy(policy)
                        restore()
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
