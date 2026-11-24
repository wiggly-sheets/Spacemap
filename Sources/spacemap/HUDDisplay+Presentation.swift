import AppKit
import SwiftUI

extension HUDDisplay {
    /// Installs the SwiftUI grid in the panel's glass container. The container
    /// keeps a native glass sibling below the content so the effect samples the
    /// window backdrop, as it does in System Settings and the glyph strip.
    /// Fades the panel in only on a fresh presentation, so repeated state
    /// renders do not re-animate it. Respects the global animation switch.
    func present(_ panel: NSPanel) {
        guard !panel.isVisible else {
            panel.orderFrontRegardless()
            return
        }
        // NSAnimationContext needs a running app; unit tests create windows but
        // do not spin an app event loop, so animate only in the real app.
        guard PanelPresenter.canAnimate(currentConfig.hudAnimationsEnabled) else {
            presenter.present(panel, duration: 0, animated: false)
            return
        }
        let target = panel.frame
        let start = entranceFrame(currentConfig.hudEntranceStyle, for: panel) ?? target
        panel.alphaValue = 0
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = currentConfig.hudAnimationStyle.fadeDuration
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func dismiss(_ panel: NSPanel) {
        guard panel.isVisible, currentConfig.hudAnimationsEnabled, NSApp != nil, NSApp.isRunning else {
            panel.orderOut(nil)
            return
        }
        let target = panel.frame
        let end = entranceFrame(currentConfig.hudEntranceStyle, for: panel) ?? target
        NSAnimationContext.runAnimationGroup { context in
            context.duration = currentConfig.hudAnimationStyle.fadeDuration
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.setFrame(target, display: false)
            panel.alphaValue = 1
        }
    }

    /// Frame the panel animates from or to for an entrance style. `nil` means
    /// a plain fade. Slides leave the screen from a chosen edge; scale grows
    /// from a slightly smaller frame.
    func entranceFrame(_ style: HUDEntranceStyle, for panel: NSPanel) -> CGRect? {
        guard let screen = panel.screen ?? NSScreen.main else { return nil }
        let frame = panel.frame
        let area = screen.frame
        switch style {
        case .fade:
            return nil
        case .slideFromLeft:
            return frame.offsetBy(dx: area.minX - frame.maxX, dy: 0)
        case .slideFromRight:
            return frame.offsetBy(dx: area.maxX - frame.minX, dy: 0)
        case .slideFromTop:
            return frame.offsetBy(dx: 0, dy: area.maxY - frame.minY)
        case .slideFromBottom:
            return frame.offsetBy(dx: 0, dy: area.minY - frame.maxY)
        case .scale:
            return frame.insetBy(dx: frame.width * 0.04, dy: frame.height * 0.04)
        }
    }

    func installContent(_ hostingView: NSView, in panel: NSPanel, size: CGSize) {
        let container: HUDGlassContainerView
        if let existing = panel.contentView as? HUDGlassContainerView {
            container = existing
        } else {
            container = HUDGlassContainerView()
            panel.contentView = container
        }
        container.configure(hosting: hostingView, size: size, appearance: hudGlassAppearance)
    }

    func makeGridView(
        state: GridState,
        hoveredCell: Int?,
        spaceIndices: [Int]? = nil
    ) -> GridView {
        GridView(state: state, hoveredCell: hoveredCell, hoverState: hoverState, numberState: numberState, noticeState: noticeState, onSelect: { [weak self] index in
            self?.yabaiService.focusSpaceAsync(index)
            self?.delegate?.hide()
        }, uiScale: currentConfig.uiScale, theme: currentConfig.theme,
           resolvedTheme: themeStore.named(currentConfig.theme), spaceIndices: spaceIndices,
           usesNativeGlass: Self.nativeGlassAvailable && currentConfig.backgroundStyle == .glass,
           hudAnimation: currentConfig.hudAnimationsEnabled ? currentConfig.hudAnimationStyle : nil,
           onSpaceDrop: onSpaceDrop,
           onWindowDrop: onWindowDrop,
           onDragActive: onDragActive,
           onSpaceDragStart: onSpaceDragStart,
           onWindowDragStart: onWindowDragStart)
    }

    func cellFrames(for cells: [Int], in panel: NSPanel) -> [(spaceIndex: Int, frame: CGRect)] {
        ScreenContext.cellFrames(
            for: cells,
            panelFrame: panel.frame,
            config: currentConfig,
            quartzMaxY: quartzMainScreenFrame.maxY
        )
    }
}
