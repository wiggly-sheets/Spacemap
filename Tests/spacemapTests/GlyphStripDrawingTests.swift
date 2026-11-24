import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripDrawingTests: GlyphStripTestCase {

    // MARK: - Background shapes

    func testCornerRadiusCarriesTheShapeIncludingPillAndSquareEnds() {
        let rounded = GlyphStrip.backdrop(bounds: stripBounds, cornerRadius: 6)
        XCTAssertEqual(rounded.cornerRadius, 6)
        XCTAssertEqual(rounded.rect, stripBounds.insetBy(dx: 0, dy: GlyphStrip.backdropVerticalInset))
        XCTAssertEqual(rounded.rect.width, stripBounds.width)
        XCTAssertEqual(rounded.rect.height, insetHeight)

        XCTAssertEqual(GlyphStrip.backdrop(bounds: stripBounds, cornerRadius: 0).cornerRadius, 0)

        // A radius at half the height or more is a pill, never a bulge.
        XCTAssertEqual(GlyphStrip.backdrop(bounds: stripBounds, cornerRadius: 400).cornerRadius, insetHeight / 2)
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

    /// Hover keeps its own radius, independent of the background radius.
    func testHoverFillKeepsItsOwnCornerRadius() {
        let segment = CGRect(x: 20, y: 0, width: 60, height: 30)
        XCTAssertEqual(
            GlyphStrip.hoverFill(segmentRect: segment, runHeight: 20, padding: 2, cornerRadius: 8)?.cornerRadius,
            8
        )
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
}
