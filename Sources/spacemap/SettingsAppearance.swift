import SwiftUI
import Foundation
import AppKit

struct SettingsAppearanceView: View {
    @Binding var theme: String
    @Binding var mode: ThemeMode
    @Binding var backgroundAlpha: Double
    @Binding var iconScale: Double
    @Binding var uiScale: Double

    let onSave: () -> Void

    private let themeManager = ThemeManager()

    var body: some View {
        Section(header: settingsSectionHeader("Appearance")) {
            Picker("Theme", selection: $theme) {
                ForEach(themeManager.allNames(), id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }
            .onChange(of: theme) { _ in onSave() }

            HStack {
                Button("Open Config File") {
                    let url = URL(fileURLWithPath: AppConfig().configPath)
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
            .onChange(of: mode) { _ in onSave() }

            VStack(alignment: .leading) {
                Text("Background Transparency")
                    .font(.subheadline)
                CustomStepper(steps: backgroundTransparencySteps, value: $backgroundAlpha)
                    .onChange(of: backgroundAlpha) { _ in onSave() }
            }

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

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .textCase(nil)
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
    }

    private let backgroundTransparencySteps: [Double] = [0.00, 0.05, 0.12, 0.22, 0.35, 0.50, 0.65, 0.80, 0.92, 1.00]
    private let uiScaleSteps: [Double] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    private let iconScaleSteps: [Double] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

    private struct CustomStepper: View {
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
}