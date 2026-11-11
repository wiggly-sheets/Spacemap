import SwiftUI

/// Segmented control that becomes a native Liquid Glass button group on
/// macOS 26+ and stays a segmented `Picker` before that.
struct GlassSegmentedPicker<Value: Hashable>: View {
    struct Option: Identifiable {
        let title: String
        let value: Value

        var id: String { title }
    }

    private let title: String
    @Binding private var selection: Value
    private let options: [Option]

    init(_ title: String, selection: Binding<Value>, options: [(title: String, value: Value)]) {
        self.title = title
        self._selection = selection
        self.options = options.map { Option(title: $0.title, value: $0.value) }
    }

    var body: some View {
        LabeledContent(title) {
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        #if compiler(>=6.0)
        if #available(macOS 26.0, *), GlassSupport.isAvailable {
            GlassEffectContainer(spacing: 2) {
                HStack(spacing: 2) {
                    ForEach(options) { option in
                        let isSelected = selection == option.value
                        Button(option.title) {
                            selection = option.value
                        }
                        .controlSize(.small)
                        .liquidGlassButtonStyle(prominent: isSelected)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    @ViewBuilder
    private var fallback: some View {
        Picker("", selection: $selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
