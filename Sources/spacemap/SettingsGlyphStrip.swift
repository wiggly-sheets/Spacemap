import SwiftUI
import Foundation
import CoreGraphics
import AppKit

/// Settings pane for the always-visible menu-bar glyph strip.
///
/// One `@Binding` to the whole `GlyphStripConfig`; every control writes through
/// `onSave`, which is the same path every other settings pane uses.
struct SettingsGlyphStrip: View {

    @Binding var glyphStrip: GlyphStripConfig
    /// Name of the theme selected in the Appearance pane. The strip's palette
    /// resolves against it when the strip follows the main HUD.
    let themeName: String

    let onSave: () -> Void

    /// Built once and reused: a fresh `ThemeService()` per render re-reads the
    /// whole themes directory on every keystroke. Reloaded when the pane opens
    /// so `.smthemes` edits show up without rebuilding the view.
    private static let themeService = ThemeService()

    /// The strip's own theme, or the main HUD's when it follows it.
    private var effectiveThemeName: String {
        glyphStrip.theme.isEmpty ? themeName : glyphStrip.theme
    }

    private var theme: AppTheme { Self.themeService.named(effectiveThemeName) }

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Glyph Strip")) {
            Toggle("Enabled", isOn: $glyphStrip.enabled)
                .onChange(of: glyphStrip.enabled) { _ in onSave() }
            SettingsFootnote(text: "Each space shows its index plus a glyph per window.")

            Picker("Position", selection: $glyphStrip.position) {
                Text("Left of Notch").tag(GlyphStripPosition.leftOfNotch)
                Text("Right of Notch").tag(GlyphStripPosition.rightOfNotch)
                Text("Center").tag(GlyphStripPosition.center)
                Text("Custom").tag(GlyphStripPosition.custom)
            }
            .onChange(of: glyphStrip.position) { _ in onSave() }

            if glyphStrip.position == .custom {
                stepper("Horizontal Offset", value: $glyphStrip.xOffset, range: -4000...4000)
                    .onChange(of: glyphStrip.xOffset) { _ in onSave() }
                SettingsFootnote(text: "Distance from the left edge of the menu bar row. Vertical Offset in Appearance moves the strip up or down.")
            }

            stepper("Notch Margin", value: $glyphStrip.margin, range: 0...40, step: 1)
                .onChange(of: glyphStrip.margin) { _ in onSave() }
            SettingsFootnote(text: "Gap between the strip and the edge of the notch area.")

            Section(header: SettingsSectionHeader(title: "Contents")) {
                Toggle(showSpaceNumbersTitle, isOn: $glyphStrip.showSpaceNumbers)
                    .onChange(of: glyphStrip.showSpaceNumbers) { _ in onSave() }
                Toggle("Show Layout Suffix (f / s)", isOn: $glyphStrip.showLayoutSuffix)
                    .onChange(of: glyphStrip.showLayoutSuffix) { _ in onSave() }
                SettingsFootnote(text: "Floating spaces are marked f, stack spaces s, bsp spaces unmarked.")
                Toggle("Show App Icons", isOn: $glyphStrip.showAppIcons)
                    .onChange(of: glyphStrip.showAppIcons) { _ in onSave() }
                Picker("Icon Source", selection: $glyphStrip.iconSource) {
                    Text("App Font").tag(GlyphStripIconSource.sbarFont)
                    Text("Native Icons").tag(GlyphStripIconSource.nativeIcons)
                }
                .onChange(of: glyphStrip.iconSource) { _ in onSave() }
                SettingsFootnote(text: "App Font draws sketchybar-app-font glyphs. Native Icons draws each app's own icon, falling back to the app-font glyph then initials when unavailable.")
                Toggle("One Glyph Per App", isOn: $glyphStrip.dedupeAppsPerSpace)
                    .onChange(of: glyphStrip.dedupeAppsPerSpace) { _ in onSave() }
                SettingsFootnote(text: "When on, an app with several windows on one space shows a single glyph.")
                Toggle("Show Empty Space Placeholder", isOn: $glyphStrip.showPlaceholders)
                    .onChange(of: glyphStrip.showPlaceholders) { _ in onSave() }
                Toggle("Show Display Separators", isOn: $glyphStrip.showDisplaySeparators)
                    .onChange(of: glyphStrip.showDisplaySeparators) { _ in onSave() }
                SettingsFootnote(text: "Draws a | between spaces that sit on different displays.")
                Toggle("Show Add Space Button", isOn: $glyphStrip.showAddSpaceButton)
                    .onChange(of: glyphStrip.showAddSpaceButton) { _ in onSave() }

                stepper("Icons Per Space (0 = unlimited)", value: $glyphStrip.maxIconsPerSpace, range: 0...16)
                    .onChange(of: glyphStrip.maxIconsPerSpace) { _ in onSave() }
                SettingsFootnote(text: "Extra windows on a space collapse into a +N indicator once this cap is reached.")
            }

            Section(header: SettingsSectionHeader(title: "Appearance")) {
                Picker("Theme", selection: $glyphStrip.theme) {
                    Text("Follow main HUD").tag("")
                    ForEach(Self.themeService.allNames(), id: \.self) { name in
                        Text(name.capitalized).tag(name)
                    }
                }
                .onChange(of: glyphStrip.theme) { _ in onSave() }
                SettingsFootnote(text: "Glyphs, fills and the glass edge resolve against this theme. Follow main HUD uses the theme from the Appearance pane.")

                stepper("Icon Size", value: $glyphStrip.iconSize, range: 6...24, step: 1)
                    .onChange(of: glyphStrip.iconSize) { _ in onSave() }
                stepper("Space Number Size", value: $glyphStrip.indexSize, range: 6...24, step: 1)
                    .onChange(of: glyphStrip.indexSize) { _ in onSave() }
                stepper("Icon Spacing", value: $glyphStrip.iconSpacing, range: 0...20, step: 0.5)
                    .onChange(of: glyphStrip.iconSpacing) { _ in onSave() }
                stepper("Index Padding", value: $glyphStrip.indexPadding, range: 0...20, step: 0.5)
                    .onChange(of: glyphStrip.indexPadding) { _ in onSave() }
                SettingsFootnote(text: "Icon Spacing is the extra gap between two app icons. Index Padding is the gap between a space's number and its first icon.")
                stepper("Vertical Offset", value: $glyphStrip.yOffset, range: -10...10, step: 0.5)
                    .onChange(of: glyphStrip.yOffset) { _ in onSave() }
                SettingsFootnote(text: "Positive moves the strip down, into the screen interior. 0 is centered. Negative moves it up toward the top edge.")
                Toggle("Highlight Current Space", isOn: $glyphStrip.highlightCurrentSpace)
                    .onChange(of: glyphStrip.highlightCurrentSpace) { _ in onSave() }
                SettingsFootnote(text: "Colours come from the \(effectiveThemeName.capitalized) theme — the current space, the + button and the hover highlight use focused, everything else uses text. No per-element colour keys.")

                Picker("Background Material", selection: $glyphStrip.backgroundMaterial) {
                    Text("None").tag(GlyphStripBackgroundMaterial.none)
                    Text("Solid").tag(GlyphStripBackgroundMaterial.solid)
                    Text("Liquid Glass").tag(GlyphStripBackgroundMaterial.liquidGlass)
                }
                .onChange(of: glyphStrip.backgroundMaterial) { _ in onSave() }
                if glyphStrip.backgroundMaterial == .liquidGlass {
                    Toggle("Theme Tint", isOn: $glyphStrip.useThemeTint)
                        .onChange(of: glyphStrip.useThemeTint) { _ in onSave() }
                    SettingsFootnote(text: "When off, the glass stays neutral with no theme colour.")
                    if glyphStrip.useThemeTint {
                        // Mirrors System Settings > Appearance > Liquid Glass:
                        // continuous 0...100% with 3 notches, centre default.
                        HStack {
                            Text("Glass Amount")
                            Spacer()
                            Text("\(Int((glyphStrip.glassAmount * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { glyphStrip.glassAmount * 100 },
                                set: { glyphStrip.glassAmount = min(max($0 / 100, 0), 1) }
                            ),
                            in: 0...100,
                            step: 1
                        )
                        .onChange(of: glyphStrip.glassAmount) { _ in onSave() }
                        HStack {
                            Text("Clear")
                            Spacer()
                            Text("Default")
                            Spacer()
                            Text("Tinted")
                        }
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }
                }

                Picker("Shape", selection: $glyphStrip.shape) {
                    Text("None").tag(GlyphStripShape.none)
                    Text("Pill").tag(GlyphStripShape.pill)
                    Text("Rounded Rectangle").tag(GlyphStripShape.roundedRect)
                    Text("Bar").tag(GlyphStripShape.bar)
                }
                .onChange(of: glyphStrip.shape) { _ in onSave() }
                SettingsFootnote(text: "None draws no background shape. Pill is fully rounded ends, Rounded Rectangle uses the corner radius below, Bar is square ends.")
                // Shapes the background (and the glass mask). Pill and Bar ignore
                // it; the hover highlight has its own radius below.
                if glyphStrip.shape == .roundedRect {
                    stepper("Background Corner Radius", value: $glyphStrip.cornerRadius, range: 0...40, step: 1)
                        .onChange(of: glyphStrip.cornerRadius) { _ in onSave() }
                }

                Toggle("Outline", isOn: $glyphStrip.borderEnabled)
                    .onChange(of: glyphStrip.borderEnabled) { _ in onSave() }
                SettingsFootnote(text: "Hairline outline around the strip, independent of the material. With none it outlines the plain strip bounds.")

                if glyphStrip.backgroundMaterial == .solid {
                    // Liquid Glass derives its translucency from the system
                    // material, so opacity applies to the solid fill only.
                    HStack {
                        Text("Background Opacity")
                        Spacer()
                        Text("\(Int((glyphStrip.backgroundOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { glyphStrip.backgroundOpacity * 100 },
                            set: { glyphStrip.backgroundOpacity = min(max($0 / 100, 0.01), 1) }
                        ),
                        in: 1...100,
                        step: 1
                    )
                    .onChange(of: glyphStrip.backgroundOpacity) { _ in onSave() }
                }
            }

            Section(header: SettingsSectionHeader(title: "Hover Highlight")) {
                stepper("Hover Padding", value: $glyphStrip.hoverPadding, range: 0...12, step: 0.5)
                    .onChange(of: glyphStrip.hoverPadding) { _ in onSave() }
                stepper("Hover Corner Radius", value: $glyphStrip.hoverCornerRadius, range: 0...20, step: 0.5)
                    .onChange(of: glyphStrip.hoverCornerRadius) { _ in onSave() }
                SettingsFootnote(text: "The highlight is the hovered segment's glyph box grown by Hover Padding on both axes, not the height of the menu bar, and hover only arms within it.")
            }

            Section(header: SettingsSectionHeader(title: "Clicks")) {
                actionPicker("Left Click", selection: $glyphStrip.leftClickAction)
                    .onChange(of: glyphStrip.leftClickAction) { _ in onSave() }
                actionPicker("Right Click", selection: $glyphStrip.rightClickAction)
                    .onChange(of: glyphStrip.rightClickAction) { _ in onSave() }
                actionPicker("Middle Click", selection: $glyphStrip.middleClickAction)
                    .onChange(of: glyphStrip.middleClickAction) { _ in onSave() }
                SettingsFootnote(text: "Destroy Space takes effect immediately with no confirmation. Window actions apply to the focused window; Merge Windows moves every window of the clicked space into the current one.")
            }
        }
        .onAppear { Self.themeService.reload() }
    }

    private func actionPicker(_ label: String, selection: Binding<GlyphStripAction>) -> some View {
        Picker(label, selection: selection) {
            ForEach(GlyphStripAction.allCases) { action in
                Text(Self.label(for: action)).tag(action)
            }
        }
    }

    private static func label(for action: GlyphStripAction) -> String {
        switch action {
        case .none: return "None"
        case .focusSpace: return "Focus Space"
        case .destroySpace: return "Destroy Space"
        case .moveWindowHere: return "Move Focused Window Here"
        case .toggleFullscreen: return "Toggle Fullscreen"
        case .floatWindow: return "Float Window"
        case .balanceWindows: return "Balance Windows"
        case .mergeWindows: return "Merge Windows"
        }
    }
}
