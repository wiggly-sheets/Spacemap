import XCTest
@testable import spacemap

final class DeepLinkHandlerTests: XCTestCase {

    private var hud: MockHUDWindowController!
    private var showSettingsCalled = false
    private var showMenuCalled = false
    private var deepLinkHandler: DeepLinkHandler!

    override func setUp() {
        super.setUp()
        hud = MockHUDWindowController()
        showSettingsCalled = false
        showMenuCalled = false
        deepLinkHandler = DeepLinkHandler(
            hud: hud,
            appConfig: AppConfig(),
            themeService: ThemeService(),
            showSettings: { [weak self] in self?.showSettingsCalled = true },
            showMenu: { [weak self] in self?.showMenuCalled = true }
        )
    }

    override func tearDown() {
        deepLinkHandler = nil
        hud = nil
        super.tearDown()
    }

    // MARK: - open() with ready state

    func testOpenToggleHUDWhenReady() {
        deepLinkHandler.isReady = true
        let url = URL(string: "spacemap://toggle-hud")!
        deepLinkHandler.open(urls: [url])
        XCTAssertTrue(hud.toggleCalled)
    }

    func testOpenPinHUDWhenReady() {
        deepLinkHandler.isReady = true
        let url = URL(string: "spacemap://pin-hud")!
        deepLinkHandler.open(urls: [url])
        XCTAssertTrue(hud.pinCalled)
    }

    func testOpenSettingsWhenReady() {
        deepLinkHandler.isReady = true
        let url = URL(string: "spacemap://settings")!
        deepLinkHandler.open(urls: [url])
        XCTAssertTrue(showSettingsCalled)
    }

    func testOpenMenuWhenReady() {
        deepLinkHandler.isReady = true
        let url = URL(string: "spacemap://menu")!
        deepLinkHandler.open(urls: [url])
        XCTAssertTrue(showMenuCalled)
    }

    func testOpenConfigWhenReady() {
        deepLinkHandler.isReady = true
        let url = URL(string: "spacemap://config")!
        deepLinkHandler.open(urls: [url])
        // Config.load() opens the config file path — just verify no crash
    }

    func testOpenThemesWhenReady() {
        deepLinkHandler.isReady = true
        let url = URL(string: "spacemap://themes")!
        deepLinkHandler.open(urls: [url])
        // ThemeManager.reload() opens the themes directory — just verify no crash
    }

    // MARK: - open() with not-ready state (pending actions)

    func testOpenWhenNotReadyQueuesAction() {
        deepLinkHandler.isReady = false
        let url = URL(string: "spacemap://toggle-hud")!
        deepLinkHandler.open(urls: [url])
        XCTAssertFalse(hud.toggleCalled)
        XCTAssertEqual(deepLinkHandler.pendingActions.count, 1)
    }

    func testOpenMultipleUrlsWhenNotReadyQueuesAll() {
        deepLinkHandler.isReady = false
        let urls = [
            URL(string: "spacemap://toggle-hud")!,
            URL(string: "spacemap://settings")!,
            URL(string: "spacemap://menu")!,
        ]
        deepLinkHandler.open(urls: urls)
        XCTAssertEqual(deepLinkHandler.pendingActions.count, 3)
    }

    func testOpenMixedReadyAndNotReadyUrls() {
        deepLinkHandler.isReady = true
        let readyURL = URL(string: "spacemap://toggle-hud")!
        let notReadyURL = URL(string: "spacemap://settings")!
        deepLinkHandler.open(urls: [readyURL, notReadyURL])
        XCTAssertTrue(hud.toggleCalled)
        XCTAssertEqual(deepLinkHandler.pendingActions.count, 1)
    }

    // MARK: - handlePending()

    func testHandlePendingExecutesQueuedActions() {
        deepLinkHandler.isReady = false
        let url = URL(string: "spacemap://toggle-hud")!
        deepLinkHandler.open(urls: [url])
        XCTAssertFalse(hud.toggleCalled)

        deepLinkHandler.isReady = true
        deepLinkHandler.handlePending()

        XCTAssertTrue(hud.toggleCalled)
        XCTAssertTrue(deepLinkHandler.pendingActions.isEmpty)
    }

    func testHandlePendingWithMultipleQueuedActions() {
        deepLinkHandler.isReady = false
        let urls = [
            URL(string: "spacemap://toggle-hud")!,
            URL(string: "spacemap://pin-hud")!,
        ]
        deepLinkHandler.open(urls: urls)

        deepLinkHandler.isReady = true
        deepLinkHandler.handlePending()

        XCTAssertTrue(hud.toggleCalled)
        XCTAssertTrue(hud.pinCalled)
        XCTAssertTrue(deepLinkHandler.pendingActions.isEmpty)
    }

    func testHandlePendingWhenNoPendingActions() {
        deepLinkHandler.isReady = true
        deepLinkHandler.handlePending()
        // Should not crash with empty pending actions
    }

    // MARK: - Ignored URLs

    func testOpenIgnoresUnsupportedURLs() {
        deepLinkHandler.isReady = true
        let urls = [
            URL(string: "https://example.com")!,
            URL(string: "spacemap://unknown")!,
            URL(string: "spacemap://")!,
        ]
        deepLinkHandler.open(urls: urls)
        XCTAssertFalse(hud.toggleCalled)
        XCTAssertTrue(deepLinkHandler.pendingActions.isEmpty)
    }

    // MARK: - Helper

    private class MockHUDWindowController: HUDWindowController {
        var toggleCalled = false
        var pinCalled = false

        override func toggle() {
            toggleCalled = true
        }

        override func pin() {
            pinCalled = true
        }
    }
}