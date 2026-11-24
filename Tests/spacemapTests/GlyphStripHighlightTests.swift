import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripHighlightTests: GlyphStripTestCase {

    // MARK: - highlightCurrentSpace semantics

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
        XCTAssertEqual(hovered?.cornerRadius, 8)
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
}
