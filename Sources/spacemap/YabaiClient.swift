import Foundation
import AppKit

enum YabaiClient {
    private static let shared = YabaiClientImpl()

    // MARK: - Queue dispatch

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func runOnYabaiQueue(_ block: @escaping () -> Void) {
        shared.runOnYabaiQueue(block)
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func runOnYabaiQueue(_ workItem: DispatchWorkItem) {
        shared.runOnYabaiQueue(workItem)
    }

    // MARK: - Yabai running check

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static var yabaiProcessCheck: () -> Bool {
        get { shared.yabaiProcessCheck }
        set { shared.yabaiProcessCheck = newValue }
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func isYabaiRunning(forceRefresh: Bool = false) -> Bool {
        shared.isYabaiRunning(forceRefresh: forceRefresh)
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func resetYabaiRunningCache() {
        shared.resetYabaiRunningCache()
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func resetYabaiProcessCheck() {
        shared.resetYabaiProcessCheck()
    }

    // MARK: - Queries

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func querySpaces() throws -> [YabaiSpace] {
        try shared.querySpaces()
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func queryDisplays() throws -> [YabaiDisplay] {
        try shared.queryDisplays()
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func queryWindows() throws -> [YabaiWindow] {
        try shared.queryWindows()
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func queryFocusedWindow() throws -> Int? {
        try shared.queryFocusedWindow()
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func queryFocusedSpaceIndex() -> Int? {
        shared.queryFocusedSpaceIndex()
    }

    // MARK: - Signals

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func registerSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool = false,
        refreshWorkspacePreviews: Bool = false,
        refreshWindowGeometry: Bool = true
    ) {
        shared.registerSignals(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange,
            refreshWorkspacePreviews: refreshWorkspacePreviews,
            refreshWindowGeometry: refreshWindowGeometry
        )
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func removeSignals() {
        shared.removeSignals()
    }

    // MARK: - Focus

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func focusSpace(_ index: Int) {
        shared.focusSpace(index)
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    @discardableResult
    static func focusSpace(_ target: SpaceFocusTarget) -> Bool {
        shared.focusSpace(target)
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func focusSpaceAsync(_ index: Int) {
        shared.focusSpaceAsync(index)
    }

    // MARK: - Spacemap

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func showSpacemap() {
        shared.showSpacemap()
    }

    // MARK: - Window movement

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        shared.moveWindowCreatingSpacesIfNeeded(
            windowID,
            toSpace: targetIndex,
            focusDestination: focusDestination,
            completion: completion
        )
    }

    // MARK: - Grid state

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func buildGridState(config: GridConfig, focusedIndex: Int? = nil) -> GridState {
        shared.buildGridState(config: config, focusedIndex: focusedIndex)
    }

    // MARK: - Signal actions

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func spaceChangedSignalAction(socketPath: String, showHUDOnSpaceChange: Bool) -> String {
        shared.spaceChangedSignalAction(socketPath: socketPath, showHUDOnSpaceChange: showHUDOnSpaceChange)
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static func refreshSignalAction(socketPath: String) -> String {
        shared.refreshSignalAction(socketPath: socketPath)
    }

    // MARK: - Refresh events

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static var windowGeometryRefreshEvents: [String] {
        shared.windowGeometryRefreshEvents
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static var workspaceTopologyRefreshEvents: [String] {
        shared.workspaceTopologyRefreshEvents
    }

    @available(*, deprecated, message: "Use YabaiClientImpl or YabaiService protocol directly")
    static var workspacePreviewRefreshEvents: [String] {
        shared.workspacePreviewRefreshEvents
    }
}
