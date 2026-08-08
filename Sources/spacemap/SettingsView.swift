import SwiftUI
import Foundation
import CoreGraphics
import AppKit
import Sparkle

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

// Types CellStyle, ShowMode, ThemeMode, HotkeyConfig, GridConfig defined in Models.swift

struct SettingsView: View {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case grid = "Grid"
        case spaceNames = "Space Names"
        case appearance = "Appearance"
        case behavior = "Behavior"
        case advanced = "Debug/Advanced"

        var id: String { rawValue }
    }

    @State private var cols: Int = 8
    @State private var rows: Int = 2
    @State private var cellStyle: CellStyle = .rects
    @State private var hotkeyString: String = "ctrl+pgdn"
    @State private var pinnedHotkeyString: String = "none"
    @State private var socketHealthInterval: Int = 60
    @State private var uiScale: Double = 1.0
    @State private var autoHideTimeout: Int = 0
    @State private var theme: String = "default"
    @State private var showMode: ShowMode = .all
    @State private var multiMonitorHUDMode: MultiMonitorHUDMode = .unified
    @State private var unifiedHUDVisibility: SeparateHUDVisibility = .active
    @State private var separateHUDVisibility: SeparateHUDVisibility = .all
    @State private var displayNavigationWrap: DisplayNavigationWrap = .within
    @State private var maxSpaces: Int = 16
    @State private var gridLayoutIndex: Int = 0
    @State private var backgroundAlpha: Double = 0.3
    @State private var hudShadow: Bool = true
    @State private var mode: ThemeMode = .auto
    @State private var iconScale: Double = 1.0
    @State private var showSpaceNumbers: Bool = true
    @State private var showSpaceNames: Bool = true
    @State private var showIconStrip: Bool = true
    @State private var showMultiAppIcons: Bool = false
    @State private var hideMenuBarIcon: Bool = false
    @State private var menuBarDisplayMode: MenuBarDisplayMode = .icon
    @State private var menuBarNearbyCount: Int = 3
    @State private var useVimKeys: Bool = false
    @State private var useArrowKeys: Bool = false
    @State private var jumpToSpaceEnabled: Bool = false
    @State private var hudPositionKind: HUDPositionKind = .center
    @State private var spaceNameInputs: [Int: String] = [:]
    @State private var showExtraWindows: Bool = false
    @State private var focusSpaceOnWindowDrop: WindowDropFocusMode = .never
    @State private var focusSpaceOnWindowDropModifier: WindowDropFocusModifier = .command
    @State private var showHUDOnSpaceChange: Bool = false
    // Store last known custom HUD position to preserve it when switching between presets and custom
    @State private var lastCustomHUDX: Double = 0.5
    @State private var lastCustomHUDY: Double = 0.5

    private var hudPosition: HUDPosition {
        switch hudPositionKind {
        case .center: return .center
        case .top: return .top
        case .bottom: return .bottom
        case .custom: return .custom(x: lastCustomHUDX, y: lastCustomHUDY)
        }
    }

    @State private var isRecording = false
    @State private var monitors: [Any] = []
    @State private var updateMode: UpdateMode = .notify
    @State private var previousUpdateMode: UpdateMode = .notify
    @State private var selectedSection: SidebarSection = .grid
    @State private var isYabaiHealthy: Bool?
    @State private var isSocketHealthy: Bool?
    @State private var isRefreshingDiagnostics = false

    private let socketHealthOptions = [15, 30, 45, 60]
    private let diagnosticsTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var maxSpacesOptions: [Int] { Array(1...16) }

    private var gridLayouts: [(cols: Int, rows: Int, label: String)] {
        var layouts: [(Int, Int, String)] = []
        for c in 1...maxSpaces {
            if maxSpaces % c == 0 {
                let r = maxSpaces / c
                layouts.append((c, r, "\(c)×\(r)"))
            }
        }
        return layouts
    }

    private var backgroundTransparencySteps: [Double] {
        [0.00, 0.05, 0.12, 0.22, 0.35, 0.50, 0.65, 0.80, 0.92, 1.00]
    }

    private var uiScaleSteps: [Double] {
        [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    }

    private var iconScaleSteps: [Double] {
        [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    }

    private func nearest<T: FixedWidthInteger>(to value: T, from sorted: [T]) -> T {
        guard var closest = sorted.first else { return value }
        for item in sorted {
            let diff = item > value ? item - value : value - item
            let closestDiff = closest > value ? closest - value : value - closest
            if diff < closestDiff {
                closest = item
            }
        }
        return closest
    }

    private func nearest<T: BinaryFloatingPoint>(to value: T, from sorted: [T]) -> T {
        guard var closest = sorted.first else { return value }
        for item in sorted {
            let diff = abs(item - value)
            let closestDiff = abs(closest - value)
            if diff < closestDiff {
                closest = item
            }
        }
        return closest
    }

init() {
        let config = Config.load()
        _cols = State(initialValue: config.cols)
        _rows = State(initialValue: config.rows)
        _cellStyle = State(initialValue: config.cellStyle)
        _hotkeyString = State(initialValue: SettingsView.hotkeyStringFrom(config.hotkey))
        _pinnedHotkeyString = State(initialValue: SettingsView.hotkeyStringFrom(config.pinnedHotkey))
        _socketHealthInterval = State(initialValue: nearest(to: config.socketHealthInterval, from: socketHealthOptions))
        _uiScale = State(initialValue: nearest(to: config.uiScale, from: uiScaleSteps))
        _autoHideTimeout = State(initialValue: config.autoHideTimeout)
        _theme = State(initialValue: config.theme)
        _showMode = State(initialValue: config.showMode)
        _multiMonitorHUDMode = State(initialValue: config.multiMonitorHUDMode)
        _unifiedHUDVisibility = State(initialValue: config.unifiedHUDVisibility)
        _separateHUDVisibility = State(initialValue: config.separateHUDVisibility)
        _displayNavigationWrap = State(initialValue: config.displayNavigationWrap)
        _maxSpaces = State(initialValue: config.maxSpaces)
        _backgroundAlpha = State(initialValue: nearest(to: config.backgroundAlpha, from: backgroundTransparencySteps))
        _hudShadow = State(initialValue: config.hudShadow)
        _mode = State(initialValue: config.mode)
        _iconScale = State(initialValue: nearest(to: config.iconScale, from: iconScaleSteps))
        _showSpaceNumbers = State(initialValue: config.showSpaceNumbers)
        _showSpaceNames = State(initialValue: config.showSpaceNames)
        _showIconStrip = State(initialValue: config.showIconStrip)
        _showMultiAppIcons = State(initialValue: config.showMultiAppIcons)
        _hideMenuBarIcon = State(initialValue: config.hideMenuBarIcon)
        _menuBarDisplayMode = State(initialValue: config.menuBarDisplayMode)
        _menuBarNearbyCount = State(initialValue: config.menuBarNearbyCount)
        _useVimKeys = State(initialValue: config.useVimKeys)
        _useArrowKeys = State(initialValue: config.useArrowKeys)
        _jumpToSpaceEnabled = State(initialValue: config.jumpToSpaceEnabled)
        // Initialize HUD position state: kind from config.hudPosition, custom position from config.customHUDX/Y
        _hudPositionKind = State(initialValue: HUDPositionKind(from: config.hudPosition))
        _lastCustomHUDX = State(initialValue: config.customHUDX)
        _lastCustomHUDY = State(initialValue: config.customHUDY)
        _showExtraWindows = State(initialValue: config.showExtraWindows)
        _focusSpaceOnWindowDrop = State(initialValue: config.focusSpaceOnWindowDrop)
        _focusSpaceOnWindowDropModifier = State(initialValue: config.focusSpaceOnWindowDropModifier)
        _showHUDOnSpaceChange = State(initialValue: config.showHUDOnSpaceChange)
        _spaceNameInputs = State(initialValue: config.spaceNames)
        _gridLayoutIndex = State(initialValue: findBestGridLayoutIndexFor(cols: config.cols, rows: config.rows, maxSpaces: config.maxSpaces))
        _updateMode = State(initialValue: config.updateMode)
        _previousUpdateMode = State(initialValue: config.updateMode)
    }

    private func findBestGridLayoutIndexFor(cols: Int, rows: Int, maxSpaces: Int) -> Int {
        let layouts: [(Int, Int)] = (1...maxSpaces).compactMap { c in
            maxSpaces % c == 0 ? (c, maxSpaces / c) : nil
        }
        for (idx, layout) in layouts.enumerated() {
            if layout.0 == cols && layout.1 == rows {
                return idx
            }
        }
        return 0
    }

    private func saveConfig() {
        let config = GridConfig(
            cols: cols,
            rows: rows,
            cellStyle: cellStyle,
            hotkey: Config.parseHotkey(hotkeyString) ?? GridConfig.default.hotkey,
            pinnedHotkey: Config.parseHotkey(pinnedHotkeyString) ?? GridConfig.default.pinnedHotkey,
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
            hudShadow: hudShadow,
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
            jumpToSpaceEnabled: jumpToSpaceEnabled,
            hudPosition: hudPosition,
            customHUDX: lastCustomHUDX,
            customHUDY: lastCustomHUDY,
            showExtraWindows: showExtraWindows,
            focusSpaceOnWindowDrop: focusSpaceOnWindowDrop,
            focusSpaceOnWindowDropModifier: focusSpaceOnWindowDropModifier,
            showHUDOnSpaceChange: showHUDOnSpaceChange,
            updateMode: updateMode
        )
        Config.saveConfig(config)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedSection: $selectedSection)

            Divider()

            switch selectedSection {
            case .grid:
                SettingsGrid(
                    maxSpaces: $maxSpaces,
                    gridLayoutIndex: $gridLayoutIndex,
                    cols: $cols,
                    rows: $rows,
                    showMode: $showMode,
                    multiMonitorHUDMode: $multiMonitorHUDMode,
                    unifiedHUDVisibility: $unifiedHUDVisibility,
                    separateHUDVisibility: $separateHUDVisibility,
                    cellStyle: $cellStyle,
                    showSpaceNumbers: $showSpaceNumbers,
                    showIconStrip: $showIconStrip,
                    showMultiAppIcons: $showMultiAppIcons,
                    onSave: saveConfig
                )

            case .spaceNames:
                SettingsSpaceNames(
                    showSpaceNames: $showSpaceNames,
                    spaceNameInputs: $spaceNameInputs,
                    maxSpaces: $maxSpaces,
                    onSave: saveConfig
                )

            case .appearance:
                SettingsAppearanceView(
                    theme: $theme,
                    mode: $mode,
                    backgroundAlpha: $backgroundAlpha,
                    hudShadow: $hudShadow,
                    iconScale: $iconScale,
                    uiScale: $uiScale,
                    onSave: saveConfig
                )

            case .behavior:
                SettingsBehavior(
                    hotkeyString: $hotkeyString,
                    pinnedHotkeyString: $pinnedHotkeyString,
                    hudPositionKind: $hudPositionKind,
                    autoHideTimeout: $autoHideTimeout,
                    useArrowKeys: $useArrowKeys,
                    useVimKeys: $useVimKeys,
                    jumpToSpaceEnabled: $jumpToSpaceEnabled,
                    displayNavigationWrap: $displayNavigationWrap,
                    focusSpaceOnWindowDrop: $focusSpaceOnWindowDrop,
                    focusSpaceOnWindowDropModifier: $focusSpaceOnWindowDropModifier,
                    showHUDOnSpaceChange: $showHUDOnSpaceChange,
                    hideMenuBarIcon: $hideMenuBarIcon,
                    menuBarDisplayMode: $menuBarDisplayMode,
                    menuBarNearbyCount: $menuBarNearbyCount,
                    updateMode: $updateMode,
                    onSave: saveConfig,
                    checkForUpdates: { (NSApp.delegate as? AppDelegate)?.checkForUpdates() }
                )

            case .advanced:
                SettingsAdvanced(
                    isYabaiHealthy: $isYabaiHealthy,
                    isSocketHealthy: $isSocketHealthy,
                    isRefreshingDiagnostics: $isRefreshingDiagnostics,
                    socketHealthInterval: $socketHealthInterval,
                    showExtraWindows: $showExtraWindows,
                    refreshDiagnostics: refreshDiagnostics,
                    saveConfig: saveConfig
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsChanged)) { _ in
            let config = Config.load()
            lastCustomHUDX = config.customHUDX
            lastCustomHUDY = config.customHUDY
        }
        .onChange(of: selectedSection) { section in
            if section == .advanced { refreshDiagnostics() }
        }
        .onReceive(diagnosticsTimer) { _ in
            if selectedSection == .advanced { refreshDiagnostics() }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
    }

    private func refreshDiagnostics() {
        guard !isRefreshingDiagnostics else { return }
        isRefreshingDiagnostics = true
        let socketPath = "/tmp/spacemap_\(NSUserName()).socket"
        DispatchQueue.global(qos: .utility).async {
            let yabaiHealthy = YabaiClient.isYabaiRunning(forceRefresh: true)
            let socketHealthy = SocketListener.sendCommand(to: socketPath, command: 5)
            DispatchQueue.main.async {
                isYabaiHealthy = yabaiHealthy
                isSocketHealthy = socketHealthy
                isRefreshingDiagnostics = false
            }
        }
    }

    static func hotkeyStringFrom(_ hotkey: HotkeyConfig) -> String {
        return Hotkey.hotkeyToString(hotkey)
    }
}
