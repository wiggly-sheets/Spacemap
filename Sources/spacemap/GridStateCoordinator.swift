import Foundation

final class GridStateCoordinator {

    enum Phase: Equatable {
        case idle
        case fetching
        case ready
    }

    var config: GridConfig?

    private(set) var latestState: GridState?

    public var state: GridState? { latestState }

    private(set) var phase: Phase = .idle

    private(set) var pendingFocusedSpaceIndex: Int?

    var isPendingFocusValid: Bool {
        pendingFocusedSpaceIndex != nil &&
            (pendingFocusDeadline.map { Date() < $0 } ?? false)
    }

    private static let pendingFocusTimeout: TimeInterval = 1.0

    private var pendingFocusDeadline: Date?

    private var fetchGeneration = 0

    private var inFlightWorkItem: DispatchWorkItem?

    private let yabaiService: YabaiService

    init(
        config: GridConfig? = nil,
        yabaiService: YabaiService
    ) {
        self.config = config
        self.yabaiService = yabaiService
    }


    /// Full snapshot for show/prewarm. Drops pending focus on purpose: opening
    /// the HUD must show live truth, not a stale focus intent from before open.
    /// Callers doing a live update while visible want refresh() instead.
    func fetch(completion: (() -> Void)? = nil) {
        guard let config else { completion?(); return }

        inFlightWorkItem?.cancel()
        fetchGeneration += 1
        let generation = fetchGeneration
        phase = .fetching

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let state = self.yabaiService.buildGridState(config: config, focusedIndex: nil)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.fetchGeneration else { return }
                self.latestState = state
                self.phase = .ready
                completion?()
            }
        }
        inFlightWorkItem = work
        yabaiService.runOnYabaiQueue(work)
    }

    /// Live update while HUD is visible. Preserves pending focus on purpose: a
    /// focus change is still in flight, so keep showing intent until yabai
    /// confirms it (or the 1s deadline expires) instead of flickering back.
    /// Callers showing fresh UI (show/prewarm) want fetch() instead.
    func refresh(completion: (() -> Void)? = nil) {
        guard let config else { completion?(); return }

        inFlightWorkItem?.cancel()
        fetchGeneration += 1
        let generation = fetchGeneration
        phase = .fetching

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let state = self.yabaiService.buildGridState(config: config, focusedIndex: nil)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.fetchGeneration else { return }
                let displayedState = self.statePreservingPendingFocus(state)
                self.latestState = displayedState
                self.phase = .ready
                completion?()
            }
        }
        inFlightWorkItem = work
        yabaiService.runOnYabaiQueue(work)
    }

    func cancelPendingFetch() {
        inFlightWorkItem?.cancel()
        inFlightWorkItem = nil
        fetchGeneration += 1
        phase = latestState != nil ? .ready : .idle
    }


    public func updateConfig(_ fresh: GridConfig) {
        // Drop any in-flight fetch built from the old config: its completion
        // must never overwrite the re-stamped state below.
        inFlightWorkItem?.cancel()
        inFlightWorkItem = nil
        fetchGeneration += 1
        config = fresh
        if let latestState {
            self.latestState = GridState(
                config: fresh,
                spaces: latestState.spaces,
                windows: latestState.windows,
                displayBounds: latestState.displayBounds,
                focusedIndex: latestState.focusedIndex,
                displays: latestState.displays
            )
        }
        phase = latestState != nil ? .ready : .idle
    }

    public func reloadConfig() {
        updateConfig(AppConfig.load())
    }


    @discardableResult
    func updateFocusedIndex(_ focusedIndex: Int?) -> GridState? {
        pendingFocusedSpaceIndex = focusedIndex
        pendingFocusDeadline = focusedIndex != nil
            ? Date().addingTimeInterval(Self.pendingFocusTimeout)
            : nil
        guard let base = latestState else { return nil }
        let updated = GridState(
            config: base.config,
            spaces: base.spaces,
            windows: base.windows,
            displayBounds: base.displayBounds,
            focusedIndex: focusedIndex,
            displays: base.displays
        )
        latestState = updated
        phase = .ready
        return updated
    }

    func clearPendingFocus() {
        pendingFocusedSpaceIndex = nil
        pendingFocusDeadline = nil
    }

    func state(withFocusedIndex focusedIndex: Int?) -> GridState? {
        guard let latestState else { return nil }
        return GridState(
            config: latestState.config,
            spaces: latestState.spaces,
            windows: latestState.windows,
            displayBounds: latestState.displayBounds,
            focusedIndex: focusedIndex,
            displays: latestState.displays
        )
    }


    private func statePreservingPendingFocus(_ state: GridState) -> GridState {
        guard let pending = pendingFocusedSpaceIndex else { return state }
        if state.focusedIndex == pending || !isPendingFocusValid {
            clearPendingFocus()
            return state
        }
        return GridState(
            config: state.config,
            spaces: state.spaces,
            windows: state.windows,
            displayBounds: state.displayBounds,
            focusedIndex: pending,
            displays: state.displays
        )
    }
}
