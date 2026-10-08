import SwiftUI

struct SettingsSpaceNames: View {
    @Binding var showSpaceNames: Bool
    @Binding var spaceNameInputs: [Int: String]
    @Binding var maxSpaces: Int
    @Binding var profiles: [SpaceNameProfile]
    @Binding var activeProfileIndex: Int
    var onSave: () -> Void

    @State private var editingProfileIndex: Int?
    @State private var newProfileName: String = ""

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Space Names")) {
            Toggle("Show Space Names", isOn: $showSpaceNames)
                .onChange(of: showSpaceNames) { _ in onSave() }

            if showSpaceNames {
                SettingsFootnote(text: "Each input corresponds to its space number, up to Max Spaces.")

                ForEach(1...max(1, maxSpaces), id: \.self) { spaceIndex in
                    HStack {
                        Text("Space \(spaceIndex):")
                            .frame(width: 80, alignment: .leading)
                        TextField("", text: binding(for: spaceIndex))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: spaceNameInputs[spaceIndex, default: ""]) { _ in onSave() }
                    }
                }
            }
        }

        Section(header: SettingsSectionHeader(title: "Space Name Profiles")) {
            SettingsFootnote(text: "Each profile stores a set of space names. Switch profiles from the menu bar or here.")

            if profiles.isEmpty {
                Text("No profiles. Click + to add one.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    VStack(alignment: .leading, spacing: 6) {
                        ProfileRow(
                            profile: $profiles[index],
                            isActive: index == activeProfileIndex,
                            isEditing: editingProfileIndex == index,
                            onActivate: {
                                activeProfileIndex = index
                                onSave()
                            },
                            onEdit: {
                                editingProfileIndex = editingProfileIndex == index ? nil : index
                            },
                            onDelete: {
                                deleteProfile(index)
                            },
                            profilesCount: profiles.count
                        )

                        if editingProfileIndex == index {
                            ProfileEditor(profile: $profiles[index], maxSpaces: maxSpaces, onSave: onSave)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                TextField("New profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)

                Button("Add Profile") {
                    addProfile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
    }

    private func binding(for spaceIndex: Int) -> Binding<String> {
        return Binding(
            get: { self.spaceNameInputs[spaceIndex, default: ""] },
            set: { self.spaceNameInputs[spaceIndex] = $0 }
        )
    }

    private func addProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let newProfile = SpaceNameProfile(name: name)
        profiles.append(newProfile)
        newProfileName = ""
        activeProfileIndex = profiles.count - 1
        onSave()
    }

    private func deleteProfile(_ index: Int) {
        guard profiles.count > 1 else { return }
        profiles.remove(at: index)
        if editingProfileIndex == index {
            editingProfileIndex = nil
        }
        if activeProfileIndex >= profiles.count {
            activeProfileIndex = profiles.count - 1
        }
        onSave()
    }
}

struct ProfileRow: View {
    @Binding var profile: SpaceNameProfile
    let isActive: Bool
    let isEditing: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let profilesCount: Int

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(size: 13, weight: .medium))
                    if isActive {
                        Text("Active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .cornerRadius(4)
                    }
                }
                Text("\(nonEmptyNameCount) space names")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isActive {
                Button("Activate") {
                    onActivate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(isEditing ? "Done" : "Edit") {
                onEdit()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Delete") {
                onDelete()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.red)
            .disabled(profilesCount <= 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }

    private var nonEmptyNameCount: Int {
        profile.spaceNames.values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}

struct ProfileEditor: View {
    @Binding var profile: SpaceNameProfile
    let maxSpaces: Int
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Profile name
            HStack {
                Text("Name:")
                    .frame(width: 60, alignment: .leading)
                TextField("", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: profile.name) { _ in onSave() }
            }

            // Space names
            Text("Space Names")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(1...max(1, maxSpaces), id: \.self) { spaceIndex in
                HStack {
                    Text("Space \(spaceIndex):")
                        .frame(width: 80, alignment: .leading)
                    TextField("", text: binding(for: spaceIndex))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }

    private func binding(for spaceIndex: Int) -> Binding<String> {
        Binding(
            get: { profile.spaceNames[spaceIndex, default: ""] },
            set: { profile.spaceNames[spaceIndex] = $0; onSave() }
        )
    }
}