import XCTest
@testable import spacemap

final class ConfigSchemaAppearanceTests: ConfigSchemaTestCase {
    func testBackgroundAndGlassStylesRoundTrip() throws {
        for style in HUDBackgroundStyle.allCases {
            var config = SpacemapConfig.default
            config.backgroundStyle = style

            let reread = try decoded(written(config)).config
            XCTAssertEqual(reread.backgroundStyle, style)
        }

        for style in HUDGlassStyle.allCases {
            var config = SpacemapConfig.default
            config.glassStyle = style

            let reread = try decoded(written(config)).config
            XCTAssertEqual(reread.glassStyle, style)
        }
    }

    func testBackgroundStyleDefaults() throws {
        let config = try decoded("[appearance]\n").config
        XCTAssertEqual(config.backgroundStyle, .glass)
        XCTAssertEqual(config.glassStyle, .regular)
    }

    func testPerStyleBackgroundOpacitiesRoundTripAndResolve() throws {
        var config = SpacemapConfig.default
        config.backgroundAlpha = 0.4
        config.backgroundStyle = .glass
        config.glassStyle = .tinted
        config.glassClearOpacity = 0.1
        config.glassRegularOpacity = 0.2
        config.glassTintedOpacity = 0.7
        config.solidOpacity = 0.9
        config.matchBackgroundOpacity = true

        var reread = try decoded(written(config)).config

        XCTAssertEqual(reread.glassClearOpacity, 0.1)
        XCTAssertEqual(reread.glassRegularOpacity, 0.2)
        XCTAssertEqual(reread.glassTintedOpacity, 0.7)
        XCTAssertEqual(reread.solidOpacity, 0.9)
        XCTAssertEqual(reread.matchBackgroundOpacity, true)

        XCTAssertEqual(reread.effectiveBackgroundOpacity(for: .glass), 0.45)
        reread.matchBackgroundOpacity = false
        XCTAssertEqual(reread.effectiveBackgroundOpacity(for: .glass), 0.7)
        reread.backgroundStyle = .solid
        XCTAssertEqual(reread.effectiveBackgroundOpacity(for: .solid), 0.9)
        reread.solidOpacity = 0
        XCTAssertEqual(reread.effectiveBackgroundOpacity(for: .solid), 0)
    }

    func testPerStyleGlassVariantsClampAndRoundTrip() throws {
        let defaults = SpacemapConfig.default
        XCTAssertEqual(defaults.glassClearVariant, 11)
        XCTAssertEqual(defaults.glassRegularVariant, 5)
        XCTAssertEqual(defaults.glassTintedVariant, 2)

        var config = SpacemapConfig.default
        config.glassClearVariant = 21
        config.glassRegularVariant = 0
        config.glassTintedVariant = 21
        let reread = try decoded(written(config)).config
        XCTAssertEqual(reread.glassClearVariant, 21)
        XCTAssertEqual(reread.glassRegularVariant, 0)
        XCTAssertEqual(reread.glassTintedVariant, 21)
    }

    func testTintedMaterialDefaultsAndResolves() throws {
        XCTAssertEqual(SpacemapConfig.default.glassTintedMaterial, .clear)
        var config = SpacemapConfig.default
        config.glassTintedMaterial = .regular
        XCTAssertEqual(try decoded(written(config)).config.glassTintedMaterial, .regular)
        XCTAssertEqual(HUDGlassStyle.tinted.material(tintedMaterial: .regular), .regular)
        XCTAssertEqual(HUDGlassStyle.tinted.material(tintedMaterial: .clear), .clear)
        XCTAssertEqual(HUDGlassStyle.clear.material(tintedMaterial: .regular), .clear)
    }

    func testGlassStylesKeepAMinimumOpacityButSolidMayFadeOut() {
        var config = SpacemapConfig.default
        config.matchBackgroundOpacity = false

        config.backgroundStyle = .glass
        config.glassStyle = .clear
        config.glassClearOpacity = 0
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .glass), 0.35)

        config.glassStyle = .regular
        config.glassRegularOpacity = 0
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .glass), 0.40)

        config.glassStyle = .tinted
        config.glassTintedOpacity = 0
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .glass), 0.45)

        config.backgroundStyle = .solid
        config.solidOpacity = 0
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .solid), 0)
    }

    func testHUDTextAppearanceDefaultsClampAndRoundTrip() throws {
        XCTAssertEqual(SpacemapConfig.default.hudFontName, "")
        XCTAssertEqual(SpacemapConfig.default.hudFontSize, 12)
        XCTAssertEqual(SpacemapConfig.default.hudTextColor, "")
        XCTAssertEqual(SpacemapConfig.default.hudCornerRadius, 10)

        var config = SpacemapConfig.default
        config.hudFontName = "Avenir Next"
        config.hudFontSize = 18
        config.hudTextColor = "#FFFFFF"
        config.hudCornerRadius = 24
        var reread = try decoded(written(config))
        XCTAssertEqual(reread.config.hudFontName, "Avenir Next")
        XCTAssertEqual(reread.config.hudFontSize, 18)
        XCTAssertEqual(reread.config.hudTextColor, "#FFFFFF")
        XCTAssertEqual(reread.config.hudCornerRadius, 24)

        // Out-of-range values fall back to the defaults on the next load.
        config.hudFontSize = 99
        config.hudCornerRadius = 99
        reread = try decoded(written(config))
        XCTAssertEqual(reread.config.hudFontSize, 12)
        XCTAssertEqual(reread.config.hudCornerRadius, 10)
        XCTAssertTrue(reread.needsRepair)
    }

    func testHUDMotionAndFeedbackFlagsDefaultOnAndRoundTrip() throws {
        XCTAssertTrue(SpacemapConfig.default.hudAnimationsEnabled)
        XCTAssertEqual(SpacemapConfig.default.hudAnimationStyle, .natural)
        XCTAssertEqual(SpacemapConfig.default.hudEntranceStyle, .fade)
        XCTAssertTrue(SpacemapConfig.default.showHUDInteractionFeedback)

        var config = SpacemapConfig.default
        XCTAssertEqual(config.showHUDInteractionFeedback, true)
        config.hudAnimationsEnabled = false
        config.hudAnimationStyle = .springy
        config.hudEntranceStyle = .slideFromLeft
        config.showHUDInteractionFeedback = false
        config.showThumbnailWallpaper = true
        let reread = try decoded(written(config)).config
        XCTAssertFalse(reread.hudAnimationsEnabled)
        XCTAssertEqual(reread.hudAnimationStyle, .springy)
        XCTAssertEqual(reread.hudEntranceStyle, .slideFromLeft)
        XCTAssertFalse(reread.showHUDInteractionFeedback)
        XCTAssertTrue(reread.showThumbnailWallpaper)
    }

    func testMenuBarModeHealsSavedGlassMaterialToSolid() throws {
        let result = try decoded("""
        [glyphStrip]
        displayMode = "menuBarItem"
        backgroundMaterial = "liquidGlass"
        """)

        XCTAssertEqual(result.config.glyphStrip.backgroundMaterial, .solid)
        XCTAssertTrue(result.needsRepair)
    }

    func testMaterialAndCornerRadiusRoundTripThroughTheConfigString() throws {
        var config = SpacemapConfig.default
        config.glyphStrip.backgroundMaterial = .liquidGlass
        config.glyphStrip.cornerRadius = 0

        let reread = try decoded(written(config)).config

        XCTAssertEqual(reread.glyphStrip.backgroundMaterial, .liquidGlass)
        XCTAssertEqual(reread.glyphStrip.cornerRadius, 0)
    }

    func testAppearanceFieldsRoundTripThroughTheWriter() throws {
        var config = SpacemapConfig.default
        config.theme = "Dracula \"Night\""
        config.mode = .light
        config.backgroundAlpha = 0.42
        config.backgroundStyle = .solid
        config.glassStyle = .tinted
        config.glassClearVariant = 3
        config.glassRegularVariant = 4
        config.glassTintedVariant = 6
        config.glassTintedMaterial = .regular
        config.glassClearOpacity = 0.11
        config.glassRegularOpacity = 0.22
        config.glassTintedOpacity = 0.33
        config.solidOpacity = 0.44
        config.matchBackgroundOpacity = true
        config.hudShadow = false
        config.hudCornerRadius = 18
        config.hudFontName = "Avenir Next"
        config.hudFontSize = 20
        config.hudTextColor = "#ABCDEF"
        config.spacesMatchBackground = false
        config.spacesBackgroundStyle = .solid
        config.spacesGlassStyle = .tinted
        config.spacesGlassClearVariant = 7
        config.spacesGlassRegularVariant = 8
        config.spacesGlassTintedVariant = 9
        config.spacesGlassTintedMaterial = .regular
        config.spacesOpacity = 0.66
        config.spacesCornerRadius = 12
        config.iconScale = 0.77
        config.uiScale = 0.88

        let (reread, needsRepair) = try decoded(written(config))

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reread, config)
        XCTAssertEqual(reread.spacesGlassStyle, .tinted)
        XCTAssertEqual(reread.spacesGlassClearVariant, 7)
        XCTAssertEqual(reread.spacesGlassRegularVariant, 8)
        XCTAssertEqual(reread.spacesGlassTintedVariant, 9)
        XCTAssertEqual(reread.spacesGlassTintedMaterial, .regular)
    }

    func testAppearanceSchemaRepairsMissingInvalidAndOutOfRangeValues() throws {
        let full = written(SpacemapConfig.default)

        // Missing key -> default + repair.
        let (missing, missingRepair) = try decoded(
            full.replacingOccurrences(of: "backgroundAlpha = 0.3\n", with: "")
        )
        XCTAssertTrue(missingRepair)
        XCTAssertEqual(missing.backgroundAlpha, SpacemapConfig.default.backgroundAlpha)

        // Invalid enum and out-of-range fractions -> default + repair.
        let (broken, brokenRepair) = try decoded(
            "[appearance]\nbackgroundStyle = \"retro\"\nbackgroundAlpha = 2.0\niconScale = -1.0\nuiScale = 5.0\n"
        )
        XCTAssertTrue(brokenRepair)
        XCTAssertEqual(broken.backgroundStyle, SpacemapConfig.default.backgroundStyle)
        XCTAssertEqual(broken.backgroundAlpha, SpacemapConfig.default.backgroundAlpha)
        XCTAssertEqual(broken.iconScale, SpacemapConfig.default.iconScale)
        XCTAssertEqual(broken.uiScale, SpacemapConfig.default.uiScale)

        // Validated keys above their range fall back to the default, not to the
        // bound: the HUD must not jump to a 60pt radius or a 48pt font.
        let (oversize, oversizeRepair) = try decoded("[appearance]\nhudFontSize = 99.0\nhudCornerRadius = 999.0\n")
        XCTAssertEqual(oversize.hudFontSize, SpacemapConfig.default.hudFontSize)
        XCTAssertEqual(oversize.hudCornerRadius, SpacemapConfig.default.hudCornerRadius)
        XCTAssertTrue(oversizeRepair)
    }

    func testAppearanceSchemaHealsSilentKeysWithoutFlaggingRepair() throws {
        let full = written(SpacemapConfig.default)

        // A wrong-typed font name heals silently.
        let (healedFont, fontRepair) = try decoded(
            full.replacingOccurrences(of: "hudFontName = \"\"\n", with: "hudFontName = 42\n")
        )
        XCTAssertFalse(fontRepair, "a mistyped font name heals without a config rewrite")
        XCTAssertEqual(healedFont.hudFontName, SpacemapConfig.default.hudFontName)

        // A non-Int variant falls back to its default, also without a flag.
        let (healedVariant, variantRepair) = try decoded(
            full.replacingOccurrences(of: "glassClearVariant = 11\n", with: "glassClearVariant = 11.5\n")
        )
        XCTAssertFalse(variantRepair)
        XCTAssertEqual(healedVariant.glassClearVariant, SpacemapConfig.default.glassClearVariant)
    }

    func testAppearanceSchemaClampsSpacesCornerRadiusSilentlyAndWritesTheHealedValue() throws {
        let full = written(SpacemapConfig.default)
        let (config, needsRepair) = try decoded(
            full.replacingOccurrences(of: "spacesCornerRadius = 4.0\n", with: "spacesCornerRadius = 999.0\n")
        )
        XCTAssertFalse(needsRepair, "the clamp is silent")
        XCTAssertEqual(config.spacesCornerRadius, 60)

        // The writer now encodes the resolved config, so the clamp reaches the
        // file on the next save instead of surviving as a raw 999.
        XCTAssertTrue(written(config).contains("spacesCornerRadius = 60.0"))
    }

    func testAppearanceSchemaClampsSpacesCornerRadiusBelowRangeToZeroSilently() throws {
        let full = written(SpacemapConfig.default)
        let (config, needsRepair) = try decoded(
            full.replacingOccurrences(of: "spacesCornerRadius = 4.0\n", with: "spacesCornerRadius = -5\n")
        )
        XCTAssertFalse(needsRepair, "the clamp is silent")
        XCTAssertEqual(config.spacesCornerRadius, 0)

        XCTAssertTrue(written(config).contains("spacesCornerRadius = 0.0"))
    }

    func testOutOfRangeVariantAndOpacityHealSilentlyToDefaults() throws {
        let toml = written(SpacemapConfig.default)
            .replacingOccurrences(of: "glassClearVariant = 11\n", with: "glassClearVariant = 99\n")
            .replacingOccurrences(of: "spacesOpacity = 0.5\n", with: "spacesOpacity = 5\n")
        let (config, needsRepair) = try decoded(toml)

        XCTAssertFalse(needsRepair, "the clamp is silent")
        XCTAssertEqual(config.glassClearVariant, SpacemapConfig.default.glassClearVariant)
        XCTAssertEqual(config.spacesOpacity, SpacemapConfig.default.spacesOpacity)
    }

}
