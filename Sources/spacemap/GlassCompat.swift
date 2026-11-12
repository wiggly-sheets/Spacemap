import SwiftUI
import AppKit

enum GlassSupport {
    /// Native Liquid Glass is usable only on macOS 26+ with Reduce Transparency off.
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
        #endif
        return false
    }
}

extension View {
    /// Native glass button on macOS 26+, bordered button before that.
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(LiquidGlassButtonStyleModifier(prominent: prominent))
    }
}

private struct LiquidGlassButtonStyleModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), GlassSupport.isAvailable {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    /// Bordered style: the look the settings buttons had before macOS 26.
    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
