/// Signal requirements for menu-bar workspace previews.
extension GridConfig {
    var needsWorkspacePreviews: Bool {
        !hideMenuBarIcon && menuBarDisplayMode != .icon
    }

    var needsWindowGeometryPreviews: Bool {
        needsWorkspacePreviews && menuBarDisplayMode != .dots
    }
}
