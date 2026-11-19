import XCTest
@testable import spacemap

final class ConfigSchemaTests: XCTestCase {

    private func decoded(_ toml: String) throws -> (config: SpacemapConfig, needsRepair: Bool) {
        try TOMLParser.parse(toml)
    }

    private func written(_ config: SpacemapConfig) -> String {
        ConfigLoader.tomlConfigString(from: config, includeHeaderComments: false)
    }

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
        config.spaceNames = [1: "Term", 2: "Code"]
        config.hudKeys = .default
        config.jumpToSpaceEnabled = true
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
        XCTAssertEqual(decoded.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertEqual(decoded.hudKeys, HUDKeyBindings.default)
        XCTAssertTrue(decoded.jumpToSpaceEnabled)
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

    func testNewMaterialAndShapeKeysRoundTripThroughTheConfigString() throws {
        var config = SpacemapConfig.default
        config.glyphStrip.backgroundMaterial = .liquidGlass
        config.glyphStrip.shape = .bar

        let reread = try decoded(written(config)).config

        XCTAssertEqual(reread.glyphStrip.backgroundMaterial, .liquidGlass)
        XCTAssertEqual(reread.glyphStrip.shape, .bar)
    }

    func testGlyphStripNumbersClampAndFlagRepair() throws {
        XCTAssertFalse(try decoded(written(SpacemapConfig.default)).needsRepair,
                       "a valid strip must not request repair")

        let toml = written(SpacemapConfig.default)
            .replacingOccurrences(of: "maxIconsPerSpace = 8", with: "maxIconsPerSpace = -1")
            .replacingOccurrences(of: "iconSize = 11", with: "iconSize = 100")
            .replacingOccurrences(of: "backgroundOpacity = 0.35", with: "backgroundOpacity = -2")
        let (config, needsRepair) = try decoded(toml)

        XCTAssertTrue(needsRepair, "out-of-range strip values must request repair")
        XCTAssertEqual(config.glyphStrip.iconSize, 24)
        XCTAssertEqual(config.glyphStrip.backgroundOpacity, 0.01)
        XCTAssertEqual(config.glyphStrip.maxIconsPerSpace, 0)
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

    func testHUDKeysRoundTripAndDefaultWhenMissing() throws {
        var config = SpacemapConfig.default
        var keys = HUDKeyBindings.default
        keys[.left] = [HotkeyConfig(key: .keyCode(7), modifiers: [])]
        config.hudKeys = keys

        let reread = try decoded(written(config)).config

        XCTAssertEqual(reread.hudKeys, keys)

        let (defaults, needsRepair) = try decoded("[grid]\n")

        XCTAssertEqual(defaults.hudKeys, HUDKeyBindings.default, "old configs without the table load with vim and arrow keys")
        XCTAssertTrue(needsRepair, "the missing table should flag repair so the file is rewritten, like its siblings")
    }

    func testNewHUDCommandsAreWrittenAndRoundTrip() throws {
        var config = SpacemapConfig.default
        var keys = HUDKeyBindings.default
        keys[.moveSpaceBack] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+f13"))]
        keys[.moveSpaceForward] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+f14"))]
        keys[.cycleLayout] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+f15"))]
        config.hudKeys = keys

        let toml = written(config)

        XCTAssertTrue(toml.contains("moveSpaceBack = [\"ctrl+"))
        XCTAssertTrue(toml.contains("moveSpaceForward = [\"ctrl+"))
        XCTAssertTrue(toml.contains("cycleLayout = [\"ctrl+"))

        let reread = try decoded(toml).config
        XCTAssertEqual(reread.hudKeys[.moveSpaceBack], keys[.moveSpaceBack])
        XCTAssertEqual(reread.hudKeys[.moveSpaceForward], keys[.moveSpaceForward])
        XCTAssertEqual(reread.hudKeys[.cycleLayout], keys[.cycleLayout])
    }

    func testDefaultHUDKeyTableWritesTheNewCommandsUnbound() {
        let toml = written(SpacemapConfig.default)

        XCTAssertTrue(toml.contains("moveSpaceBack = []"),
                      "a fresh file names the new commands with empty bindings")
        XCTAssertTrue(toml.contains("moveSpaceForward = []"))
        XCTAssertTrue(toml.contains("cycleLayout = []"))
    }

    /// A config file written before these action names existed still loads:
    /// unknown actions are skipped and the rest of the table is kept.
    func testOlderHUDFilesWithoutNewActionsLoadWithThemUnbound() throws {
        let toml = written(SpacemapConfig.default)
            .replacingOccurrences(of: "moveSpaceBack = []\n", with: "")
            .replacingOccurrences(of: "moveSpaceForward = []\n", with: "")
            .replacingOccurrences(of: "cycleLayout = []\n", with: "")

        let reread = try decoded(toml).config

        XCTAssertEqual(reread.hudKeys[.moveSpaceBack], [])
        XCTAssertEqual(reread.hudKeys[.moveSpaceForward], [])
        XCTAssertEqual(reread.hudKeys[.cycleLayout], [])
    }

    /// An action name the app does not know is ignored, and the file is not
    /// marked for repair, so a file from a newer build still loads.
    func testUnknownHUDActionIsIgnoredWithoutRepair() throws {
        let toml = written(SpacemapConfig.default)
            .replacingOccurrences(of: "layoutFloat = [\"u\"]\n",
                                  with: "layoutFloat = [\"u\"]\nbogusAction = [\"ctrl+q\"]\n")

        let (config, needsRepair) = try decoded(toml)

        XCTAssertFalse(needsRepair)
        XCTAssertNil(config.hudKeys.command(for: 12, flags: .maskControl),
                     "the unknown action must not bind its key")
        XCTAssertEqual(config.hudKeys, HUDKeyBindings.default,
                       "the rest of the table still decodes")
    }

    func testGlyphStripHotkeyRoundTripsThroughTheConfigString() throws {
        var config = SpacemapConfig.default
        config.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: [.maskCommand, .maskShift])
        config.hudMoveSpaceBackHotkey = HotkeyConfig(key: .keyCode(101), modifiers: [.maskCommand, .maskShift])
        config.hudMoveSpaceForwardHotkey = HotkeyConfig(key: .keyCode(102), modifiers: [.maskCommand, .maskShift])
        config.hudNewSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])
        config.hudDeleteSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])
        config.hudCycleLayoutHotkey = HotkeyConfig(key: .none, modifiers: [])

        let reread = try decoded(written(config)).config

        XCTAssertEqual(reread.glyphStripHotkey, config.glyphStripHotkey)
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

    func testDefaultConfigRoundTripsThroughTheWriterWithoutRepair() throws {
        let (config, needsRepair) = try decoded(written(SpacemapConfig.default))

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config, SpacemapConfig.default)
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

    func testHotkeyTableWithoutModifiersFallsBackToDefaultAndFlagsRepair() throws {
        let full = written(SpacemapConfig.default)
        let (config, needsRepair) = try decoded(
            full.replacingOccurrences(of: "modifiers = [\"ctrl\"]\n", with: "")
        )

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.hotkey, SpacemapConfig.default.hotkey)
    }

    func testInvalidCustomHUDPositionFallsBackToCenterAndFlagsRepair() throws {
        // Full default file, so the repair flag can only come from the broken
        // block swapped in below.
        let full = written(SpacemapConfig.default)
        let brokenBlock = """
        [behavior.hudPosition]
        kind = "custom"
        x = 2.0
        y = 0.75
        """
        let toml = full.replacingOccurrences(
            of: "[behavior.hudPosition]\nkind = \"center\"", with: brokenBlock
        )
        XCTAssertNotEqual(toml, full, "the default writer output must carry a hudPosition block to swap")

        let (config, needsRepair) = try decoded(toml)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.hudPosition, SpacemapConfig.default.hudPosition)
    }

    /// The screen identity rides in the same table as the fractions, so a
    /// custom position restores on the display it was dragged on.
    func testCustomHUDPositionScreenIdentityRoundTripsAndIsOptional() throws {
        var config = SpacemapConfig.default
        config.hudPosition = .custom(x: 0.4, y: 0.6, screen: "UUID-A")

        let (reread, needsRepair) = try decoded(written(config))

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reread.hudPosition, .custom(x: 0.4, y: 0.6, screen: "UUID-A"))

        // No display pairing: the key stays out of the file and decodes as nil.
        config.hudPosition = .custom(x: 0.4, y: 0.6, screen: nil)
        let (unpaired, unpairedRepair) = try decoded(written(config))
        XCTAssertFalse(unpairedRepair)
        XCTAssertEqual(unpaired.hudPosition, .custom(x: 0.4, y: 0.6, screen: nil))
        XCTAssertFalse(written(config).contains("\nscreen ="), "no screen key without an identity")
    }

    /// The scalar `customHUDX`/`customHUDY` keys died with the one-scheme
    /// change: a config that still has them loads clean and drops them on the
    /// next save (ADR 0001, no migration).
    func testLegacyCustomHUDKeysAreIgnored() throws {
        let full = written(SpacemapConfig.default)
        let toml = full.replacingOccurrences(
            of: "jumpToSpaceEnabled = false\n",
            with: "jumpToSpaceEnabled = false\ncustomHUDX = 0.9\ncustomHUDY = 0.1\n"
        )
        XCTAssertNotEqual(toml, full)

        let (config, needsRepair) = try decoded(toml)

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.hudPosition, SpacemapConfig.default.hudPosition)
        XCTAssertFalse(written(config).contains("customHUDX"))
    }

    /// The strip's old `xOffset`/`yOffset` keys are gone with the same fraction
    /// scheme: a config that still has them loads clean at the default custom
    /// fractions and drops them on the next save (ADR 0001, no migration).
    func testLegacyGlyphStripOffsetsAreIgnored() throws {
        let full = written(SpacemapConfig.default)
        let toml = full.replacingOccurrences(
            of: "[glyphStrip]\n",
            with: "[glyphStrip]\nxOffset = 120\nyOffset = -18.5\n"
        )
        XCTAssertNotEqual(toml, full)

        let (config, needsRepair) = try decoded(toml)

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.glyphStrip.customX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(config.glyphStrip.customY, 0.5, accuracy: 0.0001)
        XCTAssertFalse(written(config).contains("xOffset"))
    }


    /// Free strip placement uses the same fraction-plus-screen scheme as the
    /// HUD; out-of-range fractions clamp and flag a rewrite.
    func testGlyphStripCustomPlacementRoundTripsAndClamps() throws {
        var config = SpacemapConfig.default
        config.glyphStrip.position = .custom
        config.glyphStrip.customX = 0.25
        config.glyphStrip.customY = 0.75
        config.glyphStrip.customScreen = "UUID-A"

        let (reread, needsRepair) = try decoded(written(config))
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reread.glyphStrip.customX, 0.25, accuracy: 0.001)
        XCTAssertEqual(reread.glyphStrip.customY, 0.75, accuracy: 0.001)
        XCTAssertEqual(reread.glyphStrip.customScreen, "UUID-A")

        let clampedToml = written(config)
            .replacingOccurrences(of: "customX = 0.25", with: "customX = 4.0")
            .replacingOccurrences(of: "customY = 0.75", with: "customY = -1.0")
        let (clamped, clampedRepair) = try decoded(clampedToml)
        XCTAssertTrue(clampedRepair)
        XCTAssertEqual(clamped.glyphStrip.customX, 1)
        XCTAssertEqual(clamped.glyphStrip.customY, 0)
    }

    func testDisabledHUDKeyReencodesAsAnEmptyList() throws {
        var config = SpacemapConfig.default
        var keys = HUDKeyBindings.default
        keys[.left] = [HotkeyConfig(key: .none, modifiers: [])]
        config.hudKeys = keys

        let toml = written(config)
        XCTAssertTrue(toml.contains("left = []"))

        let reread = try decoded(toml).config
        XCTAssertEqual(reread.hudKeys[.left].isEmpty, true)
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
