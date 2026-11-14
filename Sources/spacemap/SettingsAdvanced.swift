import SwiftUI

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
                    request: { SystemPermissions.requestAccessibility(); refresh() },
                    openSettings: { SystemPermissions.openAccessibilitySettings() }
                )

                PermissionRow(
                    title: "Screen Recording",
                    detail: "Needed for thumbnail cells. Without it, thumbnails stay empty.",
                    isGranted: hasScreenRecording,
                    request: { SystemPermissions.requestScreenRecordingOrOpenSettings(); refresh() },
                    openSettings: { SystemPermissions.openScreenRecordingSettings() }
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
    }

    private func refresh() {
        hasAccessibility = SystemPermissions.hasAccessibility
        hasScreenRecording = SystemPermissions.hasScreenRecording
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
