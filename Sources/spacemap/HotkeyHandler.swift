import AppKit

class HotkeyHandler {
    private var hotkey: HotkeyMonitoring?
    private var pinnedHotkey: HotkeyMonitoring?
    private var glyphStripHotkey: HotkeyMonitoring?
    private let onToggle: () -> Void
    private let onTogglePinned: () -> Void
    private let onToggleGlyphStrip: () -> Void
    private let hotkeyMonitorFactory: HotkeyMonitorBuilding

    init(
        hud: HUDWindowController,
        glyphStrip: GlyphStripPanelController? = nil,
        hotkeyMonitorFactory: HotkeyMonitorBuilding = HotkeyMonitorFactory()
    ) {
        self.onToggle = { [weak hud] in hud?.toggle() }
        self.onTogglePinned = { [weak hud] in hud?.togglePinned() }
        self.onToggleGlyphStrip = { [weak glyphStrip] in glyphStrip?.toggleVisibilityByHotkey() }
        self.hotkeyMonitorFactory = hotkeyMonitorFactory
    }

    init(
        hotkeyMonitorFactory: HotkeyMonitorBuilding,
        onToggle: @escaping () -> Void,
        onTogglePinned: @escaping () -> Void,
        onToggleGlyphStrip: @escaping () -> Void = {}
    ) {
        self.hotkeyMonitorFactory = hotkeyMonitorFactory
        self.onToggle = onToggle
        self.onTogglePinned = onTogglePinned
        self.onToggleGlyphStrip = onToggleGlyphStrip
    }

    func restartHotkeys(config: GridConfig) {
        stopHotkeys()
        startHotkey(config: config)
        startPinnedHotkey(config: config)
        startGlyphStripHotkey(config: config)
    }

    func stopHotkeys() {
        hotkey?.stop()
        hotkey = nil
        pinnedHotkey?.stop()
        pinnedHotkey = nil
        glyphStripHotkey?.stop()
        glyphStripHotkey = nil
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

    private func startGlyphStripHotkey(config: GridConfig) {
        guard !config.glyphStripHotkey.isDisabled else { return }
        let binding = Hotkey.hotkeyToString(config.glyphStripHotkey)
        guard binding != Hotkey.hotkeyToString(config.hotkey),
              binding != Hotkey.hotkeyToString(config.pinnedHotkey) else {
            NSLog("Spacemap: glyph strip hotkey matches another binding; strip binding ignored")
            return
        }
        let monitor = hotkeyMonitorFactory.makeHotkeyMonitor(
            config: config.glyphStripHotkey,
            onTrigger: onToggleGlyphStrip
        )
        monitor.start()
        glyphStripHotkey = monitor
    }

}
