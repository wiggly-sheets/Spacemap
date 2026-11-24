import XCTest
import AppKit
@testable import spacemap

final class SpaceNameProfileTests: SettingsTestCase {
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
}
