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
    @Binding var hudPositionKind: HUDPositionKind
    @Binding var autoHideTimeout: Int
    @Binding var useArrowKeys: Bool
    @Binding var useVimKeys: Bool
    @Binding var useExtendedKeys: Bool
    @Binding var jumpToSpaceEnabled: Bool
    @Binding var displayNavigationWrap: DisplayNavigationWrap
    @Binding var focusSpaceOnWindowDrop: WindowDropFocusMode
    @Binding var focusSpaceOnWindowDropModifier: WindowDropFocusModifier
    @Binding var showHUDOnSpaceChange: Bool
    @Binding var showHUDInteractionFeedback: Bool
    @Binding var hudAnimationsEnabled: Bool
    @Binding var hudAnimationStyle: HUDAnimationStyle
    @Binding var presence: AppPresence
    @Binding var menuBarDisplayMode: MenuBarDisplayMode
    @Binding var menuBarNearbyCount: Int
    @Binding var updateMode: UpdateMode
    @Binding var appFontUpdateMode: AppFontUpdateMode


    let onSave: () -> Void
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


    var body: some View {
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
                    onSave()
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
                    onSave()
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
                    onSave()
                }
            SettingsFootnote(text: "Optional. Toggles a HUD that stays visible until you use either hotkey to hide it. The glyph strip hotkey shows or hides the menu-bar strip for the session.")

        }

        Section(header: SettingsSectionHeader(title: "HUD").settingsAnchor("behavior.hud")) {
            GlassSegmentedPicker("HUD Position", selection: $hudPositionKind, options: [
                (title: "Center", value: .center),
                (title: "Top", value: .top),
                (title: "Bottom", value: .bottom),
                (title: "Custom", value: .custom),
            ])
            .onChange(of: hudPositionKind) { _ in onSave() }

            if case .custom = hudPositionKind {
                SettingsFootnote(text: "Drag the HUD to reposition. Position is saved automatically.")
            }

            stepper("Auto-hide Timeout (s) (0 = disabled):", value: $autoHideTimeout, range: 0...60)
                .onChange(of: autoHideTimeout) { _ in onSave() }

        }

        Section(header: SettingsSectionHeader(title: "Navigation").settingsAnchor("behavior.navigation")) {
            Toggle("Navigate with Arrow Keys (←↑↓→)", isOn: $useArrowKeys)
                .onChange(of: useArrowKeys) { _ in onSave() }
            Toggle("Navigate with Vim Keys (hjkl)", isOn: $useVimKeys)
                .onChange(of: useVimKeys) { _ in onSave() }
            Toggle("Navigate with Extended Keys", isOn: $useExtendedKeys)
                .onChange(of: useExtendedKeys) { _ in onSave() }
            SettingsFootnote(text: "n/p = previous/next space, f/e = first/last space, r = recent space, a/t/w = create/create+focus/destroy space, b/s/u = bsp/stack/float layout, esc/c = close the HUD.")
            Toggle("Jump to Space with Number Keys", isOn: $jumpToSpaceEnabled)
                .onChange(of: jumpToSpaceEnabled) { _ in onSave() }

            if useArrowKeys || useVimKeys || useExtendedKeys {
                GlassSegmentedPicker("Display Navigation", selection: $displayNavigationWrap, options: [
                    (title: "Wrap Within Display", value: .within),
                    (title: "Wrap Between Displays", value: .between),
                ])
                .onChange(of: displayNavigationWrap) { _ in onSave() }
                SettingsFootnote(text: displayNavigationWrap == .within
                    ? "Keeps navigation within the display containing the focused space."
                    : "Allows navigation to wrap from one display's spaces into another's.")
            }

        }

        Section(header: SettingsSectionHeader(title: "Window Drop").settingsAnchor("behavior.windowDrop")) {
            Picker("Focus Space After Window Drop", selection: $focusSpaceOnWindowDrop) {
                Text("Never").tag(WindowDropFocusMode.never)
                Text("Always").tag(WindowDropFocusMode.always)
                Text("While Holding Modifier").tag(WindowDropFocusMode.modifier)
            }
            .pickerStyle(.menu)
                .onChange(of: focusSpaceOnWindowDrop) { _ in onSave() }

            if focusSpaceOnWindowDrop == .modifier {
                Picker("Required Modifier", selection: $focusSpaceOnWindowDropModifier) {
                    Text("Command (⌘)").tag(WindowDropFocusModifier.command)
                    Text("Fn").tag(WindowDropFocusModifier.function)
                    Text("Option (⌥)").tag(WindowDropFocusModifier.option)
                    Text("Control (⌃)").tag(WindowDropFocusModifier.control)
                    Text("Shift (⇧)").tag(WindowDropFocusModifier.shift)
                }
                .pickerStyle(.menu)
                .onChange(of: focusSpaceOnWindowDropModifier) { _ in onSave() }
            }
            SettingsFootnote(text: focusSpaceOnWindowDrop == .modifier
                ? "Switches to the destination only when the selected modifier is held while dropping."
                : "Controls whether the destination space is focused after a dragged window is moved.")

        }

        Section(header: SettingsSectionHeader(title: "HUD Feedback").settingsAnchor("behavior.feedback")) {
            Toggle("Show HUD on Space Change", isOn: $showHUDOnSpaceChange)
                .onChange(of: showHUDOnSpaceChange) { _ in onSave() }
            SettingsFootnote(text: "Shows the HUD whenever yabai changes spaces, including changes triggered by skhd.")

            Toggle("HUD Animations", isOn: $hudAnimationsEnabled)
                .onChange(of: hudAnimationsEnabled) { _ in onSave() }
            if hudAnimationsEnabled {
                Picker("Motion", selection: $hudAnimationStyle) {
                    ForEach(HUDAnimationStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: hudAnimationStyle) { _ in onSave() }
            }
            SettingsFootnote(text: "Animates the HUD fade, space highlights, and add or delete changes. Off makes every change instant.")

            Toggle("Show HUD Feedback", isOn: $showHUDInteractionFeedback)
                .onChange(of: showHUDInteractionFeedback) { _ in onSave() }
            SettingsFootnote(text: "Draws typed space numbers and action messages over the HUD. Turning this off hides the messages; every action still runs.")

        }

        Section(header: SettingsSectionHeader(title: "Menu Bar").settingsAnchor("behavior.menuBar")) {
            Picker("Show Spacemap In", selection: $presence) {
                Text("Menu Bar").tag(AppPresence.menuBar)
                Text("Dock").tag(AppPresence.dock)
                Text("Dock and Menu Bar").tag(AppPresence.both)
                Text("Neither").tag(AppPresence.none)
            }
            .onChange(of: presence) { _ in onSave() }
            SettingsFootnote(text: presenceSummary)

            if presence.showsMenuBar {
                Picker("Menu Bar Display", selection: $menuBarDisplayMode) {
                    Text("Icon").tag(MenuBarDisplayMode.icon)
                    Text("Space Dots").tag(MenuBarDisplayMode.dots)
                    Text("Current Space").tag(MenuBarDisplayMode.current)
                    Text("Nearby Spaces").tag(MenuBarDisplayMode.nearby)
                    Text("All Spaces").tag(MenuBarDisplayMode.all)
                }
                .onChange(of: menuBarDisplayMode) { _ in onSave() }

                if menuBarDisplayMode == .nearby {
                    stepper("Nearby Space Count", value: $menuBarNearbyCount, range: 1...16)
                        .onChange(of: menuBarNearbyCount) { _ in onSave() }
                }

                if menuBarDisplayMode == .dots {
                    SettingsFootnote(text: "Shows the configured workspace grid as dots, highlighting the focused space.")
                } else if menuBarDisplayMode != .icon {
                    SettingsFootnote(text: "Draws each space's live window layout in the menu bar. All spaces are shown full size in one horizontal row.")
                }
            }

        }

        Section(header: SettingsSectionHeader(title: "Updates").settingsAnchor("behavior.updates")) {
            GlassSegmentedPicker("Automatic Updates", selection: $updateMode, options: [
                (title: "Auto", value: .auto),
                (title: "Notify", value: .notify),
                (title: "Off", value: .off),
            ])
            .onChange(of: updateMode) { _ in onSave() }

            Button("Check for Updates...") {
                checkForUpdates()
            }
            .liquidGlassButtonStyle()
        }

        Section(header: SettingsSectionHeader(title: "App Font").settingsAnchor("behavior.appFont")) {
            GlassSegmentedPicker("Font Update Mode", selection: $appFontUpdateMode, options: [
                (title: "Manual", value: .manual),
                (title: "Auto", value: .auto),
            ])
            .onChange(of: appFontUpdateMode) { _ in onSave() }
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
            installedFontVersion = AppConfig.load().appFont.installedVersion
        }
    }


    private func checkForFontUpdate() {
        isCheckingFont = true
        fontStatus = "Checking for updates…"
        let installedTag = AppConfig.load().appFont.installedVersion
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
