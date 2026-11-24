import XCTest
@testable import spacemap

final class ConfigSchemaGlyphStripTests: ConfigSchemaTestCase {
    func testGlyphStripNumbersClampAndFlagRepair() throws {
        XCTAssertFalse(try decoded(written(SpacemapConfig.default)).needsRepair,
                       "a valid strip must not request repair")

        let toml = written(SpacemapConfig.default)
            .replacingOccurrences(of: "maxIconsPerSpace = 8", with: "maxIconsPerSpace = -1")
            .replacingOccurrences(of: "iconSize = 11", with: "iconSize = 100")
            .replacingOccurrences(of: "backgroundOpacity = 0.35", with: "backgroundOpacity = -2")
        let (config, needsRepair) = try decoded(toml)

        XCTAssertTrue(needsRepair, "out-of-range strip values must request repair")
        XCTAssertEqual(config.glyphStrip.iconSize, 24)
        XCTAssertEqual(config.glyphStrip.backgroundOpacity, 0.01)
        XCTAssertEqual(config.glyphStrip.maxIconsPerSpace, 0)
    }

    func testGlyphStripHotkeyRoundTripsThroughTheConfigString() throws {
        var config = SpacemapConfig.default
        config.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: [.maskCommand, .maskShift])
        config.hudMoveSpaceBackHotkey = HotkeyConfig(key: .keyCode(101), modifiers: [.maskCommand, .maskShift])
        config.hudMoveSpaceForwardHotkey = HotkeyConfig(key: .keyCode(102), modifiers: [.maskCommand, .maskShift])
        config.hudNewSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])
        config.hudDeleteSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])
        config.hudCycleLayoutHotkey = HotkeyConfig(key: .none, modifiers: [])

        let reread = try decoded(written(config)).config

        XCTAssertEqual(reread.glyphStripHotkey, config.glyphStripHotkey)
    }

    func testLegacyGlyphStripOffsetsAreIgnored() throws {
        let full = written(SpacemapConfig.default)
        let toml = full.replacingOccurrences(
            of: "[glyphStrip]\n",
            with: "[glyphStrip]\nxOffset = 120\nyOffset = -18.5\n"
        )
        XCTAssertNotEqual(toml, full)

        let (config, needsRepair) = try decoded(toml)

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.glyphStrip.customX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(config.glyphStrip.customY, 0.5, accuracy: 0.0001)
        XCTAssertFalse(written(config).contains("xOffset"))
    }


    /// Free strip placement uses the same fraction-plus-screen scheme as the
    /// HUD; out-of-range fractions clamp and flag a rewrite.
    func testGlyphStripCustomPlacementRoundTripsAndClamps() throws {
        var config = SpacemapConfig.default
        config.glyphStrip.position = .custom
        config.glyphStrip.customX = 0.25
        config.glyphStrip.customY = 0.75
        config.glyphStrip.customScreen = "UUID-A"

        let (reread, needsRepair) = try decoded(written(config))
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reread.glyphStrip.customX, 0.25, accuracy: 0.001)
        XCTAssertEqual(reread.glyphStrip.customY, 0.75, accuracy: 0.001)
        XCTAssertEqual(reread.glyphStrip.customScreen, "UUID-A")

        let clampedToml = written(config)
            .replacingOccurrences(of: "customX = 0.25", with: "customX = 4.0")
            .replacingOccurrences(of: "customY = 0.75", with: "customY = -1.0")
        let (clamped, clampedRepair) = try decoded(clampedToml)
        XCTAssertTrue(clampedRepair)
        XCTAssertEqual(clamped.glyphStrip.customX, 1)
        XCTAssertEqual(clamped.glyphStrip.customY, 0)
    }

}
