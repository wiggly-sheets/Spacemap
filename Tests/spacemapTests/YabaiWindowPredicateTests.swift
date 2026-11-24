import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class YabaiWindowPredicateTests: XCTestCase {

    private func window(
        id: Int = 1,
        app: String = "Safari",
        space: Int = 1,
        x: CGFloat = 0,
        y: CGFloat = 0,
        opacity: Double? = 1,
        isSticky: Bool? = false
    ) -> YabaiWindow {
        var window = YabaiWindow(
            id: id,
            app: app,
            space: space,
            frame: .init(x: x, y: y, w: 800, h: 600),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        window.role = "AXWindow"
        window.subrole = "AXStandardWindow"
        window.isRootWindow = true
        window.opacity = opacity
        window.isSticky = isSticky
        return window
    }

    func testStickyWindowIsExcluded() {
        XCTAssertFalse(window(id: 1, isSticky: true).shouldDisplay(showExtraWindows: false))
    }

    func testFullyTransparentWindowIsExcluded() {
        XCTAssertFalse(window(id: 1, opacity: 0).shouldDisplay(showExtraWindows: false))
    }

    func testPartiallyDimmedWindowIsKept() {
        XCTAssertTrue(window(id: 1, opacity: 0.8).shouldDisplay(showExtraWindows: false))
    }

    func testReadingOrderSortsByXThenYThenID() {
        let windows = [
            window(id: 1, x: 100, y: 0),
            window(id: 2, x: 0, y: 50),
            window(id: 3, x: 0, y: 0),
            window(id: 4, x: 0, y: 0)
        ]

        XCTAssertEqual(YabaiWindow.inReadingOrder(windows).map(\.id), [3, 4, 2, 1])
    }
}
