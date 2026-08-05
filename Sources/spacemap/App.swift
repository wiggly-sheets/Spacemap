import AppKit
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let services: SpacemapServices
    private lazy var hud: HUDWindowController = { HUDWindowController(services: services) }()
    private var hotkey: HotkeyMonitor?
    private var pinnedHotkey: HotkeyMonitor?
    private var socketListener: SocketListener?
    private var statusItem: NSStatusItem?
    private var settingsObserver: NSObjectProtocol?
    private var settingsWindowObserver: NSObjectProtocol?
    private var currentConfig: GridConfig?
    private var aboutWindowController: AboutWindowController?
    private var menubarRefreshWorkItem: DispatchWorkItem?
    private var menubarRefreshGeneration = 0
    private var isReadyForDeepLinks = false
    private var pendingDeepLinks: [DeepLinkAction] = []
    private lazy var sparkleUpdaterController: SPUStandardUpdaterController = {
        print("Spacemap: Initializing Sparkle updater controller")
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        print("Spacemap: Sparkle updater controller initialized")
        return controller
    }()

    init(services: SpacemapServices = SpacemapServices()) {
        self.services = services
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        
        // Keep the CLI and manual available when permissions allow.
        // Exit-only CLI commands must never trigger an administrator prompt.
        ensureCommandLineTools(allowAuthorizationPrompt: false)
        
        // Exit-only CLI commands are handled before AppKit starts.
        NSApp.setActivationPolicy(.prohibited)
        
        // Check yabai before doing anything else
        if !services.yabaiService.isYabaiRunning(forceRefresh: true) {
            services.showYabaiAlert()
        }
        
        // Check the Mission Control settings that keep space locations stable.
        let needsSeparateSpacesWarning = NSScreen.screens.count > 1 && !NSScreen.screensHaveSeparateSpaces
        DispatchQueue.global(qos: .utility).async {
            let mruSpacesEnabled = self.isMRUSpacesEnabled()
            DispatchQueue.main.async {
                if needsSeparateSpacesWarning {
                    self.showSeparateSpacesAlert()
                }
                if mruSpacesEnabled {
                    self.showMRUAlert()
                }
            }
        }
        
        // Check if app is in /Applications folder, if not, prompt to move
        checkApplicationLocation()
        
        // Ensure the CLI and manual are installed, offering an explicit authorization flow
        // on macOS setups where /usr/local is root-owned.
        ensureCommandLineTools(allowAuthorizationPrompt: true)
        
        setupMenubar()
        isReadyForDeepLinks = true
        handlePendingDeepLinks()
        
        // Trigger Sparkle initialization early so updater starts on launch
        _ = sparkleUpdaterController

        // Delay slightly so TCC/LaunchServices finishes registering the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Config.silentMode = true
            let config = Config.load()
            self.currentConfig = config
            self.hud.reloadConfig()
            self.hud.prewarmState()
            self.restartHotkey(config: config)
            self.applyMenubarVisibility(config: config)
            self.refreshMenubarPreview(config: config)
            self.hud.onShowSettings = { [weak self] in self?.showSettingsWindow() }
            self.socketListener = SocketListener(
                socketPath: SpacemapCommand.socketPath,
                healthInterval: config.socketHealthInterval,
                onRefresh: { [weak self] in
                    self?.hud.refresh()
                    self?.refreshMenubarPreview()
                },
                onShow: { [weak self] in
                    self?.hud.show()
                    self?.refreshMenubarPreview()
                },
                onToggle: { [weak self] in self?.hud.toggle() },
                onSettings: { [weak self] in self?.showSettingsWindow() }
            )
            self.services.yabaiService.registerSignals(
                socketPath: SpacemapCommand.socketPath,
                showHUDOnSpaceChange: config.showHUDOnSpaceChange,
                refreshWorkspacePreviews: self.workspacePreviewsEnabled(for: config),
                refreshWindowGeometry: self.windowGeometryPreviewsEnabled(for: config)
            )
            
            // Observe settings changes to update hotkey
            self.settingsObserver = NotificationCenter.default.addObserver(
                forName: .settingsChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                Config.silentMode = true
                let config = Config.load()
                let shouldUpdateYabaiSignals =
                    self.currentConfig?.showHUDOnSpaceChange != config.showHUDOnSpaceChange ||
                    self.currentConfig.map { self.workspacePreviewsEnabled(for: $0) } !=
                        self.workspacePreviewsEnabled(for: config) ||
                    self.currentConfig.map { self.windowGeometryPreviewsEnabled(for: $0) } !=
                        self.windowGeometryPreviewsEnabled(for: config)
                self.currentConfig = config
                self.hud.reloadConfig()
                self.restartHotkey(config: config)
                self.applyMenubarVisibility(config: config)
                self.refreshMenubarPreview(config: config)
                if shouldUpdateYabaiSignals {
                    services.yabaiService.registerSignals(
                        socketPath: SpacemapCommand.socketPath,
                        showHUDOnSpaceChange: config.showHUDOnSpaceChange,
                        refreshWorkspacePreviews: self.workspacePreviewsEnabled(for: config),
                        refreshWindowGeometry: self.windowGeometryPreviewsEnabled(for: config)
                    )
                }
            }

            self.configureSparkleUpdater(updateMode: config.updateMode)
        }
        #if !DEBUG
        if args.contains("--show-menu") {
            // Show menu and continue running
            self.showMenubarMenu()
        }
        if args.contains("--settings") {
            // Show settings window and continue running
            self.showSettingsWindow()
        }
        #endif
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        services.yabaiService.removeSignals()
        socketListener?.stop()
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = settingsWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let action = DeepLinkAction(url: url) else {
                NSLog("Spacemap: ignored unsupported deep link \(url.absoluteString)")
                continue
            }
            if isReadyForDeepLinks {
                handleDeepLink(action)
            } else {
                pendingDeepLinks.append(action)
            }
        }
    }

    private func handlePendingDeepLinks() {
        let actions = pendingDeepLinks
        pendingDeepLinks.removeAll()
        actions.forEach(handleDeepLink)
    }

    private func handleDeepLink(_ action: DeepLinkAction) {
        switch action {
        case .toggleHUD:
            hud.toggle()
        case .pinHUD:
            hud.pin()
        case .settings:
            showSettingsWindow()
        case .menu:
            showMenubarMenu()
        case .config:
            _ = Config.load()
            NSWorkspace.shared.open(URL(fileURLWithPath: Config.configPath))
        case .themes:
            services.themeService.reload()
            NSWorkspace.shared.open(ThemeManager.themesDir())
        }
    }

    private func showMenubarMenu() {
        let hideAfterClosing = currentConfig?.hideMenuBarIcon ?? Config.load().hideMenuBarIcon
        if statusItem == nil {
            setupMenubar()
        }
        statusItem?.button?.performClick(nil)
        if hideAfterClosing {
            statusItem?.isVisible = false
            statusItem = nil
        }
    }

    private func applyMenubarVisibility(config: GridConfig) {
        if config.hideMenuBarIcon {
            if let item = statusItem {
                item.isVisible = false
            }
            statusItem = nil
        } else if statusItem == nil {
            setupMenubar()
        }
    }

    private func workspacePreviewsEnabled(for config: GridConfig) -> Bool {
        !config.hideMenuBarIcon && config.menuBarDisplayMode != .icon
    }

    private func windowGeometryPreviewsEnabled(for config: GridConfig) -> Bool {
        workspacePreviewsEnabled(for: config) && config.menuBarDisplayMode != .dots
    }

    private func refreshMenubarPreview(config: GridConfig? = nil) {
        let config = config ?? currentConfig ?? Config.load()
        guard let item = statusItem else { return }
        menubarRefreshGeneration += 1
        let generation = menubarRefreshGeneration
        menubarRefreshWorkItem?.cancel()

        if config.menuBarDisplayMode == .icon {
            self.services.applyMenubarIcon(to: item)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.global(qos: .utility).async {
                let state = self.services.yabaiService.buildGridState(config: config, focusedIndex: nil)
                DispatchQueue.main.async {
                    guard generation == self.menubarRefreshGeneration,
                          let currentItem = self.statusItem else { return }
                    if let image = MenuBarPreviewRenderer.image(for: state) {
                        currentItem.length = image.size.width + 8
                        currentItem.button?.image = image
                        currentItem.button?.imageScaling = .scaleProportionallyDown
                        currentItem.button?.toolTip = NSLocalizedString("Spacemap workspace preview", comment: "")
                    } else {
                        self.services.applyMenubarIcon(to: currentItem)
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

    private func setupMenubar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.services.applyMenubarIcon(to: item)
        let config = currentConfig ?? Config.load()
        let menu = NSMenu()
        let hotkeyLabel = self.services.hotkeyMenuString(config.hotkey)
        menu.addItem(menuItem(
            title: String(format: NSLocalizedString("Show/Hide Map (%@)", comment: ""), hotkeyLabel),
            action: #selector(toggleHUD),
            symbolName: "square.grid.3x3"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(
            title: NSLocalizedString("About Spacemap", comment: ""),
            action: #selector(showAboutWindow),
            symbolName: "info.circle"
        ))
        menu.addItem(menuItem(
            title: NSLocalizedString("Settings...", comment: ""),
            action: #selector(showSettingsWindow),
            keyEquivalent: ",",
            symbolName: "command"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(
            title: NSLocalizedString("Open Accessibility Permissions (for hotkeys)", comment: ""),
            action: #selector(openAccessibility),
            symbolName: "accessibility"
        ))
        menu.addItem(menuItem(
            title: NSLocalizedString("Open Screen Recording Permissions (for thumbnails)", comment: ""),
            action: #selector(openScreenRecording),
            symbolName: "rectangle.inset.filled"
        ))
        menu.addItem(menuItem(
            title: NSLocalizedString("Install CLI and Man Page…", comment: ""),
            action: #selector(installCommandLineTools),
            symbolName: "terminal"
        ))
        menu.addItem(NSMenuItem.separator())
        // Launch at Login
        let launchAtLoginItem = menuItem(
            title: NSLocalizedString("Launch at Login", comment: ""),
            action: #selector(toggleLaunchAtLogin),
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
            action: #selector(checkForUpdates),
            symbolName: "arrow.down.circle"
        ))
        menu.addItem(NSMenuItem.separator())
        let restartItem = menuItem(
            title: NSLocalizedString("Restart Spacemap", comment: ""),
            action: #selector(restartApp),
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

    @objc private func toggleHUD() { hud.toggle() }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openScreenRecording() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    @objc private func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open \"\(bundlePath)\" --args --restarting"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc func checkForUpdates() {
        print("Spacemap: Check for updates clicked")
        sparkleUpdaterController.checkForUpdates(nil)
    }

    @objc private func showAboutWindow() {
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

    @objc private func installCommandLineTools() {
        ensureCommandLineTools(allowAuthorizationPrompt: true, showSuccessAlert: true, forceAuthorizationPrompt: true)
    }

    private func restartHotkey(config: GridConfig) {
        self.hotkey?.stop()
        self.hotkey = nil
        self.pinnedHotkey?.stop()
        self.pinnedHotkey = nil
        self.startHotkey(config: config)
        self.startPinnedHotkey(config: config)
    }

    private func startHotkey(config: GridConfig) {
        guard !config.hotkey.isDisabled else {
            print("Spacemap: hotkey disabled")
            return
        }
        let monitor = HotkeyMonitor(config: config.hotkey) { [weak self] in
            self?.hud.toggle()
        }
        monitor.start()
        hotkey = monitor
    }

    private func startPinnedHotkey(config: GridConfig) {
        guard !config.pinnedHotkey.isDisabled else {
            print("Spacemap: pinned HUD hotkey disabled")
            return
        }
        guard Hotkey.hotkeyToString(config.pinnedHotkey) != Hotkey.hotkeyToString(config.hotkey) else {
            NSLog("Spacemap: pinned HUD hotkey matches the normal hotkey; pinned binding ignored")
            return
        }
        let monitor = HotkeyMonitor(config: config.pinnedHotkey) { [weak self] in
            self?.hud.togglePinned()
        }
        monitor.start()
        pinnedHotkey = monitor
    }

    @objc private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        let settingsWindowController = SettingsWindowController(yabaiService: services.yabaiService)
        settingsWindowController.showWindow()
        if let window = settingsWindowController.window {
            settingsWindowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.settingsWindowObserver = nil
                NSApp.setActivationPolicy(.prohibited)
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        let newEnabled = service.status != .enabled
        setLoginAtLogin(enabled: newEnabled)

        if let menu = statusItem?.menu {
            for item in menu.items where item.tag == 1001 {
                item.state = SMAppService.mainApp.status == .enabled ? .on : .off
                break
            }
        }
    }

    private func setLoginAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let actionString = enabled ? "enable" : "disable"
            print("Failed to \(actionString) launch at login: \(error)")
        }
    }

    private func checkApplicationLocation() {
        let appPath = Bundle.main.bundleURL.path
        let applicationsPath = "/Applications"
        let isInApplications = appPath.hasPrefix(applicationsPath)
        
        // Also check if we need to show the first-launch prompt for Launch at Login
        let defaults = UserDefaults.standard
        let hasAskedLaunchAtLogin = defaults.bool(forKey: "HasAskedLaunchAtLogin")
        
        if !isInApplications {
            showMoveToApplicationsDialog()
        }
        
        if !hasAskedLaunchAtLogin {
            showFirstLaunchLaunchAtLoginPrompt()
            defaults.set(true, forKey: "HasAskedLaunchAtLogin")
        }
        
        // Ask about update preferences if not asked before
        let hasAskedUpdate = defaults.bool(forKey: "HasAskedUpdatePreference")
        if !hasAskedUpdate {
            showFirstLaunchUpdatePreferencePrompt()
            defaults.set(true, forKey: "HasAskedUpdatePreference")
        }
    }

    private func showMoveToApplicationsDialog() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Move Spacemap to Applications?", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap should be run from the Applications folder for best performance. Would you like to move it there now?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Move to Applications", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            moveToApplications()
        }
    }

    private func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("Moved to Applications", comment: "")
            alert.informativeText = NSLocalizedString("Spacemap has been copied to the Applications folder. Please quit and relaunch from there.", comment: "")
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to move", comment: "")
            alert.informativeText = String(format: NSLocalizedString("Could not move Spacemap to Applications: %@", comment: ""), error.localizedDescription)
            alert.runModal()
        }
    }

    private func showFirstLaunchLaunchAtLoginPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Launch at Login?", comment: "")
        alert.informativeText = NSLocalizedString("Would you like Spacemap to start automatically when you log in?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("No", comment: ""))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            setLoginAtLogin(enabled: true)
        }
    }
    
    private func showFirstLaunchUpdatePreferencePrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Automatic Updates?", comment: "")
        alert.informativeText = NSLocalizedString("How would you like Spacemap to check for updates?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Auto (Download & Install)", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Notify (Check & Prompt)", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Off", comment: ""))

        let response = alert.runModal()
        let updateMode: UpdateMode
        switch response {
        case .alertFirstButtonReturn:
            updateMode = .auto
        case .alertSecondButtonReturn:
            updateMode = .notify
        default:
            updateMode = .off
        }

        var config = Config.load()
        config.updateMode = updateMode
        Config.saveConfig(config)
        configureSparkleUpdater(updateMode: updateMode)
    }

    private func showYabaiAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("yabai is not running", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap requires yabai to be running. Please start yabai and relaunch Spacemap. See https://github.com/koekeishiya/yabai for installation instructions.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open yabai", comment: ""))
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            guard let yabaiURL = URL(string: "https://github.com/koekeishiya/yabai") else { return }
            NSWorkspace.shared.open(yabaiURL)
        }
        NSApp.terminate(nil)
    }

    private func isMRUSpacesEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", "mru-spaces"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private func showMRUAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Spaces Auto-Rearrange Enabled", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs this disabled for stable grid layout. Spaces must stay in a fixed order or the grid becomes unreliable.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Leave as Is", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Fix It", comment: ""))
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            task.arguments = ["write", "com.apple.dock", "mru-spaces", "-bool", "false"]
            try? task.run()
            task.waitUntilExit()
            // Restart Dock for changes to take effect
            let dock = Process()
            dock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            dock.arguments = ["Dock"]
            try? dock.run()
        }
        NSApp.setActivationPolicy(.prohibited)
    }

    private func showSeparateSpacesAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Displays Have Separate Spaces Disabled", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs Displays have separate Spaces enabled to show and navigate each monitor independently. Enable it in System Settings, then log out and back in before using multi-monitor HUD modes.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Leave as Is", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open System Settings", comment: ""))

        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
        NSApp.setActivationPolicy(.prohibited)
    }

    private let cliSymlinkPath = "/usr/local/bin/spacemap"
    private let cliExecutablePath = "/Applications/Spacemap.app/Contents/MacOS/Spacemap"
    private let manPageSymlinkPath = "/usr/local/share/man/man1/spacemap.1"
    private let manPagePath = "/Applications/Spacemap.app/Contents/Resources/spacemap.1"

    private func ensureCommandLineTools(
        allowAuthorizationPrompt: Bool,
        showSuccessAlert: Bool = false,
        forceAuthorizationPrompt: Bool = false
    ) {
        let cliResult = CLISymlinkInstaller.install(
            symlinkPath: cliSymlinkPath,
            targetPath: cliExecutablePath
        )
        let manPageResult = CLISymlinkInstaller.install(
            symlinkPath: manPageSymlinkPath,
            targetPath: manPagePath,
            targetMustBeExecutable: false
        )
        let results = [cliResult, manPageResult]

        if results.contains(.authorizationRequired) {
            guard allowAuthorizationPrompt else {
                print("Spacemap: administrator authorization is required to install CLI documentation links")
                return
            }
            let defaults = UserDefaults.standard
            let authorizationPromptKey = "HasAskedCLIAndManPageInstallAuthorization"
            if forceAuthorizationPrompt || !defaults.bool(forKey: authorizationPromptKey) {
                defaults.set(true, forKey: authorizationPromptKey)
                promptForCLIInstallAuthorization()
            }
            return
        }

        if cliResult == .targetUnavailable {
            print("Spacemap: CLI target is unavailable at \(cliExecutablePath)")
        } else if cliResult == .conflictingItem {
            print("Spacemap: preserving existing item at \(cliSymlinkPath)")
        } else if cliResult == .failed {
            print("Spacemap: failed to create CLI symlink at \(cliSymlinkPath)")
        }

        if manPageResult == .targetUnavailable {
            print("Spacemap: man page target is unavailable at \(manPagePath)")
        } else if manPageResult == .conflictingItem {
            print("Spacemap: preserving existing item at \(manPageSymlinkPath)")
        } else if manPageResult == .failed {
            print("Spacemap: failed to create man page symlink at \(manPageSymlinkPath)")
        }

        guard showSuccessAlert else { return }
        if results.contains(.conflictingItem) {
            showCLIInstallAlert(
                style: .warning,
                message: NSLocalizedString("Command-Line Tools Partially Installed", comment: ""),
                information: NSLocalizedString("Spacemap installed available links but preserved an unrelated item at a destination path.", comment: "")
            )
        } else if results.contains(.failed) || results.contains(.targetUnavailable) {
            showCLIInstallAlert(
                style: .critical,
                message: NSLocalizedString("Command-Line Tools Not Installed", comment: ""),
                information: NSLocalizedString("Spacemap could not install the command-line tool and manual page. You can try again from the menu bar.", comment: "")
            )
        } else {
            showCLIInstallAlert(
                style: .informational,
                message: NSLocalizedString("Command-Line Tools Ready", comment: ""),
                information: NSLocalizedString("You can now use `spacemap` and `man spacemap` from Terminal.", comment: "")
            )
        }
    }

    private func promptForCLIInstallAuthorization() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Install Command-Line Tools?", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs administrator permission to link its command and manual page into /usr/local. This does not change your shell configuration.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Install", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Not Now", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            installCLISymlinkWithAuthorization()
        }
    }

    private func installCLISymlinkWithAuthorization() {
        // This intentionally refuses to overwrite any unrelated item. All
        // paths are app constants, so no user-controlled shell input is used.
        let command = "/bin/mkdir -p /usr/local/bin /usr/local/share/man/man1; if [ -x /Applications/Spacemap.app/Contents/MacOS/Spacemap ] && [ ! -e /usr/local/bin/spacemap ] && [ ! -L /usr/local/bin/spacemap ]; then /bin/ln -s /Applications/Spacemap.app/Contents/MacOS/Spacemap /usr/local/bin/spacemap; fi; if [ -f /Applications/Spacemap.app/Contents/Resources/spacemap.1 ] && [ ! -e /usr/local/share/man/man1/spacemap.1 ] && [ ! -L /usr/local/share/man/man1/spacemap.1 ]; then /bin/ln -s /Applications/Spacemap.app/Contents/Resources/spacemap.1 /usr/local/share/man/man1/spacemap.1; fi"
        let source = "do shell script \"\(command)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)

        if let error {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int
            if errorNumber != -128 { // User cancelled the authorization dialog.
                print("Spacemap: authorized command-line tools installation failed: \(error)")
                showCLIInstallAlert(
                    style: .critical,
                    message: NSLocalizedString("Command-Line Tools Not Installed", comment: ""),
                    information: NSLocalizedString("Spacemap could not install the command-line tool and manual page. You can try again from the menu bar.", comment: "")
                )
            }
            return
        }

        ensureCommandLineTools(allowAuthorizationPrompt: false, showSuccessAlert: true)
    }

    private func showCLIInstallAlert(style: NSAlert.Style, message: String, information: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = information
        alert.runModal()
    }

private func configureSparkleUpdater(updateMode: UpdateMode) {
print("Spacemap: Configuring Sparkle updater with mode: \(updateMode)")
        let updater = sparkleUpdaterController.updater
        print("Spacemap: Updater feed URL: \(String(describing: updater.feedURL))")
        print("Spacemap: Current auto-check setting: \(updater.automaticallyChecksForUpdates)")
        print("Spacemap: Current auto-download setting: \(updater.automaticallyDownloadsUpdates)")
        
        switch updateMode {
        case .auto:
            updater.automaticallyDownloadsUpdates = true
            updater.automaticallyChecksForUpdates = true
        case .notify:
            updater.automaticallyDownloadsUpdates = false
            updater.automaticallyChecksForUpdates = true
        case .off:
            updater.automaticallyChecksForUpdates = false
        }
        
        print("Spacemap: After config - auto-check: \(updater.automaticallyChecksForUpdates), auto-download: \(updater.automaticallyDownloadsUpdates)")
        
        // startUpdater is idempotent — no-ops if already started
        if updateMode != .off {
            sparkleUpdaterController.startUpdater()
        }
    }

    // MARK: - SPUUpdaterDelegate

    func feedURL(for updater: SPUUpdater) -> URL? {
        return URL(string: "https://wiggly-sheets.github.io/Spacemap/appcast.xml")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("Spacemap: Sparkle update aborted with error: \(error)")
    }
    
    func updaterDidFinishLoading(_ updater: SPUUpdater) {
        print("Spacemap: Sparkle updater finished loading")
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
