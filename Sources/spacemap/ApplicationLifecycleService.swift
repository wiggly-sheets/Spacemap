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

        let refuseUntrusted = services.currentConfig.refuseUntrustedYabai
        YabaiClientImpl.refuseUntrustedBinaries = refuseUntrusted
        if let trustIssue = services.yabaiService.yabaiTrustIssue() {
            services.showYabaiUntrustedAlert(detail: trustIssue, refusing: refuseUntrusted)
        }

        let needsSeparateSpacesWarning = NSScreen.screens.count > 1 && !NSScreen.screensHaveSeparateSpaces
        DispatchQueue.global(qos: .utility).async {
            let mruSpacesEnabled = self.services.isMRUSpacesEnabled()
            DispatchQueue.main.async {
                if needsSeparateSpacesWarning {
                    self.services.showSeparateSpacesAlert()
                }
                if mruSpacesEnabled {
                    self.services.showMRUAlert()
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
            AppConfig.silentMode = true
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
                DispatchQueue.main.async {
                    self?.hud.refresh()
                    self?.services.refreshGlyphStrip()
                    self?.services.refreshMenubarPreview()
                }
            },
            onShow: { [weak self] in
                DispatchQueue.main.async {
                    self?.hud.show()
                    self?.services.refreshMenubarPreview()
                }
            },
            onToggle: { [weak self] in DispatchQueue.main.async { self?.hud.toggle() } },
            onSettings: { [weak self] in DispatchQueue.main.async { self?.services.showSettingsWindow() } }
        )
    }

    private func setupSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            AppConfig.silentMode = true
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

    static func shouldRestoreActivationPolicy(
        previous: NSApplication.ActivationPolicy,
        hasVisibleKeyWindow: Bool
    ) -> Bool {
        previous != .regular && !hasVisibleKeyWindow
    }

}
