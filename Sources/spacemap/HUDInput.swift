import AppKit
import CoreGraphics

/// What one keystroke asked the HUD to do, before dispatch.
enum HUDKeyPress: Equatable {
    case command(HUDCommand)
    case number(Int)
    case showSettings
    case none
}

protocol HUDInputDelegate: AnyObject {
    /// Single entry point for a matched HUD key.
    func perform(_ command: HUDCommand)
}

final class HUDInput {
    typealias KeyboardTapRecoveryAction = EventTapHost.RecoveryAction

    weak var delegate: HUDInputDelegate?

    var quartzPointConverter: ((CGPoint) -> CGPoint)?
    /// The fixed ⌘, shortcut, which is not a configurable HUD command.
    var onShowSettings: (() -> Void)?

    private let eventTapHost: EventTapHost
    private let relaunch: () -> Void
    private var panelDragMonitor: Any?
    private var panelDragStart: CGPoint?
    private var panelDragOrigin: CGPoint?
    private var panelDragDidMove = false
    private var isPanelDragging = false

    private weak var panel: NSPanel?
    private var isVisible = false
    private var hudKeys = HUDKeyBindings.default
    private var jumpToSpaceEnabled = false
    private var dragHandlerCellFrames: [(spaceIndex: Int, frame: CGRect)] = []


    var isPinned = false
    var lastFocusedSpaceIndex: Int? = nil
    var currentState: GridState?
    var config: SpacemapConfig?
    var yabaiService: YabaiService?
    var hudStateSync: GridStateCoordinator?
    weak var hudDisplay: HUDDisplay?
    var isPollingFocusedSpace = false
    private var pollTimer: Timer?
    private var pollTicks = 0
    var onRefresh: (() -> Void)?
    /// The presenter owns auto-hide; this asks it to re-arm the timer.
    var onAutoHideActivity: (() -> Void)?
    /// Panel drags disarm auto-hide for their duration.
    var onPanelDragChanged: ((Bool) -> Void)?
    var onNumberEntry: ((HUDNumberFeedback?) -> Void)?
    var onFocusSpaceChanged: ((Int) -> Void)?
    var onPanelDragEnded: (() -> Void)?
    var onAccessibilityRevoked: (() -> Void)?
    private var didNotifyAccessibilityRevocation = false
    private var pendingNumber = ""
    private var numberEntryTimer: Timer?
    private var numberEntryGeneration = 0
    /// Trust cached from the reconciliation path. The event-tap callback runs
    /// on every keystroke and must not syscall AXIsProcessTrusted per event.
    private(set) var cachedAccessibilityTrusted = false
    /// Trust source used by reconciliation and the rare tap-disabled path.
    /// Overridable in tests; production reads the AX API.
    var accessibilityTrustProvider: () -> Bool = { AXIsProcessTrusted() }

    var isKeyboardTapInstalled: Bool { eventTapHost.isEventTapInstalled }
    var tapCreationAttempts: Int { eventTapHost.tapCreationAttempts }
    var tapCreationFailureCount: Int { eventTapHost.tapCreationFailureCount }

    init(
        panel: NSPanel?,
        tapFactory: @escaping EventTapFactory = defaultEventTapFactory,
        relaunch: @escaping () -> Void = { SystemPermissions.relaunch() }
    ) {
        self.panel = panel
        self.relaunch = relaunch
        self.eventTapHost = EventTapHost(
            logName: "spacemap/HUDInput",
            tapFactory: tapFactory
        )
        cachedAccessibilityTrusted = accessibilityTrustProvider()
    }

    func updatePanel(_ panel: NSPanel?) {
        self.panel = panel
    }

    var currentPanel: NSPanel? { panel }

    func updateVisibility(_ visible: Bool) {
        if visible, !isVisible {
            didNotifyAccessibilityRevocation = false
        }
        isVisible = visible
    }

    func updateConfig(
        hudKeys: HUDKeyBindings = .default,
        jumpToSpaceEnabled: Bool = false
    ) {
        self.hudKeys = hudKeys
        self.jumpToSpaceEnabled = jumpToSpaceEnabled
    }

    func updateCellFrames(_ frames: [(spaceIndex: Int, frame: CGRect)]) {
        self.dragHandlerCellFrames = frames
    }

    deinit {
        // Invalidate timers and tear down monitors; a retained event tap can
        // keep this object alive, but any path that does reach deinit must
        // not leave scheduled timers behind.
        stop()
    }

    func start() {
        startSettingsKeyMonitor()
        startTrustWatchdog()
    }

    func stop() {
        stopTrustWatchdog()
        stopSettingsKeyMonitor()
        stopPanelDragMonitor()
        pollTimer?.invalidate()
        pollTimer = nil
        pollTicks = 0
        clearNumberEntry()
        onStopForTesting?(pollTimer == nil)
    }

    /// Test seam: lets a test observe that deinit reached `stop()` with the
    /// poll timer invalidated.
    var onStopForTesting: ((Bool) -> Void)?

    func startPanelDragMonitor() {
        guard panelDragMonitor == nil, self.panel != nil else { return }
        panelDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let panel = self.panel, self.isVisible else { return event }
            guard let window = panel.contentView?.window else { return event }
            let loc = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            guard panel.contentView?.bounds.contains(loc) == true else { return event }

            switch event.type {
            case .leftMouseDown:
                self.beginPanelDrag(
                    start: NSEvent.mouseLocation,
                    panelOrigin: panel.frame.origin
                )
            case .leftMouseDragged:
                guard let start = self.panelDragStart,
                      let origin = self.panelDragOrigin else { break }
                let current = NSEvent.mouseLocation
                let delta = PanelPresenter.dragDelta(from: start, to: current)
                if let quartzPoint = self.quartzPointConverter?(current) {
                    let overCell = self.dragHandlerCellFrames.contains { $0.frame.contains(quartzPoint) }
                    if !overCell {
                        var newOrigin = origin
                        newOrigin.x += delta.dx
                        newOrigin.y += delta.dy
                        panel.setFrameOrigin(newOrigin)
                        self.panelDragDidMove = true
                    }
                }
            case .leftMouseUp:
                if self.endPanelDrag() {
                    self.onPanelDragEnded?()
                }
            default: break
            }
            return event
        }
    }

    /// Start a panel drag: the armed auto-hide timer must be disarmed while
    /// the mouse is down, otherwise the HUD can vanish mid-drag.
    func beginPanelDrag(start: CGPoint, panelOrigin: CGPoint) {
        panelDragStart = start
        panelDragOrigin = panelOrigin
        panelDragDidMove = false
        isPanelDragging = true
        onPanelDragChanged?(true)
    }

    /// Finish a panel drag and re-arm auto-hide. Returns whether the panel
    /// actually moved (so the caller can persist the new position).
    @discardableResult
    func endPanelDrag() -> Bool {
        let moved = panelDragDidMove
        panelDragStart = nil
        panelDragOrigin = nil
        panelDragDidMove = false
        isPanelDragging = false
        onPanelDragChanged?(false)
        return moved
    }

    func stopPanelDragMonitor() {
        if let monitor = panelDragMonitor {
            NSEvent.removeMonitor(monitor)
            panelDragMonitor = nil
        }
        panelDragStart = nil
        panelDragOrigin = nil
        panelDragDidMove = false
        isPanelDragging = false
        onPanelDragChanged?(false)
    }

    var panelDragActive: Bool { isPanelDragging }


    func startPollTimer() {
        pollTimer?.invalidate()
        pollTicks = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            // Reconcile Accessibility roughly every 3s. Revocation and
            // re-grant must recover while the HUD stays visible, and the
            // per-keystroke callback only reads the cached value.
            self.pollTicks += 1
            if self.pollTicks >= 6 {
                self.pollTicks = 0
                self.reconcileAccessibilityFromPoll()
            }
            guard !self.isPollingFocusedSpace else { return }
            self.isPollingFocusedSpace = true
            self.yabaiService?.runOnYabaiQueue { [weak self] in
                let focused = self?.yabaiService?.queryFocusedSpaceIndex()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isPollingFocusedSpace = false
                    guard self.isVisible else { return }
                    if focused != self.lastFocusedSpaceIndex {
                        self.onRefresh?()
                        self.onAutoHideActivity?()
                    }
                }
            }
        }
    }


    func navigate(direction: SpaceNavigationDirection) {
        guard let currentIdx = lastFocusedSpaceIndex, let state = currentState else { return }
        let target: Int?
        switch config?.displayNavigationWrap {
        case .within:
            let ss = state.displayIndex(forSpace: currentIdx).map { state.spaces(forDisplay: $0) } ?? state.spaces
            target = SpaceNavigator.destination(
                from: currentIdx,
                visibleSpaceIndices: SpaceNavigator.navigableSpaceIndices(
                    activeSpaceIndices: ss.map(\.index),
                    maxSpaces: config?.maxSpaces ?? 10
                ),
                columns: config?.cols ?? 8,
                direction: direction
            )
        case .between:
            target = SpaceNavigator.destinationAcrossDisplays(
                from: currentIdx,
                displaySpaceIndices: state.populatedDisplayIndices.map { state.spaces(forDisplay: $0).map(\.index) },
                maxSpaces: config?.maxSpaces ?? 10,
                columns: config?.cols ?? 8,
                direction: direction
            )
        case .none:
            target = nil
        }
        guard let target else { return }
        focus(space: target)
    }

    func navigateToFirst() { navigateToEdge { $0.first } }
    func navigateToLast() { navigateToEdge { $0.last } }

    private func navigateToEdge(_ pick: ([Int]) -> Int?) {
        guard let state = currentState else { return }
        let visible: [Int]
        switch state.config.multiMonitorHUDMode {
        case .unified:
            visible = GridLayout.visibleSpaceIndices(
                maxSpaces: state.config.maxSpaces,
                showMode: state.config.showMode,
                activeIndices: Set(state.spaces.map(\.index))
            )
        case .separate:
            guard let currentIdx = lastFocusedSpaceIndex,
                  let display = state.displayIndex(forSpace: currentIdx) else { return }
            visible = state.spaces(forDisplay: display).map(\.index)
        }
        guard let target = pick(visible) else { return }
        focus(space: target)
    }

    func focus(space index: Int) {
        yabaiService?.focusSpaceAsync(index)
        lastFocusedSpaceIndex = index
        if let optimistic = hudStateSync?.updateFocusedIndex(index) {
            currentState = optimistic
            hudDisplay?.updateState(optimistic)
        }
        onAutoHideActivity?()
        onFocusSpaceChanged?(index)
    }

    private func handleNumberEntry(_ number: Int) {
        let indices = currentState?.spaces.map(\.index) ?? []
        pendingNumber = Self.appendedNumber("\(number)", to: pendingNumber, indices: indices)
        numberEntryTimer?.invalidate()
        numberEntryGeneration += 1
        guard let outcome = Self.numberOutcome(pending: pendingNumber, indices: indices) else { return }
        onNumberEntry?(HUDNumberFeedback(number: outcome.number, exists: outcome.exists))
        // A prefix that can only be one space resolves now; waiting is only
        // needed while a longer number is still possible.
        guard !outcome.mustWait else {
            numberEntryTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.processPendingNumber()
            }
            return
        }
        processPendingNumber()
    }

    /// Appends a digit only while the result is still a number that exists or
    /// the start of a longer one. A repeated digit therefore replaces the
    /// previous entry instead of showing "44" for two presses of 4.
    static func appendedNumber(_ digit: String, to pending: String, indices: [Int]) -> String {
        let candidate = pending + digit
        if indices.contains(where: { String($0) == candidate || String($0).hasPrefix(candidate) }) {
            return candidate
        }
        return digit
    }

    /// Typed digits against the spaces that exist. `mustWait` is true while a
    /// longer space number could still share this prefix.
    static func numberOutcome(
        pending: String,
        indices: [Int]
    ) -> (number: Int, exists: Bool, mustWait: Bool)? {
        guard let number = Int(pending) else { return nil }
        let possible = indices.filter { String($0).hasPrefix(pending) }
        return (number, indices.contains(number), possible != [number])
    }

    private func processPendingNumber() {
        let enteredNumber = pendingNumber
        numberEntryTimer?.invalidate()
        numberEntryTimer = nil
        pendingNumber = ""
        numberEntryGeneration += 1
        guard let target = Int(enteredNumber) else {
            onNumberEntry?(nil)
            return
        }
        let exists = currentState?.spaces.contains(where: { $0.index == target }) == true
        // Hold the number briefly either way so a valid jump still gives
        // feedback; invalid numbers hold a little longer. The generation stops
        // an old hold from erasing a newer entry.
        onNumberEntry?(HUDNumberFeedback(number: target, exists: exists))
        let generation = numberEntryGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + (exists ? 0.4 : 0.6)) { [weak self] in
            guard let self, self.numberEntryGeneration == generation else { return }
            self.onNumberEntry?(nil)
        }
        guard exists else { return }
        NSLog("spacemap/HUD: jump to space \(target)")
        focus(space: target)
    }

    private func clearNumberEntry() {
        numberEntryTimer?.invalidate()
        numberEntryTimer = nil
        pendingNumber = ""
        numberEntryGeneration += 1
        onNumberEntry?(nil)
    }

    /// Never swallow a key the HUD does not act on. A stale or revoked tap
    /// then cannot lock out the keyboard; only HUD shortcuts are captured.
    static func shouldConsumeKeyboardEvent(
        isTrusted: Bool,
        isVisible: Bool,
        isPinned: Bool,
        type: CGEventType,
        press: HUDKeyPress
    ) -> Bool {
        guard isTrusted, isVisible else { return false }
        guard type == .keyDown else { return false }
        return press != .none
    }

    static func keyboardTapRecoveryAction(
        isTrusted: Bool,
        hasTap: Bool,
        tapIsValid: Bool,
        tapIsEnabled: Bool
    ) -> KeyboardTapRecoveryAction {
        EventTapHost.recoveryAction(
            isTrusted: isTrusted,
            hasTap: hasTap,
            tapIsValid: tapIsValid,
            tapIsEnabled: tapIsEnabled
        )
    }


    private func startSettingsKeyMonitor() {
        let trusted = accessibilityTrustProvider()
        cachedAccessibilityTrusted = trusted
        guard trusted else {
            // Revoked while a tap was installed: remove it. A stale default tap
            // can sit at the head of the session stream and stall every key.
            stopSettingsKeyMonitor()
            return
        }
        eventTapHost.install(consumer: self)
    }

    func reconcileSettingsKeyMonitor() {
        handleAccessibilityState(isTrusted: accessibilityTrustProvider())
    }

    /// Polls trust independently of HUD visibility. The event tap outlives a
    /// hidden HUD, and the visibility-gated poll cannot notice a revocation
    /// while it is hidden, so the tap would keep its cached permission until
    /// the next presentation. Runs on the main run loop at one second.
    private func startTrustWatchdog() {
        eventTapHost.startHealthTimer { [weak self] in
            self?.probeTrustWhileHidden()
        }
    }

    private func probeTrustWhileHidden() {
        let provider = accessibilityTrustProvider
        PermissionProbe.shared.check(provider: provider) { [weak self] trusted in
            guard let self else { return }
            guard trusted != self.cachedAccessibilityTrusted else {
                // Untrusted but still cached true? The tap must go regardless.
                if !trusted, self.eventTapHost.isEventTapInstalled {
                    self.handleAccessibilityState(isTrusted: false)
                }
                return
            }
            self.handleAccessibilityState(isTrusted: trusted)
        }
    }

    private func stopTrustWatchdog() {
        eventTapHost.stopHealthTimer()
    }

    /// Poll-driven reconciliation. Skip the never-trusted startup state so a
    /// user who has not granted Accessibility is not told capture was revoked
    /// (which would hide a mouse-usable HUD). Once trusted, any transition in
    /// either direction is applied.
    private func reconcileAccessibilityFromPoll() {
        guard cachedAccessibilityTrusted || eventTapHost.isEventTapInstalled else { return }
        PermissionProbe.shared.check(provider: accessibilityTrustProvider) { [weak self] trustedNow in
            guard let self,
                  trustedNow || self.cachedAccessibilityTrusted || self.eventTapHost.isEventTapInstalled else {
                return
            }
            self.handleAccessibilityState(isTrusted: trustedNow)
        }
    }

    /// Rare path: the system disabled the tap (timeout/user input). Re-check
    /// trust instead of blindly re-enabling, so a revocation disables capture
    /// and notifies the owner; a re-grant re-installs via reconciliation.
    func handleDisabledKeyboardTap(reason: CGEventType = .tapDisabledByTimeout) {
        // A tap the system disabled on behalf of the user is suspect. Drop it
        // and build a fresh one only when trust still reads true; a revoked
        // permission makes that creation fail and leaves the keyboard free.
        if reason == .tapDisabledByUserInput {
            stopSettingsKeyMonitor()
            PermissionProbe.shared.check(provider: accessibilityTrustProvider) { [weak self] trusted in
                guard let self else { return }
                if trusted {
                    self.startSettingsKeyMonitor()
                } else {
                    self.handleAccessibilityState(isTrusted: false)
                }
            }
            return
        }
        PermissionProbe.shared.check(provider: accessibilityTrustProvider) { [weak self] trusted in
            guard let self else { return }
            guard trusted else {
                self.handleAccessibilityState(isTrusted: false)
                return
            }
            self.eventTapHost.enableTap()
        }
    }

    func handleAccessibilityState(isTrusted: Bool) {
        cachedAccessibilityTrusted = isTrusted
        guard isTrusted else {
            let hadTap = eventTapHost.isEventTapInstalled
            if hadTap {
                NSLog("spacemap/HUDInput: Accessibility revoked; releasing keyboard capture")
                stopSettingsKeyMonitor()
                // A revoked TCC entry can leave the WindowServer-side tap
                // registered even after invalidation. Replacing the process is
                // the only reliable release, and it is what a manual restart
                // does today.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [relaunch] in
                    relaunch()
                }
            }
            if isVisible, !didNotifyAccessibilityRevocation {
                didNotifyAccessibilityRevocation = true
                onAccessibilityRevoked?()
            }
            return
        }

        didNotifyAccessibilityRevocation = false
        eventTapHost.reconcile(consumer: self)
    }

    private func stopSettingsKeyMonitor() {
        eventTapHost.tearDown()
    }

    func handleHUDKeyDown(_ event: CGEvent) -> HUDKeyPress {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if Self.isSettingsShortcut(keyCode: keyCode, flags: flags) {
            return .showSettings
        }
        // Legacy scalar keys were checked first, then number jumps, then the
        // `[hudKeys]` table. That order is the observable pre-merge behavior.
        if let command = hudKeys.legacyCommand(for: keyCode, flags: flags) {
            return .command(command)
        }
        if jumpToSpaceEnabled, let number = Self.numberFromKeyCode(keyCode: keyCode, flags: flags) {
            return .number(number)
        }
        if let command = hudKeys.tableCommand(for: keyCode, flags: flags) {
            return .command(command)
        }
        return .none
    }

    private func dispatch(_ press: HUDKeyPress) {
        switch press {
        case .command(let command):
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.perform(command)
            }
        case .number(let number):
            DispatchQueue.main.async { [weak self] in
                self?.handleNumberEntry(number)
            }
        case .showSettings:
            DispatchQueue.main.async { [weak self] in
                self?.onShowSettings?()
            }
        case .none:
            break
        }
    }

    static func isSettingsShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        keyCode == 43 && flags.contains(.maskCommand)
    }

    static func numberFromKeyCode(keyCode: CGKeyCode, flags: CGEventFlags) -> Int? {
        guard !flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate) else { return nil }
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        case 29: return 0
        case 82: return 0
        case 83: return 1
        case 84: return 2
        case 85: return 3
        case 86: return 4
        case 87: return 5
        case 88: return 6
        case 89: return 7
        case 91: return 8
        case 92: return 9
        default: return nil
        }
    }
}

extension HUDInput: EventTapConsumer {
    static let keyboardEventTapMask = CGEventMask(
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue)
    )

    var eventTapMask: CGEventMask { Self.keyboardEventTapMask }
    var eventTapPlacement: EventTapPlacement { .main }

    /// The keyboard tap holds the HUD for the tap's lifetime; teardown is the
    /// only release path.
    var retainsConsumerForTapLifetime: Bool { true }

    func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let isTrusted = cachedAccessibilityTrusted
        guard isTrusted else {
            eventTapHost.disableTap()
            DispatchQueue.main.async { [weak self] in
                self?.handleAccessibilityState(isTrusted: false)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleDisabledKeyboardTap(reason: type)
            return Unmanaged.passUnretained(event)
        }
        guard isVisible else { return Unmanaged.passUnretained(event) }
        var press = HUDKeyPress.none
        if type == .keyDown {
            press = handleHUDKeyDown(event)
            dispatch(press)
        }
        let shouldConsume = HUDInput.shouldConsumeKeyboardEvent(
            isTrusted: isTrusted,
            isVisible: isVisible,
            isPinned: isPinned,
            type: type,
            press: press
        )
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }
}
