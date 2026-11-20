import AppKit
import SwiftUI

class HUDWindowController {
    private var dragHandler: WindowDragHandler
    private(set) var focusedWindowIDAtOpen: Int? = nil
    var isToggling = false
    var isVisible: Bool { presenter.isVisible }
    var isPinned: Bool {
        get { presenter.isPinned }
        set { presenter.isPinned = newValue }
    }
    // App-lifetime intent: AppDelegate owns SpacemapServices for process
    // lifetime and services owns hud. Both die together at termination,
    // so this strong back-ref never leaks in practice.
    private let services: SpacemapServices
    private var _config: SpacemapConfig? = nil
    private var lastConfigMtime: Date?
    private var didCheckConfigMtime = false
    private var config: SpacemapConfig { get { _config ?? services.configStore.load() } set { _config = newValue } }
    var onShowSettings: (() -> Void)?
    private let hudInput: HUDInput
    private let hudDisplay: HUDDisplay
    private let coordinator: GridStateCoordinator
    private let presenter: HUDPresenter
    /// Settle polls stop once the presentation that started a command ends.
    /// Lazy because the predicate needs `self` and no command runs during init.
    private lazy var spaceCommands = HUDSpaceCommands(yabaiService: services.yabaiService) { [weak self] in
        let presentation = self?.presenter.currentPresentation()
        return { [weak self] in
            guard let self, let presentation else { return false }
            return self.presenter.isCurrent(presentation)
        }
    }
    /// Reduce Transparency changes which backing the HUD can use; SwiftUI
    /// reads that only when its body re-evaluates.
    private var accessibilityObserver: NSObjectProtocol?
    /// Polls the pointer while an external drag is live. Strip drags are
    /// delivered to the strip view even outside its panel, so no HUD-side
    /// mouse tracking can see them; one timer covers strip and HUD drags.
    private var externalDragPoll: Timer?

    init(services: SpacemapServices, coordinator: GridStateCoordinator? = nil) {
        self.services = services
        let configStore = services.configStore
        self.coordinator = coordinator ?? GridStateCoordinator(yabaiService: services.yabaiService, configLoader: { configStore.load() })
        self.hudDisplay = HUDDisplay(
            yabaiService: services.yabaiService,
            themeStore: services.themeStore
        )
        self.hudInput = HUDInput(panel: nil)
        self.dragHandler = WindowDragHandler()
        self.presenter = HUDPresenter(
            display: hudDisplay,
            input: hudInput,
            coordinator: self.coordinator,
            yabaiService: services.yabaiService
        )
        setupDelegates()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.refresh()
        }
    }

    deinit {
        externalDragPoll?.invalidate()
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }
    private func setupDelegates() {
        hudInput.delegate = self
        hudDisplay.delegate = self
        hudDisplay.isPanelDragging = { [weak hudInput = self.hudInput] in
            hudInput?.panelDragActive ?? false
        }
        hudDisplay.onDragActive = { [weak self] active in
            self?.setExternalDragActive(active)
        }
        hudDisplay.onSpaceDragStart = { [weak self] source in
            self?.setExternalDragSourceSpace(source)
        }
        hudDisplay.onSpaceDrop = { [weak self] source, _ in
            self?.handleSpaceDrop(source: source)
        }
        hudDisplay.onWindowDragStart = { [weak self] source in
            self?.setExternalDragSourceSpace(source)
        }
        hudDisplay.onWindowDrop = { [weak self] ids, source, _ in
            self?.handleWindowDrop(ids: ids, source: source)
        }
        hudInput.quartzPointConverter = { [weak hudDisplay = self.hudDisplay] point in
            hudDisplay?.quartzPoint(fromAppKit: point) ?? point
        }
        hudInput.updateConfig(
            hudKeys: config.hudKeyBindings,
            jumpToSpaceEnabled: config.jumpToSpaceEnabled,
            fuzzySpaceJumpEnabled: config.effectiveFuzzySpaceJumpEnabled
        )
        hudInput.yabaiService = services.yabaiService
        hudInput.config = config
        hudInput.hudStateSync = coordinator
        hudInput.hudDisplay = hudDisplay
        hudInput.onRefresh = { [weak self] in self?.refresh() }
        hudInput.onShowSettings = { [weak self] in self?.showSettings() }
        hudInput.onNumberEntry = { [weak self] feedback in self?.hudDisplay.updateDisplayNumber(feedback) }
        hudInput.onTypedText = { [weak self] text in self?.hudDisplay.updateDisplayTypedText(text) }
        hudInput.onPanelDragEnded = { [weak self] in self?.hudDisplay.savePanelPosition() }
        hudInput.onAccessibilityRevoked = { [weak self] in self?.hide() }
        // Drag targeting is controller glue: the presenter decides when a
        // presentation is live, the drag handler owns hover and drop events.
        presenter.isDragging = { [weak self] in self?.dragHandler.isDragging ?? false }
        // Every hide path — toggle, pin, close, settings, Accessibility
        // revocation, auto-hide — must run the same drag teardown.
        presenter.onHide = { [weak self] in self?.teardownDragGlue() }
        presenter.onRendered = { [weak self] _ in self?.dragHandler.start() }
        presenter.onFocusedWindowResolved = { [weak self] focusedWindowID, state in
            guard let self else { return }
            self.focusedWindowIDAtOpen = focusedWindowID
            let cellFrames = self.hudDisplay.computeCellFrames(state: state)
            self.dragHandler.updateInput(WindowDragInput(
                cellFrames: cellFrames,
                cachedWindows: state.windows,
                focusedWindowIDAtOpen: focusedWindowID
            ))
        }
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, self.isVisible, self.presenter.state != nil else { return }
            self.handleHoverCell(cell)
        }
        dragHandler.onDropInCell = { [weak self] windowID, spaceIndex, modifiers in
            guard let self, self.isVisible else { return }
            self.presenter.clearHover()
            self.presenter.setAutoHideSuppressed(false)
            let focusDestination = self.config.focusSpaceOnWindowDrop.shouldFocus(
                eventFlags: modifiers,
                requiredModifier: self.config.focusSpaceOnWindowDropModifier
            )
            self.services.yabaiService.moveWindowCreatingSpacesIfNeeded(
                windowID,
                toSpace: spaceIndex,
                focusDestination: focusDestination
            ) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result { NSLog("spacemap/HUD: window drop failed: \(error.localizedDescription)") }
                // No presentation token here: refresh() self-guards isVisible,
                // unlike complete(), which needs the token.
                self.presenter.refresh()
                self.presenter.resetAutoHideTimer()
            }
        }
        dragHandler.onRequestDragSnapshot = { [weak self] requestGeneration in
            guard let self else { return }
            let presentation = self.presenter.currentPresentation()
            self.services.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self else { return }
                let focusedWindowID = try? self.services.yabaiService.queryFocusedWindow()
                let windows = (try? self.services.yabaiService.queryWindows()) ?? []
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.isVisible,
                          self.presenter.isCurrent(presentation) else { return }
                    self.dragHandler.applyDragSnapshot(
                        focusedWindowID: focusedWindowID,
                        windows: windows,
                        generation: requestGeneration
                    )
                }
            }
        }
    }

    /// Cell-crossing hover: only the presenter's hover and auto-hide channels
    /// change. No icons, thumbnails, rendering or panel resizing.
    func handleHoverCell(_ cell: Int?) {
        presenter.handleHoverCell(cell)
    }

    /// Test seam: the input's drag target must be the live HUD panel.
    var inputPanel: NSPanel? { hudInput.currentPanel }
    var hudDisplayForTesting: HUDDisplay { hudDisplay }
    var seededFocusedSpaceIndex: Int? { hudInput.lastFocusedSpaceIndex }
    var isAutoHideScheduled: Bool { presenter.isAutoHideScheduled }

    func toggle() {
        debouncedToggle { [weak self] in
            guard let self else { return }
            self.isPinned = false
            self.isVisible ? self.hide() : self.show()
        }
    }

    func togglePinned() {
        debouncedToggle { [weak self] in
            guard let self else { return }
            if self.isVisible, self.isPinned { self.hide() }
            else { self.isPinned = true; self.isVisible ? self.presenter.resetAutoHideTimer() : self.show() }
        }
    }
    func pin() {
        guard !(isVisible && isPinned) else { return }
        debouncedToggle { [weak self] in
            guard let self else { return }
            self.isPinned = true
            self.isVisible ? self.presenter.resetAutoHideTimer() : self.show()
        }
    }
    private func debouncedToggle(_ action: @escaping () -> Void) {
        guard !isToggling else { return }
        isToggling = true
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isToggling = false }
    }
    func show() {
        guard !isVisible else { return }
        reloadConfigIfChanged()
        presenter.show(config: config)
        reconcilePanelDragMonitor()
    }
    func prewarmState() {
        presenter.prewarmState()
    }
    func startPollTimer() {
        hudInput.startPollTimer()
    }
    /// Space under an AppKit screen point while the HUD is up. Uses the same
    /// Quartz cell frames as window drag, so hit testing follows the real grid.
    var externalDropTarget: Int?
    private var externalDragMonitor: Any?
    /// The strip's space drag does not target its own source space.
    private var externalDragSourceSpace: Int?

    func spaceIndex(atAppKitScreenPoint point: NSPoint) -> Int? {
        guard isVisible, let state = presenter.state else { return nil }
        let quartz = hudDisplay.quartzPoint(fromAppKit: point)
        let frames = hudDisplay.computeCellFrames(state: state)
        // Only the cell directly under the pointer highlights, so the visual
        // target matches the cursor position exactly.
        return frames.first(where: { $0.frame.contains(quartz) })?.spaceIndex
    }

    /// Drags that start in the glyph strip or on a HUD cell must not let the
    /// auto-hide timer close the HUD mid-drop.
    func setExternalDragSourceSpace(_ space: Int?) {
        externalDragSourceSpace = space
        updateExternalDropTarget()
    }

    func setExternalDragActive(_ active: Bool) {
        presenter.setAutoHideSuppressed(active)
        externalDragPoll?.invalidate()
        externalDragPoll = nil
        if let monitor = externalDragMonitor {
            NSEvent.removeMonitor(monitor)
            externalDragMonitor = nil
        }
        guard active else {
            externalDropTarget = nil
            externalDragSourceSpace = nil
            hudDisplay.setExternalDropTarget(nil)
            return
        }
        updateExternalDropTarget()
        // Pointer events track the cursor exactly; the timer only covers a
        // pointer that rests without moving.
        externalDragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.updateExternalDropTarget()
            return event
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateExternalDropTarget()
        }
        RunLoop.main.add(timer, forMode: .common)
        externalDragPoll = timer
    }

    private func updateExternalDropTarget() {
        let hovered = spaceIndex(atAppKitScreenPoint: NSEvent.mouseLocation)
        let target = hovered == externalDragSourceSpace ? nil : hovered
        guard externalDropTarget != target else { return }
        externalDropTarget = target
        hudDisplay.setExternalDropTarget(target)
    }

    func handleSpaceDrop(source: Int) {
        // Same value the cell highlight is showing, so the swap always lands
        // on the highlighted space.
        guard let target = externalDropTarget, source != target else { return }
        services.yabaiService.swapSpaces(source, target, mode: config.spaceDropMode, focusMode: config.spaceDragFocus)
    }

    func handleWindowDrop(ids: [Int], source: Int) {
        guard !ids.isEmpty, let target = externalDropTarget, source != target else { return }
        services.yabaiService.moveWindows(ids, toSpace: target, focusMode: config.windowDragFocus, sourceSpace: source)
    }

    func hide() {
        presenter.hide()
    }

    /// Drag glue for every hide path. The presenter's `onHide` hook runs it
    /// once the presentation is gone, which matches HEAD's ordering.
    private func teardownDragGlue() {
        dragHandler.stop()
        externalDropTarget = nil
        externalDragSourceSpace = nil
        focusedWindowIDAtOpen = nil
        dragHandler.updateInput(WindowDragInput(cellFrames: [], cachedWindows: [], focusedWindowIDAtOpen: nil))
    }
    func refresh() {
        presenter.refresh()
    }
    func reloadConfig() {
        _config = nil
        services.themeStore.reloadIfChanged()
        hudInput.config = config
        hudInput.updateConfig(
            hudKeys: config.hudKeyBindings,
            jumpToSpaceEnabled: config.jumpToSpaceEnabled,
            fuzzySpaceJumpEnabled: config.effectiveFuzzySpaceJumpEnabled
        )
        hudDisplay.updateConfig(config)
        coordinator.reloadConfig()
        reconcilePanelDragMonitor()
    }
    private func reloadConfigIfChanged() {
        let mtime: Date? = (try? FileManager.default.attributesOfItem(atPath: services.configStore.configPath))?[.modificationDate] as? Date
        guard !didCheckConfigMtime || mtime != lastConfigMtime else { return }
        didCheckConfigMtime = true
        lastConfigMtime = mtime
        reloadConfig()
    }
    /// Panel-drag positioning only applies to the single unified active
    /// panel; reconcile on show and on config reload so toggling the custom
    /// position takes effect without a hide/show cycle.
    private func reconcilePanelDragMonitor() {
        let current = config
        if isVisible,
           current.multiMonitorHUDMode == .unified,
           current.unifiedHUDVisibility == .active,
           case .custom = current.hudPosition {
            hudInput.startPanelDragMonitor()
        } else {
            hudInput.stopPanelDragMonitor()
        }
    }
}
extension HUDWindowController: HUDInputDelegate {
    /// Every matched HUD key arrives here. Legacy scalar keys and `[hudKeys]`
    /// bindings share this one path.
    func perform(_ command: HUDCommand) {
        switch command {
        case .left: navigate(direction: .left)
        case .right: navigate(direction: .right)
        case .up: navigate(direction: .up)
        case .down: navigate(direction: .down)
        case .first: hudInput.navigateToFirst()
        case .last: hudInput.navigateToLast()
        case .recent: focusRecent()
        case .close: hide()
        case .newSpace: createSpace()
        case .newSpaceAndFocus: createAndFocusNewestSpace()
        case .deleteSpace: destroyCurrentSpace()
        case .layoutBSP: setSpaceLayout(.bsp)
        case .layoutStack: setSpaceLayout(.stack)
        case .layoutFloat: setSpaceLayout(.float)
        case .cycleLayout: cycleSpaceLayout()
        case .moveSpaceBack: moveSpace(direction: .left)
        case .moveSpaceForward: moveSpace(direction: .right)
        case .previousSpace: hudInput.navigateToPreviousSpace()
        case .nextSpace: hudInput.navigateToNextSpace()
        }
    }

    func navigate(direction: SpaceNavigationDirection) { hudInput.navigate(direction: direction) }
    func focusRecent() {
        // "recent" is a named selector; SpaceFocusTarget never fails for it.
        guard let target = SpaceFocusTarget(argument: "recent") else { return }
        // focusSpaceAsync only accepts numeric indices, so run the target
        // form on yabaiQueue instead: yabai can block up to 10s and must
        // never stall the main thread (same as every other entry point).
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            _ = self.services.yabaiService.focusSpace(target)
            // Pull the new focus back immediately so the highlight and the
            // next arrow key operate on the actual current space.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible else { return }
                self.presenter.refresh()
            }
        }
    }
    func createSpace() {
        // The presenter drops the result if the HUD closed while the space was
        // being created.
        let presentation = presenter.currentPresentation()
        spaceCommands.createSpace { [weak self] newest in
            guard let self, let newest else { return }
            self.presenter.complete(presentation, notice: "Space \(newest) Created")
        }
    }
    func createAndFocusNewestSpace() {
        presenter.refresh()
        let presentation = presenter.currentPresentation()
        spaceCommands.createAndFocusNewestSpace { [weak self] newest in
            guard let self, let newest else { return }
            self.presenter.complete(presentation, notice: "Space \(newest) Created")
        }
    }
    func destroyCurrentSpace() {
        guard let focused = presenter.state?.focusedIndex else { return }
        // yabai itself falls back to the first space after a destroy. Keep the
        // user's place instead: focus the space just before it once the destroy
        // has landed, so the quick auto-jump is corrected.
        let previous = presenter.state?.spaces.map(\.index).filter { $0 < focused }.max()
        let presentation = presenter.currentPresentation()
        presenter.showNotice("Space \(focused) Deleted")
        spaceCommands.destroySpace(focused, previous: previous) { [weak self] in
            self?.presenter.complete(presentation)
        }
    }
    func setSpaceLayout(_ layout: SpaceLayout) {
        spaceCommands.setLayout(layout)
        presenter.showNotice(Self.layoutNotice(layout))
        presenter.refresh()
    }
    func cycleSpaceLayout() {
        guard let focused = presenter.state?.focusedIndex,
              let current = presenter.state?.spaces.first(where: { $0.index == focused })?.type else { return }
        setSpaceLayout(spaceCommands.cycleLayout(from: current))
    }

    private static func layoutNotice(_ layout: SpaceLayout) -> String {
        switch layout {
        case .bsp: return "BSP Layout"
        case .stack: return "Stack Layout"
        case .float: return "Float Layout"
        }
    }
    func moveSpace(direction: SpaceNavigationDirection) {
        let presentation = presenter.currentPresentation()
        guard let moved = spaceCommands.moveSpace(
            focusedIndex: presenter.state?.focusedIndex,
            indices: presenter.state?.spaces.map(\.index) ?? [],
            direction: direction,
            mode: config.spaceDropMode
        ) else { return }
        presenter.complete(presentation, notice: "Space \(moved) Moved", after: 0.25)
    }

    func showSettings() { hide(); onShowSettings?() }
}
extension HUDWindowController: HUDDisplayDelegate {
    func render(state: GridState) {}
    func updateCellFrames(state: GridState) {
        let frames = hudDisplay.computeCellFrames(state: state)
        hudInput.updateCellFrames(frames)
        // Panels are created/replaced during render; keep the drag monitor's
        // target pointed at the live unified panel or custom positioning dies.
        hudInput.updatePanel(hudDisplay.unifiedPanel)
        dragHandler.updateInput(WindowDragInput(
            cellFrames: frames,
            cachedWindows: state.windows,
            focusedWindowIDAtOpen: focusedWindowIDAtOpen
        ))
    }
}
