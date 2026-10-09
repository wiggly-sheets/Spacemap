import AppKit
import Sparkle

struct RuntimeConfigChanges: Equatable {
    let hotkeys: Bool
    let socketListener: Bool
    let updater: Bool
    let yabaiSignals: Bool

    init(previous: GridConfig?, current: GridConfig) {
        func sameHotkey(_ previous: HotkeyConfig?, _ current: HotkeyConfig) -> Bool {
            previous?.key == current.key && previous?.modifiers == current.modifiers
        }

        hotkeys = !sameHotkey(previous?.hotkey, current.hotkey) ||
            !sameHotkey(previous?.pinnedHotkey, current.pinnedHotkey) ||
            !sameHotkey(previous?.glyphStripHotkey, current.glyphStripHotkey)
        socketListener = previous?.socketHealthInterval != current.socketHealthInterval
        updater = previous?.updateMode != current.updateMode
        yabaiSignals =
            previous?.showHUDOnSpaceChange != current.showHUDOnSpaceChange ||
            previous.map(\.needsWorkspacePreviews) != current.needsWorkspacePreviews ||
            previous.map(\.needsWindowGeometryPreviews) != current.needsWindowGeometryPreviews
    }
}

final class YabaiSignalRegistrationCoordinator {
    private let lock = NSLock()
    private var generation = 0

    func nextGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    func isCurrent(_ candidate: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return candidate == generation
    }

    func invalidate() {
        _ = nextGeneration()
    }
}

final class ApplicationLifecycleService {


    let services: SpacemapServices
    let hud: HUDWindowController


    private var socketListener: SocketListener?
    private var settingsObserver: NSObjectProtocol?
    private var currentConfig: GridConfig?
    private let signalRegistrationCoordinator = YabaiSignalRegistrationCoordinator()


    init(services: SpacemapServices, hud: HUDWindowController) {
        self.services = services
        self.hud = hud
    }


    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments

        // Exit-only CLI paths must not prompt before AppKit starts.
        services.ensureCommandLineTools(allowAuthorizationPrompt: false)

        NSApp.setActivationPolicy(.prohibited)

        if !services.yabaiService.isYabaiRunning(forceRefresh: true) {
            services.showYabaiAlert()
        }

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

        services.checkApplicationLocation()

        // Off-main font warmup + bundled-face registration: first strip paint
        // never blocks on font IO, and a fresh install resolves NSFont before
        // any refresh runs.
        DispatchQueue.global(qos: .utility).async {
            AppGlyphFont.ensureRegistered()
            AppGlyphFont.prewarmInBackground()
        }

        services.ensureCommandLineTools(allowAuthorizationPrompt: true)

        services.setupMenubar()
        services.setDeepLinksReady()

        _ = services.sparkleController

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            Config.silentMode = true
            let config = self.services.currentConfig
            self.currentConfig = config
            self.hud.reloadConfig()
            self.hud.prewarmState()
            self.services.restartHotkeys(config: config)
            self.services.applyMenubarVisibility(config: config)
            self.services.refreshMenubarPreview(config: config)
            self.services.applyGlyphStrip(config: config)
            self.hud.onShowSettings = { [weak self] in self?.services.showSettingsWindow() }
            self.setupSocketListener(config: config)
            self.scheduleYabaiSignalRegistration(config: config)

            self.setupSettingsObserver()

            self.services.configureSparkleUpdater(updateMode: config.updateMode)

            if config.appFont.updateMode == .auto {
                self.checkAppFontUpdate(config: config)
            }
        }

        #if !DEBUG
        if args.contains("--show-menu") {
            self.services.showMenubarMenu()
        }
        if args.contains("--settings") {
            self.services.showSettingsWindow()
        }
        #endif
    }

    /// Auto mode: at most one GitHub fetch per 24h (rate-limit guard across
    /// restarts); downloads only when the release tag differs. Never blocks
    /// launch — failures log and retry on the next launch (lastCheck stays put).
    private func checkAppFontUpdate(config: GridConfig) {
        let now = Int(Date().timeIntervalSince1970)
        guard config.appFont.lastCheck == 0
            || now - config.appFont.lastCheck >= Int(AppFontUpdater.checkInterval) else { return }

        let installedTag = config.appFont.installedVersion
        Task {
            do {
                switch try await AppFontUpdater.runCheck(installedTag: installedTag) {
                case .upToDate:
                    AppFontUpdater.recordCheck(installedTag: nil)
                case .updated(let info):
                    AppFontUpdater.recordCheck(installedTag: info.tag)
                    NSLog("spacemap/AppFont: updated sketchybar-app-font to \(info.tag)")
                }
            } catch {
                NSLog("spacemap/AppFont: update check failed — \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        signalRegistrationCoordinator.invalidate()
        services.yabaiService.removeSignals()
        socketListener?.stop()
        services.stopHotkeys()
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }


    private func setupSocketListener(config: GridConfig) {
        socketListener?.stop()
        socketListener = services.makeSocketListener(
            socketPath: SpacemapCommand.socketPath,
            healthInterval: config.socketHealthInterval,
            onRefresh: { [weak self] in
                self?.hud.refresh()
                self?.services.refreshGlyphStrip()
                self?.services.refreshMenubarPreview()
            },
            onShow: { [weak self] in
                self?.hud.show()
                self?.services.refreshMenubarPreview()
            },
            onToggle: { [weak self] in self?.hud.toggle() },
            onSettings: { [weak self] in self?.services.showSettingsWindow() }
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
            let changes = RuntimeConfigChanges(previous: self.currentConfig, current: config)
            self.currentConfig = config
            self.hud.reloadConfig()
            if changes.hotkeys {
                self.services.restartHotkeys(config: config)
            }
            if changes.socketListener {
                self.setupSocketListener(config: config)
            }
            if changes.updater {
                self.services.configureSparkleUpdater(updateMode: config.updateMode)
            }
            self.services.applyMenubarVisibility(config: config)
            self.services.refreshMenubarPreview(config: config)
            self.services.applyGlyphStrip(config: config)
            if changes.yabaiSignals {
                self.scheduleYabaiSignalRegistration(config: config)
            }
        }
    }

    func scheduleYabaiSignalRegistration(config: GridConfig) {
        let generation = signalRegistrationCoordinator.nextGeneration()
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self,
                  self.signalRegistrationCoordinator.isCurrent(generation) else { return }
            self.services.yabaiService.registerSignals(
                socketPath: SpacemapCommand.socketPath,
                showHUDOnSpaceChange: config.showHUDOnSpaceChange,
                refreshWorkspacePreviews: config.needsWorkspacePreviews,
                refreshWindowGeometry: config.needsWindowGeometryPreviews
            )
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
        let previousActivationPolicy = NSApp.activationPolicy()
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
        restoreActivationPolicy(previousActivationPolicy)
    }

    private func showSeparateSpacesAlert() {
        let previousActivationPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Displays Have Separate Spaces Disabled", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap needs Displays have separate Spaces enabled to show and navigate each monitor independently. Enable it in System Settings, then log out and back in before using multi-monitor HUD modes.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Leave as Is", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open System Settings", comment: ""))

        if alert.runModal() == .alertSecondButtonReturn {
            _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
        restoreActivationPolicy(previousActivationPolicy)
    }

    private func restoreActivationPolicy(_ previousActivationPolicy: NSApplication.ActivationPolicy) {
        let hasVisibleKeyWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        if Self.shouldRestoreActivationPolicy(
            previous: previousActivationPolicy,
            hasVisibleKeyWindow: hasVisibleKeyWindow
        ) {
            NSApp.setActivationPolicy(previousActivationPolicy)
        }
    }

    static func shouldRestoreActivationPolicy(
        previous: NSApplication.ActivationPolicy,
        hasVisibleKeyWindow: Bool
    ) -> Bool {
        previous != .regular && !hasVisibleKeyWindow
    }

}
