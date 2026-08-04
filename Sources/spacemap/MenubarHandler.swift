import AppKit
import ServiceManagement

class MenubarHandler {
    private var statusItem: NSStatusItem?
    private var menubarRefreshWorkItem: DispatchWorkItem?
    private var menubarRefreshGeneration = 0

    private let yabaiService: YabaiService
    private let onToggleHUD: () -> Void
    private let onShowAbout: () -> Void
    private let onShowSettings: () -> Void
    private let onInstallCLI: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onRestartApp: () -> Void
    private let onGetConfig: () -> GridConfig
    private let onSetLoginAtLogin: (Bool) -> Void

    init(
        yabaiService: YabaiService,
        onToggleHUD: @escaping () -> Void,
        onShowAbout: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onInstallCLI: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onRestartApp: @escaping () -> Void,
        onGetConfig: @escaping () -> GridConfig,
        onSetLoginAtLogin: @escaping (Bool) -> Void
    ) {
        self.yabaiService = yabaiService
        self.onToggleHUD = onToggleHUD
        self.onShowAbout = onShowAbout
        self.onShowSettings = onShowSettings
        self.onInstallCLI = onInstallCLI
        self.onCheckForUpdates = onCheckForUpdates
        self.onRestartApp = onRestartApp
        self.onGetConfig = onGetConfig
        self.onSetLoginAtLogin = onSetLoginAtLogin
    }

    func setupMenubar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        applyMenubarIcon(to: item)
        let config = onGetConfig()
        let menu = NSMenu()
        let hotkeyLabel = hotkeyMenuString(config.hotkey)
        menu.addItem(menuItem(
            title: String(format: NSLocalizedString("Show/Hide Map (%@)", comment: ""), hotkeyLabel),
            action: #selector(menubarToggleHUD),
            symbolName: "square.grid.3x3"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(
            title: NSLocalizedString("About Spacemap", comment: ""),
            action: #selector(menubarShowAbout),
            symbolName: "info.circle"
        ))
        menu.addItem(menuItem(
            title: NSLocalizedString("Settings...", comment: ""),
            action: #selector(menubarShowSettings),
            keyEquivalent: ",",
            symbolName: "command"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(
            title: NSLocalizedString("Open Accessibility Permissions (for hotkeys)", comment: ""),
            action: #selector(menubarOpenAccessibility),
            symbolName: "accessibility"
        ))
        menu.addItem(menuItem(
            title: NSLocalizedString("Open Screen Recording Permissions (for thumbnails)", comment: ""),
            action: #selector(menubarOpenScreenRecording),
            symbolName: "rectangle.inset.filled"
        ))
        menu.addItem(menuItem(
            title: NSLocalizedString("Install CLI and Man Page…", comment: ""),
            action: #selector(menubarInstallCLI),
            symbolName: "terminal"
        ))
        menu.addItem(NSMenuItem.separator())
        let launchAtLoginItem = menuItem(
            title: NSLocalizedString("Launch at Login", comment: ""),
            action: #selector(menubarToggleLaunchAtLogin),
            symbolName: "power"
        )
        launchAtLoginItem.tag = 1001
        let isEnabled = SMAppService.mainApp.status == .enabled
        if isEnabled {
            launchAtLoginItem.state = .on
        }
        menu.addItem(launchAtLoginItem)
        menu.addItem(menuItem(
            title: NSLocalizedString("Check for Updates...", comment: ""),
            action: #selector(menubarCheckForUpdates),
            symbolName: "arrow.down.circle"
        ))
        menu.addItem(NSMenuItem.separator())
        let restartItem = menuItem(
            title: NSLocalizedString("Restart Spacemap", comment: ""),
            action: #selector(menubarRestartApp),
            keyEquivalent: "r",
            symbolName: "arrow.triangle.2.circlepath"
        )
        restartItem.keyEquivalentModifierMask = .command
        menu.addItem(restartItem)
        menu.addItem(menuItem(
            title: NSLocalizedString("Quit Spacemap", comment: ""),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            symbolName: "xmark.circle"
        ))
        item.menu = menu
        statusItem = item
        refreshMenubarPreview(config: config)
    }

    func showMenubarMenu() {
        let hideAfterClosing = onGetConfig().hideMenuBarIcon
        if statusItem == nil {
            setupMenubar()
        }
        statusItem?.button?.performClick(nil)
        if hideAfterClosing {
            statusItem?.isVisible = false
            statusItem = nil
        }
    }

    func applyMenubarVisibility(config: GridConfig) {
        if config.hideMenuBarIcon {
            if let item = statusItem {
                item.isVisible = false
            }
            statusItem = nil
        } else if statusItem == nil {
            setupMenubar()
        }
    }

    func refreshMenubarPreview(config: GridConfig? = nil) {
        let config = config ?? onGetConfig()
        guard let item = statusItem else { return }
        menubarRefreshGeneration += 1
        let generation = menubarRefreshGeneration
        menubarRefreshWorkItem?.cancel()

        if config.menuBarDisplayMode == .icon {
            applyMenubarIcon(to: item)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.global(qos: .utility).async {
                let state = self.yabaiService.buildGridState(config: config, focusedIndex: nil)
                DispatchQueue.main.async {
                    guard generation == self.menubarRefreshGeneration,
                          let currentItem = self.statusItem else { return }
                    if let image = MenuBarPreviewRenderer.image(for: state) {
                        currentItem.length = image.size.width + 8
                        currentItem.button?.image = image
                        currentItem.button?.imageScaling = .scaleProportionallyDown
                        currentItem.button?.toolTip = NSLocalizedString("Spacemap workspace preview", comment: "")
                    } else {
                        self.applyMenubarIcon(to: currentItem)
                    }
                }
            }
        }
        menubarRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func applyMenubarIcon(to item: NSStatusItem) {
        item.length = NSStatusItem.squareLength
        item.button?.image = NSImage(
            systemSymbolName: "square.grid.3x3",
            accessibilityDescription: "Spacemap"
        )
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "Spacemap"
    }

    private func hotkeyMenuString(_ hotkey: HotkeyConfig) -> String {
        switch hotkey.key {
        case .none:
            return "None"
        case .mediaKey(let mediaKey):
            var parts: [String] = []
            if hotkey.modifiers.contains(.maskControl) { parts.append("⌃") }
            if hotkey.modifiers.contains(.maskCommand) { parts.append("⌘") }
            if hotkey.modifiers.contains(.maskAlternate) { parts.append("⌥") }
            if hotkey.modifiers.contains(.maskShift) { parts.append("⇧") }
            parts.append(mediaKey.rawValue)
            return parts.joined(separator: "+")
        case .keyCode(let keyCode):
            var parts: [String] = []
            if hotkey.modifiers.contains(.maskControl) { parts.append("⌃") }
            if hotkey.modifiers.contains(.maskCommand) { parts.append("⌘") }
            if hotkey.modifiers.contains(.maskAlternate) { parts.append("⌥") }
            if hotkey.modifiers.contains(.maskShift) { parts.append("⇧") }
            switch keyCode {
            case 121: parts.append("PgDn")
            case 116: parts.append("PgUp")
            case 49:  parts.append("Space")
            case 48:  parts.append("Tab")
            case 36:  parts.append("Return")
            case 53:  parts.append("Esc")
            case 51:  parts.append("Del")
            case 123: parts.append("←")
            case 124: parts.append("→")
            case 125: parts.append("↓")
            case 126: parts.append("↑")
            default:  parts.append("?")
            }
            return parts.joined(separator: "+")
        }
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        symbolName: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        return item
    }

    @objc private func menubarToggleHUD() { onToggleHUD() }
    @objc private func menubarShowAbout() { onShowAbout() }
    @objc private func menubarShowSettings() { onShowSettings() }
    @objc private func menubarInstallCLI() { onInstallCLI() }
    @objc private func menubarCheckForUpdates() { onCheckForUpdates() }
    @objc private func menubarRestartApp() { onRestartApp() }

    @objc private func menubarOpenAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func menubarOpenScreenRecording() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    @objc private func menubarToggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        let newEnabled = service.status != .enabled
        onSetLoginAtLogin(newEnabled)

        if let menu = statusItem?.menu {
            for item in menu.items where item.tag == 1001 {
                item.state = SMAppService.mainApp.status == .enabled ? .on : .off
                break
            }
        }
    }
}
