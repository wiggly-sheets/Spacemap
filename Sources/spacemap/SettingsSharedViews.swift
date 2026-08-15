import SwiftUI
import AppKit

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .textCase(nil)
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
    }
}

struct DiagnosticStatusRow: View {
    let title: String
    let isHealthy: Bool?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(title)
            Spacer()
            Text(statusText)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        guard let isHealthy else { return .secondary }
        return isHealthy ? .green : .red
    }

    private var statusText: String {
        guard let isHealthy else { return "Checking…" }
        return isHealthy ? "Running" : "Unavailable"
    }
}

struct SettingsFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HotkeyRecorder: View {
    let label: String
    @Binding var hotkey: String

    @State private var isRecording = false
    @State private var monitors: [Any] = []

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(isRecording ? "Press a key..." : hotkey)
                .foregroundColor(isRecording ? .secondary : .primary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.3),
                                    lineWidth: 1)
                )
                .onTapGesture { startRecording() }

            if Self.canClear(hotkey), !isRecording {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear \(label)")
                .accessibilityLabel("Clear \(label)")
            }
        }
    }

    private func startRecording() {
        isRecording = true
        hotkey = "Recording..."

        let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil
        }

        let flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleFlagsChanged(event)
            return nil
        }

        let mediaKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            handleMediaKey(event)
            return nil
        }

        monitors = [keyDownMonitor, flagsChangedMonitor, mediaKeyMonitor].compactMap { $0 }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let hotkeyConfig = Hotkey.parseHotkeyFromEvent(event)
        hotkey = HotkeyRecorder.hotkeyStringFrom(hotkeyConfig)
        stopRecording()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let hotkeyConfig = Hotkey.parseHotkeyFromEvent(event)
        if hotkeyConfig.isDisabled {
            hotkey = "none"
            stopRecording()
        }
    }

    private func handleMediaKey(_ event: NSEvent) {
        guard let hotkeyConfig = Hotkey.parseHotkeyFromMediaKeyEvent(event) else { return }
        hotkey = HotkeyRecorder.hotkeyStringFrom(hotkeyConfig)
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func clear() {
        stopRecording()
        hotkey = "none"
    }

    static func hotkeyStringFrom(_ hotkey: HotkeyConfig) -> String {
        Hotkey.hotkeyToString(hotkey)
    }

    static func canClear(_ hotkey: String) -> Bool {
        hotkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "none"
    }
}
