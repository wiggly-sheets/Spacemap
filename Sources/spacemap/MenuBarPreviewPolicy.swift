extension GridConfig {
    var needsWorkspacePreviews: Bool {
        glyphStrip.enabled || (!hideMenuBarIcon && menuBarDisplayMode != .icon)
    }

    var needsWindowGeometryPreviews: Bool {
        glyphStrip.enabled || (needsWorkspacePreviews && menuBarDisplayMode != .dots)
    }
}
