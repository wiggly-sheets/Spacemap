import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripSpacingTests: GlyphStripTestCase {

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
}
