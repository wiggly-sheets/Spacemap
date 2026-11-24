import XCTest
@testable import spacemap

class YabaiClientImplTestCase: XCTestCase {
    var client: YabaiClientImpl!

    override func setUp() {
        super.setUp()
        client = YabaiClientImpl()
    }

    override func tearDown() {
        client.resetYabaiProcessCheck()
        client = nil
        super.tearDown()
    }


    var isYabaiAvailable: Bool {
        // Real-desktop coverage is opt-in: an installed yabai on a dev machine
        // otherwise makes these tests depend on the current window layout.
        guard ProcessInfo.processInfo.environment["SPACEMAP_RUN_YABAI_TESTS"] == "1" else { return false }
        let executable = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
        guard let executable else { return false }
        return (try? ProcessRunner.run(
            executable: executable,
            arguments: ["-m", "query", "--spaces"],
            timeout: 1
        )) != nil
    }



    func makeNonceSocket() throws -> String {
        let socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("smr_\(UUID().uuidString.prefix(8)).sock")
        let noncePath = SpacemapCommand.noncePath(for: socketPath)
        try Data(repeating: 0xef, count: 32).write(to: URL(fileURLWithPath: noncePath), options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: noncePath) }
        return socketPath
    }

    /// Hex of the nonce `makeNonceSocket` writes.
    var fixtureNonceHex: String { String(repeating: "ef", count: 32) }

    /// `yabai -m signal --list` output for one registered signal, in the real
    /// shape: label and action live in the same object, label first.
    func signalListing(label: String, nonce: String) -> String {
        """
        [
        {
        	"index":0,
        	"label":"\(label)",
        	"app":"",
        	"title":"",
        	"active":true,
        	"event":"space_changed",
        	"action":"printf 'r:\(nonce)' | /usr/bin/nc -U /tmp/s.sock"
        }
        ]
        """
    }

    func spacesJSON(_ indices: [Int], focused: Int? = nil) -> String {
        let entries = indices.map { index -> String in
            let hasFocus = index == focused ? "true" : "false"
            return "{\"id\":\(index),\"index\":\(index),\"display\":1,\"has-focus\":\(hasFocus)}"
        }
        return "[\(entries.joined(separator: ","))]"
    }

    func windowsJSON(_ ids: [Int]) -> String {
        let entries = ids.map { id -> String in
            "{\"id\":\(id),\"app\":\"App\(id)\",\"space\":1,"
                + "\"frame\":{\"x\":0,\"y\":0,\"w\":100,\"h\":100},"
                + "\"is-hidden\":false,\"is-minimized\":false,\"sub-layer\":\"normal\"}"
        }
        return "[\(entries.joined(separator: ","))]"
    }

    var displaysJSON: String {
        "[{\"index\":1,\"frame\":{\"x\":0,\"y\":0,\"w\":100,\"h\":100},\"has-focus\":true}]"
    }
}
