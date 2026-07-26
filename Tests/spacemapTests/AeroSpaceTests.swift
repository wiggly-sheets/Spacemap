import XCTest
@testable import spacemap

final class AeroSpaceTests: XCTestCase {
    func testWorkspaceJSONDecoding() throws {
        let data = Data(#"[{"workspace":"1","monitor-id":2}]"#.utf8)
        let workspaces = try JSONDecoder().decode([AeroSpaceWorkspace].self, from: data)

        XCTAssertEqual(workspaces.first?.name, "1")
        XCTAssertEqual(workspaces.first?.monitor, 2)
    }

    func testWindowJSONDecoding() throws {
        let data = Data(
            #"[{"window-id":42,"app-name":"Terminal","workspace":"2","window-title":"shell","window-is-fullscreen":false,"window-layout":"h_tiles"}]"#.utf8
        )
        let windows = try JSONDecoder().decode([AeroSpaceWindow].self, from: data)

        XCTAssertEqual(windows.first?.windowId, 42)
        XCTAssertEqual(windows.first?.appName, "Terminal")
        XCTAssertEqual(windows.first?.workspace, "2")
        XCTAssertEqual(windows.first?.windowTitle, "shell")
    }
}
