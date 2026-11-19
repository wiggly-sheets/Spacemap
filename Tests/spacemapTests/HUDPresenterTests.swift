import AppKit
import CoreGraphics
import XCTest
@testable import spacemap

final class HUDPresenterTests: XCTestCase {
    private struct Rig {
        let presenter: HUDPresenter
        let display: HUDDisplay
        let input: HUDInput
        let yabai: MockYabaiService
    }

    private func makeRig() -> Rig {
        let yabai = MockYabaiService()
        let display = HUDDisplay(yabaiService: yabai, themeStore: makeTemporaryThemeStore())
        display.screenFramesOverride = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let input = HUDInput(panel: nil)
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabai)
        let presenter = HUDPresenter(
            display: display,
            input: input,
            coordinator: coordinator,
            yabaiService: yabai
        )
        return Rig(presenter: presenter, display: display, input: input, yabai: yabai)
    }

    func testShowRendersAndHideClearsThePresentation() {
        let rig = makeRig()

        rig.presenter.show(config: .default)

        XCTAssertTrue(rig.presenter.isVisible)
        waitUntil("first render") {
            rig.display.renderedState != nil && rig.presenter.state != nil
        }

        rig.presenter.hide()

        XCTAssertFalse(rig.presenter.isVisible)
        XCTAssertNil(rig.presenter.state)
        XCTAssertNil(rig.display.renderedState, "hide must drop the rendered state")
    }

    func testCommandResultLandsOnlyOnThePresentationThatStartedIt() {
        let rig = makeRig()
        rig.presenter.show(config: .default)
        waitUntil("first render") { rig.presenter.state != nil }
        let stale = rig.presenter.currentPresentation()

        rig.presenter.hide()
        let buildsAfterHide = rig.yabai.buildGridStateCallCount

        rig.presenter.complete(stale, notice: "Space 4 Created")

        XCTAssertEqual(rig.yabai.buildGridStateCallCount, buildsAfterHide,
            "a result from a closed presentation must be dropped")

        rig.presenter.show(config: .default)
        waitUntil("second render") { rig.presenter.state != nil }
        let current = rig.presenter.currentPresentation()
        let buildsBeforeComplete = rig.yabai.buildGridStateCallCount

        rig.presenter.complete(current)

        waitUntil("current result refreshes") {
            rig.yabai.buildGridStateCallCount > buildsBeforeComplete
        }
    }

    func testAutoHideSuppressionAndPinKeepTheTimerDisarmed() {
        let rig = makeRig()
        rig.presenter.show(config: .default)
        rig.presenter.autoHideTimeout = 30
        rig.presenter.resetAutoHideTimer()
        XCTAssertTrue(rig.presenter.isAutoHideScheduled)

        rig.presenter.setAutoHideSuppressed(true)
        XCTAssertFalse(rig.presenter.isAutoHideScheduled,
            "a window drag must invalidate the pending auto-hide")

        rig.presenter.setAutoHideSuppressed(false)
        XCTAssertTrue(rig.presenter.isAutoHideScheduled)

        rig.presenter.isPinned = true
        rig.presenter.resetAutoHideTimer()
        XCTAssertFalse(rig.presenter.isAutoHideScheduled, "a pinned HUD never arms auto-hide")

        rig.presenter.isPinned = false
        rig.presenter.hide()
        XCTAssertFalse(rig.presenter.isAutoHideScheduled)
    }

    func testPanelDragDisarmsAndRearmsAutoHide() {
        let rig = makeRig()
        rig.presenter.show(config: .default)
        rig.presenter.autoHideTimeout = 30
        rig.presenter.resetAutoHideTimer()
        XCTAssertTrue(rig.presenter.isAutoHideScheduled)

        rig.input.beginPanelDrag(start: .zero, panelOrigin: .zero)
        XCTAssertTrue(rig.input.panelDragActive)
        XCTAssertFalse(rig.presenter.isAutoHideScheduled,
            "an armed auto-hide timer must be invalidated on mouse down")

        XCTAssertFalse(rig.input.endPanelDrag())
        XCTAssertFalse(rig.input.panelDragActive)
        XCTAssertTrue(rig.presenter.isAutoHideScheduled,
            "auto-hide re-arms once the panel drag ends")
        rig.presenter.hide()
    }

    func testHideResetsSuppressionSoTheNextShowArmsAutoHide() {
        let rig = makeRig()
        rig.presenter.show(config: .default)
        rig.presenter.setAutoHideSuppressed(true)
        XCTAssertFalse(rig.presenter.isAutoHideScheduled)

        rig.presenter.hide()
        rig.presenter.show(config: .default)

        XCTAssertTrue(rig.presenter.isAutoHideScheduled,
            "a hide must clear suppression so the next presentation arms auto-hide")
        rig.presenter.hide()
    }

    func testAutoHideTimerHidesTheHUD() {
        let rig = makeRig()
        rig.presenter.show(config: .default)
        rig.presenter.autoHideTimeout = 0.05

        rig.presenter.resetAutoHideTimer()

        waitUntil("auto-hide fires") { !rig.presenter.isVisible }
    }

    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(message)", file: file, line: line)
    }
}
