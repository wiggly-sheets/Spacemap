import XCTest
@testable import spacemap

final class ConfigSchemaRoundTripTests: ConfigSchemaTestCase {
    func testDecodedConfigCarriesEveryField() throws {
        var config = SpacemapConfig.default
        config.cols = 6
        config.rows = 3
        config.cellStyle = .icons
        config.theme = "dracula"
        config.mode = .dark
        config.showMode = .active
        config.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: .maskCommand)
        config.pinnedHotkey = HotkeyConfig(key: .none, modifiers: [])
        config.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: .maskShift)
        config.hudMoveSpaceBackHotkey = HotkeyConfig(key: .keyCode(101), modifiers: .maskShift)
        config.hudMoveSpaceForwardHotkey = HotkeyConfig(key: .keyCode(102), modifiers: .maskShift)
        config.hudNewSpaceHotkey = HotkeyConfig(key: .keyCode(103), modifiers: .maskShift)
        config.hudDeleteSpaceHotkey = HotkeyConfig(key: .keyCode(104), modifiers: .maskShift)
        config.hudCycleLayoutHotkey = HotkeyConfig(key: .keyCode(105), modifiers: .maskShift)

        config.maxSpaces = 12
        config.backgroundAlpha = 0.5
        config.glassClearOpacity = 0.05
        config.glassRegularOpacity = 0.35
        config.glassTintedOpacity = 0.45
        config.solidOpacity = 0.5
        config.backgroundStyle = .glass
        config.glassStyle = .tinted
        config.hudShadow = false
        config.hudCornerRadius = 12
        config.hudIconStripSeparate = true
        config.hudIconStripSource = .sbarFont
        config.hudFontName = "Avenir Next"
        config.hudFontSize = 16
        config.hudTextColor = "#FFFFFF"
        config.iconScale = 0.8
        config.uiScale = 0.75
        config.autoHideTimeout = 10
        config.socketHealthInterval = 30
        config.showExtraWindows = true
        config.showSpaceNumbers = false
        config.showSpaceLayout = true
        config.showIconStrip = false
        config.showMultiAppIcons = true
        config.showSpaceNames = true
        config.namingMode = .auto
        config.spaceNames = [1: "Term", 2: "Code"]
        config.hudKeys = .default
        config.jumpToSpaceEnabled = true
        config.fuzzySpaceJumpEnabled = false
        config.hudPosition = .custom(x: 0.25, y: 0.75, screen: "display-A")
        config.presence = AppPresence.none
        config.menuBarDisplayMode = .nearby
        config.menuBarNearbyCount = 5
        config.displayNavigationWrap = .between
        config.unifiedHUDVisibility = .all
        config.separateHUDVisibility = .active
        config.multiMonitorHUDMode = .separate
        config.focusSpaceOnWindowDrop = .modifier
        config.focusSpaceOnWindowDropModifier = .option
        config.showHUDOnSpaceChange = true
        config.showBSPLayoutBadge = true
        config.showStackLayoutBadge = false
        config.showFloatLayoutBadge = true
        config.showHUDInteractionFeedback = true
        config.spaceDropMode = .content
        config.showThumbnailWallpaper = true
        config.hudAnimationsEnabled = true
        config.hudAnimationStyle = .natural
        config.updateMode = .off
        config.appFont = AppFontConfig(updateMode: .auto, installedVersion: "v3.0.5", lastCheck: 1700000000)

        var strip = GlyphStripConfig.default
        strip.enabled = true
        strip.showSpaceNumbers = false
        strip.showLayoutSuffix = false
        strip.showAppIcons = false
        strip.dedupeAppsPerSpace = false
        strip.maxIconsPerSpace = 4
        strip.iconSize = 14
        strip.indexSize = 9
        strip.highlightCurrentSpace = false
        strip.backgroundMaterial = .liquidGlass
        strip.backgroundOpacity = 0.5
        strip.glassClearOpacity = 0.05
        strip.glassRegularOpacity = 0.35
        strip.glassTintedOpacity = 0.45
        strip.solidOpacity = 0.5
        strip.cornerRadius = 6
        strip.showDisplaySeparators = false
        strip.showAddSpaceButton = false
        strip.showPlaceholders = false
        strip.leftClickAction = .toggleFullscreen
        strip.rightClickAction = .none
        strip.middleClickAction = .balanceWindows
        strip.position = .custom
        strip.customX = 0.2
        strip.customY = 0.8
        strip.customScreen = "display-A"
        config.glyphStrip = strip

        let (decoded, needsRepair) = try decoded(written(config))

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(decoded.cols, 6)
        XCTAssertEqual(decoded.rows, 3)
        XCTAssertEqual(decoded.cellStyle, .icons)
        XCTAssertEqual(decoded.theme, "dracula")
        XCTAssertEqual(decoded.mode, .dark)
        XCTAssertEqual(decoded.showMode, .active)
        XCTAssertEqual(decoded.hotkey.keyCode, 49)
        XCTAssertTrue(decoded.hotkey.modifiers.contains(.maskCommand))
        XCTAssertEqual(decoded.pinnedHotkey.key, .none)
        XCTAssertEqual(decoded.glyphStripHotkey, HotkeyConfig(key: .keyCode(100), modifiers: .maskShift))
        XCTAssertEqual(decoded.hudMoveSpaceBackHotkey, HotkeyConfig(key: .keyCode(101), modifiers: .maskShift))
        XCTAssertEqual(decoded.hudMoveSpaceForwardHotkey, HotkeyConfig(key: .keyCode(102), modifiers: .maskShift))
        XCTAssertEqual(decoded.hudNewSpaceHotkey, HotkeyConfig(key: .keyCode(103), modifiers: .maskShift))
        XCTAssertEqual(decoded.hudDeleteSpaceHotkey, HotkeyConfig(key: .keyCode(104), modifiers: .maskShift))
        XCTAssertEqual(decoded.hudCycleLayoutHotkey, HotkeyConfig(key: .keyCode(105), modifiers: .maskShift))
        XCTAssertEqual(decoded.maxSpaces, 12)
        XCTAssertEqual(decoded.backgroundAlpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded.backgroundStyle, .glass)
        XCTAssertEqual(decoded.glassStyle, .tinted)
        XCTAssertFalse(decoded.hudShadow)
        XCTAssertEqual(decoded.iconScale, 0.8, accuracy: 0.001)
        XCTAssertEqual(decoded.uiScale, 0.75, accuracy: 0.001)
        XCTAssertEqual(decoded.autoHideTimeout, 10)
        XCTAssertEqual(decoded.socketHealthInterval, 30)
        XCTAssertTrue(decoded.showExtraWindows)
        XCTAssertFalse(decoded.showSpaceNumbers)
        XCTAssertTrue(decoded.showSpaceLayout)
        XCTAssertFalse(decoded.showIconStrip)
        XCTAssertTrue(decoded.showMultiAppIcons)
        XCTAssertTrue(decoded.showSpaceNames)
        XCTAssertEqual(decoded.namingMode, .auto)
        XCTAssertEqual(decoded.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertEqual(decoded.hudKeys, HUDKeyBindings.default)
        XCTAssertTrue(decoded.jumpToSpaceEnabled)
        XCTAssertFalse(decoded.fuzzySpaceJumpEnabled)
        XCTAssertEqual(decoded.hudPosition, .custom(x: 0.25, y: 0.75, screen: "display-A"))
        XCTAssertEqual(decoded.presence, .none)
        XCTAssertEqual(decoded.menuBarDisplayMode, .nearby)
        XCTAssertEqual(decoded.menuBarNearbyCount, 5)
        XCTAssertEqual(decoded.displayNavigationWrap, .between)
        XCTAssertEqual(decoded.unifiedHUDVisibility, .all)
        XCTAssertEqual(decoded.separateHUDVisibility, .active)
        XCTAssertEqual(decoded.multiMonitorHUDMode, .separate)
        XCTAssertEqual(decoded.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(decoded.focusSpaceOnWindowDropModifier, .option)
        XCTAssertTrue(decoded.showHUDOnSpaceChange)
        XCTAssertTrue(decoded.showBSPLayoutBadge)
        XCTAssertFalse(decoded.showStackLayoutBadge)
        XCTAssertTrue(decoded.showFloatLayoutBadge)
        XCTAssertTrue(decoded.showThumbnailWallpaper)
        XCTAssertEqual(decoded.updateMode, .off)
        XCTAssertTrue(decoded.glyphStrip.enabled)
        XCTAssertEqual(decoded.glyphStrip, strip)
        XCTAssertEqual(decoded.appFont.updateMode, .auto)
        XCTAssertEqual(decoded.appFont.installedVersion, "v3.0.5")
        XCTAssertEqual(decoded.appFont.lastCheck, 1700000000)
    }

    func testNamingModeRoundTripsAndHealsSilently() throws {
        var config = SpacemapConfig.default
        config.namingMode = .auto

        let written = written(config)
        XCTAssertTrue(written.contains("namingMode = \"auto\""), "the writer emits the mode under [spaceNames]")

        let reread = try decoded(written)
        XCTAssertEqual(reread.config.namingMode, .auto)
        XCTAssertFalse(reread.needsRepair)

        // Older files have no namingMode line: the key defaults without forcing
        // a rewrite, like the other keys added to an existing section.
        let legacy = written.replacingOccurrences(of: "namingMode = \"auto\"\n", with: "")
        let healed = try decoded(legacy)
        XCTAssertEqual(healed.config.namingMode, .custom)
        XCTAssertFalse(healed.needsRepair)

        // An unknown value falls back to custom rather than failing the load.
        let unknown = written.replacingOccurrences(of: "namingMode = \"auto\"", with: "namingMode = \"guess\"")
        let repaired = try decoded(unknown)
        XCTAssertEqual(repaired.config.namingMode, .custom)
        XCTAssertFalse(repaired.needsRepair)
    }

    func testAutoNameAppCountRoundTripsClampsAndHealsSilently() throws {
        var config = SpacemapConfig.default
        config.autoNameAppCount = 2

        let written = written(config)
        XCTAssertTrue(written.contains("autoNameAppCount = 2"), "the writer emits the count under [spaceNames]")
        XCTAssertEqual(try decoded(written).config.autoNameAppCount, 2)
        XCTAssertFalse(try decoded(written).needsRepair)

        // Older files have no count line: it defaults without forcing a rewrite.
        let legacy = written.replacingOccurrences(of: "autoNameAppCount = 2\n", with: "")
        XCTAssertEqual(try decoded(legacy).config.autoNameAppCount, 3)
        XCTAssertFalse(try decoded(legacy).needsRepair)

        // Values outside the stepper range clamp in memory and flag a rewrite.
        let outOfRange = written.replacingOccurrences(of: "autoNameAppCount = 2", with: "autoNameAppCount = 9")
        let clamped = try decoded(outOfRange)
        XCTAssertEqual(clamped.config.autoNameAppCount, 3)
        XCTAssertTrue(clamped.needsRepair)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let (empty, emptyNeedsRepair) = try decoded("[grid]\n")
        XCTAssertTrue(emptyNeedsRepair)
        XCTAssertEqual(empty.cols, SpacemapConfig.default.cols)
        XCTAssertEqual(empty.rows, SpacemapConfig.default.rows)
        XCTAssertEqual(empty.cellStyle, SpacemapConfig.default.cellStyle)
        XCTAssertEqual(empty.theme, SpacemapConfig.default.theme)
        XCTAssertEqual(empty.showMode, SpacemapConfig.default.showMode)
        XCTAssertEqual(empty.hotkey.keyCode, SpacemapConfig.default.hotkey.keyCode)
        XCTAssertEqual(empty.glyphStripHotkey, SpacemapConfig.default.glyphStripHotkey,
                       "old configs without the key load with the strip hotkey unbound")
        XCTAssertEqual(empty.hudKeys, HUDKeyBindings.default,
                       "old configs without the table load with vim and arrow keys")

        let (partial, needsRepair) = try decoded("[grid]\ncols = 5\n")

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(partial.cols, 5, "a provided field must survive")
        XCTAssertEqual(partial.rows, SpacemapConfig.default.rows)
        XCTAssertEqual(partial.cellStyle, SpacemapConfig.default.cellStyle)
        XCTAssertEqual(partial.theme, SpacemapConfig.default.theme)
    }

    func testOutOfRangeValuesClampToDefaultsOrBounds() throws {
        let (config, needsRepair) = try decoded("""
        [grid]
        cols = 0
        rows = -1
        maxSpaces = 99

        [appearance]
        backgroundAlpha = 2.0
        iconScale = -1.0
        uiScale = 5.0

        [behavior]
        autoHideTimeout = -1
        menuBarNearbyCount = 99
        """)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, SpacemapConfig.default.cols)
        XCTAssertEqual(config.rows, SpacemapConfig.default.rows)
        XCTAssertEqual(config.maxSpaces, SpacemapConfig.default.maxSpaces)
        XCTAssertEqual(config.backgroundAlpha, SpacemapConfig.default.backgroundAlpha)
        XCTAssertEqual(config.iconScale, SpacemapConfig.default.iconScale)
        XCTAssertEqual(config.uiScale, SpacemapConfig.default.uiScale)
        XCTAssertEqual(config.autoHideTimeout, SpacemapConfig.default.autoHideTimeout)
        XCTAssertEqual(config.menuBarNearbyCount, 16)

        let (clamped, clampedNeedsRepair) = try decoded("""
        [grid]
        cols = 9223372036854775807
        rows = 100
        """)
        XCTAssertTrue(clampedNeedsRepair)
        XCTAssertEqual(clamped.cols, 32)
        XCTAssertEqual(clamped.rows, 32)
    }

    func testDefaultConfigRoundTripsThroughTheWriterWithoutRepair() throws {
        let (config, needsRepair) = try decoded(written(SpacemapConfig.default))

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config, SpacemapConfig.default)
    }

    func testWriterEmitsSectionsInStableOrder() {
        let toml = written(SpacemapConfig.default)
        let markers = [
            "[grid]", "[appearance]", "[behavior]", "[hudKeys]",
            "[behavior.hudPosition]", "[glyphStrip]", "[appFont]", "[advanced]"
        ]
        var previous: String.Index?
        for marker in markers {
            guard let range = toml.range(of: marker) else {
                XCTFail("writer output is missing \(marker)")
                return
            }
            if let last = previous {
                XCTAssertLessThan(last, range.lowerBound, "\(marker) is out of writer order")
            }
            previous = range.lowerBound
        }
    }

}
