import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripLabelTests: GlyphStripTestCase {

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
}
