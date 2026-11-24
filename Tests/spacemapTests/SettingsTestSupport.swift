import XCTest
import AppKit
@testable import spacemap

class SettingsTestCase: XCTestCase {
    func makeDraft(
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

    final class SaveCounter {
        var configs: [SpacemapConfig] = []
    }

    /// Every `SpacemapConfig` field deliberately off its default so the save
    /// round-trip cannot pass by only exercising a subset.
    static func fullNonDefaultConfig() -> SpacemapConfig {
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

    static func normalizingProfileIDs(_ config: SpacemapConfig) -> SpacemapConfig {
        var normalized = config
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        normalized.spaceNameProfiles = normalized.spaceNameProfiles.map { profile in
            var copy = profile
            copy.id = id
            return copy
        }
        return normalized
    }

    static func keyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
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
