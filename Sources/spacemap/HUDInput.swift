import AppKit
import CoreGraphics

/// What one keystroke asked the HUD to do, before dispatch.
enum HUDKeyPress: Equatable {
    case command(HUDCommand)
    case number(Int)
    case letter(String)
    /// A held key repeating keyDown. Consumed, but never re-enters the prefix.
    case letterRepeat
    case letterBackspace
    case letterCancel
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

    let eventTapHost: EventTapHost
    let relaunch: () -> Void
    var panelDragMonitor: Any?
    var panelDragStart: CGPoint?
    var panelDragOrigin: CGPoint?
    var panelDragDidMove = false
    var isPanelDragging = false

    weak var panel: NSPanel?
    var isVisible = false
    var hudKeys = HUDKeyBindings.default
    var jumpToSpaceEnabled = false
    var fuzzySpaceJumpEnabled = true
    var dragHandlerCellFrames: [(spaceIndex: Int, frame: CGRect)] = []


    var isPinned = false
    var lastFocusedSpaceIndex: Int? = nil
    var currentState: GridState?
    var config: SpacemapConfig?
    var yabaiService: YabaiService?
    var hudStateSync: GridStateCoordinator?
    weak var hudDisplay: HUDDisplay?
    var isPollingFocusedSpace = false
    var pollTimer: Timer?
    var pollTicks = 0
    var onRefresh: (() -> Void)?
    /// The presenter owns auto-hide; this asks it to re-arm the timer.
    var onAutoHideActivity: (() -> Void)?
    /// Panel drags disarm auto-hide for their duration.
    var onPanelDragChanged: ((Bool) -> Void)?
    var onNumberEntry: ((HUDNumberFeedback?) -> Void)?
    var onTypedText: ((HUDTypedFeedback?) -> Void)?
    var onFocusSpaceChanged: ((Int) -> Void)?
    var onPanelDragEnded: (() -> Void)?
    var onAccessibilityRevoked: (() -> Void)?
    var didNotifyAccessibilityRevocation = false
    var pendingNumber = ""
    var numberEntryTimer: Timer?
    var numberEntryGeneration = 0
    /// Letters typed for a fuzzy space-name jump. Cleared by `stop()`, so a
    /// hide never leaves a prefix behind.
    var pendingLetters = ""
    var letterEntryTimer: Timer?
    var letterEntryGeneration = 0
    /// Synchronous count of classified letter presses. `pendingLetters` is
    /// applied one main-queue turn after classification, so backspace and
    /// escape must decide against this count; otherwise a fast second key sees
    /// an empty prefix and leaks through to the focused app.
    var letterEntryCount = 0
    /// Trust cached from the reconciliation path. The event-tap callback runs
    /// on every keystroke and must not syscall AXIsProcessTrusted per event.
    var cachedAccessibilityTrusted = false
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
        jumpToSpaceEnabled: Bool = false,
        fuzzySpaceJumpEnabled: Bool = true
    ) {
        self.hudKeys = hudKeys
        self.jumpToSpaceEnabled = jumpToSpaceEnabled
        self.fuzzySpaceJumpEnabled = fuzzySpaceJumpEnabled
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
        clearLetterEntry()
        onStopForTesting?(pollTimer == nil)
    }

    /// Test seam: lets a test observe that deinit reached `stop()` with the
    /// poll timer invalidated.
    var onStopForTesting: ((Bool) -> Void)?

    /// Named spaces that still exist at jump time. A name outlives its space in
    /// config, so the current topology decides what may match. Unnamed spaces
    /// are not candidates; digits already jump by index.
    var spaceNames: [Int: String] {
        let names = currentState?.resolvedSpaceNames ?? [:]
        let existing = Set(currentState?.spaces.map(\.index) ?? [])
        return names.filter { existing.contains($0.key) }
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
