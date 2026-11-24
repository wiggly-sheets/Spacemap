import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripSegmentTests: GlyphStripTestCase {

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
        XCTAssertEqual(space4.runs, [.index("4b"), .placeholder])
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

        XCTAssertEqual(segments[0].runs, [.index("1b"), .placeholder])
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

        XCTAssertEqual(segments.map { $0.runs.first }, [.index("1b"), .index("2f"), .index("3s"), .add])
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

    func testSpaceGlyphRunIsOrderedByReadingOrder() throws {
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

        guard let font = AppGlyphFont.load() else {
            throw XCTSkip("sketchybar-app-font is not installed")
        }
        let segments = GlyphStrip.segments(
            for: state(spaces: [space(index: 1)], windows: windows, maxSpaces: 1),
            font: font
        )

        let glyphs = segments[0].runs.compactMap { run -> String? in
            if case .app(let glyph) = run { return glyph }
            return nil
        }
        XCTAssertEqual(glyphs.count, 3)
        XCTAssertEqual(glyphs, [
            font.glyph(forApp: "Notes"),
            font.glyph(forApp: "Safari"),
            font.glyph(forApp: "Terminal")
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

        XCTAssertEqual(segments[0].runs, [.index("1b"), .nativeIcon(app: "Google Chrome", pid: nil, glyph: "GC")])
    }

    // MARK: - [glyphStrip] table

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
        XCTAssertEqual(runs, [.index("1b"), .nativeIcon(app: "Safari", pid: nil, glyph: "S"), .nativeIcon(app: "Safari", pid: nil, glyph: "S"), .overflow(1)],
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

        XCTAssertEqual(singleSegment(options, windows: []).runs, [.index("1b")])
    }
}
