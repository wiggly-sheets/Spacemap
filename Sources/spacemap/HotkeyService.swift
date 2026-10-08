import AppKit

final class HotkeyService: HotkeyHandling {
    private let hotkeyHandler: HotkeyHandler

    init(
        hud: HUDWindowController,
        glyphStrip: GlyphStripPanelController,
        hotkeyMonitorFactory: HotkeyMonitorBuilding
    ) {
        self.hotkeyHandler = HotkeyHandler(
            hud: hud,
            glyphStrip: glyphStrip,
            hotkeyMonitorFactory: hotkeyMonitorFactory
        )
    }

    func restartHotkeys(config: GridConfig) {
        hotkeyHandler.restartHotkeys(config: config)
    }

    func stopHotkeys() {
        hotkeyHandler.stopHotkeys()
    }
}
