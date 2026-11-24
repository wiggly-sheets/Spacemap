import XCTest
import CoreGraphics
import SwiftUI
@testable import spacemap

final class CellViewIconTests: CellViewGridViewTestCase {
    func testSingleWindowIconGetsEntireCell() throws {
        let layouts = GridLayout.windowIconLayouts(
            windows: [makeWindow(id: 1, app: "Safari", frame: CGRect(x: 500, y: 300, width: 700, height: 500))],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 80, height: 50)
        )

        XCTAssertEqual(layouts.count, 1)
        XCTAssertEqual(layouts[0].frame, CGRect(x: 0, y: 0, width: 80, height: 50))
    }

    func testTwoWindowsOfSameAppGetSeparateHalves() {
        let layouts = GridLayout.windowIconLayouts(
            windows: [
                makeWindow(id: 1, app: "Safari", frame: CGRect(x: 0, y: 0, width: 960, height: 1080)),
                makeWindow(id: 2, app: "Safari", frame: CGRect(x: 960, y: 0, width: 960, height: 1080)),
            ],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 80, height: 50)
        )

        XCTAssertEqual(layouts.map(\.windowID), [1, 2])
        XCTAssertEqual(layouts.map(\.frame), [
            CGRect(x: 0, y: 0, width: 40, height: 50),
            CGRect(x: 40, y: 0, width: 40, height: 50),
        ])
    }

    func testTwoWindowIconsFollowYabaiLeftRightOrder() {
        let layouts = GridLayout.windowIconLayouts(
            windows: [
                makeWindow(id: 2, app: "Notes", frame: CGRect(x: 960, y: 0, width: 960, height: 1080)),
                makeWindow(id: 1, app: "Safari", frame: CGRect(x: 0, y: 0, width: 960, height: 1080)),
            ],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 80, height: 50)
        )

        XCTAssertEqual(layouts.map(\.app), ["Safari", "Notes"])
        XCTAssertEqual(layouts[0].frame.minX, 0)
        XCTAssertEqual(layouts[1].frame.minX, 40)
    }

    func testThreeWindowIconsUseYabaiGeometry() {
        let layouts = GridLayout.windowIconLayouts(
            windows: [
                makeWindow(id: 1, app: "Safari", frame: CGRect(x: 0, y: 0, width: 960, height: 1080)),
                makeWindow(id: 2, app: "Notes", frame: CGRect(x: 960, y: 0, width: 960, height: 540)),
                makeWindow(id: 3, app: "Mail", frame: CGRect(x: 960, y: 540, width: 960, height: 540)),
            ],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 80, height: 50)
        )

        XCTAssertEqual(layouts.map(\.frame), [
            CGRect(x: 0, y: 0, width: 40, height: 50),
            CGRect(x: 40, y: 0, width: 40, height: 25),
            CGRect(x: 40, y: 25, width: 40, height: 25),
        ])
    }


    func testUniqueIconWindowsDeduplicatesByApp() {
        let windows = [
            makeWindow(id: 1, app: "Firefox"),
            makeWindow(id: 2, app: "Firefox"),
            makeWindow(id: 3, app: "Safari"),
        ]
        let result = CellView.uniqueIconWindows(windows)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.app)), Set(["Firefox", "Safari"]))
    }

    func testUniqueIconWindowsPreservesFirstOccurrence() {
        let windows = [
            makeWindow(id: 1, app: "Firefox"),
            makeWindow(id: 2, app: "Safari"),
            makeWindow(id: 3, app: "Firefox"),
        ]
        let result = CellView.uniqueIconWindows(windows)
        XCTAssertEqual(result.first?.id, 1)
        XCTAssertEqual(result.last?.id, 2)
    }

    func testUniqueIconWindowsEmpty() {
        XCTAssertTrue(CellView.uniqueIconWindows([]).isEmpty)
    }

    func testUniqueIconWindowsAllSameApp() {
        let windows = [
            makeWindow(id: 1, app: "Firefox"),
            makeWindow(id: 2, app: "Firefox"),
            makeWindow(id: 3, app: "Firefox"),
        ]
        let result = CellView.uniqueIconWindows(windows)
        XCTAssertEqual(result.count, 1)
    }

    func testUniqueIconWindowsDoesNotRefilterDisplayedFloatingWindows() {
        var floating = makeWindow(id: 2, app: "System Settings", isStandard: false)
        floating.isFloating = true
        let allWindows = [
            makeWindow(id: 1, app: "Firefox"),
            floating,
        ]

        let displayed = allWindows.filter { $0.shouldDisplay(showExtraWindows: true) }
        XCTAssertEqual(displayed.map(\.id), [1, 2])

        let result = CellView.uniqueIconWindows(displayed)

        XCTAssertEqual(result.map(\.id), [1, 2])
        XCTAssertEqual(
            allWindows.filter { $0.shouldDisplay(showExtraWindows: false) }.map(\.id),
            [1]
        )
    }

    func testIconStripWindowsPreservesOneIconPerWindowSetting() {
        let displayedWindows = [
            makeWindow(id: 1, app: "Firefox"),
            makeWindow(id: 2, app: "Firefox"),
            makeWindow(id: 3, app: "Safari"),
        ]

        XCTAssertEqual(
            CellView.iconStripWindows(displayedWindows, showMultiAppIcons: true).map(\.id),
            [1, 2, 3]
        )
        XCTAssertEqual(
            CellView.iconStripWindows(displayedWindows, showMultiAppIcons: false).map(\.id),
            [1, 3]
        )
    }


}
