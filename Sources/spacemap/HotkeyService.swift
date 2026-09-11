import AppKit

final class HotkeyService: HotkeyHandling {
    private let hotkeyHandler: HotkeyHandler

    init(hud: HUDWindowController, hotkeyMonitorFactory: HotkeyMonitorBuilding) {
        self.hotkeyHandler = HotkeyHandler(hud: hud, hotkeyMonitorFactory: hotkeyMonitorFactory)
    }

    func restartHotkeys(config: GridConfig) {
        hotkeyHandler.restartHotkeys(config: config)
    }

    func stopHotkeys() {
        hotkeyHandler.stopHotkeys()
    }
}
