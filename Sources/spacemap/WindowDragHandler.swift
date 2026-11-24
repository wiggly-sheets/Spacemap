import Cocoa

func shouldRecoverWindowDragEventTap(for type: CGEventType) -> Bool {
    type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
}

/// A layer-0 on-screen window as reported by the WindowServer. Bounds are in
/// Quartz screen coordinates, matching CGEvent and yabai frames.
struct CGWindowSample: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
}
class WindowDragHandler: WindowDragService {
    static let dragThreshold: CGFloat = 5
    static let titleBarHeight: CGFloat = 30
    static let dragEventTapMask = CGEventMask(
        (1 << CGEventType.leftMouseDragged.rawValue) |
        (1 << CGEventType.leftMouseUp.rawValue) |
        (1 << CGEventType.leftMouseDown.rawValue)
    )

    var onHoverCell: ((Int?) -> Void)?
    var onDropInCell: ((Int, Int, CGEventFlags) -> Void)?
    var onRequestDragSnapshot: ((Int) -> Void)?

    let frontmostApplicationName: () -> String?
    let frontmostApplicationPID: () -> Int32?
    let permissionCheck: () -> Bool
    let permissionCacheInterval: TimeInterval
    let cgWindowListProvider: () -> [CGWindowSample]
    let cgWindowSampleInterval: TimeInterval
    let eventTapHost: EventTapHost

    var wantsEventTap = false
    var eventTapGeneration = 0
    var dragSnapshotGeneration = 0
    var dragSnapshotReady = true
    var lastPermissionState: Bool?
    var cachedPermission: Bool?
    var lastPermissionCheckTime: TimeInterval = 0
    var mouseDownCGWindow: CGWindowSample?
    var lastCGWindowSample: [CGWindowSample] = []
    var lastCGWindowSampleTime: TimeInterval = 0

    enum DragDelivery {
        case hover(Int?)
        case drop(windowID: Int, cell: Int, modifiers: CGEventFlags)
    }

    var pendingDelivery: DragDelivery?
    var isDeliveryScheduled = false
    var deliveryGeneration = 0

    var cellFrames: [(spaceIndex: Int, frame: CGRect)] = []
    var cachedWindows: [YabaiWindow] = []
    var focusedWindowIDAtOpen: Int? = nil

    var lastHoveredCell: Int? = nil
    var draggedWindowID: Int? = nil
    var dragStartPoint: CGPoint? = nil
    var frontmostAppAtMouseDown: String? = nil
    var frontmostPIDAtMouseDown: Int32? = nil
    var isDragging = false

    var dragState: DragState {
        guard dragStartPoint != nil else { return .idle }
        return .dragging(
            isDragging: isDragging,
            draggedWindowID: draggedWindowID,
            lastHoveredCell: lastHoveredCell,
            frontmostAppAtMouseDown: frontmostAppAtMouseDown
        )
    }

    var isEventTapRequested: Bool { wantsEventTap }
    var hasTapContext: Bool { eventTapHost.hasTapContext }
    var tapCreationFailureCount: Int { eventTapHost.tapCreationFailureCount }
    var tapCreationAttempts: Int { eventTapHost.tapCreationAttempts }

    init(
        frontmostApplicationName: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.localizedName
        },
        frontmostApplicationPID: @escaping () -> Int32? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        permissionCheck: @escaping () -> Bool = {
            CGPreflightListenEventAccess() || AXIsProcessTrusted()
        },
        permissionCacheInterval: TimeInterval = 1.0,
        eventTapFactory: @escaping EventTapFactory = defaultEventTapFactory,
        cgWindowListProvider: @escaping () -> [CGWindowSample] = WindowDragHandler.onScreenWindows,
        cgWindowSampleInterval: TimeInterval = 0.05
    ) {
        self.frontmostApplicationName = frontmostApplicationName
        self.frontmostApplicationPID = frontmostApplicationPID
        self.permissionCheck = permissionCheck
        self.permissionCacheInterval = permissionCacheInterval
        self.cgWindowListProvider = cgWindowListProvider
        self.cgWindowSampleInterval = cgWindowSampleInterval
        self.eventTapHost = EventTapHost(
            logName: "Spacemap/Drag",
            tapFactory: eventTapFactory
        )
    }

    deinit {
        stop()
    }

    func updateInput(_ input: WindowDragInput) {
        cellFrames = input.cellFrames
        cachedWindows = input.cachedWindows
        focusedWindowIDAtOpen = input.focusedWindowIDAtOpen
    }

    func start() {
        if !wantsEventTap {
            wantsEventTap = true
            eventTapGeneration += 1
        }
        startHealthTimer()
        reconcileEventTap()
    }

    func stop() {
        wantsEventTap = false
        eventTapGeneration += 1
        eventTapHost.stopHealthTimer()
        lastPermissionState = nil
        cachedPermission = nil
        // Deliver the clear before invalidating queued delivery, otherwise a
        // visible drop target survives teardown.
        cancelHoverForTeardown()
        invalidateQueuedDelivery()
        eventTapHost.tearDown()
        reset()
    }

}

extension WindowDragHandler: EventTapConsumer {
    var eventTapMask: CGEventMask { Self.dragEventTapMask }
    var eventTapPlacement: EventTapPlacement { .main }
    var isEventTapListenOnly: Bool { true }

    func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if Self.shouldRecoverEventTap(for: type) {
            let generation = eventTapGeneration
            DispatchQueue.main.async { [weak self] in
                self?.recoverEventTap(expectedGeneration: generation)
            }
            return Unmanaged.passUnretained(event)
        }

        let cgPoint = event.location
        switch type {
        case .leftMouseDown:    handleMouseDown(at: cgPoint)
        case .leftMouseDragged: handleDrag(at: cgPoint)
        case .leftMouseUp:      handleMouseUp(at: cgPoint, modifiers: event.flags)
        default: break
        }
        return Unmanaged.passUnretained(event)
    }
}
