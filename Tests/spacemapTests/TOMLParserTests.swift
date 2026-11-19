import XCTest
@testable import spacemap

final class TOMLParserTests: XCTestCase {

    func testParseMissingFieldsFallBackToDefaults() {
        let parsed = try? TOMLParser.parse("""
        [grid]
        cols = 5
        """)

        XCTAssertEqual(parsed?.config.cols, 5)
        XCTAssertEqual(parsed?.config.rows, SpacemapConfig.default.rows)
        XCTAssertEqual(parsed?.config.cellStyle, SpacemapConfig.default.cellStyle)
        XCTAssertEqual(parsed?.config.theme, SpacemapConfig.default.theme)
        XCTAssertEqual(parsed?.config.hotkey, SpacemapConfig.default.hotkey)
        XCTAssertEqual(parsed?.config.pinnedHotkey, SpacemapConfig.default.pinnedHotkey)
    }

    func testParseInvalidValuesFallBackToDefaults() {
        let parsed = try? TOMLParser.parse("""
        [grid]
        cols = "not a number"
        rows = -1
        cellStyle = "invalid"
        showMode = "invalid"
        multiMonitorHUDMode = "invalid"
        unifiedHUDVisibility = "invalid"
        separateHUDVisibility = "invalid"
        maxSpaces = -1
        showSpaceNumbers = "not a boolean"
        showIconStrip = "not a boolean"
        showMultiAppIcons = "not a boolean"
        hideMenuBarIcon = "not a boolean"
        menuBarDisplayMode = "invalid"
        menuBarNearbyCount = -1
        updateMode = "invalid"

        [behavior.hotkey]
        keyKind = "invalid"
        keyCode = -1

        [behavior.pinnedHotkey]
        keyKind = "invalid"
        """)

        XCTAssertEqual(parsed?.config.cols, SpacemapConfig.default.cols)
        XCTAssertEqual(parsed?.config.rows, SpacemapConfig.default.rows)
        XCTAssertEqual(parsed?.config.cellStyle, SpacemapConfig.default.cellStyle)
        XCTAssertEqual(parsed?.config.showMode, SpacemapConfig.default.showMode)
        XCTAssertEqual(parsed?.config.multiMonitorHUDMode, SpacemapConfig.default.multiMonitorHUDMode)
        XCTAssertEqual(parsed?.config.unifiedHUDVisibility, SpacemapConfig.default.unifiedHUDVisibility)
        XCTAssertEqual(parsed?.config.separateHUDVisibility, SpacemapConfig.default.separateHUDVisibility)
        XCTAssertEqual(parsed?.config.maxSpaces, SpacemapConfig.default.maxSpaces)
        XCTAssertEqual(parsed?.config.showSpaceNumbers, SpacemapConfig.default.showSpaceNumbers)
        XCTAssertEqual(parsed?.config.showIconStrip, SpacemapConfig.default.showIconStrip)
        XCTAssertEqual(parsed?.config.showMultiAppIcons, SpacemapConfig.default.showMultiAppIcons)
        XCTAssertEqual(parsed?.config.presence, SpacemapConfig.default.presence)
        XCTAssertEqual(parsed?.config.menuBarDisplayMode, SpacemapConfig.default.menuBarDisplayMode)
        XCTAssertEqual(parsed?.config.menuBarNearbyCount, SpacemapConfig.default.menuBarNearbyCount)
        XCTAssertEqual(parsed?.config.updateMode, SpacemapConfig.default.updateMode)
        XCTAssertEqual(parsed?.config.hotkey, SpacemapConfig.default.hotkey)
        XCTAssertEqual(parsed?.config.pinnedHotkey, SpacemapConfig.default.pinnedHotkey)
        XCTAssertEqual(parsed?.needsRepair, true, "unparsable values must ask for a rewritten file")
    }

    func testParseUnknownKeysAreIgnored() {
        let full = ConfigLoader.tomlConfigString(from: SpacemapConfig.default, includeHeaderComments: false)
        let parsed = try? TOMLParser.parse("[grid]\ncols = 8\nunknownKey = \"ignored\"\n" +
            full.replacingOccurrences(of: "cols = 8\n", with: ""))

        XCTAssertEqual(parsed?.config.cols, 8)
        XCTAssertEqual(parsed?.needsRepair, false, "an unknown key is not a repair")
    }

    func testParseInvalidTOMLThrowsError() {
        XCTAssertThrowsError(try TOMLParser.parse("[grid\ncols = 5")) { error in
            XCTAssertTrue(error is TOMLParserError)
        }
    }

    func testParseEmptyStringThrowsError() {
        XCTAssertThrowsError(try TOMLParser.parse("")) { error in
            XCTAssertTrue(error is TOMLParserError)
        }
    }

    func testParseAdvancedSection() {
        let parsed = try? TOMLParser.parse("""
        [advanced]
        socketHealthInterval = 30
        showExtraWindows = true
        """)

        XCTAssertEqual(parsed?.config.socketHealthInterval, 30)
        XCTAssertEqual(parsed?.config.showExtraWindows, true)
    }

    func testParseTrailingCommaAndMultilineArray() {
        let parsed = try? TOMLParser.parse("""
        [behavior.hotkey]
        keyKind = "keyCode"
        keyCode = 49
        modifiers = [
            "cmd",
            "shift",
        ]
        """)

        XCTAssertEqual(parsed?.config.hotkey.keyCode, 49)
        XCTAssertTrue(parsed?.config.hotkey.modifiers.contains(.maskCommand) ?? false)
        XCTAssertTrue(parsed?.config.hotkey.modifiers.contains(.maskShift) ?? false)
    }

    func testParseDottedKeys() {
        let parsed = try? TOMLParser.parse("""
        grid.cols = 8
        grid.rows = 3
        appearance.theme = "default"
        spaceNames.names."1" = "Term"
        """)

        XCTAssertEqual(parsed?.config.cols, 8)
        XCTAssertEqual(parsed?.config.rows, 3)
        XCTAssertEqual(parsed?.config.theme, "default")
        XCTAssertEqual(parsed?.config.spaceNames, [1: "Term"])
    }

    func testParseHexAndUnderscoredIntegers() {
        let parsed = try? TOMLParser.parse("""
        [grid]
        cols = 0x8
        rows = 1_0

        [glyphStrip]
        maxIconsPerSpace = 0x10
        customX = 0.25
        """)

        XCTAssertEqual(parsed?.config.cols, 8)
        XCTAssertEqual(parsed?.config.rows, 10)
        XCTAssertEqual(parsed?.config.glyphStrip.maxIconsPerSpace, 16)
        XCTAssertEqual(parsed?.config.glyphStrip.customX, 0.25)
    }

    func testParseInlineTable() {
        let parsed = try? TOMLParser.parse("""
        grid = { cols = 8, rows = 3 }
        """)

        XCTAssertEqual(parsed?.config.cols, 8)
        XCTAssertEqual(parsed?.config.rows, 3)
    }

    func testNestedSpaceNameEntriesFlagRepairWhenAnEntryIsInvalid() {
        let parsed = try? TOMLParser.parse("""
        [spaceNames.names]
        "2" = "Code"
        "not-a-space" = "Broken"
        """)

        XCTAssertEqual(parsed?.config.spaceNames, [2: "Code"])
        XCTAssertEqual(parsed?.needsRepair, true)
    }

    func testParseInlineHotkeyAndHUDPositionUnderBehavior() {
        let parsed = try? TOMLParser.parse("""
        [behavior]
        hotkey = { keyKind = "keyCode", keyCode = 49, modifiers = ["cmd"] }
        hudPosition = { kind = "custom", x = 0.25, y = 0.75, screen = "display-A" }
        """)

        XCTAssertEqual(parsed?.config.hotkey.keyCode, 49)
        XCTAssertEqual(parsed?.config.hudPosition, .custom(x: 0.25, y: 0.75, screen: "display-A"))
    }

    func testParseInlineNamesUnderSpaceNameProfile() {
        let parsed = try? TOMLParser.parse("""
        [spaceNameProfiles]
        activeIndex = 0

        [spaceNameProfiles.0]
        name = "Default"
        names = { "1" = "Term", "2" = "Code" }
        """)

        XCTAssertEqual(parsed?.config.spaceNameProfiles.first?.spaceNames, [1: "Term", 2: "Code"])
    }

    func testParseLoneCarriageReturnAndCRLFLineEndings() {
        let loneCR = try? TOMLParser.parse("grid.cols = 8\rgrid.rows = 3\r")
        XCTAssertEqual(loneCR?.config.cols, 8)
        XCTAssertEqual(loneCR?.config.rows, 3)

        let crlf = try? TOMLParser.parse("grid.cols = 6\r\ngrid.rows = 2\r\n")
        XCTAssertEqual(crlf?.config.cols, 6)
        XCTAssertEqual(crlf?.config.rows, 2)
    }

    func testHugeGlyphStripNumbersSaturateInsteadOfTrapping() throws {
        let huge = try TOMLParser.parse("""
        [glyphStrip]
        maxIconsPerSpace = 1e300
        customX = 1e300
        """)
        XCTAssertTrue(huge.needsRepair)
        XCTAssertEqual(huge.config.glyphStrip.maxIconsPerSpace, 16)
        XCTAssertEqual(huge.config.glyphStrip.customX, 1)

        let negative = try TOMLParser.parse("""
        [glyphStrip]
        maxIconsPerSpace = -1e300
        customY = -1e300
        """)
        XCTAssertEqual(negative.config.glyphStrip.maxIconsPerSpace, 0)
        XCTAssertEqual(negative.config.glyphStrip.customY, 0)
    }

}
