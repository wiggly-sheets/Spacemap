import XCTest
import AppKit
@testable import spacemap

final class SettingsTests: XCTestCase {
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

    func testOnlyBareEscapeCancelsHotkeyRecording() throws {
        let bareEscape = try XCTUnwrap(Self.keyEvent(keyCode: 53, modifiers: []))
        let optionEscape = try XCTUnwrap(Self.keyEvent(keyCode: 53, modifiers: .option))

        XCTAssertTrue(HotkeyRecorder.isCancelKey(bareEscape))
        XCTAssertFalse(HotkeyRecorder.isCancelKey(optionEscape))
    }

    func testAppearanceStepsIncludeArbitraryValidCurrentValue() {
        XCTAssertEqual(
            SettingsAppearanceView.steps([0, 0.5, 1], including: 0.37),
            [0, 0.37, 0.5, 1]
        )
    }

    func testSocketHealthOptionsIncludeArbitraryValidCurrentValue() {
        XCTAssertEqual(
            SettingsAdvanced.socketHealthOptions(including: 37),
            [15, 30, 37, 45, 60]
        )
    }

    func testGridLayoutOptionsPreserveArbitraryValidGeometry() {
        let options = SettingsGrid.layoutOptions(
            maxSpaces: 10,
            currentCols: 3,
            currentRows: 4
        )
        let index = SettingsGrid.layoutIndex(
            maxSpaces: 10,
            currentCols: 3,
            currentRows: 4
        )

        XCTAssertEqual(options[index].cols, 3)
        XCTAssertEqual(options[index].rows, 4)
        XCTAssertEqual(options[index].label, "3×4 (Custom)")
    }

    func testSettingsViewAcceptsInjectedYabaiServiceAndExactConfigValues() {
        var config = GridConfig.default
        config.socketHealthInterval = 37
        config.backgroundAlpha = 0.37
        config.iconScale = 0.43
        config.uiScale = 0.61

        _ = SettingsView(yabaiService: MockYabaiService(), config: config)
    }

    func testSettingsWindowUsesStableFrameAutosaveName() {
        XCTAssertFalse(SettingsWindowController.frameAutosaveName.isEmpty)
    }

    func testAboutWindowIsReusedAcrossRepeatedShowRequests() throws {
        _ = NSApplication.shared
        let service = SettingsService(yabaiService: MockYabaiService(), checkForUpdates: {})

        service.showAboutWindow()
        let first = try XCTUnwrap(service.aboutWindowController)
        service.showAboutWindow()

        let second = try XCTUnwrap(service.aboutWindowController)
        XCTAssertTrue(first === second)
        first.close()
    }

    private static func keyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
