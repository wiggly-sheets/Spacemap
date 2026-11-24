import AppKit
import SwiftUI

protocol HUDDisplayDelegate: AnyObject {
    func render(state: GridState)
    func updateCellFrames(state: GridState)
    func show()
    func hide()
}
final class HUDDisplay {
    weak var delegate: HUDDisplayDelegate?

    var panel: NSPanel?
    var displayPanels: [Int: NSPanel] = [:]
    var hostingView: NSHostingView<AnyView>?
    var displayHostingViews: [Int: NSHostingView<AnyView>] = [:]
    var currentConfig: SpacemapConfig = .default
    var hoveredCell: Int? = nil
    /// Typed-number readout channel. Separate from the rendered grid so a
    /// digit repaints the overlay only.
    let numberState = HUDNumberState()
    let noticeState = HUDNoticeState()
    var renderedState: GridState?
    var yabaiService: YabaiService
    let themeStore: ThemeStore
    /// Panel lifecycle: window construction and the non-motion ordering path.
    /// Entrance motion stays here because the frames are HUD-style policy.
    let presenter = PanelPresenter()
    /// Shared, cheap hover channel for the rendered grid. Hover changes only
    /// mutate this observable, so SwiftUI repaints the border/background of
    /// the affected cells without icon/thumbnail work or panel resizing.
    let hoverState = HUDHoverState()
    var showingThumbnails = false

    /// Test-visible work counters: hover must not bump these.
    var fullRenderCount = 0
    var iconPreloadCount = 0
    var thumbnailRefreshCount = 0

    var unifiedPanel: NSPanel? { panel }
    var displayPanelIndices: Set<Int> { Set(displayPanels.keys) }
    /// Test seam: when set, display matching uses these frames instead of the
    /// host's `NSScreen.screens`, so panel tests do not depend on the CI
    /// machine's monitor count.
    var screenFramesOverride: [CGRect]?
    /// Supplied by the controller: true while the user is dragging the panel.
    /// A signal-driven render mid-drag must not snap it back.
    var isPanelDragging: (() -> Bool)?
    /// Drag feedback owned by the controller: suppress auto-hide, and resolve
    /// a drop onto a space cell.
    var onDragActive: ((Bool) -> Void)?
    var onSpaceDrop: ((Int, NSPoint) -> Void)?
    var onWindowDrop: (([Int], Int, NSPoint) -> Void)?
    var onSpaceDragStart: ((Int) -> Void)?
    var onWindowDragStart: ((Int) -> Void)?

    init(yabaiService: YabaiService, themeStore: ThemeStore) {
        self.yabaiService = yabaiService
        self.themeStore = themeStore
    }

    func updateConfig(_ config: SpacemapConfig) {
        let wasShowingThumbnails = currentConfig.cellStyle == .thumbnails
        currentConfig = config
        panel?.hasShadow = config.hudShadow
        displayPanels.values.forEach { $0.hasShadow = config.hudShadow }
        if wasShowingThumbnails, config.cellStyle != .thumbnails {
            clearThumbnailsIfNeeded()
        }
    }

    /// Highlight the cell a drag would drop onto. Separate from pointer hover:
    /// external drags own the highlight until they end.
    func setExternalDropTarget(_ spaceIndex: Int?) {
        guard hoverState.cell != spaceIndex else { return }
        hoverState.cell = spaceIndex
    }

    func updateDisplayNumber(_ feedback: HUDNumberFeedback?, clearAfter delay: TimeInterval? = nil) {
        // A clear must always land: the setting can flip off mid-hold, and a
        // dropped nil would leave stale text in the overlay.
        guard feedback == nil || currentConfig.showHUDInteractionFeedback else { return }
        numberState.update(feedback, clearAfter: delay)
    }

    /// Typed letters for a fuzzy space-name jump, gated like digit feedback and
    /// drawn by the same overlay.
    func updateDisplayTypedText(_ feedback: HUDTypedFeedback?) {
        guard feedback == nil || currentConfig.showHUDInteractionFeedback else { return }
        numberState.updateTypedText(feedback)
    }

    /// Action feedback is optional; the action itself never depends on it.
    func showNotice(_ text: String) {
        guard currentConfig.showHUDInteractionFeedback else { return }
        noticeState.show(text)
    }

    var thumbnailClearWorkItem: DispatchWorkItem?

    func updateHoveredCell(_ cell: Int?) {
        guard hoveredCell != cell || hoverState.cell != cell else { return }
        hoveredCell = cell
        hoverState.cell = cell
    }

    func show() {
        thumbnailClearWorkItem?.cancel()
        thumbnailClearWorkItem = nil
        delegate?.show()
    }

    func hide() {
        // Clear hover before hiding: no drop-target border may survive into
        // the next presentation. Panels/hosting views stay alive so the next
        // show does not rebuild the whole window tree.
        hoveredCell = nil
        hoverState.cell = nil
        renderedState = nil
        if #available(macOS 14.0, *) {
            ThumbnailCache.shared.cancel()
            // Captures are cancelled now, but the last frames are useful if the
            // HUD reopens soon. Drop them after a delay to bound retention.
            thumbnailClearWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let visible = (self.panel?.isVisible ?? false) ||
                    self.displayPanels.values.contains { $0.isVisible }
                if !visible { ThumbnailCache.shared.clear() }
                self.thumbnailClearWorkItem = nil
            }
            thumbnailClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        }
        if let panel { dismiss(panel) }
        for displayPanel in displayPanels.values {
            dismiss(displayPanel)
        }
        delegate?.hide()
    }

    /// Single panel-sync path: a state update is a full render. Panels are
    /// created, removed, positioned and rooted exactly like `render`, so an
    /// async icon landing or focus change cannot leave stale panels behind.
    func updateState(_ state: GridState) {
        render(state: state)
    }

    static let hudPositionChangedNotification = Notification.Name("hudPositionChanged")

    /// Native glass is only possible when the compiler, OS, and accessibility
    /// settings all allow it; otherwise SwiftUI draws its own material.
    static var nativeGlassAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return GlassSupport.isAvailable }
        #endif
        return false
    }

    var hudGlassAppearance: HUDGlassContainerView.Appearance {
        HUDGlassContainerView.Appearance(
            enabled: currentConfig.backgroundStyle == .glass && Self.nativeGlassAvailable,
            style: currentConfig.glassStyle,
            tintedMaterial: currentConfig.glassTintedMaterial,
            opacity: CGFloat(currentConfig.effectiveBackgroundOpacity(for: .glass)),
            tint: GlyphStrip.color(for: "focused", theme: themeStore.named(currentConfig.theme))
                ?? .controlAccentColor,
            cornerRadius: CGFloat(currentConfig.hudCornerRadius),
            variant: currentConfig.glassStyle == .clear
                ? currentConfig.glassClearVariant
                : (currentConfig.glassStyle == .regular
                    ? currentConfig.glassRegularVariant
                    : currentConfig.glassTintedVariant)
        )
    }

    var quartzMainScreenFrame: CGRect {
        ScreenContext.mainScreenFrame()
    }

}
