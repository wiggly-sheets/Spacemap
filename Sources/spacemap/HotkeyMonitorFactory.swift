/// Factory for creating `HotkeyMonitor` instances.
/// Abstracts the hotkey monitor creation so it can be mocked in tests.
final class HotkeyMonitorFactory {
    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitor {
        HotkeyMonitor(config: config, onTrigger: onTrigger)
    }
}