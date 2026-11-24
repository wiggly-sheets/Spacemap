import XCTest
@testable import spacemap

final class ConfigSchemaHUDKeysTests: ConfigSchemaTestCase {
    func testHUDKeysRoundTripAndDefaultWhenMissing() throws {
        var config = SpacemapConfig.default
        var keys = HUDKeyBindings.default
        keys[.left] = [HotkeyConfig(key: .keyCode(7), modifiers: [])]
        config.hudKeys = keys

        let reread = try decoded(written(config)).config

        XCTAssertEqual(reread.hudKeys, keys)

        let (defaults, needsRepair) = try decoded("[grid]\n")

        XCTAssertEqual(defaults.hudKeys, HUDKeyBindings.default, "old configs without the table load with vim and arrow keys")
        XCTAssertTrue(needsRepair, "the missing table should flag repair so the file is rewritten, like its siblings")
    }

    func testNewHUDCommandsAreWrittenAndRoundTrip() throws {
        var config = SpacemapConfig.default
        var keys = HUDKeyBindings.default
        keys[.moveSpaceBack] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+f13"))]
        keys[.moveSpaceForward] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+f14"))]
        keys[.cycleLayout] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+f15"))]
        config.hudKeys = keys

        let toml = written(config)

        XCTAssertTrue(toml.contains("moveSpaceBack = [\"ctrl+"))
        XCTAssertTrue(toml.contains("moveSpaceForward = [\"ctrl+"))
        XCTAssertTrue(toml.contains("cycleLayout = [\"ctrl+"))

        let reread = try decoded(toml).config
        XCTAssertEqual(reread.hudKeys[.moveSpaceBack], keys[.moveSpaceBack])
        XCTAssertEqual(reread.hudKeys[.moveSpaceForward], keys[.moveSpaceForward])
        XCTAssertEqual(reread.hudKeys[.cycleLayout], keys[.cycleLayout])
    }

    func testDefaultHUDKeyTableWritesTheNewCommandsUnbound() {
        let toml = written(SpacemapConfig.default)

        XCTAssertTrue(toml.contains("moveSpaceBack = []"),
                      "a fresh file names the new commands with empty bindings")
        XCTAssertTrue(toml.contains("moveSpaceForward = []"))
        XCTAssertTrue(toml.contains("cycleLayout = []"))
    }

    /// A config file written before these action names existed still loads:
    /// unknown actions are skipped and the rest of the table is kept.
    func testOlderHUDFilesWithoutNewActionsLoadWithThemUnbound() throws {
        let toml = written(SpacemapConfig.default)
            .replacingOccurrences(of: "moveSpaceBack = []\n", with: "")
            .replacingOccurrences(of: "moveSpaceForward = []\n", with: "")
            .replacingOccurrences(of: "cycleLayout = []\n", with: "")

        let reread = try decoded(toml).config

        XCTAssertEqual(reread.hudKeys[.moveSpaceBack], [])
        XCTAssertEqual(reread.hudKeys[.moveSpaceForward], [])
        XCTAssertEqual(reread.hudKeys[.cycleLayout], [])
    }

    /// An action name the app does not know is ignored, and the file is not
    /// marked for repair, so a file from a newer build still loads.
    func testUnknownHUDActionIsIgnoredWithoutRepair() throws {
        let toml = written(SpacemapConfig.default)
            .replacingOccurrences(of: "layoutFloat = [\"u\"]\n",
                                  with: "layoutFloat = [\"u\"]\nbogusAction = [\"ctrl+q\"]\n")

        let (config, needsRepair) = try decoded(toml)

        XCTAssertFalse(needsRepair)
        XCTAssertNil(config.hudKeys.command(for: 12, flags: .maskControl),
                     "the unknown action must not bind its key")
        XCTAssertEqual(config.hudKeys, HUDKeyBindings.default,
                       "the rest of the table still decodes")
    }

    func testHotkeyTableWithoutModifiersFallsBackToDefaultAndFlagsRepair() throws {
        let full = written(SpacemapConfig.default)
        let (config, needsRepair) = try decoded(
            full.replacingOccurrences(of: "modifiers = [\"ctrl\"]\n", with: "")
        )

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.hotkey, SpacemapConfig.default.hotkey)
    }

    func testInvalidCustomHUDPositionFallsBackToCenterAndFlagsRepair() throws {
        // Full default file, so the repair flag can only come from the broken
        // block swapped in below.
        let full = written(SpacemapConfig.default)
        let brokenBlock = """
        [behavior.hudPosition]
        kind = "custom"
        x = 2.0
        y = 0.75
        """
        let toml = full.replacingOccurrences(
            of: "[behavior.hudPosition]\nkind = \"center\"", with: brokenBlock
        )
        XCTAssertNotEqual(toml, full, "the default writer output must carry a hudPosition block to swap")

        let (config, needsRepair) = try decoded(toml)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.hudPosition, SpacemapConfig.default.hudPosition)
    }

    /// The screen identity rides in the same table as the fractions, so a
    /// custom position restores on the display it was dragged on.
    func testCustomHUDPositionScreenIdentityRoundTripsAndIsOptional() throws {
        var config = SpacemapConfig.default
        config.hudPosition = .custom(x: 0.4, y: 0.6, screen: "UUID-A")

        let (reread, needsRepair) = try decoded(written(config))

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reread.hudPosition, .custom(x: 0.4, y: 0.6, screen: "UUID-A"))

        // No display pairing: the key stays out of the file and decodes as nil.
        config.hudPosition = .custom(x: 0.4, y: 0.6, screen: nil)
        let (unpaired, unpairedRepair) = try decoded(written(config))
        XCTAssertFalse(unpairedRepair)
        XCTAssertEqual(unpaired.hudPosition, .custom(x: 0.4, y: 0.6, screen: nil))
        XCTAssertFalse(written(config).contains("\nscreen ="), "no screen key without an identity")
    }

    /// The scalar `customHUDX`/`customHUDY` keys died with the one-scheme
    /// change: a config that still has them loads clean and drops them on the
    /// next save (ADR 0001, no migration).
    func testLegacyCustomHUDKeysAreIgnored() throws {
        let full = written(SpacemapConfig.default)
        let toml = full.replacingOccurrences(
            of: "jumpToSpaceEnabled = false\n",
            with: "jumpToSpaceEnabled = false\ncustomHUDX = 0.9\ncustomHUDY = 0.1\n"
        )
        XCTAssertNotEqual(toml, full)

        let (config, needsRepair) = try decoded(toml)

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.hudPosition, SpacemapConfig.default.hudPosition)
        XCTAssertFalse(written(config).contains("customHUDX"))
    }

    /// The strip's old `xOffset`/`yOffset` keys are gone with the same fraction
    /// scheme: a config that still has them loads clean at the default custom
    /// fractions and drops them on the next save (ADR 0001, no migration).
    func testDisabledHUDKeyReencodesAsAnEmptyList() throws {
        var config = SpacemapConfig.default
        var keys = HUDKeyBindings.default
        keys[.left] = [HotkeyConfig(key: .none, modifiers: [])]
        config.hudKeys = keys

        let toml = written(config)
        XCTAssertTrue(toml.contains("left = []"))

        let reread = try decoded(toml).config
        XCTAssertEqual(reread.hudKeys[.left].isEmpty, true)
    }

}
