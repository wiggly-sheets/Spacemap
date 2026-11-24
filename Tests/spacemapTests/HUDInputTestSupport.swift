import XCTest
import CoreGraphics
@testable import spacemap

class HUDInputTestCase: XCTestCase {
}


/// A real `CFMachPort` shaped like a tap, so the host install path runs
/// without accessibility permission or a real session event tap.
func makeFakeEventTapPort() -> CFMachPort? {
    var context = CFMachPortContext(
        version: 0,
        info: nil,
        retain: nil,
        release: nil,
        copyDescription: nil
    )
    return CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &context, nil)
}

/// Records the commands HUDInput hands to its controller.
final class RecordingHUDInputDelegate: HUDInputDelegate {
    private(set) var commands: [HUDCommand] = []

    func perform(_ command: HUDCommand) {
        commands.append(command)
    }
}

extension HUDInputTestCase {
    /// A visible HUD whose key map is empty, so every letter reaches the
    /// typed-jump path instead of a binding.
    func makeTypingInput(
        names: [Int: String],
        windows: [YabaiWindow] = [],
        namingMode: SpaceNamingMode = .custom,
        jumpToSpaceEnabled: Bool = true,
        fuzzySpaceJumpEnabled: Bool = true
    ) -> HUDInput {
        let input = HUDInput(
            panel: nil,
            tapFactory: { _, _, _, _, _, _ in makeFakeEventTapPort() },
            relaunch: {}
        )
        input.accessibilityTrustProvider = { true }
        input.reconcileSettingsKeyMonitor()
        input.updateVisibility(true)
        input.updateConfig(
            hudKeys: HUDKeyBindings(),
            jumpToSpaceEnabled: jumpToSpaceEnabled,
            fuzzySpaceJumpEnabled: fuzzySpaceJumpEnabled
        )
        var config = SpacemapConfig.default
        config.spaceNames = names
        config.namingMode = namingMode
        let indices = Set(names.keys).union(windows.map(\.space)).sorted()
        let spaces = indices.map {
            YabaiSpace(id: $0, index: $0, display: 1, hasFocus: false, isVisible: nil, label: nil)
        }
        input.currentState = GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayBounds: .zero,
            focusedIndex: spaces.first?.index
        )
        return input
    }

    func press(
        _ input: HUDInput,
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        autorepeat: Bool = false
    ) -> Unmanaged<CGEvent>? {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            XCTFail("could not build a key event")
            return nil
        }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat ? 1 : 0)
        return input.handleTapEvent(type: .keyDown, event: event)
    }

    func waitUntil(
        _ message: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(message)", file: file, line: line)
    }
}
