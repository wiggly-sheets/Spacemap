import SwiftUI

struct SettingsGrid: View {
    @Binding var maxSpaces: Int
    @Binding var gridLayoutIndex: Int
    @Binding var cols: Int
    @Binding var rows: Int
    @Binding var showMode: ShowMode
    @Binding var multiMonitorHUDMode: MultiMonitorHUDMode
    @Binding var unifiedHUDVisibility: SeparateHUDVisibility
    @Binding var separateHUDVisibility: SeparateHUDVisibility
    @Binding var cellStyle: CellStyle
    @Binding var showSpaceNumbers: Bool
    @Binding var showIconStrip: Bool
    @Binding var showMultiAppIcons: Bool

    let onSave: () -> Void

    private var maxSpacesOptions: [Int] {
        Array(1...16)
    }

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

    var body: some View {
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
                onSave()
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
                onSave()
            }

            Picker("Show Mode", selection: $showMode) {
                Text("All Spaces").tag(ShowMode.all)
                Text("Active Spaces").tag(ShowMode.active)
            }
            .pickerStyle(.segmented)
            .onChange(of: showMode) { _ in onSave() }

            Picker("Multi-Monitor HUD", selection: $multiMonitorHUDMode) {
                Text("Unified Grid").tag(MultiMonitorHUDMode.unified)
                Text("Separate HUDs").tag(MultiMonitorHUDMode.separate)
            }
            .pickerStyle(.segmented)
            .onChange(of: multiMonitorHUDMode) { _ in onSave() }

            SettingsFootnote(text: multiMonitorHUDMode == .separate
                ? "Shows one grid on each display and keeps keyboard navigation on the focused display."
                : "Shows every space in one grid; keyboard navigation can cross displays.")

            if multiMonitorHUDMode == .unified {
                Picker("Unified Grid", selection: $unifiedHUDVisibility) {
                    Text("Active Display Only").tag(SeparateHUDVisibility.active)
                    Text("All Displays").tag(SeparateHUDVisibility.all)
                }
                .pickerStyle(.segmented)
                .onChange(of: unifiedHUDVisibility) { _ in onSave() }
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
                .onChange(of: separateHUDVisibility) { _ in onSave() }
                SettingsFootnote(text: separateHUDVisibility == .active
                    ? "Shows the HUD only on the display containing yabai's focused space."
                    : "Shows a HUD on every display at once.")
            }

            Picker("Cell Style", selection: $cellStyle) {
                Text("Rectangles").tag(CellStyle.rects)
                Text("Hybrid").tag(CellStyle.hybrid)
                Text("Icons").tag(CellStyle.icons)
                Text("Thumbnails").tag(CellStyle.thumbnails)
                Text("Simple").tag(CellStyle.simple)
            }
            .pickerStyle(.segmented)
            .onChange(of: cellStyle) { _ in onSave() }

            Toggle("Show Space Numbers", isOn: $showSpaceNumbers)
                .onChange(of: showSpaceNumbers) { _ in onSave() }
            Toggle("Show Icon Strip", isOn: $showIconStrip)
                .onChange(of: showIconStrip) { _ in onSave() }

            if showIconStrip {
                Toggle("Show Icon Per Window", isOn: $showMultiAppIcons)
                    .onChange(of: showMultiAppIcons) { _ in onSave() }
            }
        }
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .textCase(nil)
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
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
}