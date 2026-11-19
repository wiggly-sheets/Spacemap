import SwiftUI
import AppKit

/// Edits one theme in place and saves it as a TOML file in the themes folder.
/// Every colour accepts a typed `#RRGGBB` value or the system colour picker;
/// the two stay in sync, and saving reloads the store so the rest of the app
/// picks the file up.
struct SettingsThemeEditor: View {
    @Binding var theme: String
    let themeStore: ThemeStore

    @State private var name = ""
    @State private var hexes: [String: String] = [:]
    /// Last text that parsed per field. An invalid field keeps showing what the
    /// user typed, and the picker keeps this value instead of turning black.
    @State private var lastValid: [String: String] = [:]
    @State private var status: String?

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Theme Editor").settingsAnchor("appearance.themeEditor")) {
            HStack {
                TextField("Theme Name", text: $name)
                Button("Load Selected") { load(theme) }
                    .liquidGlassButtonStyle()
            }
            SettingsFootnote(text: "Load Selected copies the selected theme into the fields below. Saving an existing theme writes a separate \"(Edited)\" copy, so the original stays untouched. Change the name to create a new theme instead.")

            ForEach(AppTheme.colorNames, id: \.self) { key in
                HStack {
                    Text(label(for: key))
                    Spacer()
                    TextField("#RRGGBB", text: hexBinding(key))
                        .frame(width: 96)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(isInvalid(key) ? .red : .primary)
                    ColorPicker("", selection: colorBinding(key), supportsOpacity: false)
                        .labelsHidden()
                }
            }

            HStack {
                Button("Start From Basic") {
                    name = "my theme"
                    hexes = Self.hexes(from: .default)
                    lastValid = hexes
                    status = nil
                }
                .liquidGlassButtonStyle()
                Button("Save Theme") { save() }
                    .liquidGlassButtonStyle()
                    .disabled(composedTheme == nil)
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsFootnote(text: "A field that is not a six-digit hex value turns red and blocks saving. Saving writes a TOML theme into ~/.config/spacemap/themes and selects it. Saving a bundled or installed theme creates an (Edited) copy; saving that copy updates it. External edits reload on Load Selected or the next Settings open.")
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
        themeStore.reloadIfChanged()
        let loaded = themeStore.named(themeName)
        name = themeName
        hexes = Self.hexes(from: loaded)
        lastValid = hexes
        status = nil
    }

    private func isInvalid(_ key: String) -> Bool {
        ThemeCodec.parseHexValue(hexes[key] ?? "") == nil
    }

    private func hexBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { hexes[key] ?? "000000" },
            set: { raw in
                hexes[key] = raw
                if ThemeCodec.parseHexValue(raw) != nil {
                    lastValid[key] = raw
                }
            }
        )
    }

    private func colorBinding(_ key: String) -> Binding<Color> {
        Binding(
            get: { Self.color(isInvalid(key) ? lastValid[key] : hexes[key]) },
            set: { color in
                let hex = Self.hex(from: color)
                hexes[key] = hex
                lastValid[key] = hex
            }
        )
    }

    private func save() {
        guard let composedTheme else {
            status = "Fix the highlighted hex values"
            return
        }
        guard let saved = themeStore.save(theme: composedTheme, name: name) else {
            status = "Could not save"
            return
        }
        theme = saved
        self.name = saved
        status = "Saved \(saved)"
        load(saved)
    }

    /// Nil while any field is not a hex colour, so a bad value can never be
    /// saved as black.
    private var composedTheme: AppTheme? {
        ThemeCodec.theme(fromHexes: hexes)
    }

    private static func hexes(from theme: AppTheme) -> [String: String] {
        Dictionary(uniqueKeysWithValues: AppTheme.colorNames.map { key in
            (key, ThemeCodec.hex(theme.value(for: key) ?? 0))
        })
    }

    private static func color(_ hex: String?) -> Color {
        guard let value = ThemeCodec.parseHexValue(hex ?? "") else { return .black }
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
        return ThemeCodec.hex((red << 16) | (green << 8) | blue)
    }
}
