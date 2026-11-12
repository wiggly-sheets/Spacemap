import SwiftUI

/// Native segmented picker. macOS 26+ renders it with Liquid Glass when the
/// app links against the current SDK; older systems keep the classic look.
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
            Picker("", selection: $selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
