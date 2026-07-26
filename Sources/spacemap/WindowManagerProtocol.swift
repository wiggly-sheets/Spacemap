import Foundation

enum WindowManagerType: String, CaseIterable {
    case yabai, aerospace, auto
}

protocol WindowManager: AnyObject {
    var type: WindowManagerType { get }
    func isRunning() -> Bool
    func queryWindows() throws -> [Window]
    func queryFocusedWindow() throws -> Int?
    func queryFocusedSpaceIndex() -> Int?
    func buildGridState(config: GridConfig) -> GridState
    func runOnQueue(_ block: @escaping () -> Void)
    func runOnQueue(_ workItem: DispatchWorkItem)
    func focusSpaceAsync(_ index: Int)
    func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func registerRefreshSignals(socketPath: String)
    func removeRefreshSignals()
}

final class YabaiWindowManager: WindowManager {
    static let shared = YabaiWindowManager()
    let type = WindowManagerType.yabai

    private init() {}

    func isRunning() -> Bool { YabaiClient.isYabaiRunning() }
    func queryWindows() throws -> [Window] { try YabaiClient.queryWindows() }
    func queryFocusedWindow() throws -> Int? { try YabaiClient.queryFocusedWindow() }
    func queryFocusedSpaceIndex() -> Int? { YabaiClient.queryFocusedSpaceIndex() }
    func buildGridState(config: GridConfig) -> GridState { YabaiClient.buildGridState(config: config) }
    func runOnQueue(_ block: @escaping () -> Void) { YabaiClient.runOnYabaiQueue(block) }
    func runOnQueue(_ workItem: DispatchWorkItem) { YabaiClient.runOnYabaiQueue(workItem) }
    func focusSpaceAsync(_ index: Int) { YabaiClient.focusSpaceAsync(index) }
    func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        YabaiClient.moveWindowCreatingSpacesIfNeeded(
            windowID,
            toSpace: targetIndex,
            focusDestination: focusDestination,
            completion: completion
        )
    }
    func registerRefreshSignals(socketPath: String) { YabaiClient.registerSignals(socketPath: socketPath) }
    func removeRefreshSignals() { YabaiClient.removeSignals() }
}
