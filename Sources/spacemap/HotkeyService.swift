import AppKit

final class HotkeyService {
    private let hotkeyHandler: HotkeyHandler

    init(
        hud: HUDWindowController,
        glyphStrip: GlyphStripPanelController
    ) {
        self.hotkeyHandler = HotkeyHandler(
            hud: hud,
            glyphStrip: glyphStrip
        )
    }

    func restartHotkeys(config: GridConfig) {
        hotkeyHandler.restartHotkeys(config: config)
    }

    func stopHotkeys() {
        hotkeyHandler.stopHotkeys()
    }
}
