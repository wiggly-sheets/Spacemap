import Cocoa

protocol HotkeyMonitoring: AnyObject {
    func start()
    func stop()
}

extension HotkeyMonitor: HotkeyMonitoring {}

protocol HotkeyMonitorBuilding {
    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitoring
}

typealias EventTapFactory = (
    CGEventTapLocation,
    CGEventTapPlacement,
    CGEventTapOptions,
    CGEventMask,
    CGEventTapCallBack,
    UnsafeMutableRawPointer?
) -> CFMachPort?

let defaultEventTapFactory: EventTapFactory = { tap, place, options, mask, callback, userInfo in
    CGEvent.tapCreate(
        tap: tap,
        place: place,
        options: options,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: userInfo
    )
}

final class HotkeyMonitor {
    struct KeyEventDecision: Equatable {
        let shouldConsume: Bool
        let shouldTrigger: Bool

        static let passThrough = KeyEventDecision(shouldConsume: false, shouldTrigger: false)
    }

    typealias EventTapRecoveryAction = EventTapHost.RecoveryAction

    static let systemDefinedEventRawValue: UInt32 = 14
    static let eventTapMask: CGEventMask = {
        (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue))
            | (CGEventMask(1) << CGEventMask(systemDefinedEventRawValue))
    }()

    private let targetKey: HotkeyKey
    private let targetModifiers: CGEventFlags
    private let onTrigger: () -> Void
    private let router: HotkeyTapRouter
    private let bindingID = UUID()
    private var isRegistered = false

    init(
        config: HotkeyConfig,
        onTrigger: @escaping () -> Void,
        router: HotkeyTapRouter = .shared
    ) {
        self.targetKey = config.key
        self.targetModifiers = config.modifiers
        self.onTrigger = onTrigger
        self.router = router
    }

    deinit {
        stop()
    }

    func start() {
        if case .none = targetKey { return }
        if isRegistered {
            router.reconcile(promptIfNeeded: false)
            return
        }
        isRegistered = true
        router.addBinding(
            id: bindingID,
            key: targetKey,
            modifiers: targetModifiers
        ) { [weak self] in
            self?.onTrigger()
        }
    }

    func stop() {
        guard isRegistered else { return }
        isRegistered = false
        router.removeBinding(id: bindingID)
    }

    static func recoveryAction(
        isTrusted: Bool,
        hasTap: Bool,
        tapIsValid: Bool,
        tapIsEnabled: Bool
    ) -> EventTapRecoveryAction {
        EventTapHost.recoveryAction(
            isTrusted: isTrusted,
            hasTap: hasTap,
            tapIsValid: tapIsValid,
            tapIsEnabled: tapIsEnabled
        )
    }

    static func keyEventDecision(
        isTrusted: Bool,
        type: CGEventType,
        isAutoRepeat: Bool,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        targetKey: HotkeyKey,
        targetModifiers: CGEventFlags
    ) -> KeyEventDecision {
        guard isTrusted, type == .keyDown || type == .keyUp else { return .passThrough }
        guard case .keyCode(let targetKeyCode) = targetKey, keyCode == targetKeyCode else {
            return .passThrough
        }
        guard Hotkey.modifierMatches(
            keyCode: keyCode,
            eventFlags: flags,
            bindingModifiers: targetModifiers
        ) else {
            return .passThrough
        }
        return KeyEventDecision(
            shouldConsume: true,
            shouldTrigger: type == .keyDown && !isAutoRepeat
        )
    }

    static func mediaKeyDecision(
        eventHotkey: HotkeyConfig,
        targetKey: HotkeyKey,
        targetModifiers: CGEventFlags
    ) -> KeyEventDecision {
        guard case .mediaKey = eventHotkey.key, case .mediaKey = targetKey else {
            return .passThrough
        }
        guard eventHotkey.key == targetKey, eventHotkey.modifiers == targetModifiers else {
            return .passThrough
        }
        return KeyEventDecision(shouldConsume: true, shouldTrigger: true)
    }

    static func mediaKeyHotkey(from event: CGEvent) -> HotkeyConfig? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        return Hotkey.parseHotkeyFromMediaKeyEvent(nsEvent)
    }
}

/// One session-level event tap serving every hotkey binding. The tap runs on a
/// private thread and run loop so head-insert keyboard events never wait on
/// main-thread work. Accessibility trust is cached and refreshed by the 1s
/// reconciliation pass instead of queried per event.
final class HotkeyTapRouter {
    struct Binding {
        let key: HotkeyKey
        let modifiers: CGEventFlags
        let onTrigger: () -> Void
    }

    static let shared = HotkeyTapRouter()
    private static var didRequestAccessibilityPrompt = false
    private static let recordingLock = NSLock()
    private static var recordingFlag = false

    /// Lets a shortcut recorder observe media keys instead of the tap
    /// consuming them. MenuBar/Settings must set this around recording.
    static var isRecording: Bool {
        get {
            recordingLock.lock()
            defer { recordingLock.unlock() }
            return recordingFlag
        }
        set {
            recordingLock.lock()
            recordingFlag = newValue
            recordingLock.unlock()
        }
    }

    private let trustProvider: () -> Bool
    private let promptProvider: (Bool) -> Bool
    private let stateLock = NSLock()
    private let eventTapHost: EventTapHost

    private var bindings: [UUID: Binding] = [:]
    private var cachedTrust = false
    private var lastTrustState: Bool?

    init(
        tapFactory: @escaping EventTapFactory = defaultEventTapFactory,
        trustProvider: @escaping () -> Bool = { AXIsProcessTrusted() },
        promptProvider: @escaping (Bool) -> Bool = { isRestarting in
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: !isRestarting
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.trustProvider = trustProvider
        self.promptProvider = promptProvider
        self.eventTapHost = EventTapHost(
            logName: "Spacemap/Hotkey",
            tapFactory: tapFactory
        )
    }

    deinit {
        stop()
    }

    var hasTapContext: Bool { eventTapHost.hasTapContext }
    var isEventTapInstalled: Bool { eventTapHost.isEventTapInstalled }
    var tapCreationFailureCount: Int { eventTapHost.tapCreationFailureCount }
    var tapCreationAttempts: Int { eventTapHost.tapCreationAttempts }

    var registeredBindingCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return bindings.count
    }

    func addBinding(
        id: UUID,
        key: HotkeyKey,
        modifiers: CGEventFlags,
        onTrigger: @escaping () -> Void
    ) {
        if case .none = key { return }

        stateLock.lock()
        bindings[id] = Binding(key: key, modifiers: modifiers, onTrigger: onTrigger)
        stateLock.unlock()

        startHealthTimer()
        reconcile(promptIfNeeded: true)
    }

    func removeBinding(id: UUID) {
        stateLock.lock()
        bindings.removeValue(forKey: id)
        let isEmpty = bindings.isEmpty
        stateLock.unlock()

        if isEmpty { stop() }
    }

    /// Main-thread only: the tap, its run loop, and the health timer are all
    /// main-thread state. The tap callback itself runs on `tapThread`.
    /// Timer path: ask TCC off the main thread so a revocation cannot block
    /// the event stream, then apply the answer here.
    private func probeTrustAndReconcile() {
        let provider = trustProvider
        PermissionProbe.shared.check(provider: provider) { [weak self] isTrusted in
            guard let self else { return }
            self.setTrustState(isTrusted)
            if self.lastTrustState != isTrusted {
                NSLog(isTrusted
                    ? "Spacemap/Hotkey: accessibility granted"
                    : "Spacemap/Hotkey: accessibility unavailable; waiting for permission")
                self.lastTrustState = isTrusted
            }
            guard isTrusted else {
                self.eventTapHost.tearDown()
                return
            }
            self.reconcileEventTap()
        }
    }

    func reconcile(promptIfNeeded: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard hasBindings else {
            eventTapHost.tearDown()
            return
        }

        var isTrusted = trustProvider()
        if !isTrusted, promptIfNeeded, !Self.didRequestAccessibilityPrompt {
            Self.didRequestAccessibilityPrompt = true
            let isRestarting = CLIFlagTable.contains(.restarting, in: CommandLine.arguments)
            isTrusted = promptProvider(isRestarting)
        }
        setTrustState(isTrusted)

        if lastTrustState != isTrusted {
            NSLog(isTrusted
                ? "Spacemap/Hotkey: accessibility granted"
                : "Spacemap/Hotkey: accessibility unavailable; waiting for permission")
            lastTrustState = isTrusted
        }

        guard isTrusted else {
            eventTapHost.tearDown()
            return
        }
        reconcileEventTap()
    }

    func stop() {
        eventTapHost.stopHealthTimer()
        eventTapHost.tearDown()
        lastTrustState = nil
        eventTapHost.resetFailureCount()
    }

    private var hasBindings: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !bindings.isEmpty
    }

    private func bindingSnapshot() -> [Binding] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Array(bindings.values)
    }

    private func setTrustState(_ isTrusted: Bool) {
        stateLock.lock()
        cachedTrust = isTrusted
        stateLock.unlock()
    }

    private func currentTrustState() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedTrust
    }

    private func startHealthTimer() {
        eventTapHost.startHealthTimer { [weak self] in
            self?.probeTrustAndReconcile()
        }
    }

    private func reconcileEventTap() {
        guard hasBindings else {
            eventTapHost.tearDown()
            return
        }
        eventTapHost.reconcile(consumer: self)
    }

    /// Internal so routing decisions can be tested without a real tap.
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                self?.reconcile(promptIfNeeded: false)
            }
            return Unmanaged.passUnretained(event)
        }

        guard currentTrustState() else {
            // Trust is refreshed by the 1s reconciliation pass; do not query
            // TCC from the event stream.
            DispatchQueue.main.async { [weak self] in
                self?.reconcile(promptIfNeeded: false)
            }
            return Unmanaged.passUnretained(event)
        }

        // The Settings recorder needs to observe raw events while recording:
        // pass every kind through, triggering and consuming nothing.
        guard !Self.isRecording else { return Unmanaged.passUnretained(event) }

        let snapshot = bindingSnapshot()
        guard !snapshot.isEmpty else { return Unmanaged.passUnretained(event) }

        if type == .keyDown || type == .keyUp {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            var shouldConsume = false
            var exactTriggers: [() -> Void] = []
            var normalizedTriggers: [() -> Void] = []

            for binding in snapshot {
                let decision = HotkeyMonitor.keyEventDecision(
                    isTrusted: true,
                    type: type,
                    isAutoRepeat: isAutoRepeat,
                    keyCode: keyCode,
                    flags: event.flags,
                    targetKey: binding.key,
                    targetModifiers: binding.modifiers
                )
                if decision.shouldTrigger {
                    if Self.isExactModifierMatch(flags: event.flags, binding: binding) {
                        exactTriggers.append(binding.onTrigger)
                    } else {
                        normalizedTriggers.append(binding.onTrigger)
                    }
                }
                if decision.shouldConsume {
                    shouldConsume = true
                }
            }

            // An explicit fn+F-key binding wins over a bare F-key binding that
            // only matched because hardware reports fn.
            let triggers = exactTriggers.isEmpty ? normalizedTriggers : exactTriggers
            for trigger in triggers {
                DispatchQueue.main.async(execute: trigger)
            }
            return shouldConsume ? nil : Unmanaged.passUnretained(event)
        }

        if type.rawValue == HotkeyMonitor.systemDefinedEventRawValue {
            guard let hotkey = HotkeyMonitor.mediaKeyHotkey(from: event) else {
                return Unmanaged.passUnretained(event)
            }
            var shouldConsume = false
            for binding in snapshot {
                let decision = HotkeyMonitor.mediaKeyDecision(
                    eventHotkey: hotkey,
                    targetKey: binding.key,
                    targetModifiers: binding.modifiers
                )
                if decision.shouldTrigger {
                    DispatchQueue.main.async(execute: binding.onTrigger)
                }
                if decision.shouldConsume {
                    shouldConsume = true
                }
            }
            return shouldConsume ? nil : Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private static func isExactModifierMatch(flags: CGEventFlags, binding: Binding) -> Bool {
        guard case .keyCode = binding.key else { return false }
        return flags.intersection(Hotkey.relevantModifierFlags) == binding.modifiers
    }
}

extension HotkeyTapRouter: EventTapConsumer {
    var eventTapMask: CGEventMask { HotkeyMonitor.eventTapMask }
    var eventTapPlacement: EventTapPlacement { .tapThread }

    func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        handle(type: type, event: event)
    }
}
