import AppKit

final class HotkeyService: HotkeyHandling {
    private let hotkeyHandler: HotkeyHandler

    init(hud: HUDWindowController, hotkeyMonitorFactory: HotkeyMonitorFactory) {
        self.hotkeyHandler = HotkeyHandler(hud: hud, hotkeyMonitorFactory: hotkeyMonitorFactory)
    }

    func startHotkey(config: GridConfig) {
        hotkeyHandler.startHotkey(config: config)
    }

    func startPinnedHotkey(config: GridConfig) {
        hotkeyHandler.startPinnedHotkey(config: config)
    }

    func restartHotkey(config: GridConfig) {
        hotkeyHandler.restartHotkey(config: config)
    }
}
