import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class PanelPresenterTests: XCTestCase {

    private func stripSurface() -> PanelPresenter.Surface {
        PanelPresenter.Surface(
            level: .statusBar,
            hasShadow: true,
            collectionBehavior: [.canJoinAllSpaces, .stationary],
            hidesOnDeactivate: false
        )
    }

    func testMakePanelAppliesSurfaceAndLeavesUnsetDeactivationToAppKit() {
        var requestedMask: NSWindow.StyleMask?
        let presenter = PanelPresenter(factory: { mask in
            requestedMask = mask
            return NSPanel(contentRect: .zero, styleMask: mask, backing: .buffered, defer: false)
        })

        let strip = presenter.makePanel(stripSurface())
        XCTAssertEqual(requestedMask, [.borderless, .nonactivatingPanel])
        XCTAssertEqual(strip.level, .statusBar)
        XCTAssertTrue(strip.hasShadow)
        XCTAssertEqual(strip.collectionBehavior, [.canJoinAllSpaces, .stationary])
        XCTAssertFalse(strip.isOpaque)
        XCTAssertEqual(strip.backgroundColor, .clear)
        XCTAssertFalse(strip.hidesOnDeactivate)

        let hud = presenter.makePanel(PanelPresenter.Surface(
            level: .floating,
            hasShadow: false,
            collectionBehavior: []
        ))
        XCTAssertEqual(hud.level, .floating)
        XCTAssertFalse(hud.hasShadow)
        XCTAssertEqual(
            hud.hidesOnDeactivate,
            PanelPresenter.defaultPanelFactory([.borderless, .nonactivatingPanel]).hidesOnDeactivate,
            "an unset surface keeps AppKit's default"
        )
    }

    func testPresentAndHideOrderThePanelWhenNotAnimating() {
        _ = NSApplication.shared
        let presenter = PanelPresenter()
        let panel = presenter.makePanel(stripSurface())
        panel.alphaValue = 0

        presenter.present(panel, duration: 0.2, animated: false)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1)

        presenter.hide(panel, duration: 0.2, animated: false)
        XCTAssertFalse(panel.isVisible)
    }

    func testHideCompletionFinishesOnlyWhenTheFadeReachedZero() {
        XCTAssertTrue(PanelPresenter.shouldCompleteHide(currentAlpha: 0))
        XCTAssertTrue(PanelPresenter.shouldCompleteHide(currentAlpha: 0.004))
        XCTAssertFalse(
            PanelPresenter.shouldCompleteHide(currentAlpha: 1),
            "a present raised alpha again: the panel must stay visible"
        )
    }

    func testDragFrameFollowsPointerTravelInScreenCoordinates() {
        let start = CGRect(x: 100, y: 200, width: 300, height: 40)
        let delta = PanelPresenter.dragDelta(
            from: CGPoint(x: 50, y: 50),
            to: CGPoint(x: 80, y: 20)
        )

        XCTAssertEqual(delta, CGVector(dx: 30, dy: -30))
        XCTAssertEqual(
            PanelPresenter.draggedFrame(from: start, by: delta),
            CGRect(x: 130, y: 170, width: 300, height: 40)
        )
    }
}
