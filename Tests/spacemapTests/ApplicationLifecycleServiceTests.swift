import XCTest
@testable import spacemap

final class ApplicationLifecycleServiceTests: XCTestCase {

    /// A config path that does not exist yet, removed at teardown. Loading it
    /// writes the default config there, never into the real user config.
    private func temporaryConfigPath() -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-test-config-\(UUID().uuidString).toml").path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    func testRuntimeConfigChangesAreEmptyForEquivalentConfig() {
        let config = SpacemapConfig.default

        let changes = RuntimeConfigChanges(previous: config, current: config)
        XCTAssertFalse(changes.hotkeys)
        XCTAssertFalse(changes.socketListener)
        XCTAssertFalse(changes.updater)
        XCTAssertFalse(changes.yabaiSignals)
    }

    func testRuntimeConfigChangesIdentifyIndependentSideEffects() {
        let baseline = SpacemapConfig.default

        var hotkeys = baseline
        hotkeys.hotkey = HotkeyConfig(key: .keyCode(122), modifiers: .maskControl)
        XCTAssertTrue(RuntimeConfigChanges(previous: baseline, current: hotkeys).hotkeys)

        var socket = baseline
        socket.socketHealthInterval += 1
        XCTAssertTrue(RuntimeConfigChanges(previous: baseline, current: socket).socketListener)

        var updater = baseline
        updater.updateMode = baseline.updateMode == .off ? .notify : .off
        XCTAssertTrue(RuntimeConfigChanges(previous: baseline, current: updater).updater)

        var signals = baseline
        signals.showHUDOnSpaceChange.toggle()
        XCTAssertTrue(RuntimeConfigChanges(previous: baseline, current: signals).yabaiSignals)
    }

    func testYabaiSignalRegistrationIsQueuedAndStaleRequestsAreCoalesced() {
        let yabaiService = MockYabaiService()
        yabaiService.runsYabaiQueueImmediately = false
        let services = SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        )
        let lifecycle = ApplicationLifecycleService(services: services, hud: services.hud)
        var first = SpacemapConfig.default
        first.showHUDOnSpaceChange = false
        var latest = first
        latest.showHUDOnSpaceChange = true

        lifecycle.scheduleYabaiSignalRegistration(config: first)
        lifecycle.scheduleYabaiSignalRegistration(config: latest)

        XCTAssertEqual(yabaiService.runOnYabaiQueueCallCount, 2)
        XCTAssertEqual(yabaiService.registerSignalsCallCount, 0)
        yabaiService.performPendingYabaiQueueBlocks()
        XCTAssertEqual(yabaiService.registerSignalsCallCount, 1)
        XCTAssertEqual(yabaiService.lastRegisterSignalsShowHUDOnSpaceChange, true)
    }

    func testYabaiDaemonRelaunchRegistersSignalsAgain() {
        let yabaiService = MockYabaiService()
        let services = SpacemapServices(
            yabaiService: yabaiService,
            configStore: ConfigStore(configPath: temporaryConfigPath()),
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        )
        let lifecycle = ApplicationLifecycleService(services: services, hud: services.hud)

        lifecycle.handleYabaiDaemonPID(4321)
        XCTAssertEqual(yabaiService.registerSignalsCallCount, 1, "a new daemon starts with no signals")
        XCTAssertEqual(yabaiService.resetYabaiRunningCacheCallCount, 1, "the running check must forget the old daemon")

        lifecycle.handleYabaiDaemonPID(4321)
        XCTAssertEqual(yabaiService.registerSignalsCallCount, 1, "polling the same daemon must not re-register")

        lifecycle.handleYabaiDaemonPID(nil)
        XCTAssertEqual(yabaiService.registerSignalsCallCount, 1, "downtime is not a registration trigger")

        lifecycle.handleYabaiDaemonPID(8765)
        XCTAssertEqual(yabaiService.registerSignalsCallCount, 2)
    }

    /// proc_listallpids returns a pid count, not a byte count. Reading it as
    /// bytes scanned a quarter of the list, so a daemon past that point was
    /// missed and the strip never re-registered its signals.
    func testDaemonScanCoversTheWholePIDListAndSkipsYabaiChildren() {
        let pids: [pid_t] = [501, 502, 503, 504, 505, 506, 507, 508]
        let paths: [pid_t: String] = [
            501: "/bin/zsh",
            502: "/usr/local/bin/yabai",
            508: "/usr/local/bin/yabai"
        ]
        // 502 is a yabai CLI call under a shell; 508 is the daemon at the end
        // of the list, past the quarter a byte count would have scanned.
        func scan(parents: [pid_t: pid_t]) -> pid_t? {
            ApplicationLifecycleService.yabaiDaemonPID(
                in: pids,
                filled: Int32(pids.count),
                executablePath: { paths[$0] },
                parentPID: { parents[$0] ?? 0 }
            )
        }

        XCTAssertEqual(
            scan(parents: [502: 501, 508: 1]),
            508,
            "only the launchd-owned yabai is the daemon, even at the end of the list"
        )
        XCTAssertNil(scan(parents: [502: 501]), "a yabai CLI child is not the daemon")
        XCTAssertNil(scan(parents: [:]), "no yabai process means no daemon")
    }

    func testShowSignalRefreshesTheGlyphStrip() {
        _ = NSApplication.shared
        let services = SpacemapServices(
            yabaiService: MockYabaiService(),
            configStore: ConfigStore(configPath: temporaryConfigPath()),
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        )
        let lifecycle = ApplicationLifecycleService(services: services, hud: services.hud)
        var config = SpacemapConfig.default
        config.glyphStrip.enabled = true
        services.applyGlyphStrip(config: config)
        let refreshesBefore = services.glyphStrip.refreshGeneration

        lifecycle.handleSocketShow()

        XCTAssertEqual(
            services.glyphStrip.refreshGeneration,
            refreshesBefore + 1,
            "a show signal must repaint the strip, which stays visible while the HUD is closed"
        )
    }

    func testDelayedWarningsDoNotDemoteAnOpenSettingsWindow() {
        XCTAssertFalse(ApplicationLifecycleService.shouldRestoreActivationPolicy(
            previous: .prohibited,
            hasVisibleKeyWindow: true
        ))
        XCTAssertTrue(ApplicationLifecycleService.shouldRestoreActivationPolicy(
            previous: .prohibited,
            hasVisibleKeyWindow: false
        ))
        XCTAssertFalse(ApplicationLifecycleService.shouldRestoreActivationPolicy(
            previous: .regular,
            hasVisibleKeyWindow: false
        ))
    }

    func testActivationPolicyRestoresOnlyWhenNoWindowIsVisible() {
        XCTAssertTrue(ApplicationLifecycleService.shouldRestoreActivationPolicy(
            previous: .accessory,
            hasVisibleKeyWindow: false
        ))
        XCTAssertFalse(ApplicationLifecycleService.shouldRestoreActivationPolicy(
            previous: .accessory,
            hasVisibleKeyWindow: true
        ))
        XCTAssertFalse(ApplicationLifecycleService.shouldRestoreActivationPolicy(
            previous: .regular,
            hasVisibleKeyWindow: true
        ))
    }

    func testSparkleUpdatePolicyCoversEveryMode() {
        let auto = SparkleUpdatePolicy(updateMode: .auto)
        XCTAssertTrue(auto.automaticallyChecksForUpdates)
        XCTAssertTrue(auto.automaticallyDownloadsUpdates)

        let notify = SparkleUpdatePolicy(updateMode: .notify)
        XCTAssertTrue(notify.automaticallyChecksForUpdates)
        XCTAssertFalse(notify.automaticallyDownloadsUpdates)

        let off = SparkleUpdatePolicy(updateMode: .off)
        XCTAssertFalse(off.automaticallyChecksForUpdates)
        XCTAssertFalse(off.automaticallyDownloadsUpdates)

        // A sequence through every mode must not leave downloads enabled when
        // automatic checks are turned off.
        var policy = auto
        for mode in [UpdateMode.notify, .off, .auto, .off] {
            policy = SparkleUpdatePolicy(updateMode: mode)
        }
        XCTAssertFalse(policy.automaticallyChecksForUpdates)
        XCTAssertFalse(policy.automaticallyDownloadsUpdates)
    }
}
