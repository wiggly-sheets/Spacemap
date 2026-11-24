import XCTest
@testable import spacemap

final class ConfigSchemaBehaviorTests: ConfigSchemaTestCase {
    func testSpaceLayerDefaultsAndRoundTrip() throws {
        let defaults = SpacemapConfig.default
        XCTAssertTrue(defaults.spacesMatchBackground)
        XCTAssertEqual(defaults.spacesBackgroundStyle, .glass)
        XCTAssertEqual(defaults.spacesGlassStyle, .clear)
        XCTAssertEqual(defaults.spacesGlassClearVariant, 11)
        XCTAssertEqual(defaults.spacesOpacity, 0.5)
        XCTAssertEqual(defaults.spacesCornerRadius, 4)

        var config = SpacemapConfig.default
        config.spacesMatchBackground = false
        config.spacesBackgroundStyle = .solid
        config.spacesOpacity = 0.25
        config.spacesCornerRadius = 8
        let reread = try decoded(written(config)).config
        XCTAssertEqual(reread.spacesMatchBackground, false)
        XCTAssertEqual(reread.spacesBackgroundStyle, .solid)
        XCTAssertEqual(reread.spacesOpacity, 0.25)
        XCTAssertEqual(reread.spacesCornerRadius, 8)
    }

    func testSpaceDropModeDefaultsToContentAndRoundTrips() throws {
        XCTAssertEqual(SpacemapConfig.default.spaceDropMode, .content)
        XCTAssertEqual(SpacemapConfig.default.spaceDragFocus, .stay)
        XCTAssertEqual(SpacemapConfig.default.windowDragFocus, .destination)
        var config = SpacemapConfig.default
        XCTAssertEqual(config.spaceDropMode, .content)
        config.spaceDropMode = .spaces
        config.spaceDragFocus = .destination
        config.windowDragFocus = .stay
        let reread = try decoded(written(config)).config
        XCTAssertEqual(reread.spaceDropMode, .spaces)
        XCTAssertEqual(reread.spaceDragFocus, .destination)
        XCTAssertEqual(reread.windowDragFocus, .stay)
    }

    func testHUDIconSourceDefaultsNativeAndRoundTrips() throws {
        XCTAssertEqual(SpacemapConfig.default.hudIconSource, .nativeIcons)
        var config = SpacemapConfig.default
        XCTAssertEqual(config.hudIconSource, .nativeIcons)
        config.hudIconSource = .sbarFont
        XCTAssertEqual(try decoded(written(config)).config.hudIconSource, .sbarFont)
    }

    func testSeparateIconStripSourceDefaultsOffAndResolves() throws {
        XCTAssertFalse(SpacemapConfig.default.hudIconStripSeparate)
        var config = SpacemapConfig.default
        config.hudIconSource = .sbarFont
        XCTAssertEqual(config.resolvedHUDIconStripSource, .sbarFont)

        var separate = SpacemapConfig.default
        separate.hudIconStripSeparate = true
        separate.hudIconStripSource = .sbarFont
        let resolved = try decoded(written(separate)).config
        XCTAssertTrue(resolved.hudIconStripSeparate)
        XCTAssertEqual(resolved.resolvedHUDIconStripSource, .sbarFont)
        XCTAssertEqual(resolved.hudIconSource, .nativeIcons, "cell icons keep their own source")
    }

    func testPresenceDefaultsAndRoundTrips() throws {
        XCTAssertEqual(SpacemapConfig.default.presence, .menuBar)
        var config = SpacemapConfig.default
        XCTAssertEqual(config.presence, .menuBar)
        config.presence = .both
        XCTAssertEqual(try decoded(written(config)).config.presence, .both)

        XCTAssertTrue(AppPresence.dock.showsDock)
        XCTAssertFalse(AppPresence.dock.showsMenuBar)
        XCTAssertTrue(AppPresence.both.showsDock)
        XCTAssertTrue(AppPresence.both.showsMenuBar)
        XCTAssertFalse(AppPresence.none.showsDock)
        XCTAssertFalse(AppPresence.none.showsMenuBar)
    }

    func testGridSchemaRepairsMissingInvalidAndOutOfRangeValues() throws {
        let full = written(SpacemapConfig.default)

        // Missing key -> default + repair.
        let (missing, missingRepair) = try decoded(
            full.replacingOccurrences(of: "showSpaceLayout = false\n", with: "")
        )
        XCTAssertTrue(missingRepair)
        XCTAssertEqual(missing.showSpaceLayout, SpacemapConfig.default.showSpaceLayout)

        // Invalid enum and non-positive int -> default + repair; oversize clamps.
        let (broken, brokenRepair) = try decoded("[grid]\ncols = 999\nrows = 0\ncellStyle = \"retro\"\n")
        XCTAssertTrue(brokenRepair)
        XCTAssertEqual(broken.cols, 32)
        XCTAssertEqual(broken.rows, SpacemapConfig.default.rows)
        XCTAssertEqual(broken.cellStyle, SpacemapConfig.default.cellStyle)

        // Above the range clamps to the bound; below the range falls back.
        let oversize = try decoded("[grid]\nmaxSpaces = 99\n").config
        XCTAssertEqual(oversize.maxSpaces, 16)
    }

    func testGridSchemaHealsAMissingIconSourceWithoutFlaggingRepair() throws {
        let full = written(SpacemapConfig.default)
        let (config, needsRepair) = try decoded(
            full.replacingOccurrences(of: "hudIconSource = \"native\"\n", with: "")
        )
        XCTAssertFalse(needsRepair, "a missing icon source heals without a config rewrite")
        XCTAssertEqual(config.hudIconSource, SpacemapConfig.default.hudIconSource)
    }

    func testBehaviorSchemaRepairsMissingInvalidAndOutOfRangeValues() throws {
        let full = written(SpacemapConfig.default)

        // Missing key -> default + repair.
        let (missing, missingRepair) = try decoded(
            full.replacingOccurrences(of: "showHUDOnSpaceChange = false\n", with: "")
        )
        XCTAssertTrue(missingRepair)
        XCTAssertEqual(missing.showHUDOnSpaceChange, SpacemapConfig.default.showHUDOnSpaceChange)

        // Invalid enum, negative timeout, and over-range int repair too.
        let (broken, brokenRepair) = try decoded("""
        [behavior]
        autoHideTimeout = -1
        displayNavigationWrap = "sideways"
        menuBarNearbyCount = 99
        focusSpaceOnWindowDrop = "sometimes"
        """)
        XCTAssertTrue(brokenRepair)
        XCTAssertEqual(broken.autoHideTimeout, SpacemapConfig.default.autoHideTimeout)
        XCTAssertEqual(broken.displayNavigationWrap, SpacemapConfig.default.displayNavigationWrap)
        XCTAssertEqual(broken.menuBarNearbyCount, 16)
        XCTAssertEqual(broken.focusSpaceOnWindowDrop, SpacemapConfig.default.focusSpaceOnWindowDrop)
    }

    func testBehaviorSchemaHealsSilentKeysWithoutFlaggingRepair() throws {
        let full = written(SpacemapConfig.default)
        let silentKeys = [
            "spaceDropMode = \"content\"\n",
            "spaceDragFocus = \"stay\"\n",
            "windowDragFocus = \"destination\"\n",
            "hudAnimationStyle = \"natural\"\n",
            "hudEntranceStyle = \"fade\"\n"
        ]
        let stripped = silentKeys.reduce(full) { $0.replacingOccurrences(of: $1, with: "") }
        let (config, needsRepair) = try decoded(stripped)

        XCTAssertFalse(needsRepair, "unparsable behavior enums heal without a config rewrite")
        XCTAssertEqual(config.spaceDropMode, SpacemapConfig.default.spaceDropMode)
        XCTAssertEqual(config.spaceDragFocus, SpacemapConfig.default.spaceDragFocus)
        XCTAssertEqual(config.windowDragFocus, SpacemapConfig.default.windowDragFocus)
        XCTAssertEqual(config.hudAnimationStyle, SpacemapConfig.default.hudAnimationStyle)
        XCTAssertEqual(config.hudEntranceStyle, SpacemapConfig.default.hudEntranceStyle)
    }

    func testBehaviorKeysRoundTripThroughTheWriter() throws {
        var config = SpacemapConfig.default
        config.hudAnimationStyle = .springy
        config.hudEntranceStyle = .slideFromBottom
        config.hudAnimationsEnabled = false
        config.presence = .both
        config.menuBarDisplayMode = .current
        config.showBSPLayoutBadge = false
        config.showStackLayoutBadge = false
        config.showFloatLayoutBadge = false
        config.focusSpaceOnWindowDrop = .modifier
        config.focusSpaceOnWindowDropModifier = .option
        config.updateMode = .auto

        let (reread, needsRepair) = try decoded(written(config))

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reread.hudAnimationStyle, .springy)
        XCTAssertEqual(reread.hudEntranceStyle, .slideFromBottom)
        XCTAssertFalse(reread.hudAnimationsEnabled)
        XCTAssertEqual(reread.presence, .both)
        XCTAssertEqual(reread.menuBarDisplayMode, .current)
        XCTAssertFalse(reread.showBSPLayoutBadge)
        XCTAssertFalse(reread.showStackLayoutBadge)
        XCTAssertFalse(reread.showFloatLayoutBadge)
        XCTAssertEqual(reread.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(reread.focusSpaceOnWindowDropModifier, .option)
        XCTAssertEqual(reread.updateMode, .auto)
        XCTAssertEqual(reread, config)
    }

    func testAdvancedKeysRoundTripThroughTheWriter() throws {
        var config = SpacemapConfig.default
        config.socketHealthInterval = 30
        config.showExtraWindows = true
        config.refuseUntrustedYabai = true

        let (reread, needsRepair) = try decoded(written(config))

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reread.socketHealthInterval, 30)
        XCTAssertTrue(reread.showExtraWindows)
        XCTAssertTrue(reread.refuseUntrustedYabai)
    }

    func testShowThumbnailWallpaperFlattensFromGridAndBehavior() throws {
        let grid = try decoded("[grid]\nshowThumbnailWallpaper = false\n").config
        XCTAssertEqual(grid.showThumbnailWallpaper, false)

        let behavior = try decoded("[behavior]\nshowThumbnailWallpaper = false\n").config
        XCTAssertEqual(behavior.showThumbnailWallpaper, false)
    }

    func testAdvancedSchemaClampsMissingAndHealsSilently() throws {
        let full = written(SpacemapConfig.default)

        // Above the range clamps to the bound and flags repair.
        let (clamped, clampedRepair) = try decoded(
            full.replacingOccurrences(of: "socketHealthInterval = 60\n", with: "socketHealthInterval = 99999\n")
        )
        XCTAssertTrue(clampedRepair)
        XCTAssertEqual(clamped.socketHealthInterval, 3600)

        // Missing keys -> defaults. The new flag alone heals silently.
        let (healed, healedRepair) = try decoded(
            full.replacingOccurrences(of: "refuseUntrustedYabai = false\n", with: "")
        )
        XCTAssertFalse(healedRepair, "a missing refuseUntrustedYabai must not force a rewrite")
        XCTAssertEqual(healed.refuseUntrustedYabai, false)

        let (defaults, defaultsRepair) = try decoded("""
        [advanced]
        """)
        XCTAssertTrue(defaultsRepair)
        XCTAssertEqual(defaults.socketHealthInterval, SpacemapConfig.default.socketHealthInterval)
        XCTAssertEqual(defaults.showExtraWindows, SpacemapConfig.default.showExtraWindows)
        XCTAssertEqual(defaults.refuseUntrustedYabai, SpacemapConfig.default.refuseUntrustedYabai)
    }
}
