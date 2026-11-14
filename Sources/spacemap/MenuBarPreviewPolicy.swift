extension GridConfig {
    var needsWorkspacePreviews: Bool {
        glyphStrip.enabled || (presence.showsMenuBar && menuBarDisplayMode != .icon)
    }

    var needsWindowGeometryPreviews: Bool {
        glyphStrip.enabled || (needsWorkspacePreviews && menuBarDisplayMode != .dots)
    }
}
