import Cocoa

class WindowDragHandler: WindowDragService {
    var onHoverCell: ((Int?) -> Void)?
    var onDropInCell: ((Int, Int, CGEventFlags) -> Void)?

    private let yabaiService: YabaiService
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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

    init(yabaiService: YabaiService) {
        self.yabaiService = yabaiService
    }

    func updateInput(_ input: WindowDragInput) {
        cellFrames = input.cellFrames
        cachedWindows = input.cachedWindows
        focusedWindowIDAtOpen = input.focusedWindowIDAtOpen
    }

    func start() {
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
                guard let refcon else { return nil }
                let handler = Unmanaged<WindowDragHandler>.fromOpaque(refcon).takeUnretainedValue()
                let cgPoint = event.location
                switch type {
                case .leftMouseDown:    handler.handleMouseDown(at: cgPoint)
                case .leftMouseDragged: handler.handleDrag(at: cgPoint)
                case .leftMouseUp:      handler.handleMouseUp(at: cgPoint, modifiers: event.flags)
                default: break
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else { return }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        stop()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        reset()
    }

    func reset() {
        isDragging = false
        draggedWindowID = nil
        dragStartPoint = nil
        lastHoveredCell = nil
        frontmostAppAtMouseDown = nil
    }

    func handleMouseDown(at cgPoint: CGPoint) {
        dragStartPoint = cgPoint
        isDragging = false
        draggedWindowID = nil
        frontmostAppAtMouseDown = NSWorkspace.shared.frontmostApplication?.localizedName
    }

    func handleDrag(at cgPoint: CGPoint) {
        guard !cellFrames.isEmpty else { return }

        if !isDragging {
            guard let start = dragStartPoint,
                  hypot(cgPoint.x - start.x, cgPoint.y - start.y) > 5 else { return }
            isDragging = true
            draggedWindowID = findDraggedWindowID(atCG: start)
        }

        let cell = cellSpaceIndex(forCG: cgPoint)
        if cell != lastHoveredCell {
            lastHoveredCell = cell
            DispatchQueue.main.async { [weak self] in self?.onHoverCell?(cell) }
        }
    }

    func handleMouseUp(at cgPoint: CGPoint, modifiers: CGEventFlags) {
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
            self?.onHoverCell?(nil)
            self?.onDropInCell?(windowID, cell, modifiers)
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

        var candidates = cachedWindows.filter { $0.app == appName }
        if candidates.isEmpty {
            candidates = ((try? yabaiService.queryWindows()) ?? []).filter { $0.app == appName }
        }

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
