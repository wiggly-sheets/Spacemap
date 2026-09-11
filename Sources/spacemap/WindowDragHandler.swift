import Cocoa

private func shouldRecoverWindowDragEventTap(for type: CGEventType) -> Bool {
    type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
}

class WindowDragHandler: WindowDragService {
    var onHoverCell: ((Int?) -> Void)?
    var onDropInCell: ((Int, Int, CGEventFlags) -> Void)?
    var onRequestDragSnapshot: ((Int) -> Void)?

    private let frontmostApplicationName: () -> String?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var wantsEventTap = false
    private var eventTapGeneration = 0
    private var dragSnapshotGeneration = 0
    private var dragSnapshotReady = true

    var cellFrames: [(spaceIndex: Int, frame: CGRect)] = []
    var cachedWindows: [YabaiWindow] = []
    var focusedWindowIDAtOpen: Int? = nil

    var lastHoveredCell: Int? = nil
    var draggedWindowID: Int? = nil
    var dragStartPoint: CGPoint? = nil
    var frontmostAppAtMouseDown: String? = nil
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

    init(
        frontmostApplicationName: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.localizedName
        }
    ) {
        self.frontmostApplicationName = frontmostApplicationName
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
        guard eventTap == nil else { return }

        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue)
        )

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let handler = Unmanaged<WindowDragHandler>.fromOpaque(refcon).takeUnretainedValue()
                if shouldRecoverWindowDragEventTap(for: type) {
                    DispatchQueue.main.async { [weak handler] in
                        handler?.recoverEventTap()
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
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        stop()
    }

    func stop() {
        wantsEventTap = false
        eventTapGeneration += 1
        tearDownEventTap()
        reset()
    }

    static func shouldRecoverEventTap(for type: CGEventType) -> Bool {
        shouldRecoverWindowDragEventTap(for: type)
    }

    func recoverEventTap() {
        guard wantsEventTap else { return }
        if let tap = eventTap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return }
        }
        tearDownEventTap()
        reset()
        start()
    }

    private func tearDownEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func reset() {
        dragSnapshotGeneration += 1
        dragSnapshotReady = true
        isDragging = false
        draggedWindowID = nil
        dragStartPoint = nil
        lastHoveredCell = nil
        frontmostAppAtMouseDown = nil
    }

    func handleMouseDown(at cgPoint: CGPoint) {
        dragSnapshotGeneration += 1
        let snapshotGeneration = dragSnapshotGeneration
        dragStartPoint = cgPoint
        isDragging = false
        draggedWindowID = nil
        frontmostAppAtMouseDown = frontmostApplicationName()
        if let onRequestDragSnapshot {
            dragSnapshotReady = false
            focusedWindowIDAtOpen = nil
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
        guard generation == dragSnapshotGeneration, dragStartPoint != nil else { return }
        focusedWindowIDAtOpen = focusedWindowID
        cachedWindows = windows
        dragSnapshotReady = true
        if isDragging, draggedWindowID == nil, let start = dragStartPoint {
            draggedWindowID = findDraggedWindowID(atCG: start)
        }
    }

    func handleDrag(at cgPoint: CGPoint) {
        guard !cellFrames.isEmpty else { return }

        if !isDragging {
            guard let start = dragStartPoint,
                  hypot(cgPoint.x - start.x, cgPoint.y - start.y) > 5 else { return }
            isDragging = true
        }
        if draggedWindowID == nil, dragSnapshotReady, let start = dragStartPoint {
            draggedWindowID = findDraggedWindowID(atCG: start)
        }

        let cell = cellSpaceIndex(forCG: cgPoint)
        if cell != lastHoveredCell {
            lastHoveredCell = cell
            DispatchQueue.main.async { [weak self] in self?.onHoverCell?(cell) }
        }
    }

    func handleMouseUp(at cgPoint: CGPoint, modifiers: CGEventFlags) {
        let deliveryGeneration = eventTapGeneration
        defer { reset() }
        guard isDragging,
              let cell = cellSpaceIndex(forCG: cgPoint),
              let windowID = draggedWindowID else {
            if lastHoveredCell != nil {
                DispatchQueue.main.async { [weak self] in self?.onHoverCell?(nil) }
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.eventTapGeneration == deliveryGeneration else { return }
            self.onHoverCell?(nil)
            self.onDropInCell?(windowID, cell, modifiers)
        }
    }

    func cellSpaceIndex(forCG cgPoint: CGPoint) -> Int? {
        for entry in cellFrames where entry.frame.contains(cgPoint) {
            return entry.spaceIndex
        }
        return nil
    }

    private func cgToAX(_ cgPoint: CGPoint) -> CGPoint {
        cgPoint
    }

    func findDraggedWindowID(atCG cgPoint: CGPoint) -> Int? {
        guard let appName = frontmostAppAtMouseDown else {
            return focusedWindowIDAtOpen
        }

        let candidates = cachedWindows.filter { $0.app == appName }

        guard !candidates.isEmpty else { return focusedWindowIDAtOpen }

        if candidates.count == 1 { return candidates[0].id }

        if let focused = focusedWindowIDAtOpen, candidates.contains(where: { $0.id == focused }) {
            return focused
        }

        // AX and CGEvent coordinates share Quartz's top-left origin.
        let axPoint = cgToAX(cgPoint)
        return candidates.min {
            hypot($0.cgFrame.minX - axPoint.x, $0.cgFrame.minY - axPoint.y) <
            hypot($1.cgFrame.minX - axPoint.x, $1.cgFrame.minY - axPoint.y)
        }?.id
    }
}
