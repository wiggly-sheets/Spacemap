import AppKit
import SwiftUI

extension HUDDisplay {
    /// Panel-position normalization shared with `HUDPosition.custom.point`:
    /// fraction 0 sits at the screen origin, fraction 1 fully right/bottom.
    /// Storing a mid-panel fraction (the old code) made the round trip move
    /// the panel by half its size on the next show.
    static func normalizedPosition(panelFrame: CGRect, screenFrame: CGRect) -> CGPoint? {
        let rangeX = screenFrame.width - panelFrame.width
        let rangeY = screenFrame.height - panelFrame.height
        guard rangeX > 0, rangeY > 0 else { return nil }
        return CGPoint(
            x: (panelFrame.minX - screenFrame.minX) / rangeX,
            y: (panelFrame.minY - screenFrame.minY) / rangeY
        )
    }

    /// The custom position a panel frame represents on `screen`: the same
    /// fraction `normalizedPosition` computes plus that display's identity.
    /// Nil when the panel is larger than the screen, so no fraction exists.
    /// Fractions are clamped: a drag can push the panel past a screen edge,
    /// and the decoder rejects out-of-range values, which would reset the
    /// position to Center.
    static func customPosition(
        panelFrame: CGRect,
        screenFrame: CGRect,
        screen: NSScreen
    ) -> HUDPosition? {
        guard let normalized = normalizedPosition(panelFrame: panelFrame, screenFrame: screenFrame) else {
            return nil
        }
        return .custom(
            x: Double(min(max(normalized.x, 0), 1)),
            y: Double(min(max(normalized.y, 0), 1)),
            screen: ScreenContext.displayIdentifier(for: screen)
        )
    }

    func restoredCustomScreenFrame() -> CGRect? {
        guard let identifier = currentConfig.hudPosition.screenIdentifier,
              let screen = ScreenContext.screen(matchingIdentifier: identifier)
        else { return nil }
        return screen.frame
    }

    func savePanelPosition() {
        guard let panel = unifiedPanel ?? displayPanels.first?.value else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        guard let position = Self.customPosition(
            panelFrame: panel.frame,
            screenFrame: screen.frame,
            screen: screen
        ) else { return }
        // Atomic read-modify-write so a concurrent AppFontUpdater save cannot
        // be clobbered by this load+save pair. Fractions and the display
        // identity land in the same key, so a restore can never combine a new
        // screen with an old fraction.
        let saved = ConfigStore.updateConfig { config in
            config.hudPosition = position
        }
        guard saved else {
            NSLog("spacemap/HUDDisplay: failed to persist custom position %@", String(describing: position))
            return
        }
        NSLog("spacemap/HUDDisplay: saved custom position %@", String(describing: position))
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        NotificationCenter.default.post(name: Self.hudPositionChangedNotification, object: nil)
    }


    func positionPanel(_ panel: NSPanel, size: CGSize, screenFrame: CGRect) {
        // A render can be triggered by a yabai signal while the user is
        // dragging the panel; leave the live drag position alone.
        guard isPanelDragging?() != true else { return }
        panel.setFrameOrigin(currentConfig.hudPosition.point(for: size, screen: screenFrame))
    }

    func makePanel() -> NSPanel {
        presenter.makePanel(PanelPresenter.Surface(
            level: .floating,
            hasShadow: currentConfig.hudShadow,
            collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ))
    }

    func quartzPoint(fromAppKit point: CGPoint) -> CGPoint {
        ScreenContext.quartzPoint(fromAppKit: point, quartzMaxY: quartzMainScreenFrame.maxY)
    }
}
