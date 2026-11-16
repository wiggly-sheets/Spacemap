import SwiftUI
import UniformTypeIdentifiers

struct SettingsAdvanced: View {
    @Binding var isYabaiHealthy: Bool?
    @Binding var isSocketHealthy: Bool?
    @Binding var isRefreshingDiagnostics: Bool
    @Binding var socketHealthInterval: Int
    @Binding var showExtraWindows: Bool

    let refreshDiagnostics: () -> Void
    let saveConfig: () -> Void

    @State private var hasAccessibility = SystemPermissions.hasAccessibility
    @State private var hasScreenRecording = SystemPermissions.hasScreenRecording
    @State private var presets = ConfigPresetStore.shared.names()
    @State private var activePreset = ConfigPresetStore.shared.activeName
    @State private var selectedPreset = ConfigPresetStore.shared.names().first ?? ""
    @State private var newPresetName = ""
    @State private var newPresetSource: PresetSourceChoice = .current
    @State private var presetMessage: String?

    private enum PresetSourceChoice: Hashable {
        case defaults
        case current
        case preset(String)
    }

    var socketHealthOptions: [Int] {
        Self.socketHealthOptions(including: socketHealthInterval)
    }

    static func socketHealthOptions(including currentValue: Int) -> [Int] {
        Array(Set([15, 30, 45, 60, currentValue])).sorted()
    }

    var body: some View {
        Section(header: SettingsSectionHeader(title: "Permissions").settingsAnchor("advanced.permissions")) {
            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Needed for hotkeys and window dragging. macOS 27 shows this as Device Control & Access.",
                    isGranted: hasAccessibility,
                    request: {
                        SystemPermissions.requestAccessibility()
                        PermissionDragWindowController.shared.show()
                        refresh()
                    },
                    openSettings: {
                        SystemPermissions.openAccessibilitySettings()
                        PermissionDragWindowController.shared.show()
                    }
                )

                PermissionRow(
                    title: "Screen Recording",
                    detail: "Needed for thumbnail cells. Without it, thumbnails stay empty.",
                    isGranted: hasScreenRecording,
                    request: {
                        SystemPermissions.requestScreenRecordingOrOpenSettings()
                        PermissionDragWindowController.shared.show()
                        refresh()
                    },
                    openSettings: {
                        SystemPermissions.openScreenRecordingSettings()
                        PermissionDragWindowController.shared.show()
                    }
                )

                SettingsFootnote(text: "After changing a permission in System Settings, come back to this window; the status refreshes automatically. macOS only shows its own prompt once, so a later request opens System Settings instead.")

                Button("Relaunch Spacemap") {
                    SystemPermissions.relaunch()
                }
                .liquidGlassButtonStyle()
                SettingsFootnote(text: "Screen Recording is checked when Spacemap starts. Relaunch after granting it, or thumbnails stay empty.")
            }
            .padding(.vertical, 4)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }

        Section(header: SettingsSectionHeader(title: "Diagnostics").settingsAnchor("advanced.diagnostics")) {
            VStack(alignment: .leading, spacing: 12) {
                DiagnosticStatusRow(title: "Yabai Process", isHealthy: isYabaiHealthy)
                DiagnosticStatusRow(title: "Spacemap Signal Socket", isHealthy: isSocketHealthy)

                Button("Refresh Status") {
                    refreshDiagnostics()
                }
                .disabled(isRefreshingDiagnostics)
                .liquidGlassButtonStyle()

                SettingsFootnote(text: "Confirms yabai is running and its signals can reach Spacemap's Unix socket.")

                Picker("Socket Health Interval (s)", selection: $socketHealthInterval) {
                    ForEach(socketHealthOptions, id: \.self) { v in
                        Text("\(v)").tag(v as Int)
                    }
                }
                .onChange(of: socketHealthInterval) { _ in saveConfig() }

                Toggle("Show Extra Windows", isOn: $showExtraWindows)
                    .onChange(of: showExtraWindows) { _ in saveConfig() }

                SettingsFootnote(text: "Regular app windows are always shown, whether tiled or floating.")
            }
            .padding(.vertical, 4)
        }

        Section(header: SettingsSectionHeader(title: "Config Presets").settingsAnchor("advanced.presets")) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFootnote(text: "A preset is one complete config.toml in ~/.config/spacemap/presets. Applying one saves the current settings into the outgoing preset first. Hotkeys, presence, and the glyph strip change with it.")

                HStack(spacing: 8) {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(presets, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(presets.isEmpty)
                    Button("Apply") { applyPreset() }
                        .disabled(presets.isEmpty)
                    Button("Delete") { deleteSelectedPreset() }
                        .disabled(presets.isEmpty)
                }

                Text(activePreset.map { "Active preset: \($0)" } ?? "Active: config.toml (no preset)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Divider()

                HStack(spacing: 8) {
                    TextField("New preset name", text: $newPresetName)
                        .textFieldStyle(.roundedBorder)
                    Picker("Start from", selection: $newPresetSource) {
                        Text("Current Config").tag(PresetSourceChoice.current)
                        Text("Defaults").tag(PresetSourceChoice.defaults)
                        ForEach(presets, id: \.self) { name in
                            Text(name).tag(PresetSourceChoice.preset(name))
                        }
                    }
                    Button("Create") { createPreset() }
                }

                Divider()

                HStack(spacing: 8) {
                    Button("Export Config…") { exportConfig() }
                    Button("Import Config…") { importConfig() }
                }
                SettingsFootnote(text: "Import replaces the current config file. Font install state is left out of exports and presets.")

                if let presetMessage {
                    SettingsFootnote(text: presetMessage)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func refresh() {
        hasAccessibility = SystemPermissions.hasAccessibility
        hasScreenRecording = SystemPermissions.hasScreenRecording
    }

    // MARK: - Config presets

    private func reloadPresetState() {
        presets = ConfigPresetStore.shared.names()
        activePreset = ConfigPresetStore.shared.activeName
        if !presets.contains(selectedPreset) {
            selectedPreset = presets.first ?? ""
        }
    }

    private func applyPreset() {
        guard ConfigPresetStore.shared.apply(selectedPreset) else {
            presetMessage = "Could not apply “\(selectedPreset)”."
            reloadPresetState()
            return
        }
        presetMessage = nil
        reloadPresetState()
        postConfigReplaced()
    }

    private func createPreset() {
        guard let name = ConfigPresetStore.sanitizedName(newPresetName) else {
            presetMessage = "Use 1–40 letters, digits, spaces, - or _."
            return
        }
        guard !presets.contains(name) else {
            presetMessage = "A preset named “\(name)” already exists."
            return
        }
        let source: ConfigPresetStore.Source
        switch newPresetSource {
        case .defaults: source = .defaults
        case .current: source = .current
        case .preset(let name): source = .preset(name)
        }
        guard ConfigPresetStore.shared.create(name, from: source) else {
            presetMessage = "Could not create “\(name)”."
            return
        }
        newPresetName = ""
        presetMessage = "Created “\(name)”."
        reloadPresetState()
        selectedPreset = name
    }

    private func deleteSelectedPreset() {
        guard !selectedPreset.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Delete preset “\(selectedPreset)”?"
        alert.informativeText = "The preset file is removed. The current settings stay as they are."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard ConfigPresetStore.shared.delete(selectedPreset) else {
            presetMessage = "Could not delete “\(selectedPreset)”."
            return
        }
        presetMessage = nil
        reloadPresetState()
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "spacemap-config.toml"
        panel.allowedContentTypes = [UTType(filenameExtension: "toml") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard ConfigPresetStore.shared.exportConfig(to: url) else {
            presetMessage = "Could not write \(url.lastPathComponent)."
            return
        }
        presetMessage = "Exported \(url.lastPathComponent)."
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "toml") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard ConfigPresetStore.shared.importConfig(from: url) else {
            presetMessage = "Import failed: not a valid Spacemap config."
            return
        }
        presetMessage = nil
        postConfigReplaced()
    }

    /// Let the button action finish before the window rebuilds under it.
    private func postConfigReplaced() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
            NotificationCenter.default.post(name: .configReplacedExternally, object: nil)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isGranted ? .green : .orange)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(isGranted ? "Granted" : "Not Granted")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(isGranted ? "Open System Settings" : "Request Permission", action: isGranted ? openSettings : request)
                if !isGranted {
                    Button("Open System Settings", action: openSettings)
                }
            }
            .liquidGlassButtonStyle()
        }
    }
}
