import SwiftUI

struct SettingsSpaceNames: View {
    @Binding var showSpaceNames: Bool
    @Binding var spaceNameInputs: [Int: String]
    @Binding var maxSpaces: Int
    var onSave: () -> Void

    var body: some View {
        Section(header: settingsSectionHeader("Space Names")) {
            Toggle("Show Space Names", isOn: $showSpaceNames)
                .onChange(of: showSpaceNames) { _ in onSave() }

            if showSpaceNames {
                Text("(Each input below corresponds to each space number, up to Max Spaces)")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                let maxSpacesOptions = Array(1...16)
                ForEach(maxSpacesOptions, id: \.self) { spaceIndex in
                    if spaceIndex <= maxSpaces {
                        HStack {
                            Text("Space \(spaceIndex):")
                                .frame(width: 80, alignment: .leading)
                            TextField("", text: binding(for: spaceIndex))
                                .textFieldStyle(.roundedBorder)
                                .id("spaceName-\(spaceIndex)")
                                .onChange(of: binding(for: spaceIndex).wrappedValue) { _ in onSave() }
                        }
                        .padding(.vertical, 4)
                    }
                }
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

    private func binding(for spaceIndex: Int) -> Binding<String> {
        return Binding(
            get: { self.spaceNameInputs[spaceIndex, default: ""] },
            set: { self.spaceNameInputs[spaceIndex] = $0 }
        )
    }
}