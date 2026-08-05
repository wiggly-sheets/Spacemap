import AppKit
import ServiceManagement
import Sparkle

/// Handles the application lifecycle events (launch, terminate) by coordinating
/// various services and performing necessary setup/teardown.
final class ApplicationLifecycleService {

    // MARK: - Dependencies

    let services: SpacemapServices
    let hud: HUDWindowController

    // MARK: - Private State

    private var socketListener: SocketListener?
    private var settingsObserver: NSObjectProtocol?
    private var settingsWindowObserver: NSObjectProtocol?
    private var currentConfig: GridConfig?
    private var isReadyForDeepLinks = false
    private var pendingDeepLinks: [DeepLinkAction] = []

    // MARK: - Private State for Hotkey Monitors

    private var hotkeyMonitor: HotkeyMonitor?
    private var pinnedHotkeyMonitor: HotkeyMonitor?

    // MARK: - Initialization

    init(services: SpacemapServices, hud: HUDWindowController) {
        self.services = services
        self.hud = hud
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments

        // Keep the CLI and manual available when permissions allow.
        // Exit-only CLI commands must never trigger an administrator prompt.
        services.ensureCommandLineTools(allowAuthorizationPrompt: false)

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
        services.ensureCommandLineTools(allowAuthorizationPrompt: true)

        services.setupMenubar()
        isReadyForDeepLinks = true
        services.handlePendingDeepLinks()

        // Trigger Sparkle initialization early so updater starts on launch
        _ = services.sparkleController

        // Delay slightly so TCC/LaunchServices finishes registering the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            Config.silentMode = true
            let config = self.services.currentConfig
            self.currentConfig = config
            self.hud.reloadConfig()
            self.hud.prewarmState()
            self.restartHotkey(config: config)
            self.services.applyMenubarVisibility(config: config)
            self.services.refreshMenubarPreview(config: config)
            self.hud.onShowSettings = { [weak self] in self?.services.showSettingsWindow() }
            self.setupSocketListener(config: config)
            self.services.yabaiService.registerSignals(
                socketPath: SpacemapCommand.socketPath,
                showHUDOnSpaceChange: config.showHUDOnSpaceChange,
                refreshWorkspacePreviews: self.workspacePreviewsEnabled(for: config),
                refreshWindowGeometry: self.windowGeometryPreviewsEnabled(for: config)
            )

            // Observe settings changes to update hotkey
            self.setupSettingsObserver()

            self.services.configureSparkleUpdater(updateMode: config.updateMode)
        }

        #if !DEBUG
        if args.contains("--show-menu") {
            // Show menu and continue running
            self.services.showMenubarMenu()
        }
        if args.contains("--settings") {
            // Show settings window and continue running
            self.services.showSettingsWindow()
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.yabaiService.removeSignals()
        socketListener?.stop()
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        pinnedHotkeyMonitor?.stop()
        pinnedHotkeyMonitor = nil
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = settingsWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Private Helpers

    private func setupSocketListener(config: GridConfig) {
        socketListener = services.makeSocketListener(
            socketPath: SpacemapCommand.socketPath,
            healthInterval: config.socketHealthInterval,
            onRefresh: { [weak self] in
                self?.hud.refresh()
                self?.services.refreshMenubarPreview()
            },
            onShow: { [weak self] in
                self?.hud.show()
                self?.services.refreshMenubarPreview()
            },
            onToggle: { [weak self] in self?.hud.toggle() },
            onSettings: { [weak self] in self?.showSettingsWindow() }
        )
    }

    private func setupSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Config.silentMode = true
            let config = self.services.currentConfig
            let shouldUpdateYabaiSignals =
                self.currentConfig?.showHUDOnSpaceChange != config.showHUDOnSpaceChange ||
                self.currentConfig.map { self.workspacePreviewsEnabled(for: $0) } !=
                    self.workspacePreviewsEnabled(for: config) ||
                self.currentConfig.map { self.windowGeometryPreviewsEnabled(for: $0) } !=
                    self.windowGeometryPreviewsEnabled(for: config)
            self.currentConfig = config
            self.hud.reloadConfig()
            self.services.restartHotkey(config: config)
            self.services.applyMenubarVisibility(config: config)
            self.services.refreshMenubarPreview(config: config)
            if shouldUpdateYabaiSignals {
                self.services.yabaiService.registerSignals(
                    socketPath: SpacemapCommand.socketPath,
                    showHUDOnSpaceChange: config.showHUDOnSpaceChange,
                    refreshWorkspacePreviews: self.workspacePreviewsEnabled(for: config),
                    refreshWindowGeometry: self.windowGeometryPreviewsEnabled(for: config)
                )
            }
        }
    }

    private func showSettingsWindow() {
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

        var config = services.currentConfig
        config.updateMode = updateMode
        services.appConfig.save(config)
        services.configureSparkleUpdater(updateMode: updateMode)
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

    private func restartHotkey(config: GridConfig) {
        // Stop any existing monitors
        stopHotkeyMonitors()
        // Start new ones based on the config
        startHotkeyMonitors(for: config)
    }

    private func stopHotkeyMonitors() {
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        pinnedHotkeyMonitor?.stop()
        pinnedHotkeyMonitor = nil
    }

    private func startHotkeyMonitors(for config: GridConfig) {
        guard !config.hotkey.isDisabled else {
            print("Spacemap: hotkey disabled")
            return
        }
        let monitor = HotkeyMonitor(config: config.hotkey) { [weak self] in
            self?.hud.toggle()
        }
        monitor.start()
        hotkeyMonitor = monitor

        guard !config.pinnedHotkey.isDisabled else {
            print("Spacemap: pinned HUD hotkey disabled")
            return
        }
        guard Hotkey.hotkeyToString(config.pinnedHotkey) != Hotkey.hotkeyToString(config.hotkey) else {
            NSLog("Spacemap: pinned HUD hotkey matches the normal hotkey; pinned binding ignored")
            return
        }
        let pinnedMonitor = HotkeyMonitor(config: config.pinnedHotkey) { [weak self] in
            self?.hud.togglePinned()
        }
        pinnedMonitor.start()
        pinnedHotkeyMonitor = pinnedMonitor
    }

    // MARK: - Private Helpers (continued)

    private func workspacePreviewsEnabled(for config: GridConfig) -> Bool {
        !config.hideMenuBarIcon && config.menuBarDisplayMode != .icon
    }

    private func windowGeometryPreviewsEnabled(for config: GridConfig) -> Bool {
        workspacePreviewsEnabled(for: config) && config.menuBarDisplayMode != .dots
    }
}