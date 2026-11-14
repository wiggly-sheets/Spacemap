import SwiftUI
import Foundation
import AppKit

struct SettingsAppearanceView: View {
    @Binding var theme: String
    @Binding var mode: ThemeMode
    @Binding var backgroundAlpha: Double
    @Binding var backgroundStyle: HUDBackgroundStyle
    @Binding var glassStyle: HUDGlassStyle
    @Binding var glassClearVariant: Int
    @Binding var glassRegularVariant: Int
    @Binding var glassTintedVariant: Int
    @Binding var glassTintedMaterial: HUDGlassMaterial
    @Binding var glassClearOpacity: Double
    @Binding var glassRegularOpacity: Double
    @Binding var glassTintedOpacity: Double
    @Binding var solidOpacity: Double
    @Binding var matchBackgroundOpacity: Bool
    @Binding var hudShadow: Bool
    @Binding var hudCornerRadius: Double
    @Binding var iconScale: Double
    @Binding var uiScale: Double
    @Binding var spacesMatchBackground: Bool
    @Binding var spacesBackgroundStyle: SpacesBackgroundStyle
    @Binding var spacesGlassStyle: HUDGlassStyle
    @Binding var spacesGlassClearVariant: Int
    @Binding var spacesGlassRegularVariant: Int
    @Binding var spacesGlassTintedVariant: Int
    @Binding var spacesGlassTintedMaterial: HUDGlassMaterial
    @Binding var spacesOpacity: Double
    @Binding var spacesCornerRadius: Double

    let onSave: () -> Void

    private let themeManager = ThemeManager.shared

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Appearance")) {
            Picker("Theme", selection: $theme) {
                ForEach(themeManager.allNames(), id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }
            .onChange(of: theme) { _ in onSave() }

            HStack {
                Button("Open Config File") {
                    let url = URL(fileURLWithPath: AppConfig().configPath)
                    _ = NSWorkspace.shared.open(url)
                }
                .liquidGlassButtonStyle()
                Button("Open Themes Folder") {
                    _ = NSWorkspace.shared.open(ThemeManager.themesDir())
                }
                .liquidGlassButtonStyle()
            }

            GlassSegmentedPicker("Background Color", selection: $mode, options: [
                (title: "Light", value: .light),
                (title: "Dark", value: .dark),
                (title: "Auto", value: .auto),
            ])
            .onChange(of: mode) { _ in onSave() }

            GlassSegmentedPicker("Background Style", selection: $backgroundStyle, options: [
                (title: "Glass", value: .glass),
                (title: "Solid", value: .solid),
            ])
            .onChange(of: backgroundStyle) { _ in onSave() }

            if backgroundStyle == .glass {
                GlassSegmentedPicker("Glass Style", selection: $glassStyle, options: [
                    (title: "Clear", value: .clear),
                    (title: "Regular", value: .regular),
                    (title: "Tinted", value: .tinted),
                ])
                SettingsFootnote(text: "Clear is the native light material, Regular the frosted one, and Tinted adds the theme accent.")
                variantPicker("Glass Finish", selection: glassVariantBinding)
                if glassStyle == .tinted {
                    GlassSegmentedPicker("Tinted Material", selection: $glassTintedMaterial, options: [
                        (title: "Clear", value: .clear),
                        (title: "Regular", value: .regular),
                    ])
                    .onChange(of: glassTintedMaterial) { _ in onSave() }
                }
                SettingsFootnote(text: "Finish is the private macOS glass variant, 0 to 21; results vary by OS and wallpaper. Tinted draws the accent over the chosen material.")
            }

            Toggle("Use Same Opacity for All Styles", isOn: matchOpacityBinding)
                .padding(.top, 4)
                SettingsFootnote(
                    text: matchBackgroundOpacity
                        ? "Clear, opaque, tinted, and solid all share one opacity."
                        : "Each background style keeps its own opacity."
                )
                VStack(alignment: .leading) {
                    Text("Background Opacity")
                        .font(.subheadline)
                    CustomStepper(steps: backgroundOpacitySteps, value: activeStyleOpacity)
                        .onChange(of: activeStyleOpacity.wrappedValue) { _ in onSave() }
                }
                SettingsFootnote(
                    text: backgroundStyle == .solid
                        ? "Solid stays unblurred; lower opacity simply lets the desktop show through, and zero hides the fill."
                        : "Controls how much backing sits behind the glass blur. Glass keeps a minimum so it never turns into a hole."
                )

            Toggle("Draw HUD Shadow", isOn: $hudShadow)
                .onChange(of: hudShadow) { _ in onSave() }

            VStack(alignment: .leading) {
                Text("HUD Corner Radius")
                    .font(.subheadline)
                    .bold()
                CustomStepper(steps: Self.cornerRadiusSteps(including: hudCornerRadius), value: $hudCornerRadius)
                    .onChange(of: hudCornerRadius) { _ in onSave() }
            }
            SettingsFootnote(text: "Rounds the outside edge of the whole HUD panel. Space cells keep their own shape.")

            VStack(alignment: .leading) {
                Text("Icon Scale")
                    .font(.subheadline)
                    .bold()
                CustomStepper(steps: iconScaleSteps, value: $iconScale)
                    .onChange(of: iconScale) { _ in onSave() }
            }

            VStack(alignment: .leading) {
                Text("UI Scale")
                    .font(.subheadline)
                    .bold()
                CustomStepper(steps: uiScaleSteps, value: $uiScale)
                    .onChange(of: uiScale) { _ in onSave() }
            }
        }

        Section(header: SettingsSectionHeader(title: "HUD Spaces")) {
            Toggle("Match HUD Background", isOn: $spacesMatchBackground)
                .onChange(of: spacesMatchBackground) { _ in onSave() }
            SettingsFootnote(text: "On, the space cells stay clear so the panel material shows through. Off, give the cells their own fill drawn on top of the panel.")
            if !spacesMatchBackground {
                GlassSegmentedPicker("Cell Background", selection: $spacesBackgroundStyle, options: [
                    (title: "None", value: .none),
                    (title: "Solid", value: .solid),
                    (title: "Glass", value: .glass),
                ])
                .onChange(of: spacesBackgroundStyle) { _ in onSave() }

                if spacesBackgroundStyle == .glass {
                    GlassSegmentedPicker("Cell Glass Style", selection: $spacesGlassStyle, options: [
                        (title: "Clear", value: .clear),
                        (title: "Regular", value: .regular),
                        (title: "Tinted", value: .tinted),
                    ])
                    .onChange(of: spacesGlassStyle) { _ in onSave() }
                    variantPicker("Cell Finish", selection: spacesVariantBinding)
                    if spacesGlassStyle == .tinted {
                        GlassSegmentedPicker("Cell Tinted Material", selection: $spacesGlassTintedMaterial, options: [
                            (title: "Clear", value: .clear),
                            (title: "Regular", value: .regular),
                        ])
                        .onChange(of: spacesGlassTintedMaterial) { _ in onSave() }
                    }
                }

                VStack(alignment: .leading) {
                    Text("Cell Opacity")
                        .font(.subheadline)
                    CustomStepper(steps: Self.steps([0.0, 0.1, 0.25, 0.5, 0.75, 1.0], including: spacesOpacity), value: $spacesOpacity)
                        .onChange(of: spacesOpacity) { _ in onSave() }
                }
                VStack(alignment: .leading) {
                    Text("Cell Corner Radius")
                        .font(.subheadline)
                    CustomStepper(steps: Self.steps([0, 2, 4, 6, 8, 12, 16, 24], including: spacesCornerRadius), value: $spacesCornerRadius)
                        .onChange(of: spacesCornerRadius) { _ in onSave() }
                }
            }
        }
    }

    private func variantPicker(_ label: String, selection: Binding<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach(0...21, id: \.self) { number in
                Text("Variant \(number)").tag(number)
            }
        }
        .onChange(of: selection.wrappedValue) { _ in onSave() }
    }

    private var glassVariantBinding: Binding<Int> {
        switch glassStyle {
        case .clear: return $glassClearVariant
        case .regular: return $glassRegularVariant
        case .tinted: return $glassTintedVariant
        }
    }

    private var spacesVariantBinding: Binding<Int> {
        switch spacesGlassStyle {
        case .clear: return $spacesGlassClearVariant
        case .regular: return $spacesGlassRegularVariant
        case .tinted: return $spacesGlassTintedVariant
        }
    }

    /// Slider target: the shared value when matching, otherwise the active
    /// style's remembered opacity.
    private var activeStyleOpacity: Binding<Double> {
        guard !matchBackgroundOpacity else { return $backgroundAlpha }
        switch backgroundStyle {
        case .solid:
            return $solidOpacity
        case .glass:
            switch glassStyle {
            case .clear: return $glassClearOpacity
            case .regular: return $glassRegularOpacity
            case .tinted: return $glassTintedOpacity
            }
        }
    }

    /// Turning matching on seeds the shared value from the visible style so
    /// the HUD does not jump.
    private var matchOpacityBinding: Binding<Bool> {
        Binding(
            get: { matchBackgroundOpacity },
            set: { newValue in
                if newValue {
                    backgroundAlpha = activeStyleOpacity.wrappedValue
                }
                matchBackgroundOpacity = newValue
                onSave()
            }
        )
    }

    private var backgroundOpacitySteps: [Double] {
        let steps = Self.steps(
            [0.00, 0.05, 0.12, 0.22, 0.35, 0.50, 0.65, 0.80, 0.92, 1.00],
            including: activeStyleOpacity.wrappedValue
        )
        guard backgroundStyle == .glass else { return steps }
        return steps.filter { $0 >= glassStyle.minimumOpacity }
    }

    private static func cornerRadiusSteps(including value: Double) -> [Double] {
        steps([0, 4, 8, 10, 12, 16, 20, 24, 30, 40, 50, 60], including: value)
    }

    private var uiScaleSteps: [Double] {
        Self.steps([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], including: uiScale)
    }

    private var iconScaleSteps: [Double] {
        Self.steps([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], including: iconScale)
    }

    static func steps(_ defaults: [Double], including currentValue: Double) -> [Double] {
        Array(Set(defaults + [currentValue])).sorted()
    }

    private struct CustomStepper: View {
        let steps: [Double]
        @Binding var value: Double

        var body: some View {
            HStack {
                Button(action: { stepDown() }) {
                    Image(systemName: "minus.circle")
                }
                .disabled(currentIndex == 0)
                .liquidGlassButtonStyle()

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
                .liquidGlassButtonStyle()
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
}
