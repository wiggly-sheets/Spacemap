import XCTest
import CoreGraphics
@testable import spacemap

final class MockYabaiService: YabaiService {

    // MARK: - Configurable return values

    var querySpacesResult: [YabaiSpace] = []
    var querySpacesError: Error?
    var queryDisplaysResult: [YabaiDisplay] = []
    var queryDisplaysError: Error?
    var queryWindowsResult: [YabaiWindow] = []
    var queryWindowsError: Error?
    var queryFocusedWindowResult: Int? = nil
    var queryFocusedWindowError: Error?
    var queryFocusedSpaceIndexResult: Int? = nil
    var buildGridStateResult: GridState?
    var buildGridStateClosure: ((GridConfig, Int?) -> GridState)?
    var focusSpaceResult: Bool = true
    var isYabaiRunningResult: Bool = false

    // MARK: - Call tracking

    private(set) var querySpacesCallCount = 0
    private(set) var queryDisplaysCallCount = 0
    private(set) var queryWindowsCallCount = 0
    private(set) var queryFocusedWindowCallCount = 0
    private(set) var queryFocusedSpaceIndexCallCount = 0
    private(set) var buildGridStateCallCount = 0
    private(set) var focusSpaceIndexCallCount = 0
    private(set) var focusSpaceTargetCallCount = 0
    private(set) var focusSpaceAsyncCallCount = 0
    private(set) var showSpacemapCallCount = 0
    private(set) var moveWindowCreatingSpacesCallCount = 0
    private(set) var registerSignalsCallCount = 0
    private(set) var removeSignalsCallCount = 0
    private(set) var isYabaiRunningCallCount = 0
    private(set) var resetYabaiRunningCacheCallCount = 0
    private(set) var resetYabaiProcessCheckCallCount = 0
    private(set) var runOnYabaiQueueCallCount = 0

    // MARK: - Argument tracking

    private(set) var lastFocusSpaceIndex: Int?
    private(set) var lastFocusSpaceTarget: SpaceFocusTarget?
    private(set) var lastMoveWindowID: Int?
    private(set) var lastMoveWindowTargetIndex: Int?
    private(set) var lastMoveWindowFocusDestination: Bool?
    private(set) var lastRegisterSignalsSocketPath: String?
    private(set) var lastRegisterSignalsShowHUDOnSpaceChange: Bool?
    private(set) var lastRegisterSignalsRefreshWorkspacePreviews: Bool?
    private(set) var lastRegisterSignalsRefreshWindowGeometry: Bool?
    private(set) var lastBuildGridStateConfig: GridConfig?
    private(set) var lastBuildGridStateFocusedIndex: Int?

    // MARK: - YabaiService

    var yabaiProcessCheck: () -> Bool = { false }

    var windowGeometryRefreshEvents: [String] = []
    var workspaceTopologyRefreshEvents: [String] = []
    var workspacePreviewRefreshEvents: [String] { [] }

    func runOnYabaiQueue(_ block: @escaping () -> Void) {
        runOnYabaiQueueCallCount += 1
        block()
    }

    func runOnYabaiQueue(_ workItem: DispatchWorkItem) {
        runOnYabaiQueueCallCount += 1
        workItem.perform()
    }

    func isYabaiRunning(forceRefresh: Bool) -> Bool {
        isYabaiRunningCallCount += 1
        return isYabaiRunningResult
    }

    func resetYabaiRunningCache() {
        resetYabaiRunningCacheCallCount += 1
    }

    func resetYabaiProcessCheck() {
        resetYabaiProcessCheckCallCount += 1
    }

    func querySpaces() throws -> [YabaiSpace] {
        querySpacesCallCount += 1
        if let error = querySpacesError {
            throw error
        }
        return querySpacesResult
    }

    func queryDisplays() throws -> [YabaiDisplay] {
        queryDisplaysCallCount += 1
        if let error = queryDisplaysError {
            throw error
        }
        return queryDisplaysResult
    }

    func queryWindows() throws -> [YabaiWindow] {
        queryWindowsCallCount += 1
        if let error = queryWindowsError {
            throw error
        }
        return queryWindowsResult
    }

    func queryFocusedWindow() throws -> Int? {
        queryFocusedWindowCallCount += 1
        if let error = queryFocusedWindowError {
            throw error
        }
        return queryFocusedWindowResult
    }

    func queryFocusedSpaceIndex() -> Int? {
        queryFocusedSpaceIndexCallCount += 1
        return queryFocusedSpaceIndexResult
    }

    func registerSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool,
        refreshWorkspacePreviews: Bool,
        refreshWindowGeometry: Bool
    ) {
        registerSignalsCallCount += 1
        lastRegisterSignalsSocketPath = socketPath
        lastRegisterSignalsShowHUDOnSpaceChange = showHUDOnSpaceChange
        lastRegisterSignalsRefreshWorkspacePreviews = refreshWorkspacePreviews
        lastRegisterSignalsRefreshWindowGeometry = refreshWindowGeometry
    }

    func removeSignals() {
        removeSignalsCallCount += 1
    }

    func focusSpace(_ index: Int) {
        focusSpaceIndexCallCount += 1
        lastFocusSpaceIndex = index
    }

    func focusSpace(_ target: SpaceFocusTarget) -> Bool {
        focusSpaceTargetCallCount += 1
        lastFocusSpaceTarget = target
        return focusSpaceResult
    }

    func focusSpaceAsync(_ index: Int) {
        focusSpaceAsyncCallCount += 1
    }

    func showSpacemap() {
        showSpacemapCallCount += 1
    }

    func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        moveWindowCreatingSpacesCallCount += 1
        lastMoveWindowID = windowID
        lastMoveWindowTargetIndex = targetIndex
        lastMoveWindowFocusDestination = focusDestination
    }

    func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState {
        buildGridStateCallCount += 1
        lastBuildGridStateConfig = config
        lastBuildGridStateFocusedIndex = focusedIndex
        if let closure = buildGridStateClosure {
            return closure(config, focusedIndex)
        }
        return buildGridStateResult ?? GridState(
            config: config,
            spaces: [],
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil,
            displays: []
        )
    }
}
