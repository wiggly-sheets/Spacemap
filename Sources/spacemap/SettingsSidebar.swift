import SwiftUI

struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsView.SidebarSection

    var body: some View {
        List {
            ForEach(SettingsView.SidebarSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.rawValue, systemImage: sidebarIcon(for: section))
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSection == section ? Color.accentColor : Color.primary)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedSection == section ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .listStyle(.sidebar)
        .frame(width: 200)
    }

    private func sidebarIcon(for section: SettingsView.SidebarSection) -> String {
        switch section {
        case .grid: return "square.grid.2x2"
        case .spaceNames: return "textformat"
        case .appearance: return "paintbrush"
        case .behavior: return "slider.horizontal.3"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}
