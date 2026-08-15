import Cocoa

final class HotkeyMonitor {
    enum EventTapRecoveryAction: Equatable {
        case waitForPermission
        case remove
        case install
        case reinstall
        case reenable
        case none
    }

    static let healthCheckInterval: TimeInterval = 1.0
    private static var didRequestAccessibilityPrompt = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mediaKeyMonitor: Any?
    private var healthTimer: Timer?
    private let onTrigger: () -> Void
    private let targetKey: HotkeyKey
    private let targetModifiers: CGEventFlags
    private var wantsMonitoring = false
    private var lastTrustState: Bool?
    private var tapCreationFailureCount = 0

    init(config: HotkeyConfig, onTrigger: @escaping () -> Void) {
        self.targetKey = config.key
        self.targetModifiers = config.modifiers
        self.onTrigger = onTrigger
    }

    deinit {
        stop()
    }

    func start() {
        if case .none = targetKey { return }

        if wantsMonitoring {
            reconcileAccessibility(promptIfNeeded: false)
            return
        }

        wantsMonitoring = true
        startHealthTimer()
        reconcileAccessibility(promptIfNeeded: true)
    }

    func stop() {
        wantsMonitoring = false
        healthTimer?.invalidate()
        healthTimer = nil
        tearDownInputMonitoring()
        lastTrustState = nil
        tapCreationFailureCount = 0
    }

    static func recoveryAction(
        isTrusted: Bool,
        hasTap: Bool,
        tapIsValid: Bool,
        tapIsEnabled: Bool
    ) -> EventTapRecoveryAction {
        guard isTrusted else {
            return hasTap ? .remove : .waitForPermission
        }
        guard hasTap else { return .install }
        guard tapIsValid else { return .reinstall }
        guard tapIsEnabled else { return .reenable }
        return .none
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        let timer = Timer(timeInterval: Self.healthCheckInterval, repeats: true) { [weak self] _ in
            self?.reconcileAccessibility(promptIfNeeded: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func reconcileAccessibility(promptIfNeeded: Bool) {
        guard wantsMonitoring else { return }

        var isTrusted = AXIsProcessTrusted()
        if !isTrusted, promptIfNeeded, !Self.didRequestAccessibilityPrompt {
            Self.didRequestAccessibilityPrompt = true
            let isRestarting = CommandLine.arguments.contains("--restarting")
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: !isRestarting
            ] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(options)
        }

        if lastTrustState != isTrusted {
            NSLog(isTrusted
                ? "Spacemap/Hotkey: accessibility granted"
                : "Spacemap/Hotkey: accessibility unavailable; waiting for permission")
            lastTrustState = isTrusted
        }

        switch targetKey {
        case .keyCode:
            reconcileEventTap(isTrusted: isTrusted)
        case .mediaKey:
            reconcileMediaKeyMonitor(isTrusted: isTrusted)
        case .none:
            break
        }
    }

    private func reconcileEventTap(isTrusted: Bool) {
        let hasTap = eventTap != nil
        let tapIsValid = eventTap.map(CFMachPortIsValid) ?? false
        let tapIsEnabled = tapIsValid && (eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false)

        switch Self.recoveryAction(
            isTrusted: isTrusted,
            hasTap: hasTap,
            tapIsValid: tapIsValid,
            tapIsEnabled: tapIsEnabled
        ) {
        case .waitForPermission, .none:
            break
        case .remove:
            tearDownEventTap()
        case .install, .reinstall:
            tearDownEventTap()
            createTap()
        case .reenable:
            guard let tap = eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                tearDownEventTap()
                createTap()
            }
        }
    }

    private func reconcileMediaKeyMonitor(isTrusted: Bool) {
        if isTrusted {
            if mediaKeyMonitor == nil {
                createMediaKeyMonitor()
            }
        } else {
            tearDownMediaKeyMonitor()
        }
    }

    private func createTap() {
        guard wantsMonitoring, case .keyCode = targetKey else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async {
                        monitor.reconcileAccessibility(promptIfNeeded: false)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags.intersection([
                    .maskControl,
                    .maskCommand,
                    .maskAlternate,
                    .maskShift
                ])

                if case .keyCode(let targetKeyCode) = monitor.targetKey,
                   keyCode == targetKeyCode,
                   flags == monitor.targetModifiers {
                    DispatchQueue.main.async { monitor.onTrigger() }
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            tapCreationFailureCount += 1
            if tapCreationFailureCount == 1 || tapCreationFailureCount.isMultiple(of: 30) {
                NSLog("Spacemap/Hotkey: event tap creation failed; will retry")
            }
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            tapCreationFailureCount += 1
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapCreationFailureCount = 0
        print("Spacemap: hotkey active")
    }

    private func createMediaKeyMonitor() {
        guard wantsMonitoring, case .mediaKey = targetKey else { return }
        mediaKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let self else { return }
            guard let hotkey = Hotkey.parseHotkeyFromMediaKeyEvent(event) else { return }
            if hotkey.key == self.targetKey, hotkey.modifiers == self.targetModifiers {
                DispatchQueue.main.async { self.onTrigger() }
            }
        }
    }

    private func tearDownInputMonitoring() {
        tearDownEventTap()
        tearDownMediaKeyMonitor()
    }

    private func tearDownEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            if CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func tearDownMediaKeyMonitor() {
        if let monitor = mediaKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mediaKeyMonitor = nil
    }
}
