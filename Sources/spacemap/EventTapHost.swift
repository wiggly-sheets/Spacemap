import Cocoa

/// Where a tap's run loop lives. Placement also picks the teardown ordering;
/// the two orderings exist for different reasons and must not unify.
enum EventTapPlacement {
    /// Private-thread run loop; head-inserted so the tap sees events first.
    case tapThread
    /// Main run loop; tail-appended so the app never delays input.
    case main
}

/// What a consumer must tell `EventTapHost`, plus the event entry point.
/// Routing, gating, notifications and pass-through stay in the consumer.
protocol EventTapConsumer: AnyObject {
    var eventTapMask: CGEventMask { get }
    var eventTapPlacement: EventTapPlacement { get }
    var isEventTapListenOnly: Bool { get }
    /// True when the tap holds the consumer for the tap's lifetime. The HUD
    /// needs this; the hotkey router and drag handler keep a weak box so a
    /// deinit can still stop the tap.
    var retainsConsumerForTapLifetime: Bool { get }
    func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>?
}

extension EventTapConsumer {
    var isEventTapListenOnly: Bool { false }
    var retainsConsumerForTapLifetime: Bool { false }
}

/// Owns one session-level `CGEventTap`: creation, run-loop placement, teardown,
/// the one-second health timer, and the revocation recovery state machine.
final class EventTapHost {
    enum RecoveryAction: Equatable {
        case waitForPermission
        case remove
        case install
        case reinstall
        case reenable
        case none
    }

    /// Keeps the event tap's reference to its owner weak by default. The tap
    /// retains this box, not the owner, so the owner's deinit can still run and
    /// stop the tap.
    private final class TapContext {
        weak var weakConsumer: EventTapConsumer?
        private let strongConsumer: EventTapConsumer?

        init(_ consumer: EventTapConsumer, strongly: Bool) {
            strongConsumer = strongly ? consumer : nil
            weakConsumer = consumer
        }

        var consumer: EventTapConsumer? { strongConsumer ?? weakConsumer }
    }

    static func recoveryAction(
        isTrusted: Bool,
        hasTap: Bool,
        tapIsValid: Bool,
        tapIsEnabled: Bool
    ) -> RecoveryAction {
        guard isTrusted else {
            return hasTap ? .remove : .waitForPermission
        }
        guard hasTap else { return .install }
        guard tapIsValid else { return .reinstall }
        guard tapIsEnabled else { return .reenable }
        return .none
    }

    /// Cached from the consumer on install so teardown still knows the
    /// placement after the consumer's deinit has cleared its weak references.
    private var placement: EventTapPlacement = .main
    private let logName: String
    private let tapFactory: EventTapFactory

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapContext: UnsafeMutableRawPointer?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var tapRunLoopToken = 0
    private var healthTimer: Timer?
    private(set) var tapCreationFailureCount = 0
    private(set) var tapCreationAttempts = 0
    /// Bumped on every successful install; consumers that own a generation
    /// counter (the drag handler) mirror this.
    private(set) var installCount = 0

    init(
        logName: String,
        tapFactory: @escaping EventTapFactory = defaultEventTapFactory
    ) {
        self.logName = logName
        self.tapFactory = tapFactory
    }

    var hasTapContext: Bool { tapContext != nil }
    var isEventTapInstalled: Bool { eventTap != nil }
    var tapIsValid: Bool { eventTap.map(CFMachPortIsValid) ?? false }
    var tapIsEnabled: Bool {
        tapIsValid && (eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false)
    }

    // MARK: Install

    /// Creates the tap on the consumer's placement. Returns false when the tap
    /// already exists or creation failed; the health timer retries.
    @discardableResult
    func install(consumer: EventTapConsumer) -> Bool {
        guard eventTap == nil else { return false }

        placement = consumer.eventTapPlacement
        let place: CGEventTapPlacement = placement == .tapThread
            ? .headInsertEventTap
            : .tailAppendEventTap
        let options: CGEventTapOptions = consumer.isEventTapListenOnly
            ? .listenOnly
            : .defaultTap

        tapCreationAttempts += 1
        let box = TapContext(
            consumer,
            strongly: consumer.retainsConsumerForTapLifetime
        )
        tapContext = Unmanaged.passRetained(box).toOpaque()

        guard let tap = tapFactory(
            .cgSessionEventTap,
            place,
            options,
            consumer.eventTapMask,
            Self.tapCallback,
            tapContext
        ) else {
            releaseTapContext()
            recordFailure()
            return false
        }

        guard let runLoop = runLoopForInstall() else {
            CFMachPortInvalidate(tap)
            releaseTapContext()
            recordFailure()
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            releaseTapContext()
            recordFailure()
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        if placement == .tapThread { CFRunLoopWakeUp(runLoop) }
        CGEvent.tapEnable(tap: tap, enable: true)
        tapCreationFailureCount = 0
        installCount += 1
        NSLog("%@: event tap active", logName)
        return true
    }

    private func recordFailure() {
        tapCreationFailureCount += 1
        if tapCreationFailureCount == 1 || tapCreationFailureCount.isMultiple(of: 30) {
            NSLog("%@: event tap creation failed; will retry", logName)
        }
    }

    private func runLoopForInstall() -> CFRunLoop? {
        switch placement {
        case .main:
            return CFRunLoopGetMain()
        case .tapThread:
            return ensureTapRunLoop()
        }
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
        thread.name = "spacemap.event-tap"
        tapThread = thread
        thread.start()

        guard ready.wait(timeout: .now() + 1) == .success, tapRunLoop != nil else {
            NSLog("%@: tap thread did not start in time; will retry", logName)
            tapRunLoopToken += 1
            tapThread = nil
            return nil
        }
        return tapRunLoop
    }

    // MARK: Teardown

    func tearDown() {
        switch placement {
        case .tapThread:
            tearDownTapThreadTap()
        case .main:
            tearDownMainLoopTap()
        }
    }

    private func tearDownTapThreadTap() {
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
                Unmanaged<TapContext>.fromOpaque(context).release()
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
                Unmanaged<TapContext>.fromOpaque(context).release()
            }
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func tearDownMainLoopTap() {
        // Disable before detaching the source; a tap with no callback stalls
        // the session event stream.
        if let tap = eventTap {
            if CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        releaseTapContext()
    }

    private func releaseTapContext() {
        guard let context = tapContext else { return }
        tapContext = nil
        Unmanaged<TapContext>.fromOpaque(context).release()
    }

    // MARK: Reconciliation

    /// Applies the recovery state machine for a consumer that already knows
    /// trust. Taps are created, replaced, and re-enabled here; trust checks and
    /// their logging stay in the consumer.
    @discardableResult
    func reconcile(consumer: EventTapConsumer) -> RecoveryAction {
        let action = Self.recoveryAction(
            isTrusted: true,
            hasTap: eventTap != nil,
            tapIsValid: tapIsValid,
            tapIsEnabled: tapIsEnabled
        )

        switch action {
        case .waitForPermission, .none:
            break
        case .remove:
            tearDown()
        case .install, .reinstall:
            tearDown()
            install(consumer: consumer)
        case .reenable:
            guard let tap = eventTap else { return action }
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                tearDown()
                install(consumer: consumer)
            }
        }
        return action
    }

    func enableTap() {
        guard let tap = eventTap, CFMachPortIsValid(tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func disableTap() {
        guard let tap = eventTap, CFMachPortIsValid(tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
    }

    // MARK: Health timer

    static let healthCheckInterval: TimeInterval = 1.0

    func startHealthTimer(_ tick: @escaping () -> Void) {
        guard healthTimer == nil else { return }
        let timer = Timer(
            timeInterval: Self.healthCheckInterval,
            repeats: true
        ) { _ in tick() }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    func resetFailureCount() {
        tapCreationFailureCount = 0
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let box = Unmanaged<TapContext>.fromOpaque(refcon).takeUnretainedValue()
        guard let consumer = box.consumer else { return Unmanaged.passUnretained(event) }
        return consumer.handleTapEvent(type: type, event: event)
    }
}
