import Foundation
import AppKit

enum SpaceLayout: String {
    case bsp
    case stack
    case float
}

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
    /// Cheap fingerprint of window-to-space membership. yabai emits no signal
    /// when a window moves to another space without changing focus.
    func windowSpaceSignature() throws -> String
    /// Drops coalesced spaces/windows snapshots after an external mutation.
    func invalidateSnapshotCaches()
    func queryFocusedWindow() throws -> Int?
    func queryFocusedSpaceIndex() -> Int?

    func registerSignals(socketPath: String, showHUDOnSpaceChange: Bool, refreshWorkspacePreviews: Bool, refreshWindowGeometry: Bool)
    func removeSignals()

    func focusSpace(_ index: Int)
    func focusSpace(_ target: SpaceFocusTarget) -> Bool
    func focusSpaceAsync(_ index: Int)
    /// Swaps two spaces on the same display. `.content` moves the windows;
    /// `.spaces` moves the spaces themselves.
    func swapSpaces(_ first: Int, _ second: Int, mode: SpaceDropMode, focusMode: DragFocusMode)
    func createSpace()
    func destroySpace(_ index: Int)
    func moveFocusedWindow(toSpace index: Int)
    func moveWindows(_ windowIDs: [Int], toSpace index: Int)
    /// Move windows and then apply the configured focus behaviour.
    func moveWindows(_ windowIDs: [Int], toSpace index: Int, focusMode: DragFocusMode, sourceSpace: Int?)
    func toggleWindowFullscreen()
    func toggleWindowFloat()
    func balanceWindows()
    func setSpaceLayout(_ layout: SpaceLayout)

    func showSpacemap()

    func moveWindowCreatingSpacesIfNeeded(_ windowID: Int, toSpace targetIndex: Int, focusDestination: Bool, completion: @escaping (Result<Void, Error>) -> Void)

    func buildGridState(config: SpacemapConfig, focusedIndex: Int?) -> GridState

    /// Ownership/signature trust failure for the yabai binary, or nil when
    /// trusted. Default nil so test doubles stay conforming.
    func yabaiTrustIssue() -> String?
}

extension YabaiService {
    func windowSpaceSignature() throws -> String { "" }
    func swapSpaces(_ first: Int, _ second: Int, mode: SpaceDropMode, focusMode: DragFocusMode) {}
    func moveWindows(_ windowIDs: [Int], toSpace index: Int, focusMode: DragFocusMode, sourceSpace: Int?) {
        moveWindows(windowIDs, toSpace: index)
    }
    func yabaiTrustIssue() -> String? { nil }
    func invalidateSnapshotCaches() {}
}
