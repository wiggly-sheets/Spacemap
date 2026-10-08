import Foundation
import CoreGraphics

struct ConfigValues: ConfigValuesProtocol {
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
    var hudShadow: Bool?
    var mode: ThemeMode?
    var iconScale: Double?
    var showSpaceNumbers: Bool?
    var showSpaceNames: Bool?
    var showIconStrip: Bool?
    var showMultiAppIcons: Bool?
    var hideMenuBarIcon: Bool?
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
    var updateMode: UpdateMode?
    var appFont: AppFontConfig?
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
        self.hudShadow = config.hudShadow
        self.mode = config.mode
        self.iconScale = config.iconScale
        self.showSpaceNumbers = config.showSpaceNumbers
        self.showSpaceNames = config.showSpaceNames
        self.showIconStrip = config.showIconStrip
        self.showMultiAppIcons = config.showMultiAppIcons
        self.hideMenuBarIcon = config.hideMenuBarIcon
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
        self.updateMode = config.updateMode
        self.appFont = config.appFont
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
            cols: valid(cols, defaults.cols) { $0 > 0 },
            rows: valid(rows, defaults.rows) { $0 > 0 },
            cellStyle: resolvedCellStyle,
            hotkey: resolvedHotkey,
            pinnedHotkey: resolvedPinnedHotkey,
            glyphStripHotkey: resolvedGlyphStripHotkey,
            socketHealthInterval: valid(socketHealthInterval, defaults.socketHealthInterval) { $0 > 0 },
            uiScale: valid(uiScale, defaults.uiScale) { (0...1).contains($0) },
            autoHideTimeout: valid(autoHideTimeout, defaults.autoHideTimeout) { $0 >= 0 },
            theme: orDefault(theme, defaults.theme),
            showMode: resolvedShowMode,
            multiMonitorHUDMode: resolvedMultiMonitorMode,
            unifiedHUDVisibility: resolvedUnifiedVisibility,
            separateHUDVisibility: resolvedSeparateVisibility,
            displayNavigationWrap: resolvedNavigationWrap,
            maxSpaces: oversizeClamped(maxSpaces, defaults.maxSpaces, in: 1...16),
            backgroundAlpha: valid(backgroundAlpha, defaults.backgroundAlpha) { (0...1).contains($0) },
            hudShadow: orDefault(hudShadow, defaults.hudShadow),
            mode: resolvedThemeMode,
            iconScale: valid(iconScale, defaults.iconScale) { (0...1).contains($0) },
            showSpaceNumbers: orDefault(showSpaceNumbers, defaults.showSpaceNumbers),
            showSpaceNames: orDefault(showSpaceNames, defaults.showSpaceNames),
            showIconStrip: orDefault(showIconStrip, defaults.showIconStrip),
            showMultiAppIcons: orDefault(showMultiAppIcons, defaults.showMultiAppIcons),
            hideMenuBarIcon: orDefault(hideMenuBarIcon, defaults.hideMenuBarIcon),
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
            updateMode: resolvedUpdateMode,
            appFont: orDefault(appFont, defaults.appFont),
            spaceNameProfiles: resolvedSpaceNameProfiles,
            activeSpaceNameProfileIndex: resolvedActiveProfileIndex
        )
        return (config, needsRepair)
    }

    var gridConfig: GridConfig {
        toGridConfig().config
    }
}
