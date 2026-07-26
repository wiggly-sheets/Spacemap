import SwiftUI
import Foundation
import CoreGraphics
import AppKit
import Sparkle

struct CustomStepper: View {
    let steps: [Double]
    @Binding var value: Double
    
    var body: some View {
        HStack {
            Button(action: { stepDown() }) {
                Image(systemName: "minus.circle")
            }
            .disabled(currentIndex == 0)
            
            Slider(value: Binding(
                get: { Double(currentIndex) },
                set: { newIndex in
                    let idx = max(0, min(steps.count - 1, Int(newIndex.rounded())))
                    value = steps[idx]
                }
            ), in: 0...Double(steps.count - 1), step: 1)
            
            Button(action: { stepUp() }) {
                Image(systemName: "plus.circle")
            }
            .disabled(currentIndex == steps.count - 1)
        }
    }
    
    private var currentIndex: Int {
        if let idx = steps.firstIndex(of: value) { return idx }
        var closest = 0
        for i in 1..<steps.count {
            if abs(steps[i] - value) < abs(steps[closest] - value) { closest = i }
        }
        return closest
    }
    
    private func stepDown() {
        if currentIndex > 0 {
            value = steps[currentIndex - 1]
        }
    }
    
    private func stepUp() {
        if currentIndex < steps.count - 1 {
            value = steps[currentIndex + 1]
        }
    }
}

private struct SettingsFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

// Types CellStyle, ShowMode, ThemeMode, HotkeyConfig, GridConfig defined in Models.swift

struct SettingsView: View {
    private enum SidebarSection: String, CaseIterable, Identifiable {
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
    @State private var mode: ThemeMode = .auto
    @State private var iconScale: Double = 1.0
    @State private var showSpaceNumbers: Bool = true
    @State private var showSpaceNames: Bool = true
    @State private var showIconStrip: Bool = true
    @State private var showMultiAppIcons: Bool = false
    @State private var hideMenuBarIcon: Bool = false
    @State private var useVimKeys: Bool = false
    @State private var useArrowKeys: Bool = false
    @State private var hudPositionKind: HUDPositionKind = .center
    @State private var spaceNameInputs: [Int: String] = [:]
    @State private var showExtraWindows: Bool = false
    @State private var focusSpaceOnWindowDrop: Bool = false
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
    
    private let socketHealthOptions = [15, 30, 45, 60]
    
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
        let config = ConfigReader.load()
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
        _mode = State(initialValue: config.mode)
        _iconScale = State(initialValue: nearest(to: config.iconScale, from: iconScaleSteps))
        _showSpaceNumbers = State(initialValue: config.showSpaceNumbers)
        _showSpaceNames = State(initialValue: config.showSpaceNames)
        _showIconStrip = State(initialValue: config.showIconStrip)
        _showMultiAppIcons = State(initialValue: config.showMultiAppIcons)
        _hideMenuBarIcon = State(initialValue: config.hideMenuBarIcon)
        _useVimKeys = State(initialValue: config.useVimKeys)
        _useArrowKeys = State(initialValue: config.useArrowKeys)
        // Initialize HUD position state: kind from config.hudPosition, custom position from config.customHUDX/Y
        _hudPositionKind = State(initialValue: HUDPositionKind(from: config.hudPosition))
        _lastCustomHUDX = State(initialValue: config.customHUDX)
        _lastCustomHUDY = State(initialValue: config.customHUDY)
        _showExtraWindows = State(initialValue: config.showExtraWindows)
        _focusSpaceOnWindowDrop = State(initialValue: config.focusSpaceOnWindowDrop)
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
            hotkey: ConfigReader.parseHotkey(hotkeyString) ?? GridConfig.default.hotkey,
            pinnedHotkey: ConfigReader.parseHotkey(pinnedHotkeyString) ?? GridConfig.default.pinnedHotkey,
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
            spaceNames: spaceNameInputs,
            useVimKeys: useVimKeys,
            useArrowKeys: useArrowKeys,
            hudPosition: hudPosition,
            customHUDX: lastCustomHUDX,
            customHUDY: lastCustomHUDY,
            showExtraWindows: showExtraWindows,
            focusSpaceOnWindowDrop: focusSpaceOnWindowDrop,
            updateMode: updateMode
        )
        ConfigReader.saveConfig(config)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    private func findBestGridLayoutIndex() -> Int {
        let layouts = gridLayouts
        guard !layouts.isEmpty else { return 0 }
        for (idx, layout) in layouts.enumerated() {
            if layout.cols == cols && layout.rows == rows {
                return idx
            }
        }
        return layouts.firstIndex(where: { $0.cols * $0.rows == maxSpaces }) ?? 0
    }
    
    var body: some View {
        HStack(spacing: 0) {
            List {
                ForEach(SidebarSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.rawValue, systemImage: sidebarIcon(for: section))
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedSection == section ? Color.accentColor : Color.primary)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedSection == section ? Color.accentColor.opacity(0.18) : Color.clear)
                    )
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            Form {
                switch selectedSection {
                case .grid:
                    Section(header: settingsSectionHeader("Grid")) {
                        Picker("Max Spaces", selection: $maxSpaces) {
                            ForEach(maxSpacesOptions, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .onChange(of: maxSpaces) { _ in
                            gridLayoutIndex = findBestGridLayoutIndex()
                            let layout = gridLayouts[gridLayoutIndex]
                            cols = layout.cols
                            rows = layout.rows
                            saveConfig()
                        }

                        Picker("Grid Layout", selection: $gridLayoutIndex) {
                            ForEach(Array(gridLayouts.enumerated()), id: \.offset) { idx, layout in
                                Text(layout.label).tag(idx)
                            }
                        }
                        .onChange(of: gridLayoutIndex) { _ in
                            let layout = gridLayouts[gridLayoutIndex]
                            cols = layout.cols
                            rows = layout.rows
                            saveConfig()
                        }

                        Picker("Show Mode", selection: $showMode) {
                            Text("All Spaces").tag(ShowMode.all)
                            Text("Active Spaces").tag(ShowMode.active)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: showMode) { _ in saveConfig() }

                        Picker("Multi-Monitor HUD", selection: $multiMonitorHUDMode) {
                            Text("Unified Grid").tag(MultiMonitorHUDMode.unified)
                            Text("Separate HUDs").tag(MultiMonitorHUDMode.separate)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: multiMonitorHUDMode) { _ in saveConfig() }

                        SettingsFootnote(text: multiMonitorHUDMode == .separate
                            ? "Shows one grid on each display and keeps keyboard navigation on the focused display."
                            : "Shows every space in one grid; keyboard navigation can cross displays.")

                        if multiMonitorHUDMode == .unified {
                            Picker("Unified Grid", selection: $unifiedHUDVisibility) {
                                Text("Active Display Only").tag(SeparateHUDVisibility.active)
                                Text("All Displays").tag(SeparateHUDVisibility.all)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: unifiedHUDVisibility) { _ in saveConfig() }
                            SettingsFootnote(text: unifiedHUDVisibility == .active
                                ? "Shows the unified grid on the display containing yabai's focused space."
                                : "Shows the same unified grid on every display at once.")
                        }

                        if multiMonitorHUDMode == .separate {
                            Picker("Separate HUDs", selection: $separateHUDVisibility) {
                                Text("All Displays").tag(SeparateHUDVisibility.all)
                                Text("Active Display Only").tag(SeparateHUDVisibility.active)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: separateHUDVisibility) { _ in saveConfig() }
                            SettingsFootnote(text: separateHUDVisibility == .active
                                ? "Shows the HUD only on the display containing yabai's focused space."
                                : "Shows a HUD on every display at once.")
                        }

                        Picker("Cell Style", selection: $cellStyle) {
                            Text("Rectangles").tag(CellStyle.rects)
                            Text("Icons").tag(CellStyle.icons)
                            Text("Thumbnails").tag(CellStyle.thumbnails)
                            Text("Simple").tag(CellStyle.simple)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: cellStyle) { _ in saveConfig() }

                        Toggle("Show Space Numbers", isOn: $showSpaceNumbers)
                            .onChange(of: showSpaceNumbers) { _ in saveConfig() }
                        Toggle("Show Icon Strip", isOn: $showIconStrip)
                            .onChange(of: showIconStrip) { _ in saveConfig() }

                        if showIconStrip {
                            Toggle("Show Icon Per Window", isOn: $showMultiAppIcons)
                                .onChange(of: showMultiAppIcons) { _ in saveConfig() }
                        }

                        Toggle("Show Extra Windows", isOn: $showExtraWindows)
                            .onChange(of: showExtraWindows) { _ in saveConfig() }

                        if showExtraWindows {
                            Text("Shows utility/floating windows (e.g. System Settings). May show invisible utility windows. Turn off for cleaner display with some missed windows.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                case .spaceNames:
                    Section(header: settingsSectionHeader("Space Names")) {
                        Toggle("Show Space Names", isOn: $showSpaceNames)
                            .onChange(of: showSpaceNames) { _ in saveConfig() }

                        if showSpaceNames {
                            Text("(Each input below corresponds to each space number, up to Max Spaces)")
                                .font(.footnote)
                                .foregroundColor(.secondary)

                            ForEach(maxSpacesOptions, id: \.self) { spaceIndex in
                                if spaceIndex <= maxSpaces {
                                    HStack {
                                        Text("Space \(spaceIndex):")
                                            .frame(width: 80, alignment: .leading)
                                        TextField("", text: binding(for: spaceIndex))
                                            .textFieldStyle(.roundedBorder)
                                            .id("spaceName-\(spaceIndex)")
                                            .onChange(of: binding(for: spaceIndex).wrappedValue) { _ in saveConfig() }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                case .appearance:
                    Section(header: settingsSectionHeader("Appearance")) {
                        Picker("Theme", selection: $theme) {
                            ForEach(ThemeManager.shared.allNames(), id: \.self) { name in
                                Text(name.capitalized).tag(name)
                            }
                        }
                        .onChange(of: theme) { _ in saveConfig() }

                        HStack {
                            Button("Open Config File") {
                                let url = URL(fileURLWithPath: ConfigReader.configPath)
                                NSWorkspace.shared.open(url)
                            }
                            Button("Open Themes Folder") {
                                NSWorkspace.shared.open(ThemeManager.themesDir())
                            }
                        }

                        Picker("Background Color", selection: $mode) {
                            Text("Light").tag(ThemeMode.light)
                            Text("Dark").tag(ThemeMode.dark)
                            Text("Auto").tag(ThemeMode.auto)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _ in saveConfig() }

                        VStack(alignment: .leading) {
                            Text("Background Transparency")
                                .font(.subheadline)
                            CustomStepper(steps: backgroundTransparencySteps, value: $backgroundAlpha)
                                .onChange(of: backgroundAlpha) { _ in saveConfig() }
                        }

                        VStack(alignment: .leading) {
                            Text("Icon Scale")
                                .font(.subheadline)
                                .bold()
                            CustomStepper(steps: iconScaleSteps, value: $iconScale)
                                .onChange(of: iconScale) { _ in saveConfig() }
                        }

                        VStack(alignment: .leading) {
                            Text("UI Scale")
                                .font(.subheadline)
                                .bold()
                            CustomStepper(steps: uiScaleSteps, value: $uiScale)
                                .onChange(of: uiScale) { _ in saveConfig() }
                        }
                    }
                case .behavior:
                    Section(header: settingsSectionHeader("Behavior")) {
                        HotkeyRecorder(label: "Hotkey", hotkey: $hotkeyString)
                            .onChange(of: hotkeyString) { _ in saveConfig() }
                        HotkeyRecorder(label: "Pinned HUD Hotkey", hotkey: $pinnedHotkeyString)
                            .onChange(of: pinnedHotkeyString) { _ in saveConfig() }
                        SettingsFootnote(text: "Optional. Toggles a HUD that stays visible until you use either hotkey to hide it. Use a different shortcut from the normal hotkey.")

                        Picker("HUD Position", selection: $hudPositionKind) {
                            Text("Center").tag(HUDPositionKind.center)
                            Text("Top").tag(HUDPositionKind.top)
                            Text("Bottom").tag(HUDPositionKind.bottom)
                            Text("Custom").tag(HUDPositionKind.custom)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: hudPositionKind) { _ in saveConfig() }

                        if case .custom = hudPosition {
                            SettingsFootnote(text: "Drag the HUD to reposition. Position is saved automatically.")
                        }

                        HStack {
                            Text("Auto-hide Timeout (s) (0 = disabled):")
                            Spacer()
                            Text("\(autoHideTimeout)")
                            Stepper("", value: $autoHideTimeout, in: 0...60)
                                .labelsHidden()
                                .onChange(of: autoHideTimeout) { _ in saveConfig() }
                        }

                        Toggle("Navigate with Arrow Keys (←↑↓→)", isOn: $useArrowKeys)
                            .onChange(of: useArrowKeys) { _ in saveConfig() }
                        Toggle("Navigate with Vim Keys (hjkl)", isOn: $useVimKeys)
                            .onChange(of: useVimKeys) { _ in saveConfig() }

                        if useArrowKeys || useVimKeys {
                            Picker("Display Navigation", selection: $displayNavigationWrap) {
                                Text("Wrap Within Display").tag(DisplayNavigationWrap.within)
                                Text("Wrap Between Displays").tag(DisplayNavigationWrap.between)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: displayNavigationWrap) { _ in saveConfig() }
                            SettingsFootnote(text: displayNavigationWrap == .within
                                ? "Keeps navigation within the display containing the focused space."
                                : "Allows navigation to wrap from one display's spaces into another's.")
                        }

                        Toggle("Focus Space After Window Drop", isOn: $focusSpaceOnWindowDrop)
                            .onChange(of: focusSpaceOnWindowDrop) { _ in saveConfig() }
                        SettingsFootnote(text: "Switches to the destination space after a dragged window is moved.")

                        Toggle("Hide Menu Bar Icon", isOn: $hideMenuBarIcon)
                            .onChange(of: hideMenuBarIcon) { _ in saveConfig() }

                        if hideMenuBarIcon {
                            SettingsFootnote(text: "Access settings by relaunching the app or pressing ⌘, while the HUD is open.")
                        }

                        Picker("Automatic Updates", selection: $updateMode) {
                            Text("Auto").tag(UpdateMode.auto)
                            Text("Notify").tag(UpdateMode.notify)
                            Text("Off").tag(UpdateMode.off)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: updateMode) { newValue in
                            if newValue != previousUpdateMode {
                                saveConfig()
                                previousUpdateMode = newValue
                            }
                        }

                        Button("Check for Updates...") {
                            (NSApp.delegate as? AppDelegate)?.checkForUpdates()
                        }
                    }
                case .advanced:
                    Section(header: settingsSectionHeader("Debug/Advanced")) {
                        Picker("Socket Health Interval (s)", selection: $socketHealthInterval) {
                            ForEach(socketHealthOptions, id: \.self) { v in
                                Text("\(v)").tag(v as Int)
                            }
                        }
                        .onChange(of: socketHealthInterval) { _ in saveConfig() }
                    }
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
            let config = ConfigReader.load()
            lastCustomHUDX = config.customHUDX
            lastCustomHUDY = config.customHUDY
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .textCase(nil)
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
    }

    private func sidebarIcon(for section: SidebarSection) -> String {
        switch section {
        case .grid: return "square.grid.2x2"
        case .spaceNames: return "textformat"
        case .appearance: return "paintbrush"
        case .behavior: return "slider.horizontal.3"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    private var cellStyleString: String {
        switch cellStyle {
        case .rects: return "rects"
        case .icons: return "icons"
        case .thumbnails: return "thumbnails"
        case .simple: return "simple"
        }
    }
    
    private var showModeString: String {
        switch showMode {
        case .all: return "all"
        case .active: return "active"
        }
    }
    
    private var modeString: String {
        switch mode {
        case .light: return "light"
        case .dark: return "dark"
        case .auto: return "auto"
        }
    }
    
    private func binding(for spaceIndex: Int) -> Binding<String> {
        return Binding(
            get: { self.spaceNameInputs[spaceIndex, default: ""] },
            set: { self.spaceNameInputs[spaceIndex] = $0 }
        )
    }
    
    static func hotkeyStringFrom(_ hotkey: HotkeyConfig) -> String {
        return ConfigReader.hotkeyToString(hotkey)
    }
}

// MARK: - HotkeyRecorder

struct HotkeyRecorder: View {
    let label: String
    @Binding var hotkey: String
    @State private var isRecording = false
    @State private var monitors: [Any] = []
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 6) {
                Button(action: {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                            .font(.system(size: 12, weight: .semibold))
                        Text(displayTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isRecording {
                            Text("Press a key")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .frame(width: 210, alignment: .leading)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                )
                .contentShape(Rectangle())

                Button(action: clearHotkey) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Clear hotkey")
                .disabled(hotkey.isEmpty || hotkey == "none" || isRecording)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var displayTitle: String {
        if isRecording { return "Recording" }
        if hotkey.isEmpty || hotkey == "none" { return "None" }
        return hotkey
    }
    
    private func startRecording() {
        isRecording = true
        if let localKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: { event in
                guard self.isRecording else { return event }
                self.handleKeyDown(event)
                return nil
            }
        ) {
            monitors.append(localKeyMonitor)
        }
        if let localMediaMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.systemDefined],
            handler: { event in
                guard self.isRecording else { return event }
                return self.handleSystemDefined(event) ? nil : event
            }
        ) {
            monitors.append(localMediaMonitor)
        }
        if let keyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown],
            handler: { event in
                self.handleKeyDown(event)
            }
        ) {
            monitors.append(keyMonitor)
        }
        if let mediaMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.systemDefined],
            handler: { event in
                _ = self.handleSystemDefined(event)
            }
        ) {
            monitors.append(mediaMonitor)
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isRecording else { return }

        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.option) { parts.append("alt") }
        if flags.contains(.shift) { parts.append("shift") }

        let keyString: String
        switch Int(event.keyCode) {
        case 49: keyString = "space"
        case 48: keyString = "tab"
        case 36: keyString = "return"
        case 53: keyString = "escape"
        case 51: keyString = "delete"
        case 76: keyString = "delete"
        case 121: keyString = "pgdn"
        case 116: keyString = "pgup"
        case 115: keyString = "home"
        case 119: keyString = "end"
        case 123: keyString = "left"
        case 124: keyString = "right"
        case 125: keyString = "down"
        case 126: keyString = "up"
        case 122: keyString = "f1"
        case 120: keyString = "f2"
        case 99:  keyString = "f3"
        case 118: keyString = "f4"
        case 96:  keyString = "f5"
        case 97:  keyString = "f6"
        case 98:  keyString = "f7"
        case 100: keyString = "f8"
        case 101: keyString = "f9"
        case 109: keyString = "f10"
        case 103: keyString = "f11"
        case 111: keyString = "f12"
        case 105: keyString = "f13"
        case 107: keyString = "f14"
        case 113: keyString = "f15"
        case 106: keyString = "f16"
        case 64:  keyString = "f17"
        case 79:  keyString = "f18"
        case 80:  keyString = "f19"
        case 90:  keyString = "f20"
        default:
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                keyString = String(chars.lowercased().first!)
            } else {
                keyString = "\(event.keyCode)"
            }
        }

        parts.append(keyString)
        finishRecording(with: parts.joined(separator: "+"))
    }

    private func handleSystemDefined(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return false }
        let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
        let keyState = ((event.data1 & 0x0000FFFF) >> 8) & 0x0F
        guard keyState == 0xA || keyState == 0xB else { return false }
        guard let keyString = mediaKeyString(for: keyCode) else { return false }
        finishRecording(with: keyString)
        return true
    }

    private func mediaKeyString(for keyCode: Int) -> String? {
        switch keyCode {
        case 16: return "play-pause"
        case 17: return "next-track"
        case 18: return "previous-track"
        case 0: return "volume-up"
        case 1: return "volume-down"
        case 7: return "mute"
        case 2: return "brightness-up"
        case 3: return "brightness-down"
        default: return nil
        }
    }

    private func finishRecording(with recorded: String) {
        DispatchQueue.main.async {
            hotkey = recorded
            stopRecording()
        }
    }

    private func clearHotkey() {
        guard !isRecording else { return }
        hotkey = "none"
    }
    
    private func stopRecording() {
        isRecording = false
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
