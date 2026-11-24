import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripConfigDecodingTests: GlyphStripTestCase {

    // MARK: - Config decoding

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

    func testInvalidEnumValuesFallBackForMaterialAndPosition() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        backgroundMaterial = "plasma"
        shape = "triangle"
        position = "topLeft"
        spaceLabelStyle = "emoji"
        """)

        XCTAssertEqual(config?.backgroundMaterial, GlyphStripBackgroundMaterial.none)
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
        XCTAssertEqual(clamped?.plainMargin, 6, "an unset plain margin keeps its default")
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
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.plainMargin, 6)
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\nplainMargin = -4.0")?.clamped().plainMargin,
            0
        )
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\nplainMargin = 400.0")?.clamped().plainMargin,
            40
        )
    }

    func testCustomPlacementDefaultsToCentredFractions() {
        let defaults = decodeGlyphStrip("[glyphStrip]\nenabled = true")
        XCTAssertEqual(defaults?.customX, 0.5)
        XCTAssertEqual(defaults?.customY, 0.5)
        XCTAssertEqual(defaults?.customScreen, "", "no display pairing by default")
        XCTAssertEqual(defaults?.plainCustomX, 0.5)
        XCTAssertEqual(defaults?.plainCustomY, 0.5)
        XCTAssertEqual(defaults?.plainCustomScreen, "", "no display pairing by default")
    }

    func testCustomPointsAreIndependentPerScreenType() {
        var strip = GlyphStripConfig.default
        strip.position = .custom
        strip.plainPosition = .custom
        strip.setCustomPlacement(hasNotch: true, x: 0.2, y: 0.9, screen: "notched")
        strip.setCustomPlacement(hasNotch: false, x: 0.8, y: 0.1, screen: "plain")

        let notched = strip.customPlacement(hasNotch: true)
        XCTAssertEqual(notched.x, 0.2)
        XCTAssertEqual(notched.y, 0.9)
        XCTAssertEqual(notched.screen, "notched")

        let plain = strip.customPlacement(hasNotch: false)
        XCTAssertEqual(plain.x, 0.8)
        XCTAssertEqual(plain.y, 0.1)
        XCTAssertEqual(plain.screen, "plain")
    }

    func testOldSharedCustomPointSeedsThePlainPoint() {
        let config = decodeGlyphStrip("""
        [glyphStrip]
        customX = 0.3
        customY = 0.7
        customScreen = "old-display"
        """)
        XCTAssertEqual(config?.plainCustomX, 0.3)
        XCTAssertEqual(config?.plainCustomY, 0.7)
        XCTAssertEqual(config?.plainCustomScreen, "old-display")
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
        XCTAssertEqual(config?.plainCustomX, 0.5)
        XCTAssertEqual(config?.borderEnabled, true, "border defaults to on")
        XCTAssertEqual(config?.position, .leftOfNotch)
        XCTAssertEqual(
            config?.plainPosition,
            .center,
            "a plain display defaults to centred instead of a notch anchor's screen edge"
        )
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
        original.plainPosition = .rightOfNotch
        original.plainMargin = 4
        original.customX = 0.3
        original.customY = 0.7
        original.customScreen = "display-A"
        original.plainCustomX = 0.8
        original.plainCustomY = 0.2
        original.plainCustomScreen = "display-B"
        original.theme = "nord"
        original.borderEnabled = false

        var values = SpacemapConfig.default
        values.glyphStrip = original
        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = decodeGlyphStrip(toml)?.clamped()

        XCTAssertEqual(reread, original)
    }
}
