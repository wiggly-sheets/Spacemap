import AppKit
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let hud = HUDWindowController()
    private var hotkey: HotkeyMonitor?
    private var windowManager: WindowManager?
    private var statusItem: NSStatusItem?
    private var settingsObserver: NSObjectProtocol?
    private var currentConfig: GridConfig?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        
        // Ensure symlink first, before any early exits from CLI flags
        ensureSymlink()
        
        #if !DEBUG
        // Handle CLI arguments that cause immediate exit
        if args.contains("--version") {
            ConfigReader.silentMode = true
            printVersionAndExit()
            return
        }
        if args.contains("--help") {
            ConfigReader.silentMode = true
            printHelpAndExit()
            return
        }
        if args.contains("--config") {
            ConfigReader.silentMode = true
            openConfigAndExit()
            return
        }
        if args.contains("--trigger") {
            ConfigReader.silentMode = true
            setupForTriggerAndExit()
            return
        }
        #endif
        
        // Normal setup (do not run for exit-only CLI args)
        NSApp.setActivationPolicy(.prohibited)
        
        // Check if window manager is available before doing anything else
        windowManager = detectWindowManager()
        if let wm = windowManager, !wm.isRunning() {
            showWMNotRunningAlert()
        }
        
        // Check if MRU spaces is enabled (bad for spacemap)
        if isMRUSpacesEnabled() {
            showMRUAlert()
        }
        
        // Check if app is in /Applications folder, if not, prompt to move
        checkApplicationLocation()
        
        // Ensure symlink exists in /usr/local/bin for easy CLI access
        ensureSymlink()
        
        setupMenubar()
        
        // Trigger Sparkle initialization early so updater starts on launch
        _ = sparkleUpdaterController
        
        // Delay slightly so TCC/LaunchServices finishes registering the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ConfigReader.silentMode = true
            let config = ConfigReader.load()
            self.currentConfig = config
            self.hud.reloadConfig()
            self.restartHotkey(config: config)
            self.applyMenubarVisibility(config: config)
            self.hud.onShowSettings = { [weak self] in self?.showSettingsWindow() }
            
            // Set up window manager event listening
            if let wm = self.windowManager {
                wm.startListening(
                    socketPath: "/tmp/spacemap_\(NSUserName()).socket",
                    onRefresh: { [weak self] in
                        self?.hud.refresh()
                    },
                    onShow: { [weak self] in
                        self?.hud.show()
                    },
                    onSettings: { [weak self] in
                        self?.showSettingsWindow()
                    }
                )
            }
            
            // Observe settings changes to update hotkey and WM detection
            self.settingsObserver = NotificationCenter.default.addObserver(
                forName: .settingsChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                ConfigReader.silentMode = true
                let config = ConfigReader.load()
                self.currentConfig = config
                self.hud.reloadConfig()
                self.restartHotkey(config: config)
                self.applyMenubarVisibility(config: config)
                
                // Re-detect window manager if config changed
                let oldWM = self.windowManager
                self.windowManager = self.detectWindowManager()
                
                // Restart listening with new WM if needed
                if let oldWM = oldWM, let newWM = self.windowManager {
                    if type(of: oldWM) != type(of: newWM) {
                        oldWM.stopListening()
                        newWM.startListening(
                            socketPath: "/tmp/spacemap_\(NSUserName()).socket",
                            onRefresh: { [weak self] in
                                self?.hud.refresh()
                            },
                            onShow: { [weak self] in
                                self?.hud.show()
                            },
                            onSettings: { [weak self] in
                                self?.showSettingsWindow()
                            }
                        )
                    }
                }
            }
            
            self.configureSparkleUpdater(updateMode: config.updateMode)
        }
        
        #if !DEBUG
        if args.contains("--show-menu") {
            // Show menu and continue running
            if let button = self.statusItem?.button {
                button.performClick(nil)
            }
        }
        if args.contains("--settings") {
            // Show settings window and continue running
            self.showSettingsWindow()
        }
        #endif
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        windowManager?.stopListening()
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
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
    
    private func hotkeyMenuString(_ hotkey: HotkeyConfig) -> String {
        var parts: [String] = []
        if hotkey.modifiers.contains(.maskControl) { parts.append("⌃") }
        if hotkey.modifiers.contains(.maskCommand) { parts.append("⌘") }
        if hotkey.modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if hotkey.modifiers.contains(.maskShift) { parts.append("⇧") }
        switch hotkey.keyCode {
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
    
    private func setupMenubar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Spacemap")
        }
        let config = currentConfig ?? ConfigReader.load()
        let menu = NSMenu()
        let hotkeyLabel = hotkeyMenuString(config.hotkey)
        menu.addItem(NSMenuItem(title: String(format: NSLocalizedString("Show/Hide Map (%@)", comment: ""), hotkeyLabel), action: #selector(toggleHUD), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Settings...", comment: ""), action: #selector(showSettingsWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Open Accessibility Permissions (for hotkeys)", comment: ""), action: #selector(openAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Open Screen Recording Permissions (for thumbnails)", comment: ""), action: #selector(openScreenRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        // Launch at Login
        let launchAtLoginItem = NSMenuItem(title: NSLocalizedString("Launch at Login", comment: ""), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.tag = 1001
        let isEnabled: Bool
        if #available(macOS 13, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
        if isEnabled {
            launchAtLoginItem.state = .on
        }
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem(title: NSLocalizedString("Check for Updates...", comment: ""), action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let restartItem = NSMenuItem(title: NSLocalizedString("Restart Spacemap", comment: ""), action: #selector(restartApp), keyEquivalent: "r")
        restartItem.keyEquivalentModifierMask = .command
        menu.addItem(restartItem)
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit Spacemap", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
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
    
    private func restartHotkey(config: GridConfig) {
        self.hotkey?.stop()
        self.hotkey = nil
        self.startHotkey(config: config)
    }
    
    private func startHotkey(config: GridConfig) {
        let monitor = HotkeyMonitor(config: config.hotkey) { [weak self] in
            self?.hud.toggle()
        }
        monitor.start()
        hotkey = monitor
    }
    
    @objc private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        let settingsWindowController = SettingsWindowController()
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
    
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13, *) {
            let service = SMAppService.mainApp
            let currentStatus = service.status
            let newEnabled = currentStatus != .enabled
            
            setLoginAtLogin(enabled: newEnabled)
            
            // Update menu item state
            if let menu = statusItem?.menu {
                for item in menu.items {
                    if item.tag == 1001 {
                        let newStatus: Bool
                        if #available(macOS 13, *) {
                            newStatus = SMAppService.mainApp.status == .enabled
                        } else {
                            newStatus = false
                        }
                        item.state = newStatus ? .on : .off
                        break
                    }
                }
            }
        }
    }
    
    private func setLoginAtLogin(enabled: Bool) {
        if #available(macOS 13, *) {
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
        } else {
            print("Launch at login requires macOS 13 or later")
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
        
        var config = ConfigReader.load()
        config.updateMode = updateMode
        ConfigReader.saveConfig(config)
        configureSparkleUpdater(updateMode: updateMode)
    }
    
    private func showWMNotRunningAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Window manager is not running", comment: "")
        if let wm = windowManager {
            alert.informativeText = String(format: NSLocalizedString("Spacemap requires %@ to be running. Please start %@ and relaunch Spacemap.", comment: ""), wm.type.rawValue, wm.type.rawValue)
        } else {
            alert.informativeText = NSLocalizedString("Spacemap requires a window manager (yabai or aerospace) to be running. Please start one and relaunch Spacemap.", comment: "")
        }
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open yabai", comment: ""))
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/koekeishiya/yabai")!)
        }
        NSApp.terminate(nil)
    }
    
    private func detectWindowManager() -> WindowManager? {
        let config = ConfigReader.load()
        let wmType = WindowManagerType(rawValue: config.windowManager) ?? .auto
        
        switch wmType {
        case .yabai:
            return YabaiClient.shared
        case .aerospace:
            return AeroSpaceClient.shared
        case .auto:
            // Auto-detect: prefer yabai if available, otherwise aerospace
            if YabaiClient.shared.isRunning() {
                return YabaiClient.shared
            } else if AeroSpaceClient.shared.isRunning() {
                return AeroSpaceClient.shared
            } else {
                // Neither is running, default to yabai for alert purposes
                return YabaiClient.shared
            }
        }
    }
    
    private func printVersionAndExit() {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            print("Spacemap \(version)")
        } else {
            print("Spacemap 1.0.0")
        }
        NSApp.terminate(nil)
    }
    
    private func printHelpAndExit() {
        let help = """
        Usage: Spacemap [OPTIONS]
        
        Options:
          --version          Print the version and exit
          --trigger          Toggle the HUD visibility and exit
          --show-menu        Show the menu bar dropdown (app continues running)
          --settings         Open the settings window directly (app continues running)
          --config           Open the config file in the default editor and exit
          --help             Print this help and exit
        
        Without any options, Spacemap launches and waits for the hotkey (Ctrl+Space) to toggle the HUD.
        """
        print(help)
        NSApp.terminate(nil)
    }
    
    private func openConfigAndExit() {
        let configPath = NSString(string: "~/.config/spacemap/config").expandingTildeInPath
        let url = URL(fileURLWithPath: configPath)
        NSWorkspace.shared.open(url)
        NSApp.terminate(nil)
    }
    
    private func setupForTriggerAndExit() {
        // For --trigger, we still need minimal setup to toggle the HUD
        NSApp.setActivationPolicy(.prohibited)
        setupMenubar()
        // Delay slightly so TCC/LaunchServices finishes registering the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.hud.toggle()
            NSApp.terminate(nil)
        }
    }
    
    private func ensureSymlink() {
        let symlinkPath = "/usr/local/bin/spacemap"
        let executablePath = "/Applications/Spacemap.app/Contents/MacOS/spacemap"
        let fileManager = FileManager.default
        
        // Always remove any existing symlink first (handles broken/self-referential symlinks)
        try? fileManager.removeItem(atPath: symlinkPath)
        
        do {
            try fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: executablePath)
        } catch {
            print("Spacemap: failed to create symlink at \(symlinkPath): \(error)")
        }
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
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}