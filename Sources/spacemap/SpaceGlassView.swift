import SwiftUI
import AppKit

/// How a space cell paints its own background when it does not match the HUD.
enum CellSpaceBackground: Equatable {
    case theme
    case none
    case solid(Color, Double)
    case glass(SpaceGlassAppearance)
}

struct SpaceGlassAppearance: Equatable {
    var material: HUDGlassMaterial
    var variant: Int
    var tint: NSColor?
    var opacity: CGFloat
    var cornerRadius: CGFloat
}

/// Per-cell glass. SwiftUI's glass modifier cannot take the private variant,
/// so each cell hosts its own `NSGlassEffectView`, clipped to the cell shape.
struct SpaceGlassView: NSViewRepresentable {
    let appearance: SpaceGlassAppearance

    func makeNSView(context: Context) -> SpaceGlassHostView {
        SpaceGlassHostView()
    }

    func updateNSView(_ view: SpaceGlassHostView, context: Context) {
        view.apply(appearance)
    }
}

final class SpaceGlassHostView: NSView {
    private var glass: NSView?

    func apply(_ appearance: SpaceGlassAppearance) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), GlassSupport.isAvailable {
            let glass = (self.glass as? NSGlassEffectView) ?? makeGlass()
            glass.style = appearance.material == .clear ? .clear : .regular
            glass.tintColor = appearance.tint
            glass.cornerRadius = appearance.cornerRadius
            glass.alphaValue = appearance.opacity
            GlassVariant.apply(appearance.variant, to: glass)
            glass.isHidden = false
            return
        }
        #endif
        // Pre-26 or Reduce Transparency: a plain blur keeps the layer shape.
        let fallback: NSVisualEffectView
        if let existing = glass as? NSVisualEffectView {
            fallback = existing
        } else {
            glass?.removeFromSuperview()
            fallback = NSVisualEffectView()
            addSubview(fallback)
            glass = fallback
        }
        fallback.material = appearance.material == .clear ? .underWindowBackground : .headerView
        fallback.blendingMode = .withinWindow
        fallback.state = .active
        fallback.alphaValue = appearance.opacity
        fallback.isHidden = false
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func makeGlass() -> NSGlassEffectView {
        glass?.removeFromSuperview()
        let view = NSGlassEffectView()
        addSubview(view)
        glass = view
        return view
    }
    #endif

    override func layout() {
        super.layout()
        glass?.frame = bounds
    }
}
