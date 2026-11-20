import SwiftUI
import Foundation

struct SettingsSpaceNames: View {
    @Binding var showSpaceNames: Bool
    @Binding var spaceNameInputs: [Int: String]
    @Binding var maxSpaces: Int
    @Binding var profiles: [SpaceNameProfile]
    @Binding var activeProfileIndex: Int
    @Binding var namingMode: SpaceNamingMode
    @Binding var autoNameAppCount: Int
    /// HUD-derived names shown read-only while auto naming is on.
    var autoSpaceNames: [Int: String]

    @State private var editingProfileIndex: Int?
    @State private var newProfileName: String = ""

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Space Names").settingsAnchor("spaceNames.names")) {
            Picker("Names", selection: $namingMode) {
                Text("Custom").tag(SpaceNamingMode.custom)
                Text("Auto from apps").tag(SpaceNamingMode.auto)
            }
            if namingMode == .auto {
                stepper("Apps per name", value: $autoNameAppCount, range: 1...3)
                SettingsFootnote(text: "Each space lists up to \(autoNameAppCount) visible apps in window order, separated by ·, with … when it has more.")
            }
            Toggle("Show Space Names", isOn: $showSpaceNames)

            if showSpaceNames {
                if namingMode == .custom {
                    SettingsFootnote(text: "Each input corresponds to its space number, up to Max Spaces.")
                } else {
                    SettingsFootnote(text: "Showing the names auto naming derives from each space's visible apps. Custom names stay saved and return when you switch back.")
                }
                ForEach(1...max(1, maxSpaces), id: \.self) { spaceIndex in
                    HStack {
                        Text("Space \(spaceIndex):")
                            .frame(width: 80, alignment: .leading)
                        if namingMode == .auto {
                            Text(autoName(for: spaceIndex))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField("", text: binding(for: spaceIndex))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
        }

        Section(header: SettingsSectionHeader(title: "Space Name Profiles").settingsAnchor("spaceNames.profiles")) {
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
                                Self.syncActiveProfile(
                                    names: spaceNameInputs,
                                    into: &profiles,
                                    activeIndex: activeProfileIndex
                                )
                                activeProfileIndex = index
                                spaceNameInputs = Self.activatedNames(
                                    profiles: profiles,
                                    index: index
                                ) ?? spaceNameInputs
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
                            ProfileEditor(profile: $profiles[index], maxSpaces: maxSpaces)
                                .disabled(namingMode == .auto)
                                // Editing the active profile must update the
                                // names the strip and HUD actually render.
                                .onChange(of: profiles[index].spaceNames) { names in
                                    if index == activeProfileIndex {
                                        spaceNameInputs = names
                                    }
                                }
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
                .liquidGlassButtonStyle(prominent: true)
                .controlSize(.small)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
    }

    private func autoName(for spaceIndex: Int) -> String {
        let name = autoSpaceNames[spaceIndex]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "—" : name
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
        Self.syncActiveProfile(
            names: spaceNameInputs,
            into: &profiles,
            activeIndex: activeProfileIndex
        )
        let newProfile = SpaceNameProfile(name: name)
        profiles.append(newProfile)
        newProfileName = ""
        activeProfileIndex = profiles.count - 1
        spaceNameInputs = newProfile.spaceNames
    }

    private func deleteProfile(_ index: Int) {
        guard profiles.count > 1, profiles.indices.contains(index) else { return }
        let wasActive = index == activeProfileIndex
        Self.syncActiveProfile(
            names: spaceNameInputs,
            into: &profiles,
            activeIndex: activeProfileIndex
        )
        profiles.remove(at: index)

        if let editing = editingProfileIndex {
            if editing == index {
                editingProfileIndex = nil
            } else if editing > index {
                editingProfileIndex = editing - 1
            }
        }

        activeProfileIndex = Self.activeIndexAfterDeleting(
            index,
            activeIndex: activeProfileIndex,
            remainingCount: profiles.count
        )
        // Activation copies names into the editable inputs; deleting the active
        // profile must do the same for whichever profile becomes active.
        if wasActive {
            spaceNameInputs = profiles[activeProfileIndex].spaceNames
        }
    }

    /// Writes the visible Space Names fields back into the active profile
    /// before any save or profile transition, so edits are never discarded.
    static func syncActiveProfile(
        names: [Int: String],
        into profiles: inout [SpaceNameProfile],
        activeIndex: Int
    ) {
        guard profiles.indices.contains(activeIndex) else { return }
        profiles[activeIndex].spaceNames = names
    }

    /// Names the editable inputs take when `index` is activated. `nil` when the
    /// index no longer exists.
    static func activatedNames(profiles: [SpaceNameProfile], index: Int) -> [Int: String]? {
        guard profiles.indices.contains(index) else { return nil }
        return profiles[index].spaceNames
    }

    /// Deletions below the active profile shift it down; deleting the active
    /// one selects the item that slid into its place (or the last item).
    static func activeIndexAfterDeleting(
        _ index: Int,
        activeIndex: Int,
        remainingCount: Int
    ) -> Int {
        guard remainingCount > 0 else { return 0 }
        if index < activeIndex { return min(activeIndex - 1, remainingCount - 1) }
        if index == activeIndex { return min(index, remainingCount - 1) }
        return min(activeIndex, remainingCount - 1)
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
                .liquidGlassButtonStyle()
                .controlSize(.small)
            }

            Button(isEditing ? "Done" : "Edit") {
                onEdit()
            }
            .liquidGlassButtonStyle()
            .controlSize(.small)

            Button("Delete") {
                onDelete()
            }
            .liquidGlassButtonStyle()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Profile name
            HStack {
                Text("Name:")
                    .frame(width: 60, alignment: .leading)
                TextField("", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
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
            set: { profile.spaceNames[spaceIndex] = $0 }
        )
    }
}