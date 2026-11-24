import AppKit
import Foundation
import XCTest
@testable import spacemap

// MARK: - createAndFocusNewestSpace timeout path (Stream B owns source)

final class CreateAndFocusTimeoutTests: XCTestCase {
    private func makeController(yabai: MockYabaiService) -> HUDWindowController {
        HUDWindowController(services: SpacemapServices(
            yabaiService: yabai,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
    }

    func testTimeoutPathCreatesButNeverFocuses() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = [] // newest never appears: poll exhausts attempts
        var controller: HUDWindowController? = makeController(yabai: yabai)
        controller?.createAndFocusNewestSpace()

        let settled = expectation(description: "poll attempts exhaust")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        defer { controller = nil }

        XCTAssertEqual(yabai.createSpaceCallCount, 1)
        XCTAssertEqual(yabai.focusSpaceIndexCallCount, 0)
        XCTAssertEqual(yabai.focusSpaceTargetCallCount, 0)
        XCTAssertGreaterThanOrEqual(yabai.querySpacesCallCount, 3)
    }

    func testStaleGenerationAbortsPoll() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = []
        var controller: HUDWindowController? = makeController(yabai: yabai)
        controller?.show()
        controller?.createAndFocusNewestSpace()
        controller?.hide() // bumps generation: pending polls must abort

        let settled = expectation(description: "aborted poll settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        defer { controller = nil }

        XCTAssertEqual(yabai.focusSpaceIndexCallCount, 0)
        XCTAssertEqual(yabai.focusSpaceTargetCallCount, 0)
    }
}
