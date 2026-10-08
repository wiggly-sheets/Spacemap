import XCTest
@testable import spacemap

final class AppFontUpdaterTests: XCTestCase {

    private let sampleRelease = """
    {
      "url": "https://api.github.com/repos/kvndrsslr/sketchybar-app-font/releases/168707231",
      "tag_name": "v3.0.5",
      "name": "v3.0.5",
      "assets": [
        {
          "url": "https://api.github.com/repos/kvndrsslr/sketchybar-app-font/releases/168707231/assets/540118123",
          "name": "Source code (zip)",
          "browser_download_url": "https://github.com/kvndrsslr/sketchybar-app-font/archive/refs/tags/v3.0.5.zip",
          "size": 4021335
        },
        {
          "url": "https://api.github.com/repos/kvndrsslr/sketchybar-app-font/releases/168707231/assets/540118124",
          "name": "sketchybar-app-font.ttf",
          "browser_download_url": "https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v3.0.5/sketchybar-app-font.ttf",
          "size": 171234
        }
      ]
    }
    """

    // MARK: - Release JSON parsing

    func testParseReleasePicksTtfAsset() throws {
        let info = try AppFontUpdater.parseRelease(Data(sampleRelease.utf8))

        XCTAssertEqual(info.tag, "v3.0.5")
        XCTAssertEqual(
            info.downloadURL.absoluteString,
            "https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v3.0.5/sketchybar-app-font.ttf"
        )
        XCTAssertEqual(info.size, 171234)
    }

    func testParseReleaseThrowsWhenTtfAssetMissing() {
        let json = #"{"tag_name":"v9.9.9","assets":[{"name":"other.zip","browser_download_url":"https://example.com/other.zip","size":1}]}"#

        XCTAssertThrowsError(try AppFontUpdater.parseRelease(Data(json.utf8))) { error in
            XCTAssertEqual(error as? AppFontUpdater.UpdateError, .assetMissing)
        }
    }

    func testParseReleaseThrowsOnGarbageInput() {
        XCTAssertThrowsError(try AppFontUpdater.parseRelease(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? AppFontUpdater.UpdateError, .unreadableRelease)
        }
    }

    // MARK: - Tag comparison

    func testNeedsUpdateComparesTags() {
        XCTAssertTrue(AppFontUpdater.needsUpdate(installedTag: "", latestTag: "v3.0.5"))
        XCTAssertTrue(AppFontUpdater.needsUpdate(installedTag: "v3.0.4", latestTag: "v3.0.5"))
        XCTAssertFalse(AppFontUpdater.needsUpdate(installedTag: "v3.0.5", latestTag: "v3.0.5"))
    }

    // MARK: - Downloaded data validation

    func testFontValidationAcceptsSfntMagicBytes() {
        XCTAssertTrue(AppFontUpdater.isValidFontData(Data([0x00, 0x01, 0x00, 0x00]) + Data(count: 100_001)))
        XCTAssertTrue(AppFontUpdater.isValidFontData(Data("true".utf8) + Data(count: 100_001)))
        XCTAssertTrue(AppFontUpdater.isValidFontData(Data("OTTO".utf8) + Data(count: 100_001)))
    }

    func testFontValidationRejectsSmallOrWrongData() {
        XCTAssertFalse(AppFontUpdater.isValidFontData(Data()), "empty body")
        XCTAssertFalse(
            AppFontUpdater.isValidFontData(Data([0x00, 0x01, 0x00, 0x00]) + Data(count: 99_000)),
            "below size floor"
        )
        XCTAssertFalse(
            AppFontUpdater.isValidFontData(Data("<html>error page".utf8) + Data(count: 100_001)),
            "HTML error page with valid size"
        )
    }

    // MARK: - Config keys

    func testAppFontConfigRoundTripsThroughConfigString() throws {
        var values = ConfigValues()
        values.appFont = AppFontConfig(updateMode: .auto, installedVersion: "v3.0.5", lastCheck: 1760000000)

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)

        XCTAssertEqual(reread.appFont, values.appFont)
    }

    func testAppFontDefaultsApplyWhenSectionMissing() throws {
        let values = try TOMLParser.parse("[grid]\ncols = 6\n")

        XCTAssertNil(values.appFont, "missing section keeps the repair flag path intact")
        let config = values.gridConfig
        XCTAssertEqual(config.appFont, AppFontConfig.default)
        XCTAssertEqual(config.appFont.updateMode, .manual)
        XCTAssertEqual(config.appFont.installedVersion, "")
        XCTAssertEqual(config.appFont.lastCheck, 0)
    }

    func testAppFontPartialTableKeepsDefaultsForMissingKeys() throws {
        let values = try TOMLParser.parse("""
        [appFont]
        updateMode = "auto"
        """)

        XCTAssertEqual(values.appFont?.updateMode, .auto)
        XCTAssertEqual(values.appFont?.installedVersion, "")
        XCTAssertEqual(values.appFont?.lastCheck, 0)
    }

    func testAppFontRejectsUnknownUpdateMode() throws {
        let values = try TOMLParser.parse("""
        [appFont]
        updateMode = "sometimes"
        installedVersion = "v3.0.5"
        """)

        XCTAssertEqual(values.appFont?.updateMode, .manual, "unknown mode falls back to the default")
        XCTAssertEqual(values.appFont?.installedVersion, "v3.0.5")
    }

    // MARK: - Font candidate order

    func testUserInstalledFontCandidatesWinOverBundle() {
        let paths = AppGlyphFont.candidateURLs().map(\.path)
        let userInstalled = paths.enumerated().filter {
            $0.element.hasSuffix("Library/Fonts/sketchybar-app-font.ttf")
        }.map(\.offset)
        let bundled = paths.enumerated().filter {
            !$0.element.contains("Library/Fonts")
        }.map(\.offset)

        guard let lastUserInstalled = userInstalled.last, let firstBundled = bundled.first else {
            return XCTFail("expected user-installed and bundled candidates, got \(paths)")
        }
        XCTAssertLessThan(lastUserInstalled, firstBundled, "user-installed font must load before the bundle copy")
    }
}
