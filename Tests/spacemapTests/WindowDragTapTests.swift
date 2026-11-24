import XCTest
import CoreGraphics
@testable import spacemap

final class WindowDragTapTests: WindowDragHandlerTestCase {
    func testDisabledEventTapTypesRequireRecovery() {
        XCTAssertTrue(WindowDragHandler.shouldRecoverEventTap(for: .tapDisabledByTimeout))
        XCTAssertTrue(WindowDragHandler.shouldRecoverEventTap(for: .tapDisabledByUserInput))
        XCTAssertFalse(WindowDragHandler.shouldRecoverEventTap(for: .leftMouseDragged))
    }

    func testStoppedHandlerIgnoresQueuedEventTapRecovery() {
        handler.stop()

        handler.recoverEventTap()

        XCTAssertFalse(handler.isEventTapRequested)
    }

    func testEventTapCreationFailureRetries() {
        var attempts = 0
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { true },
            eventTapFactory: { _, _, _, _, _, _ in
                attempts += 1
                return nil
            }
        )

        handler.start()
        XCTAssertEqual(handler.tapCreationAttempts, 1)
        XCTAssertEqual(handler.tapCreationFailureCount, 1)
        XCTAssertFalse(handler.hasTapContext, "failed install must release its tap context")

        handler.reconcileEventTap()
        XCTAssertEqual(handler.tapCreationAttempts, 2)
        XCTAssertEqual(handler.tapCreationFailureCount, 2)
    }

    func testDragTapWaitsForInputMonitoringPermission() {
        var permitted = false
        var attempts = 0
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { permitted },
            permissionCacheInterval: 0,
            eventTapFactory: { _, _, _, _, _, _ in
                attempts += 1
                return nil
            }
        )

        handler.start()
        XCTAssertEqual(attempts, 0)

        permitted = true
        handler.reconcileEventTap()
        XCTAssertEqual(attempts, 1)
    }

    func testStaleRecoveryGenerationIsIgnored() {
        var attempts = 0
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { true },
            eventTapFactory: { _, _, _, _, _, _ in
                attempts += 1
                return nil
            }
        )

        handler.start()
        let generation = handler.eventTapGeneration
        XCTAssertTrue(handler.recoverEventTap(expectedGeneration: generation))
        XCTAssertEqual(attempts, 2)

        XCTAssertFalse(handler.recoverEventTap(expectedGeneration: generation - 1))
        XCTAssertEqual(attempts, 2, "a stale recovery must not tear down a newer tap")
    }

    func testUnpermittedReconcileClearsHoverAndDragState() {
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { false },
            permissionCacheInterval: 0,
            eventTapFactory: { _, _, _, _, _, _ in nil },
            cgWindowListProvider: { [] }
        )
        var didClear = false
        handler.onHoverCell = { cell in
            if cell == nil { didClear = true }
        }

        handler.start()
        handler.isDragging = true
        handler.lastHoveredCell = 1
        handler.dragStartPoint = CGPoint(x: 10, y: 10)
        handler.reconcileEventTap()

        XCTAssertTrue(didClear)
        XCTAssertFalse(handler.isDragging)
        XCTAssertNil(handler.dragStartPoint)
        XCTAssertNil(handler.lastHoveredCell)
    }

    func testStoppedDragHandlerDeallocates() {
        var local: WindowDragHandler? = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { true },
            eventTapFactory: { _, _, _, _, _, _ in nil }
        )
        weak var weakHandler = local

        local?.start()
        XCTAssertFalse(local?.hasTapContext ?? true)
        local?.stop()
        local = nil

        XCTAssertNil(weakHandler)
    }

}
