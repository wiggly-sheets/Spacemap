import SwiftUI
import Foundation
import AppKit

struct SettingsAppearanceView: View {
    @Binding var theme: String
    @Binding var mode: ThemeMode
    @Binding var backgroundAlpha: Double
    @Binding var backgroundStyle: HUDBackgroundStyle
    @Binding var glassStyle: HUDGlassStyle
    @Binding var glassClearOpacity: Double
    @Binding var glassOpaqueOpacity: Double
    @Binding var glassTintedOpacity: Double
    @Binding var solidOpacity: Double
    @Binding var matchBackgroundOpacity: Bool
    @Binding var hudShadow: Bool
    @Binding var iconScale: Double
    @Binding var uiScale: Double

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
                (title: "Transparent", value: .transparent),
            ])
            .onChange(of: backgroundStyle) { _ in onSave() }

            if backgroundStyle == .glass {
                GlassSegmentedPicker("Glass Style", selection: $glassStyle, options: [
                    (title: "Clear", value: .clear),
                    (title: "Opaque", value: .opaque),
                    (title: "Tinted", value: .tinted),
                ])
                .onChange(of: glassStyle) { _ in onSave() }
                SettingsFootnote(text: "Clear matches the left of the native Liquid Glass slider, Opaque the right, and Tinted adds the theme colour.")
            }

            if backgroundStyle != .transparent {
                Toggle("Use Same Opacity for All Styles", isOn: matchOpacityBinding)
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
                        ? "Solid stays unblurred; lower opacity simply lets the desktop show through."
                        : "Controls how much backing sits behind the glass blur."
                )
            }

            Toggle("Draw HUD Shadow", isOn: $hudShadow)
                .onChange(of: hudShadow) { _ in onSave() }

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
            case .opaque: return $glassOpaqueOpacity
            case .tinted: return $glassTintedOpacity
            }
        case .transparent:
            return $backgroundAlpha
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
        Self.steps(
            [0.00, 0.05, 0.12, 0.22, 0.35, 0.50, 0.65, 0.80, 0.92, 1.00],
            including: activeStyleOpacity.wrappedValue
        )
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
