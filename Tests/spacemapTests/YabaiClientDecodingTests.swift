import XCTest
@testable import spacemap

final class YabaiClientDecodingTests: YabaiClientImplTestCase {
    func testDecodeTolerantDropsOnlyMalformedEntries() throws {
        let json = """
        [
          {"id":1,"index":1,"display":1,"has-focus":true},
          {"id":"not-an-int","index":2,"display":1,"has-focus":false},
          {"id":3,"index":3,"display":1,"has-focus":false}
        ]
        """

        let spaces = try client.decodeTolerant(YabaiSpace.self, from: json, label: "test")

        XCTAssertEqual(spaces.map(\.index), [1, 3])
        XCTAssertEqual(spaces.map(\.id), [1, 3])
    }

    func testDecodeTolerantThrowsWhenPayloadIsNotAnArray() {
        XCTAssertThrowsError(
            try client.decodeTolerant(YabaiSpace.self, from: "{\"id\":1}", label: "test")
        )
    }


    // MARK: - Last-good snapshots

}
