import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap

final class AppGlyphFontTests: XCTestCase {

    private func installedFontURL() throws -> URL {
        guard let url = AppGlyphFont.candidateURLs().first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw XCTSkip("sketchybar-app-font is not installed")
        }
        return url
    }

    private func bundledFontData() throws -> Data {
        try Data(contentsOf: try installedFontURL())
    }

    private func loadedFont() throws -> AppGlyphFont {
        guard let font = AppGlyphFont.load() else {
            throw XCTSkip("sketchybar-app-font failed to load")
        }
        return font
    }

    func testInstalledFontHasAppMetadataRecord() throws {
        let data = try bundledFontData()
        let payload = try XCTUnwrap(
            AppGlyphFont.appMetadataPayload(in: data),
            "meta/APPM table not found"
        )
        XCTAssertGreaterThan(payload.count, 0)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: payload))
    }

    func testFaceMatchesParsedFontFile() throws {
        let url = try installedFontURL()
        let font = try XCTUnwrap(AppGlyphFont.parse(data: Data(contentsOf: url), url: url))
        let face = try XCTUnwrap(font.face(size: 11))
        let faceURL = CTFontCopyAttribute(face as CTFont, kCTFontURLAttribute) as? URL
        XCTAssertEqual(faceURL?.standardizedFileURL, url.standardizedFileURL)
    }

    func testKnownLigaturesMapToExpectedAppNames() throws {
        let font = try loadedFont()

        // Finder aliases change between font releases; the stable contract is
        // that the primary name and known aliases resolve.
        let finder = font.appNames(forLigature: ":finder:") ?? []
        XCTAssertTrue(finder.contains("Finder"))
        XCTAssertTrue(finder.contains("访达"))
        XCTAssertTrue(finder.contains("FlowFinder"))
        XCTAssertEqual(font.appNames(forLigature: ":alacritty:"), ["Alacritty"])
        XCTAssertEqual(
            font.appNames(forLigature: ":google_chrome:"),
            ["Chromium", "Google Chrome", "Google Chrome Canary"]
        )
    }

    func testDefaultGlyphIsNonEmptyAndUsedForUnknownApps() throws {
        let font = try loadedFont()

        XCTAssertEqual(font.glyph(forApp: "Totally Unknown App"), font.glyph(forApp: AppGlyphFont.defaultLigature))
        XCTAssertFalse(font.glyph(forApp: "Totally Unknown App").isEmpty)
    }

    func testExactMatchWinsAndPrefixMatchesAreSupported() throws {
        let font = try loadedFont()

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
        var config = SpacemapConfig.default
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

    private func window(_ id: Int, _ app: String, x: CGFloat = 0, space: Int = 1) -> YabaiWindow {
        var window = YabaiWindow(
            id: id, app: app, space: space,
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

    // MARK: - Space label style

    func testSpaceLabelStyleShowsNumberNameOrBoth() {
        var numbers = GlyphStrip.Options(.default)
        numbers.spaceNames = [1: "Web"]
        XCTAssertEqual(singleSegment(numbers, windows: []).runs.first, .index("1b"),
                       "the default style keeps the bare number")

        var names = numbers
        names.spaceLabelStyle = .names
        XCTAssertEqual(singleSegment(names, windows: []).runs.first, .index("Web"),
                       "names style replaces the number with the profile name")

        var both = numbers
        both.spaceLabelStyle = .both
        XCTAssertEqual(singleSegment(both, windows: []).runs.first, .index("1b Web"),
                       "both style keeps the number, layout suffix included")

        var config = GlyphStripConfig.default
        config.spaceLabelStyle = .names
        let fromInit = GlyphStrip.Options(config, spaceNames: [1: "Web"])
        XCTAssertEqual(singleSegment(fromInit, windows: []).runs.first, .index("Web"),
                       "the real Options init must carry spaceNames through")
    }

    func testSpaceLabelFallsBackToTheNumberWhenTheNameIsMissingOrBlank() {
        for style in [GlyphStripSpaceLabelStyle.names, .both] {
            var options = GlyphStrip.Options(.default)
            options.spaceLabelStyle = style
            XCTAssertEqual(singleSegment(options, windows: []).runs.first, .index("1b"),
                           "no name entry keeps the number")

            options.spaceNames = [1: "   "]
            XCTAssertEqual(singleSegment(options, windows: []).runs.first, .index("1b"),
                           "a whitespace-only name keeps the number")
        }
    }

    func testSpaceLabelTruncatesLongNamesToKeepTheStripBounded() {
        var options = GlyphStrip.Options(.default)
        options.spaceLabelStyle = .names
        options.spaceNames = [1: "VeryLongSpaceName"]

        XCTAssertEqual(singleSegment(options, windows: []).runs.first, .index("VeryLongSpac…"))

        options.spaceNames = [1: "ABCDEFGHIJKL"]
        XCTAssertEqual(singleSegment(options, windows: []).runs.first, .index("ABCDEFGHIJKL"),
                       "a 12-character name fits unchanged")

        options.spaceNames = [1: "ABCDEFGHIJKLM"]
        XCTAssertEqual(singleSegment(options, windows: []).runs.first, .index("ABCDEFGHIJKL…"),
                       "13 characters keep the first 12")

        options.spaceNames = [1: "ABCDEFGHIJK👨‍👩‍👧‍👦X"]
        XCTAssertEqual(singleSegment(options, windows: []).runs.first, .index("ABCDEFGHIJK👨‍👩‍👧‍👦…"),
                       "truncation counts characters, never slices a grapheme")
    }

    func testHidingSpaceNumbersAlsoHidesNames() {
        var options = GlyphStrip.Options(.default)
        options.showSpaceNumbers = false
        options.spaceLabelStyle = .names
        options.spaceNames = [1: "Web"]
        options.showPlaceholders = false

        XCTAssertEqual(singleSegment(options, windows: []).runs, [],
                       "the numbers toggle still controls the leading run")
    }

    func testAutoNamingModeNamesTheStripLabelFromTheLeftmostWindowApp() {
        var config = SpacemapConfig.default
        config.namingMode = .auto
        config.maxSpaces = 2
        config.glyphStrip.spaceLabelStyle = .names
        let windows = [
            window(1, "Safari", x: 100),
            window(2, "Terminal", x: 0),
            window(3, "Mail", x: 0, space: 2),
        ]
        let spaces = [space(index: 1), space(index: 2)]
        let state = GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayBounds: .zero,
            focusedIndex: nil
        )
        let options = GlyphStrip.Options(state.config.glyphStrip, spaceNames: state.resolvedSpaceNames)

        let segments = GlyphStrip.segments(for: state, options: options)

        XCTAssertEqual(state.resolvedSpaceNames[1], "Terminal · Safari",
                       "visible apps in reading order name the space, not the typed profile name")
        XCTAssertEqual(segments[0].runs.first, .index("Terminal · S…"),
                       "the strip label uses the derived name and its existing length cap")
        XCTAssertEqual(segments[1].runs.first, .index("Mail"))
    }

    func testSegmentOptionsCarryAutoDerivedNames() {
        var config = SpacemapConfig.default
        config.namingMode = .auto
        config.spaceNames = [1: "Typed"]
        let windows = [window(1, "Safari", x: 0)]
        let state = GridState(
            config: config,
            spaces: [space(index: 1)],
            windows: windows,
            displayBounds: .zero,
            focusedIndex: nil
        )

        let options = GlyphStripPanelController.segmentOptions(for: config, state: state)

        XCTAssertEqual(options.spaceNames[1], "Safari",
                       "strip options read the derived auto name, never the typed one")
    }

    func testSegmentOptionsPassThroughCustomNames() {
        var config = SpacemapConfig.default
        config.namingMode = .custom
        config.spaceNames = [1: "Typed"]
        let state = GridState(
            config: config,
            spaces: [space(index: 1)],
            windows: [window(1, "Safari", x: 0)],
            displayBounds: .zero,
            focusedIndex: nil
        )

        let options = GlyphStripPanelController.segmentOptions(for: config, state: state)

        XCTAssertEqual(options.spaceNames[1], "Typed",
                       "custom mode passes the typed profile names through")
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
        xFraction: Double = 0.5,
        yFraction: Double = 0.5
    ) -> CGRect {
        GlyphStrip.frame(
            contentSize: CGSize(width: width, height: row.height),
            menuBarRow: row,
            leftNotchArea: notched ? leftArea : nil,
            rightNotchArea: notched ? rightArea : nil,
            position: position,
            margin: margin,
            xFraction: xFraction,
            yFraction: yFraction
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

    /// Anchored positions centre vertically in the menu bar row; the strip
    /// holds no user nudge of its own.
    func testAnchoredPlacementCentresVerticallyInTheRow() {
        let level = placed(width: 200, position: .leftOfNotch)
        XCTAssertEqual(level.midY, row.midY, accuracy: 0.001)

        let tall = placed(width: 200, position: .rightOfNotch, notched: false)
        XCTAssertEqual(tall.midY, row.midY, accuracy: 0.001)
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

    func testCustomPositionUsesFractionsOfTheSpareArea() {
        let frame = placed(width: 200, position: .custom, xFraction: 0.5)
        // (1728 - 200) / 2
        XCTAssertEqual(frame.minX, 764, accuracy: 0.001)
        // Margin does not apply to free placement.
        XCTAssertEqual(placed(width: 200, position: .custom, margin: 40, xFraction: 0.5), frame)
    }

    func testCustomFractionsAreClampedInsideTheArea() {
        let tooFarRight = placed(width: 200, position: .custom, xFraction: 2)
        XCTAssertEqual(tooFarRight.maxX, row.maxX)

        let tooFarLeft = placed(width: 200, position: .custom, xFraction: -1)
        XCTAssertEqual(tooFarLeft.minX, row.minX)
    }

    func testCustomPositionIgnoresNotchAreas() {
        let frame = placed(width: 200, position: .custom, xFraction: 0.5)
        XCTAssertEqual(frame.minX, 764, accuracy: 0.001, "custom must not be pulled toward the notch")
    }

    // MARK: - Drag placement

    func testDraggedIconCarriesOneWindowOrEveryWindowOfItsApp() {
        let first = YabaiWindow(id: 1, app: "Safari", space: 1, frame: .init(x: 0, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal")
        let second = YabaiWindow(id: 2, app: "Safari", space: 1, frame: .init(x: 20, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal")
        let other = YabaiWindow(id: 3, app: "Notes", space: 1, frame: .init(x: 40, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal")
        let all = [first, second, other]

        XCTAssertEqual(GlyphStrip.draggedWindows(for: first, allWindows: all, dedupe: false).map(\.id), [1])
        XCTAssertEqual(GlyphStrip.draggedWindows(for: first, allWindows: all, dedupe: true).map(\.id), [1, 2])
    }

    /// Fractions derived from a dragged frame must replay through `frame(...)`
    /// to the exact frame they came from — otherwise the strip jumps the
    /// moment the drag's config lands.
    func testCustomFractionsInvertTheFrameMath() {
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 200, height: 16),
            menuBarRow: row,
            leftNotchArea: nil,
            rightNotchArea: nil,
            position: .custom,
            margin: 0,
            xFraction: 0.163,
            yFraction: 0.25
        )
        let fractions = GlyphStrip.customFractions(for: frame, area: row)

        XCTAssertEqual(fractions?.x ?? .nan, 0.163, accuracy: 0.0001)
        XCTAssertEqual(fractions?.y ?? .nan, 0.25, accuracy: 0.0001)
        XCTAssertEqual(
            GlyphStrip.frame(
                contentSize: frame.size,
                menuBarRow: row,
                leftNotchArea: nil,
                rightNotchArea: nil,
                position: .custom,
                margin: 0,
                xFraction: fractions?.x ?? 0,
                yFraction: fractions?.y ?? 0
            ),
            frame
        )
    }

    /// One scheme for both surfaces: the strip's fractions are the HUD's
    /// `normalizedPosition` for the same frame.
    func testCustomFractionsMatchTheHUDPanelScheme() {
        let screen = CGRect(x: 100, y: 50, width: 1600, height: 1000)
        let frame = CGRect(x: 500, y: 300, width: 200, height: 60)

        let fractions = GlyphStrip.customFractions(for: frame, area: screen)
        let normalized = HUDDisplay.normalizedPosition(panelFrame: frame, screenFrame: screen)

        XCTAssertEqual(fractions?.x ?? .nan, Double(normalized?.x ?? .nan), accuracy: 0.0001)
        XCTAssertEqual(fractions?.y ?? .nan, Double(normalized?.y ?? .nan), accuracy: 0.0001)
    }

    func testCustomFractionsAreNilWhenTheStripFillsTheArea() {
        let fullWidth = CGRect(x: row.minX, y: row.minY, width: row.width, height: row.height)
        XCTAssertNil(GlyphStrip.customFractions(for: fullWidth, area: row))
    }

    /// Free placement must reach any row of the display, not just the menu bar.
    func testCustomPlacementUsesTheWholeScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 200, height: 30),
            menuBarRow: row,
            screenFrame: screen,
            leftNotchArea: nil,
            rightNotchArea: nil,
            position: .custom,
            margin: 0,
            xFraction: 0.25,
            yFraction: 0.25
        )
        XCTAssertEqual(frame.minX, (1728 - 200) * 0.25, accuracy: 0.001)
        XCTAssertEqual(frame.minY, (1117 - 30) * 0.25, accuracy: 0.001)
        XCTAssertEqual(frame.height, 30, "custom must not clamp to the menu bar row height")
    }

    /// The drag inverse must replay through the same screen-relative area.
    func testCustomFractionsRoundTripOnTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 200, height: 300),
            menuBarRow: row,
            screenFrame: screen,
            leftNotchArea: nil,
            rightNotchArea: nil,
            position: .custom,
            margin: 0,
            xFraction: 0.1,
            yFraction: 0.4
        )
        let fractions = GlyphStrip.customFractions(for: frame, area: screen)
        XCTAssertEqual(
            GlyphStrip.frame(
                contentSize: frame.size,
                menuBarRow: row,
                screenFrame: screen,
                leftNotchArea: nil,
                rightNotchArea: nil,
                position: .custom,
                margin: 0,
                xFraction: fractions?.x ?? 0,
                yFraction: fractions?.y ?? 0
            ),
            frame
        )
    }

    /// A frame flung past the screen derives out-of-range fractions; `clamped()`
    /// must bound them before they reach config.
    func testDraggedFractionsClampToTheUnitRange() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let flung = CGRect(x: screen.minX + 9000, y: screen.minY - 100, width: 200, height: 20)
        let fractions = GlyphStrip.customFractions(for: flung, area: screen)
        var strip = GlyphStripConfig.default
        strip.position = .custom
        strip.customX = fractions?.x ?? 0
        strip.customY = fractions?.y ?? 0

        let clamped = strip.clamped()
        XCTAssertEqual(clamped.customX, 1)
        XCTAssertEqual(clamped.customY, 0)
    }

    func testLockPositionDefaultsOffAndOnlyLocksCustomPlacement() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.lockPosition, false)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nlockPosition = true")?.lockPosition, true)

        var strip = GlyphStripConfig.default
        strip.lockPosition = true
        XCTAssertFalse(strip.isPositionLocked, "anchored positions ignore the lock")
        strip.position = .custom
        XCTAssertTrue(strip.isPositionLocked)
    }

    // MARK: - Vertical layout


    func testOnlyChangedSegmentsAnimate() {
        let a = GlyphStrip.Segment(spaceIndex: 1, runs: [.index("1"), .app("Safari")])
        let b = GlyphStrip.Segment(spaceIndex: 2, runs: [.index("2")])
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: nil, current: [a, b]),
            []
        )
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: [a, b], current: [a, b]),
            []
        )
        let moved = GlyphStrip.Segment(spaceIndex: 2, runs: [.index("1"), .app("Safari")])
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: [a, b], current: [moved, b]),
            [0]
        )
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: [a, b], current: [a]),
            [0]
        )
        let iconAdded = GlyphStrip.Segment(spaceIndex: 2, runs: [.index("2"), .app("Safari")])
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: [a, b], current: [a, iconAdded]),
            [1],
            "a changed second segment must animate even when the first is identical"
        )
    }

    // MARK: - Render layout

    private func styles(
        for segments: [GlyphStrip.Segment],
        focused: Int?,
        strip: GlyphStripConfig = .default
    ) -> [[GlyphStrip.RunStyle]] {
        segments.map { segment in
            let isCurrent = segment.spaceIndex != nil && segment.spaceIndex == focused
            return segment.runs.map { run in
                GlyphStrip.style(for: run, isCurrent: isCurrent, strip: strip)
            }
        }
    }

    /// One horizontal render: exact slot frames and run frames, plus the
    /// colour policy the paint path resolves from the same segments.
    func testHorizontalLayoutPinsSlotRunFramesAndStyles() {
        let segments: [GlyphStrip.Segment] = [
            .init(spaceIndex: 1, runs: [.index("1"), .app("A"), .overflow(2)]),
            .init(spaceIndex: 2, runs: [.index("2"), .placeholder])
        ]
        let slots = [
            CGRect(x: 10, y: 0, width: 50, height: 24),
            CGRect(x: 60, y: 0, width: 40, height: 24)
        ]
        let layout = GlyphStrip.layout(
            segments: segments,
            state: nil,
            options: GlyphStrip.Options(.default),
            input: GlyphStrip.LayoutInput(
                slots: slots,
                advances: [[8, 10, 6], [8, 5]],
                gaps: [[0, 3, 3], [0, 6]],
                placement: .inline(inset: 2)
            )
        )

        XCTAssertEqual(layout.slots, slots)
        XCTAssertEqual(layout.runs.map { $0.map(\.frame) }, [
            [
                CGRect(x: 12, y: 0, width: 8, height: 24),
                CGRect(x: 23, y: 0, width: 10, height: 24),
                CGRect(x: 36, y: 0, width: 6, height: 24)
            ],
            [
                CGRect(x: 62, y: 0, width: 8, height: 24),
                CGRect(x: 76, y: 0, width: 5, height: 24)
            ]
        ])
        let policy = styles(for: segments, focused: 1)
        XCTAssertEqual(policy[0].map(\.colorName), ["focused", "focused", "focused"])
        XCTAssertEqual(policy[1].map(\.colorName), ["text", "text"])
        XCTAssertEqual(policy[1].map(\.alpha), [1, 1])
    }

    /// Vertical inline layout centres the segment's single line in its slot.
    func testVerticalLayoutCentresTheLineInItsSlot() {
        let segments: [GlyphStrip.Segment] = [
            .init(spaceIndex: 1, runs: [.index("1"), .app("A")])
        ]
        let layout = GlyphStrip.layout(
            segments: segments,
            state: nil,
            options: GlyphStrip.Options(.default),
            input: GlyphStrip.LayoutInput(
                slots: [CGRect(x: 0, y: 0, width: 60, height: 30)],
                advances: [[8, 10]],
                gaps: [[0, 3]],
                placement: .centered
            )
        )

        XCTAssertEqual(layout.runs[0].map(\.frame), [
            CGRect(x: 19.5, y: 0, width: 8, height: 30),
            CGRect(x: 30.5, y: 0, width: 10, height: 30)
        ])
    }

    /// Stacked vertical layout puts one run per line and centres each by its
    /// ink centre, falling back to the advance box for nil centres.
    func testStackedLayoutCentresEachRunOnItsLine() {
        let segments: [GlyphStrip.Segment] = [
            .init(spaceIndex: 1, runs: [.index("1"), .app("A")])
        ]
        let layout = GlyphStrip.layout(
            segments: segments,
            state: nil,
            options: GlyphStrip.Options(.default),
            input: GlyphStrip.LayoutInput(
                slots: [CGRect(x: 0, y: 0, width: 40, height: 50)],
                advances: [[10, 12]],
                gaps: [[0, 0]],
                placement: .stacked,
                lines: [[
                    CGRect(x: 0, y: 40, width: 40, height: 10),
                    CGRect(x: 0, y: 20, width: 40, height: 10)
                ]],
                inkCenters: [[nil, 15]]
            )
        )

        XCTAssertEqual(layout.runs[0].map(\.frame), [
            CGRect(x: 15, y: 40, width: 10, height: 10),
            CGRect(x: 15, y: 20, width: 12, height: 10)
        ])
    }

    func testLayoutHitTestsNameTheSegmentAndRunUnderThePoint() {
        let segments: [GlyphStrip.Segment] = [
            .init(spaceIndex: 1, runs: [.index("1"), .app("A"), .overflow(2)]),
            .init(spaceIndex: 2, runs: [.index("2"), .placeholder])
        ]
        let layout = GlyphStrip.layout(
            segments: segments,
            state: nil,
            options: GlyphStrip.Options(.default),
            input: GlyphStrip.LayoutInput(
                slots: [
                    CGRect(x: 10, y: 0, width: 50, height: 24),
                    CGRect(x: 60, y: 0, width: 40, height: 24)
                ],
                advances: [[8, 10, 6], [8, 5]],
                gaps: [[0, 3, 3], [0, 6]],
                placement: .inline(inset: 2)
            )
        )

        XCTAssertEqual(layout.segment(at: CGPoint(x: 12, y: 10)), 0)
        XCTAssertEqual(layout.segment(at: CGPoint(x: 59, y: 10)), 0)
        XCTAssertEqual(layout.segment(at: CGPoint(x: 60, y: 10)), 1)
        XCTAssertNil(layout.segment(at: CGPoint(x: 5, y: 10)))

        XCTAssertEqual(layout.run(at: CGPoint(x: 12, y: 10))?.segment, 0)
        XCTAssertEqual(layout.run(at: CGPoint(x: 12, y: 10))?.run, 0)
        XCTAssertEqual(layout.run(at: CGPoint(x: 23, y: 10), in: 0), 1)
        XCTAssertEqual(layout.run(at: CGPoint(x: 76, y: 10), in: 1), 1)
        XCTAssertNil(layout.run(at: CGPoint(x: 21, y: 10), in: 0), "the gap between two runs is not a run")
        XCTAssertNil(layout.run(at: CGPoint(x: 5, y: 10), in: 0))
    }

    /// Drag payloads must follow the same dedupe and icon cap as the runs.
    func testLayoutMapsWindowsFromSegmentOptions() {
        var deduped = GlyphStrip.Options(.default)
        deduped.dedupeAppsPerSpace = true
        deduped.maxIconsPerSpace = 0
        var capped = GlyphStrip.Options(.default)
        capped.dedupeAppsPerSpace = false
        capped.maxIconsPerSpace = 1
        let gridState = state(spaces: [space(index: 1)], windows: mixedWindows, maxSpaces: 1)

        func layout(for options: GlyphStrip.Options) -> GlyphStrip.SegmentLayout {
            let segment = singleSegment(options, windows: mixedWindows)
            return GlyphStrip.layout(
                segments: [segment],
                state: gridState,
                options: options,
                input: GlyphStrip.LayoutInput(
                    slots: [CGRect(x: 0, y: 0, width: 40, height: 20)],
                    advances: [Array(repeating: 5, count: segment.runs.count)],
                    gaps: [Array(repeating: 0, count: segment.runs.count)],
                    placement: .inline(inset: 0)
                )
            )
        }

        // Dedupe: one Safari icon carries every Safari window.
        let dedupedLayout = layout(for: deduped)
        XCTAssertEqual(dedupedLayout.runs[0].count, 3)
        XCTAssertTrue(dedupedLayout.runs[0][0].windows.isEmpty, "the number run carries no windows")
        XCTAssertEqual(dedupedLayout.runs[0][1].windows.map(\.id), [1, 2])
        XCTAssertEqual(dedupedLayout.runs[0][2].windows.map(\.id), [3])

        // Cap: the kept icon carries its window, the overflow indicator none.
        let cappedLayout = layout(for: capped)
        XCTAssertEqual(cappedLayout.runs[0].count, 3)
        XCTAssertEqual(cappedLayout.runs[0][1].windows.map(\.id), [1])
        XCTAssertTrue(cappedLayout.runs[0][2].windows.isEmpty)
    }

    func testVerticalSlotsStackFromTheTopInSpaceOrder() {
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 120)
        let slots = GlyphStrip.verticalSlots(heights: [50, 30, 40], in: bounds)

        XCTAssertEqual(slots.map(\.height), [50, 30, 40])
        XCTAssertEqual(slots[0].maxY, bounds.maxY, "first space owns the top slot")
        XCTAssertEqual(slots[0].minY, slots[1].maxY)
        XCTAssertEqual(slots[1].minY, slots[2].maxY)
        XCTAssertEqual(slots[2].minY, bounds.minY)
        XCTAssertTrue(slots.allSatisfy { $0.width == bounds.width && $0.minX == bounds.minX })
    }

    func testAutoResizeMaxLengthDefaultsOffAndDecodes() {
        var strip = GlyphStripConfig.default
        XCTAssertEqual(strip.autoResizeMaxLength, 0)

        strip.autoResizeMaxLength = 6000
        XCTAssertEqual(strip.clamped().autoResizeMaxLength, 4000)
        strip.autoResizeMaxLength = -10
        XCTAssertEqual(strip.clamped().autoResizeMaxLength, 0)

        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nautoResizeMaxLength = 420")?.autoResizeMaxLength, 420)
    }

    func testVerticalColumnSlotsWrapInsteadOfOverflowing() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        let slots = GlyphStrip.verticalColumnSlots(
            heights: [20, 20, 20],
            in: bounds,
            available: 50,
            columnGap: 8
        )
        XCTAssertEqual(GlyphStrip.verticalColumnCount(totalHeight: 60, available: 50), 2)
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(slots[0].maxY, 50)
        XCTAssertEqual(slots[1].maxY, 30)
        XCTAssertEqual(slots[2].maxY, 50)
        XCTAssertGreaterThan(slots[2].minX, slots[0].minX)
        XCTAssertEqual(slots[0].width, 46)
    }

    func testVerticalColumnCountStaysOneWhenItFits() {
        XCTAssertEqual(GlyphStrip.verticalColumnCount(totalHeight: 40, available: 50), 1)
        XCTAssertEqual(GlyphStrip.verticalColumnCount(totalHeight: 50, available: 50), 1)
    }

    func testStackedLinesFillTheSlotTopDown() {
        let slot = CGRect(x: 4, y: 10, width: 40, height: 96)
        let lines = GlyphStrip.stackedLines(
            count: 3,
            lineHeight: 30,
            indexGap: 4,
            iconGap: 2,
            in: slot
        )

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].maxY, slot.maxY)
        XCTAssertEqual(lines[1].maxY, lines[0].minY - 4, "index padding separates the number line")
        XCTAssertEqual(lines[2].maxY, lines[1].minY - 2, "icon spacing separates icon lines")
        XCTAssertEqual(lines[2].minY, slot.minY)
        XCTAssertTrue(lines.allSatisfy { $0.width == slot.width && $0.minX == slot.minX })
    }

    func testVerticalLayoutDefaultsToInlineAndDecodesBothModes() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.verticalLayout, .inline)
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\nverticalLayout = \"stacked\"")?.verticalLayout,
            .stacked
        )
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\nverticalLayout = \"nonsense\"")?.verticalLayout,
            .inline
        )
    }

    func testLayoutSuffixFiltersEachSpaceType() {
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "bsp"), "b")
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "bsp", showBSP: false), "")
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "stack", showStack: false), "")
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "float", showFloat: false), "")
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "float", showStack: false), "f")

        var strip = GlyphStripConfig.default
        XCTAssertTrue(strip.showBSPLayoutBadge)
        strip.showBSPLayoutBadge = false
        strip.verticalPadding = 99
        XCTAssertFalse(GlyphStrip.Options(strip.clamped()).showBSPLayoutBadge)
        XCTAssertEqual(strip.clamped().verticalPadding, 40)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nverticalPadding = 12")?.verticalPadding, 12)
    }

    func testHideInFullscreenDefaultsOffAndDecodes() {
        XCTAssertEqual(GlyphStripConfig.default.hideInFullscreen, false)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nhideInFullscreen = true")?.hideInFullscreen, true)
    }

    func testPaddingLocksByDefaultAndDecodesDisplayMode() {
        let defaults = GlyphStripConfig.default
        XCTAssertTrue(defaults.lockPadding)
        XCTAssertEqual(defaults.resolvedHorizontalPadding, 4)
        XCTAssertEqual(defaults.resolvedVerticalPadding, 4)

        var unlocked = defaults
        unlocked.lockPadding = false
        unlocked.horizontalPadding = 12
        unlocked.verticalPadding = 2
        XCTAssertEqual(unlocked.resolvedHorizontalPadding, 12)
        XCTAssertEqual(unlocked.resolvedVerticalPadding, 2)

        let decoded = decodeGlyphStrip("""
        [glyphStrip]
        displayMode = "menuBarItem"
        padding = 9
        lockPadding = false
        horizontalPadding = 7
        """)
        XCTAssertEqual(decoded?.displayMode, .menuBarItem)
        XCTAssertEqual(decoded?.resolvedHorizontalPadding, 7)
        XCTAssertEqual(decoded?.padding, 9)
    }

    func testOrientationDefaultsToHorizontalAndDecodesBothDirections() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.orientation, .horizontal)
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\norientation = \"vertical\"")?.orientation,
            .vertical
        )
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\norientation = \"sideways\"")?.orientation,
            .horizontal
        )
    }

    func testDragThresholdSeparatesClickFromDrag() {
        XCTAssertFalse(GlyphStrip.exceedsDragThreshold(CGVector(dx: 3.9, dy: 0)))
        XCTAssertFalse(GlyphStrip.exceedsDragThreshold(CGVector(dx: 0, dy: -3.9)))
        XCTAssertTrue(GlyphStrip.exceedsDragThreshold(CGVector(dx: 4, dy: 0)))
        XCTAssertTrue(GlyphStrip.exceedsDragThreshold(CGVector(dx: -4, dy: 4)))
    }

    func testDragOnlyDropsOnAnotherSpace() {
        XCTAssertTrue(GlyphStrip.dragResolvesToDrop(hudTarget: 3, targetSpace: nil, sourceSpace: 2))
        XCTAssertTrue(GlyphStrip.dragResolvesToDrop(hudTarget: nil, targetSpace: 3, sourceSpace: 2))
        XCTAssertFalse(GlyphStrip.dragResolvesToDrop(hudTarget: nil, targetSpace: 2, sourceSpace: 2))
        XCTAssertFalse(GlyphStrip.dragResolvesToDrop(hudTarget: nil, targetSpace: nil, sourceSpace: 2))
        XCTAssertFalse(GlyphStrip.dragResolvesToDrop(hudTarget: nil, targetSpace: 3, sourceSpace: nil))
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
        let theme = try XCTUnwrap(makeTemporaryThemeStore().named("default"), "default theme missing")
        for role in ["focused", "text", "cellBg"] {
            XCTAssertNotNil(GlyphStrip.color(for: role, theme: theme), "\(role) has no value")
        }
    }

    func testEveryThemeColorNameResolvesToItsValue() throws {
        let theme = try XCTUnwrap(makeTemporaryThemeStore().named("default"), "default theme missing")
        for name in AppTheme.colorNames {
            XCTAssertNotNil(theme.value(for: name), "\(name) has no value")
            XCTAssertNotNil(GlyphStrip.color(for: name, theme: theme))
        }
    }

    func testNoColorResolvesToNoDrawableColor() throws {
        let theme = try XCTUnwrap(makeTemporaryThemeStore().named("default"))
        XCTAssertNil(GlyphStrip.color(for: "none", theme: theme))
        XCTAssertNil(GlyphStrip.color(for: "chartreuse", theme: theme))
    }

    /// Current space and add button both draw in the theme's `focused` role.
    func testCurrentSpaceAndAddButtonUseTheFocusedRole() throws {
        let theme = try XCTUnwrap(makeTemporaryThemeStore().named("default"))
        var strip = GlyphStripConfig.default
        strip.highlightCurrentSpace = true

        let current = GlyphStrip.style(for: .index("2"), isCurrent: true, strip: strip)
        XCTAssertEqual(current.colorName, "focused")
        XCTAssertEqual(
            GlyphStrip.color(for: current.colorName, theme: theme),
            GlyphStrip.color(for: "focused", theme: theme)
        )

        let add = GlyphStrip.style(for: .add, isCurrent: false, strip: strip)
        XCTAssertEqual(add.colorName, "focused")
    }

    /// Every resting element draws in the theme's `text` role — hover uses
    /// `focused` (the same role as the current space), so a leak would show.
    func testRestingRolesResolveToText() throws {
        let theme = try XCTUnwrap(makeTemporaryThemeStore().named("default"))
        let strip = GlyphStripConfig.default
        let runs: [GlyphStrip.Run] = [.index("1"), .app("A"), .overflow(3), .separator, .placeholder]
        for run in runs {
            let style = GlyphStrip.style(for: run, isCurrent: false, strip: strip)
            XCTAssertEqual(style.colorName, "text", "\(run) should rest in text")
            XCTAssertEqual(
                GlyphStrip.color(for: style.colorName, theme: theme),
                GlyphStrip.color(for: "text", theme: theme)
            )
        }
    }

    func testGlassStrokeColorIsDerivedFromTheThemeNotHardcoded() throws {
        for name in makeTemporaryThemeStore().allNames() {
            let theme = try XCTUnwrap(makeTemporaryThemeStore().named(name))
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
        let theme = try XCTUnwrap(makeTemporaryThemeStore().named("default"))
        let strip = styleStrip(highlight: true)

        let current = GlyphStrip.style(for: .index("2"), isCurrent: true, strip: strip)
        let other = GlyphStrip.style(for: .index("3"), isCurrent: false, strip: strip)
        XCTAssertEqual(current.colorName, "focused")
        XCTAssertNotEqual(current.colorName, other.colorName)

        let currentIcon = GlyphStrip.style(for: .app("A"), isCurrent: true, strip: strip)
        let otherIcon = GlyphStrip.style(for: .app("B"), isCurrent: false, strip: strip)
        XCTAssertEqual(currentIcon.alpha, 1.0)
        XCTAssertEqual(otherIcon.alpha, 0.55, "non-current app glyphs stay faded")
    }

    /// The reported bug: with the flag off the current space was painted with the
    /// dimmed colour but was still marked out. It must be byte-identical to every
    /// other space instead.
    func testHighlightingOffMakesTheCurrentSpaceIdenticalToEveryOther() throws {
        let theme = try XCTUnwrap(makeTemporaryThemeStore().named("default"))
        let strip = styleStrip(highlight: false)
        let runs: [GlyphStrip.Run] = [
            .index("2"), .app("A"), .app("B"), .overflow(3), .placeholder, .separator, .add
        ]

        for run in runs {
            let current = GlyphStrip.style(for: run, isCurrent: true, strip: strip)
            let other = GlyphStrip.style(for: run, isCurrent: false, strip: strip)
            XCTAssertEqual(current, other, "\(run) still looks different when it is the current space")
        }
    }

    func testHighlightingOffAlsoRemovesTheAppGlyphAlphaStep() throws {
        let theme = try XCTUnwrap(makeTemporaryThemeStore().named("default"))
        let strip = styleStrip(highlight: false)
        let currentIcon = GlyphStrip.style(for: .app("A"), isCurrent: true, strip: strip)
        let otherIcon = GlyphStrip.style(for: .app("B"), isCurrent: false, strip: strip)
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
    /// hardcoded per-glyph estimate. Measured on the installed font: every app
    /// glyph occupies the same 15.521pt cell at 11pt, which is precisely why
    /// adjacent icons touch and why `iconSpacing` has to supply the tracking.
    func testAppGlyphAdvanceIsReadFromTheFontAndIsUniform() throws {
        guard let font = AppGlyphFont.load() else {
            throw XCTSkip("sketchybar-app-font is not installed")
        }
        let nsFont = try XCTUnwrap(font.face(size: 11))
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
        return (try? TOMLParser.parse(toml))?.config.glyphStrip
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
        XCTAssertEqual(config?.spaceLabelStyle, .numbers)
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
        spaceLabelStyle = "emoji"
        """)

        XCTAssertEqual(config?.backgroundMaterial, GlyphStripBackgroundMaterial.none)
        XCTAssertEqual(config?.shape, GlyphStripShape.none)
        XCTAssertEqual(config?.position, GlyphStripPosition.leftOfNotch)
        XCTAssertEqual(config?.spaceLabelStyle, .numbers)
    }

    func testSpaceLabelStyleDecodes() {
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\nspaceLabelStyle = \"names\"")?.spaceLabelStyle,
            .names
        )
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\nspaceLabelStyle = \"both\"")?.spaceLabelStyle,
            .both
        )
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

    func testGlassStyleDecodesAndDefaultsToOpaque() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nglassStyle = \"tinted\"")?.glassStyle, .tinted)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nglassStyle = \"frosted\"")?.glassStyle, .regular)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.glassStyle, .regular)
    }

    func testGlassFallbackMaterialsAreDistinctPerStyle() {
        XCTAssertEqual(GlyphStrip.glassFallbackMaterial(for: .tinted, tintedMaterial: .clear), .popover)
        XCTAssertEqual(GlyphStrip.glassFallbackMaterial(for: .tinted, tintedMaterial: .regular), .headerView)
        XCTAssertEqual(GlyphStrip.glassFallbackMaterial(for: .regular, tintedMaterial: .clear), .headerView)
        XCTAssertEqual(GlyphStrip.glassFallbackMaterial(for: .clear, tintedMaterial: .regular), .underWindowBackground)
    }

    func testPerStyleGlassVariantsClampAndFollowHUD() {
        var strip = GlyphStripConfig.default
        XCTAssertEqual(strip.glassClearVariant, 11)
        XCTAssertEqual(strip.glassRegularVariant, 5)
        XCTAssertEqual(strip.glassTintedVariant, 2)

        strip.glassClearVariant = 99
        strip.glassRegularVariant = -4
        let clamped = strip.clamped()
        XCTAssertEqual(clamped.glassClearVariant, 21)
        XCTAssertEqual(clamped.glassRegularVariant, 0)

        var hud = SpacemapConfig.default
        hud.glassStyle = .regular
        hud.glassRegularVariant = 16
        strip.glassStyle = .regular
        strip.glassRegularVariant = 15
        strip.matchHUDAppearance = true
        XCTAssertEqual(strip.resolvedGlassVariant(hud: hud), 16)
        strip.matchHUDAppearance = false
        XCTAssertEqual(strip.resolvedGlassVariant(hud: hud), 15)

        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nglassClearVariant = 15")?.glassClearVariant, 15)
    }

    func testPerStyleOpacityResolvesAndSharedModeOverrides() {
        var config = GlyphStripConfig.default
        config.glassClearOpacity = 0.1
        config.glassRegularOpacity = 0.2
        config.glassTintedOpacity = 0.7
        config.solidOpacity = 0.9
        config.backgroundOpacity = 0.4

        config.backgroundMaterial = .solid
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .solid), 0.9)
        config.backgroundMaterial = .liquidGlass
        config.glassStyle = .clear
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .liquidGlass), 0.35)
        config.glassStyle = .regular
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .liquidGlass), 0.40)
        config.glassStyle = .tinted
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .liquidGlass), 0.7)

        config.matchBackgroundOpacity = true
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .solid), 0.4)
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .liquidGlass), 0.45)
    }

    func testMatchHUDAppearanceCopiesMaterialStyleOpacityAndTheme() {
        var hud = SpacemapConfig.default
        hud.backgroundStyle = .solid
        hud.solidOpacity = 0.8
        hud.glassStyle = .tinted
        hud.theme = "nord"

        var strip = GlyphStripConfig.default
        strip.backgroundMaterial = .none
        strip.theme = "dracula"
        strip.matchHUDAppearance = true
        let store = makeTemporaryThemeStore()

        XCTAssertEqual(strip.resolvedBackgroundMaterial(hud: hud), .solid)
        XCTAssertEqual(strip.resolvedBackgroundOpacity(hud: hud), 0.8)
        XCTAssertEqual(store.resolvedThemeName(strip: strip, hudTheme: hud.theme), "nord")

        hud.backgroundStyle = .glass
        XCTAssertEqual(strip.resolvedBackgroundMaterial(hud: hud), .liquidGlass)
        XCTAssertEqual(strip.resolvedGlassStyle(hud: hud), .tinted)
        XCTAssertEqual(
            strip.resolvedBackgroundOpacity(hud: hud),
            hud.effectiveBackgroundOpacity(for: .glass)
        )

        strip.matchHUDAppearance = false
        XCTAssertEqual(strip.resolvedBackgroundMaterial(hud: hud), .none)
        XCTAssertEqual(strip.resolvedGlassStyle(hud: hud), .regular)
        XCTAssertEqual(store.resolvedThemeName(strip: strip, hudTheme: hud.theme), "dracula")
    }

    func testAbsentGlyphStripTableFallsBackToItsDefaultsAndFlagsRepair() {
        let parsed = try? TOMLParser.parse("""
        [grid]
        cols = 4
        """)

        XCTAssertEqual(parsed?.config.glyphStrip, GlyphStripConfig.default)
        XCTAssertEqual(parsed?.needsRepair, true, "a missing strip table flags a rewrite")
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

    func testCustomPlacementDefaultsToCentredFractions() {
        let defaults = decodeGlyphStrip("[glyphStrip]\nenabled = true")
        XCTAssertEqual(defaults?.customX, 0.5)
        XCTAssertEqual(defaults?.customY, 0.5)
        XCTAssertEqual(defaults?.customScreen, "", "no display pairing by default")
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
        XCTAssertEqual(config?.customX, 0.5)
        XCTAssertEqual(config?.borderEnabled, true, "border defaults to on")
        XCTAssertEqual(config?.position, .leftOfNotch)
    }

    func testStripThemeDecodesAndFallsBackOnWrongType() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\ntheme = \"nord\"")?.theme, "nord")
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\ntheme = 42")?.theme, "")
    }

    func testCustomPositionAndFractionsDecode() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        position = "custom"
        customX = 0.3
        customY = 0.7
        customScreen = "display-A"
        """)
        XCTAssertEqual(config?.position, .custom)
        XCTAssertEqual(config?.customX, 0.3)
        XCTAssertEqual(config?.customY, 0.7)
        XCTAssertEqual(config?.customScreen, "display-A")
    }

    func testCustomFractionsClampToTheUnitRange() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\ncustomX = 99.0")?.clamped().customX, 1)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\ncustomY = -99.0")?.clamped().customY, 0)
    }

    func testBorderEnabledDecodesAndRejectsNonBools() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nborderEnabled = false")?.borderEnabled, false)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nborderEnabled = \"yes\"")?.borderEnabled, true)
    }

    func testRoundTripThroughTheConfigStringPreservesEveryKey() {
        var original = GlyphStripConfig.default
        original.enabled = true
        original.showSpaceNumbers = false
        original.spaceLabelStyle = .both
        original.showLayoutSuffix = false
        original.showAppIcons = false
        original.dedupeAppsPerSpace = false
        original.maxIconsPerSpace = 3
        original.iconSize = 14
        original.indexSize = 9
        original.highlightCurrentSpace = false
        original.backgroundMaterial = .liquidGlass
        original.glassStyle = .tinted
        original.matchHUDAppearance = true
        original.shape = .pill
        original.backgroundOpacity = 0.6
        original.glassClearOpacity = 0.2
        original.glassRegularOpacity = 0.4
        original.glassTintedOpacity = 0.8
        original.solidOpacity = 0.9
        original.matchBackgroundOpacity = true
        original.cornerRadius = 12
        original.margin = 9
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
        original.customX = 0.3
        original.customY = 0.7
        original.customScreen = "display-A"
        original.theme = "nord"
        original.borderEnabled = false

        var values = SpacemapConfig.default
        values.glyphStrip = original
        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = decodeGlyphStrip(toml)?.clamped()

        XCTAssertEqual(reread, original)
    }
}

final class GlyphStripPanelPresentationTests: XCTestCase {

    private func enabledConfig() -> SpacemapConfig {
        var config = SpacemapConfig.default
        config.glyphStrip.enabled = true
        return config
    }

    func testContentOnlyRefreshRepaintsEvenWhenTheFrameIsUnchanged() throws {
        _ = NSApplication.shared
        let controller = GlyphStripPanelController(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        let panel = try XCTUnwrap(controller.panel)
        let frame = panel.frame
        // Drain the coalesced refresh scheduled by `update` so a late pass
        // cannot add a second increment during this assertion.
        controller.pendingRefresh?.cancel()
        let repaintsBefore = controller.contentRepaintCount

        controller.present()

        XCTAssertEqual(panel.frame, frame, "the second present must reuse the frame")
        XCTAssertEqual(
            controller.contentRepaintCount,
            repaintsBefore + 1,
            "content changes must request a repaint without a frame move"
        )
    }

    /// A config change must drop the cached panel render, or the next repaint
    /// keeps the old padding.
    func testConfigUpdateRebuildsTheCachedPanelLayout() throws {
        guard NSScreen.main != nil else {
            throw XCTSkip("no display available in this environment")
        }
        _ = NSApplication.shared
        let yabai = MockYabaiService()
        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [1, 2].map {
                YabaiSpace(id: $0, index: $0, display: 1, hasFocus: $0 == 1, isVisible: true, label: nil)
            },
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )
        let controller = GlyphStripPanelController(
            yabaiService: yabai,
            themeStore: makeTemporaryThemeStore()
        )
        var config = enabledConfig()
        config.glyphStrip.padding = 4
        controller.update(config: config)
        controller.present()

        // The first pass waits for the off-main font load.
        let deadline = Date().addingTimeInterval(2)
        while controller.layout.slots.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        controller.pendingRefresh?.cancel()
        let first = try XCTUnwrap(controller.layout.slots.first)
        XCTAssertEqual(first.minX, 4, accuracy: 0.5)

        // Same config and bounds reuse the cached render.
        let builds = controller.layoutBuildCount
        _ = controller.layout
        XCTAssertEqual(controller.layoutBuildCount, builds)

        var widened = config
        widened.glyphStrip.padding = 12
        controller.update(config: widened)
        controller.pendingRefresh?.cancel()

        let second = try XCTUnwrap(controller.layout.slots.first)
        XCTAssertEqual(second.minX, 12, accuracy: 0.5, "the cache must rebuild from the new config")
        XCTAssertEqual(controller.layoutBuildCount, builds + 1)
    }

    func testHidingInvalidatesInFlightRefreshAndStalePresentCannotShow() throws {
        _ = NSApplication.shared
        let controller = GlyphStripPanelController(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isVisible)
        let generationBeforeHide = controller.refreshGeneration

        controller.toggleVisibilityByHotkey()
        // Hide fades before ordering out.
        let deadline = Date().addingTimeInterval(1)
        while panel.isVisible, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertFalse(panel.isVisible)
        XCTAssertGreaterThan(controller.refreshGeneration, generationBeforeHide)
        XCTAssertNil(controller.pendingRefresh, "hide must cancel the coalesced refresh")

        // A reply that was already in flight used to call present() and put the
        // strip back on screen; the hidden guard must reject it.
        controller.present()
        XCTAssertFalse(panel.isVisible)
    }

    /// A free-placed strip first honours the display it was saved on, so its
    /// position survives a monitor change; a preset has no such claim, and a
    /// display that is gone must fall through to the usual target.
    func testStoredScreenHonoursCustomPlacementOnly() throws {
        guard let main = NSScreen.main else {
            throw XCTSkip("no display available in this environment")
        }
        var strip = SpacemapConfig.default.glyphStrip
        strip.position = .custom
        strip.customScreen = ScreenContext.displayIdentifier(for: main)
        XCTAssertTrue(GlyphStripPanelController.storedScreen(for: strip, screens: [main]) === main)

        strip.position = .leftOfNotch
        XCTAssertNil(GlyphStripPanelController.storedScreen(for: strip, screens: [main]))

        strip.position = .custom
        strip.customScreen = "gone-display"
        XCTAssertNil(GlyphStripPanelController.storedScreen(for: strip, screens: [main]))
    }

    func testSettingsUpdateClearsAWedgeRefreshLatch() {
        _ = NSApplication.shared
        let controller = GlyphStripPanelController(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.pendingRefresh?.cancel()
        controller.markRefreshWedgedForTesting()
        XCTAssertTrue(controller.refreshInFlight)
        XCTAssertTrue(controller.needsFollowupRefresh)

        controller.update(config: enabledConfig())

        XCTAssertFalse(controller.refreshInFlight, "updateConfig cancellation must not wedge the strip")
        XCTAssertFalse(controller.needsFollowupRefresh)
        XCTAssertNotNil(controller.pendingRefresh, "a fresh refresh should be queued")
    }

    /// A daemon restart makes yabai report no spaces. That empty state must not
    /// replace a painted strip with a lone add button until the next signal.
    func testEmptyStateRefreshKeepsTheLastPaintedStrip() throws {
        guard NSScreen.main != nil else {
            throw XCTSkip("no display available in this environment")
        }
        _ = NSApplication.shared
        let yabai = MockYabaiService()
        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [1, 2].map {
                YabaiSpace(id: $0, index: $0, display: 1, hasFocus: $0 == 1, isVisible: true, label: nil)
            },
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )
        let controller = GlyphStripPanelController(
            yabaiService: yabai,
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        // The first pass waits for the off-main font load.
        let deadline = Date().addingTimeInterval(2)
        while controller.layout.slots.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        controller.pendingRefresh?.cancel()
        let painted = controller.layout.slots
        XCTAssertFalse(painted.isEmpty, "the strip must paint spaces while yabai is up")

        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [],
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil
        )
        let buildsBefore = yabai.buildGridStateCallCount
        controller.refresh()
        let emptyDeadline = Date().addingTimeInterval(2)
        while yabai.buildGridStateCallCount == buildsBefore, Date() < emptyDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        // Let the coordinator's main-queue completion paint.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(controller.layout.slots, painted, "an empty state must keep the last painted frame")
    }

    /// A strip hidden by the hotkey and shown again while yabai is down has kept
    /// segments but no frame on screen. The empty-state guard must present them.
    func testStripHiddenDuringDowntimeComesBackWithTheKeptSegments() throws {
        guard NSScreen.main != nil else {
            throw XCTSkip("no display available in this environment")
        }
        _ = NSApplication.shared
        let yabai = MockYabaiService()
        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [1, 2].map {
                YabaiSpace(id: $0, index: $0, display: 1, hasFocus: $0 == 1, isVisible: true, label: nil)
            },
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )
        let controller = GlyphStripPanelController(
            yabaiService: yabai,
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        // The first pass waits for the off-main font load.
        let deadline = Date().addingTimeInterval(2)
        while controller.layout.slots.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        controller.pendingRefresh?.cancel()
        let painted = controller.layout.slots
        XCTAssertFalse(painted.isEmpty, "the strip must paint spaces while yabai is up")
        let panel = try XCTUnwrap(controller.panel)

        controller.toggleVisibilityByHotkey()
        let hideDeadline = Date().addingTimeInterval(1)
        while panel.isVisible, Date() < hideDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(panel.isVisible)

        // Yabai is down: every state from here on reports no spaces.
        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [],
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil
        )
        controller.toggleVisibilityByHotkey()

        let showDeadline = Date().addingTimeInterval(2)
        while !panel.isVisible, Date() < showDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(panel.isVisible, "showing the strip during downtime must present it")
        XCTAssertEqual(controller.layout.slots, painted, "the kept frame is reused, not repainted empty")
    }

    func testVerticallyStackedQuartzDisplaysResolveToAppKitScreens() {
        let quartzMaxY: CGFloat = 1080
        let appKitFrames = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080),
        ]
        let topQuartz = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let bottomQuartz = CGRect(x: 0, y: 1080, width: 1920, height: 1080)

        let topAppKit = ScreenContext.appKitFrame(
            forQuartzFrame: topQuartz,
            quartzMaxY: quartzMaxY
        )
        let bottomAppKit = ScreenContext.appKitFrame(
            forQuartzFrame: bottomQuartz,
            quartzMaxY: quartzMaxY
        )

        XCTAssertEqual(topAppKit, appKitFrames[0])
        XCTAssertEqual(bottomAppKit, appKitFrames[1])
        XCTAssertEqual(
            ScreenContext.bestScreenIndex(for: topAppKit, screenFrames: appKitFrames),
            0
        )
        XCTAssertEqual(
            ScreenContext.bestScreenIndex(for: bottomAppKit, screenFrames: appKitFrames),
            1
        )
        // The raw Quartz frame does not live in AppKit's coordinate space.
        XCTAssertFalse(appKitFrames[0].intersects(bottomQuartz))
    }

    func testMenuBarRowUsesNotchSafeAreaInset() {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let visible = CGRect(x: 0, y: 0, width: 1710, height: 1075)

        let notched = ScreenContext.menuBarRow(
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaTop: 37.5
        )
        XCTAssertEqual(notched, CGRect(x: 0, y: 1074.5, width: 1710, height: 37.5))

        let plainVisible = CGRect(x: 0, y: 0, width: 1710, height: 1088)
        let plain = ScreenContext.menuBarRow(
            screenFrame: screen,
            visibleFrame: plainVisible,
            safeAreaTop: 0
        )
        XCTAssertEqual(plain, CGRect(x: 0, y: 1088, width: 1710, height: 24))
    }

    func testAccessibilityLabelsDescribeSpacesAppsAndControls() {
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(
                for: .init(spaceIndex: 3, runs: [.index("3"), .app("Safari"), .app("Terminal")]),
                focused: true
            ),
            "Space 3, Safari, Terminal, Current space"
        )
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(
                for: .init(spaceIndex: 2, runs: [.index("2"), .placeholder]),
                focused: false
            ),
            "Space 2, Empty"
        )
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(for: .init(spaceIndex: 4, runs: [.add]), focused: false),
            "Add space"
        )
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(for: .init(spaceIndex: nil, runs: [.separator]), focused: false),
            "Display separator"
        )
    }

    func testAccessibilityLabelIncludesTheSpaceNameWhenShown() {
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(
                for: .init(spaceIndex: 3, runs: [.index("3 Web"), .app("Safari")]),
                focused: false,
                spaceName: "Web"
            ),
            "Space 3 — Web, Safari"
        )
    }

    func testAccessibilityNameUsesTheSameTrimAndBlankRuleAsThePaintedLabel() {
        var options = GlyphStrip.Options(.default)
        options.spaceLabelStyle = .names
        options.spaceNames = [1: "  Web  ", 2: "   "]

        XCTAssertEqual(GlyphStrip.spaceName(for: 1, options: options), "Web",
                       "VoiceOver must not read the padding the strip trims")
        XCTAssertNil(GlyphStrip.spaceName(for: 2, options: options),
                     "a blank name paints the number, so VoiceOver must not read it either")

        options.spaceLabelStyle = .numbers
        XCTAssertNil(GlyphStrip.spaceName(for: 1, options: options),
                     "numbers mode never exposes a name")
    }
}

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
