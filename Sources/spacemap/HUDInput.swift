import AppKit
import CoreGraphics

enum InputAction: Equatable {
    case navigate(direction: SpaceNavigationDirection)
    case navigateFirst
    case navigateLast
    case closeHUD
    case focusRecent
    case enterSpaceNumber(Int)
    case showSettings
    case none
}

protocol HUDInputDelegate: AnyObject {
    func navigate(direction: SpaceNavigationDirection)
    func navigateToFirst()
    func navigateToLast()
    func closeHUD()
    func focusRecent()
    func showSettings()
}

final class HUDInput {
    enum KeyboardTapRecoveryAction: Equatable {
        case waitForPermission
        case remove
        case install
        case reinstall
        case reenable
        case none
    }

    weak var delegate: HUDInputDelegate?

    var quartzPointConverter: ((CGPoint) -> CGPoint)?

    private var keyboardEventTap: CFMachPort?
    private var keyboardRunLoopSource: CFRunLoopSource?
    private var panelDragMonitor: Any?
    private var panelDragStart: CGPoint?
    private var panelDragOrigin: CGPoint?
    private var panelDragDidMove = false
    private var isPanelDragging = false

    private weak var panel: NSPanel?
    private var isVisible = false
    private var useArrowKeys = false
    private var useVimKeys = false
    private var useExtendedKeys = false
    private var jumpToSpaceEnabled = false
    private var dragHandlerCellFrames: [(spaceIndex: Int, frame: CGRect)] = []


    var isPinned = false
    var autoHideTimeout: TimeInterval = 0
    private var autoHideTimer: Timer?
    var lastFocusedSpaceIndex: Int? = nil
    var currentState: GridState?
    var config: GridConfig?
    var yabaiService: YabaiService?
    var hudStateSync: HUDStateSync?
    weak var hudDisplay: HUDDisplay?
    var isPollingFocusedSpace = false
    private var pollTimer: Timer?
    var onRefresh: (() -> Void)?
    var onAutoHide: (() -> Void)?
    var onNumberEntry: ((Int?) -> Void)?
    var onFocusSpaceChanged: ((Int) -> Void)?
    var onPanelDragEnded: (() -> Void)?
    var onAccessibilityRevoked: (() -> Void)?
    private var didNotifyAccessibilityRevocation = false
    private var pendingNumber = ""
    private var numberEntryTimer: Timer?

    init(panel: NSPanel?) {
        self.panel = panel
    }

    func updatePanel(_ panel: NSPanel?) {
        self.panel = panel
    }

    func updateVisibility(_ visible: Bool) {
        if visible, !isVisible {
            didNotifyAccessibilityRevocation = false
        }
        isVisible = visible
    }

    func updateConfig(useArrowKeys: Bool, useVimKeys: Bool, useExtendedKeys: Bool = true, jumpToSpaceEnabled: Bool = false) {
        self.useArrowKeys = useArrowKeys
        self.useVimKeys = useVimKeys
        self.useExtendedKeys = useExtendedKeys
        self.jumpToSpaceEnabled = jumpToSpaceEnabled
    }

    func updateCellFrames(_ frames: [(spaceIndex: Int, frame: CGRect)]) {
        self.dragHandlerCellFrames = frames
    }

    deinit {
        stopSettingsKeyMonitor()
        stopPanelDragMonitor()
    }

    func start() {
        startSettingsKeyMonitor()
    }

    func stop() {
        stopSettingsKeyMonitor()
        stopPanelDragMonitor()
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        clearNumberEntry()
    }

    func startPanelDragMonitor() {
        guard panelDragMonitor == nil, self.panel != nil else { return }
        panelDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let panel = self.panel, self.isVisible else { return event }
            guard let window = panel.contentView?.window else { return event }
            let loc = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            guard panel.contentView?.bounds.contains(loc) == true else { return event }

            switch event.type {
            case .leftMouseDown:
                self.panelDragStart = NSEvent.mouseLocation
                self.panelDragOrigin = panel.frame.origin
                self.panelDragDidMove = false
                self.isPanelDragging = true
            case .leftMouseDragged:
                guard let start = self.panelDragStart,
                      let origin = self.panelDragOrigin else { break }
                let current = NSEvent.mouseLocation
                let dx = current.x - start.x
                let dy = current.y - start.y
                if let quartzPoint = self.quartzPointConverter?(current) {
                    let overCell = self.dragHandlerCellFrames.contains { $0.frame.contains(quartzPoint) }
                    if !overCell {
                        var newOrigin = origin
                        newOrigin.x += dx
                        newOrigin.y += dy
                        panel.setFrameOrigin(newOrigin)
                        self.panelDragDidMove = true
                    }
                }
            case .leftMouseUp:
                if self.panelDragDidMove {
                    self.onPanelDragEnded?()
                }
                self.panelDragStart = nil
                self.panelDragOrigin = nil
                self.panelDragDidMove = false
                self.isPanelDragging = false
            default: break
            }
            return event
        }
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
    }

    var panelDragActive: Bool { isPanelDragging }


    func resetAutoHideTimer() {
        guard !panelDragActive else { return }
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard !isPinned, autoHideTimeout > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideTimeout, repeats: false) { [weak self] _ in
            self?.onAutoHide?()
        }
    }


    func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.reconcileSettingsKeyMonitor()
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
                        self.resetAutoHideTimer()
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
            // Use actual active space indices from yabai, not HUD visible indices
            let activeIndices = state.spaces.map(\.index).sorted()
            if state.config.showMode == .active {
                visible = activeIndices
            } else {
                // For "all" mode, still use actual active spaces for edge navigation
                // to avoid jumping to non-existent placeholder spaces
                visible = activeIndices
            }
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
        resetAutoHideTimer()
        onFocusSpaceChanged?(index)
    }

    private func handleNumberEntry(_ number: Int) {
        pendingNumber.append("\(number)")
        onNumberEntry?(Int(pendingNumber))
        numberEntryTimer?.invalidate()
        numberEntryTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.processPendingNumber()
        }
    }

    private func processPendingNumber() {
        let enteredNumber = pendingNumber
        clearNumberEntry()
        guard let target = Int(enteredNumber),
              let state = currentState,
              state.spaces.contains(where: { $0.index == target }) else { return }
        NSLog("spacemap/HUD: jump to space \(target)")
        focus(space: target)
    }

    private func clearNumberEntry() {
        numberEntryTimer?.invalidate()
        numberEntryTimer = nil
        pendingNumber = ""
        onNumberEntry?(nil)
    }

    static func shouldConsumeKeyboardEvent(
        isTrusted: Bool,
        isVisible: Bool,
        isPinned: Bool,
        type: CGEventType,
        action: InputAction
    ) -> Bool {
        guard isTrusted, isVisible else { return false }
        guard type == .keyDown || type == .keyUp else { return false }
        guard isPinned else { return true }
        guard type == .keyDown else { return false }
        switch action {
        case .none:
            return false
        case .navigate, .navigateFirst, .navigateLast, .closeHUD, .focusRecent, .enterSpaceNumber, .showSettings:
            return true
        }
    }

    static func keyboardTapRecoveryAction(
        isTrusted: Bool,
        hasTap: Bool,
        tapIsValid: Bool,
        tapIsEnabled: Bool
    ) -> KeyboardTapRecoveryAction {
        guard isTrusted else { return hasTap ? .remove : .waitForPermission }
        guard hasTap else { return .install }
        guard tapIsValid else { return .reinstall }
        guard tapIsEnabled else { return .reenable }
        return .none
    }


    private func startSettingsKeyMonitor() {
        guard keyboardEventTap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let input = Unmanaged<HUDInput>.fromOpaque(refcon).takeUnretainedValue()
                let isTrusted = AXIsProcessTrusted()
                guard isTrusted else {
                    if let tap = input.keyboardEventTap, CFMachPortIsValid(tap) {
                        CGEvent.tapEnable(tap: tap, enable: false)
                    }
                    DispatchQueue.main.async {
                        input.handleAccessibilityState(isTrusted: false)
                    }
                    return Unmanaged.passUnretained(event)
                }
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = input.keyboardEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard input.isVisible else { return Unmanaged.passUnretained(event) }
                var action = InputAction.none
                if type == .keyDown {
                    action = input.handleHUDKeyDown(event)
                    input.dispatchAction(action)
                }
                let shouldConsume = HUDInput.shouldConsumeKeyboardEvent(
                    isTrusted: isTrusted,
                    isVisible: input.isVisible,
                    isPinned: input.isPinned,
                    type: type,
                    action: action
                )
                return shouldConsume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("spacemap/HUDInput: keyboard capture event tap creation failed")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        keyboardEventTap = tap
        keyboardRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func reconcileSettingsKeyMonitor() {
        handleAccessibilityState(isTrusted: AXIsProcessTrusted())
    }

    func handleAccessibilityState(isTrusted: Bool) {
        guard isTrusted else {
            if keyboardEventTap != nil {
                NSLog("spacemap/HUDInput: Accessibility revoked; releasing keyboard capture")
                stopSettingsKeyMonitor()
            }
            if isVisible, !didNotifyAccessibilityRevocation {
                didNotifyAccessibilityRevocation = true
                onAccessibilityRevoked?()
            }
            return
        }

        didNotifyAccessibilityRevocation = false
        let tapIsValid = keyboardEventTap.map(CFMachPortIsValid) ?? false
        let tapIsEnabled = tapIsValid && (keyboardEventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false)
        switch Self.keyboardTapRecoveryAction(
            isTrusted: true,
            hasTap: keyboardEventTap != nil,
            tapIsValid: tapIsValid,
            tapIsEnabled: tapIsEnabled
        ) {
        case .waitForPermission, .remove, .none:
            break
        case .install:
            startSettingsKeyMonitor()
        case .reinstall:
            stopSettingsKeyMonitor()
            startSettingsKeyMonitor()
        case .reenable:
            guard let tap = keyboardEventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                stopSettingsKeyMonitor()
                startSettingsKeyMonitor()
            }
        }
    }

    private func stopSettingsKeyMonitor() {
        if let source = keyboardRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = keyboardEventTap {
            if CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            CFMachPortInvalidate(tap)
        }
        keyboardRunLoopSource = nil
        keyboardEventTap = nil
    }

    func handleHUDKeyDown(_ event: CGEvent) -> InputAction {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if Self.isSettingsShortcut(keyCode: keyCode, flags: flags) {
            return .showSettings
        }
        if jumpToSpaceEnabled, let number = Self.numberFromKeyCode(keyCode: keyCode, flags: flags) {
            return .enterSpaceNumber(number)
        }
        if let direction = Self.navigationDirection(
            keyCode: keyCode,
            flags: flags,
            useArrowKeys: useArrowKeys,
            useVimKeys: useVimKeys
        ) {
            return .navigate(direction: direction)
        }
        if let action = Self.extendedKeyAction(
            keyCode: keyCode,
            flags: flags,
            useExtendedKeys: useExtendedKeys
        ) {
            return action
        }
        return .none
    }

    private func dispatchAction(_ action: InputAction) {
        switch action {
        case .navigate(let direction):
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.navigate(direction: direction)
            }
        case .navigateFirst:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.navigateToFirst()
            }
        case .navigateLast:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.navigateToLast()
            }
        case .closeHUD:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.closeHUD()
            }
        case .focusRecent:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.focusRecent()
            }
        case .showSettings:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.showSettings()
            }
        case .enterSpaceNumber(let number):
            DispatchQueue.main.async { [weak self] in
                self?.handleNumberEntry(number)
            }
        case .none:
            break
        }
    }

    static func isSettingsShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        keyCode == 43 && flags.contains(.maskCommand)
    }

    static func navigationDirection(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        useArrowKeys: Bool,
        useVimKeys: Bool
    ) -> SpaceNavigationDirection? {
        guard !flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate) else { return nil }
        if useArrowKeys {
            switch keyCode {
            case 123: return .left
            case 124: return .right
            case 125: return .down
            case 126: return .up
            default: break
            }
        }
        if useVimKeys {
            switch keyCode {
            case 38: return .down
            case 40: return .up
            case 37: return .right
            case 4: return .left
            default: break
            }
        }
        return nil
    }

    /// n/p/f/e/r/esc/c — aliases for arrow navigation plus grid-edge jumps,
    /// recent-space switch and close. `n`/`p` are plain aliases of the
    /// left/right arrows.
    static func extendedKeyAction(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        useExtendedKeys: Bool
    ) -> InputAction? {
        guard useExtendedKeys,
              !flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate) else { return nil }
        switch keyCode {
        case 45: return .navigate(direction: .right) // n
        case 35: return .navigate(direction: .left)  // p
        case 3: return .navigateFirst                // f
        case 14: return .navigateLast                // e
        case 15: return .focusRecent                 // r
        case 53: return .closeHUD                    // esc
        case 8: return .closeHUD                     // c
        default: return nil
        }
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
