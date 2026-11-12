import XCTest
@testable import spacemap

final class ApplicationLifecycleServiceTests: XCTestCase {
    func testRuntimeConfigChangesAreEmptyForEquivalentConfig() {
        let config = GridConfig.default

        let changes = RuntimeConfigChanges(previous: config, current: config)
        XCTAssertFalse(changes.hotkeys)
        XCTAssertFalse(changes.socketListener)
        XCTAssertFalse(changes.updater)
        XCTAssertFalse(changes.yabaiSignals)
    }

    func testRuntimeConfigChangesIdentifyIndependentSideEffects() {
        let baseline = GridConfig.default

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
            alertsService: Alerts()
        )
        let lifecycle = ApplicationLifecycleService(services: services, hud: services.hud)
        var first = GridConfig.default
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
