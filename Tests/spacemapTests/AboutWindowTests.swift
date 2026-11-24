import XCTest
import AppKit
@testable import spacemap

final class AboutWindowTests: SettingsTestCase {
    func testAboutWindowIsReusedAcrossRepeatedShowRequests() throws {
        _ = NSApplication.shared
        let themeStore = makeTemporaryThemeStore()
        let service = SettingsService(
            yabaiService: MockYabaiService(),
            themeStore: themeStore,
            themeCatalog: ThemeCatalogService(themeStore: themeStore),
            checkForUpdates: {}
        )

        service.showAboutWindow()
        let first = try XCTUnwrap(service.aboutWindowController)
        service.showAboutWindow()

        let second = try XCTUnwrap(service.aboutWindowController)
        XCTAssertTrue(first === second)
        first.close()
    }

}
