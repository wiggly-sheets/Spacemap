import XCTest
import AppKit
@testable import spacemap

final class HotkeyRecorderTests: SettingsTestCase {
    func testHotkeyRecordingStateGuardsRepeatedStartsAndRestoresOriginalOnCancel() {
        var state = HotkeyRecordingState()

        XCTAssertTrue(state.begin(currentHotkey: "ctrl+space"))
        XCTAssertTrue(state.isRecording)
        XCTAssertFalse(state.begin(currentHotkey: "cmd+space"))
        XCTAssertEqual(state.cancel(), "ctrl+space")
        XCTAssertFalse(state.isRecording)
        XCTAssertNil(state.cancel())
    }

    func testHotkeyRecordingStateCompletionDoesNotRestoreOriginal() {
        var state = HotkeyRecordingState()

        XCTAssertTrue(state.begin(currentHotkey: "ctrl+space"))
        state.complete()

        XCTAssertFalse(state.isRecording)
        XCTAssertNil(state.cancel())
    }

    func testHotkeyRecorderCoordinatorCancelsPreviousRecorderBeforeActivatingAnother() {
        let coordinator = HotkeyRecorderCoordinator()
        let first = UUID()
        let second = UUID()
        var cancellations: [UUID] = []

        coordinator.activate(recorderID: first) { cancellations.append(first) }
        coordinator.activate(recorderID: second) { cancellations.append(second) }

        XCTAssertEqual(cancellations, [first])
        XCTAssertEqual(coordinator.activeRecorderID, second)
        coordinator.deactivate(recorderID: first)
        XCTAssertEqual(coordinator.activeRecorderID, second)
        coordinator.deactivate(recorderID: second)
        XCTAssertNil(coordinator.activeRecorderID)
    }

    func testRecorderCoordinatorTogglesMediaKeySuppressionFlag() {
        defer { HotkeyTapRouter.isRecording = false }
        let coordinator = HotkeyRecorderCoordinator()
        let first = UUID()
        let second = UUID()

        XCTAssertFalse(HotkeyTapRouter.isRecording)
        coordinator.activate(recorderID: first) {}
        XCTAssertTrue(HotkeyTapRouter.isRecording)

        // Switching recorders keeps suppression on; the replaced recorder's
        // late deactivate must not clear it for the active one.
        coordinator.activate(recorderID: second) {}
        XCTAssertTrue(HotkeyTapRouter.isRecording)
        coordinator.deactivate(recorderID: first)
        XCTAssertTrue(HotkeyTapRouter.isRecording)

        coordinator.deactivate(recorderID: second)
        XCTAssertFalse(HotkeyTapRouter.isRecording)
    }

    func testDiscardedRecorderCoordinatorClearsMediaKeySuppression() {
        defer { HotkeyTapRouter.isRecording = false }
        var coordinator: HotkeyRecorderCoordinator? = HotkeyRecorderCoordinator()

        coordinator?.activate(recorderID: UUID()) {}
        XCTAssertTrue(HotkeyTapRouter.isRecording)

        coordinator = nil
        XCTAssertFalse(HotkeyTapRouter.isRecording)
    }

    func testOnlyBareEscapeCancelsHotkeyRecording() throws {
        let bareEscape = try XCTUnwrap(Self.keyEvent(keyCode: 53, modifiers: []))
        let optionEscape = try XCTUnwrap(Self.keyEvent(keyCode: 53, modifiers: .option))

        XCTAssertTrue(HotkeyRecorder.isCancelKey(bareEscape))
        XCTAssertFalse(HotkeyRecorder.isCancelKey(optionEscape))
    }

    func testHotkeyKeycapsSplitModifiersFromTheKey() {
        XCTAssertEqual(HotkeyRecorder.keycaps(for: "ctrl+cmd+space"), ["⌃", "⌘", "Space"])
        XCTAssertEqual(HotkeyRecorder.keycaps(for: "hyper+f5"), ["⌃", "⌘", "⌥", "⇧", "F5"])
        XCTAssertEqual(HotkeyRecorder.keycaps(for: "none"), [])
        XCTAssertEqual(HotkeyRecorder.keycaps(for: ""), [])
        XCTAssertEqual(HotkeyRecorder.keycaps(for: "a"), ["A"])
    }

    func testDuplicateHotkeyDetectionTreatsFunctionKeyFnModifierAsTheSameBinding() {
        XCTAssertTrue(SettingsBehavior.matches("f1", "fn+f1"))
        XCTAssertTrue(SettingsBehavior.matches("ctrl+f2", "fn+ctrl+f2"))
        XCTAssertFalse(SettingsBehavior.matches("f1", "f2"))
        XCTAssertFalse(SettingsBehavior.matches("f1", "ctrl+f1"))
    }

}
