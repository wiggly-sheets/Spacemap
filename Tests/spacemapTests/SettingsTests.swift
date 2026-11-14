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

    func testSettingsViewAcceptsInjectedYabaiServiceAndExactConfigValues() {
        var config = GridConfig.default
        config.socketHealthInterval = 37
        config.backgroundAlpha = 0.37
        config.iconScale = 0.43
        config.uiScale = 0.61

        _ = SettingsView(yabaiService: MockYabaiService(), config: config)
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

        AppConfig.silentMode = true
        defer { AppConfig.silentMode = false }

        var disk = GridConfig.default
        disk.refuseUntrustedYabai = true
        disk.appFont.installedVersion = "v9.9.9"
        disk.appFont.lastCheck = 1_234_567
        AppConfig.saveConfig(disk, to: savedPath)

        let ui = Self.fullNonDefaultConfig()
        XCTAssertTrue(ConfigLoader.update(at: savedPath, silentMode: true) { stored in
            SettingsView.applySave(ui, to: &stored, appFontUpdateMode: .auto)
        })
        let reloaded = AppConfig.load(from: savedPath)

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
        var config = GridConfig.default
        config.spaceNameProfiles = [
            SpaceNameProfile(name: "Work", spaceNames: [1: "Code"]),
            SpaceNameProfile(name: "Play", spaceNames: [2: "Games"]),
        ]
        config.activeSpaceNameProfileIndex = 1

        let seed = SettingsView.profileStateToSeed(from: config)
        XCTAssertEqual(seed?.index, 1)
        XCTAssertEqual(seed?.spaceNames, [2: "Games"])

        config.activeSpaceNameProfileIndex = 9
        XCTAssertNil(SettingsView.profileStateToSeed(from: config))
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

    func testPendingSpaceNameEditFlushesIntoTheProfileActiveWhenItWasQueued() {
        var profiles = [
            SpaceNameProfile(name: "Work", spaceNames: [1: "One"]),
            SpaceNameProfile(name: "Play", spaceNames: [2: "Two"]),
        ]
        let pending = SpaceNamePendingEdit()
        pending.setApply {
            SettingsSpaceNames.syncActiveProfile(
                names: [1: "Edited"],
                into: &profiles,
                activeIndex: 0
            )
        }

        XCTAssertTrue(pending.flushApply())
        XCTAssertEqual(profiles[0].spaceNames, [1: "Edited"])
        XCTAssertEqual(profiles[1].spaceNames, [2: "Two"])
        XCTAssertFalse(pending.flushApply(), "a flushed edit must run only once")
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

    /// Every `GridConfig` field deliberately off its default so the save
    /// round-trip cannot pass by only exercising a subset.
    private static func fullNonDefaultConfig() -> GridConfig {
        var strip = GlyphStripConfig.default
        strip.enabled = true
        strip.theme = "nord"
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
        strip.shape = .pill
        strip.backgroundOpacity = 0.6
        strip.glassClearOpacity = 0.2
        strip.glassRegularOpacity = 0.4
        strip.glassTintedOpacity = 0.8
        strip.solidOpacity = 0.9
        strip.matchBackgroundOpacity = true
        strip.cornerRadius = 12
        strip.margin = 9
        strip.yOffset = 3.5
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
        strip.xOffset = 300
        strip.borderEnabled = false

        var config = GridConfig.default
        config.cols = 5
        config.rows = 3
        config.cellStyle = .hybrid
        config.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: [.maskCommand])
        config.pinnedHotkey = HotkeyConfig(key: .keyCode(122), modifiers: [.maskControl])
        config.glyphStripHotkey = HotkeyConfig(key: .keyCode(114), modifiers: [.maskAlternate])
        config.socketHealthInterval = 45
        config.uiScale = 0.7
        config.autoHideTimeout = 12
        config.theme = "nord"
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
        config.hideMenuBarIcon = true
        config.glyphStrip = strip
        config.menuBarDisplayMode = .nearby
        config.menuBarNearbyCount = 7
        config.spaceNames = [1: "Code", 2: "Web"]
        config.useVimKeys = true
        config.useArrowKeys = true
        config.useExtendedKeys = false
        config.jumpToSpaceEnabled = true
        config.hudPosition = .custom(x: 0.25, y: 0.75)
        config.customHUDX = 0.25
        config.customHUDY = 0.75
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

    private static func normalizingProfileIDs(_ config: GridConfig) -> GridConfig {
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
        let service = SettingsService(yabaiService: MockYabaiService(), checkForUpdates: {})

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
