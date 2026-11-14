import SwiftUI

/// One jump target inside a settings pane. `id` is the anchor applied to the
/// matching `Section`; `title` is the sidebar label.
struct SettingsSubsection: Identifiable, Hashable {
    let id: String
    let title: String
}

extension SettingsView.SidebarSection {
    var subsections: [SettingsSubsection] {
        switch self {
        case .grid:
            return [SettingsSubsection(id: "grid", title: "Grid")]
        case .spaceNames:
            return [
                SettingsSubsection(id: "spaceNames.names", title: "Space Names"),
                SettingsSubsection(id: "spaceNames.profiles", title: "Profiles"),
            ]
        case .appearance:
            return [
                SettingsSubsection(id: "appearance.hud", title: "HUD"),
                SettingsSubsection(id: "appearance.spaces", title: "HUD Spaces"),
                SettingsSubsection(id: "appearance.themeEditor", title: "Theme Editor"),
            ]
        case .behavior:
            return [
                SettingsSubsection(id: "behavior.hotkeys", title: "Hotkeys"),
                SettingsSubsection(id: "behavior.hud", title: "HUD"),
                SettingsSubsection(id: "behavior.navigation", title: "Navigation"),
                SettingsSubsection(id: "behavior.windowDrop", title: "Window Drop"),
                SettingsSubsection(id: "behavior.feedback", title: "HUD Feedback"),
                SettingsSubsection(id: "behavior.menuBar", title: "Menu Bar"),
                SettingsSubsection(id: "behavior.updates", title: "Updates"),
                SettingsSubsection(id: "behavior.appFont", title: "App Font"),
            ]
        case .glyphStrip:
            return [
                SettingsSubsection(id: "glyphStrip.general", title: "General"),
                SettingsSubsection(id: "glyphStrip.contents", title: "Contents"),
                SettingsSubsection(id: "glyphStrip.appearance", title: "Appearance"),
                SettingsSubsection(id: "glyphStrip.hover", title: "Hover Highlight"),
                SettingsSubsection(id: "glyphStrip.clicks", title: "Clicks"),
            ]
        case .advanced:
            return [
                SettingsSubsection(id: "advanced.permissions", title: "Permissions"),
                SettingsSubsection(id: "advanced.diagnostics", title: "Diagnostics"),
            ]
        }
    }
}

/// Reports section headers relative to the detail pane so the sidebar can
/// follow the scroll position. Min-y values shrink as the pane scrolls down.
struct SettingsSectionOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Tags a settings section for scrolling, and publishes its offset so the
    /// sidebar dropdown can highlight the section currently at the top.
    func settingsAnchor(_ id: String) -> some View {
        self
            .id(id)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SettingsSectionOffsetKey.self,
                        value: [id: proxy.frame(in: .named(SettingsView.detailSpace)).minY]
                    )
                }
            )
    }
}
