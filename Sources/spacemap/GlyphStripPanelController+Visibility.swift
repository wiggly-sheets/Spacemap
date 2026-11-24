import AppKit
import ApplicationServices
import CoreText

extension GlyphStripPanelController {
    /// Sleep can freeze a press or hover highlight on the menu-bar view.
    /// Clear both without rebuilding the status item: AppKit is still
    /// restoring the menu bar, and replacing the item steals the first click.
    func handleWake() {
        // Rebuilding the status item here steals the first post-wake click:
        // AppKit is still restoring the menu bar and the new item is not yet
        // the one under the cursor. Clear any stale press and repaint instead.
        cancelGesture()
        statusView?.refreshHover()
        if let panel, panel.isVisible {
            applyFrame(to: panel)
        }
    }

    func cancelGesture() {
        statusView?.cancelGesture()
    }

    /// Hides the strip while another app owns a native fullscreen window or
    /// Mission Control is up, and brings it back afterwards. Polled because
    /// the window server gives no notification for either; yabai signals alone
    /// miss the green-button case.
    func reconcileOverlayVisibility() {
        // Mission Control copies every visible window into each space
        // thumbnail, so the strip hides there regardless of the fullscreen
        // setting.
        applyMissionControlVisibility(ScreenContext.isMissionControlActive())
        guard config.glyphStrip.enabled, config.glyphStrip.hideInFullscreen else {
            guard hiddenByFullscreen else { return }
            hiddenByFullscreen = false
            update(config: config)
            return
        }
        if let yabaiAnswer = fullscreenWindowOnFocusedSpace() {
            applyFullscreenVisibility(yabaiAnswer)
            return
        }
        // Accessibility can stall while permissions are edited. Never ask on
        // the main thread; fall back to geometry when the probe is unhealthy.
        PermissionProbe.shared.check(provider: { AXIsProcessTrusted() }) { [weak self] trusted in
            guard let self else { return }
            self.applyFullscreenVisibility(ScreenContext.hasFullscreenAppInFront(trusted: trusted))
        }
    }

    func applyFullscreenVisibility(_ shouldHide: Bool) {
        guard shouldHide != hiddenByFullscreen else { return }
        hiddenByFullscreen = shouldHide
        if shouldHide {
            hide()
        } else {
            update(config: config)
        }
    }

    func applyMissionControlVisibility(_ shouldHide: Bool) {
        guard shouldHide != hiddenByMissionControl else { return }
        hiddenByMissionControl = shouldHide
        if shouldHide {
            hide()
        } else {
            update(config: config)
        }
    }

    /// Native fullscreen on the focused space, from yabai's window or space flag.
    /// A fullscreen window on another space is invisible to the user, so the
    /// window-server and Accessibility checks alone cannot tell them apart.
    /// `nil` when the focused space or the field is unavailable.
    func fullscreenWindowOnFocusedSpace() -> Bool? {
        guard let state = coordinator.state, let focused = state.focusedIndex else { return nil }
        return state.isFullscreen(spaceIndex: focused)
    }

    /// Toggles the session-only hotkey visibility. Disabled strip: the flag
    /// flips but the strip stays hidden until it is enabled again.
    func toggleVisibilityByHotkey() {
        hiddenByHotkey.toggle()
        if hiddenByHotkey {
            hide()
        } else {
            update(config: config)
        }
    }
}
