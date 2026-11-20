import XCTest
import AppKit
@testable import spacemap

final class SettingsTests: XCTestCase {
    func testHotkeyRecordingStateGuardsRepeatedStartsAndRestoresOriginalOnCancel() {
        var state = HotkeyRecordingState()

        XCTAssertTrue(state.begin(currentHotkey: "ctrl+space"))
        XCTAssertTrue(state.isRecording)
        XCTAssertFalse(state.begin(currentHotkey: "cmd+space"))
        XCTAssertEqual(state.cancel(), "ctrl+space")
        XCTAssertFalse(state.isRecording)
        XCTAssertNil(state.cancel())
    }

    func testHotkeyRecordingStateCompletionDoesNotRestoreOriginal() {
        var state = HotkeyRecordingState()

        XCTAssertTrue(state.begin(currentHotkey: "ctrl+space"))
        state.complete()

        XCTAssertFalse(state.isRecording)
        XCTAssertNil(state.cancel())
    }

    func testHotkeyRecorderCoordinatorCancelsPreviousRecorderBeforeActivatingAnother() {
        let coordinator = HotkeyRecorderCoordinator()
        let first = UUID()
        let second = UUID()
        var cancellations: [UUID] = []

        coordinator.activate(recorderID: first) { cancellations.append(first) }
        coordinator.activate(recorderID: second) { cancellations.append(second) }

        XCTAssertEqual(cancellations, [first])
        XCTAssertEqual(coordinator.activeRecorderID, second)
        coordinator.deactivate(recorderID: first)
        XCTAssertEqual(coordinator.activeRecorderID, second)
        coordinator.deactivate(recorderID: second)
        XCTAssertNil(coordinator.activeRecorderID)
    }

    func testRecorderCoordinatorTogglesMediaKeySuppressionFlag() {
        defer { HotkeyTapRouter.isRecording = false }
        let coordinator = HotkeyRecorderCoordinator()
        let first = UUID()
        let second = UUID()

        XCTAssertFalse(HotkeyTapRouter.isRecording)
        coordinator.activate(recorderID: first) {}
        XCTAssertTrue(HotkeyTapRouter.isRecording)

        // Switching recorders keeps suppression on; the replaced recorder's
        // late deactivate must not clear it for the active one.
        coordinator.activate(recorderID: second) {}
        XCTAssertTrue(HotkeyTapRouter.isRecording)
        coordinator.deactivate(recorderID: first)
        XCTAssertTrue(HotkeyTapRouter.isRecording)

        coordinator.deactivate(recorderID: second)
        XCTAssertFalse(HotkeyTapRouter.isRecording)
    }

    func testDiscardedRecorderCoordinatorClearsMediaKeySuppression() {
        defer { HotkeyTapRouter.isRecording = false }
        var coordinator: HotkeyRecorderCoordinator? = HotkeyRecorderCoordinator()

        coordinator?.activate(recorderID: UUID()) {}
        XCTAssertTrue(HotkeyTapRouter.isRecording)

        coordinator = nil
        XCTAssertFalse(HotkeyTapRouter.isRecording)
    }

    func testOnlyBareEscapeCancelsHotkeyRecording() throws {
        let bareEscape = try XCTUnwrap(Self.keyEvent(keyCode: 53, modifiers: []))
        let optionEscape = try XCTUnwrap(Self.keyEvent(keyCode: 53, modifiers: .option))

        XCTAssertTrue(HotkeyRecorder.isCancelKey(bareEscape))
        XCTAssertFalse(HotkeyRecorder.isCancelKey(optionEscape))
    }

    func testHotkeyKeycapsSplitModifiersFromTheKey() {
        XCTAssertEqual(HotkeyRecorder.keycaps(for: "ctrl+cmd+space"), ["⌃", "⌘", "Space"])
        XCTAssertEqual(HotkeyRecorder.keycaps(for: "hyper+f5"), ["⌃", "⌘", "⌥", "⇧", "F5"])
        XCTAssertEqual(HotkeyRecorder.keycaps(for: "none"), [])
        XCTAssertEqual(HotkeyRecorder.keycaps(for: ""), [])
        XCTAssertEqual(HotkeyRecorder.keycaps(for: "a"), ["A"])
    }

    func testDuplicateHotkeyDetectionTreatsFunctionKeyFnModifierAsTheSameBinding() {
        XCTAssertTrue(SettingsBehavior.matches("f1", "fn+f1"))
        XCTAssertTrue(SettingsBehavior.matches("ctrl+f2", "fn+ctrl+f2"))
        XCTAssertFalse(SettingsBehavior.matches("f1", "f2"))
        XCTAssertFalse(SettingsBehavior.matches("f1", "ctrl+f1"))
    }

    func testAppearanceStepsIncludeArbitraryValidCurrentValue() {
        XCTAssertEqual(
            SettingsAppearanceView.steps([0, 0.5, 1], including: 0.37),
            [0, 0.37, 0.5, 1]
        )
    }

    func testSocketHealthOptionsIncludeArbitraryValidCurrentValue() {
        XCTAssertEqual(
            SettingsAdvanced.socketHealthOptions(including: 37),
            [15, 30, 37, 45, 60]
        )
    }

    func testGridLayoutOptionsPreserveArbitraryValidGeometry() {
        let options = SettingsGrid.layoutOptions(
            maxSpaces: 10,
            currentCols: 3,
            currentRows: 4
        )
        let index = SettingsGrid.layoutIndex(
            maxSpaces: 10,
            currentCols: 3,
            currentRows: 4
        )

        XCTAssertEqual(options[index].cols, 3)
        XCTAssertEqual(options[index].rows, 4)
        XCTAssertEqual(options[index].label, "3×4 (Custom)")
    }

    func testSwitchingToThumbnailsAsksForScreenRecordingOnlyWhenItIsMissing() {
        XCTAssertTrue(SystemPermissions.needsScreenRecordingRequest(hasPermission: false))
        XCTAssertFalse(
            SystemPermissions.needsScreenRecordingRequest(hasPermission: true),
            "a granted permission must not prompt or open System Settings"
        )
    }

    func testEveryHUDCommandHasADistinctDisplayName() {
        let labels = HUDCommand.allCases.map(\.label)

        XCTAssertEqual(Set(labels).count, labels.count, "the HUD key picker needs one name per command")
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    func testSettingsViewAcceptsInjectedYabaiServiceAndExactConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-settings-view-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var config = SpacemapConfig.default
        config.socketHealthInterval = 37
        config.backgroundAlpha = 0.37
        config.iconScale = 0.43
        config.uiScale = 0.61

        _ = SettingsView(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore(),
            themeCatalog: ThemeCatalogService(themeStore: makeTemporaryThemeStore()),
            draft: makeDraft(config, at: path)
        )
    }

    func testSettingsWindowUsesStableFrameAutosaveName() {
        XCTAssertFalse(SettingsWindowController.frameAutosaveName.isEmpty)
    }

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

    func testMenuProfileChangeSeedsSettingsProfileState() {
        var config = SpacemapConfig.default
        config.spaceNameProfiles = [
            SpaceNameProfile(name: "Work", spaceNames: [1: "Code"]),
            SpaceNameProfile(name: "Play", spaceNames: [2: "Games"]),
        ]
        config.activeSpaceNameProfileIndex = 1

        let seed = SettingsDraft.profileStateToSeed(from: config)
        XCTAssertEqual(seed?.index, 1)
        XCTAssertEqual(seed?.spaceNames, [2: "Games"])

        config.activeSpaceNameProfileIndex = 9
        XCTAssertNil(SettingsDraft.profileStateToSeed(from: config))
    }

    func testActivatingProfileCopiesItsSpaceNames() {
        let work = SpaceNameProfile(name: "Work", spaceNames: [1: "Code", 2: "Web"])
        let play = SpaceNameProfile(name: "Play", spaceNames: [1: "Games"])

        XCTAssertEqual(
            SettingsSpaceNames.activatedNames(profiles: [work, play], index: 1),
            play.spaceNames
        )
        XCTAssertNil(SettingsSpaceNames.activatedNames(profiles: [work, play], index: 2))
    }

    func testDeletingAProfileShiftsTheActiveIndexForDeletionsBelowIt() {
        // Removing item 0 moves the active profile from 2 down to 1.
        XCTAssertEqual(
            SettingsSpaceNames.activeIndexAfterDeleting(0, activeIndex: 2, remainingCount: 3),
            1
        )
        // Removing the active item keeps the slot now occupied by the next one.
        XCTAssertEqual(
            SettingsSpaceNames.activeIndexAfterDeleting(1, activeIndex: 1, remainingCount: 3),
            1
        )
        // Removing the active last item falls back to the new last item.
        XCTAssertEqual(
            SettingsSpaceNames.activeIndexAfterDeleting(2, activeIndex: 2, remainingCount: 2),
            1
        )
        // Removing above the active item leaves it alone.
        XCTAssertEqual(
            SettingsSpaceNames.activeIndexAfterDeleting(1, activeIndex: 0, remainingCount: 2),
            0
        )
    }

    /// A menu-bar profile switch flushes a pending keystroke before the draft
    /// re-seeds, so the edit lands in the profile that was active when typed.
    func testFlushWritesSpaceNameEditsIntoTheProfileActiveAtTheTime() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-space-names-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var seeded = SpacemapConfig.default
        seeded.spaceNameProfiles = [
            SpaceNameProfile(name: "Work", spaceNames: [1: "One"]),
            SpaceNameProfile(name: "Play", spaceNames: [2: "Two"]),
        ]
        seeded.spaceNames = [1: "One"]
        let draft = makeDraft(seeded, at: path, debounce: 5)

        draft.binding(\.spaceNames).wrappedValue = [1: "Edited"]
        draft.flush()

        let reloaded = ConfigStore.load(from: path)
        XCTAssertEqual(reloaded.spaceNameProfiles[0].spaceNames, [1: "Edited"])
        XCTAssertEqual(reloaded.spaceNameProfiles[1].spaceNames, [2: "Two"], "the inactive profile stays untouched")
    }

    /// Auto naming is a display choice: switching modes must leave the typed
    /// names in the profile untouched so switching back restores them.
    func testSwitchingNamingModeNeverRewritesProfileNames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-naming-mode-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var seeded = SpacemapConfig.default
        seeded.spaceNameProfiles = [
            SpaceNameProfile(name: "Work", spaceNames: [1: "One"]),
            SpaceNameProfile(name: "Play", spaceNames: [2: "Two"]),
        ]
        seeded.spaceNames = [1: "One"]
        let draft = makeDraft(seeded, at: path, debounce: 5)

        draft.binding(\.namingMode).wrappedValue = .auto
        draft.flush()

        let reloaded = ConfigStore.load(from: path)
        XCTAssertEqual(reloaded.namingMode, .auto)
        XCTAssertEqual(reloaded.spaceNames, [1: "One"], "typed names stay saved")
        XCTAssertEqual(reloaded.spaceNameProfiles[0].spaceNames, [1: "One"])
        XCTAssertEqual(reloaded.spaceNameProfiles[1].spaceNames, [2: "Two"])
    }

    /// The Glass Style picker once lost its save attachment; a control write
    /// must reach the draft and the file.
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
    func testDraftSeedsLegacyHUDKeysIntoTheKeyMap() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-draft-legacy-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var config = SpacemapConfig.default
        config.hudNewSpaceHotkey = try XCTUnwrap(Hotkey.parseHotkey("x"))
        let draft = makeDraft(config, at: path, debounce: 5)

        XCTAssertEqual(draft.config.hudKeyBindings.command(for: 7, flags: []), .newSpace)

        draft.binding(\.autoHideTimeout).wrappedValue = 11
        draft.flush()

        let reloaded = ConfigStore.load(from: path)
        XCTAssertTrue(reloaded.hudNewSpaceHotkey.isDisabled, "the scalar key is written unbound")
        XCTAssertEqual(reloaded.hudKeyBindings.command(for: 7, flags: []), .newSpace)
        XCTAssertEqual(reloaded.autoHideTimeout, 11)
    }

    /// The menu bar writes the new index, then posts. A pending keystroke must
    /// land in the profile it was typed in without reverting that index.
    func testAProfileSwitchKeepsTheMenuBarIndexAndThePendingEdit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-draft-profile-switch-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        var seeded = SpacemapConfig.default
        seeded.spaceNameProfiles = [
            SpaceNameProfile(name: "Work", spaceNames: [1: "One"]),
            SpaceNameProfile(name: "Play", spaceNames: [2: "Two"]),
        ]
        seeded.spaceNames = [1: "One"]
        let draft = makeDraft(seeded, at: path, debounce: 5)

        draft.binding(\.spaceNames).wrappedValue = [1: "Edited"]

        // What the menu bar does: switch the active profile on disk, then post.
        ConfigLoader.update(at: path, silentMode: true) { config in
            config.activeSpaceNameProfileIndex = 1
            config.spaceNames = config.spaceNameProfiles[1].spaceNames
        }
        NotificationCenter.default.post(name: .spaceNameProfileChanged, object: nil)

        XCTAssertEqual(draft.config.activeSpaceNameProfileIndex, 1)
        XCTAssertEqual(draft.config.spaceNames, [2: "Two"])

        draft.flush()

        let reloaded = ConfigStore.load(from: path)
        XCTAssertEqual(reloaded.activeSpaceNameProfileIndex, 1, "the menu-bar switch is not reverted")
        XCTAssertEqual(reloaded.spaceNames, [2: "Two"])
        XCTAssertEqual(reloaded.spaceNameProfiles[0].spaceNames, [1: "Edited"], "the queued edit stays in its profile")
    }

    func testEditingVisibleSpaceNamesWritesThemIntoTheActiveProfile() {
        var profiles = [
            SpaceNameProfile(name: "Work", spaceNames: [1: "One"]),
            SpaceNameProfile(name: "Play", spaceNames: [2: "Two"]),
        ]
        let edited = [1: "Edited", 3: "Third"]

        SettingsSpaceNames.syncActiveProfile(
            names: edited,
            into: &profiles,
            activeIndex: 1
        )

        XCTAssertEqual(profiles[1].spaceNames, edited)
        XCTAssertEqual(profiles[0].spaceNames, [1: "One"], "inactive profiles stay untouched")
    }

    /// Draft over a temp config file, so saves land somewhere disposable.
    private func makeDraft(
        _ config: SpacemapConfig,
        at path: String,
        debounce: TimeInterval = SettingsDraft.saveDebounce,
        into counter: SaveCounter? = nil,
        onSave: @escaping () -> Void = {}
    ) -> SettingsDraft {
        ConfigStore.saveConfig(config, to: path)
        let draft = SettingsDraft(
            config: ConfigStore.load(from: path),
            debounce: debounce,
            load: { ConfigStore.load(from: path) },
            save: { saved in
                counter?.configs.append(saved)
                onSave()
                return ConfigLoader.update(at: path, silentMode: true) { disk in
                    SettingsDraft.applySave(saved, to: &disk)
                }
            }
        )
        return draft
    }

    private final class SaveCounter {
        var configs: [SpacemapConfig] = []
    }

    /// Every `SpacemapConfig` field deliberately off its default so the save
    /// round-trip cannot pass by only exercising a subset.
    private static func fullNonDefaultConfig() -> SpacemapConfig {
        var strip = GlyphStripConfig.default
        strip.enabled = true
        strip.theme = "default"
        strip.showSpaceNumbers = false
        strip.showLayoutSuffix = false
        strip.showAppIcons = false
        strip.iconSource = .nativeIcons
        strip.dedupeAppsPerSpace = false
        strip.maxIconsPerSpace = 3
        strip.iconSize = 14
        strip.indexSize = 9
        strip.highlightCurrentSpace = false
        strip.backgroundMaterial = .liquidGlass
        strip.glassStyle = .tinted
        strip.matchHUDAppearance = true
        strip.backgroundOpacity = 0.6
        strip.glassClearOpacity = 0.2
        strip.glassRegularOpacity = 0.4
        strip.glassTintedOpacity = 0.8
        strip.solidOpacity = 0.9
        strip.matchBackgroundOpacity = true
        strip.cornerRadius = 12
        strip.margin = 9
        strip.hoverPadding = 2.5
        strip.hoverCornerRadius = 7.5
        strip.iconSpacing = 3.5
        strip.indexPadding = 2.5
        strip.showDisplaySeparators = false
        strip.showAddSpaceButton = false
        strip.showPlaceholders = false
        strip.leftClickAction = .floatWindow
        strip.rightClickAction = .mergeWindows
        strip.middleClickAction = .balanceWindows
        strip.position = .custom
        strip.customX = 0.3
        strip.customY = 0.6
        strip.customScreen = "display-A"
        strip.borderEnabled = false

        var config = SpacemapConfig.default
        config.cols = 5
        config.rows = 3
        config.cellStyle = .hybrid
        config.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: [.maskCommand])
        config.pinnedHotkey = HotkeyConfig(key: .keyCode(122), modifiers: [.maskControl])
        config.glyphStripHotkey = HotkeyConfig(key: .keyCode(114), modifiers: [.maskAlternate])
        config.socketHealthInterval = 45
        config.uiScale = 0.7
        config.autoHideTimeout = 12
        config.theme = "default"
        config.showMode = .active
        config.multiMonitorHUDMode = .separate
        config.unifiedHUDVisibility = .all
        config.separateHUDVisibility = .active
        config.displayNavigationWrap = .between
        config.maxSpaces = 15
        config.backgroundAlpha = 0.55
        config.backgroundStyle = .solid
        config.glassStyle = .tinted
        config.glassClearOpacity = 0.2
        config.glassRegularOpacity = 0.4
        config.glassTintedOpacity = 0.6
        config.solidOpacity = 0.8
        config.matchBackgroundOpacity = true
        config.hudShadow = false
        config.mode = .dark
        config.iconScale = 0.6
        config.showSpaceNumbers = false
        config.showSpaceLayout = true
        config.showSpaceNames = false
        config.showIconStrip = false
        config.showMultiAppIcons = true
        config.presence = AppPresence.none
        config.glyphStrip = strip
        config.menuBarDisplayMode = .nearby
        config.menuBarNearbyCount = 7
        config.spaceNames = [1: "Code", 2: "Web"]
        var hudKeys = HUDKeyBindings.default
        hudKeys[.left] = [HotkeyConfig(key: .keyCode(7), modifiers: [])]
        config.hudKeys = hudKeys
        config.jumpToSpaceEnabled = true
        config.hudPosition = .custom(x: 0.25, y: 0.75, screen: "display-A")
        config.showExtraWindows = true
        config.focusSpaceOnWindowDrop = .modifier
        config.focusSpaceOnWindowDropModifier = .option
        config.showHUDOnSpaceChange = true
        config.updateMode = .auto
        config.spaceNameProfiles = [
            SpaceNameProfile(name: "Work", spaceNames: [1: "Code"]),
            SpaceNameProfile(name: "Play", spaceNames: [2: "Web"]),
        ]
        config.activeSpaceNameProfileIndex = 1
        return config
    }

    private static func normalizingProfileIDs(_ config: SpacemapConfig) -> SpacemapConfig {
        var normalized = config
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        normalized.spaceNameProfiles = normalized.spaceNameProfiles.map { profile in
            var copy = profile
            copy.id = id
            return copy
        }
        return normalized
    }

    func testAboutWindowIsReusedAcrossRepeatedShowRequests() throws {
        _ = NSApplication.shared
        let themeStore = makeTemporaryThemeStore()
        let service = SettingsService(
            yabaiService: MockYabaiService(),
            themeStore: themeStore,
            themeCatalog: ThemeCatalogService(themeStore: themeStore),
            checkForUpdates: {}
        )

        service.showAboutWindow()
        let first = try XCTUnwrap(service.aboutWindowController)
        service.showAboutWindow()

        let second = try XCTUnwrap(service.aboutWindowController)
        XCTAssertTrue(first === second)
        first.close()
    }

    private static func keyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
