import XCTest
import AppKit
@testable import spacemap

final class SettingsOptionsTests: SettingsTestCase {
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

    func testSwitchingToThumbnailsAsksForScreenRecordingOnlyWhenItIsMissing() {
        XCTAssertTrue(SystemPermissions.needsScreenRecordingRequest(hasPermission: false))
        XCTAssertFalse(
            SystemPermissions.needsScreenRecordingRequest(hasPermission: true),
            "a granted permission must not prompt or open System Settings"
        )
    }

    func testEveryHUDCommandHasADistinctDisplayName() {
        let labels = HUDCommand.allCases.map(\.label)

        XCTAssertEqual(Set(labels).count, labels.count, "the HUD key picker needs one name per command")
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    func testSettingsViewAcceptsInjectedYabaiServiceAndExactConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-settings-view-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var config = SpacemapConfig.default
        config.socketHealthInterval = 37
        config.backgroundAlpha = 0.37
        config.iconScale = 0.43
        config.uiScale = 0.61

        _ = SettingsView(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore(),
            themeCatalog: ThemeCatalogService(themeStore: makeTemporaryThemeStore()),
            draft: makeDraft(config, at: path)
        )
    }

    func testSettingsWindowUsesStableFrameAutosaveName() {
        XCTAssertFalse(SettingsWindowController.frameAutosaveName.isEmpty)
    }

}
