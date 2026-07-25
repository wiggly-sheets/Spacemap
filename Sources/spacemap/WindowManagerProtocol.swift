import Foundation

enum WindowManagerType: String, CaseIterable {
    case yabai, aerospace, auto
}

protocol WindowManager: AnyObject {
    var type: WindowManagerType { get }
    func isRunning() -> Bool
    func querySpaces() -> [Space]
    func queryWindows() throws -> [Window]
    func queryFocusedWindow() -> Int?
    func queryFocusedSpaceIndex() -> Int?
    func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState
    func focusSpace(_ index: Int)
    func moveWindow(_ windowID: Int, toSpace spaceIndex: Int)
    func startListening(
        socketPath: String,
        onRefresh: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onSettings: @escaping () -> Void
    )
    func stopListening()
}