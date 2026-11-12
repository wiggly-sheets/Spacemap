import Cocoa

private func shouldRecoverWindowDragEventTap(for type: CGEventType) -> Bool {
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
    static let healthCheckInterval: TimeInterval = 1.0

    var onHoverCell: ((Int?) -> Void)?
    var onDropInCell: ((Int, Int, CGEventFlags) -> Void)?
    var onRequestDragSnapshot: ((Int) -> Void)?

    private let frontmostApplicationName: () -> String?
    private let frontmostApplicationPID: () -> Int32?
    private let permissionCheck: () -> Bool
    private let permissionCacheInterval: TimeInterval
    private let eventTapFactory: EventTapFactory
    private let cgWindowListProvider: () -> [CGWindowSample]
    private let cgWindowSampleInterval: TimeInterval

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapContext: UnsafeMutableRawPointer?
    private var wantsEventTap = false
    private(set) var eventTapGeneration = 0
    private var dragSnapshotGeneration = 0
    private(set) var dragSnapshotReady = true
    private var healthTimer: Timer?
    private var lastPermissionState: Bool?
    private var cachedPermission: Bool?
    private var lastPermissionCheckTime: TimeInterval = 0
    private var mouseDownCGWindow: CGWindowSample?
    private var lastCGWindowSample: [CGWindowSample] = []
    private var lastCGWindowSampleTime: TimeInterval = 0
    private(set) var tapCreationFailureCount = 0
    private(set) var tapCreationAttempts = 0

    private enum DragDelivery {
        case hover(Int?)
        case drop(windowID: Int, cell: Int, modifiers: CGEventFlags)
    }

    private var pendingDelivery: DragDelivery?
    private var isDeliveryScheduled = false
    private var deliveryGeneration = 0

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
    var hasTapContext: Bool { tapContext != nil }

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
        self.eventTapFactory = eventTapFactory
        self.cgWindowListProvider = cgWindowListProvider
        self.cgWindowSampleInterval = cgWindowSampleInterval
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
        healthTimer?.invalidate()
        healthTimer = nil
        lastPermissionState = nil
        cachedPermission = nil
        // Deliver the clear before invalidating queued delivery, otherwise a
        // visible drop target survives teardown.
        cancelHoverForTeardown()
        invalidateQueuedDelivery()
        tearDownEventTap()
        reset()
    }

    static func shouldRecoverEventTap(for type: CGEventType) -> Bool {
        shouldRecoverWindowDragEventTap(for: type)
    }

    func recoverEventTap() {
        _ = recoverEventTap(expectedGeneration: nil)
    }

    @discardableResult
    func recoverEventTap(expectedGeneration: Int?) -> Bool {
        guard wantsEventTap else { return false }
        if let expectedGeneration, expectedGeneration != eventTapGeneration {
            NSLog("Spacemap/Drag: ignoring stale event tap recovery")
            return false
        }
        if let tap = eventTap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return true }
        }
        cancelHoverForTeardown()
        invalidateQueuedDelivery()
        tearDownEventTap()
        reset()
        reconcileEventTap()
        return true
    }

    /// Installs, re-enables, or retries the drag tap. Exposed for the health
    /// timer and for tests; keeps retrying on a bounded cadence.
    func reconcileEventTap() {
        guard wantsEventTap else { return }

        let isPermitted = permissionIsGranted()
        if lastPermissionState != isPermitted {
            NSLog(isPermitted
                ? "Spacemap/Drag: window drag event tap active"
                : "Spacemap/Drag: input monitoring unavailable; will retry")
            lastPermissionState = isPermitted
        }
        guard isPermitted else {
            // Permission can disappear mid-drag; do not leave a highlight or
            // a half-finished drag behind.
            cancelHoverForTeardown()
            tearDownEventTap()
            reset()
            return
        }

        if let tap = eventTap {
            if CFMachPortIsValid(tap) {
                if !CGEvent.tapIsEnabled(tap: tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                if CGEvent.tapIsEnabled(tap: tap) { return }
            }
            tearDownEventTap()
        }
        installEventTap()
    }

    private func permissionIsGranted() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cachedPermission, now - lastPermissionCheckTime < permissionCacheInterval {
            return cachedPermission
        }
        lastPermissionCheckTime = now
        let permitted = permissionCheck()
        cachedPermission = permitted
        return permitted
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        let timer = Timer(timeInterval: Self.healthCheckInterval, repeats: true) { [weak self] _ in
            self?.reconcileEventTap()
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func installEventTap() {
        guard wantsEventTap, eventTap == nil else { return }

        tapCreationAttempts += 1
        if tapContext == nil {
            let box = WeakTapContext(self)
            tapContext = Unmanaged.passRetained(box).toOpaque()
        }

        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue)
        )
        guard let tap = eventTapFactory(
            .cgSessionEventTap,
            .tailAppendEventTap,
            .listenOnly,
            mask,
            Self.tapCallback,
            tapContext
        ) else {
            releaseTapContext()
            tapCreationFailureCount += 1
            if tapCreationFailureCount == 1 || tapCreationFailureCount.isMultiple(of: 30) {
                NSLog("Spacemap/Drag: event tap creation failed; will retry")
            }
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
        eventTapGeneration += 1
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapCreationFailureCount = 0
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
        eventTap = nil
        runLoopSource = nil
        releaseTapContext()
    }

    private func releaseTapContext() {
        guard let context = tapContext else { return }
        tapContext = nil
        Unmanaged<WeakTapContext<WindowDragHandler>>.fromOpaque(context).release()
    }

    func reset() {
        dragSnapshotGeneration += 1
        dragSnapshotReady = true
        isDragging = false
        draggedWindowID = nil
        dragStartPoint = nil
        lastHoveredCell = nil
        frontmostAppAtMouseDown = nil
        frontmostPIDAtMouseDown = nil
        mouseDownCGWindow = nil
        lastCGWindowSample = []
    }

    func handleMouseDown(at cgPoint: CGPoint) {
        dragSnapshotGeneration += 1
        let snapshotGeneration = dragSnapshotGeneration
        dragStartPoint = cgPoint
        isDragging = false
        draggedWindowID = nil
        frontmostAppAtMouseDown = frontmostApplicationName()
        frontmostPIDAtMouseDown = frontmostApplicationPID()
        // The WindowServer is authoritative for which app owns the window
        // under the click, even when the frontmost-app snapshot is stale.
        mouseDownCGWindow = sampleCGWindows(force: true).first { $0.bounds.contains(cgPoint) }
        if let onRequestDragSnapshot {
            dragSnapshotReady = false
            onRequestDragSnapshot(snapshotGeneration)
        } else {
            dragSnapshotReady = true
        }
    }

    func applyDragSnapshot(
        focusedWindowID: Int?,
        windows: [YabaiWindow],
        generation: Int
    ) {
        guard generation == dragSnapshotGeneration else { return }
        dragSnapshotReady = true
        guard dragStartPoint != nil else { return }
        focusedWindowIDAtOpen = focusedWindowID
        cachedWindows = windows
        if isDragging, draggedWindowID == nil, let start = dragStartPoint {
            draggedWindowID = findDraggedWindowID(atCG: start)
        }
    }

    func handleDrag(at cgPoint: CGPoint) {
        guard !cellFrames.isEmpty else { return }

        if !isDragging {
            guard let start = dragStartPoint,
                  hypot(cgPoint.x - start.x, cgPoint.y - start.y) > Self.dragThreshold,
                  hasWindowDragEvidence(at: start) else {
                return
            }
            isDragging = true
        }
        if draggedWindowID == nil, dragSnapshotReady, let start = dragStartPoint {
            draggedWindowID = findDraggedWindowID(atCG: start)
        }

        let cell = cellSpaceIndex(forCG: cgPoint)
        if cell != lastHoveredCell {
            lastHoveredCell = cell
            enqueueDelivery(.hover(cell))
        }
    }

    func handleMouseUp(at cgPoint: CGPoint, modifiers: CGEventFlags) {
        let wasDragging = isDragging
        let start = dragStartPoint
        let snapshotWasPending = !dragSnapshotReady
        let trackedWindowID = draggedWindowID
        let cell = cellSpaceIndex(forCG: cgPoint)
        defer { reset() }

        guard wasDragging else {
            if lastHoveredCell != nil {
                lastHoveredCell = nil
                enqueueDelivery(.hover(nil))
            }
            return
        }

        let windowID = trackedWindowID ?? resolveDraggedWindowID(atCG: start ?? cgPoint)
        guard let cell, let windowID else {
            if cell == nil {
                NSLog("Spacemap/Drag: drop cancelled; released outside all cells")
            } else {
                NSLog("Spacemap/Drag: drop abandoned; no window identified")
            }
            if lastHoveredCell != nil {
                lastHoveredCell = nil
                enqueueDelivery(.hover(nil))
            }
            return
        }

        if trackedWindowID == nil {
            NSLog("Spacemap/Drag: drop used cached window fallback (snapshot pending: \(snapshotWasPending))")
        }
        lastHoveredCell = nil
        enqueueDelivery(.drop(windowID: windowID, cell: cell, modifiers: modifiers))
    }

    func cellSpaceIndex(forCG cgPoint: CGPoint) -> Int? {
        for entry in cellFrames where entry.frame.contains(cgPoint) {
            return entry.spaceIndex
        }
        return nil
    }

    func hasWindowDragEvidence(at cgPoint: CGPoint) -> Bool {
        if let windowID = findDraggedWindowID(atCG: cgPoint),
           let window = cachedWindows.first(where: { $0.id == windowID }) {
            let frame = window.cgFrame
            if frame.contains(cgPoint),
               cgPoint.y - frame.minY <= Self.titleBarHeight {
                return true
            }
        }
        // Toolbar, borderless, and background drags may start below the title
        // bar. The WindowServer tells us cheaply whether the window under the
        // cursor actually moved; text selection and sliders do not move it.
        return cgWindowMoved()
    }

    func findDraggedWindowID(atCG cgPoint: CGPoint) -> Int? {
        let candidates = windowsForFrontmostApp()
        guard !candidates.isEmpty else {
            // A known app/pid with no cached window is not evidence. Falling
            // back to the focused window here can move a different app's
            // overlapping window.
            return hasKnownFrontmostIdentity ? nil : focusedWindowIDAtOpen
        }

        // Prefer the exact window the WindowServer reported under the click.
        if let sample = mouseDownCGWindow,
           let matching = candidates.first(where: {
               framesApproximatelyMatch($0.cgFrame, sample.bounds)
           }) {
            return matching.id
        }

        if let focused = focusedWindowIDAtOpen,
           let focusedWindow = candidates.first(where: { $0.id == focused }),
           focusedWindow.cgFrame.contains(cgPoint) {
            return focused
        }

        if let containing = candidates.first(where: { $0.cgFrame.contains(cgPoint) }) {
            return containing.id
        }

        // AX and CGEvent coordinates share Quartz's top-left origin.
        return candidates.min {
            hypot($0.cgFrame.minX - cgPoint.x, $0.cgFrame.minY - cgPoint.y) <
            hypot($1.cgFrame.minX - cgPoint.x, $1.cgFrame.minY - cgPoint.y)
        }?.id
    }

    /// Drop resolution is more permissive than evidence: a focused window that
    /// contains the drag start can still receive the drop.
    func resolveDraggedWindowID(atCG cgPoint: CGPoint) -> Int? {
        if let windowID = findDraggedWindowID(atCG: cgPoint) { return windowID }
        if let focused = focusedWindowIDAtOpen,
           let window = cachedWindows.first(where: { $0.id == focused }),
           window.cgFrame.contains(cgPoint) {
            return focused
        }
        return nil
    }

    private var hasKnownFrontmostIdentity: Bool {
        mouseDownCGWindow != nil || frontmostPIDAtMouseDown != nil || frontmostAppAtMouseDown != nil
    }

    private var effectiveFrontmostPID: Int32? {
        mouseDownCGWindow?.ownerPID ?? frontmostPIDAtMouseDown
    }

    private func windowsForFrontmostApp() -> [YabaiWindow] {
        if let pid = effectiveFrontmostPID {
            let matches = cachedWindows.filter { $0.pid == Int(pid) }
            if !matches.isEmpty { return matches }
            // The WindowServer pid is authoritative; do not fall back to a
            // stale frontmost localized name when it does not match.
            if mouseDownCGWindow != nil { return [] }
        }
        guard let appName = frontmostAppAtMouseDown else { return [] }
        return cachedWindows.filter { $0.app == appName }
    }

    private func framesApproximatelyMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 4 &&
            abs(lhs.minY - rhs.minY) <= 4 &&
            abs(lhs.width - rhs.width) <= 4 &&
            abs(lhs.height - rhs.height) <= 4
    }

    private func sampleCGWindows(force: Bool = false) -> [CGWindowSample] {
        let now = ProcessInfo.processInfo.systemUptime
        if force || lastCGWindowSample.isEmpty
            || now - lastCGWindowSampleTime >= cgWindowSampleInterval {
            lastCGWindowSample = cgWindowListProvider()
            lastCGWindowSampleTime = now
        }
        return lastCGWindowSample
    }

    private func cgWindowMoved() -> Bool {
        guard let before = mouseDownCGWindow else { return false }
        guard let after = sampleCGWindows().first(where: { $0.windowID == before.windowID }) else {
            return false
        }
        let moved = abs(after.bounds.minX - before.bounds.minX) > Self.dragThreshold
            || abs(after.bounds.minY - before.bounds.minY) > Self.dragThreshold
        // An edge-resize changes the origin too; only count movement when the
        // window kept its size.
        let resized = abs(after.bounds.width - before.bounds.width) > Self.dragThreshold
            || abs(after.bounds.height - before.bounds.height) > Self.dragThreshold
        return moved && !resized
    }

    private static func onScreenWindows() -> [CGWindowSample] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? Int,
                  ownerPID != Int(ownPID),
                  let windowID = entry[kCGWindowNumber as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else {
                return nil
            }
            return CGWindowSample(
                windowID: CGWindowID(windowID),
                ownerPID: pid_t(ownerPID),
                bounds: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    private func enqueueDelivery(_ delivery: DragDelivery) {
        if case .hover = delivery, case .drop = pendingDelivery { return }
        pendingDelivery = delivery
        schedulePendingDelivery()
    }

    private func schedulePendingDelivery() {
        guard !isDeliveryScheduled, pendingDelivery != nil else { return }
        isDeliveryScheduled = true
        let generation = deliveryGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isDeliveryScheduled = false
            // Check generation before touching the queue: a newer delivery may
            // belong to the current generation while this block is stale.
            guard generation == self.deliveryGeneration else {
                self.schedulePendingDelivery()
                return
            }
            guard let delivery = self.pendingDelivery else { return }
            self.pendingDelivery = nil
            switch delivery {
            case .hover(let cell):
                self.onHoverCell?(cell)
            case .drop(let windowID, let cell, let modifiers):
                self.onHoverCell?(nil)
                self.onDropInCell?(windowID, cell, modifiers)
            }
        }
    }

    private func cancelHoverForTeardown() {
        guard lastHoveredCell != nil || isDragging else { return }
        lastHoveredCell = nil
        onHoverCell?(nil)
    }

    private func invalidateQueuedDelivery() {
        deliveryGeneration += 1
        pendingDelivery = nil
        isDeliveryScheduled = false
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let box = Unmanaged<WeakTapContext<WindowDragHandler>>.fromOpaque(refcon)
            .takeUnretainedValue()
        guard let handler = box.owner else { return Unmanaged.passUnretained(event) }

        if shouldRecoverWindowDragEventTap(for: type) {
            let generation = handler.eventTapGeneration
            DispatchQueue.main.async { [weak handler] in
                handler?.recoverEventTap(expectedGeneration: generation)
            }
            return Unmanaged.passUnretained(event)
        }

        let cgPoint = event.location
        switch type {
        case .leftMouseDown:    handler.handleMouseDown(at: cgPoint)
        case .leftMouseDragged: handler.handleDrag(at: cgPoint)
        case .leftMouseUp:      handler.handleMouseUp(at: cgPoint, modifiers: event.flags)
        default: break
        }
        return Unmanaged.passUnretained(event)
    }
}
