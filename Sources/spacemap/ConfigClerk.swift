import SwiftUI
import Foundation
import CoreGraphics
import AppKit

final class ConfigClerk {
    var cols: Int = 8
    var rows: Int = 2
    var cellStyle: CellStyle = .rects
    var hotkeyString: String = "ctrl+pgdn"
    var pinnedHotkeyString: String = "none"
    var socketHealthInterval: Int = 60
    var uiScale: Double = 1.0
    var autoHideTimeout: Int = 0
    var theme: String = "default"
    var showMode: ShowMode = .all
    var multiMonitorHUDMode: MultiMonitorHUDMode = .unified
    var unifiedHUDVisibility: SeparateHUDVisibility = .active
    var separateHUDVisibility: SeparateHUDVisibility = .all
    var displayNavigationWrap: DisplayNavigationWrap = .within
    var maxSpaces: Int = 16
    var backgroundAlpha: Double = 0.3
    var mode: ThemeMode = .auto
    var iconScale: Double = 1.0
    var showSpaceNumbers: Bool = true
    var showSpaceNames: Bool = true
    var showIconStrip: Bool = true
    var showMultiAppIcons: Bool = false
    var hideMenuBarIcon: Bool = false
    var menuBarDisplayMode: MenuBarDisplayMode = .icon
    var menuBarNearbyCount: Int = 3
    var useVimKeys: Bool = false
    var useArrowKeys: Bool = false
    var hudPositionKind: HUDPositionKind = .center
    var spaceNameInputs: [Int: String] = [:]
    var showExtraWindows: Bool = false
    var focusSpaceOnWindowDrop: WindowDropFocusMode = .never
    var focusSpaceOnWindowDropModifier: WindowDropFocusModifier = .command
    var showHUDOnSpaceChange: Bool = false
    var lastCustomHUDX: Double = 0.5
    var lastCustomHUDY: Double = 0.5
    var updateMode: UpdateMode = .notify

    func load(from config: GridConfig) {
        cols = config.cols
        rows = config.rows
        cellStyle = config.cellStyle
        hotkeyString = ConfigClerk.hotkeyStringFrom(config.hotkey)
        pinnedHotkeyString = ConfigClerk.hotkeyStringFrom(config.pinnedHotkey)
        socketHealthInterval = config.socketHealthInterval
        uiScale = config.uiScale
        autoHideTimeout = config.autoHideTimeout
        theme = config.theme
        showMode = config.showMode
        multiMonitorHUDMode = config.multiMonitorHUDMode
        unifiedHUDVisibility = config.unifiedHUDVisibility
        separateHUDVisibility = config.separateHUDVisibility
        displayNavigationWrap = config.displayNavigationWrap
        maxSpaces = config.maxSpaces
        backgroundAlpha = config.backgroundAlpha
        mode = config.mode
        iconScale = config.iconScale
        showSpaceNumbers = config.showSpaceNumbers
        showSpaceNames = config.showSpaceNames
        showIconStrip = config.showIconStrip
        showMultiAppIcons = config.showMultiAppIcons
        hideMenuBarIcon = config.hideMenuBarIcon
        menuBarDisplayMode = config.menuBarDisplayMode
        menuBarNearbyCount = config.menuBarNearbyCount
        useVimKeys = config.useVimKeys
        useArrowKeys = config.useArrowKeys
        hudPositionKind = ConfigClerk.hudPositionKind(from: config.hudPosition)
        lastCustomHUDX = config.customHUDX
        lastCustomHUDY = config.customHUDY
        showExtraWindows = config.showExtraWindows
        focusSpaceOnWindowDrop = config.focusSpaceOnWindowDrop
        focusSpaceOnWindowDropModifier = config.focusSpaceOnWindowDropModifier
        showHUDOnSpaceChange = config.showHUDOnSpaceChange
        spaceNameInputs = config.spaceNames
        updateMode = config.updateMode
    }

    func buildGridConfig() -> GridConfig {
        GridConfig(
            cols: cols,
            rows: rows,
            cellStyle: cellStyle,
            hotkey: Hotkey.parseHotkey(hotkeyString) ?? GridConfig.default.hotkey,
            pinnedHotkey: Hotkey.parseHotkey(pinnedHotkeyString) ?? GridConfig.default.pinnedHotkey,
            socketHealthInterval: socketHealthInterval,
            uiScale: uiScale,
            autoHideTimeout: autoHideTimeout,
            theme: theme,
            showMode: showMode,
            multiMonitorHUDMode: multiMonitorHUDMode,
            unifiedHUDVisibility: unifiedHUDVisibility,
            separateHUDVisibility: separateHUDVisibility,
            displayNavigationWrap: displayNavigationWrap,
            maxSpaces: maxSpaces,
            backgroundAlpha: backgroundAlpha,
            mode: mode,
            iconScale: iconScale,
            showSpaceNumbers: showSpaceNumbers,
            showSpaceNames: showSpaceNames,
            showIconStrip: showIconStrip,
            showMultiAppIcons: showMultiAppIcons,
            hideMenuBarIcon: hideMenuBarIcon,
            menuBarDisplayMode: menuBarDisplayMode,
            menuBarNearbyCount: menuBarNearbyCount,
            spaceNames: spaceNameInputs,
            useVimKeys: useVimKeys,
            useArrowKeys: useArrowKeys,
            hudPosition: hudPosition,
            customHUDX: lastCustomHUDX,
            customHUDY: lastCustomHUDY,
            showExtraWindows: showExtraWindows,
            focusSpaceOnWindowDrop: focusSpaceOnWindowDrop,
            focusSpaceOnWindowDropModifier: focusSpaceOnWindowDropModifier,
            showHUDOnSpaceChange: showHUDOnSpaceChange,
            updateMode: updateMode
        )
    }

    var hudPosition: HUDPosition {
        switch hudPositionKind {
        case .center: return .center
        case .top: return .top
        case .bottom: return .bottom
        case .custom: return .custom(x: lastCustomHUDX, y: lastCustomHUDY)
        }
    }

    static func hotkeyStringFrom(_ hotkey: HotkeyConfig) -> String {
        return Hotkey.hotkeyToString(hotkey)
    }

    static func hudPositionKind(from position: HUDPosition) -> HUDPositionKind {
        HUDPositionKind(from: position)
    }

}
