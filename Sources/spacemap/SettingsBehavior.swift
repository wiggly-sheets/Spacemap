import SwiftUI
import Foundation
import CoreGraphics
import AppKit
import Sparkle

struct SettingsBehavior: View {

    @Binding var hotkeyString: String
    @Binding var pinnedHotkeyString: String
    @Binding var hudPositionKind: HUDPositionKind
    @Binding var autoHideTimeout: Int
    @Binding var useArrowKeys: Bool
    @Binding var useVimKeys: Bool
    @Binding var jumpToSpaceEnabled: Bool
    @Binding var displayNavigationWrap: DisplayNavigationWrap
    @Binding var focusSpaceOnWindowDrop: WindowDropFocusMode
    @Binding var focusSpaceOnWindowDropModifier: WindowDropFocusModifier
    @Binding var showHUDOnSpaceChange: Bool
    @Binding var hideMenuBarIcon: Bool
    @Binding var menuBarDisplayMode: MenuBarDisplayMode
    @Binding var menuBarNearbyCount: Int
    @Binding var updateMode: UpdateMode


    @State private var previousUpdateMode: UpdateMode = .notify


    let onSave: () -> Void
    let checkForUpdates: () -> Void


    var body: some View {
        Section(header: SettingsSectionHeader(title: "Behavior")) {
            HotkeyRecorder(label: "Hotkey", hotkey: $hotkeyString)
                .onChange(of: hotkeyString) { value in
                    if Self.matches(value, pinnedHotkeyString) {
                        pinnedHotkeyString = "none"
                    }
                    onSave()
                }
            HotkeyRecorder(label: "Pinned HUD Hotkey", hotkey: $pinnedHotkeyString)
                .onChange(of: pinnedHotkeyString) { value in
                    if Self.matches(value, hotkeyString) {
                        hotkeyString = "none"
                    }
                    onSave()
                }
            SettingsFootnote(text: "Optional. Toggles a HUD that stays visible until you use either hotkey to hide it.")

            Picker("HUD Position", selection: $hudPositionKind) {
                Text("Center").tag(HUDPositionKind.center)
                Text("Top").tag(HUDPositionKind.top)
                Text("Bottom").tag(HUDPositionKind.bottom)
                Text("Custom").tag(HUDPositionKind.custom)
            }
            .pickerStyle(.segmented)
            .onChange(of: hudPositionKind) { _ in onSave() }

            if case .custom = hudPositionKind {
                SettingsFootnote(text: "Drag the HUD to reposition. Position is saved automatically.")
            }

            HStack {
                Text("Auto-hide Timeout (s) (0 = disabled):")
                Spacer()
                Text("\(autoHideTimeout)")
                Stepper("", value: $autoHideTimeout, in: 0...60)
                    .labelsHidden()
                    .onChange(of: autoHideTimeout) { _ in onSave() }
            }

            Toggle("Navigate with Arrow Keys (←↑↓→)", isOn: $useArrowKeys)
                .onChange(of: useArrowKeys) { _ in onSave() }
            Toggle("Navigate with Vim Keys (hjkl)", isOn: $useVimKeys)
                .onChange(of: useVimKeys) { _ in onSave() }
            Toggle("Jump to Space with Number Keys", isOn: $jumpToSpaceEnabled)
                .onChange(of: jumpToSpaceEnabled) { _ in onSave() }

            if useArrowKeys || useVimKeys {
                Picker("Display Navigation", selection: $displayNavigationWrap) {
                    Text("Wrap Within Display").tag(DisplayNavigationWrap.within)
                    Text("Wrap Between Displays").tag(DisplayNavigationWrap.between)
                }
                .pickerStyle(.segmented)
                .onChange(of: displayNavigationWrap) { _ in onSave() }
                SettingsFootnote(text: displayNavigationWrap == .within
                    ? "Keeps navigation within the display containing the focused space."
                    : "Allows navigation to wrap from one display's spaces into another's.")
            }

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

            Toggle("Show HUD on Space Change", isOn: $showHUDOnSpaceChange)
                .onChange(of: showHUDOnSpaceChange) { _ in onSave() }
            SettingsFootnote(text: "Shows the HUD whenever yabai changes spaces, including changes triggered by skhd.")

            Toggle("Hide Menu Bar Icon", isOn: $hideMenuBarIcon)
                .onChange(of: hideMenuBarIcon) { _ in onSave() }

            if hideMenuBarIcon {
                SettingsFootnote(text: "Access settings by relaunching the app or pressing ⌘, while the HUD is open.")
            } else {
                Picker("Menu Bar Display", selection: $menuBarDisplayMode) {
                    Text("Icon").tag(MenuBarDisplayMode.icon)
                    Text("Space Dots").tag(MenuBarDisplayMode.dots)
                    Text("Current Space").tag(MenuBarDisplayMode.current)
                    Text("Nearby Spaces").tag(MenuBarDisplayMode.nearby)
                    Text("All Spaces").tag(MenuBarDisplayMode.all)
                }
                .onChange(of: menuBarDisplayMode) { _ in onSave() }

                if menuBarDisplayMode == .nearby {
                    HStack {
                        Text("Nearby Space Count")
                        Spacer()
                        Text("\(menuBarNearbyCount)")
                        Stepper("", value: $menuBarNearbyCount, in: 1...16)
                            .labelsHidden()
                            .onChange(of: menuBarNearbyCount) { _ in onSave() }
                    }
                }

                if menuBarDisplayMode == .dots {
                    SettingsFootnote(text: "Shows the configured workspace grid as dots, highlighting the focused space.")
                } else if menuBarDisplayMode != .icon {
                    SettingsFootnote(text: "Draws each space's live window layout in the menu bar. All spaces are shown full size in one horizontal row.")
                }
            }

            Picker("Automatic Updates", selection: $updateMode) {
                Text("Auto").tag(UpdateMode.auto)
                Text("Notify").tag(UpdateMode.notify)
                Text("Off").tag(UpdateMode.off)
            }
            .pickerStyle(.segmented)
            .onChange(of: updateMode) { newValue in
                if newValue != previousUpdateMode {
                    onSave()
                    previousUpdateMode = newValue
                }
            }

            Button("Check for Updates...") {
                checkForUpdates()
            }
        }
    }


    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .textCase(nil)
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = Hotkey.parseHotkey(lhs),
              let right = Hotkey.parseHotkey(rhs),
              !left.isDisabled,
              !right.isDisabled else { return false }
        return left.key == right.key && left.modifiers == right.modifiers
    }
}
