import Foundation
import CoreGraphics

struct ConfigValues {
    var cols: Int?
    var rows: Int?
    var cellStyle: CellStyle?
    var hotkey: HotkeyConfig?
    var pinnedHotkey: HotkeyConfig?
    var glyphStripHotkey: HotkeyConfig?
    var socketHealthInterval: Int?
    var uiScale: Double?
    var autoHideTimeout: Int?
    var theme: String?
    var showMode: ShowMode?
    var multiMonitorHUDMode: MultiMonitorHUDMode?
    var unifiedHUDVisibility: SeparateHUDVisibility?
    var separateHUDVisibility: SeparateHUDVisibility?
    var displayNavigationWrap: DisplayNavigationWrap?
    var maxSpaces: Int?
    var backgroundAlpha: Double?
    var backgroundStyle: HUDBackgroundStyle?
    var glassStyle: HUDGlassStyle?
    var glassClearVariant: Int?
    var glassRegularVariant: Int?
    var glassTintedVariant: Int?
    var glassTintedMaterial: HUDGlassMaterial?
    var glassClearOpacity: Double?
    var glassRegularOpacity: Double?
    var glassTintedOpacity: Double?
    var solidOpacity: Double?
    var matchBackgroundOpacity: Bool?
    var hudShadow: Bool?
    var hudCornerRadius: Double?
    var spacesMatchBackground: Bool?
    var spacesBackgroundStyle: SpacesBackgroundStyle?
    var spacesGlassStyle: HUDGlassStyle?
    var spacesGlassClearVariant: Int?
    var spacesGlassRegularVariant: Int?
    var spacesGlassTintedVariant: Int?
    var spacesGlassTintedMaterial: HUDGlassMaterial?
    var spacesOpacity: Double?
    var spacesCornerRadius: Double?
    var mode: ThemeMode?
    var iconScale: Double?
    var showSpaceNumbers: Bool?
    var showSpaceLayout: Bool?
    var showSpaceNames: Bool?
    var showIconStrip: Bool?
    var showMultiAppIcons: Bool?
    var presence: AppPresence?
    var glyphStrip: GlyphStripConfig?
    var menuBarDisplayMode: MenuBarDisplayMode?
    var menuBarNearbyCount: Int?
    var spaceNames: [Int: String]?
    var useVimKeys: Bool?
    var useArrowKeys: Bool?
    var useExtendedKeys: Bool?
    var jumpToSpaceEnabled: Bool?
    var hudPosition: HUDPosition?
    var customHUDX: Double?
    var customHUDY: Double?
    var showExtraWindows: Bool?
    var focusSpaceOnWindowDrop: WindowDropFocusMode?
    var focusSpaceOnWindowDropModifier: WindowDropFocusModifier?
    var showHUDOnSpaceChange: Bool?
    var showBSPLayoutBadge: Bool?
    var showStackLayoutBadge: Bool?
    var showFloatLayoutBadge: Bool?
    var showHUDInteractionFeedback: Bool?
    var showThumbnailWallpaper: Bool?
    var hudAnimationsEnabled: Bool?
    var hudAnimationStyle: HUDAnimationStyle?
    var updateMode: UpdateMode?
    var appFont: AppFontConfig?
    var refuseUntrustedYabai: Bool?
    var hasInvalidSpaceNames = false

    /// Space name profiles
    var spaceNameProfiles: [SpaceNameProfile]?
    var activeSpaceNameProfileIndex: Int?

    init() {}

    init(from config: GridConfig) {
        self.cols = config.cols
        self.rows = config.rows
        self.cellStyle = config.cellStyle
        self.hotkey = config.hotkey
        self.pinnedHotkey = config.pinnedHotkey
        self.glyphStripHotkey = config.glyphStripHotkey
        self.socketHealthInterval = config.socketHealthInterval
        self.uiScale = config.uiScale
        self.autoHideTimeout = config.autoHideTimeout
        self.theme = config.theme
        self.showMode = config.showMode
        self.multiMonitorHUDMode = config.multiMonitorHUDMode
        self.unifiedHUDVisibility = config.unifiedHUDVisibility
        self.separateHUDVisibility = config.separateHUDVisibility
        self.displayNavigationWrap = config.displayNavigationWrap
        self.maxSpaces = config.maxSpaces
        self.backgroundAlpha = config.backgroundAlpha
        self.backgroundStyle = config.backgroundStyle
        self.glassStyle = config.glassStyle
        self.glassClearVariant = config.glassClearVariant
        self.glassRegularVariant = config.glassRegularVariant
        self.glassTintedVariant = config.glassTintedVariant
        self.glassTintedMaterial = config.glassTintedMaterial
        self.glassClearOpacity = config.glassClearOpacity
        self.glassRegularOpacity = config.glassRegularOpacity
        self.glassTintedOpacity = config.glassTintedOpacity
        self.solidOpacity = config.solidOpacity
        self.matchBackgroundOpacity = config.matchBackgroundOpacity
        self.hudShadow = config.hudShadow
        self.hudCornerRadius = config.hudCornerRadius
        self.spacesMatchBackground = config.spacesMatchBackground
        self.spacesBackgroundStyle = config.spacesBackgroundStyle
        self.spacesGlassStyle = config.spacesGlassStyle
        self.spacesGlassClearVariant = config.spacesGlassClearVariant
        self.spacesGlassRegularVariant = config.spacesGlassRegularVariant
        self.spacesGlassTintedVariant = config.spacesGlassTintedVariant
        self.spacesGlassTintedMaterial = config.spacesGlassTintedMaterial
        self.spacesOpacity = config.spacesOpacity
        self.spacesCornerRadius = config.spacesCornerRadius
        self.mode = config.mode
        self.iconScale = config.iconScale
        self.showSpaceNumbers = config.showSpaceNumbers
        self.showSpaceLayout = config.showSpaceLayout
        self.showSpaceNames = config.showSpaceNames
        self.showIconStrip = config.showIconStrip
        self.showMultiAppIcons = config.showMultiAppIcons
        self.presence = config.presence
        self.glyphStrip = config.glyphStrip
        self.menuBarDisplayMode = config.menuBarDisplayMode
        self.menuBarNearbyCount = config.menuBarNearbyCount
        self.spaceNames = config.spaceNames
        self.useVimKeys = config.useVimKeys
        self.useArrowKeys = config.useArrowKeys
        self.useExtendedKeys = config.useExtendedKeys
        self.jumpToSpaceEnabled = config.jumpToSpaceEnabled
        self.hudPosition = config.hudPosition
        self.customHUDX = config.customHUDX
        self.customHUDY = config.customHUDY
        self.showExtraWindows = config.showExtraWindows
        self.focusSpaceOnWindowDrop = config.focusSpaceOnWindowDrop
        self.focusSpaceOnWindowDropModifier = config.focusSpaceOnWindowDropModifier
        self.showHUDOnSpaceChange = config.showHUDOnSpaceChange
        self.showBSPLayoutBadge = config.showBSPLayoutBadge
        self.showStackLayoutBadge = config.showStackLayoutBadge
        self.showFloatLayoutBadge = config.showFloatLayoutBadge
        self.showHUDInteractionFeedback = config.showHUDInteractionFeedback
        self.showThumbnailWallpaper = config.showThumbnailWallpaper
        self.hudAnimationsEnabled = config.hudAnimationsEnabled
        self.hudAnimationStyle = config.hudAnimationStyle
        self.updateMode = config.updateMode
        self.appFont = config.appFont
        self.refuseUntrustedYabai = config.refuseUntrustedYabai
        self.spaceNameProfiles = config.spaceNameProfiles
        self.activeSpaceNameProfileIndex = config.activeSpaceNameProfileIndex
    }

    func toGridConfig() -> (config: GridConfig, needsRepair: Bool) {
        let defaults = GridConfig.default
        var needsRepair = hasInvalidSpaceNames

        func orDefault<T>(_ value: T?, _ default: T) -> T {
            if value == nil { needsRepair = true }
            return value ?? `default`
        }

        func valid<T>(_ value: T?, _ default: T, where predicate: (T) -> Bool) -> T {
            guard let value, predicate(value) else {
                needsRepair = true
                return `default`
            }
            return value
        }

        func oversizeClamped<T: Comparable>(_ value: T?, _ default: T, in range: ClosedRange<T>) -> T {
            guard let value else {
                needsRepair = true
                return `default`
            }
            if value < range.lowerBound {
                needsRepair = true
                return `default`
            }
            if value > range.upperBound {
                needsRepair = true
                return range.upperBound
            }
            return value
        }

        let resolvedCellStyle = orDefault(cellStyle, defaults.cellStyle)
        let resolvedBackgroundStyle = orDefault(backgroundStyle, defaults.backgroundStyle)
        let resolvedGlassStyle = orDefault(glassStyle, defaults.glassStyle)
        let resolvedClearVariant = min(max(glassClearVariant ?? defaults.glassClearVariant, 0), 21)
        let resolvedRegularVariant = min(max(glassRegularVariant ?? defaults.glassRegularVariant, 0), 21)
        let resolvedTintedVariant = min(max(glassTintedVariant ?? defaults.glassTintedVariant, 0), 21)
        let resolvedGlassTintedMaterial = glassTintedMaterial ?? defaults.glassTintedMaterial
        let resolvedBackgroundAlpha = valid(backgroundAlpha, defaults.backgroundAlpha) { (0...1).contains($0) }
        // Per-style keys are new: absent values inherit `backgroundAlpha` so
        // older configs keep their look without triggering a repair. Clear used
        // to be painted at 15% of its value, so inherit that effective share.
        let legacyClearOpacity = resolvedBackgroundAlpha * 0.15
        let resolvedGlassClearOpacity = valid(
            glassClearOpacity ?? legacyClearOpacity, defaults.glassClearOpacity
        ) { (0...1).contains($0) }
        let resolvedGlassRegularOpacity = valid(
            glassRegularOpacity ?? resolvedBackgroundAlpha, resolvedBackgroundAlpha
        ) { (0...1).contains($0) }
        let resolvedGlassTintedOpacity = valid(
            glassTintedOpacity ?? resolvedBackgroundAlpha, resolvedBackgroundAlpha
        ) { (0...1).contains($0) }
        let resolvedSolidOpacity = valid(
            solidOpacity ?? resolvedBackgroundAlpha, resolvedBackgroundAlpha
        ) { (0...1).contains($0) }
        let resolvedShowMode = orDefault(showMode, defaults.showMode)
        let resolvedMultiMonitorMode = orDefault(multiMonitorHUDMode, defaults.multiMonitorHUDMode)
        let resolvedUnifiedVisibility = orDefault(unifiedHUDVisibility, defaults.unifiedHUDVisibility)
        let resolvedSeparateVisibility = orDefault(separateHUDVisibility, defaults.separateHUDVisibility)
        let resolvedNavigationWrap = orDefault(displayNavigationWrap, defaults.displayNavigationWrap)
        let resolvedThemeMode = orDefault(mode, defaults.mode)
        let resolvedUpdateMode = orDefault(updateMode, defaults.updateMode)
        let resolvedMenuBarDisplayMode = orDefault(menuBarDisplayMode, defaults.menuBarDisplayMode)
        let resolvedWindowDropFocusMode = orDefault(focusSpaceOnWindowDrop, defaults.focusSpaceOnWindowDrop)
        let resolvedWindowDropModifier = orDefault(focusSpaceOnWindowDropModifier, defaults.focusSpaceOnWindowDropModifier)

        let resolvedHotkey = orDefault(hotkey, defaults.hotkey)
        let resolvedPinnedHotkey = orDefault(pinnedHotkey, defaults.pinnedHotkey)
        let resolvedGlyphStripHotkey = orDefault(glyphStripHotkey, defaults.glyphStripHotkey)

        let resolvedHudPosition: HUDPosition
        switch hudPosition {
        case .center, .top, .bottom, .custom:
            resolvedHudPosition = hudPosition ?? defaults.hudPosition
        case nil:
            resolvedHudPosition = defaults.hudPosition
            needsRepair = true
        }

        var resolvedSpaceNameProfiles = spaceNameProfiles ?? defaults.spaceNameProfiles
        if resolvedSpaceNameProfiles.isEmpty {
            resolvedSpaceNameProfiles = defaults.spaceNameProfiles
            needsRepair = true
        }
        var resolvedActiveProfileIndex = activeSpaceNameProfileIndex ?? defaults.activeSpaceNameProfileIndex
        if !(0..<resolvedSpaceNameProfiles.count).contains(resolvedActiveProfileIndex) {
            resolvedActiveProfileIndex = 0
            needsRepair = true
        }

        let rawStrip = orDefault(glyphStrip, defaults.glyphStrip)
        let clampedStrip = rawStrip.clamped()
        if clampedStrip != rawStrip {
            needsRepair = true
        }

        let config = GridConfig(
            // Upper bound keeps `GridLayout.idealSize` arithmetic (visible +
            // cols - 1) away from `Int` overflow on a hand-edited `cols`.
            cols: oversizeClamped(cols, defaults.cols, in: 1...32),
            rows: oversizeClamped(rows, defaults.rows, in: 1...32),
            cellStyle: resolvedCellStyle,
            hotkey: resolvedHotkey,
            pinnedHotkey: resolvedPinnedHotkey,
            glyphStripHotkey: resolvedGlyphStripHotkey,
            socketHealthInterval: oversizeClamped(socketHealthInterval, defaults.socketHealthInterval, in: 1...3600),
            uiScale: valid(uiScale, defaults.uiScale) { (0...1).contains($0) },
            autoHideTimeout: valid(autoHideTimeout, defaults.autoHideTimeout) { $0 >= 0 },
            theme: orDefault(theme, defaults.theme),
            showMode: resolvedShowMode,
            multiMonitorHUDMode: resolvedMultiMonitorMode,
            unifiedHUDVisibility: resolvedUnifiedVisibility,
            separateHUDVisibility: resolvedSeparateVisibility,
            displayNavigationWrap: resolvedNavigationWrap,
            maxSpaces: oversizeClamped(maxSpaces, defaults.maxSpaces, in: 1...16),
            backgroundAlpha: resolvedBackgroundAlpha,
            backgroundStyle: resolvedBackgroundStyle,
            glassStyle: resolvedGlassStyle,
            glassClearVariant: resolvedClearVariant,
            glassRegularVariant: resolvedRegularVariant,
            glassTintedVariant: resolvedTintedVariant,
            glassTintedMaterial: resolvedGlassTintedMaterial,
            glassClearOpacity: resolvedGlassClearOpacity,
            glassRegularOpacity: resolvedGlassRegularOpacity,
            glassTintedOpacity: resolvedGlassTintedOpacity,
            solidOpacity: resolvedSolidOpacity,
            spacesMatchBackground: spacesMatchBackground ?? defaults.spacesMatchBackground,
            spacesBackgroundStyle: spacesBackgroundStyle ?? defaults.spacesBackgroundStyle,
            spacesGlassStyle: spacesGlassStyle ?? defaults.spacesGlassStyle,
            spacesGlassClearVariant: min(max(spacesGlassClearVariant ?? defaults.spacesGlassClearVariant, 0), 21),
            spacesGlassRegularVariant: min(max(spacesGlassRegularVariant ?? defaults.spacesGlassRegularVariant, 0), 21),
            spacesGlassTintedVariant: min(max(spacesGlassTintedVariant ?? defaults.spacesGlassTintedVariant, 0), 21),
            spacesGlassTintedMaterial: spacesGlassTintedMaterial ?? defaults.spacesGlassTintedMaterial,
            spacesOpacity: min(max(spacesOpacity ?? defaults.spacesOpacity, 0), 1),
            spacesCornerRadius: min(max(spacesCornerRadius ?? defaults.spacesCornerRadius, 0), 60),
            matchBackgroundOpacity: matchBackgroundOpacity ?? defaults.matchBackgroundOpacity,
            hudShadow: orDefault(hudShadow, defaults.hudShadow),
            hudCornerRadius: valid(hudCornerRadius, defaults.hudCornerRadius) { (0...60).contains($0) },
            mode: resolvedThemeMode,
            iconScale: valid(iconScale, defaults.iconScale) { (0...1).contains($0) },
            showSpaceNumbers: orDefault(showSpaceNumbers, defaults.showSpaceNumbers),
            showSpaceLayout: orDefault(showSpaceLayout, defaults.showSpaceLayout),
            showSpaceNames: orDefault(showSpaceNames, defaults.showSpaceNames),
            showIconStrip: orDefault(showIconStrip, defaults.showIconStrip),
            showMultiAppIcons: orDefault(showMultiAppIcons, defaults.showMultiAppIcons),
            presence: orDefault(presence, defaults.presence),
            glyphStrip: clampedStrip,
            menuBarDisplayMode: resolvedMenuBarDisplayMode,
            menuBarNearbyCount: oversizeClamped(menuBarNearbyCount, defaults.menuBarNearbyCount, in: 1...16),
            spaceNames: spaceNames ?? defaults.spaceNames,
            useVimKeys: orDefault(useVimKeys, defaults.useVimKeys),
            useArrowKeys: orDefault(useArrowKeys, defaults.useArrowKeys),
            useExtendedKeys: orDefault(useExtendedKeys, defaults.useExtendedKeys),
            jumpToSpaceEnabled: orDefault(jumpToSpaceEnabled, defaults.jumpToSpaceEnabled),
            hudPosition: resolvedHudPosition,
            customHUDX: valid(customHUDX, defaults.customHUDX) { (0...1).contains($0) },
            customHUDY: valid(customHUDY, defaults.customHUDY) { (0...1).contains($0) },
            showExtraWindows: orDefault(showExtraWindows, defaults.showExtraWindows),
            focusSpaceOnWindowDrop: resolvedWindowDropFocusMode,
            focusSpaceOnWindowDropModifier: resolvedWindowDropModifier,
            showHUDOnSpaceChange: orDefault(showHUDOnSpaceChange, defaults.showHUDOnSpaceChange),
            showBSPLayoutBadge: orDefault(showBSPLayoutBadge, defaults.showBSPLayoutBadge),
            showStackLayoutBadge: orDefault(showStackLayoutBadge, defaults.showStackLayoutBadge),
            showFloatLayoutBadge: orDefault(showFloatLayoutBadge, defaults.showFloatLayoutBadge),
            showHUDInteractionFeedback: orDefault(showHUDInteractionFeedback, defaults.showHUDInteractionFeedback),
            showThumbnailWallpaper: orDefault(showThumbnailWallpaper, defaults.showThumbnailWallpaper),
            hudAnimationsEnabled: orDefault(hudAnimationsEnabled, defaults.hudAnimationsEnabled),
            hudAnimationStyle: hudAnimationStyle ?? defaults.hudAnimationStyle,
            updateMode: resolvedUpdateMode,
            appFont: orDefault(appFont, defaults.appFont),
            // New flag: absent in old files heals silently without forcing a
            // config rewrite (keeps all-fields-set tests repair-free).
            refuseUntrustedYabai: refuseUntrustedYabai ?? defaults.refuseUntrustedYabai,
            spaceNameProfiles: resolvedSpaceNameProfiles,
            activeSpaceNameProfileIndex: resolvedActiveProfileIndex
        )
        return (config, needsRepair)
    }

    var gridConfig: GridConfig {
        toGridConfig().config
    }
}
