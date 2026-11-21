import AppKit

/// Owns the HUD's presentation: visibility, pin, auto-hide, and the generation
/// that keeps a late async result from landing on a later presentation.
final class HUDPresenter {
    /// Opaque marker for one presentation. Async results carry it back, so a
    /// hide or a new show drops them without the producer knowing why.
    struct Presentation {
        fileprivate let generation: Int
    }

    private let display: HUDDisplay
    private let input: HUDInput
    private let coordinator: GridStateCoordinator
    private let yabaiService: YabaiService

    private var generation = 0
    private(set) var isVisible = false
    /// Last state pushed to the display; nil while hidden.
    private(set) var state: GridState?
    var isPinned = false {
        didSet { input.isPinned = isPinned }
    }

    /// Auto-hide delay for the current presentation. Set on show from config.
    var autoHideTimeout: TimeInterval = 0
    var isAutoHideScheduled: Bool { autoHideTimer != nil }
    private var autoHideTimer: Timer?
    /// Polls the window server while a presentation is up. Mission Control
    /// posts no notification, so a short poll is the only signal.
    private var missionControlTimer: Timer?
    /// Test seam: Mission Control shield check.
    var isMissionControlActive: () -> Bool = ScreenContext.isMissionControlActive
    private var autoHideSuppressed = false
    private var panelDragActive = false
    private var dragAutoHidePoll: DispatchWorkItem?
    private var hoveredCell: Int?

    /// Controller glue: true while a window drag is live.
    var isDragging: () -> Bool = { false }
    /// Controller glue: a state reached the display, so drag targeting can start.
    var onRendered: ((GridState) -> Void)?
    /// Controller glue: the focused window resolved for this presentation.
    var onFocusedWindowResolved: ((Int?, GridState) -> Void)?
    /// Controller glue: runs after every hide, including the auto-hide timer,
    /// so drag teardown reaches every hide path.
    var onHide: (() -> Void)?

    init(
        display: HUDDisplay,
        input: HUDInput,
        coordinator: GridStateCoordinator,
        yabaiService: YabaiService
    ) {
        self.display = display
        self.input = input
        self.coordinator = coordinator
        self.yabaiService = yabaiService
        input.onAutoHideActivity = { [weak self] in self?.resetAutoHideTimer() }
        input.onPanelDragChanged = { [weak self] active in self?.setPanelDragActive(active) }
    }

    // MARK: - Presentation generation

    func currentPresentation() -> Presentation { Presentation(generation: generation) }

    func isCurrent(_ presentation: Presentation) -> Bool {
        presentation.generation == generation
    }

    /// Applies a command result only while the presentation that started it is
    /// still on screen.
    func complete(_ presentation: Presentation, notice: String? = nil, after delay: TimeInterval = 0) {
        guard isCurrent(presentation) else { return }
        if let notice { display.showNotice(notice) }
        guard delay > 0 else {
            refresh()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isCurrent(presentation) else { return }
            self.refresh()
        }
    }

    // MARK: - Show / hide / refresh

    func show(config: SpacemapConfig) {
        guard !isVisible else { return }
        guard !isMissionControlActive() else { return }
        display.hide()
        generation += 1
        isVisible = true
        input.updateVisibility(true)
        if let current = coordinator.state {
            display.updateState(current)
            input.currentState = current
            input.lastFocusedSpaceIndex = current.focusedIndex
        } else {
            // Fail-usable placeholder: empty grid still paints cells and
            // seeds input state, so navigation works once fetch lands.
            // Placeholder forces .all: active mode with no spaces paints
            // nothing (GridLayout filters on active indices).
            var placeholderConfig = config
            placeholderConfig.showMode = .all
            let placeholder = GridState(
                config: placeholderConfig,
                spaces: [],
                windows: [],
                displayBounds: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440),
                focusedIndex: nil
            )
            display.updateState(placeholder)
            input.currentState = placeholder
            input.lastFocusedSpaceIndex = placeholder.focusedIndex
        }
        autoHideTimeout = TimeInterval(config.autoHideTimeout)
        resetAutoHideTimer()
        input.startPollTimer()
        input.start()
        startMissionControlPoll()
        coordinator.fetch { [weak self] in self?.renderRefreshedState(force: false, refreshFocusedWindow: true) }
    }

    func hide() {
        guard isVisible else { return }
        generation += 1
        isVisible = false
        input.updateVisibility(false)
        isPinned = false
        // Hide the display first: hudInput.stop() clears number entry, whose
        // callback triggers updateDisplayNumber → a full render if the display
        // still considers itself rendered. Ordering avoids a transient re-show.
        dragAutoHidePoll?.cancel()
        dragAutoHidePoll = nil
        // A hide ends any hold; otherwise the next show's arm would no-op.
        autoHideSuppressed = false
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        missionControlTimer?.invalidate()
        missionControlTimer = nil
        display.hide()
        input.stop()
        hoveredCell = nil
        state = nil
        input.currentState = nil
        input.isPollingFocusedSpace = false
        input.lastFocusedSpaceIndex = nil
        coordinator.clearPendingFocus()
        coordinator.cancelPendingFetch()
        onHide?()
    }

    func refresh() {
        guard isVisible else {
            guard coordinator.state != nil else { prewarmState(); return }
            yabaiService.runOnYabaiQueue { [weak self] in
                guard let self else { return }
                let focusedIndex = self.yabaiService.queryFocusedSpaceIndex()
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isVisible, let focusedIndex else { return }
                    self.coordinator.fetch { _ = self.coordinator.updateFocusedIndex(focusedIndex) }
                }
            }
            return
        }
        resetAutoHideTimer()
        coordinator.refresh { [weak self] in self?.renderRefreshedState(force: false) }
    }

    func prewarmState() {
        coordinator.fetch { [weak self] in
            guard let self, let state = self.coordinator.state else { return }
            self.display.prewarm(state: state)
            if self.isVisible, self.state == nil { self.display.updateState(state) }
        }
    }

    private func renderRefreshedState(force: Bool, refreshFocusedWindow: Bool = false) {
        guard isVisible, let state = coordinator.state else { return }
        self.state = state
        input.currentState = state
        display.refreshAndRender(state: state, force: force)
        input.lastFocusedSpaceIndex = state.focusedIndex
        onRendered?(state)
        guard refreshFocusedWindow else { return }
        let presentation = currentPresentation()
        yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            let focusedWindowID = try? self.yabaiService.queryFocusedWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(presentation) else { return }
                self.onFocusedWindowResolved?(focusedWindowID, state)
            }
        }
    }

    // MARK: - Hover and auto-hide

    /// Cell-crossing hover: only mutate the observable hover channel and
    /// auto-hide state. No icons, thumbnails, rendering or panel resizing.
    func handleHoverCell(_ cell: Int?) {
        guard hoveredCell != cell else { return }
        hoveredCell = cell
        display.updateHoveredCell(cell)
        setAutoHideSuppressed(cell != nil || isDragging())
        guard cell == nil else { return }
        guard isDragging() else {
            setAutoHideSuppressed(false)
            resetAutoHideTimer()
            return
        }
        // handleMouseUp clears the hover before WindowDragHandler.reset() runs
        // its deferred isDragging reset, and a drag that ends over panel
        // padding produces no final hover callback at all. Poll briefly until
        // the drag is genuinely over, then re-arm auto-hide.
        releaseAutoHideAfterDrag()
    }

    /// Clears the hover channel without touching auto-hide arbitration; the
    /// drop path owns suppression itself.
    func clearHover() {
        hoveredCell = nil
        display.updateHoveredCell(nil)
    }

    private func releaseAutoHideAfterDrag(attempt: Int = 0) {
        dragAutoHidePoll?.cancel()
        // Bounded: a drag under 20s is re-checked every 200ms; after that
        // give up and re-arm auto-hide rather than polling forever.
        guard attempt < 100 else {
            dragAutoHidePoll = nil
            setAutoHideSuppressed(false)
            resetAutoHideTimer()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            guard !self.isDragging() else {
                self.releaseAutoHideAfterDrag(attempt: attempt + 1)
                return
            }
            self.dragAutoHidePoll = nil
            self.setAutoHideSuppressed(false)
            self.resetAutoHideTimer()
        }
        dragAutoHidePoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Hold/release auto-hide while a drag is live, so the HUD cannot vanish
    /// mid-drop.
    func setAutoHideSuppressed(_ suppressed: Bool) {
        guard autoHideSuppressed != suppressed else { return }
        autoHideSuppressed = suppressed
        if suppressed {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
        } else {
            resetAutoHideTimer()
        }
    }

    func resetAutoHideTimer() {
        guard !panelDragActive, !autoHideSuppressed else { return }
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard !isPinned, autoHideTimeout > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideTimeout, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    /// Mission Control snapshots every window, so a visible HUD would be
    /// copied into each space thumbnail. 0.25s keeps the hide ahead of the
    /// snapshot animation; the poll stops with the presentation.
    private func startMissionControlPoll() {
        missionControlTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollMissionControl()
        }
        RunLoop.main.add(timer, forMode: .common)
        missionControlTimer = timer
    }

    func pollMissionControl() {
        guard isVisible, isMissionControlActive() else { return }
        hide()
    }

    /// Mouse down on the panel must disarm an armed auto-hide timer; mouse up
    /// re-arms it. A hidden HUD has nothing to arm.
    private func setPanelDragActive(_ active: Bool) {
        panelDragActive = active
        if active {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
        } else if isVisible {
            resetAutoHideTimer()
        }
    }

    /// Action feedback is optional; the action itself never depends on it.
    func showNotice(_ text: String) {
        display.showNotice(text)
    }
}
