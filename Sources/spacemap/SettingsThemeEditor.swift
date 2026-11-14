import SwiftUI
import AppKit

/// Edits one theme in place and saves it as a TOML file in the themes folder.
/// Every colour accepts a typed `#RRGGBB` value or the system colour picker;
/// the two stay in sync, and saving reloads `ThemeManager` so the rest of the
/// app picks the file up.
struct SettingsThemeEditor: View {
    @Binding var theme: String
    let onSave: () -> Void

    @State private var name = ""
    @State private var hexes: [String: String] = [:]
    @State private var status: String?

    private static let themeManager = ThemeManager.shared

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Theme Editor").settingsAnchor("appearance.themeEditor")) {
            HStack {
                TextField("Theme Name", text: $name)
                Button("Load Selected") { load(theme) }
                    .liquidGlassButtonStyle()
            }
            SettingsFootnote(text: "Load Selected copies the selected theme into the fields below. Change the name before saving to create a new theme; keep it to overwrite the file you loaded.")

            ForEach(AppTheme.colorNames, id: \.self) { key in
                HStack {
                    Text(label(for: key))
                    Spacer()
                    TextField("#RRGGBB", text: hexBinding(key))
                        .frame(width: 96)
                        .multilineTextAlignment(.trailing)
                    ColorPicker("", selection: colorBinding(key), supportsOpacity: false)
                        .labelsHidden()
                }
            }

            HStack {
                Button("Start From Basic") {
                    name = "my theme"
                    hexes = Self.hexes(from: .default)
                    status = nil
                }
                .liquidGlassButtonStyle()
                Button("Save Theme") { save() }
                    .liquidGlassButtonStyle()
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsFootnote(text: "Saving writes a TOML theme into ~/.config/spacemap/themes and selects it. External edits reload on Load Selected or the next Settings open.")
        }
        .onAppear { load(theme) }
        .onChange(of: theme) { load($0) }
    }

    private func label(for key: String) -> String {
        switch key {
        case "cellBg": return "Cell Background"
        case "cellBgFocused": return "Cell Background Focused"
        case "dropTarget": return "Drop Target"
        default: return key.capitalized
        }
    }

    private func load(_ themeName: String) {
        let loaded = Self.themeManager.named(themeName)
        name = themeName
        hexes = Self.hexes(from: loaded)
        status = nil
    }

    private func hexBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { hexes[key] ?? "000000" },
            set: { raw in
                hexes[key] = raw
            }
        )
    }

    private func colorBinding(_ key: String) -> Binding<Color> {
        Binding(
            get: { Self.color(hexes[key]) },
            set: { color in
                let hex = Self.hex(from: color)
                hexes[key] = hex
            }
        )
    }

    private func save() {
        guard let saved = ThemeManager.save(theme: composedTheme, name: name) else {
            status = "Could not save"
            return
        }
        theme = saved
        self.name = saved
        status = "Saved \(saved)"
        onSave()
        load(saved)
    }

    private var composedTheme: AppTheme {
        func value(_ key: String) -> UInt32 {
            ThemeManager.parseHexValue(hexes[key] ?? "") ?? 0
        }
        return AppTheme(
            background: value("background"),
            focused: value("focused"),
            text: value("text"),
            dropTarget: value("dropTarget"),
            cellBg: value("cellBg"),
            cellBgFocused: value("cellBgFocused"),
            rect1: value("rect1"),
            rect2: value("rect2"),
            rect3: value("rect3")
        )
    }

    private static func hexes(from theme: AppTheme) -> [String: String] {
        Dictionary(uniqueKeysWithValues: AppTheme.colorNames.map { key in
            (key, ThemeManager.hex(theme.value(for: key) ?? 0))
        })
    }

    private static func color(_ hex: String?) -> Color {
        guard let value = ThemeManager.parseHexValue(hex ?? "") else { return .black }
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        return Color(.sRGB, red: red, green: green, blue: blue)
    }

    private static func hex(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let red = UInt32((ns.redComponent * 255).rounded())
        let green = UInt32((ns.greenComponent * 255).rounded())
        let blue = UInt32((ns.blueComponent * 255).rounded())
        return ThemeManager.hex((red << 16) | (green << 8) | blue)
    }
}
