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
    let coordinator: HotkeyRecorderCoordinator

    @State private var recordingState = HotkeyRecordingState()
    @State private var monitors: [Any] = []
    @State private var recorderID = UUID()

    private var isRecording: Bool { recordingState.isRecording }

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
                .onTapGesture {
                    if isRecording {
                        cancelRecording()
                    } else {
                        startRecording()
                    }
                }

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
        .onDisappear { cancelRecording() }
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

final class HotkeyRecorderCoordinator {
    private(set) var activeRecorderID: UUID?
    private var cancelActiveRecorder: (() -> Void)?

    func activate(recorderID: UUID, onCancel: @escaping () -> Void) {
        if activeRecorderID != recorderID {
            let cancelPrevious = cancelActiveRecorder
            activeRecorderID = nil
            cancelActiveRecorder = nil
            cancelPrevious?()
        }
        activeRecorderID = recorderID
        cancelActiveRecorder = onCancel
    }

    func deactivate(recorderID: UUID) {
        guard activeRecorderID == recorderID else { return }
        activeRecorderID = nil
        cancelActiveRecorder = nil
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
