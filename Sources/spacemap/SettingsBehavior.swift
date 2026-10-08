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
    @Binding var hideMenuBarIcon: Bool
    @Binding var menuBarDisplayMode: MenuBarDisplayMode
    @Binding var menuBarNearbyCount: Int
    @Binding var updateMode: UpdateMode
    @Binding var appFontUpdateMode: AppFontUpdateMode


    let onSave: () -> Void
    let checkForUpdates: () -> Void

    @State private var installedFontVersion = ""
    @State private var isCheckingFont = false
    @State private var fontStatus: String?


    var body: some View {
        Section(header: SettingsSectionHeader(title: "Behavior")) {
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

            stepper("Auto-hide Timeout (s) (0 = disabled):", value: $autoHideTimeout, range: 0...60)
                .onChange(of: autoHideTimeout) { _ in onSave() }

            Toggle("Navigate with Arrow Keys (←↑↓→)", isOn: $useArrowKeys)
                .onChange(of: useArrowKeys) { _ in onSave() }
            Toggle("Navigate with Vim Keys (hjkl)", isOn: $useVimKeys)
                .onChange(of: useVimKeys) { _ in onSave() }
            Toggle("Navigate with Extended Keys (n/p/f/e, esc/c)", isOn: $useExtendedKeys)
                .onChange(of: useExtendedKeys) { _ in onSave() }
            SettingsFootnote(text: "n/p = previous/next space, f/e = first/last space, r = recent space, esc/c = close the HUD.")
            Toggle("Jump to Space with Number Keys", isOn: $jumpToSpaceEnabled)
                .onChange(of: jumpToSpaceEnabled) { _ in onSave() }

            if useArrowKeys || useVimKeys || useExtendedKeys {
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
                    stepper("Nearby Space Count", value: $menuBarNearbyCount, range: 1...16)
                        .onChange(of: menuBarNearbyCount) { _ in onSave() }
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
            .onChange(of: updateMode) { _ in onSave() }

            Button("Check for Updates...") {
                checkForUpdates()
            }
        }

        Section(header: SettingsSectionHeader(title: "App Font")) {
            Picker("Font Update Mode", selection: $appFontUpdateMode) {
                Text("Manual").tag(AppFontUpdateMode.manual)
                Text("Auto").tag(AppFontUpdateMode.auto)
            }
            .pickerStyle(.segmented)
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
            }
            if let fontStatus {
                SettingsFootnote(text: fontStatus)
            }
        }
        .onAppear {
            installedFontVersion = Config.load().appFont.installedVersion
        }
    }


    private func checkForFontUpdate() {
        isCheckingFont = true
        fontStatus = "Checking for updates…"
        let installedTag = Config.load().appFont.installedVersion
        installedFontVersion = installedTag
        Task {
            let status: String
            do {
                switch try await AppFontUpdater.runCheck(installedTag: installedTag) {
                case .upToDate(let tag):
                    status = "Up to date (\(tag))"
                case .updated(let info):
                    status = "Updated to \(info.tag)"
                    installedFontVersion = info.tag
                }
            } catch {
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
        return left.key == right.key && left.modifiers == right.modifiers
    }
}
