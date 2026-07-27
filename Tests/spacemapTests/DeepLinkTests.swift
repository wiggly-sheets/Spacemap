import XCTest
@testable import spacemap

final class DeepLinkTests: XCTestCase {
    func testParsesAllCanonicalDeepLinks() throws {
        let expected: [(String, DeepLinkAction)] = [
            ("spacemap://toggle-hud", .toggleHUD),
            ("spacemap://pin-hud", .pinHUD),
            ("spacemap://settings", .settings),
            ("spacemap://menu", .menu),
            ("spacemap://config", .config),
            ("spacemap://themes", .themes),
        ]

        for (urlString, action) in expected {
            XCTAssertEqual(DeepLinkAction(url: try XCTUnwrap(URL(string: urlString))), action)
        }
    }

    func testParsingIsCaseInsensitive() throws {
        XCTAssertEqual(
            DeepLinkAction(url: try XCTUnwrap(URL(string: "SPACEMAP://SETTINGS"))),
            .settings
        )
    }

    func testSupportsSchemePathForm() throws {
        XCTAssertEqual(
            DeepLinkAction(url: try XCTUnwrap(URL(string: "spacemap:toggle-hud"))),
            .toggleHUD
        )
    }

    func testRejectsUnsupportedURLs() throws {
        let urls = [
            "https://settings",
            "spacemap://unknown",
            "spacemap://settings/extra",
            "spacemap://",
        ]

        for urlString in urls {
            XCTAssertNil(DeepLinkAction(url: try XCTUnwrap(URL(string: urlString))))
        }
    }
}
