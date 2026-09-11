protocol HotkeyMonitoring: AnyObject {
    func start()
    func stop()
}

extension HotkeyMonitor: HotkeyMonitoring {}

protocol HotkeyMonitorBuilding {
    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitoring
}

final class HotkeyMonitorFactory: HotkeyMonitorBuilding {
    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitoring {
        HotkeyMonitor(config: config, onTrigger: onTrigger)
    }
}
