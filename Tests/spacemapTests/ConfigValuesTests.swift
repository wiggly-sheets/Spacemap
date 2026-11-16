import XCTest
@testable import spacemap

final class ConfigValuesTests: XCTestCase {

    func testToGridConfigWithAllFieldsSet() {
        var values = ConfigValues()
        values.cols = 6
        values.rows = 3
        values.cellStyle = .icons
        values.theme = "dracula"
        values.mode = .dark
        values.showMode = .active
        values.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: .maskCommand)
        values.pinnedHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: .maskShift)
        values.hudMoveSpaceBackHotkey = HotkeyConfig(key: .keyCode(101), modifiers: .maskShift)
        values.hudMoveSpaceForwardHotkey = HotkeyConfig(key: .keyCode(102), modifiers: .maskShift)
        values.hudNewSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.hudDeleteSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.hudCycleLayoutHotkey = HotkeyConfig(key: .none, modifiers: [])

        values.maxSpaces = 12
        values.backgroundAlpha = 0.5
        values.glassClearOpacity = 0.05
        values.glassRegularOpacity = 0.35
        values.glassTintedOpacity = 0.45
        values.solidOpacity = 0.5
        values.backgroundStyle = .glass
        values.glassStyle = .tinted
        values.hudShadow = false
        values.hudCornerRadius = 12
        values.hudIconStripSeparate = true
        values.hudIconStripSource = .sbarFont
        values.hudFontName = "Avenir Next"
        values.hudFontSize = 16
        values.hudTextColor = "#FFFFFF"
        values.iconScale = 0.8
        values.uiScale = 0.75
        values.autoHideTimeout = 10
        values.socketHealthInterval = 30
        values.showExtraWindows = true
        values.showSpaceNumbers = false
        values.showSpaceLayout = true
        values.showIconStrip = false
        values.showMultiAppIcons = true
        values.showSpaceNames = true
        values.spaceNames = [1: "Term", 2: "Code"]
        values.useVimKeys = true
        values.useArrowKeys = true
        values.useExtendedKeys = true
        values.jumpToSpaceEnabled = true
        values.hudPosition = .custom(x: 0.25, y: 0.75)
        values.customHUDX = 0.25
        values.customHUDY = 0.75
        values.presence = AppPresence.none
        values.glyphStrip = GlyphStripConfig(enabled: true)
        values.menuBarDisplayMode = .nearby
        values.menuBarNearbyCount = 5
        values.displayNavigationWrap = .between
        values.unifiedHUDVisibility = .all
        values.separateHUDVisibility = .active
        values.multiMonitorHUDMode = .separate
        values.focusSpaceOnWindowDrop = .modifier
        values.focusSpaceOnWindowDropModifier = .option
        values.showHUDOnSpaceChange = true
        values.showBSPLayoutBadge = true
        values.showStackLayoutBadge = false
        values.showFloatLayoutBadge = true

        values.showHUDInteractionFeedback = true
        values.spaceDropMode = .content
        values.showThumbnailWallpaper = true
        values.hudAnimationsEnabled = true
        values.hudAnimationStyle = .natural
        values.updateMode = .off
        values.appFont = AppFontConfig(updateMode: .auto, installedVersion: "v3.0.5", lastCheck: 1700000000)

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
        strip.shape = .pill
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
        strip.position = .center
        values.glyphStrip = strip

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 6)
        XCTAssertEqual(config.rows, 3)
        XCTAssertEqual(config.cellStyle, .icons)
        XCTAssertEqual(config.theme, "dracula")
        XCTAssertEqual(config.mode, .dark)
        XCTAssertEqual(config.showMode, .active)
        XCTAssertEqual(config.hotkey.keyCode, 49)
        XCTAssertTrue(config.hotkey.modifiers.contains(.maskCommand))
        XCTAssertEqual(config.pinnedHotkey.key, .none)
        XCTAssertEqual(config.glyphStripHotkey, HotkeyConfig(key: .keyCode(100), modifiers: .maskShift))
        XCTAssertEqual(config.maxSpaces, 12)
        XCTAssertEqual(config.backgroundAlpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(config.backgroundStyle, .glass)
        XCTAssertEqual(config.glassStyle, .tinted)
        XCTAssertFalse(config.hudShadow)
        XCTAssertEqual(config.iconScale, 0.8, accuracy: 0.001)
        XCTAssertEqual(config.uiScale, 0.75, accuracy: 0.001)
        XCTAssertEqual(config.autoHideTimeout, 10)
        XCTAssertEqual(config.socketHealthInterval, 30)
        XCTAssertTrue(config.showExtraWindows)
        XCTAssertFalse(config.showSpaceNumbers)
        XCTAssertTrue(config.showSpaceLayout)
        XCTAssertFalse(config.showIconStrip)
        XCTAssertTrue(config.showMultiAppIcons)
        XCTAssertTrue(config.showSpaceNames)
        XCTAssertEqual(config.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertTrue(config.useVimKeys)
        XCTAssertTrue(config.useArrowKeys)
        XCTAssertTrue(config.useExtendedKeys)
        XCTAssertTrue(config.jumpToSpaceEnabled)
        XCTAssertEqual(config.hudPosition, .custom(x: 0.25, y: 0.75))
        XCTAssertEqual(config.customHUDX, 0.25, accuracy: 0.001)
        XCTAssertEqual(config.customHUDY, 0.75, accuracy: 0.001)
        XCTAssertEqual(config.presence, .none)
        XCTAssertEqual(config.menuBarDisplayMode, .nearby)
        XCTAssertEqual(config.menuBarNearbyCount, 5)
        XCTAssertEqual(config.displayNavigationWrap, .between)
        XCTAssertEqual(config.unifiedHUDVisibility, .all)
        XCTAssertEqual(config.separateHUDVisibility, .active)
        XCTAssertEqual(config.multiMonitorHUDMode, .separate)
        XCTAssertEqual(config.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(config.focusSpaceOnWindowDropModifier, .option)
        XCTAssertTrue(config.showHUDOnSpaceChange)
        XCTAssertTrue(config.showBSPLayoutBadge)
        XCTAssertFalse(config.showStackLayoutBadge)
        XCTAssertTrue(config.showFloatLayoutBadge)
        XCTAssertTrue(config.showThumbnailWallpaper)
        XCTAssertEqual(config.updateMode, .off)
        XCTAssertTrue(config.glyphStrip.enabled)
        XCTAssertEqual(config.glyphStrip, strip)
        XCTAssertEqual(config.appFont.updateMode, .auto)
        XCTAssertEqual(config.appFont.installedVersion, "v3.0.5")
        XCTAssertEqual(config.appFont.lastCheck, 1700000000)
    }

    func testBackgroundStyleRoundTrip() throws {
        for style in HUDBackgroundStyle.allCases {
            var values = ConfigValues()
            values.backgroundStyle = style

            let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
            let reread = try TOMLParser.parse(toml)

            XCTAssertEqual(reread.backgroundStyle, style)

            let (config, _) = reread.toGridConfig()
            XCTAssertEqual(config.backgroundStyle, style)
        }
    }

    func testGlassStyleRoundTrip() throws {
        for style in HUDGlassStyle.allCases {
            var values = ConfigValues()
            values.glassStyle = style

            let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
            let reread = try TOMLParser.parse(toml)

            XCTAssertEqual(reread.glassStyle, style)

            let (config, _) = reread.toGridConfig()
            XCTAssertEqual(config.glassStyle, style)
        }
    }

    func testBackgroundStyleDefaults() {
        let values = ConfigValues()
        let (config, _) = values.toGridConfig()
        XCTAssertEqual(config.backgroundStyle, .glass)
        XCTAssertEqual(config.glassStyle, .regular)
    }

    func testPerStyleBackgroundOpacitiesRoundTripAndResolve() throws {
        var values = ConfigValues()
        values.backgroundAlpha = 0.4
        values.backgroundStyle = .glass
        values.glassStyle = .tinted
        values.glassClearOpacity = 0.1
        values.glassRegularOpacity = 0.2
        values.glassTintedOpacity = 0.7
        values.solidOpacity = 0.9
        values.matchBackgroundOpacity = true

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)

        XCTAssertEqual(reread.glassClearOpacity, 0.1)
        XCTAssertEqual(reread.glassRegularOpacity, 0.2)
        XCTAssertEqual(reread.glassTintedOpacity, 0.7)
        XCTAssertEqual(reread.solidOpacity, 0.9)
        XCTAssertEqual(reread.matchBackgroundOpacity, true)

        var config = reread.toGridConfig().config
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .glass), 0.45)
        config.matchBackgroundOpacity = false
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .glass), 0.7)
        config.backgroundStyle = .solid
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .solid), 0.9)
        config.solidOpacity = 0
        XCTAssertEqual(config.effectiveBackgroundOpacity(for: .solid), 0)
    }

    func testPerStyleGlassVariantsClampAndRoundTrip() throws {
        var values = ConfigValues()
        let defaults = values.toGridConfig().config
        XCTAssertEqual(defaults.glassClearVariant, 11)
        XCTAssertEqual(defaults.glassRegularVariant, 5)
        XCTAssertEqual(defaults.glassTintedVariant, 2)

        values.glassClearVariant = 21
        values.glassRegularVariant = 0
        values.glassTintedVariant = 21
        let config = values.toGridConfig().config
        XCTAssertEqual(config.glassClearVariant, 21)
        XCTAssertEqual(config.glassRegularVariant, 0)
        XCTAssertEqual(config.glassTintedVariant, 21)

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)
        XCTAssertEqual(reread.glassClearVariant, 21)
        XCTAssertEqual(reread.glassRegularVariant, 0)
        XCTAssertEqual(reread.glassTintedVariant, 21)
    }

    func testTintedMaterialDefaultsAndResolves() {
        var values = ConfigValues()
        XCTAssertEqual(values.toGridConfig().config.glassTintedMaterial, .clear)
        values.glassTintedMaterial = .regular
        XCTAssertEqual(values.toGridConfig().config.glassTintedMaterial, .regular)
        XCTAssertEqual(HUDGlassStyle.tinted.material(tintedMaterial: .regular), .regular)
        XCTAssertEqual(HUDGlassStyle.tinted.material(tintedMaterial: .clear), .clear)
        XCTAssertEqual(HUDGlassStyle.clear.material(tintedMaterial: .regular), .clear)
    }

    func testSpaceLayerDefaultsAndRoundTrip() throws {
        let defaults = ConfigValues().toGridConfig().config
        XCTAssertTrue(defaults.spacesMatchBackground)
        XCTAssertEqual(defaults.spacesBackgroundStyle, .glass)
        XCTAssertEqual(defaults.spacesGlassStyle, .clear)
        XCTAssertEqual(defaults.spacesGlassClearVariant, 11)
        XCTAssertEqual(defaults.spacesOpacity, 0.5)
        XCTAssertEqual(defaults.spacesCornerRadius, 4)

        var values = ConfigValues()
        values.spacesMatchBackground = false
        values.spacesBackgroundStyle = .solid
        values.spacesOpacity = 0.25
        values.spacesCornerRadius = 8
        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)
        XCTAssertEqual(reread.spacesMatchBackground, false)
        XCTAssertEqual(reread.spacesBackgroundStyle, .solid)
        XCTAssertEqual(reread.spacesOpacity, 0.25)
        XCTAssertEqual(reread.spacesCornerRadius, 8)
    }

    func testGlassStylesKeepAMinimumOpacityButSolidMayFadeOut() {
        var config = GridConfig.default
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


    func testHUDFontDefaultsAndClampsSize() throws {
        XCTAssertEqual(GridConfig.default.hudFontName, "")
        XCTAssertEqual(GridConfig.default.hudFontSize, 12)

        var values = ConfigValues()
        values.hudFontName = "Avenir Next"
        values.hudFontSize = 18
        let (config, _) = values.toGridConfig()
        XCTAssertEqual(config.hudFontName, "Avenir Next")
        XCTAssertEqual(config.hudFontSize, 18)

        values.hudFontSize = 99
        XCTAssertEqual(values.toGridConfig().config.hudFontSize, 12)

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)
        XCTAssertEqual(reread.hudFontName, "Avenir Next")
        XCTAssertEqual(reread.hudFontSize, 99)
    }

    func testHUDTextColorDefaultsEmptyAndRoundTrips() throws {
        XCTAssertEqual(GridConfig.default.hudTextColor, "")

        var values = ConfigValues()
        values.hudTextColor = "#FFFFFF"
        XCTAssertEqual(values.toGridConfig().config.hudTextColor, "#FFFFFF")

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)
        XCTAssertEqual(reread.hudTextColor, "#FFFFFF")
    }

    func testHUDCornerRadiusDefaultsClampsAndRoundTrips() throws {
        XCTAssertEqual(GridConfig.default.hudCornerRadius, 10)

        var values = ConfigValues()
        values.hudCornerRadius = 24
        let (config, _) = values.toGridConfig()
        XCTAssertEqual(config.hudCornerRadius, 24)

        values.hudCornerRadius = 99
        XCTAssertEqual(values.toGridConfig().config.hudCornerRadius, 10, "out-of-range falls back to the default")

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)
        XCTAssertEqual(reread.hudCornerRadius, 99)
        XCTAssertEqual(reread.toGridConfig().config.hudCornerRadius, 10)
    }

    func testHUDAnimationDefaultsAndRoundTrips() {
        XCTAssertTrue(GridConfig.default.hudAnimationsEnabled)
        XCTAssertEqual(GridConfig.default.hudAnimationStyle, .natural)
        XCTAssertEqual(GridConfig.default.hudEntranceStyle, .fade)
        var values = ConfigValues()
        values.hudAnimationsEnabled = false
        values.hudAnimationStyle = .springy
        values.hudEntranceStyle = .slideFromLeft
        let grid = values.toGridConfig().config
        XCTAssertFalse(grid.hudAnimationsEnabled)
        XCTAssertEqual(grid.hudAnimationStyle, .springy)
        XCTAssertEqual(grid.hudEntranceStyle, .slideFromLeft)
    }

    func testHUDInteractionFeedbackDefaultsOnAndRoundTrips() {
        XCTAssertTrue(GridConfig.default.showHUDInteractionFeedback)
        var values = ConfigValues(from: GridConfig.default)
        XCTAssertEqual(values.showHUDInteractionFeedback, true)
        values.showHUDInteractionFeedback = false
        values.showThumbnailWallpaper = true
        values.hudAnimationsEnabled = true
        values.hudAnimationStyle = .natural
        XCTAssertFalse(values.toGridConfig().config.showHUDInteractionFeedback)
    }

    func testSpaceDropModeDefaultsToContentAndRoundTrips() {
        XCTAssertEqual(GridConfig.default.spaceDropMode, .content)
        XCTAssertEqual(GridConfig.default.spaceDragFocus, .stay)
        XCTAssertEqual(GridConfig.default.windowDragFocus, .destination)
        var values = ConfigValues(from: GridConfig.default)
        XCTAssertEqual(values.spaceDropMode, .content)
        values.spaceDropMode = .spaces
        values.spaceDragFocus = .destination
        values.windowDragFocus = .stay
        let grid = values.toGridConfig().config
        XCTAssertEqual(grid.spaceDropMode, .spaces)
        XCTAssertEqual(grid.spaceDragFocus, .destination)
        XCTAssertEqual(grid.windowDragFocus, .stay)
    }

    func testHUDIconSourceDefaultsNativeAndRoundTrips() {
        XCTAssertEqual(GridConfig.default.hudIconSource, .nativeIcons)
        var values = ConfigValues(from: GridConfig.default)
        XCTAssertEqual(values.hudIconSource, .nativeIcons)
        values.hudIconSource = .sbarFont
        XCTAssertEqual(values.toGridConfig().config.hudIconSource, .sbarFont)
    }

    func testSeparateIconStripSourceDefaultsOffAndResolves() {
        XCTAssertFalse(GridConfig.default.hudIconStripSeparate)
        var config = GridConfig.default
        config.hudIconSource = .sbarFont
        XCTAssertEqual(config.resolvedHUDIconStripSource, .sbarFont)

        var values = ConfigValues(from: GridConfig.default)
        values.hudIconStripSeparate = true
        values.hudIconStripSource = .sbarFont
        let resolved = values.toGridConfig().config
        XCTAssertTrue(resolved.hudIconStripSeparate)
        XCTAssertEqual(resolved.resolvedHUDIconStripSource, .sbarFont)
        XCTAssertEqual(resolved.hudIconSource, .nativeIcons, "cell icons keep their own source")
    }

    func testPresenceDefaultsAndRoundTrips() {
        XCTAssertEqual(GridConfig.default.presence, .menuBar)
        var values = ConfigValues(from: GridConfig.default)
        XCTAssertEqual(values.presence, .menuBar)
        values.presence = .both
        XCTAssertEqual(values.toGridConfig().config.presence, .both)

        XCTAssertTrue(AppPresence.dock.showsDock)
        XCTAssertFalse(AppPresence.dock.showsMenuBar)
        XCTAssertTrue(AppPresence.both.showsDock)
        XCTAssertTrue(AppPresence.both.showsMenuBar)
        XCTAssertFalse(AppPresence.none.showsDock)
        XCTAssertFalse(AppPresence.none.showsMenuBar)
    }

    func testNewMaterialAndShapeKeysRoundTripThroughTheConfigString() throws {
        var values = ConfigValues()
        var strip = GlyphStripConfig.default
        strip.backgroundMaterial = .liquidGlass
        strip.shape = .bar
        values.glyphStrip = strip

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)

        XCTAssertEqual(reread.glyphStrip?.backgroundMaterial, .liquidGlass)
        XCTAssertEqual(reread.glyphStrip?.shape, .bar)
    }

    func testToGridConfigClampsGlyphStripNumbersAndFlagsRepair() {
        var values = ConfigValues(from: .default)
        var strip = GlyphStripConfig.default
        values.glyphStrip = strip
        XCTAssertFalse(values.toGridConfig().needsRepair, "a valid strip must not request repair")

        strip.iconSize = 100
        strip.backgroundOpacity = -2
        strip.maxIconsPerSpace = -1
        values.glyphStrip = strip

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair, "out-of-range strip values must request repair")
        XCTAssertEqual(config.glyphStrip.iconSize, 24)
        XCTAssertEqual(config.glyphStrip.backgroundOpacity, 0.01)
        XCTAssertEqual(config.glyphStrip.maxIconsPerSpace, 0)

        values.glyphStrip = GlyphStripConfig.default
        XCTAssertFalse(values.toGridConfig().needsRepair, "repair must clear once the strip is valid")
    }

    func testToGridConfigWithMissingFieldsUsesDefaults() {
        var values = ConfigValues()
        values.cols = 5
        values.rows = nil
        values.cellStyle = nil
        values.theme = nil
        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, 5)
        XCTAssertEqual(config.rows, GridConfig.default.rows)
        XCTAssertEqual(config.cellStyle, GridConfig.default.cellStyle)
        XCTAssertEqual(config.theme, GridConfig.default.theme)
    }

    func testToGridConfigClampsInvalidValuesToDefaults() {
        var values = ConfigValues()
        values.cols = 0
        values.rows = -1
        values.maxSpaces = 99
        values.backgroundAlpha = 2.0
        values.iconScale = -1.0
        values.uiScale = 5.0
        values.autoHideTimeout = -1
        values.menuBarNearbyCount = 99

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, GridConfig.default.cols)
        XCTAssertEqual(config.rows, GridConfig.default.rows)
        XCTAssertEqual(config.maxSpaces, GridConfig.default.maxSpaces)
        XCTAssertEqual(config.backgroundAlpha, GridConfig.default.backgroundAlpha)
        XCTAssertEqual(config.iconScale, GridConfig.default.iconScale)
        XCTAssertEqual(config.uiScale, GridConfig.default.uiScale)
        XCTAssertEqual(config.autoHideTimeout, GridConfig.default.autoHideTimeout)
        XCTAssertEqual(config.menuBarNearbyCount, 16)
    }

    func testToGridConfigClampsOversizedColsAndRows() {
        var values = ConfigValues()
        values.cols = Int.max
        values.rows = 100

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, 32)
        XCTAssertEqual(config.rows, 32)
        // Exact geometry for a clamped 32-column grid at uiScale 0.5.
        let size = GridLayout.idealSize(visibleIndices: 16, cols: config.cols, uiScale: 0.5)
        XCTAssertEqual(size.width, 3136.5, accuracy: 0.001)
        XCTAssertEqual(size.height, 166.5, accuracy: 0.001)
    }

    func testToGridConfigWithEmptyConfigReturnsDefaults() {
        let values = ConfigValues()
        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, GridConfig.default.cols)
        XCTAssertEqual(config.rows, GridConfig.default.rows)
        XCTAssertEqual(config.cellStyle, GridConfig.default.cellStyle)
        XCTAssertEqual(config.theme, GridConfig.default.theme)
        XCTAssertEqual(config.showMode, GridConfig.default.showMode)
        XCTAssertEqual(config.hotkey.keyCode, GridConfig.default.hotkey.keyCode)
        XCTAssertEqual(config.glyphStripHotkey, GridConfig.default.glyphStripHotkey,
                       "old configs without the key load with the strip hotkey unbound")
    }

    func testUseExtendedKeysRoundTripsAndDefaultsTrueWhenMissing() throws {
        var values = ConfigValues()
        values.useExtendedKeys = false

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)

        XCTAssertEqual(reread.useExtendedKeys, false)

        let defaults = ConfigValues()
        let (config, needsRepair) = defaults.toGridConfig()

        XCTAssertTrue(config.useExtendedKeys, "old configs without the key load with extended keys enabled")
        XCTAssertTrue(needsRepair, "the nil key should flag repair so the file is rewritten, like its siblings")
    }

    func testGlyphStripHotkeyRoundTripsThroughTheConfigString() throws {
        var values = ConfigValues()
        values.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: [.maskCommand, .maskShift])
        values.hudMoveSpaceBackHotkey = HotkeyConfig(key: .keyCode(101), modifiers: [.maskCommand, .maskShift])
        values.hudMoveSpaceForwardHotkey = HotkeyConfig(key: .keyCode(102), modifiers: [.maskCommand, .maskShift])
        values.hudNewSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.hudDeleteSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.hudCycleLayoutHotkey = HotkeyConfig(key: .none, modifiers: [])


        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)

        XCTAssertEqual(reread.glyphStripHotkey, values.glyphStripHotkey)
    }
}
