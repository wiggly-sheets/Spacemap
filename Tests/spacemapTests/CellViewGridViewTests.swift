import XCTest
import CoreGraphics
@testable import spacemap

final class CellViewGridViewTests: XCTestCase {

    // MARK: - CellView label positioning

    func testSpaceNumberPositionScalesWithHUD() {
        XCTAssertEqual(CellView.spaceNumberPosition(for: 0.5), CGPoint(x: 4, y: 5))
        XCTAssertEqual(CellView.spaceNumberPosition(for: 1), CGPoint(x: 8, y: 10))
        XCTAssertEqual(CellView.spaceNumberPosition(for: 4), CGPoint(x: 32, y: 40))
    }

    func testSpaceNamePositionStaysCenteredAcrossCellSizes() {
        XCTAssertEqual(
            CellView.spaceNamePosition(in: CGSize(width: 40, height: 25)),
            CGPoint(x: 20, y: 12.5)
        )
        XCTAssertEqual(
            CellView.spaceNamePosition(in: CGSize(width: 320, height: 200)),
            CGPoint(x: 160, y: 100)
        )
    }

    func testScaledWindowFramePreservesRectangleGeometry() throws {
        let frame = try XCTUnwrap(CellView.scaledWindowFrame(
            windowFrame: CGRect(x: 960, y: 0, width: 960, height: 540),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 80, height: 50)
        ))

        XCTAssertEqual(frame, CGRect(x: 40, y: 0, width: 40, height: 25))
    }

    func testHybridIconSizeKeepsSameProportionAcrossUIScales() {
        let baseSize = CellView.hybridIconSize(
            uiScale: 1,
            windowFrame: CGRect(x: 0, y: 0, width: 80, height: 50)
        )
        let largeSize = CellView.hybridIconSize(
            uiScale: 4,
            windowFrame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )

        XCTAssertEqual(baseSize, 26.25, accuracy: 0.001)
        XCTAssertEqual(largeSize, 105, accuracy: 0.001)
        XCTAssertEqual(largeSize / baseSize, 4, accuracy: 0.001)
    }

    func testHybridIconSizeCapsProportionallyInsideSmallRectangles() {
        let baseSize = CellView.hybridIconSize(
            uiScale: 1,
            windowFrame: CGRect(x: 0, y: 0, width: 8, height: 6)
        )
        let largeSize = CellView.hybridIconSize(
            uiScale: 3,
            windowFrame: CGRect(x: 0, y: 0, width: 24, height: 18)
        )

        XCTAssertEqual(baseSize, 4.5, accuracy: 0.001)
        XCTAssertEqual(largeSize, 13.5, accuracy: 0.001)
        XCTAssertEqual(largeSize / baseSize, 3, accuracy: 0.001)
    }

    func testSingleWindowIconGetsEntireCell() throws {
        let layouts = CellView.windowIconLayouts(
            windows: [makeWindow(id: 1, app: "Safari", frame: CGRect(x: 500, y: 300, width: 700, height: 500))],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 80, height: 50)
        )

        XCTAssertEqual(layouts.count, 1)
        XCTAssertEqual(layouts[0].frame, CGRect(x: 0, y: 0, width: 80, height: 50))
    }

    func testTwoWindowsOfSameAppGetSeparateHalves() {
        let layouts = CellView.windowIconLayouts(
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
        let layouts = CellView.windowIconLayouts(
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
        let layouts = CellView.windowIconLayouts(
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

    // MARK: - CellView.uniqueIconWindows

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

    func testUniqueIconWindowsFiltersBackgroundApps() {
        let windows = [
            makeWindow(id: 1, app: "Firefox"),
            makeWindow(id: 2, app: "Hammerspoon", subLayer: "normal"),
            makeWindow(id: 3, app: "Wallpaper Selector", subLayer: "normal"),
        ]
        let result = CellView.uniqueIconWindows(windows)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.app, "Firefox")
    }

    // MARK: - CellView.appColor

    func testAppColorFewWindowsReturnsBaseRectColor() {
        let theme = AppTheme(background: 0, focused: 0, text: 0, dropTarget: 0, cellBg: 0, cellBgFocused: 0,
                             rect1: 0xff0000, rect2: 0x00ff00, rect3: 0x0000ff)
        // With windowCount <= 3, appColor returns Color(hex: base)
        // The exact base depends on name.hashValue % 3, but we can verify it's deterministic
        let c1 = CellView.appColor("Firefox", theme: theme, windowCount: 2)
        let c2 = CellView.appColor("Firefox", theme: theme, windowCount: 2)
        XCTAssertEqual(String(describing: c1), String(describing: c2))
    }

    func testAppColorManyWindowsHSLVariation() {
        let theme = AppTheme(background: 0, focused: 0, text: 0, dropTarget: 0, cellBg: 0, cellBgFocused: 0,
                             rect1: 0xff0000, rect2: 0x00ff00, rect3: 0x0000ff)
        // With windowCount > 3, HSL variation kicks in
        let c1 = CellView.appColor("Firefox", theme: theme, windowCount: 5)
        let c2 = CellView.appColor("Firefox", theme: theme, windowCount: 5)
        XCTAssertEqual(String(describing: c1), String(describing: c2))
    }

    func testAppColorReturnsValidThemeColor() {
        let theme = AppTheme(background: 0, focused: 0, text: 0, dropTarget: 0, cellBg: 0, cellBgFocused: 0,
                             rect1: 0xff0000, rect2: 0x00ff00, rect3: 0x0000ff)
        // For windowCount <= 3, appColor must return one of the three theme rect colors
        let names = ["Firefox", "Safari", "Terminal", "VSCode", "Slack", "Notes"]
        let validColors: Set<String> = ["#FF0000FF", "#00FF00FF", "#0000FFFF"]
        for name in names {
            let c = CellView.appColor(name, theme: theme, windowCount: 2)
            XCTAssertTrue(validColors.contains(String(describing: c)),
                          "\(name) returned unexpected color \(c)")
        }
    }

    // MARK: - GridView.computeVisibleSpaceIndices

    func testVisibleIndicesShowAll() {
        let indices = GridView.computeVisibleSpaceIndices(
            maxSpaces: 8, showMode: .all, activeIndices: Set([1, 3])
        )
        XCTAssertEqual(indices, [1, 2, 3, 4, 5, 6, 7, 8])
    }

    func testVisibleIndicesShowActiveOnly() {
        let indices = GridView.computeVisibleSpaceIndices(
            maxSpaces: 8, showMode: .active, activeIndices: Set([1, 3, 5])
        )
        XCTAssertEqual(indices, [1, 3, 5])
    }

    func testVisibleIndicesMaxSpacesLimitsOutput() {
        let indices = GridView.computeVisibleSpaceIndices(
            maxSpaces: 4, showMode: .all, activeIndices: Set([1, 2, 3, 4, 5, 6])
        )
        XCTAssertEqual(indices, [1, 2, 3, 4])
    }

    func testVisibleIndicesMaxSpacesClampedTo16() {
        let indices = GridView.computeVisibleSpaceIndices(
            maxSpaces: 20, showMode: .all, activeIndices: Set()
        )
        XCTAssertEqual(indices.count, 16)
    }

    func testVisibleIndicesActiveNoOverlap() {
        let indices = GridView.computeVisibleSpaceIndices(
            maxSpaces: 4, showMode: .active, activeIndices: Set([5, 6])
        )
        XCTAssertTrue(indices.isEmpty)
    }

    // MARK: - GridView.computeIdealSize

    func testIdealSizeSingleCell() {
        let size = GridView.computeIdealSize(
            cellCount: 1, cols: 8,
            cellWidth: 800, cellHeight: 500,
            gap: 60, padding: 120
        )
        // 1 col, 1 row
        // w = 1 * (800 + 60) - 60 + 120*2 = 860 - 60 + 240 = 1040
        // h = 1 * (500 + 60) - 60 + 120*2 = 560 - 60 + 240 = 740
        XCTAssertEqual(size.width, 1040, accuracy: 0.1)
        XCTAssertEqual(size.height, 740, accuracy: 0.1)
    }

    func testIdealSizeMultipleRows() {
        let size = GridView.computeIdealSize(
            cellCount: 16, cols: 8,
            cellWidth: 800, cellHeight: 500,
            gap: 60, padding: 120
        )
        // 8 cols, 2 rows
        // w = 8 * 860 - 60 + 240 = 6880 - 60 + 240 = 7060
        // h = 2 * 560 - 60 + 240 = 1120 - 60 + 240 = 1300
        XCTAssertEqual(size.width, 7060, accuracy: 0.1)
        XCTAssertEqual(size.height, 1300, accuracy: 0.1)
    }

    func testIdealSizeZeroCells() {
        let size = GridView.computeIdealSize(
            cellCount: 0, cols: 8,
            cellWidth: 800, cellHeight: 500,
            gap: 60, padding: 120
        )
        // 0 cols, 0 rows
        // w = 0 * 860 - 60 + 240 = 180
        // h = 0 * 560 - 60 + 240 = 180
        XCTAssertEqual(size.width, 180, accuracy: 0.1)
        XCTAssertEqual(size.height, 180, accuracy: 0.1)
    }

    func testIdealSizePartialRow() {
        let size = GridView.computeIdealSize(
            cellCount: 3, cols: 8,
            cellWidth: 800, cellHeight: 500,
            gap: 60, padding: 120
        )
        // 3 cols, 1 row (partial)
        // w = 3 * 860 - 60 + 240 = 2580 - 60 + 240 = 2760
        // h = 1 * 560 - 60 + 240 = 740
        XCTAssertEqual(size.width, 2760, accuracy: 0.1)
        XCTAssertEqual(size.height, 740, accuracy: 0.1)
    }

    // MARK: - Row chunking

    func testRowChunking() {
        let cells = [1, 2, 3, 4, 5, 6, 7, 8]
        let cols = 3
        let rows = stride(from: 0, to: cells.count, by: cols).map {
            Array(cells[$0..<min($0 + cols, cells.count)])
        }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], [1, 2, 3])
        XCTAssertEqual(rows[1], [4, 5, 6])
        XCTAssertEqual(rows[2], [7, 8])
    }

    func testRowChunkingExactMultiple() {
        let cells = [1, 2, 3, 4, 5, 6]
        let cols = 3
        let rows = stride(from: 0, to: cells.count, by: cols).map {
            Array(cells[$0..<min($0 + cols, cells.count)])
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], [1, 2, 3])
        XCTAssertEqual(rows[1], [4, 5, 6])
    }

    func testRowChunkingSingleRow() {
        let cells = [1, 2, 3]
        let cols = 8
        let rows = stride(from: 0, to: cells.count, by: cols).map {
            Array(cells[$0..<min($0 + cols, cells.count)])
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], [1, 2, 3])
    }

    func testRowChunkingEmpty() {
        let cells: [Int] = []
        let cols = 3
        let rows = stride(from: 0, to: cells.count, by: cols).map {
            Array(cells[$0..<min($0 + cols, cells.count)])
        }
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Helpers

    private func makeWindow(
        id: Int,
        app: String,
        space: Int = 1,
        subLayer: String = "below",
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> YabaiWindow {
        YabaiWindow(id: id, app: app, space: space,
                    frame: .init(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
                    isHidden: false, isMinimized: false, subLayer: subLayer)
    }

    // MARK: - Scale mapping

    func testEffectiveScaleMinimum() {
        let s = GridView.effectiveScale(for: 0.0)
        XCTAssertEqual(s, 0.5, accuracy: 0.001)
    }

    func testEffectiveScaleMidpoint() {
        let s = GridView.effectiveScale(for: 0.5)
        XCTAssertEqual(s, 2.25, accuracy: 0.001)
    }

    func testEffectiveScaleMaximum() {
        let s = GridView.effectiveScale(for: 1.0)
        XCTAssertEqual(s, 4.0, accuracy: 0.001)
    }

    func testEffectiveScaleMonotonic() {
        var prev = GridView.effectiveScale(for: 0.0)
        for i in stride(from: 0.1, through: 1.0, by: 0.1) {
            let cur = GridView.effectiveScale(for: i)
            XCTAssertGreaterThan(cur, prev, "scale must increase at \(i)")
            prev = cur
        }
    }

    func testEffectiveIconScaleMinimum() {
        let s = GridView.effectiveIconScale(for: 0.0)
        XCTAssertEqual(s, 0.2, accuracy: 0.001)
    }

    func testEffectiveIconScaleMaximum() {
        let s = GridView.effectiveIconScale(for: 1.0)
        XCTAssertEqual(s, 1.0, accuracy: 0.001)
    }

    func testEffectiveIconScaleMonotonic() {
        var prev = GridView.effectiveIconScale(for: 0.0)
        for i in stride(from: 0.1, through: 1.0, by: 0.1) {
            let cur = GridView.effectiveIconScale(for: i)
            XCTAssertGreaterThan(cur, prev, "icon scale must increase at \(i)")
            prev = cur
        }
    }

    func testCellWidthRange() {
        let base: CGFloat = 80
        let minW = base * GridView.effectiveScale(for: 0.0)
        let maxW = base * GridView.effectiveScale(for: 1.0)
        XCTAssertEqual(minW, 40, accuracy: 0.001)
        XCTAssertEqual(maxW, 320, accuracy: 0.001)
    }
}
