import Foundation
import Combine
import SwiftUI
import AppKit

/// One editing session over the whole config.
///
/// Controls write through `binding`, which coalesces a burst of edits into one
/// disk write. The write itself is the route Settings always used: the value is
/// applied over the current disk config so the fields the updater owns survive,
/// then the file is rewritten atomically.
final class SettingsDraft: ObservableObject {
    @Published private(set) var config: SpacemapConfig
    @Published var saveErrorMessage: String?
    /// Position of the Grid Layout picker. Derived from `cols`/`rows`, not a key.
    @Published var gridLayoutIndex: Int

    /// Long enough to swallow a slider drag, short enough that the file matches
    /// the window by the time the user looks away.
    static let saveDebounce: TimeInterval = 0.5

    private let load: () -> SpacemapConfig
    private let save: (SpacemapConfig) -> Bool
    private let debounce: TimeInterval
    private var pendingSave: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    /// Last free placement, kept so returning the HUD Position picker to Custom
    /// restores it instead of the screen centre.
    private var lastCustomHUDPosition: HUDPosition

    init(
        config: SpacemapConfig = ConfigStore.load(),
        debounce: TimeInterval = saveDebounce,
        load: @escaping () -> SpacemapConfig = { ConfigStore.load() },
        save: @escaping (SpacemapConfig) -> Bool = SettingsDraft.saveToDisk
    ) {
        let seeded = Self.seed(from: config)
        self.config = seeded
        self.gridLayoutIndex = SettingsGrid.layoutIndex(
            maxSpaces: seeded.maxSpaces,
            currentCols: seeded.cols,
            currentRows: seeded.rows
        )
        if case .custom = seeded.hudPosition {
            lastCustomHUDPosition = seeded.hudPosition
        } else {
            lastCustomHUDPosition = .custom(x: 0.5, y: 0.5, screen: nil)
        }
        self.debounce = debounce
        self.load = load
        self.save = save

        // A preset apply or import replaced config.toml. Start again from the
        // file: a write in flight belongs to the config that is gone.
        observers.append(NotificationCenter.default.addObserver(
            forName: .configReplacedExternally,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reload()
        })
        // Other writers move the HUD or the strip under an open pane. Adopt
        // those values so a later save here cannot revert them.
        observers.append(NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reloadHUDPosition()
            self?.reloadGlyphStripPosition()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .glyphStripPositionChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reloadGlyphStripPosition()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: HUDDisplay.hudPositionChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reloadHUDPosition()
        })
        // The menu bar switched the space-name profile.
        observers.append(NotificationCenter.default.addObserver(
            forName: .spaceNameProfileChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reloadActiveSpaceNameProfile()
        })
        // Quitting must not drop an edit that is still inside the debounce.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flush()
        })
    }

    deinit {
        pendingSave?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Seeding

    /// Config the controls start from. The legacy `[behavior]` HUD scalars fold
    /// into the key map, and are then written back unbound, so a command stays
    /// bound through `[hudKeys]` alone.
    static func seed(from config: SpacemapConfig) -> SpacemapConfig {
        var seeded = config
        seeded.hudKeys = config.hudKeyBindings.foldingLegacy()
        let unbound = HotkeyConfig(key: .none, modifiers: [])
        seeded.hudMoveSpaceBackHotkey = unbound
        seeded.hudMoveSpaceForwardHotkey = unbound
        seeded.hudNewSpaceHotkey = unbound
        seeded.hudDeleteSpaceHotkey = unbound
        seeded.hudCycleLayoutHotkey = unbound
        seeded.glyphStrip = config.glyphStrip.clamped()
        return seeded
    }

    /// Profile state to re-seed from a menu-bar profile switch. Pure so the
    /// menu → Settings flow is testable without SwiftUI state.
    static func profileStateToSeed(
        from config: SpacemapConfig
    ) -> (index: Int, spaceNames: [Int: String])? {
        let index = config.activeSpaceNameProfileIndex
        guard config.spaceNameProfiles.indices.contains(index) else { return nil }
        return (index, config.spaceNameProfiles[index].spaceNames)
    }

    // MARK: - Bindings

    /// Writing through this binding marks the draft dirty; the save lands after
    /// the debounce, or on `flush`.
    func binding<T>(_ keyPath: WritableKeyPath<SpacemapConfig, T>) -> Binding<T> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { self.set($0, at: keyPath) }
        )
    }

    func set<T>(_ value: T, at keyPath: WritableKeyPath<SpacemapConfig, T>) {
        config[keyPath: keyPath] = value
        scheduleSave()
    }

    var hotkeyStringBinding: Binding<String> {
        hotkeyStringBinding(for: \.hotkey, fallback: SpacemapConfig.default.hotkey)
    }

    var pinnedHotkeyStringBinding: Binding<String> {
        hotkeyStringBinding(for: \.pinnedHotkey, fallback: SpacemapConfig.default.pinnedHotkey)
    }

    var glyphStripHotkeyStringBinding: Binding<String> {
        hotkeyStringBinding(for: \.glyphStripHotkey, fallback: HotkeyConfig(key: .none, modifiers: []))
    }

    var hudPositionKind: HUDPositionKind {
        get { HUDPositionKind(from: config.hudPosition) }
        set {
            if case .custom = config.hudPosition {
                lastCustomHUDPosition = config.hudPosition
            }
            let position: HUDPosition
            switch newValue {
            case .center: position = .center
            case .top: position = .top
            case .bottom: position = .bottom
            case .custom: position = lastCustomHUDPosition
            }
            set(position, at: \.hudPosition)
        }
    }

    var hudPositionKindBinding: Binding<HUDPositionKind> {
        Binding(get: { self.hudPositionKind }, set: { self.hudPositionKind = $0 })
    }

    var appFontUpdateModeBinding: Binding<AppFontUpdateMode> {
        Binding(
            get: { self.config.appFont.updateMode },
            set: { mode in
                var appFont = self.config.appFont
                appFont.updateMode = mode
                self.set(appFont, at: \.appFont)
            }
        )
    }

    /// General > Menu Bar owns the glyph strip's menu-bar toggle. Turning it on
    /// also enables the strip; both menu-bar items may be visible at once.
    var glyphStripMenuBarItemBinding: Binding<Bool> {
        Binding(
            get: { self.config.glyphStrip.displayMode == .menuBarItem },
            set: { show in
                self.config.glyphStrip.displayMode = show ? .menuBarItem : .floating
                if show { self.config.glyphStrip.enabled = true }
                self.scheduleSave()
            }
        )
    }

    // MARK: - Saving

    static func saveToDisk(_ config: SpacemapConfig) -> Bool {
        let saved = ConfigStore.updateConfig { disk in
            applySave(config, to: &disk)
        }
        if saved {
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
        return saved
    }

    /// Applies the draft's fields onto the current disk config. The updater
    /// owns `appFont.installedVersion`/`lastCheck`, and yabai trust refusal has
    /// no UI control, so both are read from `disk` at write time.
    static func applySave(_ ui: SpacemapConfig, to disk: inout SpacemapConfig) {
        var appFont = disk.appFont
        appFont.updateMode = ui.appFont.updateMode
        let refuseUntrustedYabai = disk.refuseUntrustedYabai
        disk = ui
        disk.appFont = appFont
        disk.refuseUntrustedYabai = refuseUntrustedYabai
    }

    /// Write a pending edit now. Called on a pane switch, before the window
    /// closes, and before the file is replaced.
    func flush() {
        guard pendingSave != nil else { return }
        performSave()
    }

    func cancelPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
    }

    private func scheduleSave() {
        cancelPendingSave()
        let work = DispatchWorkItem { [weak self] in
            self?.performSave()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func performSave() {
        cancelPendingSave()
        syncActiveSpaceNameProfile()
        var config = self.config
        config.glyphStrip = config.glyphStrip.clamped()
        saveErrorMessage = SettingsView.saveResultMessage(save(config))
    }

    /// The visible names belong to the active profile too, or the next profile
    /// switch would show a set the file never recorded.
    private func syncActiveSpaceNameProfile() {
        let index = config.activeSpaceNameProfileIndex
        guard config.spaceNameProfiles.indices.contains(index) else { return }
        config.spaceNameProfiles[index].spaceNames = config.spaceNames
    }

    // MARK: - Reloading

    /// A preset or import replaced config.toml: drop the edit in flight and
    /// start again from the file.
    func reload() {
        cancelPendingSave()
        adopt(Self.seed(from: load()))
    }

    /// Another writer moved the HUD. Re-seed just that value so the next save
    /// keeps the drag instead of reverting it. A pending picker change owns the
    /// value: adopting the file now would let the queued save write it back.
    func reloadHUDPosition() {
        guard pendingSave == nil else { return }
        let position = load().hudPosition
        config.hudPosition = position
        if case .custom = position { lastCustomHUDPosition = position }
    }

    /// A finished strip drag persisted only the placement. Adopt those fields
    /// alone, so a pending edit to any other strip setting survives the drag.
    func reloadGlyphStripPosition() {
        guard pendingSave == nil else { return }
        let saved = load().glyphStrip
        config.glyphStrip.position = saved.position
        config.glyphStrip.customX = saved.customX
        config.glyphStrip.customY = saved.customY
        config.glyphStrip.customScreen = saved.customScreen
    }

    /// The menu bar switched the active space-name profile. The names still in
    /// the fields belong to the profile that was active when they were typed,
    /// so write them there first, then take the new index and its names from
    /// the file.
    func reloadActiveSpaceNameProfile() {
        let hadPendingSave = pendingSave != nil
        syncActiveSpaceNameProfile()
        cancelPendingSave()
        guard let seed = Self.profileStateToSeed(from: load()) else {
            // The file changed under the notification and its index is out of
            // range. Re-arm the cancelled edit so the typed names still land.
            if hadPendingSave { scheduleSave() }
            return
        }
        config.activeSpaceNameProfileIndex = seed.index
        config.spaceNames = seed.spaceNames
        if hadPendingSave { scheduleSave() }
    }

    private func adopt(_ newConfig: SpacemapConfig) {
        config = newConfig
        gridLayoutIndex = SettingsGrid.layoutIndex(
            maxSpaces: newConfig.maxSpaces,
            currentCols: newConfig.cols,
            currentRows: newConfig.rows
        )
        if case .custom = newConfig.hudPosition {
            lastCustomHUDPosition = newConfig.hudPosition
        }
    }

    private func hotkeyStringBinding(
        for keyPath: WritableKeyPath<SpacemapConfig, HotkeyConfig>,
        fallback: HotkeyConfig
    ) -> Binding<String> {
        Binding(
            get: { Hotkey.hotkeyToString(self.config[keyPath: keyPath]) },
            set: { self.set(Hotkey.parseHotkey($0) ?? fallback, at: keyPath) }
        )
    }
}
