import Cocoa

protocol WindowDragService {
    var onHoverCell: ((Int?) -> Void)? { get set }
    var onDropInCell: ((Int, Int, CGEventFlags) -> Void)? { get set }
    var dragState: DragState { get }
    func start()
    func stop()
    func reset()
    func updateInput(_ input: WindowDragInput)
}

enum DragState: Equatable {
    case idle
    case dragging(
        isDragging: Bool,
        draggedWindowID: Int?,
        lastHoveredCell: Int?,
        frontmostAppAtMouseDown: String?
    )
}
