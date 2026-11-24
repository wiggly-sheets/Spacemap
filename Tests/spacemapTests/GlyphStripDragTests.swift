import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripDragTests: GlyphStripTestCase {

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
        XCTAssertFalse(
            strip.isPositionLocked(hasNotch: true),
            "anchored positions ignore the lock"
        )
        XCTAssertFalse(
            strip.isPositionLocked(hasNotch: false),
            "the plain default is centred, so the lock has nothing to hold"
        )
        strip.position = .custom
        XCTAssertTrue(strip.isPositionLocked(hasNotch: true))
        strip.position = .leftOfNotch
        strip.plainPosition = .custom
        XCTAssertTrue(
            strip.isPositionLocked(hasNotch: false),
            "a free-placed plain strip locks independently of the notch placement"
        )
    }

    func testCustomStripRaisesToMenuBarLevelOnlyInsideTheRow() {
        let row = CGRect(x: 0, y: 1085, width: 1728, height: 32)
        let inside = CGRect(x: 200, y: 1085, width: 100, height: 32)
        let below = CGRect(x: 200, y: 900, width: 100, height: 32)

        XCTAssertTrue(
            GlyphStrip.usesMenuBarLevel(position: .leftOfNotch, frame: below, menuBarRow: row),
            "anchored placements always sit above the menu bar"
        )
        XCTAssertTrue(
            GlyphStrip.usesMenuBarLevel(position: .custom, frame: inside, menuBarRow: row),
            "a custom strip in the row must stay clickable above the menu bar"
        )
        XCTAssertFalse(
            GlyphStrip.usesMenuBarLevel(position: .custom, frame: below, menuBarRow: row),
            "a free strip below the row stays below the menu bar"
        )
    }

    func testNotchAndPlainPlacementsResolveIndependently() {
        var strip = GlyphStripConfig.default
        strip.position = .rightOfNotch
        strip.margin = 12
        strip.plainPosition = .leftOfNotch
        strip.plainMargin = 3

        let notched = strip.placement(hasNotch: true)
        XCTAssertEqual(notched.position, .rightOfNotch)
        XCTAssertEqual(notched.margin, 12)

        let plain = strip.placement(hasNotch: false)
        XCTAssertEqual(plain.position, .leftOfNotch)
        XCTAssertEqual(plain.margin, 3)
    }
}
