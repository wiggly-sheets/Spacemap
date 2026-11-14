import AppKit
import ApplicationServices
import CoreGraphics

/// Trust state and settings deep links for the two system permissions Spacemap
/// needs. Both checks report without prompting, so Settings can refresh them on
/// every activation. macOS 27 shows Accessibility as "Device Control & Access";
/// the TCC path and preflight API do not change.
enum SystemPermissions {
    // MARK: Accessibility (hotkeys, window drag)

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt when macOS has not asked yet. Returns the
    /// current trust value, which stays false until the user grants it.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // MARK: Screen Recording (thumbnail cells)

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt once per install. Later calls only report the
    /// state, because macOS does not repeat the prompt.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Requests Screen Recording, then opens the pane when macOS will not show
    /// its prompt again. macOS records one decision per app: after a denial the
    /// request only returns false, so the user needs the settings list.
    @discardableResult
    static func requestScreenRecordingOrOpenSettings() -> Bool {
        if CGRequestScreenCaptureAccess() { return true }
        openScreenRecordingSettings()
        return false
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    /// Screen Recording is read at process start, so a new grant needs a new
    /// process. Starts a fresh copy, then quits this one.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
