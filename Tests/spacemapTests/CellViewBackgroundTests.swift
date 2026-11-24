import XCTest
import CoreGraphics
import SwiftUI
@testable import spacemap

final class CellViewBackgroundTests: CellViewGridViewTestCase {
    func testSpacesGlassKeysBuildTheGlassAppearance() {
        var config = SpacemapConfig.default
        config.spacesMatchBackground = false
        config.spacesBackgroundStyle = .glass
        config.spacesGlassStyle = .regular
        config.spacesGlassRegularVariant = 7
        config.spacesOpacity = 0.8
        config.spacesCornerRadius = 12

        XCTAssertEqual(
            CellSpaceBackground.from(config: config, resolvedTheme: .default),
            .glass(SpaceGlassAppearance(
                material: .regular,
                variant: 7,
                tint: nil,
                opacity: 0.8,
                cornerRadius: 12
            ))
        )
    }

    func testTintedSpacesGlassCarriesTheFocusedTint() {
        var config = SpacemapConfig.default
        config.spacesMatchBackground = false
        config.spacesBackgroundStyle = .glass
        config.spacesGlassStyle = .tinted
        config.spacesGlassTintedMaterial = .regular
        config.spacesGlassTintedVariant = 9
        config.spacesOpacity = 0.6
        config.spacesCornerRadius = 8

        let background = CellSpaceBackground.from(config: config, resolvedTheme: .default)

        XCTAssertEqual(
            background,
            .glass(SpaceGlassAppearance(
                material: .regular,
                variant: 9,
                tint: NSColor(srgbRed: 0, green: 0x7A / 255, blue: 1, alpha: 1),
                opacity: 0.6,
                cornerRadius: 8
            ))
        )
    }

    func testSolidSpacesBackgroundUsesTheThemeCellColour() {
        var config = SpacemapConfig.default
        config.spacesMatchBackground = false
        config.spacesBackgroundStyle = .solid
        config.spacesOpacity = 0.75

        XCTAssertEqual(
            CellSpaceBackground.from(config: config, resolvedTheme: .default),
            .solid(Color(hex: AppTheme.default.cellBg), 0.75)
        )
    }

    func testNoneSpacesBackgroundDrawsNoCellFill() {
        var config = SpacemapConfig.default
        config.spacesMatchBackground = false
        config.spacesBackgroundStyle = .none

        XCTAssertEqual(
            CellSpaceBackground.from(config: config, resolvedTheme: .default),
            .none
        )
    }

    func testMatchingSpacesBackgroundIgnoresTheSpacesGlassKeys() {
        var config = SpacemapConfig.default
        config.spacesMatchBackground = true
        config.spacesBackgroundStyle = .glass
        config.spacesGlassStyle = .tinted

        XCTAssertEqual(
            CellSpaceBackground.from(config: config, resolvedTheme: .default),
            .theme
        )
    }

    func testOnlyThumbnailCellsDrawTheCaptureAboveTheGlass() {
        for style in CellStyle.allCases {
            XCTAssertEqual(
                style.drawsCaptureAboveGlass,
                style == .thumbnails,
                "unexpected capture decision for \(style)"
            )
        }
    }

    func testThumbnailCaptureSitsAboveTheGlass() throws {
        let host = SpaceGlassHostView()
        let image = NSImage(size: NSSize(width: 8, height: 8))

        host.apply(
            SpaceGlassAppearance(
                material: .regular, variant: 5, tint: nil, opacity: 0.7, cornerRadius: 6
            ),
            capture: image
        )

        XCTAssertEqual(host.subviews.count, 2)
        let glass = try XCTUnwrap(host.subviews.first)
        XCTAssertEqual(glass.alphaValue, 0.7, accuracy: 0.001)
        let capture = try XCTUnwrap(host.subviews.last)
        XCTAssertTrue((capture.layer?.contents as? NSImage) === image,
                      "the capture must stay above the glass")
        XCTAssertFalse(capture.isHidden)
    }

    func testNonThumbnailCellsHideTheCaptureLayer() throws {
        let host = SpaceGlassHostView()

        host.apply(
            SpaceGlassAppearance(
                material: .clear, variant: 11, tint: nil, opacity: 0.5, cornerRadius: 4
            ),
            capture: nil
        )

        XCTAssertTrue(try XCTUnwrap(host.subviews.last).isHidden)
    }
}
