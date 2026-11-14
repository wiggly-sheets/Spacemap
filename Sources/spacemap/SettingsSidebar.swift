import SwiftUI

/// Sidebar with one expandable group per pane, mirroring IINA's settings
/// sidebar. The open group follows the pane's scroll position; clicking a
/// subsection scrolls the detail pane to that section.
struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsView.SidebarSection
    @Binding var currentSubsection: String?
    let onSelectSection: (SettingsView.SidebarSection) -> Void
    let onSelectSubsection: (SettingsSubsection) -> Void
    @State private var expanded: Set<SettingsView.SidebarSection> = [.grid]

    var body: some View {
        List {
            ForEach(SettingsView.SidebarSection.allCases) { section in
                sectionRow(section)
                if expanded.contains(section) {
                    ForEach(section.subsections) { subsection in
                        subsectionRow(subsection, in: section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .background(Color.clear)
        .onChange(of: selectedSection) { section in
            expanded = [section]
        }
        .onChange(of: currentSubsection) { id in
            guard let id,
                  let section = SettingsView.SidebarSection.allCases.first(where: {
                      $0.subsections.contains(where: { $0.id == id })
                  }) else { return }
            expanded = [section]
        }
    }

    private func sectionRow(_ section: SettingsView.SidebarSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: sidebarIcon(for: section))
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22)
            Text(section.rawValue)
                .font(.system(size: 15, weight: .medium))
            Spacer(minLength: 4)
            if section.subsections.count > 1 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.contains(section) ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSection = section
            onSelectSection(section)
            if expanded.contains(section) {
                expanded.remove(section)
            } else {
                expanded = [section]
            }
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selectedSection == section
                      ? Color.accentColor.opacity(0.18)
                      : Color.clear)
        )
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
        .accessibilityLabel(section.rawValue)
    }

    private func subsectionRow(
        _ subsection: SettingsSubsection,
        in section: SettingsView.SidebarSection
    ) -> some View {
        let isCurrent = selectedSection == section && currentSubsection == subsection.id
        return HStack(spacing: 8) {
            Text(subsection.title)
                .font(.system(size: 13))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 30)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSection = section
            onSelectSubsection(subsection)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .accessibilityLabel("\(section.rawValue), \(subsection.title)")
    }

    private func sidebarIcon(for section: SettingsView.SidebarSection) -> String {
        switch section {
        case .grid: return "square.grid.2x2"
        case .spaceNames: return "textformat"
        case .appearance: return "paintbrush"
        case .behavior: return "slider.horizontal.3"
        case .glyphStrip: return "rectangle.split.1x2"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}
