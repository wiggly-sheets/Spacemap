import Foundation
import CoreGraphics

struct ConfigValues: ConfigValuesProtocol {
    var cols: Int?
    var rows: Int?
    var cellStyle: CellStyle?
    var hotkey: HotkeyConfig?
    var pinnedHotkey: HotkeyConfig?
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
    var mode: ThemeMode?
    var iconScale: Double?
    var showSpaceNumbers: Bool?
    var showSpaceNames: Bool?
    var showIconStrip: Bool?
    var showMultiAppIcons: Bool?
    var hideMenuBarIcon: Bool?
    var menuBarDisplayMode: MenuBarDisplayMode?
    var menuBarNearbyCount: Int?
    var spaceNames: [Int: String]?
    var useVimKeys: Bool?
    var useArrowKeys: Bool?
    var hudPosition: HUDPosition?
    var customHUDX: Double?
    var customHUDY: Double?
    var showExtraWindows: Bool?
    var focusSpaceOnWindowDrop: WindowDropFocusMode?
    var focusSpaceOnWindowDropModifier: WindowDropFocusModifier?
    var showHUDOnSpaceChange: Bool?
    var updateMode: UpdateMode?

    init() {}

    init(from config: GridConfig) {
        self.cols = config.cols
        self.rows = config.rows
        self.cellStyle = config.cellStyle
        self.hotkey = config.hotkey
        self.pinnedHotkey = config.pinnedHotkey
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
        self.mode = config.mode
        self.iconScale = config.iconScale
        self.showSpaceNumbers = config.showSpaceNumbers
        self.showSpaceNames = config.showSpaceNames
        self.showIconStrip = config.showIconStrip
        self.showMultiAppIcons = config.showMultiAppIcons
        self.hideMenuBarIcon = config.hideMenuBarIcon
        self.menuBarDisplayMode = config.menuBarDisplayMode
        self.menuBarNearbyCount = config.menuBarNearbyCount
        self.spaceNames = config.spaceNames
        self.useVimKeys = config.useVimKeys
        self.useArrowKeys = config.useArrowKeys
        self.hudPosition = config.hudPosition
        self.customHUDX = config.customHUDX
        self.customHUDY = config.customHUDY
        self.showExtraWindows = config.showExtraWindows
        self.focusSpaceOnWindowDrop = config.focusSpaceOnWindowDrop
        self.focusSpaceOnWindowDropModifier = config.focusSpaceOnWindowDropModifier
        self.showHUDOnSpaceChange = config.showHUDOnSpaceChange
        self.updateMode = config.updateMode
    }

    func toGridConfig() -> (config: GridConfig, needsRepair: Bool) {
        let defaults = GridConfig.default
        var needsRepair = false

        func orDefault<T>(_ value: T?, _ default: T) -> T {
            if value == nil { needsRepair = true }
            return value ?? `default`
        }

        func valid<T>(_ value: T?, _ default: T, where predicate: (T) -> Bool) -> T {
            guard let value, predicate(value) else {
                if value != nil { needsRepair = true }
                return `default`
            }
            return value
        }

        func double(_ value: Double?, _ default: Double) -> Double {
            guard let value else {
                needsRepair = true
                return `default`
            }
            return value
        }

        let resolvedCellStyle = cellStyle ?? defaults.cellStyle
        let resolvedShowMode = showMode ?? defaults.showMode
        let resolvedMultiMonitorMode = multiMonitorHUDMode ?? defaults.multiMonitorHUDMode
        let resolvedUnifiedVisibility = unifiedHUDVisibility ?? defaults.unifiedHUDVisibility
        let resolvedSeparateVisibility = separateHUDVisibility ?? defaults.separateHUDVisibility
        let resolvedNavigationWrap = displayNavigationWrap ?? defaults.displayNavigationWrap
        let resolvedThemeMode = mode ?? defaults.mode
        let resolvedUpdateMode = updateMode ?? defaults.updateMode
        let resolvedMenuBarDisplayMode = menuBarDisplayMode ?? defaults.menuBarDisplayMode
        let resolvedWindowDropFocusMode = focusSpaceOnWindowDrop ?? defaults.focusSpaceOnWindowDrop
        let resolvedWindowDropModifier = focusSpaceOnWindowDropModifier ?? defaults.focusSpaceOnWindowDropModifier

        let resolvedHotkey = hotkey ?? defaults.hotkey
        let resolvedPinnedHotkey = pinnedHotkey ?? defaults.pinnedHotkey

        let resolvedHudPosition: HUDPosition
        switch hudPosition {
        case .center, .top, .bottom, .custom:
            resolvedHudPosition = hudPosition ?? defaults.hudPosition
        case nil:
            resolvedHudPosition = defaults.hudPosition
            needsRepair = true
        }

        let config = GridConfig(
            cols: valid(cols, defaults.cols) { $0 > 0 },
            rows: valid(rows, defaults.rows) { $0 > 0 },
            cellStyle: resolvedCellStyle,
            hotkey: resolvedHotkey,
            pinnedHotkey: resolvedPinnedHotkey,
            socketHealthInterval: valid(socketHealthInterval, defaults.socketHealthInterval) { $0 > 0 },
            uiScale: valid(uiScale, defaults.uiScale) { (0...1).contains($0) },
            autoHideTimeout: valid(autoHideTimeout, defaults.autoHideTimeout) { $0 >= 0 },
            theme: orDefault(theme, defaults.theme),
            showMode: resolvedShowMode,
            multiMonitorHUDMode: resolvedMultiMonitorMode,
            unifiedHUDVisibility: resolvedUnifiedVisibility,
            separateHUDVisibility: resolvedSeparateVisibility,
            displayNavigationWrap: resolvedNavigationWrap,
            maxSpaces: valid(maxSpaces, defaults.maxSpaces) { (1...16).contains($0) },
            backgroundAlpha: valid(backgroundAlpha, defaults.backgroundAlpha) { (0...1).contains($0) },
            mode: resolvedThemeMode,
            iconScale: valid(iconScale, defaults.iconScale) { (0...1).contains($0) },
            showSpaceNumbers: orDefault(showSpaceNumbers, defaults.showSpaceNumbers),
            showSpaceNames: orDefault(showSpaceNames, defaults.showSpaceNames),
            showIconStrip: orDefault(showIconStrip, defaults.showIconStrip),
            showMultiAppIcons: orDefault(showMultiAppIcons, defaults.showMultiAppIcons),
            hideMenuBarIcon: orDefault(hideMenuBarIcon, defaults.hideMenuBarIcon),
            menuBarDisplayMode: resolvedMenuBarDisplayMode,
            menuBarNearbyCount: valid(menuBarNearbyCount, defaults.menuBarNearbyCount) { (1...16).contains($0) },
            spaceNames: spaceNames ?? defaults.spaceNames,
            useVimKeys: orDefault(useVimKeys, defaults.useVimKeys),
            useArrowKeys: orDefault(useArrowKeys, defaults.useArrowKeys),
            hudPosition: resolvedHudPosition,
            customHUDX: valid(customHUDX, defaults.customHUDX) { (0...1).contains($0) },
            customHUDY: valid(customHUDY, defaults.customHUDY) { (0...1).contains($0) },
            showExtraWindows: orDefault(showExtraWindows, defaults.showExtraWindows),
            focusSpaceOnWindowDrop: resolvedWindowDropFocusMode,
            focusSpaceOnWindowDropModifier: resolvedWindowDropModifier,
            showHUDOnSpaceChange: orDefault(showHUDOnSpaceChange, defaults.showHUDOnSpaceChange),
            updateMode: resolvedUpdateMode
        )
        return (config, needsRepair)
    }

    var gridConfig: GridConfig {
        gridConfig
    }
}
