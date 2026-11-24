import AppKit
import ApplicationServices
import CoreText

enum GlyphStripClick {
    case left, right, middle
}

/// NSPanel subclass so clicks land here without activating Spacemap.
final class GlyphStripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// Hosts the glass layer for the whole strip.
///
/// macOS 26+: a single `NSGlassEffectView` sized to the shared backdrop rect,
/// with the drawing layer as its `contentView` so the glyphs render inside the
/// glass rather than as a sibling behind it. No mask needed — `cornerRadius`
/// clips the glass.
/// Pre-26 or Reduce Transparency: the legacy `NSVisualEffectView` sibling
/// below the drawing layer, clipped by a shape mask.
///
/// In both cases the flat fill is painted by the drawing layer over the
/// material, because a glass material samples the window backdrop rather than
/// sibling views below it.
final class GlyphStripContainerView: NSView {

    weak var controller: GlyphStripPanelController?
    let glyphs: GlyphStripView

    private let fallbackGlass = NSVisualEffectView()
    /// `NSGlassEffectView` on macOS 26+, stored untyped. Native-glass code is
    /// additionally gated on `compiler(>=6.2)` (see `useNativeGlass`) because
    /// pre-6.2 SDKs lack the type entirely, so it must not appear in source.
    private var nativeGlass: NSView?

    init(controller: GlyphStripPanelController) {
        self.controller = controller
        self.glyphs = GlyphStripView(controller: controller)
        super.init(frame: .zero)
        // Native menu glass sampling the desktop behind the panel. The style
        // and backing are applied in `layout()`/`draw()` so settings apply live.
        fallbackGlass.blendingMode = .behindWindow
        fallbackGlass.state = .active
        addSubview(fallbackGlass)
        addSubview(glyphs)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        NSLog("spacemap/GlyphStripContainerView: init(coder:) unsupported")
        return nil
    }

    // The container is a transparent grouping wrapper, not an element itself;
    // VoiceOver should descend to the drawing layer's segment children.
    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityChildren() -> [Any]? { [glyphs] }

    /// Native glass whenever the OS has it, except under Reduce Transparency
    /// where the masked `NSVisualEffectView` stays legible. Also requires a
    /// 6.0+ compiler: the type only exists in post-5.9 SDKs (CI's macos-14
    /// toolchain cannot even name it), so it must be source-excluded there.
    private var useNativeGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            return !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
        #endif
        return false
    }

    override func layout() {
        super.layout()
        // Single source of truth with draw(): one flag, one rect. Clearing the
        // mask whenever the fallback glass hides stops a stale mask surviving
        // a switch.
        guard let controller, controller.usesGlass,
              let backdrop = controller.backdrop(in: bounds) else {
            dockGlyphsAsSibling()
            fallbackGlass.isHidden = true
            fallbackGlass.maskImage = nil
            glyphs.frame = bounds
            return
        }
        if useNativeGlass {
            layoutNativeGlass(backdrop: backdrop, controller: controller)
        } else {
            layoutFallbackGlass(backdrop: backdrop, controller: controller)
        }
    }

    private func layoutNativeGlass(backdrop: GlyphStrip.Backdrop, controller: GlyphStripPanelController) {
        // Source-gated (not just availability-gated): pre-6.0 SDKs lack
        // `NSGlassEffectView` entirely, so any naming of it fails to compile.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let style: NSGlassEffectView.Style =
                controller.glassStyle.material(tintedMaterial: controller.glassTintedMaterial) == .clear ? .clear : .regular
            let glass: NSGlassEffectView
            // `NSGlassEffectView` caches its effect; `needsDisplay` does not
            // rebuild it. A material swap needs a fresh view.
            if let existing = nativeGlass as? NSGlassEffectView, existing.style == style {
                glass = existing
            } else {
                nativeGlass?.removeFromSuperview()
                glass = NSGlassEffectView()
                glass.style = style
                nativeGlass = glass
            }
            // Glass below the drawing layer, not its `contentView`: the view's
            // alpha then carries the opacity without fading the glyphs, the way
            // macOS menu-bar overlays do it.
            addSubview(glass, positioned: .below, relativeTo: glyphs)
            GlassVariant.apply(controller.glassVariant, to: glass)
            glass.tintColor = controller.glassTintColor
            glass.cornerRadius = backdrop.cornerRadius
            glass.frame = backdrop.rect
            glass.alphaValue = CGFloat(controller.backgroundOpacity)
            glass.isHidden = false
            glass.needsDisplay = true
            glyphs.needsDisplay = true
            glyphs.frame = bounds
        }
        #endif
        fallbackGlass.isHidden = true
        fallbackGlass.maskImage = nil
    }

    private func layoutFallbackGlass(backdrop: GlyphStrip.Backdrop, controller: GlyphStripPanelController) {
        dockGlyphsAsSibling()
        // One material per sub-type, so clear and opaque stay distinct.
        fallbackGlass.material = GlyphStrip.glassFallbackMaterial(
            for: controller.glassStyle,
            tintedMaterial: controller.glassTintedMaterial
        )
        fallbackGlass.state = .active
        fallbackGlass.alphaValue = 1.0
        // Size the blur view itself to the backdrop rect — a full-bounds frame
        // leaves a big rectangle whenever the mask is nil or misaligned.
        fallbackGlass.frame = backdrop.rect
        fallbackGlass.maskImage = Self.maskImage(for: backdrop)
        fallbackGlass.isHidden = false
        glyphs.frame = bounds
        // Alpha/material swaps alone do not always repaint, so force both
        // layers: otherwise the neutral slider looks dead until resize.
        fallbackGlass.needsDisplay = true
        glyphs.needsDisplay = true
    }

    /// Returns the drawing layer to a direct sibling above the effect view.
    private func dockGlyphsAsSibling() {
        nativeGlass?.isHidden = true
        if glyphs.superview !== self {
            glyphs.removeFromSuperview()
            addSubview(glyphs, positioned: .above, relativeTo: fallbackGlass)
        }
    }

    /// Mask in the blur view's own coordinates: transparent background with
    /// the shape filled white at origin zero. Matches the rect the stroke
    /// paints (translated to zero), so mask and edge cannot disagree.
    /// `flipped: false` matches this non-flipped view's y-up coordinates.
    fileprivate static func maskImage(for backdrop: GlyphStrip.Backdrop) -> NSImage? {
        let size = backdrop.rect.size
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: backdrop.cornerRadius,
                yRadius: backdrop.cornerRadius
            ).fill()
            return true
        }
        image.size = size
        return image
    }
}

/// One VoiceOver child per painted segment; pressing it runs the same command
/// as a left click on that segment.
final class GlyphStripAccessibilityElement: NSAccessibilityElement {
    weak var controller: GlyphStripPanelController?
    var segmentIndex = 0

    override func accessibilityActionNames() -> [NSAccessibility.Action] { [.press] }

    override func accessibilityPerformPress() -> Bool {
        guard let controller,
              let command = controller.command(forSegment: segmentIndex, click: .left) else {
            return false
        }
        controller.handle(command)
        return true
    }
}

