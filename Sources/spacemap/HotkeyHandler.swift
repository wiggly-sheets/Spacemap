import AppKit

class HotkeyHandler {
    private var hotkey: HotkeyMonitor?
    private var pinnedHotkey: HotkeyMonitor?
    private let hud: HUDWindowController

    init(hud: HUDWindowController) {
        self.hud = hud
    }

    func restartHotkey(config: GridConfig) {
        self.hotkey?.stop()
        self.hotkey = nil
        self.pinnedHotkey?.stop()
        self.pinnedHotkey = nil
        self.startHotkey(config: config)
        self.startPinnedHotkey(config: config)
    }

    private func startHotkey(config: GridConfig) {
        guard !config.hotkey.isDisabled else { return }
        let monitor = HotkeyMonitor(config: config.hotkey) { [weak self] in
            self?.hud.toggle()
        }
        monitor.start()
        hotkey = monitor
    }

    private func startPinnedHotkey(config: GridConfig) {
        guard !config.pinnedHotkey.isDisabled else { return }
        guard Hotkey.hotkeyToString(config.pinnedHotkey) != Hotkey.hotkeyToString(config.hotkey) else {
            NSLog("Spacemap: pinned HUD hotkey matches the normal hotkey; pinned binding ignored")
            return
        }
        let monitor = HotkeyMonitor(config: config.pinnedHotkey) { [weak self] in
            self?.hud.togglePinned()
        }
        monitor.start()
        pinnedHotkey = monitor
    }

    func workspacePreviewsEnabled(for config: GridConfig) -> Bool {
        !config.hideMenuBarIcon && config.menuBarDisplayMode != .icon
    }

    func windowGeometryPreviewsEnabled(for config: GridConfig) -> Bool {
        workspacePreviewsEnabled(for: config) && config.menuBarDisplayMode != .dots
    }
}
