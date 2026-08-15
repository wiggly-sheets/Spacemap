final class HotkeyMonitorFactory {
    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitor {
        HotkeyMonitor(config: config, onTrigger: onTrigger)
    }
}
