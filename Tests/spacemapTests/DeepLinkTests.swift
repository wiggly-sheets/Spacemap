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

    func testPendingActionsFlushOnceReady() throws {
        let services = SpacemapServices(yabaiService: MockYabaiService(), alertsService: Alerts())
        var menuCount = 0
        let service = DeepLinkService(
            hud: services.hud,
            themeService: services.themeService,
            showSettings: {},
            showMenu: { menuCount += 1 }
        )
        let menu = try XCTUnwrap(URL(string: "spacemap://menu"))

        service.open(urls: [menu])
        XCTAssertEqual(menuCount, 0)

        service.setReady(true)
        XCTAssertEqual(menuCount, 1)
    }

    func testPendingQueueOverflowDropsOldestAction() throws {
        let services = SpacemapServices(yabaiService: MockYabaiService(), alertsService: Alerts())
        var menuCount = 0
        let service = DeepLinkService(
            hud: services.hud,
            themeService: services.themeService,
            showSettings: {},
            showMenu: { menuCount += 1 }
        )
        let menu = try XCTUnwrap(URL(string: "spacemap://menu"))

        // Cap is 16: the oldest of 19 is dropped, leaving 16.
        service.open(urls: Array(repeating: menu, count: 19))
        XCTAssertEqual(menuCount, 0)

        service.setReady(true)
        XCTAssertEqual(menuCount, 16)
    }
}
