import XCTest
@testable import spacemap

final class ThemeTests: XCTestCase {

    // MARK: - parseThemeContent

    func testParseValidTheme() throws {
        let content = """
        # My Theme
        background=#1a1b26
        focused=#7aa2f7
        text=#a9b1d6
        dropTarget=#bb9af7
        cellBg=#1a1b26
        cellBgFocused=#1a1b26
        rect1=#7aa2f7
        rect2=#bb9af7
        rect3=#9ece6a
        """
        let theme = try XCTUnwrap(ThemeManager.parseThemeContent(content))
        XCTAssertEqual(theme.background, 0x1a1b26)
        XCTAssertEqual(theme.focused, 0x7aa2f7)
        XCTAssertEqual(theme.text, 0xa9b1d6)
        XCTAssertEqual(theme.dropTarget, 0xbb9af7)
        XCTAssertEqual(theme.cellBg, 0x1a1b26)
        XCTAssertEqual(theme.cellBgFocused, 0x1a1b26)
        XCTAssertEqual(theme.rect1, 0x7aa2f7)
        XCTAssertEqual(theme.rect2, 0xbb9af7)
        XCTAssertEqual(theme.rect3, 0x9ece6a)
    }

    func testParseThemeWithoutHash() throws {
        let content = """
        background=ffffff
        focused=000000
        text=333333
        dropTarget=aaaaaa
        cellBg=eeeeee
        cellBgFocused=dddddd
        """
        let theme = try XCTUnwrap(ThemeManager.parseThemeContent(content))
        XCTAssertEqual(theme.background, 0xffffff)
        XCTAssertEqual(theme.focused, 0x000000)
    }

    func testParseThemeRectFallback() throws {
        let content = """
        background=000000
        focused=111111
        text=222222
        dropTarget=333333
        cellBg=444444
        cellBgFocused=555555
        """
        let theme = try XCTUnwrap(ThemeManager.parseThemeContent(content))
        XCTAssertEqual(theme.rect1, 0x111111)
        XCTAssertEqual(theme.rect2, 0x111111)
        XCTAssertEqual(theme.rect3, 0x111111)
    }

    func testParseThemeCommentsIgnored() throws {
        let content = """
        # This is a comment
        background=ff0000
        # Another comment
        focused=00ff00
        text=0000ff
        dropTarget=ffffff
        cellBg=111111
        cellBgFocused=222222
        """
        let theme = try XCTUnwrap(ThemeManager.parseThemeContent(content))
        XCTAssertEqual(theme.background, 0xff0000)
        XCTAssertEqual(theme.focused, 0x00ff00)
    }

    func testParseThemeEmptyLines() throws {
        let content = """

        background=aaaaaa

        focused=bbbbbb

        text=cccccc
        dropTarget=dddddd
        cellBg=eeeeee
        cellBgFocused=ffffffff

        """
        let theme = try XCTUnwrap(ThemeManager.parseThemeContent(content))
        XCTAssertEqual(theme.background, 0xaaaaaa)
    }

    func testParseThemeMissingRequiredFieldReturnsNil() {
        let content = """
        background=000000
        focused=111111
        text=222222
        dropTarget=333333
        # cellBg missing
        cellBgFocused=555555
        """
        XCTAssertNil(ThemeManager.parseThemeContent(content))
    }

    func testParseThemeEmptyReturnsNil() {
        XCTAssertNil(ThemeManager.parseThemeContent(""))
    }

    func testParseThemeInvalidHex() {
        let content = """
        background=ZZZZZZ
        focused=111111
        text=222222
        dropTarget=333333
        cellBg=444444
        cellBgFocused=555555
        """
        XCTAssertNil(ThemeManager.parseThemeContent(content))
    }

    // MARK: - hex formatting

    func testHexPadding() {
        let tm = ThemeManager.shared
        XCTAssertEqual(tm.hex(0), "000000")
        XCTAssertEqual(tm.hex(0xf), "00000f")
        XCTAssertEqual(tm.hex(0xff), "0000ff")
        XCTAssertEqual(tm.hex(0xfff), "000fff")
        XCTAssertEqual(tm.hex(0xffffff), "ffffff")
    }

    // MARK: - Named theme lookup

    func testNamedDefault() {
        let theme = AppTheme.named("nonexistent")
        XCTAssertEqual(theme, AppTheme.default)
    }

    func testNamedDefaultExplicit() {
        let theme = AppTheme.named("default")
        XCTAssertEqual(theme, AppTheme.default)
    }

    func testBuiltinThemesExist() {
        XCTAssertNotEqual(AppTheme.named("tokyo night"), AppTheme.default)
        XCTAssertNotEqual(AppTheme.named("catppuccin"), AppTheme.default)
        XCTAssertNotEqual(AppTheme.named("dracula"), AppTheme.default)
        XCTAssertNotEqual(AppTheme.named("nord"), AppTheme.default)
    }
}
