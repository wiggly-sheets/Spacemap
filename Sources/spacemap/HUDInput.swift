import AppKit
import CoreGraphics

/// Actions that can result from HUD input handling.
enum InputAction {
    case navigate(direction: SpaceNavigationDirection)
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
    private var dragHandlerCellFrames: [(spaceIndex: Int, frame: CGRect)] = []

    init(panel: NSPanel?) {
        self.panel = panel
    }

    func updatePanel(_ panel: NSPanel?) {
        self.panel = panel
    }

    func updateVisibility(_ visible: Bool) {
        isVisible = visible
    }

    func updateConfig(useArrowKeys: Bool, useVimKeys: Bool) {
        self.useArrowKeys = useArrowKeys
        self.useVimKeys = useVimKeys
    }

    func updateCellFrames(_ frames: [(spaceIndex: Int, frame: CGRect)]) {
        self.dragHandlerCellFrames = frames
    }

    func start() {
        startSettingsKeyMonitor()
    }

    func stop() {
        stopSettingsKeyMonitor()
        stopPanelDragMonitor()
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
                    // savePanelPosition() has been moved to HUDDisplay
                    // HUDWindowController should call HUDDisplay.savePanelPosition() when needed
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

    /// Dispatches an InputAction to the delegate.
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
}
