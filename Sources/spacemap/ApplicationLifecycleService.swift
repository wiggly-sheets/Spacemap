import AppKit
import Darwin
import Sparkle

struct RuntimeConfigChanges: Equatable {
    let hotkeys: Bool
    let socketListener: Bool
    let updater: Bool
    let yabaiSignals: Bool

    init(previous: SpacemapConfig?, current: SpacemapConfig) {
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
    private var currentConfig: SpacemapConfig?
    private let signalRegistrationCoordinator = YabaiSignalRegistrationCoordinator()
    private var windowSpaceTimer: Timer?
    private var windowSpaceSignature: String?
    private var windowSpacePollInFlight = false
    private var yabaiDaemonTimer: Timer?
    private var watchedYabaiDaemonPID: pid_t?


    init(services: SpacemapServices, hud: HUDWindowController) {
        self.services = services
        self.hud = hud
    }


    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments

        // Exit-only CLI paths must not prompt before AppKit starts.
        services.ensureCommandLineTools(allowAuthorizationPrompt: false)

        NSApp.setActivationPolicy(.prohibited)

        let refuseUntrusted = services.currentConfig.refuseUntrustedYabai
        YabaiClientImpl.refuseUntrustedBinaries = refuseUntrusted
        let needsSeparateSpacesWarning = NSScreen.screens.count > 1 && !NSScreen.screensHaveSeparateSpaces

        // pgrep/codesign spawn processes; keep both off the main thread and
        // present their alerts only after the results land.
        DispatchQueue.global(qos: .utility).async {
            let yabaiRunning = self.services.yabaiService.isYabaiRunning(forceRefresh: true)
            let trustIssue = self.services.yabaiService.yabaiTrustIssue()
            let mruSpacesEnabled = self.services.isMRUSpacesEnabled()
            DispatchQueue.main.async {
                if !yabaiRunning {
                    self.services.showYabaiAlert()
                }
                if let trustIssue {
                    self.services.showYabaiUntrustedAlert(detail: trustIssue, refusing: refuseUntrusted)
                }
                if needsSeparateSpacesWarning {
                    self.services.showSeparateSpacesAlert()
                }
                if mruSpacesEnabled {
                    self.services.showMRUAlert()
                }
            }
        }

        services.checkApplicationLocation()

        // Off-main font warmup: first strip paint never blocks on font IO.
        DispatchQueue.global(qos: .utility).async {
            AppGlyphFont.prewarmInBackground()
        }

        services.ensureCommandLineTools(allowAuthorizationPrompt: true)

        services.setupMenubar()
        services.setDeepLinksReady()

        _ = services.sparkleController

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            ConfigStore.silentMode = true
            let config = self.services.currentConfig
            self.currentConfig = config
            self.hud.reloadConfig()
            self.hud.prewarmState()
            self.services.restartHotkeys(config: config)
            self.services.applyPresence(config: config)
            self.services.refreshMenubarPreview(config: config)
            self.services.applyGlyphStrip(config: config)
            self.hud.onShowSettings = { [weak self] in self?.services.showSettingsWindow() }
            self.setupSocketListener(config: config)

            self.setupSettingsObserver()

            if !SystemPermissions.hasAccessibility {
                SystemPermissions.requestAccessibility()
                // Show the privacy pane before the drag helper so the icon has
                // a visible target. The legacy anchor still resolves on macOS 27,
                // where the pane is titled Device Control and Data Access.
                SystemPermissions.openAccessibilitySettings()
                PermissionDragWindowController.shared.show()
            }

            if config.cellStyle == .thumbnails, !SystemPermissions.hasScreenRecording {
                SystemPermissions.requestScreenRecording()
                SystemPermissions.openScreenRecordingSettings()
            }

            AccessibilityHealthMonitor.shared.start()
            services.themeCatalog.start()
            self.startWindowSpaceWatcher()
            self.startYabaiDaemonWatcher()
            self.services.configureSparkleUpdater(updateMode: config.updateMode)

            if config.appFont.updateMode == .auto {
                self.checkAppFontUpdate(config: config)
            }
        }

        // Order matches the historical checks: the menu first, then Settings.
        let delivered = CLIFlagTable.deliveredCommands(in: args)
        if delivered.contains(.showMenu) {
            self.services.showMenubarMenu()
        }
        if delivered.contains(.settings) {
            self.services.showSettingsWindow()
        }
    }

    /// Auto mode: at most one GitHub fetch per 24h (rate-limit guard across
    /// restarts); downloads only when the release tag differs. Never blocks
    /// launch — failures log and retry on the next launch (lastCheck stays put).
    private func checkAppFontUpdate(config: SpacemapConfig) {
        let now = Int(Date().timeIntervalSince1970)
        guard config.appFont.lastCheck == 0
            || now - config.appFont.lastCheck >= Int(AppFontUpdater.checkInterval) else { return }

        let installedTag = config.appFont.installedVersion
        let hadFace = AppGlyphFont.load() != nil
        Task {
            do {
                switch try await AppFontUpdater.runCheck(installedTag: installedTag) {
                case .upToDate:
                    AppFontUpdater.recordCheck(installedTag: nil)
                case .updated(let info):
                    AppFontUpdater.recordCheck(installedTag: info.tag)
                    NSLog("spacemap/AppFont: updated sketchybar-app-font to \(info.tag)")
                    if hadFace {
                        AppFontUpdater.relaunchIfGlyphStripUsesFont(config)
                    }
                }
            } catch {
                NSLog("spacemap/AppFont: update check failed — \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        signalRegistrationCoordinator.invalidate()
        stopWindowSpaceWatcher()
        yabaiDaemonTimer?.invalidate()
        yabaiDaemonTimer = nil
        services.yabaiService.removeSignals()
        socketListener?.stop()
        services.stopHotkeys()
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }


    private func setupSocketListener(config: SpacemapConfig) {
        socketListener?.stop()
        let socketPath = SpacemapCommand.socketPath
        // Write (or reuse) the nonce before registration. Yabai actions embed
        // it verbatim; registering without one would create bare frames that
        // the listener drops.
        let nonce = SocketListener.prepareNonceForProcess(for: socketPath)
        socketListener = services.makeSocketListener(
            socketPath: socketPath,
            healthInterval: config.socketHealthInterval,
            onRefresh: { [weak self] in
                DispatchQueue.main.async {
                    self?.services.yabaiService.invalidateSnapshotCaches()
                    self?.hud.refresh()
                    self?.services.refreshGlyphStrip()
                    self?.services.refreshMenubarPreview()
                }
            },
            onShow: { [weak self] in
                DispatchQueue.main.async { self?.handleSocketShow() }
            },
            onToggle: { [weak self] in DispatchQueue.main.async { self?.hud.toggle() } },
            onSettings: { [weak self] in DispatchQueue.main.async { self?.services.showSettingsWindow() } },
            onReloadConfig: { [weak self] in
                DispatchQueue.main.async { self?.applyConfigReplacedExternally() }
            },
            onUpdate: { [weak self] in
                DispatchQueue.main.async { self?.services.checkForUpdates() }
            },
            onUpdateFont: { [weak self] in
                DispatchQueue.main.async { self?.services.checkForFontUpdate() }
            }
        )
        // stop() preserves the nonce, but rebuilding the listener is the
        // moment to re-embed it: a previous registration may have captured a
        // missing/old value.
        if nonce != nil {
            scheduleYabaiSignalRegistration(config: config)
        } else {
            NSLog("spacemap/lifecycle: nonce unavailable — yabai signals not registered")
        }
    }

    /// Show signal: the HUD opens, and every always-on surface repaints. The
    /// strip stays visible while the HUD is closed, so a space switch that
    /// asks for the HUD also has to refresh it.
    func handleSocketShow() {
        services.yabaiService.invalidateSnapshotCaches()
        hud.show()
        services.refreshGlyphStrip()
        services.refreshMenubarPreview()
    }

    /// yabai signals cover window creation, focus, and frame changes but not a
    /// window moving to another space. Poll a small membership fingerprint so
    /// the strip and HUD repaint within half a second.
    private func startWindowSpaceWatcher() {
        guard windowSpaceTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.pollWindowSpaces()
        }
        RunLoop.main.add(timer, forMode: .common)
        windowSpaceTimer = timer
    }

    private func stopWindowSpaceWatcher() {
        windowSpaceTimer?.invalidate()
        windowSpaceTimer = nil
        windowSpaceSignature = nil
        windowSpacePollInFlight = false
    }

    private func pollWindowSpaces() {
        guard !windowSpacePollInFlight, currentConfig?.needsWorkspacePreviews == true else { return }
        windowSpacePollInFlight = true
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            let signature = (try? self.services.yabaiService.windowSpaceSignature()) ?? nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.windowSpacePollInFlight = false
                guard let signature else { return }
                let previous = self.windowSpaceSignature
                self.windowSpaceSignature = signature
                guard let previous, previous != signature else { return }
                self.services.yabaiService.invalidateSnapshotCaches()
                self.hud.refresh()
                self.services.refreshGlyphStrip()
                self.services.refreshMenubarPreview()
            }
        }
    }

    /// Signals live in the yabai daemon, so a restarted daemon knows none of
    /// them and stops reporting space changes. Watch the daemon process and
    /// register again when a new one appears.
    private func startYabaiDaemonWatcher() {
        guard yabaiDaemonTimer == nil else { return }
        // The launch path just registered signals for the daemon running now,
        // so adopt it: only a later replacement is new. One scan at launch; the
        // repeating poll stays off main.
        watchedYabaiDaemonPID = Self.currentYabaiDaemonPID()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.pollYabaiDaemon()
        }
        RunLoop.main.add(timer, forMode: .common)
        yabaiDaemonTimer = timer
    }

    private func pollYabaiDaemon() {
        // Scanning the process list touches every pid; keep it off main.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let pid = Self.currentYabaiDaemonPID()
            DispatchQueue.main.async { self?.handleYabaiDaemonPID(pid) }
        }
    }

    /// A daemon that was not seen before starts with an empty signal table, so
    /// register again and repaint: the strip may still show the focus from
    /// before the restart. This also heals a launch where yabai was not yet up.
    func handleYabaiDaemonPID(_ pid: pid_t?) {
        guard pid != watchedYabaiDaemonPID else { return }
        watchedYabaiDaemonPID = pid
        // Downtime itself needs no work; the replacement daemon is the trigger.
        guard pid != nil else { return }
        services.yabaiService.resetYabaiRunningCache()
        services.yabaiService.invalidateSnapshotCaches()
        scheduleYabaiSignalRegistration(config: currentConfig ?? services.currentConfig)
        services.refreshGlyphStrip()
    }

    /// Process id of the yabai daemon: the launchd-owned process running the
    /// yabai binary. Nil while yabai is not running.
    static func currentYabaiDaemonPID() -> pid_t? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 16)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return nil }
        return yabaiDaemonPID(
            in: pids,
            filled: filled,
            executablePath: Self.executablePath(of:),
            parentPID: Self.parentPID(of:)
        )
    }

    /// Picks the daemon out of a process list. `filled` is the pid count that
    /// `proc_listallpids` returned, not a byte count: dividing by the pid size
    /// scanned a quarter of the list, and a daemon late in it was missed. The
    /// lookups are injected so tests drive the match rule without real
    /// processes. Short-lived `yabai` CLI calls run the same binary, so the
    /// parent pid (1 for a launchd agent) tells the daemon apart.
    static func yabaiDaemonPID(
        in pids: [pid_t],
        filled: Int32,
        executablePath: (pid_t) -> String?,
        parentPID: (pid_t) -> pid_t?
    ) -> pid_t? {
        for pid in pids.prefix(Int(max(filled, 0))) where pid > 0 {
            guard let path = executablePath(pid),
                  URL(fileURLWithPath: path).lastPathComponent == "yabai",
                  parentPID(pid) == 1 else { continue }
            return pid
        }
        return nil
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(cString: path)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }


    /// An external process replaced config.toml (CLI preset switch). Re-apply
    /// the file; an open Settings window rebuilds on the second notification.
    private func applyConfigReplacedExternally() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        NotificationCenter.default.post(name: .configReplacedExternally, object: nil)
    }

    private func setupSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            ConfigStore.silentMode = true
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
            self.services.applyPresence(config: config)
            self.services.refreshMenubarPreview(config: config)
            self.services.applyGlyphStrip(config: config)
            if changes.yabaiSignals {
                self.scheduleYabaiSignalRegistration(config: config)
            }
        }
    }

    func scheduleYabaiSignalRegistration(config: SpacemapConfig) {
        let generation = signalRegistrationCoordinator.nextGeneration()
        // Once a listener exists its frames require a nonce. Never register an
        // action that would send a bare frame the listener must drop.
        let requiresNonce = socketListener != nil
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self,
                  self.signalRegistrationCoordinator.isCurrent(generation) else { return }
            if requiresNonce,
               SpacemapCommand.currentNonceHex(for: SpacemapCommand.socketPath) == nil {
                NSLog("spacemap/lifecycle: nonce missing — skipping yabai signal registration")
                return
            }
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
