import XCTest
@testable import spacemap

final class ConfigPresetStoreTests: XCTestCase {

    private var root: URL!
    private var store: ConfigPresetStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-presets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ConfigPresetStore(
            directory: root.appendingPathComponent("presets").path,
            configPath: root.appendingPathComponent("config.toml").path
        )
        ConfigLoader.save(GridConfig.default, to: store.configPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSwitchingPresetsSavesTheOutgoingEdits() throws {
        XCTAssertTrue(store.create("work", from: .defaults))
        XCTAssertTrue(store.create("home", from: .defaults))
        XCTAssertTrue(store.apply("work"))

        // Edit while "work" is active; the preset file may lag until a switch.
        var edited = ConfigLoader.load(from: store.configPath, silentMode: true).values.gridConfig
        edited.cols = 5
        ConfigLoader.save(edited, to: store.configPath)

        XCTAssertTrue(store.apply("home"))
        XCTAssertEqual(store.activeName, "home")

        let work = ConfigLoader.load(
            from: root.appendingPathComponent("presets/work.toml").path,
            silentMode: true
        ).values.gridConfig
        XCTAssertEqual(work.cols, 5, "outgoing preset must capture edits made while it was active")
        XCTAssertEqual(ConfigLoader.load(from: store.configPath, silentMode: true).values.gridConfig.cols, 8)
    }

    func testPresetBuiltFromAnotherPresetCopiesItsSettings() throws {
        var base = GridConfig.default
        base.cols = 6
        ConfigLoader.save(base, to: store.configPath)

        XCTAssertTrue(store.create("base", from: .current))
        XCTAssertTrue(store.create("copy", from: .preset("base")))
        XCTAssertEqual(store.names(), ["base", "copy"])

        let copy = ConfigLoader.load(
            from: root.appendingPathComponent("presets/copy.toml").path,
            silentMode: true
        ).values.gridConfig
        XCTAssertEqual(copy.cols, 6)
        XCTAssertFalse(store.create("copy", from: .defaults), "existing presets are never overwritten")
    }

    func testUnsafePresetNamesAreRejected() {
        for name in ["", "  ", "a/b", "../escape", ".hidden", String(repeating: "a", count: 41)] {
            XCTAssertNil(ConfigPresetStore.sanitizedName(name), "accepted \(name)")
        }
        XCTAssertEqual(ConfigPresetStore.sanitizedName("  My Work  "), "My Work")
    }

    func testExportThenImportLeavesOutFontInstallState() throws {
        var config = GridConfig.default
        config.cols = 7
        config.appFont.installedVersion = "v9.9.9"
        config.appFont.lastCheck = 42
        ConfigLoader.save(config, to: store.configPath)

        let exported = root.appendingPathComponent("exported.toml")
        XCTAssertTrue(store.exportConfig(to: exported))
        let text = try String(contentsOf: exported, encoding: .utf8)
        XCTAssertFalse(text.contains("v9.9.9"))

        let target = ConfigPresetStore(
            directory: root.appendingPathComponent("other-presets").path,
            configPath: root.appendingPathComponent("other-config.toml").path
        )
        XCTAssertTrue(target.importConfig(from: exported))
        let imported = ConfigLoader.load(from: target.configPath, silentMode: true).values.gridConfig
        XCTAssertEqual(imported.cols, 7)
        XCTAssertEqual(imported.appFont.installedVersion, "")
        XCTAssertEqual(imported.appFont.lastCheck, 0)
    }

    func testImportRejectsUnparsableFileWithoutTouchingConfig() throws {
        var config = GridConfig.default
        config.cols = 4
        ConfigLoader.save(config, to: store.configPath)

        let broken = root.appendingPathComponent("broken.toml")
        try "this is not = = toml [".write(to: broken, atomically: true, encoding: .utf8)

        XCTAssertFalse(store.importConfig(from: broken))
        XCTAssertEqual(ConfigLoader.load(from: store.configPath, silentMode: true).values.gridConfig.cols, 4)
    }

    func testDeletingTheActivePresetClearsThePointerButKeepsTheConfig() throws {
        XCTAssertTrue(store.create("work", from: .defaults))
        XCTAssertTrue(store.apply("work"))
        XCTAssertTrue(store.delete("work"))
        XCTAssertNil(store.activeName)
        XCTAssertEqual(store.names(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.configPath))
    }
}
