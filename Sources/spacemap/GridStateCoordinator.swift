import Foundation

/// Owns the single write path for GridState construction and coordinates the
/// fetch → publish → refresh-cache transitions that were previously duplicated
/// across HUDWindowController.
///
/// Responsibilities
/// - Build fresh GridState via `YabaiService.buildGridState` on the yabai queue.
/// - Own the latest state so no other type constructs or mutates it by hand.
/// - Own pending-focus preservation (`updateFocusedIndex` + `refresh`).
/// - Own debounce/cancellation (replaces the HUD's `refreshWorkItem`,
///   `isFetching` and `workCancelled` flags).
///
/// The coordinator is deliberately UI-free: rendering, icon preloading,
/// thumbnail refresh and drag wiring stay in the HUD and are driven by the
/// completions of these methods.
final class GridStateCoordinator {

    /// Phase of the write pipeline. Transitions: idle → fetching → ready.
    enum Phase: Equatable {
        case idle
        case fetching
        case ready
    }

    /// Config used for the next fetch/refresh. The owner keeps this current
    /// (reloadConfig) before triggering a fetch.
    var config: GridConfig?

    /// The single source of truth for the last built state.
    private(set) var latestState: GridState?

    /// Public read-only access to the latest state.
    public var state: GridState? { latestState }

    /// Current phase of the write pipeline.
    private(set) var phase: Phase = .idle

    /// Optimistic focus set by keyboard navigation while the real fetch is in
    /// flight. `refresh` preserves it until yabai confirms the change.
    private(set) var pendingFocusedSpaceIndex: Int?

    /// True while a pending focus is still inside its deadline.
    var isPendingFocusValid: Bool {
        pendingFocusedSpaceIndex != nil &&
            (pendingFocusDeadline.map { Date() < $0 } ?? false)
    }

    /// How long an optimistic focus stays valid before `refresh` stops
    /// preserving it. Mirrors the original HUD's 1s navigation deadline.
    private static let pendingFocusTimeout: TimeInterval = 1.0

    private var pendingFocusDeadline: Date?

    /// Generation counter guards against stale completions: when a new fetch
    /// starts it increments the generation and any older completion that lands
    /// on the main queue is dropped instead of overwriting newer state.
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

    // MARK: - Fetch / refresh

    /// Fetch a fresh GridState and publish it as `latestState`.
    ///
    /// When `replacingFocusedIndex` is non-nil and a state already exists, the
    /// fetch is skipped and only the focused index is updated on the cached
    /// state (used while the HUD is hidden to keep the highlight current).
    /// - Parameters:
    ///   - completion: called on the main queue after publish.
    ///   - replacingFocusedIndex: optional focused-index-only update.
    func fetch(completion: (() -> Void)? = nil, replacingFocusedIndex: Int? = nil) {
        if let replacingFocusedIndex, let latestState {
            let updated = GridState(
                config: latestState.config,
                spaces: latestState.spaces,
                windows: latestState.windows,
                displayBounds: latestState.displayBounds,
                focusedIndex: replacingFocusedIndex,
                displays: latestState.displays
            )
            self.latestState = updated
            phase = .ready
            completion?()
            return
        }
        guard let config else { return }

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

    /// Fetch a fresh GridState, preserving an in-flight optimistic focus
    /// selected via `updateFocusedIndex`.
    /// - Parameter completion: called on the main queue after publish.
    func refresh(completion: (() -> Void)? = nil) {
        guard let config else { return }

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

    /// Cancel any in-flight fetch so a stale completion cannot publish after
    /// the HUD hides. The last published state is retained.
    func cancelPendingFetch() {
        inFlightWorkItem?.cancel()
        inFlightWorkItem = nil
        fetchGeneration += 1
        phase = latestState != nil ? .ready : .idle
    }

    // MARK: - Config

    /// Reload config from disk. The owner keeps this current
    /// (reloadConfig) before triggering a fetch.
    public func reloadConfig() {
        config = Config.load()
    }

    // MARK: - Optimistic focus (navigation)

    /// Optimistically move `focusedIndex` for keyboard navigation, recording it
    /// as pending so a subsequent `refresh` preserves it until yabai confirms.
    /// - Parameter focusedIndex: the target space index.
    /// - Returns: the optimistic state to render immediately, or nil if no
    ///   base state exists yet.
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

    /// Clear the pending focus without touching the latest state.
    func clearPendingFocus() {
        pendingFocusedSpaceIndex = nil
        pendingFocusDeadline = nil
    }

    /// Derive a copy of the latest state with a given focused index without
    /// mutating `latestState`. Returns nil when no state exists yet.
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

    // MARK: - Private

    /// Keep an optimistic focus in the displayed state while it is still valid;
    /// otherwise adopt the freshly fetched focus and clear the pending entry.
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
