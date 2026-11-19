import XCTest
@testable import spacemap

final class ThemeTests: XCTestCase {


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
        let theme = try XCTUnwrap(ThemeCodec.parseThemeContent(content))
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

    func testParseTOMLThemeWithSectionsAndQuotedHex() throws {
        let content = """
        # Custom theme
        [colors]
        background = "#1a1b26" # inline comment
        focused = '#7aa2f7'
        text = "#a9b1d6"
        dropTarget = "#bb9af7"
        cellBg = "#1a1b26"
        cellBgFocused = "#1a1b26"
        rect1 = "#7aa2f7"
        rect2 = "#bb9af7"
        rect3 = "#9ece6a"
        """
        let theme = try XCTUnwrap(ThemeCodec.parseThemeContent(content))
        XCTAssertEqual(theme.background, 0x1a1b26)
        XCTAssertEqual(theme.focused, 0x7aa2f7)
        XCTAssertEqual(theme.text, 0xa9b1d6)
    }

    func testParseHexValueAcceptsTOMLForms() {
        XCTAssertEqual(ThemeCodec.parseHexValue("#1a1b26"), 0x1a1b26)
        XCTAssertEqual(ThemeCodec.parseHexValue("\"#1a1b26\""), 0x1a1b26)
        XCTAssertEqual(ThemeCodec.parseHexValue("'#1a1b26'"), 0x1a1b26)
        XCTAssertEqual(ThemeCodec.parseHexValue("#1a1b26 # comment"), 0x1a1b26)
        XCTAssertNil(ThemeCodec.parseHexValue("#12345"))
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
        let theme = try XCTUnwrap(ThemeCodec.parseThemeContent(content))
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
        let theme = try XCTUnwrap(ThemeCodec.parseThemeContent(content))
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
        let theme = try XCTUnwrap(ThemeCodec.parseThemeContent(content))
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
        cellBgFocused=ffffff

        """
        let theme = try XCTUnwrap(ThemeCodec.parseThemeContent(content))
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
        XCTAssertNil(ThemeCodec.parseThemeContent(content))
    }

    func testParseThemeEmptyReturnsNil() {
        XCTAssertNil(ThemeCodec.parseThemeContent(""))
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
        XCTAssertNil(ThemeCodec.parseThemeContent(content))
    }


    func testHexPadding() {
        XCTAssertEqual(ThemeCodec.hex(0), "000000")
        XCTAssertEqual(ThemeCodec.hex(0xf), "00000f")
        XCTAssertEqual(ThemeCodec.hex(0xff), "0000ff")
        XCTAssertEqual(ThemeCodec.hex(0xfff), "000fff")
        XCTAssertEqual(ThemeCodec.hex(0xffffff), "ffffff")
    }


    func testNamedDefault() throws {
        let (store, _) = try makeTemporaryStore()
        XCTAssertEqual(store.named("nonexistent"), AppTheme.default)
    }

    func testNamedDefaultExplicit() throws {
        let (store, _) = try makeTemporaryStore()
        XCTAssertEqual(store.named("default"), AppTheme.default)
    }

    // MARK: - Store

    func testNamedAcceptsCompactNamesAndPrefersExactOnes() throws {
        let directory = try makeTemporaryDirectory()
        try writeTheme(named: "my theme", in: directory)
        let store = ThemeStore(directory: directory)

        XCTAssertEqual(store.named("my theme").background, 0x101010,
                       "the file must load from the injected directory")
        XCTAssertEqual(store.named("My-Theme").background, 0x101010,
                       "documented compact names resolve to the same theme")
        XCTAssertEqual(store.named("missing"), AppTheme.default)
    }

    func testNamedResolvesACompactNameWithNoExactKey() throws {
        let directory = try makeTemporaryDirectory()
        try writeTheme(named: "Tokyo Night", in: directory)
        let store = ThemeStore(directory: directory)

        XCTAssertEqual(store.named("tokyonight").background, 0x101010,
                       "the compact fallback must resolve when no exact key exists")
    }

    func testNamedPrefersTheExactKeyOverACompactCollision() throws {
        let directory = try makeTemporaryDirectory()
        try writeTheme(named: "My Theme", in: directory, background: 0x111111)
        try writeTheme(named: "MyTheme", in: directory, background: 0x222222)
        let store = ThemeStore(directory: directory)

        XCTAssertEqual(store.named("mytheme").background, 0x222222,
                       "the exact key wins over a compact candidate")
        XCTAssertEqual(store.named("my theme").background, 0x111111)
    }

    func testReloadIfChangedLoadsAThemeWrittenAfterTheLastLoad() throws {
        let (store, directory) = try makeTemporaryStore()
        XCTAssertEqual(store.named("my theme"), AppTheme.default,
                       "the theme file does not exist yet")

        try writeTheme(named: "my theme", in: directory)
        store.reloadIfChanged()

        XCTAssertEqual(store.named("my theme").background, 0x101010,
                       "a changed theme directory must reload without a fresh store")
    }

    func testSaveWritesAnEditedCopyAndSelectsIt() throws {        let (store, directory) = try makeTemporaryStore()
        let theme = AppTheme(
            background: 0x010203, focused: 0x040506, text: 0x070809,
            dropTarget: 0x0a0b0c, cellBg: 0x0d0e0f, cellBgFocused: 0x101112,
            rect1: 0x131415, rect2: 0x161718, rect3: 0x191a1b
        )

        XCTAssertEqual(store.save(theme: theme, name: "Mine"), "Mine")
        XCTAssertEqual(store.named("mine"), theme, "save must reload the store")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Mine.toml").path))

        XCTAssertEqual(store.save(theme: theme, name: "Mine"), "Mine (Edited)",
                       "saving an existing theme must never overwrite it")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Mine-(Edited).toml").path))
    }

    func testSaveReturnsTheSanitizedNameItWrote() throws {
        let (store, directory) = try makeTemporaryStore()

        let saved = try XCTUnwrap(store.save(theme: sampleTheme, name: "a/b"))

        XCTAssertEqual(saved, "a-b")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("a-b.toml").path))
        XCTAssertEqual(store.named(saved), sampleTheme,
                       "the returned name must resolve to the file it wrote")
    }

    func testCodecRoundTripsThroughTheSavedShape() throws {
        let theme = AppTheme(
            background: 0x1a1b26, focused: 0x7aa2f7, text: 0xa9b1d6,
            dropTarget: 0xbb9af7, cellBg: 0x1a1b24, cellBgFocused: 0x1a1b25,
            rect1: 0x9ece6a, rect2: 0x7dcfff, rect3: 0xe0af68
        )
        let rendered = ThemeCodec.renderTheme(theme)
        XCTAssertEqual(ThemeCodec.parseThemeContent(rendered), theme)
        XCTAssertEqual(ThemeCodec.renderTheme(try XCTUnwrap(ThemeCodec.parseThemeContent(rendered))),
                       rendered, "rendering is stable across a parse")
    }

    func testEffectiveThemeNameFollowsTheHUDUnlessTheStripOverridesIt() throws {
        let (store, _) = try makeTemporaryStore()
        var strip = GlyphStripConfig.default
        strip.theme = ""
        strip.matchHUDAppearance = false
        XCTAssertEqual(store.resolvedThemeName(strip: strip, hudTheme: "nord"), "nord",
                       "an empty strip theme follows the HUD")

        strip.theme = "dracula"
        XCTAssertEqual(store.resolvedThemeName(strip: strip, hudTheme: "nord"), "dracula")

        strip.matchHUDAppearance = true
        XCTAssertEqual(store.resolvedThemeName(strip: strip, hudTheme: "nord"), "nord",
                       "match HUD appearance wins over the strip's own theme")
    }

    func testAppThemeColorsInitRequiresTheSixCoreKeysAndDefaultsRects() {
        let core = [
            "background": UInt32(1), "focused": UInt32(2), "text": UInt32(3),
            "dropTarget": UInt32(4), "cellBg": UInt32(5), "cellBgFocused": UInt32(6),
        ]
        let theme = AppTheme(colors: core)
        XCTAssertEqual(theme?.rect1, 2, "missing rects fall back to focused")
        XCTAssertEqual(theme?.rect2, 2)
        XCTAssertEqual(theme?.rect3, 2)
        XCTAssertNil(AppTheme(colors: ["background": 1, "focused": 2]),
                     "every core key is required")

        var withExtras = core
        withExtras["accent"] = 9
        withExtras["RECT1"] = 7
        let extras = AppTheme(colors: withExtras)
        XCTAssertEqual(extras?.rect1, 7, "keys are case-insensitive and extras are ignored")

        var duplicated = core
        duplicated["dropTarget"] = 4
        duplicated["DROPTARGET"] = 9
        XCTAssertEqual(AppTheme(colors: duplicated)?.dropTarget, 4,
                       "the exact camelCase key wins, so duplicates never depend on order")
        duplicated.removeValue(forKey: "dropTarget")
        XCTAssertEqual(AppTheme(colors: duplicated)?.dropTarget, 9,
                       "the lowercase fallback still accepts the on-disk names")
    }

    func testEditorCompositionRejectsAnyBadHexField() {
        let valid = Dictionary(uniqueKeysWithValues: AppTheme.colorNames.map { ($0, "#102030") })
        XCTAssertEqual(ThemeCodec.theme(fromHexes: valid)?.text, 0x102030)

        var bad = valid
        bad["focused"] = "#12"
        XCTAssertNil(ThemeCodec.theme(fromHexes: bad),
                     "a bad hex must block the save instead of composing black")
    }

    // MARK: - Catalog

    func testCatalogEntryBuildsPreviewTheme() {
        let entry = ThemeCatalogEntry(
            name: "Example",
            file: "themes/Example.toml",
            colors: [
                "background": "#101010", "focused": "#202020", "text": "#ffffff",
                "dropTarget": "#303030", "cellBg": "#404040", "cellBgFocused": "#505050",
                "rect1": "#606060", "rect2": "#707070", "rect3": "#808080",
            ]
        )
        XCTAssertEqual(entry.theme?.background, 0x101010)
        XCTAssertEqual(entry.theme?.rect3, 0x808080)
        XCTAssertNil(ThemeCatalogEntry(name: "Bad", file: "x", colors: [:]).theme)

        let lowercased = ThemeCatalogEntry(
            name: "Lowercased",
            file: "themes/Lowercased.toml",
            colors: [
                "background": "#101010", "focused": "#202020", "text": "#ffffff",
                "droptarget": "#303030", "cellbg": "#404040", "cellbgfocused": "#505050",
            ]
        )
        XCTAssertEqual(lowercased.theme?.dropTarget, 0x303030,
                       "catalog JSON uses the on-disk names")

        let lenient = ThemeCatalogEntry(
            name: "Lenient",
            file: "themes/Lenient.toml",
            colors: [
                "background": "#fff", "focused": "FF202020", "text": "#ffffff",
                "dropTarget": "#303030", "cellBg": "#404040", "cellBgFocused": "#505050",
                "rect1": "#606060", "rect2": "#707070", "rect3": "#123456789",
            ]
        )
        XCTAssertEqual(lenient.theme?.background, 0x000fff,
                       "previews keep the old 1-8 digit hex acceptance")
        XCTAssertEqual(lenient.theme?.focused, 0xff202020,
                       "eight-digit ARGB previews, masked to RGB at paint time")
        XCTAssertEqual(lenient.theme?.rect3, 0xff202020,
                       "a too-long value drops like any unparsable colour, so the rect falls back")
    }

    @MainActor
    func testCatalogNamesWithPathSeparatorsShareOneOnDiskName() throws {
        let (store, directory) = try makeTemporaryStore()
        let entry = ThemeCatalogEntry(
            name: "Neon/Night",
            file: "themes/Neon-Night.toml",
            colors: [:]
        )

        XCTAssertEqual(store.save(theme: sampleTheme, name: entry.name), entry.fileStem,
                       "install writes the same sanitized stem the apply path uses")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Neon-Night.toml").path))

        let catalog = ThemeCatalogService(themeStore: store)
        XCTAssertTrue(catalog.isInstalled(entry), "the applied file counts as installed")
        XCTAssertEqual(store.named(entry.fileStem), sampleTheme)
    }

    // MARK: - Helpers

    /// A theme that differs from `.default` in every role, so a resolution
    /// failure cannot pass by falling back to the default theme.
    private var sampleTheme: AppTheme {
        AppTheme(
            background: 0x010203, focused: 0x040506, text: 0x070809,
            dropTarget: 0x0a0b0c, cellBg: 0x0d0e0f, cellBgFocused: 0x101112,
            rect1: 0x131415, rect2: 0x161718, rect3: 0x191a1b
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-theme-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeTemporaryStore() throws -> (ThemeStore, URL) {
        let directory = try makeTemporaryDirectory()
        return (ThemeStore(directory: directory), directory)
    }

    private func writeTheme(
        named name: String,
        in directory: URL,
        background: UInt32 = 0x101010
    ) throws {
        let content = """
        [colors]
        background = "#\(ThemeCodec.hex(background))"
        focused = "#202020"
        text = "#303030"
        dropTarget = "#404040"
        cellBg = "#505050"
        cellBgFocused = "#606060"
        """
        try content.write(
            to: directory.appendingPathComponent("\(name).toml"),
            atomically: true,
            encoding: .utf8
        )
    }

    func testEditingAnExistingThemeTargetsAnEditedCopy() {
        XCTAssertEqual(
            ThemeStore.editedCopyName("Dracula", existing: true),
            "Dracula (Edited)"
        )
        XCTAssertEqual(
            ThemeStore.editedCopyName("Dracula (Edited)", existing: true),
            "Dracula (Edited)"
        )
        XCTAssertEqual(
            ThemeStore.editedCopyName("Dracula", existing: false),
            "Dracula"
        )
    }

    func testThemeNameNormalizationCollapsesSeparatorsAndWhitespace() {
        XCTAssertEqual(ThemeStore.normalizedName("  Monokai--Dark  "), "monokai dark")
        XCTAssertEqual(ThemeStore.normalizedName("Atom_One_Dark"), "atom one dark")
        XCTAssertEqual(ThemeStore.normalizedName("DEFAULT"), "default")
    }
}

extension XCTestCase {
    /// A `ThemeStore` over a unique temp directory, removed at teardown. Tests
    /// must never read or create the real `~/.config/spacemap/themes`.
    func makeTemporaryThemeStore() -> ThemeStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-test-themes-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ThemeStore(directory: directory)
    }
}
