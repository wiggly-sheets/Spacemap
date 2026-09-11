import SwiftUI
import Foundation
import CoreGraphics
import AppKit
import Sparkle

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}


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

    @State private var updateMode: UpdateMode = .notify
    @State private var selectedSection: SidebarSection = .grid
    @State private var isYabaiHealthy: Bool?
    @State private var isSocketHealthy: Bool?
    @State private var isRefreshingDiagnostics = false

    private let yabaiService: YabaiService
    private let diagnosticsTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(yabaiService: YabaiService, config: GridConfig = Config.load()) {
        self.yabaiService = yabaiService
        _cols = State(initialValue: config.cols)
        _rows = State(initialValue: config.rows)
        _cellStyle = State(initialValue: config.cellStyle)
        _hotkeyString = State(initialValue: SettingsView.hotkeyStringFrom(config.hotkey))
        _pinnedHotkeyString = State(initialValue: SettingsView.hotkeyStringFrom(config.pinnedHotkey))
        _socketHealthInterval = State(initialValue: config.socketHealthInterval)
        _uiScale = State(initialValue: config.uiScale)
        _autoHideTimeout = State(initialValue: config.autoHideTimeout)
        _theme = State(initialValue: config.theme)
        _showMode = State(initialValue: config.showMode)
        _multiMonitorHUDMode = State(initialValue: config.multiMonitorHUDMode)
        _unifiedHUDVisibility = State(initialValue: config.unifiedHUDVisibility)
        _separateHUDVisibility = State(initialValue: config.separateHUDVisibility)
        _displayNavigationWrap = State(initialValue: config.displayNavigationWrap)
        _maxSpaces = State(initialValue: config.maxSpaces)
        _backgroundAlpha = State(initialValue: config.backgroundAlpha)
        _hudShadow = State(initialValue: config.hudShadow)
        _mode = State(initialValue: config.mode)
        _iconScale = State(initialValue: config.iconScale)
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
        _hudPositionKind = State(initialValue: HUDPositionKind(from: config.hudPosition))
        _lastCustomHUDX = State(initialValue: config.customHUDX)
        _lastCustomHUDY = State(initialValue: config.customHUDY)
        _showExtraWindows = State(initialValue: config.showExtraWindows)
        _focusSpaceOnWindowDrop = State(initialValue: config.focusSpaceOnWindowDrop)
        _focusSpaceOnWindowDropModifier = State(initialValue: config.focusSpaceOnWindowDropModifier)
        _showHUDOnSpaceChange = State(initialValue: config.showHUDOnSpaceChange)
        _spaceNameInputs = State(initialValue: config.spaceNames)
        _gridLayoutIndex = State(initialValue: SettingsGrid.layoutIndex(
            maxSpaces: config.maxSpaces,
            currentCols: config.cols,
            currentRows: config.rows
        ))
        _updateMode = State(initialValue: config.updateMode)
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

            Form {
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
            .id(selectedSection)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .controlBackgroundColor).opacity(0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        yabaiService.runOnYabaiQueue {
            let yabaiHealthy = yabaiService.isYabaiRunning(forceRefresh: true)
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
