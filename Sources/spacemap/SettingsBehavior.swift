import SwiftUI
import Foundation
import CoreGraphics
import AppKit
import Sparkle

struct SettingsBehavior: View {

    @State private var hotkeyRecorderCoordinator = HotkeyRecorderCoordinator()

    @Binding var hotkeyString: String
    @Binding var pinnedHotkeyString: String
    @Binding var glyphStripHotkeyString: String
    @Binding var hudKeys: HUDKeyBindings
    @Binding var hudPositionKind: HUDPositionKind
    @Binding var autoHideTimeout: Int
    @Binding var jumpToSpaceEnabled: Bool
    @Binding var displayNavigationWrap: DisplayNavigationWrap
    @Binding var focusSpaceOnWindowDrop: WindowDropFocusMode
    @Binding var focusSpaceOnWindowDropModifier: WindowDropFocusModifier
    @Binding var showHUDOnSpaceChange: Bool
    @Binding var showHUDInteractionFeedback: Bool
    @Binding var hudAnimationsEnabled: Bool
    @Binding var hudAnimationStyle: HUDAnimationStyle
    @Binding var hudEntranceStyle: HUDEntranceStyle
    @Binding var presence: AppPresence
    @Binding var menuBarDisplayMode: MenuBarDisplayMode
    @Binding var menuBarNearbyCount: Int
    @Binding var glyphStripMenuBarItem: Bool
    @Binding var updateMode: UpdateMode
    @Binding var appFontUpdateMode: AppFontUpdateMode


    let checkForUpdates: () -> Void

    /// What each placement means in practice. Settings and About always add a
    /// Dock icon while they are open, whatever this setting says.
    private var presenceSummary: String {
        switch presence {
        case .menuBar:
            return "Menu-bar icon only. No Dock icon while Spacemap runs in the background. Settings and About still appear in the Dock while open."
        case .dock:
            return "Dock icon only. The menu-bar icon is hidden. Use the Dock icon to reach Settings and Quit."
        case .both:
            return "Dock icon and menu-bar icon both stay visible. Use either one."
        case .none:
            return "No Dock icon and no menu-bar icon. Spacemap keeps running in the background. Settings and About still appear in the Dock while open."
        }
    }

    @State private var installedFontVersion = ""
    @State private var isCheckingFont = false
    @State private var fontStatus: String?


    enum Scope {
        case general, hud, hotkeys
    }

    let scope: Scope

    var body: some View {
        Group {
            if scope == .hotkeys {
                hotkeysSection
                hudKeySection
            }
            if scope == .hud {
                hudSection
                navigationSection
                windowDropSection
                feedbackSection
            }
            if scope == .general {
                menuBarSection
                menuBarStripSection
                updatesSection
                appFontSection
            }
        }
    }

    private var hotkeysSection: some View {
        Section(header: SettingsSectionHeader(title: "Hotkeys").settingsAnchor("behavior.hotkeys")) {
            HotkeyRecorder(
                label: "Hotkey",
                hotkey: $hotkeyString,
                coordinator: hotkeyRecorderCoordinator
            )
                .onChange(of: hotkeyString) { value in
                    if Self.matches(value, pinnedHotkeyString) {
                        pinnedHotkeyString = "none"
                    }
                    if Self.matches(value, glyphStripHotkeyString) {
                        glyphStripHotkeyString = "none"
                    }
                }
            HotkeyRecorder(
                label: "Pinned HUD Hotkey",
                hotkey: $pinnedHotkeyString,
                coordinator: hotkeyRecorderCoordinator
            )
                .onChange(of: pinnedHotkeyString) { value in
                    if Self.matches(value, hotkeyString) {
                        hotkeyString = "none"
                    }
                    if Self.matches(value, glyphStripHotkeyString) {
                        glyphStripHotkeyString = "none"
                    }
                }
            HotkeyRecorder(
                label: "Toggle Glyph Strip",
                hotkey: $glyphStripHotkeyString,
                coordinator: hotkeyRecorderCoordinator
            )
                .onChange(of: glyphStripHotkeyString) { value in
                    if Self.matches(value, hotkeyString) {
                        hotkeyString = "none"
                    }
                    if Self.matches(value, pinnedHotkeyString) {
                        pinnedHotkeyString = "none"
                    }
                }
            SettingsFootnote(text: "Optional. Toggles a HUD that stays visible until you use either hotkey to hide it. The glyph strip hotkey shows or hides the menu-bar strip for the session.")

        }
    }

    private var hudKeySection: some View {
        Section(header: SettingsSectionHeader(title: "HUD Keys").settingsAnchor("behavior.hudKeys")) {
            ForEach(HUDCommand.allCases, id: \.rawValue) { command in
                HUDKeyBindingEditor(
                    label: command.label,
                    bindings: Binding(
                        get: { hudKeys[command] },
                        set: { hudKeys[command] = $0 }
                    ),
                    coordinator: hotkeyRecorderCoordinator
                )
            }
            SettingsFootnote(text: "Defaults are vim keys (h/j/k/l) and arrow keys. Clear a shortcut to unbind it; add a shortcut for an extra binding.")
        }
    }

    private var hudSection: some View {
        Section(header: SettingsSectionHeader(title: "HUD").settingsAnchor("behavior.hud")) {
            GlassSegmentedPicker("HUD Position", selection: $hudPositionKind, options: [
                (title: "Center", value: .center),
                (title: "Top", value: .top),
                (title: "Bottom", value: .bottom),
                (title: "Custom", value: .custom),
            ])

            if case .custom = hudPositionKind {
                SettingsFootnote(text: "Drag the HUD to reposition. Position is saved automatically.")
            }

            stepper("Auto-hide Timeout (s) (0 = disabled):", value: $autoHideTimeout, range: 0...60)

        }
    }

    private var navigationSection: some View {
        Section(header: SettingsSectionHeader(title: "Navigation").settingsAnchor("behavior.navigation")) {
            Toggle("Jump to Space with Number Keys", isOn: $jumpToSpaceEnabled)

            GlassSegmentedPicker("Display Navigation", selection: $displayNavigationWrap, options: [
                (title: "Wrap Within Display", value: .within),
                (title: "Wrap Between Displays", value: .between),
            ])
            SettingsFootnote(text: displayNavigationWrap == .within
                ? "Keeps navigation within the display containing the focused space."
                : "Allows navigation to wrap from one display's spaces into another's.")

        }
    }

    private var windowDropSection: some View {
        Section(header: SettingsSectionHeader(title: "Window Drop").settingsAnchor("behavior.windowDrop")) {
            Picker("Focus Space After Window Drop", selection: $focusSpaceOnWindowDrop) {
                Text("Never").tag(WindowDropFocusMode.never)
                Text("Always").tag(WindowDropFocusMode.always)
                Text("While Holding Modifier").tag(WindowDropFocusMode.modifier)
            }
            .pickerStyle(.menu)

            if focusSpaceOnWindowDrop == .modifier {
                Picker("Required Modifier", selection: $focusSpaceOnWindowDropModifier) {
                    Text("Command (⌘)").tag(WindowDropFocusModifier.command)
                    Text("Fn").tag(WindowDropFocusModifier.function)
                    Text("Option (⌥)").tag(WindowDropFocusModifier.option)
                    Text("Control (⌃)").tag(WindowDropFocusModifier.control)
                    Text("Shift (⇧)").tag(WindowDropFocusModifier.shift)
                }
                .pickerStyle(.menu)
            }
            SettingsFootnote(text: focusSpaceOnWindowDrop == .modifier
                ? "Switches to the destination only when the selected modifier is held while dropping."
                : "Controls whether the destination space is focused after a dragged window is moved.")

        }
    }

    private var feedbackSection: some View {
        Section(header: SettingsSectionHeader(title: "HUD Feedback").settingsAnchor("behavior.feedback")) {
            Toggle("Show HUD on Space Change", isOn: $showHUDOnSpaceChange)
            SettingsFootnote(text: "Shows the HUD whenever yabai changes spaces, including changes triggered by skhd.")

            Toggle("HUD Animations", isOn: $hudAnimationsEnabled)
            if hudAnimationsEnabled {
                Picker("Entrance", selection: $hudEntranceStyle) {
                    ForEach(HUDEntranceStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                SettingsFootnote(text: "How the HUD arrives and leaves. Slide starts it just outside that screen edge; Scale grows it from a slightly smaller frame.")

                Picker("Motion", selection: $hudAnimationStyle) {
                    ForEach(HUDAnimationStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                SettingsFootnote(text: "Natural is a calm ease. Springy overshoots and bounces back. Fast is the quickest.")
            }
            SettingsFootnote(text: "Animates the HUD fade, space highlights, and add or delete changes. Off makes every change instant.")

            Toggle("Show HUD Feedback", isOn: $showHUDInteractionFeedback)
            SettingsFootnote(text: "Draws typed space numbers and action messages over the HUD. Turning this off hides the messages; every action still runs.")

        }
    }

    private var menuBarSection: some View {
        Section(header: SettingsSectionHeader(title: "Menu Bar").settingsAnchor("behavior.menuBar")) {
            Picker("Show Spacemap In", selection: $presence) {
                Text("Menu Bar").tag(AppPresence.menuBar)
                Text("Dock").tag(AppPresence.dock)
                Text("Dock and Menu Bar").tag(AppPresence.both)
                Text("Neither").tag(AppPresence.none)
            }
            SettingsFootnote(text: presenceSummary)

            if presence.showsMenuBar {
                Picker("Menu Bar Display", selection: $menuBarDisplayMode) {
                    Text("Icon").tag(MenuBarDisplayMode.icon)
                    Text("Space Dots").tag(MenuBarDisplayMode.dots)
                    Text("Current Space").tag(MenuBarDisplayMode.current)
                    Text("Nearby Spaces").tag(MenuBarDisplayMode.nearby)
                    Text("All Spaces").tag(MenuBarDisplayMode.all)
                }

                if menuBarDisplayMode == .nearby {
                    stepper("Nearby Space Count", value: $menuBarNearbyCount, range: 1...16)
                }

                if menuBarDisplayMode == .dots {
                    SettingsFootnote(text: "Shows the configured workspace grid as dots, highlighting the focused space.")
                } else if menuBarDisplayMode != .icon {
                    SettingsFootnote(text: "Draws each space's live window layout in the menu bar. All spaces are shown full size in one horizontal row.")
                }
            }

        }
    }

    private var menuBarStripSection: some View {
        Section(header: SettingsSectionHeader(title: "Glyph Strip Menu Bar").settingsAnchor("behavior.menuBarStrip")) {
            Toggle("Show Glyph Strip in Menu Bar", isOn: $glyphStripMenuBarItem)
            SettingsFootnote(text: "The strip becomes a compact menu-bar item. The Spacemap menu-bar icon can stay visible at the same time. Shape, glass, free placement and vertical layouts do not apply in the menu bar.")
            if glyphStripMenuBarItem {
                SettingsFootnote(text: "Turn the strip off in Glyph Strip > General to remove it. Turning this off returns it to the floating strip.")
            }
        }
    }

    private var updatesSection: some View {
        Section(header: SettingsSectionHeader(title: "Updates").settingsAnchor("behavior.updates")) {
            GlassSegmentedPicker("Automatic Updates", selection: $updateMode, options: [
                (title: "Auto", value: .auto),
                (title: "Notify", value: .notify),
                (title: "Off", value: .off),
            ])

            Button("Check for Updates...") {
                checkForUpdates()
            }
            .liquidGlassButtonStyle()
        }
    }

    private var appFontSection: some View {
        Section(header: SettingsSectionHeader(title: "App Font").settingsAnchor("behavior.appFont")) {
            GlassSegmentedPicker("Font Update Mode", selection: $appFontUpdateMode, options: [
                (title: "Manual", value: .manual),
                (title: "Auto", value: .auto),
            ])
            SettingsFootnote(text: "Auto checks GitHub once a day for sketchybar-app-font updates.")

            HStack {
                Text(installedFontVersion.isEmpty
                    ? "Current: bundled version"
                    : "Current: \(installedFontVersion)")
                Spacer()
                Button("Check for Update") {
                    checkForFontUpdate()
                }
                .disabled(isCheckingFont)
                .liquidGlassButtonStyle()
            }
            if let fontStatus {
                SettingsFootnote(text: fontStatus)
            }
        }
        .onAppear {
            installedFontVersion = ConfigStore.load().appFont.installedVersion
        }
    }

    private func checkForFontUpdate() {
        isCheckingFont = true
        fontStatus = "Checking for updates…"
        let installedTag = ConfigStore.load().appFont.installedVersion
        let hadFace = AppGlyphFont.load() != nil
        installedFontVersion = installedTag
        Task {
            let status: String
            do {
                switch try await AppFontUpdater.runCheck(installedTag: installedTag) {
                case .upToDate(let tag):
                    // Same persistence as the auto path: the check happened,
                    // even though nothing installed.
                    AppFontUpdater.recordCheck(installedTag: nil)
                    status = "Up to date (\(tag))"
                case .updated(let info):
                    AppFontUpdater.recordCheck(installedTag: info.tag)
                    status = "Updated to \(info.tag)"
                    installedFontVersion = info.tag
                    if hadFace {
                        AppFontUpdater.relaunchIfGlyphStripUsesFont(ConfigStore.load())
                    }
                }
            } catch {
                // Failures record nothing so the next check retries.
                status = "Update failed: \(error.localizedDescription)"
            }
            await MainActor.run {
                fontStatus = status
                isCheckingFont = false
            }
        }
    }


    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = Hotkey.parseHotkey(lhs),
              let right = Hotkey.parseHotkey(rhs),
              !left.isDisabled,
              !right.isDisabled else { return false }
        return hotkeyIdentity(left) == hotkeyIdentity(right)
    }

    /// Function keys report `.maskSecondaryFn` when pressed on some keyboards
    /// but parse without it from `f1`; treat both spellings as the same
    /// binding so duplicate detection stays consistent.
    static func hotkeyIdentity(_ hotkey: HotkeyConfig) -> String {
        Hotkey.bindingIdentity(hotkey)
    }
}
