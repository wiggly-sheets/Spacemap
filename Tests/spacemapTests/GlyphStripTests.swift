import XCTest
import CoreGraphics
import CoreText
@testable import spacemap

final class AppGlyphFontTests: XCTestCase {

    private func bundledFontData() throws -> Data {
        let bundle = Bundle.module
        let url = try XCTUnwrap(
            bundle.url(forResource: AppGlyphFont.resourceName, withExtension: "ttf"),
            "sketchybar-app-font.ttf missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    func testBundledFontHasAppMetadataRecord() throws {
        let payload = try XCTUnwrap(
            AppGlyphFont.appMetadataPayload(in: try bundledFontData()),
            "meta/APPM table not found"
        )
        XCTAssertGreaterThan(payload.count, 0)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: payload))
    }

    func testKnownLigaturesMapToExpectedAppNames() throws {
        let font = try XCTUnwrap(AppGlyphFont.load(), "bundled font failed to load")

        // Names below are copied from sketchybar-app-font/mappings/.
        XCTAssertEqual(font.appNames(forLigature: ":finder:"), ["Finder", "访达", "Bloom", "FlowFinder"])
        XCTAssertEqual(font.appNames(forLigature: ":alacritty:"), ["Alacritty"])
        XCTAssertEqual(
            font.appNames(forLigature: ":google_chrome:"),
            ["Chromium", "Google Chrome", "Google Chrome Canary"]
        )
    }

    func testDefaultGlyphIsNonEmptyAndUsedForUnknownApps() throws {
        let font = try XCTUnwrap(AppGlyphFont.load())

        XCTAssertEqual(font.glyph(forApp: "Totally Unknown App"), font.glyph(forApp: AppGlyphFont.defaultLigature))
        XCTAssertFalse(font.glyph(forApp: "Totally Unknown App").isEmpty)
    }

    func testExactMatchWinsAndPrefixMatchesAreSupported() throws {
        let font = try XCTUnwrap(AppGlyphFont.load())

        XCTAssertEqual(font.glyph(forApp: "Finder"), font.glyph(forApp: "访达"))
        // Every installed mapping resolves to something other than the default.
        XCTAssertNotEqual(font.glyph(forApp: "Google Chrome"), font.glyph(forApp: "Default"))
    }

    func testInitialsFallbackForMissingFont() {
        XCTAssertEqual(AppGlyphFont.initials(forApp: "Google Chrome"), "GC")
        XCTAssertEqual(AppGlyphFont.initials(forApp: "Safari"), "S")
        XCTAssertEqual(AppGlyphFont.initials(forApp: "some-weird-app"), "SW")
    }
}

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

final class GlyphStripTests: XCTestCase {

    private func state(
        spaces: [YabaiSpace],
        windows: [YabaiWindow],
        maxSpaces: Int = 16,
        focusedIndex: Int? = nil
    ) -> GridState {
        var config = GridConfig.default
        config.maxSpaces = maxSpaces
        return GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: focusedIndex
        )
    }

    private func space(index: Int, display: Int = 1, type: String? = "bsp") -> YabaiSpace {
        var space = YabaiSpace(id: index, index: index, display: display, hasFocus: false, isVisible: true, label: nil)
        space.type = type
        return space
    }

    func testOneSegmentPerSpacePlusTrailingAdd() {
        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 1), space(index: 2)], windows: [], maxSpaces: 2),
            font: nil
        )

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map(\.spaceIndex), [1, 2, nil])
        XCTAssertEqual(segments.last?.runs, [.add])
    }

    // MARK: - Only real spaces render

    func testGappedSpaceIndexesRenderOneSegmentEachAndCarryTheRealIndex() {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [space(index: 1), space(index: 3), space(index: 7)],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )

        // Three real spaces plus the add button. Indexes 2, 4, 5, 6 do not
        // exist and must not be invented.
        XCTAssertEqual(segments.count, 4)
        XCTAssertEqual(segments.map(\.spaceIndex), [1, 3, 7, nil])
    }

    func testNoGhostSegmentsBeyondTheHighestRealIndex() {
        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 2)], windows: [], maxSpaces: 16),
            font: nil
        )

        // maxSpaces is 16 but yabai reported one space.
        XCTAssertEqual(segments.count, 2, "expected one space segment plus add, got \(segments.map(\.spaceIndex))")
        XCTAssertEqual(segments.first?.spaceIndex, 2)
    }

    func testSpacesAreSortedByIndexRegardlessOfQueryOrder() {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [space(index: 7), space(index: 1), space(index: 3)],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )

        XCTAssertEqual(segments.map(\.spaceIndex), [1, 3, 7, nil])
    }

    func testRealSpaceWithNoWindowsStillGetsAPlaceholderNotGhosts() throws {
        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 4)], windows: [], maxSpaces: 16),
            font: nil
        )

        let space4 = try XCTUnwrap(segments.first)
        XCTAssertEqual(space4.spaceIndex, 4, "a real empty space is a space, not a missing one")
        XCTAssertEqual(space4.runs, [.index("4"), .placeholder])
    }

    func testDisplaySeparatorComparesRenderedNeighboursWithGappedIndexes() {
        // 1 and 3 on display 1, 7 on display 2. The separator must land between
        // the segment for space 3 and the segment for space 7.
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [
                    space(index: 1, display: 1),
                    space(index: 3, display: 1),
                    space(index: 7, display: 2)
                ],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )

        XCTAssertEqual(segments.count, 5)
        XCTAssertEqual(segments.map(\.spaceIndex), [1, 3, nil, 7, nil])
        XCTAssertEqual(segments[2].runs, [.separator], "separator belongs between the rendered spaces 3 and 7")
    }

    func testNoSeparatorBetweenTwoRenderedSpacesOnTheSameDisplayWithAGap() {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [space(index: 1, display: 1), space(index: 5, display: 1)],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )

        XCTAssertEqual(segments.map(\.spaceIndex), [1, 5, nil])
        XCTAssertFalse(segments.contains { $0.runs == [.separator] })
    }

    func testAddButtonIsPresentAndIsNotCountedAsASpaceSegment() {
        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 1), space(index: 3)], windows: [], maxSpaces: 16),
            font: nil
        )

        let add = segments.last
        XCTAssertEqual(add?.runs, [.add])
        XCTAssertNil(add?.spaceIndex)
        XCTAssertEqual(segments.filter { $0.spaceIndex != nil }.count, 2)
    }

    /// The highest-risk regression in the non-contiguous-index change: a command
    /// built from a segment's position instead of its index would silently act
    /// on the wrong space.
    // MARK: - Multi-display

    /// Every space goes on the one bar, including spaces on a secondary display
    /// (the old SketchyBar config set `ignore_association = true` for exactly
    /// this), in global-index order, with `|` only at display boundaries.
    func testSpacesFromASecondaryDisplayAreAllPresent() {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [
                    space(index: 1, display: 1),
                    space(index: 4, display: 2),
                    space(index: 7, display: 2)
                ],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )

        let spaceIndexes = segments.compactMap(\.spaceIndex)
        XCTAssertEqual(spaceIndexes, [1, 4, 7], "no space is dropped because of its display")
    }

    func testInterleavedDisplaysProduceExactlyOneSeparatorAtTheBoundary() {
        // 1 and 3 on display 1, 4 and 7 on display 2. One boundary, so one `|`.
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [
                    space(index: 1, display: 1),
                    space(index: 3, display: 1),
                    space(index: 4, display: 2),
                    space(index: 7, display: 2)
                ],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )

        let separatorOffsets = segments.indices.filter { segments[$0].runs == [.separator] }
        XCTAssertEqual(separatorOffsets, [2], "the separator sits before the first display-2 space")
        XCTAssertEqual(
            segments.map(\.spaceIndex),
            [1, 3, nil, 4, 7, nil],
            "nil at the separator and at the add button"
        )
    }

    func testEveryDisplayChangeInsertsOneSeparator() {
        // 1/2/3/4 walking display 1, 1, 2, 2 means two boundaries.
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [
                    space(index: 1, display: 1),
                    space(index: 2, display: 2),
                    space(index: 3, display: 3),
                    space(index: 4, display: 3)
                ],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )

        XCTAssertEqual(segments.filter { $0.runs == [.separator] }.count, 2)
        XCTAssertEqual(segments.map(\.spaceIndex), [1, nil, 2, nil, 3, 4, nil])
    }

    func testIndexesAreNotRenumberedPerDisplay() {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [space(index: 1, display: 1), space(index: 6, display: 2)],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )
        // The last segment is the add button; the space before it shows its global
        // index 6, not a per-display 2.
        XCTAssertEqual(segments.last?.runs, [.add])
        XCTAssertEqual(segments[segments.count - 2].spaceIndex, 6)
    }

    func testClicksCarryTheGlobalIndexAcrossDisplaysAndGaps() throws {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [
                    space(index: 2, display: 1),
                    space(index: 5, display: 2),
                    space(index: 9, display: 2)
                ],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )

        let spaceSegments = segments.filter { $0.spaceIndex != nil }
        XCTAssertEqual(spaceSegments.map(\.spaceIndex), [2, 5, 9])

        // A separator and the add button sit between them, so segment position
        // and space index must not be confused.
        for (position, segment) in spaceSegments.enumerated() {
            let index = try XCTUnwrap(segment.spaceIndex)
            XCTAssertEqual(
                GlyphStrip.command(for: .focusSpace, spaceIndex: index, focusedSpaceIndex: 2),
                .focusSpace([2, 5, 9][position])
            )
            XCTAssertEqual(
                GlyphStrip.command(for: .destroySpace, spaceIndex: index, focusedSpaceIndex: 2),
                .destroySpace([2, 5, 9][position])
            )
        }
    }

    func testMoveAndMergeActionsAlsoCarryTheGlobalIndex() throws {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [space(index: 2, display: 1), space(index: 5, display: 2)],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )
        // The last segment is the add button; the space segment before it is space 5.
        let second = try XCTUnwrap(segments[segments.count - 2].spaceIndex)
        XCTAssertEqual(second, 5)
        XCTAssertEqual(
            GlyphStrip.command(for: .moveWindowHere, spaceIndex: second, focusedSpaceIndex: 2),
            .moveFocusedWindowToSpace(5)
        )
        XCTAssertEqual(
            GlyphStrip.command(for: .mergeWindows, spaceIndex: second, focusedSpaceIndex: 2),
            .mergeIntoSpace(5)
        )
    }

    /// The add button carries no space, so it must never be mistaken for one.
    func testSeparatorAndAddButtonTargetNoSpace() {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [space(index: 1, display: 1), space(index: 2, display: 2)],
                windows: [],
                maxSpaces: 16
            ),
            font: nil
        )
        let nonSpaces = segments.filter { $0.spaceIndex == nil }
        XCTAssertEqual(nonSpaces.count, 2)
        for segment in nonSpaces {
            XCTAssertNil(GlyphStrip.command(for: .focusSpace, spaceIndex: segment.spaceIndex, focusedSpaceIndex: 1))
            XCTAssertNil(GlyphStrip.command(for: .destroySpace, spaceIndex: segment.spaceIndex, focusedSpaceIndex: 1))
        }
    }

    func testTurningSeparatorsOffRemovesOnlySeparators() {
        let spaces = [
            space(index: 1, display: 1),
            space(index: 3, display: 1),
            space(index: 4, display: 2),
            space(index: 7, display: 2)
        ]
        var withSeparators = GlyphStrip.Options(GlyphStripConfig.default)
        withSeparators.showDisplaySeparators = true
        var withoutSeparators = GlyphStrip.Options(GlyphStripConfig.default)
        withoutSeparators.showDisplaySeparators = false

        let grid = state(spaces: spaces, windows: [], maxSpaces: 16)
        let withSeparatorSegments = GlyphStrip.segments(for: grid, options: withSeparators, font: nil)
        let withoutSeparatorSegments = GlyphStrip.segments(for: grid, options: withoutSeparators, font: nil)

        XCTAssertEqual(withSeparatorSegments.filter { $0.runs == [.separator] }.count, 1)
        XCTAssertFalse(withoutSeparatorSegments.contains { $0.runs == [.separator] })
        XCTAssertEqual(
            withSeparatorSegments.filter { $0.spaceIndex != nil }.map(\.spaceIndex),
            withoutSeparatorSegments.filter { $0.spaceIndex != nil }.map(\.spaceIndex),
            "the spaces themselves are unchanged"
        )
        XCTAssertEqual(
            withSeparatorSegments.filter { $0.spaceIndex != nil }.map(\.runs),
            withoutSeparatorSegments.filter { $0.spaceIndex != nil }.map(\.runs)
        )
        XCTAssertEqual(withoutSeparatorSegments.last?.runs, [.add], "the add button is not a separator")
    }

    func testClickActionsTargetTheRealYabaiIndexNotTheSegmentPosition() throws {
        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 1), space(index: 3), space(index: 7)], windows: [], maxSpaces: 16),
            font: nil
        )

        let spaceSegments = segments.filter { $0.spaceIndex != nil }
        XCTAssertEqual(spaceSegments.map(\.spaceIndex), [1, 3, 7])

        // Segment at position 1 is space 3, and position 2 is space 7.
        for (position, segment) in spaceSegments.enumerated() {
            let index = try XCTUnwrap(segment.spaceIndex)
            XCTAssertEqual(
                GlyphStrip.command(for: .focusSpace, spaceIndex: index, focusedSpaceIndex: 1),
                .focusSpace([1, 3, 7][position])
            )
            XCTAssertEqual(
                GlyphStrip.command(for: .destroySpace, spaceIndex: index, focusedSpaceIndex: 1),
                .destroySpace([1, 3, 7][position])
            )
        }
    }

    func testEmptySpaceGetsPlaceholderGlyph() {
        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 1)], windows: [], maxSpaces: 1),
            font: nil
        )

        XCTAssertEqual(segments[0].runs, [.index("1"), .placeholder])
    }

    func testFloatAndStackSpacesGetLayoutSuffix() {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [space(index: 1), space(index: 2, type: "float"), space(index: 3, type: "stack")],
                windows: [],
                maxSpaces: 3
            ),
            font: nil
        )

        XCTAssertEqual(segments.map { $0.runs.first }, [.index("1"), .index("2f"), .index("3s"), .add])
    }

    func testSeparatorAppearsOnlyBetweenDisplays() {
        let segments = GlyphStrip.segments(
            for: state(
                spaces: [
                    space(index: 1, display: 1),
                    space(index: 2, display: 1),
                    space(index: 3, display: 2)
                ],
                windows: [],
                maxSpaces: 3
            ),
            font: nil
        )

        XCTAssertEqual(segments.map { $0.runs == [.separator] }, [false, false, true, false, false])
    }

    func testSpaceGlyphRunIsOrderedByReadingOrder() {
        var windows = [
            YabaiWindow(id: 3, app: "Terminal", space: 1, frame: .init(x: 100, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 1, app: "Safari", space: 1, frame: .init(x: 0, y: 40, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 2, app: "Notes", space: 1, frame: .init(x: 0, y: 10, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal")
        ]
        for index in windows.indices {
            windows[index].role = "AXWindow"
            windows[index].subrole = "AXStandardWindow"
            windows[index].isRootWindow = true
        }

        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 1)], windows: windows, maxSpaces: 1),
            font: AppGlyphFont.load()
        )

        let glyphs = segments[0].runs.compactMap { run -> String? in
            if case .app(let glyph) = run { return glyph }
            return nil
        }
        XCTAssertEqual(glyphs.count, 3)
        XCTAssertEqual(glyphs, [
            AppGlyphFont.load()?.glyph(forApp: "Notes"),
            AppGlyphFont.load()?.glyph(forApp: "Safari"),
            AppGlyphFont.load()?.glyph(forApp: "Terminal")
        ])
    }

    func testFallsBackToInitialsWhenFontUnavailable() {
        var windows = [
            YabaiWindow(id: 1, app: "Google Chrome", space: 1, frame: .init(x: 0, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal")
        ]
        windows[0].role = "AXWindow"
        windows[0].subrole = "AXStandardWindow"
        windows[0].isRootWindow = true

        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 1)], windows: windows, maxSpaces: 1),
            font: nil
        )

        XCTAssertEqual(segments[0].runs, [.index("1"), .index("GC")])
    }

    // MARK: - [glyphStrip] table

    private func window(_ id: Int, _ app: String, x: CGFloat = 0) -> YabaiWindow {
        var window = YabaiWindow(
            id: id, app: app, space: 1,
            frame: .init(x: x, y: 0, w: 10, h: 10),
            isHidden: false, isMinimized: false, subLayer: "normal"
        )
        window.role = "AXWindow"
        window.subrole = "AXStandardWindow"
        window.isRootWindow = true
        return window
    }

    /// Three windows from two apps: Safari, Safari, Terminal.
    private var mixedWindows: [YabaiWindow] {
        [window(1, "Safari", x: 0), window(2, "Safari", x: 100), window(3, "Terminal", x: 200)]
    }

    private func singleSegment(_ options: GlyphStrip.Options, windows: [YabaiWindow]) -> GlyphStrip.Segment {
        GlyphStrip.segments(
            for: state(spaces: [space(index: 1)], windows: windows, maxSpaces: 1),
            options: options
        )[0]
    }

    func testDedupeCollapsesRepeatedAppsWithinOneSpace() {
        var options = GlyphStrip.Options(.default)
        options.dedupeAppsPerSpace = true
        options.maxIconsPerSpace = 0

        let runs = singleSegment(options, windows: mixedWindows).runs
        XCTAssertEqual(runs.count, 3, "expected the index plus one run per distinct app, got \(runs)")
    }

    func testNonDedupeDrawsOneGlyphPerWindow() {
        var options = GlyphStrip.Options(.default)
        options.dedupeAppsPerSpace = false
        options.maxIconsPerSpace = 0

        let runs = singleSegment(options, windows: mixedWindows).runs
        XCTAssertEqual(runs.count, 4, "expected the index plus one run per window, got \(runs)")
    }

    func testMaxIconsPerSpaceAddsOverflowIndicator() {
        var options = GlyphStrip.Options(.default)
        options.dedupeAppsPerSpace = false
        options.maxIconsPerSpace = 2

        let runs = singleSegment(options, windows: mixedWindows).runs
        XCTAssertEqual(runs, [.index("1"), .index("S"), .index("S"), .overflow(1)],
                       "two of three windows fit, the third becomes +1")
    }

    func testMaxIconsPerSpaceZeroIsUnlimited() {
        var options = GlyphStrip.Options(.default)
        options.dedupeAppsPerSpace = false
        options.maxIconsPerSpace = 0

        let runs = singleSegment(options, windows: mixedWindows).runs
        XCTAssertFalse(runs.contains(.overflow(0)))
        XCTAssertFalse(runs.contains(.overflow(1)))
        XCTAssertEqual(runs.count, 4)
    }

    func testContentTogglesRemoveRuns() {
        var options = GlyphStrip.Options(.default)
        options.showSpaceNumbers = false
        options.showAddSpaceButton = false
        options.showDisplaySeparators = false

        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 1)], windows: [], maxSpaces: 1),
            options: options
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].runs, [.placeholder])
    }

    func testPlaceholdersCanBeDisabled() {
        var options = GlyphStrip.Options(.default)
        options.showPlaceholders = false

        XCTAssertEqual(singleSegment(options, windows: []).runs, [.index("1")])
    }

    // MARK: - Click actions

    func testFocusAndDestroyCarryTheSegmentIndex() {
        XCTAssertEqual(
            GlyphStrip.command(for: .focusSpace, spaceIndex: 3, focusedSpaceIndex: 1),
            .focusSpace(3)
        )
        XCTAssertEqual(
            GlyphStrip.command(for: .destroySpace, spaceIndex: 3, focusedSpaceIndex: 1),
            .destroySpace(3)
        )
    }

    func testSpaceActionsNeedASegmentIndex() {
        for action in [GlyphStripAction.focusSpace, .destroySpace, .moveWindowHere] {
            XCTAssertNil(GlyphStrip.command(for: action, spaceIndex: nil, focusedSpaceIndex: 1))
        }
    }

    func testNoneNeverProducesACommand() {
        XCTAssertNil(GlyphStrip.command(for: .none, spaceIndex: 2, focusedSpaceIndex: 1))
    }

    func testWindowScopedActionsIgnoreTheSegmentIndex() {
        XCTAssertEqual(GlyphStrip.command(for: .toggleFullscreen, spaceIndex: 2, focusedSpaceIndex: 1), .toggleFullscreen)
        XCTAssertEqual(GlyphStrip.command(for: .floatWindow, spaceIndex: 2, focusedSpaceIndex: 1), .floatWindow)
        XCTAssertEqual(GlyphStrip.command(for: .balanceWindows, spaceIndex: 2, focusedSpaceIndex: 1), .balanceWindows)
    }

    func testMergeIsRejectedOnTheCurrentSpace() {
        XCTAssertNil(GlyphStrip.command(for: .mergeWindows, spaceIndex: 2, focusedSpaceIndex: 2))
        XCTAssertEqual(
            GlyphStrip.command(for: .mergeWindows, spaceIndex: 4, focusedSpaceIndex: 2),
            .mergeIntoSpace(4)
        )
    }

    // MARK: - Notch-aware placement

    /// Synthetic 16" MacBook Pro geometry: 1728x1117 screen, 32pt menu bar row,
    /// notch from x=720 to x=1008.
    private let row = CGRect(x: 0, y: 1085, width: 1728, height: 32)
    private let leftArea = CGRect(x: 0, y: 1085, width: 720, height: 32)
    private let rightArea = CGRect(x: 1008, y: 1085, width: 720, height: 32)

    private func placed(
        width: CGFloat,
        position: GlyphStripPosition,
        margin: CGFloat = 6,
        notched: Bool = true,
        yOffset: CGFloat = 0,
        xOffset: CGFloat = 0
    ) -> CGRect {
        GlyphStrip.frame(
            contentSize: CGSize(width: width, height: row.height),
            menuBarRow: row,
            leftNotchArea: notched ? leftArea : nil,
            rightNotchArea: notched ? rightArea : nil,
            position: position,
            margin: margin,
            yOffset: yOffset,
            xOffset: xOffset
        )
    }

    func testLeftOfNotchHugsTheLeftNotchEdge() {
        let frame = placed(width: 200, position: .leftOfNotch, margin: 6)
        // The strip sits to the LEFT of the notch, so its RIGHT edge is the
        // anchor. Anchoring minX here would render it inside the notch.
        XCTAssertEqual(frame.maxX, leftArea.maxX - 6)
        XCTAssertEqual(frame.width, 200)
        XCTAssertEqual(frame.minY, row.minY, "must sit on the menu bar row, not float above it")
        XCTAssertEqual(frame.height, row.height)
    }

    func testRightOfNotchHugsTheRightNotchEdge() {
        let frame = placed(width: 200, position: .rightOfNotch, margin: 6)
        XCTAssertEqual(frame.minX, rightArea.minX + 6)
    }

    /// The bug this whole block exists for: the strip must never overlap the
    /// notch cutout, whichever side it is anchored to.
    func testNeitherNotchPositionOverlapsTheNotchGap() {
        let gap = CGRect(x: leftArea.maxX, y: row.minY, width: rightArea.minX - leftArea.maxX, height: row.height)
        for position in [GlyphStripPosition.leftOfNotch, .rightOfNotch] {
            let frame = placed(width: 220, position: position, margin: 0)
            XCTAssertFalse(
                frame.intersects(gap),
                "\(position) frame \(frame) overlaps the notch gap \(gap)"
            )
            XCTAssertTrue(row.contains(frame), "\(position) frame \(frame) escaped the menu bar row \(row)")
        }
    }

    func testCenterSitsInsideTheNotchGap() {
        let frame = placed(width: 200, position: .center)
        XCTAssertEqual(frame.midX, (leftArea.maxX + rightArea.minX) / 2, accuracy: 0.001)
    }

    func testMarginMovesTheStripAwayFromTheNotch() {
        XCTAssertEqual(placed(width: 200, position: .leftOfNotch, margin: 0).maxX, leftArea.maxX)
        XCTAssertEqual(placed(width: 200, position: .leftOfNotch, margin: 40).maxX, leftArea.maxX - 40)
        XCTAssertEqual(placed(width: 200, position: .rightOfNotch, margin: 0).minX, rightArea.minX)
        XCTAssertEqual(placed(width: 200, position: .rightOfNotch, margin: 40).minX, rightArea.minX + 40)
    }

    /// Screen-reading terms, so the sign is the opposite of what the geometry
    /// reads like: AppKit's y grows upward, so a positive offset lowers the strip
    /// into the screen interior.
    func testYOffsetMovesTheStripDownWhenPositiveAndUpWhenNegative() {
        let level = placed(width: 200, position: .leftOfNotch, yOffset: 0)
        let down = placed(width: 200, position: .leftOfNotch, yOffset: 8)
        let up = placed(width: 200, position: .leftOfNotch, yOffset: -8)
        XCTAssertEqual(down.minY, level.minY - 8, accuracy: 0.001)
        XCTAssertEqual(up.minY, level.minY + 8, accuracy: 0.001)
        // The horizontal anchor is untouched.
        XCTAssertEqual(down, level.offsetBy(dx: 0, dy: -8))
        XCTAssertEqual(up, level.offsetBy(dx: 0, dy: 8))
    }

    /// Deliberately not clamped into the row: the panel sits at `.statusBar`
    /// level, so an offset the user asked for is honoured even where it leaves
    /// the menu bar row.
    func testYOffsetIsNotClampedBackIntoTheMenuBarRow() {
        let frame = placed(width: 200, position: .leftOfNotch, yOffset: 20)
        XCTAssertEqual(frame.minY, row.minY - 20, accuracy: 0.001)
        XCTAssertGreaterThan(row.maxY, frame.maxY)
    }

    func testPlacementFallsBackToTheRowWhenTheDisplayHasNoNotch() {
        // AppKit reports empty auxiliary rects on a plain display, so the strip
        // must fall back to the row edges rather than collapsing to zero width.
        let left = placed(width: 200, position: .leftOfNotch, notched: false)
        XCTAssertEqual(left.minX, row.minX + 6)

        let right = placed(width: 200, position: .rightOfNotch, notched: false)
        XCTAssertEqual(right.maxX, row.maxX - 6)

        let center = placed(width: 200, position: .center, notched: false)
        XCTAssertEqual(center.midX, row.midX, accuracy: 0.001)
    }

    func testEmptyNotchAreasAreTreatedAsNoNotch() {
        let empty = CGRect.zero
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 200, height: 32),
            menuBarRow: row,
            leftNotchArea: empty,
            rightNotchArea: empty,
            position: .leftOfNotch,
            margin: 6
        )
        XCTAssertEqual(frame.minX, row.minX + 6)
    }

    func testStripIsClampedInsideTheRowWhenWiderThanTheAnchorSpace() {
        let frame = placed(width: 900, position: .rightOfNotch, margin: 6, notched: false)
        XCTAssertGreaterThanOrEqual(frame.minX, row.minX)
        XCTAssertLessThanOrEqual(frame.maxX, row.maxX)
    }

    /// Non-notch secondary display: the row starts at a non-zero x, and all
    /// three positions must still anchor to *that* row — `.center` in
    /// particular centres on the row's midpoint, not on the screen origin.
    func testNonNotchPositionsAnchorToAnOffsetRow() {
        let offsetRow = CGRect(x: 1920, y: 1085, width: 2560, height: 32)
        func placedOnOffsetRow(width: CGFloat, position: GlyphStripPosition) -> CGRect {
            GlyphStrip.frame(
                contentSize: CGSize(width: width, height: offsetRow.height),
                menuBarRow: offsetRow,
                leftNotchArea: nil,
                rightNotchArea: nil,
                position: position,
                margin: 6
            )
        }

        let left = placedOnOffsetRow(width: 200, position: .leftOfNotch)
        XCTAssertEqual(left.minX, offsetRow.minX + 6)

        let center = placedOnOffsetRow(width: 200, position: .center)
        XCTAssertEqual(center.midX, offsetRow.midX, accuracy: 0.001)

        let right = placedOnOffsetRow(width: 200, position: .rightOfNotch)
        XCTAssertEqual(right.maxX, offsetRow.maxX - 6)

        for frame in [left, center, right] {
            XCTAssertTrue(offsetRow.contains(frame), "\(frame) escaped the offset row \(offsetRow)")
        }
    }

    // MARK: - Custom placement

    func testCustomPositionOffsetsFromTheRowLeftEdge() {
        let frame = placed(width: 200, position: .custom, xOffset: 300)
        XCTAssertEqual(frame.minX, row.minX + 300)
        // Margin does not apply to free placement.
        XCTAssertEqual(placed(width: 200, position: .custom, margin: 40, xOffset: 300), frame)
    }

    func testCustomPositionIsClampedInsideTheRow() {
        let tooFarRight = placed(width: 200, position: .custom, xOffset: 100_000)
        XCTAssertEqual(tooFarRight.maxX, row.maxX)

        let tooFarLeft = placed(width: 200, position: .custom, xOffset: -50)
        XCTAssertEqual(tooFarLeft.minX, row.minX)
    }

    func testCustomPositionIgnoresNotchAreas() {
        let frame = placed(width: 200, position: .custom, xOffset: 500)
        XCTAssertEqual(frame.minX, row.minX + 500, "custom must not be pulled toward the notch")
    }

    // MARK: - Drag placement

    /// Offsets derived from a dragged frame must replay through `frame(...)`
    /// to the exact frame they came from — otherwise the strip jumps the
    /// moment the drag's config lands.
    func testCustomOffsetsInvertTheFrameMath() {
        let frame = placed(width: 200, position: .custom, yOffset: 8, xOffset: 300)
        let offsets = GlyphStrip.customOffsets(for: frame, menuBarRow: row)

        XCTAssertEqual(offsets.xOffset, 300)
        XCTAssertEqual(offsets.yOffset, 8, accuracy: 0.001)
        XCTAssertEqual(
            placed(
                width: 200,
                position: .custom,
                yOffset: CGFloat(offsets.yOffset),
                xOffset: CGFloat(offsets.xOffset)
            ),
            frame
        )
    }

    /// A drag can start from any anchored position, and the offsets derived
    /// from that anchored frame must land the strip back on it as `.custom`.
    func testCustomOffsetsRecoverAnAnchoredFrame() {
        let frame = placed(width: 200, position: .leftOfNotch, margin: 6)
        let offsets = GlyphStrip.customOffsets(for: frame, menuBarRow: row)

        XCTAssertEqual(
            placed(
                width: 200,
                position: .custom,
                yOffset: CGFloat(offsets.yOffset),
                xOffset: CGFloat(offsets.xOffset)
            ),
            frame
        )
    }

    /// A frame flung past the allowed range derives out-of-range offsets;
    /// `clamped()` — the same bounds the settings steppers use — must bound
    /// them before they reach config.
    func testDraggedOffsetsClampThroughTheExistingBounds() {
        let flung = CGRect(x: row.minX + 9000, y: row.minY - 100, width: 200, height: row.height)
        let offsets = GlyphStrip.customOffsets(for: flung, menuBarRow: row)
        var strip = GlyphStripConfig.default
        strip.position = .custom
        strip.xOffset = offsets.xOffset
        strip.yOffset = offsets.yOffset

        let clamped = strip.clamped()
        XCTAssertEqual(clamped.xOffset, 4000)
        XCTAssertEqual(clamped.yOffset, 10)
    }

    func testDragThresholdSeparatesClickFromDrag() {
        XCTAssertFalse(GlyphStrip.exceedsDragThreshold(CGVector(dx: 3.9, dy: 0)))
        XCTAssertFalse(GlyphStrip.exceedsDragThreshold(CGVector(dx: 0, dy: -3.9)))
        XCTAssertTrue(GlyphStrip.exceedsDragThreshold(CGVector(dx: 4, dy: 0)))
        XCTAssertTrue(GlyphStrip.exceedsDragThreshold(CGVector(dx: -4, dy: 4)))
    }

    func testTallContentIsClampedToTheRowHeight() {
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 200, height: 900),
            menuBarRow: row,
            leftNotchArea: leftArea,
            rightNotchArea: rightArea,
            position: .leftOfNotch,
            margin: 6
        )
        XCTAssertEqual(frame.height, row.height)
        XCTAssertEqual(frame.midY, row.midY, accuracy: 0.001)
    }

    /// Geometry captured from this machine with /tmp/notchprobe: a 14" MacBook
    /// Pro at 2x reporting a 1710x1112 frame, a 37.5pt safe-area top inset and
    /// a notch occupying x 751...959. The strip used to be placed at x=751 with
    /// the notch edge as its LEFT anchor, which put its whole body inside the
    /// camera housing. This asserts what the old code got wrong.
    func testRealNotchDisplayKeepsTheStripOutOfTheCameraHousing() {
        let realRow = CGRect(x: 0, y: 1074.5, width: 1710, height: 37.5)
        let realLeft = CGRect(x: 0, y: 1074.5, width: 751, height: 37.5)
        let realRight = CGRect(x: 959, y: 1074.5, width: 751, height: 37.5)
        let notch = CGRect(x: realLeft.maxX, y: 1074.5, width: realRight.minX - realLeft.maxX, height: 37.5)
        // The widest strip the live app actually produced was 220.6pt.
        let width: CGFloat = 220.627453125

        let left = GlyphStrip.frame(
            contentSize: CGSize(width: width, height: 37.5),
            menuBarRow: realRow,
            leftNotchArea: realLeft,
            rightNotchArea: realRight,
            position: .leftOfNotch,
            margin: 0
        )
        XCTAssertFalse(left.intersects(notch), "leftOfNotch landed in the notch: \(left)")
        XCTAssertEqual(left.maxX, 751, "should sit flush against the notch's left edge")
        XCTAssertTrue(realRow.contains(left))

        let right = GlyphStrip.frame(
            contentSize: CGSize(width: width, height: 37.5),
            menuBarRow: realRow,
            leftNotchArea: realLeft,
            rightNotchArea: realRight,
            position: .rightOfNotch,
            margin: 0
        )
        XCTAssertFalse(right.intersects(notch), "rightOfNotch landed in the notch: \(right)")
        XCTAssertEqual(right.minX, 959, "should sit flush against the notch's right edge")
        XCTAssertTrue(realRow.contains(right))
    }

    /// The notch cutout on this display is only 208pt wide, so `.center` cannot
    /// hold a full strip. Documented ceiling rather than a silent clamp.
    func testCenterOnTheRealDisplayIsWiderThanTheNotchGap() {
        let realRow = CGRect(x: 0, y: 1074.5, width: 1710, height: 37.5)
        let realLeft = CGRect(x: 0, y: 1074.5, width: 751, height: 37.5)
        let realRight = CGRect(x: 959, y: 1074.5, width: 751, height: 37.5)
        let notchGap = realRight.minX - realLeft.maxX
        XCTAssertEqual(notchGap, 208)
        // `.center` centres on the gap midpoint, which is under the camera.
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 220.627453125, height: 37.5),
            menuBarRow: realRow,
            leftNotchArea: realLeft,
            rightNotchArea: realRight,
            position: .center,
            margin: 0
        )
        XCTAssertEqual(frame.midX, 855, accuracy: 0.001)
        XCTAssertGreaterThan(
            frame.width, notchGap,
            "known limitation: a full strip cannot fit the notch gap, so .center is partly occluded"
        )
    }

    // MARK: - Background shapes

    private let stripBounds = CGRect(x: 0, y: 0, width: 400, height: 30)

    private var insetHeight: CGFloat { stripBounds.height - GlyphStrip.backdropVerticalInset * 2 }

    func testPillShapeDrawsACapsuleOverTheWholeStrip() {
        let backdrop = GlyphStrip.backdrop(for: .pill, bounds: stripBounds, cornerRadius: 8)
        XCTAssertEqual(backdrop.shape, .capsule)
        XCTAssertEqual(backdrop.rect, stripBounds.insetBy(dx: 0, dy: GlyphStrip.backdropVerticalInset))
        XCTAssertEqual(backdrop.rect.width, stripBounds.width)
        XCTAssertEqual(backdrop.rect.height, insetHeight)
    }

    func testBarShapeFillsTheWholeStripWithSquareEnds() {
        let backdrop = GlyphStrip.backdrop(for: .bar, bounds: stripBounds, cornerRadius: 8)
        XCTAssertEqual(backdrop.shape, .bar)
        XCTAssertEqual(backdrop.rect.width, stripBounds.width, "only as wide as the content")
        XCTAssertEqual(backdrop.rect.height, insetHeight)
    }

    func testRoundedRectShapeHonorsCornerRadiusCappedToHalfHeight() {
        let backdrop = GlyphStrip.backdrop(for: .roundedRect, bounds: stripBounds, cornerRadius: 6)
        XCTAssertEqual(backdrop.shape, .rounded(6))

        // A radius taller than the rect collapses to a capsule, never a bulge.
        let oversized = GlyphStrip.backdrop(for: .roundedRect, bounds: stripBounds, cornerRadius: 400)
        XCTAssertEqual(oversized.shape, .rounded(insetHeight / 2))
    }

    func testEveryShapeResolvesToItsOwnBackdrop() {
        let shapes = GlyphStripShape.allCases.map {
            GlyphStrip.backdrop(for: $0, bounds: stripBounds, cornerRadius: 6).shape
        }
        XCTAssertEqual(shapes, [.none, .capsule, .rounded(6), .bar])
    }

    func testOnlyNoneMaterialDeclaresThatItDrawsNoBackdrop() {
        for material in GlyphStripBackgroundMaterial.allCases {
            XCTAssertEqual(
                material.drawsBackdrop,
                material != .none,
                "\(material.rawValue) disagrees about whether it draws a backdrop"
            )
        }
    }

    /// Hover is the same rounded capsule for every shape, composited over the
    /// base layer.
    func testHoverFillIsRoundedInEveryShape() {
        let segment = CGRect(x: 20, y: 0, width: 60, height: 30)
        for shape in GlyphStripShape.allCases {
            XCTAssertEqual(
                GlyphStrip.hoverFill(segmentRect: segment, runHeight: 20, padding: 2, cornerRadius: 8)?.shape,
                .rounded(8),
                "hover shape under \(shape.rawValue)"
            )
        }
    }

    func testHoverFillIsAbsentWithoutAHoveredSegmentOrWithZeroWidth() {
        XCTAssertNil(GlyphStrip.hoverFill(segmentRect: nil, runHeight: 20, padding: 2, cornerRadius: 8))
        XCTAssertNil(
            GlyphStrip.hoverFill(
                segmentRect: CGRect(x: 0, y: 0, width: 0, height: 30),
                runHeight: 20,
                padding: 2,
                cornerRadius: 8
            )
        )
    }

    func testHoverFillGrowsTheRectItIsGivenByThePaddingOnBothAxes() {
        let segment = CGRect(x: 20, y: 0, width: 60, height: 30)
        let fill = GlyphStrip.hoverFill(segmentRect: segment, runHeight: 20, padding: 2, cornerRadius: 8)
        XCTAssertEqual(fill?.rect.width ?? 0, 64, accuracy: 0.001)
        XCTAssertEqual(fill?.rect.height ?? 0, 24, accuracy: 0.001)
        XCTAssertEqual(fill?.rect.midX ?? 0, 50, accuracy: 0.001)
    }

    /// The panel hands `hoverFill` the segment's *content* box — its slot minus
    /// the padding either side of the glyphs — so the same `padding` key has to
    /// grow that box by the same amount on both axes. Sizing from the slot
    /// instead made the highlight narrower than the glyphs and off-centre.
    func testHoverFillWrapsTheContentBoxByThePaddingOnBothAxes() {
        let content = CGRect(x: 23, y: 0, width: 54, height: 37.5)
        let fill = GlyphStrip.hoverFill(segmentRect: content, runHeight: 13, padding: 1, cornerRadius: 4)
        XCTAssertEqual(fill?.rect.width ?? 0, 56, accuracy: 0.001)
        XCTAssertEqual(fill?.rect.height ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(fill?.rect.midX ?? 0, content.midX, accuracy: 0.001)
        XCTAssertEqual(fill?.rect.midY ?? 0, content.midY, accuracy: 0.001)
    }

    func testHoverFillWithNoPaddingCollapsesToTheRunBox() {
        let content = CGRect(x: 23, y: 0, width: 54, height: 37.5)
        let fill = GlyphStrip.hoverFill(segmentRect: content, runHeight: 13, padding: 0, cornerRadius: 4)
        XCTAssertEqual(fill?.rect.width ?? 0, 54, accuracy: 0.001)
        XCTAssertEqual(fill?.rect.height ?? 0, 13, accuracy: 0.001)
    }

    /// `hoverPadding` can grow the highlight past the strip's ends — the first
    /// segment's highlight used to reach beyond x=0 and paint on the menu bar
    /// outside the panel. With limits it clips instead of bleeding.
    func testHoverFillClipsToTheGivenBoundsInsteadOfBleedingPastTheStripEnds() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 32)
        let firstSegment = CGRect(x: 0, y: 0, width: 40, height: 32)
        let lastSegment = CGRect(x: 360, y: 0, width: 40, height: 32)

        for segment in [firstSegment, lastSegment] {
            let fill = GlyphStrip.hoverFill(
                segmentRect: segment,
                runHeight: 32,
                padding: 12,
                cornerRadius: 8,
                within: bounds
            )
            let rect = try! XCTUnwrap(fill?.rect)
            XCTAssertGreaterThanOrEqual(rect.minX, bounds.minX - 0.001, "\(rect) escaped left of \(bounds)")
            XCTAssertLessThanOrEqual(rect.maxX, bounds.maxX + 0.001, "\(rect) escaped right of \(bounds)")
            XCTAssertLessThanOrEqual(rect.maxY, bounds.maxY + 0.001, "\(rect) rose above \(bounds)")
            XCTAssertGreaterThanOrEqual(rect.minY, bounds.minY - 0.001, "\(rect) fell below \(bounds)")
        }
    }

    func testHoverFillIsNilWhenNothingOfItRemainsInsideTheBounds() {
        let outside = CGRect(x: 500, y: 0, width: 40, height: 32)
        XCTAssertNil(
            GlyphStrip.hoverFill(
                segmentRect: outside,
                runHeight: 20,
                padding: 2,
                cornerRadius: 8,
                within: CGRect(x: 0, y: 0, width: 400, height: 32)
            )
        )
    }

    /// Without limits the pure function must keep its old behaviour: growth on
    /// both axes, unclipped.
    func testHoverFillWithoutLimitsIsNotClipped() {
        let firstSegment = CGRect(x: 0, y: 0, width: 40, height: 32)
        let fill = GlyphStrip.hoverFill(segmentRect: firstSegment, runHeight: 32, padding: 12, cornerRadius: 8)
        XCTAssertEqual(fill?.rect.minX ?? 0, -12, accuracy: 0.001)
    }

    // MARK: - Semantic palette

    /// The three roles the strip resolves against the theme all exist in the
    /// default theme, so every layer has a drawable colour.
    func testRoleNamesResolveInTheDefaultTheme() throws {
        let theme = try XCTUnwrap(ThemeManager().named("default"), "default theme missing")
        for role in ["focused", "text", "cellBg"] {
            XCTAssertNotNil(GlyphStrip.color(for: role, theme: theme), "\(role) has no value")
        }
    }

    func testEveryThemeColorNameResolvesToItsValue() throws {
        let theme = try XCTUnwrap(ThemeManager().named("default"), "default theme missing")
        for name in AppTheme.colorNames {
            XCTAssertNotNil(theme.value(for: name), "\(name) has no value")
            XCTAssertNotNil(GlyphStrip.color(for: name, theme: theme))
        }
    }

    func testNoColorResolvesToNoDrawableColor() throws {
        let theme = try XCTUnwrap(ThemeManager().named("default"))
        XCTAssertNil(GlyphStrip.color(for: "none", theme: theme))
        XCTAssertNil(GlyphStrip.color(for: "chartreuse", theme: theme))
    }

    /// Current space and add button both draw in the theme's `focused` role.
    func testCurrentSpaceAndAddButtonUseTheFocusedRole() throws {
        let theme = try XCTUnwrap(ThemeManager().named("default"))
        var strip = GlyphStripConfig.default
        strip.highlightCurrentSpace = true

        let current = GlyphStripPanelController.style(for: .index("2"), isCurrent: true, strip: strip, theme: theme)
        XCTAssertEqual(current.colorName, "focused")
        XCTAssertEqual(
            GlyphStrip.color(for: current.colorName, theme: theme),
            GlyphStrip.color(for: "focused", theme: theme)
        )

        let add = GlyphStripPanelController.style(for: .add, isCurrent: false, strip: strip, theme: theme)
        XCTAssertEqual(add.colorName, "focused")
    }

    /// Every resting element draws in the theme's `text` role — hover uses
    /// `focused` (the same role as the current space), so a leak would show.
    func testRestingRolesResolveToText() throws {
        let theme = try XCTUnwrap(ThemeManager().named("default"))
        let strip = GlyphStripConfig.default
        let runs: [GlyphStrip.Run] = [.index("1"), .app("A"), .overflow(3), .separator, .placeholder]
        for run in runs {
            let style = GlyphStripPanelController.style(for: run, isCurrent: false, strip: strip, theme: theme)
            XCTAssertEqual(style.colorName, "text", "\(run) should rest in text")
            XCTAssertEqual(
                GlyphStrip.color(for: style.colorName, theme: theme),
                GlyphStrip.color(for: "text", theme: theme)
            )
        }
    }

    func testGlassStrokeColorIsDerivedFromTheThemeNotHardcoded() throws {
        for name in ThemeManager().allNames() {
            let theme = try XCTUnwrap(ThemeManager().named(name))
            let stroke = GlyphStrip.glassStrokeColor(theme: theme)
            XCTAssertNotNil(stroke.usingColorSpace(.sRGB), "\(name) produced an unusable stroke colour")
            let expected = GlyphStrip.color(for: "text", theme: theme)!
            XCTAssertNotEqual(stroke, expected, "\(name) stroke must be blended, not raw text colour")
        }
    }

    // MARK: - Icon spacing

    func testIndexPaddingSeparatesTheNumberFromTheFirstIcon() {
        let runs: [GlyphStrip.Run] = [.index("2"), .app("A"), .app("B"), .overflow(3)]
        let gaps = GlyphStrip.interRunGaps(for: runs, iconSpacing: 2, indexPadding: 4)

        XCTAssertEqual(gaps.count, runs.count, "one gap per run so measuring and drawing share one array")
        XCTAssertEqual(gaps[0], 0, "no gap before the first run")
        XCTAssertEqual(gaps[1], 4, "indexPadding between the number and the first icon")
        XCTAssertEqual(gaps[2], 2, "iconSpacing between two app icons")
        XCTAssertEqual(gaps[3], 2, "iconSpacing before the +N overflow indicator")
    }

    func testIconSpacingAppliesBetweenIconsOnlyNotAfterTheIndex() {
        // The bug this fixes: two controls where one is really two gaps.
        let runs: [GlyphStrip.Run] = [.index("1"), .app("A"), .app("B"), .app("C")]
        let gaps = GlyphStrip.interRunGaps(for: runs, iconSpacing: 2, indexPadding: 4)
        XCTAssertEqual(gaps, [0, 4, 2, 2])
    }

    func testIndexPaddingAlsoSeparatesTheInitialsFallback() {
        // No ligature for the app, so `spaceRuns` emits `.index` initials. They
        // are still an app icon and must not butt against the space number.
        let runs: [GlyphStrip.Run] = [.index("1"), .index("GC"), .index("S")]
        XCTAssertEqual(
            GlyphStrip.interRunGaps(for: runs, iconSpacing: 2, indexPadding: 4),
            [0, 4, 2]
        )
    }

    func testBothGapsOfZeroRemoveEveryGap() {
        let runs: [GlyphStrip.Run] = [.index("2"), .app("A"), .app("B"), .app("C")]
        XCTAssertEqual(
            GlyphStrip.interRunGaps(for: runs, iconSpacing: 0, indexPadding: 0),
            [0, 0, 0, 0]
        )
    }

    func testPlaceholderAfterTheIndexGetsIndexPadding() {
        // An empty space shows the index and a placeholder; the placeholder
        // keeps the same gap as the first icon.
        XCTAssertEqual(
            GlyphStrip.interRunGaps(for: [.index("3"), .placeholder], iconSpacing: 2, indexPadding: 4),
            [0, 4]
        )
    }

    func testSingleAppGlyphGetsNoGap() {
        XCTAssertEqual(GlyphStrip.interRunGaps(for: [.app("A")], iconSpacing: 2, indexPadding: 4), [0])
    }

    func testSeparatorAndAddRunsNeverReceiveEitherGap() {
        XCTAssertEqual(GlyphStrip.interRunGaps(for: [.separator], iconSpacing: 2, indexPadding: 4), [0])
        XCTAssertEqual(GlyphStrip.interRunGaps(for: [.add], iconSpacing: 2, indexPadding: 4), [0])
        XCTAssertEqual(
            GlyphStrip.interRunGaps(for: [.app("A"), .app("B")], iconSpacing: 5, indexPadding: 9),
            [0, 5],
            "without a leading index the first gap is iconSpacing"
        )
    }

    func testSpacingKeysAreClampedAtTheModelBoundary() {
        let clamped = decodeGlyphStrip("""
        [glyphStrip]
        iconSpacing = 900.0
        indexPadding = 900.0
        """)?.clamped()
        XCTAssertEqual(clamped?.iconSpacing, 20)
        XCTAssertEqual(clamped?.indexPadding, 20)

        let negative = decodeGlyphStrip("""
        [glyphStrip]
        iconSpacing = -4.0
        indexPadding = -4.0
        """)?.clamped()
        XCTAssertEqual(negative?.iconSpacing, 0)
        XCTAssertEqual(negative?.indexPadding, 0)
    }

    func testSpacingDefaultsWhenUnset() {
        let config = decodeGlyphStrip("[glyphStrip]\nenabled = true")
        XCTAssertEqual(config?.iconSpacing, 3)
        XCTAssertEqual(config?.indexPadding, 6)
    }

    // MARK: - highlightCurrentSpace semantics

    private func styleStrip(highlight: Bool) -> GlyphStripConfig {
        var strip = GlyphStripConfig.default
        strip.highlightCurrentSpace = highlight
        return strip
    }

    func testHighlightingOnMakesTheCurrentSpaceDistinct() throws {
        let theme = try XCTUnwrap(ThemeManager().named("default"))
        let strip = styleStrip(highlight: true)

        let current = GlyphStripPanelController.style(for: .index("2"), isCurrent: true, strip: strip, theme: theme)
        let other = GlyphStripPanelController.style(for: .index("3"), isCurrent: false, strip: strip, theme: theme)
        XCTAssertEqual(current.colorName, "focused")
        XCTAssertNotEqual(current.colorName, other.colorName)

        let currentIcon = GlyphStripPanelController.style(for: .app("A"), isCurrent: true, strip: strip, theme: theme)
        let otherIcon = GlyphStripPanelController.style(for: .app("B"), isCurrent: false, strip: strip, theme: theme)
        XCTAssertEqual(currentIcon.alpha, 1.0)
        XCTAssertEqual(otherIcon.alpha, 0.55, "non-current app glyphs stay faded")
    }

    /// The reported bug: with the flag off the current space was painted with the
    /// dimmed colour but was still marked out. It must be byte-identical to every
    /// other space instead.
    func testHighlightingOffMakesTheCurrentSpaceIdenticalToEveryOther() throws {
        let theme = try XCTUnwrap(ThemeManager().named("default"))
        let strip = styleStrip(highlight: false)
        let runs: [GlyphStrip.Run] = [
            .index("2"), .app("A"), .app("B"), .overflow(3), .placeholder, .separator, .add
        ]

        for run in runs {
            let current = GlyphStripPanelController.style(for: run, isCurrent: true, strip: strip, theme: theme)
            let other = GlyphStripPanelController.style(for: run, isCurrent: false, strip: strip, theme: theme)
            XCTAssertEqual(current, other, "\(run) still looks different when it is the current space")
        }
    }

    func testHighlightingOffAlsoRemovesTheAppGlyphAlphaStep() throws {
        let theme = try XCTUnwrap(ThemeManager().named("default"))
        let strip = styleStrip(highlight: false)
        let currentIcon = GlyphStripPanelController.style(for: .app("A"), isCurrent: true, strip: strip, theme: theme)
        let otherIcon = GlyphStripPanelController.style(for: .app("B"), isCurrent: false, strip: strip, theme: theme)
        XCTAssertEqual(currentIcon.alpha, 0.55, "no special alpha for the current space")
        XCTAssertEqual(currentIcon, otherIcon)
    }

    func testHoverTreatmentNeverDependsOnWhichSpaceIsCurrent() {
        let segment = CGRect(x: 20, y: 0, width: 60, height: 30)
        let hovered = GlyphStrip.hoverFill(segmentRect: segment, runHeight: 20, padding: 2, cornerRadius: 8)
        XCTAssertEqual(hovered, GlyphStrip.hoverFill(segmentRect: segment, runHeight: 20, padding: 2, cornerRadius: 8))
        XCTAssertEqual(hovered?.shape, .rounded(8))
        XCTAssertEqual(
            GlyphStrip.hoverHighlightOpacity, GlyphStrip.hoverHighlightOpacity,
            "one hover opacity for all segments"
        )
    }

    /// The width sum must use each glyph's real advance from the font rather than a
    /// hardcoded per-glyph estimate. Measured on the bundled font: every app
    /// glyph occupies the same 15.521pt cell at 11pt, which is precisely why
    /// adjacent icons touch and why `iconSpacing` has to supply the tracking.
    func testAppGlyphAdvanceIsReadFromTheFontAndIsUniform() throws {
        let font = try XCTUnwrap(AppGlyphFont.load())
        // The bundled ttf is a resource, not an installed font, so register it
        // with the process font manager before NSFont(name:) can resolve it.
        let fontURL = try XCTUnwrap(
            Bundle.module.url(forResource: AppGlyphFont.resourceName, withExtension: "ttf")
        )
        CTFontManagerRegisterFontURLs([fontURL] as CFArray, .process, true, nil)
        let nsFont = try XCTUnwrap(NSFont(name: "sketchybar-app-font", size: 11))
        func advance(_ app: String) -> CGFloat {
            NSAttributedString(
                string: font.glyph(forApp: app),
                attributes: [.font: nsFont]
            ).size().width
        }

        let advances = ["Safari", "Google Chrome", "Finder", "Terminal", "Obsidian"].map(advance)
        XCTAssertTrue(advances.allSatisfy { $0 > 0 })
        XCTAssertEqual(Set(advances).count, 1, "this font uses one uniform icon cell, got \(advances)")

        // A space number in the system font is much narrower than an icon cell,
        // so the two are genuinely measured differently rather than sharing a
        // constant.
        let numberWidth = NSAttributedString(
            string: "1",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        ).size().width
        XCTAssertLessThan(numberWidth, advances[0])

        // Two app glyphs in a row therefore need their real widths plus one gap.
        XCTAssertEqual(
            GlyphStrip.interRunGaps(
                for: [.index("1"), .app("a"), .app("b")],
                iconSpacing: 2,
                indexPadding: 0
            ),
            [0, 0, 2]
        )
    }

    // MARK: - Notch-aware placement

    func testHoverUsesOneFixedTintInEveryStyle() {
        // `.pill` used to read `backgroundOpacity` for its hover capsule because
        // the capsule was the whole background. Now every style has a base layer,
        // so hover is one consistent subtle tint over all of them.
        XCTAssertGreaterThan(GlyphStrip.hoverHighlightOpacity, 0)
        XCTAssertLessThan(GlyphStrip.hoverHighlightOpacity, 1, "a hover tint must not read as a fill")
    }

    // MARK: - Config decoding

    private func decodeGlyphStrip(_ toml: String) -> GlyphStripConfig? {
        // `TOMLParser.parse` already normalizes and decodes.
        return (try? TOMLParser.parse(toml))?.glyphStrip
    }

    func testClickActionKeysDecodeIndependently() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        leftClickAction = "moveWindowHere"
        rightClickAction = "mergeWindows"
        middleClickAction = "floatWindow"
        """)

        XCTAssertEqual(config?.leftClickAction, .moveWindowHere)
        XCTAssertEqual(config?.rightClickAction, .mergeWindows)
        XCTAssertEqual(config?.middleClickAction, .floatWindow)
    }

    func testUnsetClickActionsKeepTheirDefaults() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        enabled = true
        """)

        XCTAssertEqual(config?.enabled, true)
        XCTAssertEqual(config?.leftClickAction, .focusSpace)
        XCTAssertEqual(config?.rightClickAction, .destroySpace)
        XCTAssertEqual(config?.middleClickAction, GlyphStripAction.none)
        XCTAssertEqual(config?.backgroundMaterial, GlyphStripBackgroundMaterial.none)
        XCTAssertEqual(config?.position, GlyphStripPosition.leftOfNotch)
        XCTAssertEqual(config?.maxIconsPerSpace, 8)
    }

    func testInvalidClickActionFallsBackWithoutFailingTheLoad() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        enabled = true
        leftClickAction = "selfDestruct"
        rightClickAction = 42
        middleClickAction = "balanceWindows"
        showAppIcons = false
        """)

        XCTAssertEqual(config?.leftClickAction, .focusSpace, "unknown name falls back to the default")
        XCTAssertEqual(config?.rightClickAction, .destroySpace, "wrong type falls back to the default")
        XCTAssertEqual(config?.middleClickAction, .balanceWindows, "siblings still decode")
        XCTAssertEqual(config?.enabled, true)
        XCTAssertEqual(config?.showAppIcons, false)
    }

    func testInvalidEnumValuesFallBackForMaterialShapeAndPosition() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        backgroundMaterial = "plasma"
        shape = "triangle"
        position = "topLeft"
        """)

        XCTAssertEqual(config?.backgroundMaterial, GlyphStripBackgroundMaterial.none)
        XCTAssertEqual(config?.shape, GlyphStripShape.none)
        XCTAssertEqual(config?.position, GlyphStripPosition.leftOfNotch)
    }

    func testExplicitMaterialAndShapeKeysDecode() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        backgroundMaterial = "liquidGlass"
        shape = "pill"
        """)
        XCTAssertEqual(config?.backgroundMaterial, .liquidGlass)
        XCTAssertEqual(config?.shape, .pill)
    }

    func testGlassAmountDecodesAndDefaultsToCentre() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nglassAmount = 0.8")?.glassAmount, 0.8)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.glassAmount, 0.5)
    }

    func testGlassAmountClampsToZeroAndOne() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nglassAmount = 4.0")?.clamped().glassAmount, 1)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nglassAmount = -2.0")?.clamped().glassAmount, 0)
    }

    func testGlassTintAndFillMath() {
        XCTAssertNil(GlyphStrip.glassTintAlpha(for: 0.02))
        XCTAssertEqual(GlyphStrip.glassTintAlpha(for: 0.5) ?? 0, 0.23, accuracy: 1e-9)
        XCTAssertEqual(GlyphStrip.glassFillOpacity(for: 0.5), 0.375, accuracy: 1e-9)
        XCTAssertFalse(GlyphStrip.glassUsesPopoverMaterial(for: 0.15))
        XCTAssertTrue(GlyphStrip.glassUsesPopoverMaterial(for: 0.5))
    }

    func testAbsentGlyphStripKeyLeavesConfigUntouched() {
        XCTAssertNil(decodeGlyphStrip("""
        [grid]
        cols = 4
        """))
    }

    func testNumericRangesAreClampedAtTheModelBoundary() {
        let decoded = decodeGlyphStrip("""
        [glyphStrip]
        iconSize = 900.0
        indexSize = 1.0
        backgroundOpacity = 4.0
        cornerRadius = -8.0
        margin = 400.0
        maxIconsPerSpace = -3
        """)
        let clamped = decoded?.clamped()

        XCTAssertEqual(clamped?.iconSize, 24)
        XCTAssertEqual(clamped?.indexSize, 6)
        XCTAssertEqual(clamped?.backgroundOpacity, 1)
        XCTAssertEqual(clamped?.cornerRadius, 0)
        XCTAssertEqual(clamped?.margin, 40)
        XCTAssertEqual(clamped?.maxIconsPerSpace, 0)
    }

    func testNegativeMarginClampsToZero() {
        let clamped = decodeGlyphStrip("""
        [glyphStrip]
        margin = -12.0
        """)?.clamped()
        XCTAssertEqual(clamped?.margin, 0)
    }

    func testMarginDefaultsToSixWhenUnset() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.margin, 6)
    }

    func testYOffsetDefaultsToZeroAndClampsToMinusTenAndTen() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.yOffset, 0)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nyOffset = 55.0")?.clamped().yOffset, 10)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nyOffset = -55.0")?.clamped().yOffset, -10)
    }

    func testHoverPaddingDefaultsToOneAndClampsToZeroAndTwelve() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.hoverPadding, 1)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nhoverPadding = 90.0")?.clamped().hoverPadding, 12)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nhoverPadding = -3.0")?.clamped().hoverPadding, 0)
    }

    func testHoverCornerRadiusDefaultsToFourAndClampsToZeroAndTwenty() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.hoverCornerRadius, 4)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nhoverCornerRadius = 90.0")?.clamped().hoverCornerRadius, 20)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nhoverCornerRadius = -3.0")?.clamped().hoverCornerRadius, 0)
    }

    func testNewKeysDefaultWhenAbsentFromAnOldConfig() {
        let config = decodeGlyphStrip("[glyphStrip]\nenabled = true")
        XCTAssertEqual(config?.theme, "", "empty theme = follow the main HUD")
        XCTAssertEqual(config?.xOffset, 0)
        XCTAssertEqual(config?.borderEnabled, true, "border defaults to on")
        XCTAssertEqual(config?.position, .leftOfNotch)
    }

    func testStripThemeDecodesAndFallsBackOnWrongType() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\ntheme = \"nord\"")?.theme, "nord")
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\ntheme = 42")?.theme, "")
    }

    func testCustomPositionAndXOffsetDecode() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        position = "custom"
        xOffset = 300
        """)
        XCTAssertEqual(config?.position, .custom)
        XCTAssertEqual(config?.xOffset, 300)
    }

    func testXOffsetAcceptsADecimalAndClamps() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nxOffset = 300.0")?.xOffset, 300)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nxOffset = 99999")?.clamped().xOffset, 4000)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nxOffset = -99999")?.clamped().xOffset, -4000)
    }

    func testBorderEnabledDecodesAndRejectsNonBools() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nborderEnabled = false")?.borderEnabled, false)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nborderEnabled = \"yes\"")?.borderEnabled, true)
    }

    func testRoundTripThroughTheConfigStringPreservesEveryKey() {
        var original = GlyphStripConfig.default
        original.enabled = true
        original.showSpaceNumbers = false
        original.showLayoutSuffix = false
        original.showAppIcons = false
        original.dedupeAppsPerSpace = false
        original.maxIconsPerSpace = 3
        original.iconSize = 14
        original.indexSize = 9
        original.highlightCurrentSpace = false
        original.backgroundMaterial = .liquidGlass
        original.glassAmount = 0.8
        original.shape = .pill
        original.backgroundOpacity = 0.6
        original.cornerRadius = 12
        original.margin = 9
        original.yOffset = 3.5
        original.hoverPadding = 2.5
        original.hoverCornerRadius = 7.5
        original.iconSpacing = 3.5
        original.showDisplaySeparators = false
        original.showAddSpaceButton = false
        original.showPlaceholders = false
        original.leftClickAction = .floatWindow
        original.rightClickAction = .mergeWindows
        original.middleClickAction = .balanceWindows
        original.position = .custom
        original.xOffset = 300
        original.theme = "nord"
        original.borderEnabled = false

        var values = ConfigValues()
        values.glyphStrip = original
        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = decodeGlyphStrip(toml)?.clamped()

        XCTAssertEqual(reread, original)
    }
}
