import SwiftUI

struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsView.SidebarSection

    var body: some View {
        #if compiler(>=6.0)
        if #available(macOS 26.0, *) {
            List(selection: $selectedSection) {
                ForEach(SettingsView.SidebarSection.allCases) { section in
                    row(for: section)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } else {
            legacyList
        }
        #else
        legacyList
        #endif
    }

    /// Pre-26 sidebar: plain buttons with the hand-drawn accent selection.
    private var legacyList: some View {
        List {
            ForEach(SettingsView.SidebarSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    row(for: section)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSection == section ? Color.accentColor : Color.primary)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedSection == section ? Color.accentColor.opacity(0.18) : Color.clear)
                )
            }
        }
        .listStyle(.sidebar)
        .frame(width: 260)
    }

    private func row(for section: SettingsView.SidebarSection) -> some View {
        let isSelected = selectedSection == section
        return HStack(spacing: 10) {
            Image(systemName: sidebarIcon(for: section))
                .font(.system(size: 15, weight: .medium))
            Text(section.rawValue)
                .font(.system(size: 15, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
