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
        Self.layoutOptions(maxSpaces: maxSpaces, currentCols: cols, currentRows: rows)
    }

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Grid")) {
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

            Toggle(showSpaceNumbersTitle, isOn: $showSpaceNumbers)
                .onChange(of: showSpaceNumbers) { _ in onSave() }
            Toggle("Show Icon Strip", isOn: $showIconStrip)
                .onChange(of: showIconStrip) { _ in onSave() }

            if showIconStrip {
                Toggle("Show Icon Per Window", isOn: $showMultiAppIcons)
                    .onChange(of: showMultiAppIcons) { _ in onSave() }
            }
        }
    }

    private func findBestGridLayoutIndex() -> Int {
        Self.layoutIndex(
            maxSpaces: maxSpaces,
            currentCols: cols,
            currentRows: rows
        )
    }

    static func layoutOptions(
        maxSpaces: Int,
        currentCols: Int,
        currentRows: Int
    ) -> [(cols: Int, rows: Int, label: String)] {
        guard maxSpaces > 0 else { return [] }
        var layouts = (1...maxSpaces).compactMap { columns -> (Int, Int, String)? in
            guard maxSpaces.isMultiple(of: columns) else { return nil }
            let rows = maxSpaces / columns
            return (columns, rows, "\(columns)×\(rows)")
        }
        if !layouts.contains(where: { $0.0 == currentCols && $0.1 == currentRows }) {
            layouts.append((currentCols, currentRows, "\(currentCols)×\(currentRows) (Custom)"))
        }
        return layouts
    }

    static func layoutIndex(maxSpaces: Int, currentCols: Int, currentRows: Int) -> Int {
        layoutOptions(
            maxSpaces: maxSpaces,
            currentCols: currentCols,
            currentRows: currentRows
        ).firstIndex(where: { $0.cols == currentCols && $0.rows == currentRows }) ?? 0
    }
}
