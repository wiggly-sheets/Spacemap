import XCTest
@testable import spacemap

final class TOMLParserTests: XCTestCase {

    func testParseMissingFieldsAreNil() {
        let values = try? TOMLParser.parse("""
        [grid]
        cols = 5
        """)

        XCTAssertEqual(values?.cols, 5)
        XCTAssertNil(values?.rows)
        XCTAssertNil(values?.cellStyle)
        XCTAssertNil(values?.theme)
        XCTAssertNil(values?.hotkey)
        XCTAssertNil(values?.pinnedHotkey)
    }

    func testParseInvalidValuesAreNil() {
        let values = try? TOMLParser.parse("""
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

        XCTAssertNil(values?.cols)
        XCTAssertNil(values?.rows)
        XCTAssertNil(values?.cellStyle)
        XCTAssertNil(values?.theme)
        XCTAssertNil(values?.hotkey)
        XCTAssertNil(values?.pinnedHotkey)
        XCTAssertNil(values?.showSpaceNumbers)
        XCTAssertNil(values?.showIconStrip)
        XCTAssertNil(values?.showMultiAppIcons)
        XCTAssertNil(values?.presence)
        XCTAssertNil(values?.menuBarDisplayMode)
        XCTAssertNil(values?.menuBarNearbyCount)
        XCTAssertNil(values?.updateMode)
        XCTAssertNil(values?.hotkey?.keyCode)
        XCTAssertNil(values?.pinnedHotkey?.mediaKey)
    }

    func testParseUnknownKeysAreIgnored() {
        let values = try? TOMLParser.parse("""
        [grid]
        cols = 8
        unknownKey = "ignored"
        """)

        XCTAssertEqual(values?.cols, 8)
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
        let values = try? TOMLParser.parse("""
        [advanced]
        socketHealthInterval = 30
        showExtraWindows = true
        """)

        XCTAssertEqual(values?.socketHealthInterval, 30)
        XCTAssertEqual(values?.showExtraWindows, true)
    }

    func testParseTrailingCommaAndMultilineArray() {
        let values = try? TOMLParser.parse("""
        [behavior.hotkey]
        keyKind = "keyCode"
        keyCode = 49
        modifiers = [
            "cmd",
            "shift",
        ]
        """)

        XCTAssertNotNil(values?.hotkey)
        XCTAssertTrue(values?.hotkey?.modifiers.contains(.maskCommand) ?? false)
        XCTAssertTrue(values?.hotkey?.modifiers.contains(.maskShift) ?? false)
    }

    func testParseDottedKeys() {
        let values = try? TOMLParser.parse("""
        grid.cols = 8
        grid.rows = 3
        appearance.theme = "default"
        spaceNames.names."1" = "Term"
        """)

        XCTAssertEqual(values?.cols, 8)
        XCTAssertEqual(values?.rows, 3)
        XCTAssertEqual(values?.theme, "default")
        XCTAssertEqual(values?.spaceNames, [1: "Term"])
    }

    func testParseHexAndUnderscoredIntegers() {
        let values = try? TOMLParser.parse("""
        [grid]
        cols = 0x8
        rows = 1_0

        [glyphStrip]
        maxIconsPerSpace = 0x10
        xOffset = 1_000
        """)

        XCTAssertEqual(values?.cols, 8)
        XCTAssertEqual(values?.rows, 10)
        XCTAssertEqual(values?.glyphStrip?.maxIconsPerSpace, 16)
        XCTAssertEqual(values?.glyphStrip?.xOffset, 1000)
    }

    func testParseInlineTable() {
        let values = try? TOMLParser.parse("""
        grid = { cols = 8, rows = 3 }
        """)

        XCTAssertEqual(values?.cols, 8)
        XCTAssertEqual(values?.rows, 3)
    }

    func testDirectSpaceNameEntriesArePreserved() {
        let values = try? TOMLParser.parse("""
        [spaceNames]
        showSpaceNames = false
        "2" = "Code"
        """)

        XCTAssertEqual(values?.showSpaceNames, false)
        XCTAssertEqual(values?.spaceNames, [2: "Code"])
        XCTAssertEqual(values?.hasInvalidSpaceNames, false)
    }

    func testDirectSpaceNameEntriesFlagRepairWhenAnEntryIsInvalid() {
        let values = try? TOMLParser.parse("""
        [spaceNames]
        "2" = "Code"
        "not-a-space" = "Broken"
        """)

        XCTAssertEqual(values?.spaceNames, [2: "Code"])
        XCTAssertEqual(values?.hasInvalidSpaceNames, true)
    }

    func testLegacyBareBooleanGlyphStripMapsToEnabled() {
        let enabled = try? TOMLParser.parse("glyphStrip = true")
        XCTAssertEqual(enabled?.glyphStrip?.enabled, true)

        let disabled = try? TOMLParser.parse("glyphStrip = false")
        XCTAssertEqual(disabled?.glyphStrip?.enabled, false)

        let table = try? TOMLParser.parse("""
        [glyphStrip]
        enabled = true
        iconSize = 14
        """)
        XCTAssertEqual(table?.glyphStrip?.enabled, true)
        XCTAssertEqual(table?.glyphStrip?.iconSize, 14)
    }

    func testParseInlineHotkeyAndHUDPositionUnderBehavior() {
        let values = try? TOMLParser.parse("""
        [behavior]
        hotkey = { keyKind = "keyCode", keyCode = 49, modifiers = ["cmd"] }
        hudPosition = { kind = "custom", x = 0.25, y = 0.75 }
        """)

        XCTAssertEqual(values?.hotkey?.keyCode, 49)
        XCTAssertEqual(values?.hudPosition, .custom(x: 0.25, y: 0.75))
    }

    func testParseInlineNamesUnderSpaceNameProfile() {
        let values = try? TOMLParser.parse("""
        [spaceNameProfiles]
        activeIndex = 0

        [spaceNameProfiles.0]
        name = "Default"
        names = { "1" = "Term", "2" = "Code" }
        """)

        XCTAssertEqual(values?.spaceNameProfiles?.first?.spaceNames, [1: "Term", 2: "Code"])
    }

    func testParseLoneCarriageReturnAndCRLFLineEndings() {
        let loneCR = try? TOMLParser.parse("grid.cols = 8\rgrid.rows = 3\r")
        XCTAssertEqual(loneCR?.cols, 8)
        XCTAssertEqual(loneCR?.rows, 3)

        let crlf = try? TOMLParser.parse("grid.cols = 6\r\ngrid.rows = 2\r\n")
        XCTAssertEqual(crlf?.cols, 6)
        XCTAssertEqual(crlf?.rows, 2)
    }

    func testHugeGlyphStripNumbersSaturateInsteadOfTrapping() throws {
        let huge = try TOMLParser.parse("""
        [glyphStrip]
        maxIconsPerSpace = 1e300
        xOffset = 1e300
        """)
        let (config, needsRepair) = huge.toGridConfig()
        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.glyphStrip.maxIconsPerSpace, 16)
        XCTAssertEqual(config.glyphStrip.xOffset, 4000)

        let negative = try TOMLParser.parse("""
        [glyphStrip]
        maxIconsPerSpace = -1e300
        xOffset = -1e300
        """)
        let (negativeConfig, _) = negative.toGridConfig()
        XCTAssertEqual(negativeConfig.glyphStrip.maxIconsPerSpace, 0)
        XCTAssertEqual(negativeConfig.glyphStrip.xOffset, -4000)
    }

    func testLegacyBehaviorShowExtraWindowsFallsBackButAdvancedAndTopLevelWin() throws {
        let legacy = try TOMLParser.parse("""
        [behavior]
        showExtraWindows = true
        """).gridConfig
        XCTAssertTrue(legacy.showExtraWindows, "pre-[advanced] files must keep their value")

        let advancedWins = try TOMLParser.parse("""
        [behavior]
        showExtraWindows = false

        [advanced]
        showExtraWindows = true
        """).gridConfig
        XCTAssertTrue(advancedWins.showExtraWindows, "[advanced] must win over the legacy key")

        let topLevelWins = try TOMLParser.parse("""
        showExtraWindows = false

        [behavior]
        showExtraWindows = true
        """).gridConfig
        XCTAssertFalse(topLevelWins.showExtraWindows, "a top-level key must win over the legacy key")
    }

    func testDirectAndNestedSpaceNamesMergeWithNestedWinning() throws {
        let values = try TOMLParser.parse("""
        [spaceNames]
        "1" = "Direct"
        "2" = "Two"

        [spaceNames.names]
        "1" = "Nested"
        "3" = "Three"
        """)

        XCTAssertEqual(values.spaceNames, [1: "Nested", 2: "Two", 3: "Three"])
    }
}
