import XCTest
import CoreGraphics
@testable import spacemap

final class HotkeyRouterTests: HotkeyTestCase {
    func testEventTapRecoveryPolicy() {
        let cases: [(Bool, Bool, Bool, Bool, EventTapHost.RecoveryAction)] = [
            (false, false, false, false, .waitForPermission),
            (false, true, true, true, .remove),
            (true, false, false, false, .install),
            (true, true, false, false, .reinstall),
            (true, true, true, false, .reenable),
            (true, true, true, true, .none)
        ]

        for (trusted, hasTap, valid, enabled, expected) in cases {
            XCTAssertEqual(
                EventTapHost.recoveryAction(
                    isTrusted: trusted,
                    hasTap: hasTap,
                    tapIsValid: valid,
                    tapIsEnabled: enabled
                ),
                expected
            )
        }
    }

    func testEventTapNeverConsumesMatchingShortcutAfterAccessibilityRevocation() {
        XCTAssertEqual(
            HotkeyMonitor.keyEventDecision(
                isTrusted: false,
                type: .keyDown,
                isAutoRepeat: false,
                keyCode: 40,
                flags: [.maskCommand, .maskShift],
                targetKey: .keyCode(40),
                targetModifiers: [.maskCommand, .maskShift]
            ),
            .passThrough
        )
    }

    func testMatchingHotkeyRepeatsStayConsumedWithoutRetriggering() {
        let initial = HotkeyMonitor.keyEventDecision(
            isTrusted: true,
            type: .keyDown,
            isAutoRepeat: false,
            keyCode: 40,
            flags: [.maskCommand, .maskShift],
            targetKey: .keyCode(40),
            targetModifiers: [.maskCommand, .maskShift]
        )
        let repeated = HotkeyMonitor.keyEventDecision(
            isTrusted: true,
            type: .keyDown,
            isAutoRepeat: true,
            keyCode: 40,
            flags: [.maskCommand, .maskShift],
            targetKey: .keyCode(40),
            targetModifiers: [.maskCommand, .maskShift]
        )

        XCTAssertEqual(initial, .init(shouldConsume: true, shouldTrigger: true))
        XCTAssertEqual(repeated, .init(shouldConsume: true, shouldTrigger: false))
    }

    func testHotkeyHandlerRestartStopsEveryPreviousMonitor() {
        let factory = RecordingHotkeyMonitorFactory()
        let handler = HotkeyHandler(
            hotkeyMonitorFactory: factory,
            onToggle: {},
            onTogglePinned: {}
        )
        var config = SpacemapConfig.default
        config.pinnedHotkey = HotkeyConfig(key: .keyCode(122), modifiers: .maskControl)

        handler.restartHotkeys(config: config)
        XCTAssertEqual(factory.monitors.count, 2)
        XCTAssertTrue(factory.monitors.allSatisfy { $0.startCount == 1 && $0.stopCount == 0 })

        handler.restartHotkeys(config: config)
        XCTAssertEqual(factory.monitors.count, 4)
        XCTAssertTrue(factory.monitors.prefix(2).allSatisfy { $0.stopCount == 1 })
        XCTAssertTrue(factory.monitors.suffix(2).allSatisfy { $0.startCount == 1 && $0.stopCount == 0 })

        handler.stopHotkeys()
        XCTAssertTrue(factory.monitors.allSatisfy { $0.stopCount == 1 })
    }

    func testGlyphStripHotkeyStartsAThirdMonitor() {
        let factory = RecordingHotkeyMonitorFactory()
        let handler = HotkeyHandler(
            hotkeyMonitorFactory: factory,
            onToggle: {},
            onTogglePinned: {}
        )
        var config = SpacemapConfig.default
        config.pinnedHotkey = HotkeyConfig(key: .keyCode(122), modifiers: .maskControl)
        config.glyphStripHotkey = HotkeyConfig(key: .keyCode(114), modifiers: .maskControl)

        handler.restartHotkeys(config: config)
        XCTAssertEqual(factory.monitors.count, 3, "hotkey + pinned + glyph strip")

        handler.restartHotkeys(config: config)
        XCTAssertEqual(factory.monitors.count, 6, "the third monitor restarts too")
        XCTAssertTrue(factory.monitors.suffix(3).allSatisfy { $0.startCount == 1 && $0.stopCount == 0 })
        XCTAssertTrue(factory.monitors.prefix(3).allSatisfy { $0.stopCount == 1 })

        handler.stopHotkeys()
        XCTAssertTrue(factory.monitors.allSatisfy { $0.stopCount == 1 })
    }

    func testMatchingKeyUpIsConsumedWithoutTriggering() {
        XCTAssertEqual(
            HotkeyMonitor.keyEventDecision(
                isTrusted: true,
                type: .keyUp,
                isAutoRepeat: false,
                keyCode: 40,
                flags: [.maskCommand, .maskShift],
                targetKey: .keyCode(40),
                targetModifiers: [.maskCommand, .maskShift]
            ),
            .init(shouldConsume: true, shouldTrigger: false)
        )
    }

    func testEventTapObservesKeyDownKeyUpAndSystemDefined() {
        let mask = HotkeyMonitor.eventTapMask
        XCTAssertNotEqual(mask & (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)), 0)
        XCTAssertNotEqual(mask & (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue)), 0)
        XCTAssertNotEqual(
            mask & (CGEventMask(1) << CGEventMask(HotkeyMonitor.systemDefinedEventRawValue)),
            0
        )
    }

    func testRouterRetriesFailedTapCreation() {
        let router = HotkeyTapRouter(
            tapFactory: { _, _, _, _, _, _ in nil },
            trustProvider: { true },
            promptProvider: { _ in true }
        )
        router.addBinding(id: UUID(), key: .keyCode(40), modifiers: [.maskCommand]) {}

        XCTAssertEqual(router.tapCreationAttempts, 1)
        XCTAssertEqual(router.tapCreationFailureCount, 1)
        XCTAssertFalse(router.hasTapContext, "failed install must release its tap context")
        XCTAssertFalse(router.isEventTapInstalled)

        router.reconcile(promptIfNeeded: false)
        XCTAssertEqual(router.tapCreationAttempts, 2)
        XCTAssertEqual(router.tapCreationFailureCount, 2)
        router.stop()
    }

    func testRouterWaitsForAccessibilityBeforeCreatingTap() {
        var isTrusted = false
        var attempts = 0
        let router = HotkeyTapRouter(
            tapFactory: { _, _, _, _, _, _ in
                attempts += 1
                return nil
            },
            trustProvider: { isTrusted },
            promptProvider: { _ in isTrusted }
        )
        router.addBinding(id: UUID(), key: .keyCode(40), modifiers: [.maskCommand]) {}

        XCTAssertEqual(attempts, 0)
        isTrusted = true
        router.reconcile(promptIfNeeded: false)
        XCTAssertEqual(attempts, 1)
        router.stop()
    }

    func testRouterCreatesTapOnTapThreadWithKeyboardMask() throws {
        var creation: (CGEventTapLocation, CGEventTapPlacement, CGEventTapOptions, CGEventMask)?
        let router = HotkeyTapRouter(
            tapFactory: { location, place, options, mask, _, _ in
                creation = (location, place, options, mask)
                return nil
            },
            trustProvider: { true },
            promptProvider: { _ in true }
        )

        router.addBinding(id: UUID(), key: .keyCode(40), modifiers: [.maskCommand]) {}

        let tap = try XCTUnwrap(creation)
        XCTAssertEqual(tap.0, .cgSessionEventTap)
        XCTAssertEqual(tap.1, .headInsertEventTap, "the router tap sees keys first")
        XCTAssertEqual(tap.2, .defaultTap, "the router consumes matched keys")
        XCTAssertEqual(tap.3, HotkeyMonitor.eventTapMask)
        router.stop()
    }

    func testRouterRemovesBindingsAndDeallocates() {
        var router: HotkeyTapRouter? = HotkeyTapRouter(
            tapFactory: { _, _, _, _, _, _ in nil },
            trustProvider: { true },
            promptProvider: { _ in true }
        )
        weak var weakRouter = router
        let id = UUID()

        router?.addBinding(id: id, key: .keyCode(40), modifiers: [.maskCommand]) {}
        XCTAssertEqual(router?.registeredBindingCount, 1)

        router?.removeBinding(id: id)
        XCTAssertEqual(router?.registeredBindingCount, 0)
        router = nil

        XCTAssertNil(weakRouter)
    }

    func testHotkeyMonitorRegistersAndUnregistersOneBinding() {
        let router = HotkeyTapRouter(
            tapFactory: { _, _, _, _, _, _ in nil },
            trustProvider: { true },
            promptProvider: { _ in true }
        )
        let monitor = HotkeyMonitor(
            config: HotkeyConfig(key: .keyCode(40), modifiers: [.maskCommand]),
            onTrigger: {},
            router: router
        )

        monitor.start()
        XCTAssertEqual(router.registeredBindingCount, 1)
        monitor.stop()
        XCTAssertEqual(router.registeredBindingCount, 0)
    }

    func testHotkeyHandlerDeinitStopsEveryMonitor() {
        let factory = RecordingHotkeyMonitorFactory()
        var handler: HotkeyHandler? = HotkeyHandler(
            hotkeyMonitorFactory: factory,
            onToggle: {},
            onTogglePinned: {}
        )

        handler?.restartHotkeys(config: .default)
        XCTAssertEqual(factory.monitors.count, 1)
        handler = nil

        XCTAssertTrue(factory.monitors.allSatisfy { $0.stopCount == 1 })
    }

    func testHotkeyHandlerTreatsFNVariantAsDuplicate() {
        let factory = RecordingHotkeyMonitorFactory()
        let handler = HotkeyHandler(
            hotkeyMonitorFactory: factory,
            onToggle: {},
            onTogglePinned: {}
        )
        var config = SpacemapConfig.default
        config.hotkey = HotkeyConfig(key: .keyCode(122), modifiers: [])
        config.pinnedHotkey = HotkeyConfig(key: .keyCode(122), modifiers: [.maskSecondaryFn])

        handler.restartHotkeys(config: config)

        XCTAssertEqual(factory.monitors.count, 1, "f1 and fn+f1 are the same physical binding")
    }

    func testRouterRoutesMultipleBindingsAndHopsTriggers() {
        let router = makeRouter()
        var firstCount = 0
        var secondCount = 0
        router.addBinding(id: UUID(), key: .keyCode(40), modifiers: [.maskCommand]) {
            firstCount += 1
        }
        router.addBinding(id: UUID(), key: .keyCode(41), modifiers: [.maskCommand]) {
            secondCount += 1
        }

        let matching = makeKeyEvent(keyCode: 40, flags: [.maskCommand])
        XCTAssertNil(router.handle(type: .keyDown, event: matching))
        XCTAssertEqual(firstCount, 0, "trigger must hop to main")
        pumpMainQueue()
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 0)

        let unmatched = makeKeyEvent(keyCode: 42, flags: [.maskCommand])
        XCTAssertNotNil(router.handle(type: .keyDown, event: unmatched))
        pumpMainQueue()
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 0)

        router.stop()
    }

    func testRouterConsumesMatchingKeyUpWithoutTriggering() {
        let router = makeRouter()
        var count = 0
        router.addBinding(id: UUID(), key: .keyCode(40), modifiers: [.maskCommand]) {
            count += 1
        }

        let release = makeKeyEvent(keyCode: 40, flags: [.maskCommand], keyDown: false)
        XCTAssertNil(router.handle(type: .keyUp, event: release))
        pumpMainQueue()
        XCTAssertEqual(count, 0)

        router.stop()
    }

    func testRouterPrefersExplicitFunctionKeyBindingOverBareMatch() {
        let router = makeRouter()
        var bareCount = 0
        var explicitCount = 0
        router.addBinding(id: UUID(), key: .keyCode(122), modifiers: []) {
            bareCount += 1
        }
        router.addBinding(id: UUID(), key: .keyCode(122), modifiers: [.maskSecondaryFn]) {
            explicitCount += 1
        }

        let withFn = makeKeyEvent(keyCode: 122, flags: [.maskSecondaryFn])
        XCTAssertNil(router.handle(type: .keyDown, event: withFn))
        pumpMainQueue()
        XCTAssertEqual(bareCount, 0, "explicit fn binding wins; no double fire")
        XCTAssertEqual(explicitCount, 1)

        let withoutFn = makeKeyEvent(keyCode: 122, flags: [])
        XCTAssertNil(router.handle(type: .keyDown, event: withoutFn))
        pumpMainQueue()
        XCTAssertEqual(bareCount, 1)
        XCTAssertEqual(explicitCount, 1)

        router.stop()
    }

    func testRouterSuppressesMediaKeysWhileRecording() throws {
        let router = makeRouter()
        var count = 0
        router.addBinding(id: UUID(), key: .mediaKey(.playPause), modifiers: []) {
            count += 1
        }

        let event = try XCTUnwrap(
            NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (16 << 16) | (0xA << 8),
                data2: 0
            )
        )
        let cgEvent = try XCTUnwrap(event.cgEvent)
        let type = try XCTUnwrap(
            CGEventType(rawValue: HotkeyMonitor.systemDefinedEventRawValue)
        )

        HotkeyTapRouter.isRecording = true
        defer { HotkeyTapRouter.isRecording = false }

        XCTAssertNotNil(router.handle(type: type, event: cgEvent))
        pumpMainQueue()
        XCTAssertEqual(count, 0)

        HotkeyTapRouter.isRecording = false
        XCTAssertNil(router.handle(type: type, event: cgEvent))
        pumpMainQueue()
        XCTAssertEqual(count, 1)

        router.stop()
    }

    func testRouterPassesKeyDownKeyUpAndMediaEventsWhileRecording() throws {
        let router = makeRouter()
        var count = 0
        router.addBinding(id: UUID(), key: .keyCode(40), modifiers: [.maskCommand]) {
            count += 1
        }
        router.addBinding(id: UUID(), key: .mediaKey(.playPause), modifiers: []) {
            count += 1
        }

        let mediaEvent = try XCTUnwrap(
            NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (16 << 16) | (0xA << 8),
                data2: 0
            )?.cgEvent
        )
        let mediaType = try XCTUnwrap(
            CGEventType(rawValue: HotkeyMonitor.systemDefinedEventRawValue)
        )

        HotkeyTapRouter.isRecording = true
        defer { HotkeyTapRouter.isRecording = false }

        // Keep the events alive: `handle` returns an unretained wrapper, and
        // reflecting a dangling Unmanaged in XCTAssertNotNil can crash.
        let down = makeKeyEvent(keyCode: 40, flags: [.maskCommand])
        let up = makeKeyEvent(keyCode: 40, flags: [.maskCommand], keyDown: false)
        XCTAssertTrue(router.handle(type: .keyDown, event: down) != nil)
        XCTAssertTrue(router.handle(type: .keyUp, event: up) != nil)
        XCTAssertTrue(router.handle(type: mediaType, event: mediaEvent) != nil)

        pumpMainQueue()
        XCTAssertEqual(count, 0)
        router.stop()
    }

    func testGlyphStripHotkeyIsSkippedWhenUnboundOrConflicting() {
        let factory = RecordingHotkeyMonitorFactory()
        let handler = HotkeyHandler(
            hotkeyMonitorFactory: factory,
            onToggle: {},
            onTogglePinned: {}
        )

        // Default: strip hotkey unbound, pinned unbound. Only the main
        // hotkey's monitor starts.
        handler.restartHotkeys(config: .default)
        XCTAssertEqual(factory.monitors.count, 1)

        // Same key as the main hotkey: the strip binding is ignored, so a
        // second restart adds one monitor, not two.
        var conflicting = SpacemapConfig.default
        conflicting.glyphStripHotkey = SpacemapConfig.default.hotkey
        handler.restartHotkeys(config: conflicting)
        XCTAssertEqual(factory.monitors.count, 2)
    }

}
