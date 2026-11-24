import XCTest
import CoreGraphics
@testable import spacemap

class HotkeyTestCase: XCTestCase {
    func makeRouter() -> HotkeyTapRouter {
        HotkeyTapRouter(
            tapFactory: { _, _, _, _, _, _ in nil },
            trustProvider: { true },
            promptProvider: { _ in true }
        )
    }

    func makeKeyEvent(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool = true
    ) -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        )!
        event.flags = flags
        return event
    }

    func pumpMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}


final class RecordingHotkeyMonitor: HotkeyMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

final class RecordingHotkeyMonitorFactory: HotkeyMonitorBuilding {
    private(set) var monitors: [RecordingHotkeyMonitor] = []

    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitoring {
        let monitor = RecordingHotkeyMonitor()
        monitors.append(monitor)
        return monitor
    }
}
