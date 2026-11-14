import AppKit

/// Panel content root for the HUD.
///
/// Liquid Glass only samples the window backdrop when the `NSGlassEffectView`
/// is a plain view in the window's content hierarchy. A glass view nested in a
/// SwiftUI `.background` samples the SwiftUI content instead, which is why the
/// effect appeared inside the cells but never filled the HUD. The glass is
/// therefore an AppKit sibling below the hosting view, the same arrangement
/// the glyph strip and Settings window use.
final class HUDGlassContainerView: NSView {

    struct Appearance {
        var enabled: Bool
        var style: HUDGlassStyle
        var tintedMaterial: HUDGlassMaterial
        var opacity: CGFloat
        var tint: NSColor
        var cornerRadius: CGFloat
        /// Private `_variant` finish, 0...21.
        var variant: Int
    }

    private var hostingView: NSView?
    /// `NSGlassEffectView` on macOS 26+, stored untyped so pre-6.2 SDKs compile.
    private var glassView: NSView?
    private var glassStyle: HUDGlassStyle?
    private var glassAppearance = Appearance(
        enabled: false, style: .regular, tintedMaterial: .clear, opacity: 1, tint: .clear, cornerRadius: 10, variant: 11
    )

    func configure(hosting view: NSView, size: CGSize, appearance: Appearance) {
        if hostingView !== view {
            hostingView?.removeFromSuperview()
            addSubview(view)
            hostingView = view
        }
        self.glassAppearance = appearance
        frame = NSRect(origin: .zero, size: size)
        hostingView?.frame = bounds
        applyGlass()
        glassView?.frame = bounds
    }

    override func layout() {
        super.layout()
        hostingView?.frame = bounds
        glassView?.frame = bounds
    }

    private func applyGlass() {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            guard glassAppearance.enabled else {
                glassView?.isHidden = true
                return
            }
            // NSGlassEffectView caches its style, so a style change needs a new
            // view rather than a property write.
            if glassView == nil || glassStyle != glassAppearance.style {
                glassView?.removeFromSuperview()
                let glass = NSGlassEffectView()
                glass.style = glassAppearance.style.material(tintedMaterial: glassAppearance.tintedMaterial) == .clear ? .clear : .regular
                addSubview(glass, positioned: .below, relativeTo: hostingView)
                glassView = glass
                glassStyle = glassAppearance.style
            }
            guard let glass = glassView as? NSGlassEffectView else { return }
            // Tinted is regular glass plus an accent: clear glass is too thin
            // for the tint to register over a desktop backdrop.
            glass.tintColor = glassAppearance.style == .tinted ? glassAppearance.tint : nil
            glass.cornerRadius = glassAppearance.cornerRadius
            glass.alphaValue = glassAppearance.opacity
            glass.isHidden = false
            // The public styles alone render nearly flat for third-party
            // views; the private variant picks the refractive finish.
            GlassVariant.apply(glassAppearance.variant, to: glass)
            return
        }
        #endif
        glassView?.isHidden = true
    }
}
