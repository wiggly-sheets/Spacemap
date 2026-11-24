import AppKit
import ApplicationServices
import CoreText

extension GlyphStripPanelController {
    func presentMenuBarItem() {
        panel?.orderOut(nil)
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = ""
            item.button?.imagePosition = .noImage
            let view = GlyphStripStatusView(controller: self)
            view.autoresizingMask = [.width, .height]
            item.button?.addSubview(view)
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            statusView = view
            statusItem = item
        }
        updateStatusItem()
    }

    func removeStatusItem() {
        statusView?.cancelGesture()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusView = nil
    }

    func updateStatusItem() {
        guard let statusItem, let button = statusItem.button else { return }
        guard config.glyphStrip.displayMode == .menuBarItem else { return }
        let horizontal = CGFloat(config.glyphStrip.resolvedHorizontalPadding) * 2
        let width = min(
            max(segmentWidths.reduce(0, +) + horizontal, 1),
            ScreenContext.screenFrame(on: NSScreen.main).width * 0.8
        )
        // Reassigning the length makes the menu bar relayout the whole item.
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
        if statusView?.frame != button.bounds {
            statusView?.frame = button.bounds
        }
        statusView?.refreshHover()
        statusView?.needsLayout = true
        statusView?.needsDisplay = true
    }

    /// The status-bar button can own the click tracking even when its custom
    /// subview draws the strip. Use the button action as a fallback so a click
    /// that never reaches `GlyphStripStatusView.mouseDown` still focuses.
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent, let view = statusView else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        view.handleButtonClick(at: point, eventTime: event.timestamp)
    }
}
