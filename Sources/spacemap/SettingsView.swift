import SwiftUI
import Foundation
import CoreGraphics
import AppKit
import Combine
import Sparkle

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
    /// Position-only strip change (a drag). Unlike `.settingsChanged` this must
    /// not reload themes or drop the glyph-font cache.
    static let glyphStripPositionChanged = Notification.Name("glyphStripPositionChanged")
    /// Active space-name profile changed from the menu bar. Re-seeds only the
    /// profile state in an open Settings window.
    static let spaceNameProfileChanged = Notification.Name("spaceNameProfileChanged")
}


struct SettingsView: View {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case grid = "Grid"
        case spaceNames = "Space Names"
        case appearance = "Appearance"
        case behavior = "Behavior"
        case glyphStrip = "Glyph Strip"
        case advanced = "Debug/Advanced"

        var id: String { rawValue }
    }

    @State private var cols: Int = 8
    @State private var rows: Int = 2
    @State private var cellStyle: CellStyle = .rects
    @State private var hotkeyString: String = "ctrl+pgdn"
    @State private var pinnedHotkeyString: String = "none"
    @State private var glyphStripHotkeyString: String = "none"
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
    @State private var backgroundStyle: HUDBackgroundStyle = .glass
    @State private var glassStyle: HUDGlassStyle = .opaque
    @State private var glassClearOpacity: Double = 0.15
    @State private var glassOpaqueOpacity: Double = 0.3
    @State private var glassTintedOpacity: Double = 0.3
    @State private var solidOpacity: Double = 1.0
    @State private var matchBackgroundOpacity: Bool = false
    @State private var hudShadow: Bool = true
    @State private var mode: ThemeMode = .auto
    @State private var iconScale: Double = 1.0
    @State private var showSpaceNumbers: Bool = true
    @State private var showSpaceLayout: Bool = false
    @State private var showSpaceNames: Bool = true
    @State private var showIconStrip: Bool = true
    @State private var showMultiAppIcons: Bool = false
    @State private var hideMenuBarIcon: Bool = false
    @State private var glyphStrip: GlyphStripConfig = .default
    @State private var menuBarDisplayMode: MenuBarDisplayMode = .icon
    @State private var menuBarNearbyCount: Int = 3
    @State private var useVimKeys: Bool = false
    @State private var useArrowKeys: Bool = false
    @State private var useExtendedKeys: Bool = true
    @State private var jumpToSpaceEnabled: Bool = false
    @State private var hudPositionKind: HUDPositionKind = .center
    @State private var spaceNameInputs: [Int: String] = [:]
    @State private var spaceNameProfiles: [SpaceNameProfile] = [SpaceNameProfile.default]
    @State private var pendingSpaceNameEdit = SpaceNamePendingEdit()
    @State private var activeSpaceNameProfileIndex: Int = 0
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
    @State private var appFontUpdateMode: AppFontUpdateMode = .manual
    @State private var selectedSection: SidebarSection = .grid
    @State private var isYabaiHealthy: Bool?
    @State private var isSocketHealthy: Bool?
    @State private var isRefreshingDiagnostics = false
    @State private var saveErrorMessage: String?

    private let yabaiService: YabaiService
    private let diagnosticsTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(yabaiService: YabaiService, config: GridConfig = AppConfig.load()) {
        self.yabaiService = yabaiService
        _cols = State(initialValue: config.cols)
        _rows = State(initialValue: config.rows)
        _cellStyle = State(initialValue: config.cellStyle)
        _hotkeyString = State(initialValue: SettingsView.hotkeyStringFrom(config.hotkey))
        _pinnedHotkeyString = State(initialValue: SettingsView.hotkeyStringFrom(config.pinnedHotkey))
        _glyphStripHotkeyString = State(initialValue: SettingsView.hotkeyStringFrom(config.glyphStripHotkey))
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
        _backgroundStyle = State(initialValue: config.backgroundStyle)
        _glassStyle = State(initialValue: config.glassStyle)
        _glassClearOpacity = State(initialValue: config.glassClearOpacity)
        _glassOpaqueOpacity = State(initialValue: config.glassOpaqueOpacity)
        _glassTintedOpacity = State(initialValue: config.glassTintedOpacity)
        _solidOpacity = State(initialValue: config.solidOpacity)
        _matchBackgroundOpacity = State(initialValue: config.matchBackgroundOpacity)
        _hudShadow = State(initialValue: config.hudShadow)
        _mode = State(initialValue: config.mode)
        _iconScale = State(initialValue: config.iconScale)
        _showSpaceNumbers = State(initialValue: config.showSpaceNumbers)
        _showSpaceLayout = State(initialValue: config.showSpaceLayout)
        _showSpaceNames = State(initialValue: config.showSpaceNames)
        _showIconStrip = State(initialValue: config.showIconStrip)
        _showMultiAppIcons = State(initialValue: config.showMultiAppIcons)
        _hideMenuBarIcon = State(initialValue: config.hideMenuBarIcon)
        _glyphStrip = State(initialValue: config.glyphStrip.clamped())
        _menuBarDisplayMode = State(initialValue: config.menuBarDisplayMode)
        _menuBarNearbyCount = State(initialValue: config.menuBarNearbyCount)
        _useVimKeys = State(initialValue: config.useVimKeys)
        _useArrowKeys = State(initialValue: config.useArrowKeys)
        _useExtendedKeys = State(initialValue: config.useExtendedKeys)
        _jumpToSpaceEnabled = State(initialValue: config.jumpToSpaceEnabled)
        _hudPositionKind = State(initialValue: HUDPositionKind(from: config.hudPosition))
        _lastCustomHUDX = State(initialValue: config.customHUDX)
        _lastCustomHUDY = State(initialValue: config.customHUDY)
        _showExtraWindows = State(initialValue: config.showExtraWindows)
        _focusSpaceOnWindowDrop = State(initialValue: config.focusSpaceOnWindowDrop)
        _focusSpaceOnWindowDropModifier = State(initialValue: config.focusSpaceOnWindowDropModifier)
        _showHUDOnSpaceChange = State(initialValue: config.showHUDOnSpaceChange)
        _spaceNameInputs = State(initialValue: config.spaceNames)
        _spaceNameProfiles = State(initialValue: config.spaceNameProfiles)
        _activeSpaceNameProfileIndex = State(initialValue: config.activeSpaceNameProfileIndex)
        _gridLayoutIndex = State(initialValue: SettingsGrid.layoutIndex(
            maxSpaces: config.maxSpaces,
            currentCols: config.cols,
            currentRows: config.rows
        ))
        _updateMode = State(initialValue: config.updateMode)
        _appFontUpdateMode = State(initialValue: config.appFont.updateMode)
    }

    static let saveFailureMessage = NSLocalizedString(
        "Spacemap could not write its configuration file. Check permissions and try again.",
        comment: "Settings save failure message"
    )

    static func saveResultMessage(_ success: Bool) -> String? {
        success ? nil : saveFailureMessage
    }

    /// Applies the UI-owned fields onto the current disk config. The updater
    /// owns `appFont.installedVersion`/`lastCheck`, and yabai trust refusal has
    /// no UI control, so both are read from `disk` at write time inside the
    /// atomic `AppConfig.updateConfig` closure.
    static func applySave(
        _ ui: GridConfig,
        to disk: inout GridConfig,
        appFontUpdateMode: AppFontUpdateMode
    ) {
        var appFont = disk.appFont
        appFont.updateMode = appFontUpdateMode
        let refuseUntrustedYabai = disk.refuseUntrustedYabai
        disk = ui
        disk.appFont = appFont
        disk.refuseUntrustedYabai = refuseUntrustedYabai
    }

    private func saveConfig() {
        let config = GridConfig(
            cols: cols,
            rows: rows,
            cellStyle: cellStyle,
            hotkey: AppConfig.parseHotkey(hotkeyString) ?? GridConfig.default.hotkey,
            pinnedHotkey: AppConfig.parseHotkey(pinnedHotkeyString) ?? GridConfig.default.pinnedHotkey,
            glyphStripHotkey: AppConfig.parseHotkey(glyphStripHotkeyString) ?? HotkeyConfig(key: .none, modifiers: []),
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
            backgroundStyle: backgroundStyle,
            glassStyle: glassStyle,
            glassClearOpacity: glassClearOpacity,
            glassOpaqueOpacity: glassOpaqueOpacity,
            glassTintedOpacity: glassTintedOpacity,
            solidOpacity: solidOpacity,
            matchBackgroundOpacity: matchBackgroundOpacity,
            hudShadow: hudShadow,
            mode: mode,
            iconScale: iconScale,
            showSpaceNumbers: showSpaceNumbers,
            showSpaceLayout: showSpaceLayout,
            showSpaceNames: showSpaceNames,
            showIconStrip: showIconStrip,
            showMultiAppIcons: showMultiAppIcons,
            hideMenuBarIcon: hideMenuBarIcon,
            glyphStrip: glyphStrip.clamped(),
            menuBarDisplayMode: menuBarDisplayMode,
            menuBarNearbyCount: menuBarNearbyCount,
            spaceNames: spaceNameInputs,
            useVimKeys: useVimKeys,
            useArrowKeys: useArrowKeys,
            useExtendedKeys: useExtendedKeys,
            jumpToSpaceEnabled: jumpToSpaceEnabled,
            hudPosition: hudPosition,
            customHUDX: lastCustomHUDX,
            customHUDY: lastCustomHUDY,
            showExtraWindows: showExtraWindows,
            focusSpaceOnWindowDrop: focusSpaceOnWindowDrop,
            focusSpaceOnWindowDropModifier: focusSpaceOnWindowDropModifier,
            showHUDOnSpaceChange: showHUDOnSpaceChange,
            updateMode: updateMode,
            spaceNameProfiles: spaceNameProfiles,
            activeSpaceNameProfileIndex: activeSpaceNameProfileIndex
        )
        let fontUpdateMode = appFontUpdateMode
        let saved = AppConfig.updateConfig { disk in
            Self.applySave(config, to: &disk, appFontUpdateMode: fontUpdateMode)
        }
        saveErrorMessage = Self.saveResultMessage(saved)
        guard saved else { return }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selectedSection: $selectedSection)
                .background(Color.clear)
        } detail: {
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
                    showSpaceLayout: $showSpaceLayout,
                    showIconStrip: $showIconStrip,
                    showMultiAppIcons: $showMultiAppIcons,
                    onSave: saveConfig
                )

            case .spaceNames:
                SettingsSpaceNames(
                    showSpaceNames: $showSpaceNames,
                    spaceNameInputs: $spaceNameInputs,
                    maxSpaces: $maxSpaces,
                    profiles: $spaceNameProfiles,
                    activeProfileIndex: $activeSpaceNameProfileIndex,
                    pendingEdit: pendingSpaceNameEdit,
                    onSave: saveConfig
                )

            case .appearance:
                SettingsAppearanceView(
                    theme: $theme,
                    mode: $mode,
                    backgroundAlpha: $backgroundAlpha,
                    backgroundStyle: $backgroundStyle,
                    glassStyle: $glassStyle,
                    glassClearOpacity: $glassClearOpacity,
                    glassOpaqueOpacity: $glassOpaqueOpacity,
                    glassTintedOpacity: $glassTintedOpacity,
                    solidOpacity: $solidOpacity,
                    matchBackgroundOpacity: $matchBackgroundOpacity,
                    hudShadow: $hudShadow,
                    iconScale: $iconScale,
                    uiScale: $uiScale,
                    onSave: saveConfig
                )

            case .behavior:
                SettingsBehavior(
                    hotkeyString: $hotkeyString,
                    pinnedHotkeyString: $pinnedHotkeyString,
                    glyphStripHotkeyString: $glyphStripHotkeyString,
                    hudPositionKind: $hudPositionKind,
                    autoHideTimeout: $autoHideTimeout,
                    useArrowKeys: $useArrowKeys,
                    useVimKeys: $useVimKeys,
                    useExtendedKeys: $useExtendedKeys,
                    jumpToSpaceEnabled: $jumpToSpaceEnabled,
                    displayNavigationWrap: $displayNavigationWrap,
                    focusSpaceOnWindowDrop: $focusSpaceOnWindowDrop,
                    focusSpaceOnWindowDropModifier: $focusSpaceOnWindowDropModifier,
                    showHUDOnSpaceChange: $showHUDOnSpaceChange,
                    hideMenuBarIcon: $hideMenuBarIcon,
                    menuBarDisplayMode: $menuBarDisplayMode,
                    menuBarNearbyCount: $menuBarNearbyCount,
                    updateMode: $updateMode,
                    appFontUpdateMode: $appFontUpdateMode,
                    onSave: saveConfig,
                    checkForUpdates: { (NSApp.delegate as? AppDelegate)?.checkForUpdates() }
                )

            case .glyphStrip:
                SettingsGlyphStrip(
                    glyphStrip: $glyphStrip,
                    themeName: theme,
                    onSave: saveConfig
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
            .background(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
        .onReceive(NotificationCenter.default.publisher(for: .settingsChanged)) { _ in
            let config = AppConfig.load()
            lastCustomHUDX = config.customHUDX
            lastCustomHUDY = config.customHUDY
            // External writers (the strip's own drag) change the config under
            // an open settings window; re-seed so a later save here cannot
            // revert them. Every control saves on change, so the state being
            // re-seeded always already matches the file.
            glyphStrip = config.glyphStrip.clamped()
        }
        .onReceive(NotificationCenter.default.publisher(for: .glyphStripPositionChanged)) { _ in
            // A finished drag persists only the strip position. Re-seed just
            // that value so the next settings save keeps the drag.
            glyphStrip = AppConfig.load().glyphStrip.clamped()
        }
        .onReceive(NotificationCenter.default.publisher(for: .spaceNameProfileChanged)) { _ in
            // Apply any queued keystroke to the profile that was active when it
            // was typed, then re-seed the newly active profile. Saving after
            // both keeps the menu switch and the edit on disk together.
            let flushed = pendingSpaceNameEdit.flushApply()
            let config = AppConfig.load()
            if let seed = Self.profileStateToSeed(from: config) {
                activeSpaceNameProfileIndex = seed.index
                spaceNameInputs = seed.spaceNames
            }
            if flushed { saveConfig() }
        }
        .onReceive(NotificationCenter.default.publisher(for: HUDDisplay.hudPositionChangedNotification)) { _ in
            let seed = Self.hudPositionStateToSeed(from: AppConfig.load())
            hudPositionKind = seed.kind
            lastCustomHUDX = seed.x
            lastCustomHUDY = seed.y
        }
        .onChange(of: selectedSection) { section in
            if section == .advanced { refreshDiagnostics() }
        }
        .onReceive(diagnosticsTimer) { _ in
            if selectedSection == .advanced { refreshDiagnostics() }
        }
        .alert(
            "Could not save settings",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
    }

    /// Profile state to re-seed from a menu-bar profile switch. Pure so the
    /// menu → Settings flow is testable without SwiftUI state.
    static func profileStateToSeed(
        from config: GridConfig
    ) -> (index: Int, spaceNames: [Int: String])? {
        let index = config.activeSpaceNameProfileIndex
        guard config.spaceNameProfiles.indices.contains(index) else { return nil }
        return (index, config.spaceNameProfiles[index].spaceNames)
    }

    static func hudPositionStateToSeed(
        from config: GridConfig
    ) -> (kind: HUDPositionKind, x: Double, y: Double) {
        (
            HUDPositionKind(from: config.hudPosition),
            config.customHUDX,
            config.customHUDY
        )
    }

    private func refreshDiagnostics() {
        guard !isRefreshingDiagnostics else { return }
        isRefreshingDiagnostics = true
        let socketPath = SpacemapCommand.socketPath
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
