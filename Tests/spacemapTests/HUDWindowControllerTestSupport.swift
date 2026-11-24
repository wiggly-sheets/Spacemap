import XCTest
import CoreGraphics
@testable import spacemap

class HUDWindowControllerTestCase: XCTestCase {
    func cannedState(
        focusedIndex: Int? = nil,
        spaces: [YabaiSpace] = [],
        windows: [YabaiWindow] = [],
        displays: [YabaiDisplay] = []
    ) -> GridState {
        GridState(
            config: .default,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: focusedIndex,
            displays: displays
        )
    }

    func makeHUDWindowController() -> HUDWindowController {
        HUDWindowController(services: SpacemapServices(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
    }


    func hudInput(of controller: HUDWindowController) -> HUDInput? {
        Mirror(reflecting: controller).children
            .first { $0.label == "hudInput" }?
            .value as? HUDInput
    }

    func dragHandler(of controller: HUDWindowController) -> WindowDragHandler? {
        Mirror(reflecting: controller).children
            .first { $0.label == "dragHandler" }?
            .value as? WindowDragHandler
    }

    func withTemporaryHome(_ body: (URL) throws -> Void) throws {
        // CFFIXED_USER_HOME is process-wide: this test must not share a process
        // with other home-reading tests. `swift test --parallel` isolates each
        // worker in its own process; in-process XCTest parallelism would not.
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-hud-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let previous = getenv("CFFIXED_USER_HOME").map { String(cString: $0) }
        setenv("CFFIXED_USER_HOME", home.path, 1)
        defer {
            if let previous {
                setenv("CFFIXED_USER_HOME", previous, 1)
            } else {
                unsetenv("CFFIXED_USER_HOME")
            }
            try? FileManager.default.removeItem(at: home)
        }
        try body(home)
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
