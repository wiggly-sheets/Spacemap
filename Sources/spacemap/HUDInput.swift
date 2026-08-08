import AppKit
import CoreGraphics

/// Actions that can result from HUD input handling.
enum InputAction {
    case navigate(direction: SpaceNavigationDirection)
    case enterSpaceNumber(Int)
    case showSettings
    case none
}

/// Delegate for HUDInput to report navigation and settings requests.
protocol HUDInputDelegate: AnyObject {
    func navigate(direction: SpaceNavigationDirection)
    func showSettings()
}

/// Owns CGEventTap for keyboard input and panel drag monitor.
/// Parses key events into InputAction enum, reports to delegate.
final class HUDInput {
    weak var delegate: HUDInputDelegate?

    /// Optional coordinate converter for transforming points from AppKit to Quartz coordinates
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
    private var jumpToSpaceEnabled = false
    private var dragHandlerCellFrames: [(spaceIndex: Int, frame: CGRect)] = []

    // MARK: - Navigation & timer state

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
    var onPanelDragEnded: (() -> Void)?
    private var pendingNumber = ""
    private var numberEntryTimer: Timer?

    init(panel: NSPanel?) {
        self.panel = panel
    }

    func updatePanel(_ panel: NSPanel?) {
        self.panel = panel
    }

    func updateVisibility(_ visible: Bool) {
        isVisible = visible
    }

    func updateConfig(useArrowKeys: Bool, useVimKeys: Bool, jumpToSpaceEnabled: Bool = false) {
        self.useArrowKeys = useArrowKeys
        self.useVimKeys = useVimKeys
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

    // MARK: - Auto-hide timer

    func resetAutoHideTimer() {
        guard !panelDragActive else { return }
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard !isPinned, autoHideTimeout > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideTimeout, repeats: false) { [weak self] _ in
            self?.onAutoHide?()
        }
    }

    // MARK: - Poll timer

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
                        NSLog("spacemap/HUD: poll detected change last=\(self.lastFocusedSpaceIndex ?? -1) current=\(focused ?? -1)")
                        self.onRefresh?()
                        self.resetAutoHideTimer()
                    }
                }
            }
        }
    }

    // MARK: - Navigation

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

    private func focus(space index: Int) {
        yabaiService?.focusSpaceAsync(index)
        lastFocusedSpaceIndex = index
        if let optimistic = hudStateSync?.updateFocusedIndex(index) {
            currentState = optimistic
            hudDisplay?.updateState(optimistic)
        }
        resetAutoHideTimer()
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

    // MARK: - Keyboard event tap

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
                guard AXIsProcessTrusted() else {
                    DispatchQueue.main.async {
                        input.stopSettingsKeyMonitor()
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
                if type == .keyDown {
                    let action = input.handleHUDKeyDown(event)
                    input.dispatchAction(action)
                }
                return nil
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
        if AXIsProcessTrusted() {
            startSettingsKeyMonitor()
        } else if keyboardEventTap != nil {
            NSLog("spacemap/HUDInput: Accessibility revoked; releasing keyboard capture")
            stopSettingsKeyMonitor()
        }
    }

    private func stopSettingsKeyMonitor() {
        if let source = keyboardRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = keyboardEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        keyboardRunLoopSource = nil
        keyboardEventTap = nil
    }

    /// Parses a key event into an InputAction. Does not call delegate methods directly.
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
        return .none
    }

    /// Dispatches an InputAction. Navigation is handled internally;
    /// settings requests are forwarded to the delegate.
    private func dispatchAction(_ action: InputAction) {
        switch action {
        case .navigate(let direction):
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.navigate(direction: direction)
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
