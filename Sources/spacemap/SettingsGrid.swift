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
    @Binding var showSpaceLayout: Bool
    @Binding var showBSPLayoutBadge: Bool
    @Binding var showStackLayoutBadge: Bool
    @Binding var showFloatLayoutBadge: Bool
    @Binding var showIconStrip: Bool
    @Binding var showMultiAppIcons: Bool
    @Binding var hudIconSource: GlyphStripIconSource
    @Binding var hudIconStripSeparate: Bool
    @Binding var hudIconStripSource: GlyphStripIconSource
    @Binding var showThumbnailWallpaper: Bool

    private var maxSpacesOptions: [Int] {
        Array(1...16)
    }

    private var gridLayouts: [(cols: Int, rows: Int, label: String)] {
        Self.layoutOptions(maxSpaces: maxSpaces, currentCols: cols, currentRows: rows)
    }

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Grid").settingsAnchor("grid")) {
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
            }

            GlassSegmentedPicker("Show Mode", selection: $showMode, options: [
                (title: "All Spaces", value: .all),
                (title: "Active Spaces", value: .active),
            ])

            GlassSegmentedPicker("Multi-Monitor HUD", selection: $multiMonitorHUDMode, options: [
                (title: "Unified Grid", value: .unified),
                (title: "Separate HUDs", value: .separate),
            ])

            SettingsFootnote(text: multiMonitorHUDMode == .separate
                ? "Shows one grid on each display and keeps keyboard navigation on the focused display."
                : "Shows every space in one grid; keyboard navigation can cross displays.")

            if multiMonitorHUDMode == .unified {
                GlassSegmentedPicker("Unified Grid", selection: $unifiedHUDVisibility, options: [
                    (title: "Active Display Only", value: .active),
                    (title: "All Displays", value: .all),
                ])
                SettingsFootnote(text: unifiedHUDVisibility == .active
                    ? "Shows the unified grid on the display containing yabai's focused space."
                    : "Shows the same unified grid on every display at once.")
            }

            if multiMonitorHUDMode == .separate {
                GlassSegmentedPicker("Separate HUDs", selection: $separateHUDVisibility, options: [
                    (title: "All Displays", value: .all),
                    (title: "Active Display Only", value: .active),
                ])
                SettingsFootnote(text: separateHUDVisibility == .active
                    ? "Shows the HUD only on the display containing yabai's focused space."
                    : "Shows a HUD on every display at once.")
            }

            GlassSegmentedPicker("Cell Style", selection: $cellStyle, options: [
                (title: "Rectangles", value: .rects),
                (title: "Hybrid", value: .hybrid),
                (title: "Icons", value: .icons),
                (title: "Thumbnails", value: .thumbnails),
                (title: "Simple", value: .simple),
            ])
            .onChange(of: cellStyle) { style in
                if style == .thumbnails { SystemPermissions.requestScreenRecordingOrOpenSettings() }
            }
            if cellStyle == .thumbnails {
                Toggle("Show Wallpaper in Thumbnails", isOn: $showThumbnailWallpaper)
                SettingsFootnote(text: "Draws the desktop wallpaper behind the windows. Turn it off for thumbnails that are easier to read on busy desktops.")
            }

            Toggle(showSpaceNumbersTitle, isOn: $showSpaceNumbers)
            Toggle("Show Space Layout", isOn: $showSpaceLayout)
                .disabled(!showSpaceNumbers)
            if showSpaceLayout {
                Toggle("Show BSP Layout (b)", isOn: $showBSPLayoutBadge)
                Toggle("Show Stack Layout (s)", isOn: $showStackLayoutBadge)
                Toggle("Show Float Layout (f)", isOn: $showFloatLayoutBadge)
                SettingsFootnote(text: "Pick the layout letters the HUD badge draws. A hidden letter still applies to the space; it just leaves the badge blank.")
            }
            Toggle("Show Icon Strip", isOn: $showIconStrip)

            if showIconStrip {
                Toggle("Show Icon Per Window", isOn: $showMultiAppIcons)
                Picker("Cell Icon Style", selection: $hudIconSource) {
                    Text("Native App Icons").tag(GlyphStripIconSource.nativeIcons)
                    Text("App Font Glyphs").tag(GlyphStripIconSource.sbarFont)
                }
                SettingsFootnote(text: "Used by hybrid and icon cells. App Font Glyphs need the sketchybar-app-font installed.")

                Toggle("Separate Icon Strip Style", isOn: $hudIconStripSeparate)
                if hudIconStripSeparate {
                    Picker("Icon Strip Style", selection: $hudIconStripSource) {
                        Text("Native App Icons").tag(GlyphStripIconSource.nativeIcons)
                        Text("App Font Glyphs").tag(GlyphStripIconSource.sbarFont)
                    }
                } else {
                    SettingsFootnote(text: "The strip follows the cell icon style.")
                }
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
