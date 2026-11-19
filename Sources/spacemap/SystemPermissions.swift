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

    /// True when Accessibility works right now, not just when the cached trust
    /// bit says so. Removing Spacemap from the permission list leaves
    /// `AXIsProcessTrusted()` true but makes real AX calls fail.
    static func accessibilityIsUsable() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        return error == .success || error == .noValue
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

    /// Whether a switch to thumbnail cells should ask for Screen Recording at
    /// all. A granted permission needs no prompt and no System Settings pane.
    static func needsScreenRecordingRequest(hasPermission: Bool = hasScreenRecording) -> Bool {
        !hasPermission
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    /// Screen Recording is read at process start, so a new grant needs a new
    /// process. Starts a fresh copy after this one exits, then quits this one.
    static func relaunch() {
        AppRestartPlan.relaunch()
    }

    private static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Runs permission checks off the main thread. TCC can stall while the user
/// edits the permission list; a synchronous check on a timer would freeze the
/// event stream and make every tap look dead.
final class PermissionProbe {
    static let shared = PermissionProbe()

    private let queue = DispatchQueue(label: "spacemap.permission-probe", qos: .utility)
    private var inFlight = false
    private var startedAt = Date.distantPast
    /// Set once a check exceeds the timeout. Reads keep returning false so
    /// callers tear their event taps down instead of hanging again.
    private(set) var isStalled = false

    func check(
        timeout: TimeInterval = 1.5,
        provider: @escaping () -> Bool,
        completion: @escaping (Bool) -> Void
    ) {
        let now = Date()
        if inFlight {
            if now.timeIntervalSince(startedAt) > timeout {
                isStalled = true
                completion(false)
            }
            return
        }
        guard !isStalled else {
            completion(false)
            return
        }
        inFlight = true
        startedAt = now
        queue.async { [weak self] in
            let trusted = provider()
            DispatchQueue.main.async {
                self?.inFlight = false
                // The hung call finally answered; allow checks again.
                self?.isStalled = false
                completion(trusted)
            }
        }
    }
}


/// Watches the *working* Accessibility permission, not the cached trust bit.
/// A revoked permission can leave WindowServer event taps registered with no
/// callback, which freezes all input; replacing the process releases them.
final class AccessibilityHealthMonitor {
    static let shared = AccessibilityHealthMonitor()

    private var timer: Timer?
    private var lastUsable: Bool?

    func start() {
        guard timer == nil else { return }
        lastUsable = SystemPermissions.accessibilityIsUsable()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    private func check() {
        PermissionProbe.shared.check(provider: SystemPermissions.accessibilityIsUsable) { [weak self] usable in
            guard let self else { return }
            let previous = self.lastUsable
            self.lastUsable = usable
            guard previous == true, !usable else { return }
            NSLog("Spacemap: Accessibility stopped working; relaunching to release event taps")
            SystemPermissions.relaunch()
        }
    }
}
