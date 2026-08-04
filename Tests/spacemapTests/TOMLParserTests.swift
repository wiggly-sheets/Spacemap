import XCTest
@testable import spacemap

final class TOMLParserTests: XCTestCase {

    func testParseEverySetting() {
        let values = TOMLParser.parse("""
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
        """)

        XCTAssertEqual(values.cols, 6)
        XCTAssertEqual(values.rows, 3)
        XCTAssertEqual(values.cellStyle, .icons)
        XCTAssertEqual(values.showMode, .active)
        XCTAssertEqual(values.multiMonitorHUDMode, .separate)
        XCTAssertEqual(values.unifiedHUDVisibility, .all)
        XCTAssertEqual(values.separateHUDVisibility, .active)
        XCTAssertEqual(values.maxSpaces, 12)
        XCTAssertFalse(values.showSpaceNumbers!)
        XCTAssertFalse(values.showIconStrip!)
        XCTAssertTrue(values.showMultiAppIcons!)
        XCTAssertTrue(values.showSpaceNames!)
        XCTAssertEqual(values.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertEqual(values.theme, "dracula")
        XCTAssertEqual(values.mode, .dark)
        XCTAssertEqual(values.backgroundAlpha, 0.5)
        XCTAssertEqual(values.iconScale, 0.8)
        XCTAssertEqual(values.uiScale, 0.75)
        XCTAssertEqual(values.autoHideTimeout, 10)
        XCTAssertEqual(values.displayNavigationWrap, .between)
        XCTAssertTrue(values.useVimKeys!)
        XCTAssertTrue(values.useArrowKeys!)
        XCTAssertEqual(values.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(values.focusSpaceOnWindowDropModifier, .option)
        XCTAssertTrue(values.showHUDOnSpaceChange!)
        XCTAssertTrue(values.hideMenuBarIcon!)
        XCTAssertEqual(values.menuBarDisplayMode, .nearby)
        XCTAssertEqual(values.menuBarNearbyCount, 5)
        XCTAssertEqual(values.updateMode, .off)
        XCTAssertEqual(values.hotkey?.keyCode, 49)
        XCTAssertTrue(values.hotkey?.modifiers.contains(.maskCommand) == true)
        XCTAssertTrue(values.hotkey?.modifiers.contains(.maskShift) == true)
        XCTAssertEqual(values.pinnedHotkey?.mediaKey, .playPause)
        XCTAssertTrue(values.pinnedHotkey?.modifiers.contains(.maskControl) == true)
        XCTAssertEqual(values.hudPosition, .custom(x: 0.25, y: 0.75))
        XCTAssertEqual(values.socketHealthInterval, 30)
        XCTAssertTrue(values.showExtraWindows!)
    }

    func testParseMissingFieldsAreNil() {
        let values = TOMLParser.parse("""
        [grid]
        cols = 5
        """)

        XCTAssertEqual(values.cols, 5)
        XCTAssertNil(values.rows)
        XCTAssertNil(values.cellStyle)
        XCTAssertNil(values.theme)
        XCTAssertNil(values.hotkey)
        XCTAssertNil(values.pinnedHotkey)
    }

    func testParseInvalidValuesAreNil() {
        let values = TOMLParser.parse("""
        [grid]
        cols = 0
        rows = "broken"
        cellStyle = "invalid"
        maxSpaces = 99

        [appearance]
        mode = "invalid"
        backgroundAlpha = 2.0
        iconScale = -1.0
        uiScale = 5.0

        [behavior]
        autoHideTimeout = -1
        menuBarDisplayMode = "invalid"
        menuBarNearbyCount = 99

        [advanced]
        socketHealthInterval = 0
        """)

        // Invalid values are set as nil (parsed but not valid)
        // cols = 0 is parsed as Int 0, but toGridConfig will clamp it
        XCTAssertEqual(values.cols, 0)
        // Invalid enum strings are nil
        XCTAssertNil(values.cellStyle)
        XCTAssertNil(values.mode)
        XCTAssertNil(values.menuBarDisplayMode)
        // Out-of-range numeric values are still parsed
        XCTAssertEqual(values.maxSpaces, 99)
        XCTAssertEqual(values.backgroundAlpha, 2.0)
        XCTAssertEqual(values.iconScale, -1.0)
        XCTAssertEqual(values.uiScale, 5.0)
        XCTAssertEqual(values.autoHideTimeout, -1)
        XCTAssertEqual(values.menuBarNearbyCount, 99)
        XCTAssertEqual(values.socketHealthInterval, 0)
    }

    func testParseCommentsAndQuotedValues() {
        let values = TOMLParser.parse("""
        # Comment
        [grid]
        cols = 4 # Inline comment

        [appearance]
        theme = "tokyo # night"
        """)

        XCTAssertEqual(values.cols, 4)
        XCTAssertEqual(values.theme, "tokyo # night")
    }

    func testParseHUDPositionPresets() {
        for (kind, expected) in [
            ("center", HUDPosition.center),
            ("top", HUDPosition.top),
            ("bottom", HUDPosition.bottom)
        ] as [(String, HUDPosition)] {
            let values = TOMLParser.parse("""
            [behavior.hudPosition]
            kind = "\(kind)"
            """)
            XCTAssertEqual(values.hudPosition, expected)
        }
    }

    func testParseInvalidCustomHUDPositionIsNil() {
        let values = TOMLParser.parse("""
        [behavior.hudPosition]
        kind = "custom"
        x = 2.0
        y = 0.5
        """)
        XCTAssertNil(values.hudPosition)
    }

    func testParseHotkeyKeyCode() {
        let values = TOMLParser.parse("""
        [behavior.hotkey]
        keyKind = "keyCode"
        keyCode = 49
        modifiers = ["cmd", "shift"]
        """)

        XCTAssertEqual(values.hotkey?.keyCode, 49)
        XCTAssertTrue(values.hotkey?.modifiers.contains(.maskCommand) == true)
        XCTAssertTrue(values.hotkey?.modifiers.contains(.maskShift) == true)
    }

    func testParseHotkeyMediaKey() {
        let values = TOMLParser.parse("""
        [behavior.hotkey]
        keyKind = "mediaKey"
        mediaKey = "play-pause"
        modifiers = ["ctrl"]
        """)

        XCTAssertEqual(values.hotkey?.mediaKey, .playPause)
        XCTAssertTrue(values.hotkey?.modifiers.contains(.maskControl) == true)
    }

    func testParseHotkeyNone() {
        let values = TOMLParser.parse("""
        [behavior.hotkey]
        keyKind = "none"
        modifiers = []
        """)

        XCTAssertEqual(values.hotkey?.key, HotkeyKey.none)
    }

    func testParsePinnedHotkey() {
        let values = TOMLParser.parse("""
        [behavior.pinnedHotkey]
        keyKind = "keyCode"
        keyCode = 121
        modifiers = ["ctrl"]
        """)

        XCTAssertEqual(values.pinnedHotkey?.keyCode, 121)
        XCTAssertTrue(values.pinnedHotkey?.modifiers.contains(.maskControl) == true)
    }

    func testParseUnknownKeysAreIgnored() {
        let values = TOMLParser.parse("""
        [grid]
        cols = 8
        unknownKey = "ignored"
        """)

        XCTAssertEqual(values.cols, 8)
        // unknownKey is not a known field, so it's silently ignored
    }

    func testParseInvalidTOMLReturnsEmptyConfig() {
        let values = TOMLParser.parse("[grid\ncols = 5")
        // Invalid TOML returns empty ConfigValues (all optionals nil)
        XCTAssertNil(values.cols)
    }

    func testParseEmptyStringReturnsEmptyConfig() {
        let values = TOMLParser.parse("")
        XCTAssertNil(values.cols)
        XCTAssertNil(values.theme)
    }

    func testParseSpaceNamesSection() {
        let values = TOMLParser.parse("""
        [spaceNames]
        showSpaceNames = true

        [spaceNames.names]
        "1" = "Term"
        "2" = "Code"
        "3" = "Browser"
        """)

        XCTAssertTrue(values.showSpaceNames!)
        XCTAssertEqual(values.spaceNames, [1: "Term", 2: "Code", 3: "Browser"])
    }

    func testParseAdvancedSection() {
        let values = TOMLParser.parse("""
        [advanced]
        socketHealthInterval = 30
        showExtraWindows = true
        """)

        XCTAssertEqual(values.socketHealthInterval, 30)
        XCTAssertTrue(values.showExtraWindows!)
    }

    func testParseBehaviorSection() {
        let values = TOMLParser.parse("""
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
        """)

        XCTAssertEqual(values.autoHideTimeout, 10)
        XCTAssertEqual(values.displayNavigationWrap, .between)
        XCTAssertTrue(values.useVimKeys!)
        XCTAssertTrue(values.useArrowKeys!)
        XCTAssertEqual(values.customHUDX, 0.25)
        XCTAssertEqual(values.customHUDY, 0.75)
        XCTAssertEqual(values.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(values.focusSpaceOnWindowDropModifier, .option)
        XCTAssertTrue(values.showHUDOnSpaceChange!)
        XCTAssertTrue(values.hideMenuBarIcon!)
        XCTAssertEqual(values.menuBarDisplayMode, .nearby)
        XCTAssertEqual(values.menuBarNearbyCount, 5)
        XCTAssertEqual(values.updateMode, .off)
    }
}
