import AppKit
import ApplicationServices
import CoreText

extension GlyphStripPanelController {
    // MARK: - Panel

    /// AppKit can leave the strip pinned to the space where it was ordered
    /// out during a fullscreen transition. Re-register the panel on the active
    /// space, then restore all-spaces membership so the next space switch
    /// carries it along.
    func reattachPanelToActiveSpace() {
        guard config.glyphStrip.enabled,
              config.glyphStrip.displayMode == .floating,
              !hiddenByHotkey,
              !hiddenByFullscreen,
              !hiddenByMissionControl,
              let panel,
              panel.isVisible else { return }
        // Each behavior change needs its own run-loop turn; the window server
        // ignores a move that is undone in the same turn.
        panel.collectionBehavior = .managed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak panel] in
            guard let panel else { return }
            panel.collectionBehavior = .moveToActiveSpace
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak panel] in
                panel?.collectionBehavior = Self.stripCollectionBehavior
            }
        }
    }

    /// Creates the panel on first use, then always lays it out. Ordering front
    /// happens only when the panel is not already visible, so steady-state
    /// refreshes do not re-order the panel on every yabai signal.
    func present() {
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByFullscreen, !hiddenByMissionControl else {
            hide()
            return
        }
        if config.glyphStrip.displayMode == .menuBarItem {
            presentMenuBarItem()
            return
        }
        removeStatusItem()
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        applyFrame(to: panel)
        if !panel.isVisible {
            presenter.present(
                panel,
                duration: config.hudAnimationStyle.fadeDuration,
                animated: PanelPresenter.canAnimate(config.hudAnimationsEnabled)
            )
        }
        if let glyphs {
            NSAccessibility.post(element: glyphs, notification: .layoutChanged)
        }
    }

    func hide() {
        // A menu-bar item is a separate surface; ordering out the panel does
        // not remove it. Drop it before any early return so hotkey, fullscreen,
        // and disabled hides all take effect.
        removeStatusItem()
        // An in-flight refresh must not re-present a strip the user just hid or
        // disabled. Bumping the generation makes every pending reply stale, and
        // cancelling the coalesced work stops a queued pass from starting.
        refreshGeneration += 1
        pendingRefresh?.cancel()
        pendingRefresh = nil
        needsFollowupRefresh = false
        refreshInFlight = false
        inFlightGeneration = 0
        guard let panel else { return }
        presenter.hide(
            panel,
            duration: config.hudAnimationStyle.fadeDuration,
            animated: PanelPresenter.canAnimate(config.hudAnimationsEnabled)
        )
    }

    private func makePanel() -> NSPanel {
        // Glass floats over the menu bar; the shadow separates its edge. The
        // `.statusBar` level keeps the strip above menu bar items.
        let panel = presenter.makePanel(PanelPresenter.Surface(
            level: .statusBar,
            hasShadow: true,
            collectionBehavior: Self.stripCollectionBehavior,
            hidesOnDeactivate: false
        ))
        let container = GlyphStripContainerView(controller: self)
        glyphs = container.glyphs
        panel.contentView = container
        return panel
    }

    func applyFrame() {
        guard let panel else { return }
        applyFrame(to: panel)
    }

    func applyFrame(to panel: NSPanel, screen explicitScreen: NSScreen? = nil) {
        let screen = explicitScreen ?? targetScreen()
        let strip = config.glyphStrip
        let hasNotch = screen.map(Self.hasNotch) ?? false
        let placement = strip.placement(hasNotch: hasNotch)
        let custom = strip.customPlacement(hasNotch: hasNotch)
        let row = ScreenContext.menuBarRow(on: screen)
        // Free placement can leave the menu bar row, so `presentationFrame`
        // there is the whole display. Anchored positions keep the row.
        // Dragging stays free: the pointer can reach any screen edge. The safe
        // area only decides when a tall strip wraps into more columns.
        let area = placement.position == .custom ? ScreenContext.screenFrame(on: screen) : row
        let availableHeight = placement.position == .custom
            ? ScreenContext.safeScreenFrame(on: screen).height
            : row.height
        // A transparent strip draws no backdrop, so its only opaque pixels are
        // the glyphs and the window server would cast their outline as a black
        // shadow. Only shadow a surface that actually paints a shape.
        panel.hasShadow = strip.resolvedBackgroundMaterial(hud: config) != .none
        let frame = GlyphStrip.frame(
            contentSize: stripContentSize(
                rowHeight: row.height,
                availableHeight: availableHeight,
                position: placement.position
            ),
            menuBarRow: row,
            screenFrame: area,
            leftNotchArea: screen?.auxiliaryTopLeftArea,
            rightNotchArea: screen?.auxiliaryTopRightArea,
            position: placement.position,
            margin: placement.margin,
            xFraction: custom.x,
            yFraction: custom.y
        )
        // A custom strip can be dragged into the menu bar row. The menu bar
        // window covers anything below it, so raise the strip above the bar
        // there while keeping free placement below it everywhere else.
        // Anchored placements always need the status-bar level.
        panel.level = GlyphStrip.usesMenuBarLevel(
            position: placement.position,
            frame: frame,
            menuBarRow: row
        ) ? .statusBar : .floating
        // Only move the window when the frame changed, but always repaint:
        // content can change (new glyphs, focus, theme) at an identical frame.
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        contentRepaintCount += 1
        glyphs?.needsDisplay = true
    }

    /// Slot size for the panel: one horizontal row in the menu bar, or one
    /// stacked block per space when `.custom` renders vertically.
    private func stripContentSize(
        rowHeight: CGFloat,
        availableHeight: CGFloat,
        position: GlyphStripPosition
    ) -> CGSize {
        guard isVerticalLayout(position: position) else {
            let horizontal = CGFloat(config.glyphStrip.resolvedHorizontalPadding) * 2
            // An anchored strip is pinned to the menu-bar row, so vertical
            // padding can only move the glyphs inside it. A free strip owns
            // its height, so padding grows the panel around the row.
            let vertical = position == .custom
                ? CGFloat(config.glyphStrip.resolvedVerticalPadding) * 2
                : 0
            return CGSize(
                width: max(segmentWidths.reduce(0, +) + horizontal, 1),
                height: rowHeight + vertical
            )
        }
        var width: CGFloat
        if isStackedVertical {
            // Each line holds one run, so the widest run sets the strip width.
            let widest = attributedRuns
                .map { runs in runs.map { $0.size().width }.max() ?? 0 }
                .max() ?? 0
            width = widest + Self.horizontalPadding * 2
        } else {
            width = segmentWidths.max() ?? 0
        }
        width += CGFloat(config.glyphStrip.resolvedHorizontalPadding) * 2
        let padding = CGFloat(config.glyphStrip.resolvedVerticalPadding)
        let total = verticalTotalHeight
        let available = max(availableHeight - padding * 2, 1)
        let columns = GlyphStrip.verticalColumnCount(totalHeight: total, available: available)
        let columnsWidth = columns > 1
            ? width * CGFloat(columns) + Self.verticalColumnGap * CGFloat(columns - 1)
            : width
        let height = columns > 1 ? available : total
        return CGSize(width: max(columnsWidth, 1), height: max(height + padding * 2, 1))
    }

    /// Vertical stacking only applies to free placement; anchored positions
    /// stay in the single menu-bar row.
    func isVerticalLayout(position: GlyphStripPosition) -> Bool {
        config.glyphStrip.displayMode == .floating
            && position == .custom
            && config.glyphStrip.orientation == .vertical
    }

    /// Layout for the display the strip currently sits on.
    var isVerticalLayout: Bool {
        isVerticalLayout(position: resolvedPlacement.position)
    }

    /// Strip content box. Both axes are inset, so split padding works for
    /// horizontal and vertical layouts alike.
    func contentBounds(in bounds: CGRect) -> CGRect {
        // Keep a drawable pixel when padding exceeds the panel dimension.
        let dx = min(CGFloat(config.glyphStrip.resolvedHorizontalPadding), max((bounds.width - 1) / 2, 0))
        let dy = min(CGFloat(config.glyphStrip.resolvedVerticalPadding), max((bounds.height - 1) / 2, 0))
        return bounds.insetBy(dx: dx, dy: dy)
    }

    /// Icons under the number, one per line, instead of beside it.
    var isStackedVertical: Bool {
        isVerticalLayout && config.glyphStrip.verticalLayout == .stacked
    }

    /// Height of one glyph line: the tallest glyph box.
    var contentLineHeight: CGFloat { max(contentHeight, 1) }

    /// Slot height for an inline vertical space, with hover breathing room.
    fileprivate var verticalLineHeight: CGFloat {
        contentLineHeight + hoverPadding * 2
    }

    /// Number of drawn lines in a vertical segment. Inline vertical is always
    /// one line; stacked vertical spends one line per run.
    fileprivate func verticalLineCount(_ index: Int) -> Int {
        guard isStackedVertical, attributedRuns.indices.contains(index) else { return 1 }
        return max(attributedRuns[index].count, 1)
    }

    /// Gap before stacked line `index`: `indexPadding` once between the number
    /// and the first icon, `iconSpacing` between icons after that.
    func stackedGap(before index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        return CGFloat(index == 1 ? config.glyphStrip.indexPadding : config.glyphStrip.iconSpacing)
    }

    func verticalSegmentHeight(_ index: Int) -> CGFloat {
        guard isStackedVertical else { return verticalLineHeight }
        let lines = verticalLineCount(index)
        let gaps = (1..<max(lines, 1)).reduce(CGFloat(0)) { $0 + stackedGap(before: $1) }
        return CGFloat(lines) * contentLineHeight + gaps + hoverPadding * 2
    }

    var verticalTotalHeight: CGFloat {
        guard !attributedRuns.isEmpty else { return verticalLineHeight }
        return attributedRuns.indices.reduce(0) { $0 + verticalSegmentHeight($1) }
    }
}
