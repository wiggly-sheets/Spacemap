import SwiftUI
import AppKit

/// How a space cell paints its own background when it does not match the HUD.
enum CellSpaceBackground: Equatable {
    case theme
    case none
    case solid(Color, Double)
    case glass(SpaceGlassAppearance)
}

extension CellSpaceBackground {
    /// The cell background the `spaces*` keys describe. Every cell style reads
    /// this, so thumbnails honour the same glass keys as rects, hybrid and icons.
    static func from(config: SpacemapConfig, resolvedTheme: AppTheme) -> CellSpaceBackground {
        guard !config.spacesMatchBackground else { return .theme }
        switch config.spacesBackgroundStyle {
        case .none:
            return .none
        case .solid:
            return .solid(Color(hex: resolvedTheme.cellBg), config.spacesOpacity)
        case .glass:
            let style = config.spacesGlassStyle
            let variant = style == .clear
                ? config.spacesGlassClearVariant
                : (style == .regular ? config.spacesGlassRegularVariant : config.spacesGlassTintedVariant)
            return .glass(SpaceGlassAppearance(
                material: style.material(tintedMaterial: config.spacesGlassTintedMaterial),
                variant: variant,
                tint: style == .tinted ? GlyphStrip.color(for: "focused", theme: resolvedTheme) : nil,
                opacity: CGFloat(config.spacesOpacity),
                cornerRadius: CGFloat(config.spacesCornerRadius)
            ))
        }
    }
}

extension CellStyle {
    /// Thumbnail cells draw their capture above the glass and skip the theme
    /// fill overlay; every other style keeps the overlay and no capture.
    var drawsCaptureAboveGlass: Bool { self == .thumbnails }
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
    /// Thumbnail capture, drawn above the glass. Nil for every other style.
    var capture: NSImage? = nil

    func makeNSView(context: Context) -> SpaceGlassHostView {
        SpaceGlassHostView()
    }

    func updateNSView(_ view: SpaceGlassHostView, context: Context) {
        view.apply(appearance, capture: capture)
    }
}

final class SpaceGlassHostView: NSView {
    private var glass: NSView?
    /// Thumbnail capture layer. A subview, not a sublayer: AppKit draws it
    /// above the glass, while SwiftUI drawing under a glass view reads as the
    /// desktop rather than as the capture.
    private let capture = NSView()

    /// Decoration only; the cell's own gesture handles taps and drags.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ appearance: SpaceGlassAppearance, capture image: NSImage? = nil) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), GlassSupport.isAvailable {
            let glass = (self.glass as? NSGlassEffectView) ?? makeGlass()
            glass.style = appearance.material == .clear ? .clear : .regular
            glass.tintColor = appearance.tint
            glass.cornerRadius = appearance.cornerRadius
            glass.alphaValue = appearance.opacity
            GlassVariant.apply(appearance.variant, to: glass)
            glass.isHidden = false
            applyCapture(image)
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
        applyCapture(image)
    }

    /// Keeps the capture above the glass, whatever the glass path rebuilt.
    private func applyCapture(_ image: NSImage?) {
        if capture.superview == nil {
            capture.wantsLayer = true
            capture.layer?.contentsGravity = .resizeAspectFill
            capture.layer?.masksToBounds = true
            addSubview(capture)
        }
        if let glass {
            addSubview(capture, positioned: .above, relativeTo: glass)
        }
        capture.layer?.contents = image
        capture.isHidden = image == nil
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
        capture.frame = bounds
    }
}
