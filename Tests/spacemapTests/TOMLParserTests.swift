import XCTest
@testable import spacemap

final class TOMLParserTests: XCTestCase {

    func testParseEverySetting() {
        let toml = """
        [grid]
        cols = 6
        rows = 3
        cellStyle = "icons"
        showMode = "active"
        multiMonitorHUDMode = "separate"
        unifiedHUDVisibility = "all"
        separateHUDVisibility = "active"
        maxSpaces = 12
        showSpaceNumbers = false
        showIconStrip = false
        showMultiAppIcons = true

        [spaceNames]
        showSpaceNames = true

        [spaceNames.names]
        "1" = "Term"
        "2" = "Code"

        [appearance]
        theme = "dracula"
        mode = "dark"
        backgroundAlpha = 0.5
        iconScale = 0.8
        uiScale = 0.75

        [behavior]
        autoHideTimeout = 10
        displayNavigationWrap = "between"
        useVimKeys = true
        useArrowKeys = true
        customHUDX = 0.25
        customHUDY = 0.75
        focusSpaceOnWindowDrop = "modifier"
        focusSpaceOnWindowDropModifier = "option"
        showHUDOnSpaceChange = true
        hideMenuBarIcon = true
        menuBarDisplayMode = "nearby"
        menuBarNearbyCount = 5
        updateMode = "off"

        [behavior.hotkey]
        keyKind = "keyCode"
        keyCode = 49
        modifiers = ["cmd", "shift"]

        [behavior.pinnedHotkey]
        keyKind = "mediaKey"
        mediaKey = "play-pause"
        modifiers = ["ctrl"]

        [behavior.hudPosition]
        kind = "custom"
        x = 0.25
        y = 0.75

        [advanced]
        socketHealthInterval = 30
        showExtraWindows = true
        """

        let values = try? TOMLParser.parse(toml)
        XCTAssertNotNil(values)

        XCTAssertEqual(values?.cols, 6)
        XCTAssertEqual(values?.rows, 3)
        XCTAssertEqual(values?.cellStyle, .icons)
        XCTAssertEqual(values?.showMode, .active)
        XCTAssertEqual(values?.multiMonitorHUDMode, .separate)
        XCTAssertEqual(values?.unifiedHUDVisibility, .all)
        XCTAssertEqual(values?.separateHUDVisibility, .active)
        XCTAssertEqual(values?.maxSpaces, 12)
        XCTAssertEqual(values?.showSpaceNumbers, false)
        XCTAssertEqual(values?.showIconStrip, false)
        XCTAssertEqual(values?.showMultiAppIcons, true)
        XCTAssertEqual(values?.showSpaceNames, true)
        XCTAssertEqual(values?.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertEqual(values?.theme, "dracula")
        XCTAssertEqual(values?.mode, .dark)
        XCTAssertEqual(values?.backgroundAlpha, 0.5)
        XCTAssertEqual(values?.iconScale, 0.8)
        XCTAssertEqual(values?.uiScale, 0.75)
        XCTAssertEqual(values?.autoHideTimeout, 10)
        XCTAssertEqual(values?.displayNavigationWrap, .between)
        XCTAssertEqual(values?.useVimKeys, true)
        XCTAssertEqual(values?.useArrowKeys, true)
        XCTAssertEqual(values?.customHUDX, 0.25)
        XCTAssertEqual(values?.customHUDY, 0.75)
        XCTAssertEqual(values?.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(values?.focusSpaceOnWindowDropModifier, .option)
        XCTAssertEqual(values?.showHUDOnSpaceChange, true)
        XCTAssertEqual(values?.hideMenuBarIcon, true)
        XCTAssertEqual(values?.menuBarDisplayMode, .nearby)
        XCTAssertEqual(values?.menuBarNearbyCount, 5)
        XCTAssertEqual(values?.updateMode, .off)
        XCTAssertEqual(values?.hotkey?.keyCode, 49)
        XCTAssertTrue((values?.hotkey?.modifiers.contains(.maskCommand)) ?? false)
        XCTAssertTrue((values?.hotkey?.modifiers.contains(.maskShift)) ?? false)
        XCTAssertEqual(values?.pinnedHotkey?.mediaKey, .playPause)
        XCTAssertTrue((values?.pinnedHotkey?.modifiers.contains(.maskControl)) ?? false)
        XCTAssertEqual(values?.hudPosition, .custom(x: 0.25, y: 0.75))
        XCTAssertEqual(values?.socketHealthInterval, 30)
        XCTAssertEqual(values?.showExtraWindows, true)
    }

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
        XCTAssertNil(values?.hideMenuBarIcon)
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
        // unknownKey is not a known field, so it's silently ignored
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

    func testParseSpaceNamesSection() {
        let values = try? TOMLParser.parse("""
        [spaceNames]
        showSpaceNames = true

        [spaceNames.names]
        "1" = "Term"
        "2" = "Code"
        "3" = "Browser"
        """)

        XCTAssertEqual(values?.showSpaceNames, true)
        XCTAssertEqual(values?.spaceNames, [1: "Term", 2: "Code", 3: "Browser"])
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
}