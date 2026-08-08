import Foundation
import AppKit

protocol YabaiService {
    var yabaiProcessCheck: () -> Bool { get set }

    var windowGeometryRefreshEvents: [String] { get }
    var workspaceTopologyRefreshEvents: [String] { get }
    var workspacePreviewRefreshEvents: [String] { get }

    func runOnYabaiQueue(_ block: @escaping () -> Void)
    func runOnYabaiQueue(_ workItem: DispatchWorkItem)

    func isYabaiRunning(forceRefresh: Bool) -> Bool
    func resetYabaiRunningCache()
    func resetYabaiProcessCheck()

    func querySpaces() throws -> [YabaiSpace]
    func queryDisplays() throws -> [YabaiDisplay]
    func queryWindows() throws -> [YabaiWindow]
    func queryFocusedWindow() throws -> Int?
    func queryFocusedSpaceIndex() -> Int?

    func registerSignals(socketPath: String, showHUDOnSpaceChange: Bool, refreshWorkspacePreviews: Bool, refreshWindowGeometry: Bool)
    func removeSignals()

    func focusSpace(_ index: Int)
    func focusSpace(_ target: SpaceFocusTarget) -> Bool
    func focusSpaceAsync(_ index: Int)

    func showSpacemap()

    func moveWindowCreatingSpacesIfNeeded(_ windowID: Int, toSpace targetIndex: Int, focusDestination: Bool, completion: @escaping (Result<Void, Error>) -> Void)

    func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState
}
