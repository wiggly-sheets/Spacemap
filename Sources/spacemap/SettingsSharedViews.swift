import SwiftUI
import AppKit

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        // The type is `String` because some call sites build names at runtime;
        // routing through `LocalizedStringKey` still lets literal titles hit
        // the strings table, which `Text(String)` would bypass.
        Text(LocalizedStringKey(stringLiteral: title))
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
            Text(LocalizedStringKey(stringLiteral: title))
            Spacer()
            Text(LocalizedStringKey(stringLiteral: statusText))
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
        Text(LocalizedStringKey(stringLiteral: text))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shared label so Grid and Glyph Strip panes stay in sync. Typed as a key so
/// `Toggle` performs the lookup instead of treating it as verbatim text.
let showSpaceNumbersTitle: LocalizedStringKey = "Show Space Numbers"

func stepper(
    _ label: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double = 1
) -> some View {
    HStack {
        Text(label)
        Spacer()
        Text(String(format: step < 1 ? "%.2f" : "%.0f", value.wrappedValue))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        Stepper("", value: value, in: range, step: step)
            .labelsHidden()
    }
}

func stepper(
    _ label: String,
    value: Binding<Int>,
    range: ClosedRange<Int>
) -> some View {
    HStack {
        Text(label)
        Spacer()
        Text("\(value.wrappedValue)")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        Stepper("", value: value, in: range)
            .labelsHidden()
    }
}

struct HotkeyRecorder: View {
    let label: String
    @Binding var hotkey: String
    let coordinator: HotkeyRecorderCoordinator

    @State private var recordingState = HotkeyRecordingState()
    @State private var monitors: [Any] = []
    @State private var recorderID = UUID()

    private var isRecording: Bool { recordingState.isRecording }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer()
            recorderField
            if Self.canClear(hotkey), !isRecording {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear \(label)")
                .accessibilityLabel("Clear \(label)")
            }
        }
        .onDisappear { cancelRecording() }
    }

    private var recorderField: some View {
        HStack(spacing: 5) {
            if isRecording {
                Text("Press a key…")
                    .foregroundStyle(.secondary)
            } else if keycaps.isEmpty {
                Text("Not Set")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
                    Keycap(caption: cap)
                }
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 8)
        .frame(minWidth: 84, minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isRecording ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isRecording ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.7),
                    lineWidth: isRecording ? 1.5 : 0.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture {
            if isRecording {
                cancelRecording()
            } else {
                startRecording()
            }
        }
        .help(isRecording ? "Press Escape to cancel" : "Click to record a shortcut")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(stringLiteral: label)))
        .accessibilityValue(Text(isRecording ? "Recording" : hotkey))
        .accessibilityAddTraits(.isButton)
    }

    private var keycaps: [String] {
        Self.keycaps(for: hotkey)
    }

    /// Splits the stored shortcut into one caption per key, like a menu item.
    static func keycaps(for hotkey: String) -> [String] {
        let trimmed = hotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "none" else { return [] }
        var caps: [String] = []
        for token in trimmed.lowercased().components(separatedBy: "+") {
            switch token {
            case "ctrl": caps.append("⌃")
            case "cmd": caps.append("⌘")
            case "alt": caps.append("⌥")
            case "shift": caps.append("⇧")
            case "fn": caps.append("fn")
            case "hyper": caps.append(contentsOf: ["⌃", "⌘", "⌥", "⇧"])
            case "space": caps.append("Space")
            case "tab": caps.append("⇥")
            case "return": caps.append("↩")
            case "escape": caps.append("⎋")
            case "delete": caps.append("⌫")
            case "forward-delete": caps.append("⌦")
            case "pgup": caps.append("⇞")
            case "pgdn": caps.append("⇟")
            case "home": caps.append("↖")
            case "end": caps.append("↘")
            case "left": caps.append("←")
            case "right": caps.append("→")
            case "down": caps.append("↓")
            case "up": caps.append("↑")
            case "help": caps.append("?")
            case "backslash": caps.append("\\")
            default:
                if token.hasPrefix("f"), Int(token.dropFirst()) != nil {
                    caps.append(token.uppercased())
                } else if token.hasPrefix("keypad-") {
                    caps.append("Keypad " + token.dropFirst("keypad-".count).capitalized)
                } else if token.hasPrefix("play-") || token.hasPrefix("next-") || token.hasPrefix("previous-")
                            || token.hasPrefix("volume-") || token.hasPrefix("brightness-") || token == "mute" {
                    caps.append(token.replacingOccurrences(of: "-", with: " ").capitalized)
                } else {
                    caps.append(token.count == 1 ? token.uppercased() : token.capitalized)
                }
            }
        }
        return caps
    }

    private func startRecording() {
        guard recordingState.begin(currentHotkey: hotkey) else { return }
        coordinator.activate(recorderID: recorderID) {
            cancelRecording()
        }

        let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.isCancelKey(event) {
                cancelRecording()
            } else {
                handleKeyDown(event)
            }
            return nil
        }

        let mediaKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            handleMediaKey(event) ? nil : event
        }

        monitors = [keyDownMonitor, mediaKeyMonitor].compactMap { $0 }
        if monitors.isEmpty {
            cancelRecording()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let hotkeyConfig = Hotkey.parseHotkeyFromEvent(event)
        let recordedHotkey = HotkeyRecorder.hotkeyStringFrom(hotkeyConfig)
        guard Hotkey.parseHotkey(recordedHotkey) != nil else {
            NSSound.beep()
            return
        }
        hotkey = recordedHotkey
        stopRecording()
    }

    private func handleMediaKey(_ event: NSEvent) -> Bool {
        guard let hotkeyConfig = Hotkey.parseHotkeyFromMediaKeyEvent(event) else { return false }
        hotkey = HotkeyRecorder.hotkeyStringFrom(hotkeyConfig)
        stopRecording()
        return true
    }

    private func stopRecording() {
        removeMonitors()
        recordingState.complete()
        coordinator.deactivate(recorderID: recorderID)
    }

    private func cancelRecording() {
        guard recordingState.isRecording else {
            removeMonitors()
            coordinator.deactivate(recorderID: recorderID)
            return
        }
        removeMonitors()
        if let originalHotkey = recordingState.cancel() {
            hotkey = originalHotkey
        }
        coordinator.deactivate(recorderID: recorderID)
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
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

    static func isCancelKey(_ event: NSEvent) -> Bool {
        let shortcutModifiers = event.modifierFlags.intersection([
            .control,
            .command,
            .option,
            .shift,
            .function
        ])
        return event.type == .keyDown && event.keyCode == 53 && shortcutModifiers.isEmpty
    }
}

/// Edits every key bound to one HUD action. Extra rows can be removed; the
/// first row keeps the action label.
struct HUDKeyBindingEditor: View {
    let label: String
    @Binding var bindings: [HotkeyConfig]
    let coordinator: HotkeyRecorderCoordinator

    var body: some View {
        // Keep one editor in one container. Flattening its rows into the Form
        // gives sibling editors the same row identities, and SwiftUI can then
        // duplicate or reuse the first action's label.
        VStack(alignment: .leading, spacing: 4) {
            if bindings.isEmpty {
                HStack(spacing: 8) {
                    Text(label)
                    Spacer()
                    Text("Not Set")
                        .foregroundStyle(.tertiary)
                }
            }
            ForEach(bindings.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    HotkeyRecorder(
                        label: index == 0 ? label : "",
                        hotkey: hotkeyBinding(at: index),
                        coordinator: coordinator
                    )
                    if index > 0 {
                        Button {
                            bindings.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove shortcut")
                        .accessibilityLabel("Remove shortcut")
                    }
                }
            }
            Button("Add Shortcut") {
                bindings.append(HotkeyConfig(key: .none, modifiers: []))
            }
            .liquidGlassButtonStyle()
            .controlSize(.small)
        }
    }

    private func hotkeyBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard bindings.indices.contains(index) else { return "none" }
                return Hotkey.hotkeyToString(bindings[index])
            },
            set: { value in
                guard bindings.indices.contains(index) else { return }
                bindings[index] = Hotkey.parseHotkey(value)
                    ?? HotkeyConfig(key: .none, modifiers: [])
            }
        )
    }
}

/// One shortcut key, drawn as a compact physical keycap.
private struct Keycap: View {
    let caption: String

    var body: some View {
        Text(caption)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .shadow(color: .black.opacity(0.22), radius: 0.5, y: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 0.5)
            )
    }
}

final class HotkeyRecorderCoordinator {
    private(set) var activeRecorderID: UUID?
    private var cancelActiveRecorder: (() -> Void)?
    /// IDs of every recorder currently active across coordinators. The tap's
    /// global suppression flag is derived from this set, so a discarded or
    /// replaced recorder cannot clear it while another one still records.
    private static var activeRecorderIDs = Set<UUID>()

    deinit {
        if let activeRecorderID {
            Self.setRecording(activeRecorderID, false)
        }
    }

    func activate(recorderID: UUID, onCancel: @escaping () -> Void) {
        if activeRecorderID != recorderID {
            let cancelPrevious = cancelActiveRecorder
            if let previous = activeRecorderID {
                Self.setRecording(previous, false)
            }
            activeRecorderID = nil
            cancelActiveRecorder = nil
            cancelPrevious?()
        }
        activeRecorderID = recorderID
        cancelActiveRecorder = onCancel
        Self.setRecording(recorderID, true)
    }

    func deactivate(recorderID: UUID) {
        guard activeRecorderID == recorderID else { return }
        activeRecorderID = nil
        cancelActiveRecorder = nil
        Self.setRecording(recorderID, false)
    }

    private static func setRecording(_ recorderID: UUID, _ active: Bool) {
        if active {
            activeRecorderIDs.insert(recorderID)
        } else {
            activeRecorderIDs.remove(recorderID)
        }
        HotkeyTapRouter.isRecording = !activeRecorderIDs.isEmpty
    }
}

struct HotkeyRecordingState {
    private(set) var originalHotkey: String?

    var isRecording: Bool { originalHotkey != nil }

    mutating func begin(currentHotkey: String) -> Bool {
        guard !isRecording else { return false }
        originalHotkey = currentHotkey
        return true
    }

    mutating func complete() {
        originalHotkey = nil
    }

    mutating func cancel() -> String? {
        defer { originalHotkey = nil }
        return originalHotkey
    }
}
