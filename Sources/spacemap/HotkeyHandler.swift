import AppKit

class HotkeyHandler {
    private var hotkey: HotkeyMonitoring?
    private var pinnedHotkey: HotkeyMonitoring?
    private let onToggle: () -> Void
    private let onTogglePinned: () -> Void
    private let hotkeyMonitorFactory: HotkeyMonitorBuilding

    init(hud: HUDWindowController, hotkeyMonitorFactory: HotkeyMonitorBuilding = HotkeyMonitorFactory()) {
        self.onToggle = { [weak hud] in hud?.toggle() }
        self.onTogglePinned = { [weak hud] in hud?.togglePinned() }
        self.hotkeyMonitorFactory = hotkeyMonitorFactory
    }

    init(
        hotkeyMonitorFactory: HotkeyMonitorBuilding,
        onToggle: @escaping () -> Void,
        onTogglePinned: @escaping () -> Void
    ) {
        self.hotkeyMonitorFactory = hotkeyMonitorFactory
        self.onToggle = onToggle
        self.onTogglePinned = onTogglePinned
    }

    func restartHotkeys(config: GridConfig) {
        stopHotkeys()
        startHotkey(config: config)
        startPinnedHotkey(config: config)
    }

    func stopHotkeys() {
        hotkey?.stop()
        hotkey = nil
        pinnedHotkey?.stop()
        pinnedHotkey = nil
    }

    private func startHotkey(config: GridConfig) {
        guard !config.hotkey.isDisabled else { return }
        let monitor = hotkeyMonitorFactory.makeHotkeyMonitor(config: config.hotkey, onTrigger: onToggle)
        monitor.start()
        hotkey = monitor
    }

    private func startPinnedHotkey(config: GridConfig) {
        guard !config.pinnedHotkey.isDisabled else { return }
        guard Hotkey.hotkeyToString(config.pinnedHotkey) != Hotkey.hotkeyToString(config.hotkey) else {
            NSLog("Spacemap: pinned HUD hotkey matches the normal hotkey; pinned binding ignored")
            return
        }
        let monitor = hotkeyMonitorFactory.makeHotkeyMonitor(config: config.pinnedHotkey, onTrigger: onTogglePinned)
        monitor.start()
        pinnedHotkey = monitor
    }

}
