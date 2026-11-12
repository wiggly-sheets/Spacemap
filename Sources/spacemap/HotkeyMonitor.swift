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

/// Keeps the event tap's reference to its owner weak. The tap retains this
/// box, not the owner, so the owner's deinit can still run and stop the tap.
final class WeakTapContext<Owner: AnyObject> {
    weak var owner: Owner?

    init(_ owner: Owner) {
        self.owner = owner
    }
}

final class HotkeyMonitor {
    struct KeyEventDecision: Equatable {
        let shouldConsume: Bool
        let shouldTrigger: Bool

        static let passThrough = KeyEventDecision(shouldConsume: false, shouldTrigger: false)
    }

    enum EventTapRecoveryAction: Equatable {
        case waitForPermission
        case remove
        case install
        case reinstall
        case reenable
        case none
    }

    static let healthCheckInterval: TimeInterval = HotkeyTapRouter.healthCheckInterval
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
        guard isTrusted else {
            return hasTap ? .remove : .waitForPermission
        }
        guard hasTap else { return .install }
        guard tapIsValid else { return .reinstall }
        guard tapIsEnabled else { return .reenable }
        return .none
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

        var relevantFlags = flags.intersection(Hotkey.relevantModifierFlags)
        // Hardware reports the fn flag for top-row function keys even when the
        // user thinks of the binding as a bare F-key. Ignore that hardware fn
        // only when the binding did not explicitly ask for it.
        if Hotkey.isFunctionKey(keyCode), !targetModifiers.contains(.maskSecondaryFn) {
            relevantFlags.remove(.maskSecondaryFn)
        }
        guard relevantFlags == targetModifiers.intersection(Hotkey.relevantModifierFlags) else {
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
    static let healthCheckInterval: TimeInterval = 1.0
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

    private let tapFactory: EventTapFactory
    private let trustProvider: () -> Bool
    private let promptProvider: (Bool) -> Bool
    private let stateLock = NSLock()

    private var bindings: [UUID: Binding] = [:]
    private var cachedTrust = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapContext: UnsafeMutableRawPointer?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var tapRunLoopToken = 0
    private var healthTimer: Timer?
    private var lastTrustState: Bool?
    private(set) var tapCreationFailureCount = 0
    private(set) var tapCreationAttempts = 0

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
        self.tapFactory = tapFactory
        self.trustProvider = trustProvider
        self.promptProvider = promptProvider
    }

    deinit {
        stop()
    }

    var hasTapContext: Bool { tapContext != nil }
    var isEventTapInstalled: Bool { eventTap != nil }

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
    func reconcile(promptIfNeeded: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard hasBindings else {
            tearDownEventTap()
            return
        }

        var isTrusted = trustProvider()
        if !isTrusted, promptIfNeeded, !Self.didRequestAccessibilityPrompt {
            Self.didRequestAccessibilityPrompt = true
            let isRestarting = CommandLine.arguments.contains("--restarting")
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
            tearDownEventTap()
            return
        }
        reconcileEventTap()
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        tearDownEventTap()
        lastTrustState = nil
        tapCreationFailureCount = 0
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
        guard healthTimer == nil else { return }
        let timer = Timer(timeInterval: Self.healthCheckInterval, repeats: true) { [weak self] _ in
            self?.reconcile(promptIfNeeded: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func reconcileEventTap() {
        let hasTap = eventTap != nil
        let tapIsValid = eventTap.map(CFMachPortIsValid) ?? false
        let tapIsEnabled = tapIsValid && (eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false)

        switch HotkeyMonitor.recoveryAction(
            isTrusted: true,
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
            installEventTap()
        case .reenable:
            guard let tap = eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                tearDownEventTap()
                installEventTap()
            }
        }
    }

    /// Main-thread only; see `reconcile`.
    private func installEventTap() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard wantsTap else { return }

        tapCreationAttempts += 1
        if tapContext == nil {
            let box = WeakTapContext(self)
            tapContext = Unmanaged.passRetained(box).toOpaque()
        }

        guard let tap = tapFactory(
            .cgSessionEventTap,
            .headInsertEventTap,
            .defaultTap,
            HotkeyMonitor.eventTapMask,
            Self.tapCallback,
            tapContext
        ) else {
            releaseTapContext()
            tapCreationFailureCount += 1
            if tapCreationFailureCount == 1 || tapCreationFailureCount.isMultiple(of: 30) {
                NSLog("Spacemap/Hotkey: event tap creation failed; will retry")
            }
            return
        }

        guard let runLoop = ensureTapRunLoop() else {
            CFMachPortInvalidate(tap)
            releaseTapContext()
            tapCreationFailureCount += 1
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            releaseTapContext()
            tapCreationFailureCount += 1
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CFRunLoopWakeUp(runLoop)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapCreationFailureCount = 0
        NSLog("Spacemap/Hotkey: hotkey active")
    }

    private var wantsTap: Bool {
        !bindingSnapshot().isEmpty
    }

    private func ensureTapRunLoop() -> CFRunLoop? {
        if let runLoop = tapRunLoop { return runLoop }
        // A previous start is still pending; the health timer will retry.
        guard tapThread == nil else { return nil }

        tapRunLoopToken += 1
        let token = tapRunLoopToken
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, self.tapRunLoopToken == token else {
                ready.signal()
                return
            }
            let runLoop = CFRunLoopGetCurrent()
            self.tapRunLoop = runLoop
            // A source is required for CFRunLoopRun to stay alive.
            let keepAlive = Timer(timeInterval: 3600, repeats: true) { _ in }
            RunLoop.current.add(keepAlive, forMode: .common)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "spacemap.hotkey-tap"
        tapThread = thread
        thread.start()

        guard ready.wait(timeout: .now() + 1) == .success, tapRunLoop != nil else {
            NSLog("Spacemap/Hotkey: tap thread did not start in time; will retry")
            tapRunLoopToken += 1
            tapThread = nil
            return nil
        }
        return tapRunLoop
    }

    /// Main-thread only; see `reconcile`.
    private func tearDownEventTap() {
        if let runLoop = tapRunLoop, let source = runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }

        let tap = eventTap
        let context = tapContext
        eventTap = nil
        runLoopSource = nil
        tapContext = nil

        guard let runLoop = tapRunLoop else {
            // No tap thread exists, so no callback can reference the context.
            if let tap {
                if CFMachPortIsValid(tap) {
                    CGEvent.tapEnable(tap: tap, enable: false)
                }
                CFMachPortInvalidate(tap)
            }
            if let context {
                Unmanaged<WeakTapContext<HotkeyTapRouter>>.fromOpaque(context).release()
            }
            tapThread = nil
            return
        }

        tapRunLoop = nil
        tapThread = nil
        tapRunLoopToken += 1
        // Invalidate and release on the tap thread after any in-flight
        // callback returns. Releasing from main here can race the callback.
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            if let tap, CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            if let context {
                Unmanaged<WeakTapContext<HotkeyTapRouter>>.fromOpaque(context).release()
            }
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func releaseTapContext() {
        guard let context = tapContext else { return }
        tapContext = nil
        Unmanaged<WeakTapContext<HotkeyTapRouter>>.fromOpaque(context).release()
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

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let box = Unmanaged<WeakTapContext<HotkeyTapRouter>>.fromOpaque(refcon)
            .takeUnretainedValue()
        guard let router = box.owner else { return Unmanaged.passUnretained(event) }
        return router.handle(type: type, event: event)
    }
}
