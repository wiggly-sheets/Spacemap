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

        monitors = [keyDownMonitor, flagsChangedMonitor]
    }

    private func handleKeyDown(_ event: NSEvent) {
        let hotkeyConfig = HotkeyConfig.from(event)
        hotkey = HotkeyRecorder.hotkeyStringFrom(hotkeyConfig, event: event)
        stopRecording()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let hotkeyConfig = HotkeyConfig.from(event)
        if hotkeyConfig.isDisabled {
            hotkey = "none"
            stopRecording()
        }
    }

    private func stopRecording() {
        isRecording = false
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    static func hotkeyStringFrom(_ hotkey: HotkeyConfig, event: NSEvent) -> String {
        if hotkey.isDisabled { return "none" }

        var components: [String] = []

        if hotkey.modifiers.contains(.maskCommand) { components.append("⌘") }
        if hotkey.modifiers.contains(.maskControl) { components.append("⌃") }
        if hotkey.modifiers.contains(.maskAlternate) { components.append("⌥") }
        if hotkey.modifiers.contains(.maskShift) { components.append("⇧") }
        if hotkey.modifiers.contains(.maskSecondaryFn) { components.append("fn") }

        if let keyCode = hotkey.keyCode {
            let keyString: String
            switch keyCode {
            case 36: keyString = "return"
            case 48: keyString = "tab"
            case 49: keyString = "space"
            case 51: keyString = "delete"
            case 53: keyString = "escape"
            case 123: keyString = "left"
            case 124: keyString = "right"
            case 125: keyString = "down"
            case 126: keyString = "up"
            case 125...126: keyString = "arrow"
            default:
                if let char = event.charactersIgnoringModifiers, !char.isEmpty {
                    keyString = String(char.lowercased())
                } else {
                    keyString = "key\(keyCode)"
                }
            }
            components.append(keyString)
        } else if let mediaKey = hotkey.mediaKey {
            components.append(mediaKey.rawValue)
        }

        return components.joined(separator: "+")
    }
}