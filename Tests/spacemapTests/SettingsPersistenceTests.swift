import XCTest
import AppKit
@testable import spacemap

final class SettingsPersistenceTests: SettingsTestCase {
    func testSettingsSavePreservesDiskOwnedFieldsAndRoundTripsEveryField() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-settings-save-\(UUID().uuidString)")
        let savedPath = directory.appendingPathComponent("saved.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var disk = SpacemapConfig.default
        disk.refuseUntrustedYabai = true
        disk.appFont.installedVersion = "v9.9.9"
        disk.appFont.lastCheck = 1_234_567
        ConfigStore.saveConfig(disk, to: savedPath)

        let ui = Self.fullNonDefaultConfig()
        XCTAssertTrue(ConfigLoader.update(at: savedPath, silentMode: true) { stored in
            SettingsDraft.applySave(ui, to: &stored)
        })
        let reloaded = ConfigStore.load(from: savedPath)

        var expected = ui
        expected.appFont = AppFontConfig(
            updateMode: .auto,
            installedVersion: "v9.9.9",
            lastCheck: 1_234_567
        )
        expected.refuseUntrustedYabai = true

        XCTAssertTrue(reloaded.refuseUntrustedYabai, "trust refusal must survive a settings save")
        XCTAssertEqual(reloaded.appFont.installedVersion, "v9.9.9")
        XCTAssertEqual(reloaded.appFont.lastCheck, 1_234_567)
        XCTAssertEqual(reloaded.appFont.updateMode, .auto)
        XCTAssertEqual(
            Self.normalizingProfileIDs(reloaded),
            Self.normalizingProfileIDs(expected),
            "a settings save must preserve disk-owned fields without dropping UI fields"
        )
    }

    /// Settings saves the folded key map and writes the legacy scalars
    /// unbound, so the command must stay bound through the table alone.
    func testFoldedLegacyBindingSurvivesASettingsSaveThroughTheTableAlone() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-settings-fold-\(UUID().uuidString)")
        let savedPath = directory.appendingPathComponent("saved.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var config = SpacemapConfig.default
        config.hudNewSpaceHotkey = try XCTUnwrap(Hotkey.parseHotkey("x"))
        config.hudKeys[.newSpace] = [try XCTUnwrap(Hotkey.parseHotkey("y"))]
        config.hudKeys = config.hudKeyBindings.foldingLegacy()
        config.hudNewSpaceHotkey = HotkeyConfig(key: .none, modifiers: [])

        ConfigStore.saveConfig(config, to: savedPath)
        let reloaded = ConfigStore.load(from: savedPath)

        XCTAssertTrue(reloaded.hudNewSpaceHotkey.isDisabled, "the scalar key is written unbound")
        XCTAssertEqual(reloaded.hudKeyBindings.command(for: 7, flags: []), .newSpace)
        XCTAssertEqual(reloaded.hudKeyBindings.command(for: 16, flags: []), .newSpace)
    }

    func testConfigSaveFailureReturnsASurfacedMessage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-settings-save-failure-\(UUID().uuidString)")
        let target = directory.appendingPathComponent("target.toml").path
        let link = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "original".write(toFile: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

        let saved = ConfigLoader.update(at: link, silentMode: true) { config in
            config.cols = 9
        }

        XCTAssertFalse(saved)
        XCTAssertEqual(SettingsView.saveResultMessage(saved), SettingsView.saveFailureMessage)
        XCTAssertNil(SettingsView.saveResultMessage(true))
    }

    func testAControlBindingWritesTheDraftAndTheSavePersistsIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-draft-binding-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        let draft = makeDraft(SpacemapConfig.default, at: path, debounce: 5)

        draft.binding(\.glassStyle).wrappedValue = .tinted
        draft.binding(\.glassRegularOpacity).wrappedValue = 0.62
        draft.flush()

        let reloaded = ConfigStore.load(from: path)
        XCTAssertEqual(reloaded.glassStyle, .tinted)
        XCTAssertEqual(reloaded.glassRegularOpacity, 0.62)
        XCTAssertNil(draft.saveErrorMessage)
    }

    func testRapidEditsCoalesceIntoOneDebouncedSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-draft-debounce-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        let saved = expectation(description: "one debounced save")
        let counter = SaveCounter()
        let draft = makeDraft(SpacemapConfig.default, at: path, debounce: 0.05, into: counter) {
            saved.fulfill()
        }

        draft.binding(\.cols).wrappedValue = 5
        draft.binding(\.cols).wrappedValue = 6
        draft.binding(\.rows).wrappedValue = 4

        wait(for: [saved], timeout: 2)
        XCTAssertEqual(counter.configs.count, 1, "a burst of edits is one write")
        XCTAssertEqual(counter.configs.last?.cols, 6)
        XCTAssertEqual(counter.configs.last?.rows, 4)
    }

    /// A preset apply or import replaces config.toml under an open window. The
    /// edit in flight belongs to the replaced config and must not land on it.
    func testReplacedConfigReloadsTheDraftAndDropsThePendingWrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-draft-preset-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var seeded = SpacemapConfig.default
        seeded.cols = 3
        let counter = SaveCounter()
        let draft = makeDraft(seeded, at: path, debounce: 5, into: counter)

        draft.binding(\.cols).wrappedValue = 9

        var replacement = SpacemapConfig.default
        replacement.cols = 7
        replacement.theme = "preset-theme"
        ConfigStore.saveConfig(replacement, to: path)
        NotificationCenter.default.post(name: .configReplacedExternally, object: nil)

        XCTAssertEqual(draft.config.cols, 7)
        XCTAssertEqual(draft.config.theme, "preset-theme")

        draft.flush()
        XCTAssertEqual(counter.configs.count, 0, "the replaced config is never overwritten by an older edit")
        XCTAssertEqual(ConfigStore.load(from: path).cols, 7)
    }

    /// Another writer moves the HUD or the strip under an open pane. The draft
    /// adopts the value, so a later save here cannot revert it.
    func testAnExternalPositionChangeIsAdoptedAndSurvivesTheNextSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-draft-position-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var seeded = SpacemapConfig.default
        seeded.hudPosition = .center
        seeded.glyphStrip.customX = 0.5
        let draft = makeDraft(seeded, at: path, debounce: 5)

        let moved = HUDPosition.custom(x: 0.2, y: 0.8, screen: "display-B")
        ConfigLoader.update(at: path, silentMode: true) { config in
            config.hudPosition = moved
            config.glyphStrip.customX = 0.7
        }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)

        XCTAssertEqual(draft.config.hudPosition, moved)
        XCTAssertEqual(draft.config.glyphStrip.customX, 0.7)

        draft.binding(\.autoHideTimeout).wrappedValue = 9
        draft.flush()

        let reloaded = ConfigStore.load(from: path)
        XCTAssertEqual(reloaded.hudPosition, moved, "the next save keeps the moved HUD")
        XCTAssertEqual(reloaded.glyphStrip.customX, 0.7, "the next save keeps the moved strip")
        XCTAssertEqual(reloaded.autoHideTimeout, 9)
    }

    /// A picker change still inside the debounce window owns the value. The
    /// external move must not be adopted, or the queued save would write it.
    func testAPendingPickerChangeIsNotRevertedByAnExternalPositionChange() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-draft-position-pending-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var seeded = SpacemapConfig.default
        seeded.hudPosition = .center
        seeded.glyphStrip.customX = 0.5
        let draft = makeDraft(seeded, at: path, debounce: 5)

        draft.hudPositionKind = .top

        ConfigLoader.update(at: path, silentMode: true) { config in
            config.hudPosition = .bottom
            config.glyphStrip.customX = 0.9
        }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)

        XCTAssertEqual(draft.config.hudPosition, .top, "the unsaved picker choice survives the external move")
        XCTAssertEqual(draft.config.glyphStrip.customX, 0.5)

        draft.flush()

        let reloaded = ConfigStore.load(from: path)
        XCTAssertEqual(reloaded.hudPosition, .top, "the queued save writes the picker choice")
        XCTAssertEqual(reloaded.glyphStrip.customX, 0.5, "and keeps the draft's strip placement")
    }

    /// The legacy `[behavior]` scalars fold into the key map on seed and are
    /// written back unbound, so the command stays bound through the table.
}
