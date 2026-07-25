import SwiftUI
import AppKit

/// Native macOS Liquid Glass background using .glassEffect() from Tahoe.
/// Provides frosted glass that dynamically tracks system appearance.
/// Tinted grey — darker for dark mode, lighter for light mode.
struct LiquidGlassBackground: View {
    let cornerRadius: CGFloat
    let alpha: Double
    let isDarkMode: Bool
    let theme: String
    
    private var tint: Color {
        if isDarkMode {
            return Color(red: 0.04, green: 0.04, blue: 0.06)
        }
        return Color(red: 0.95, green: 0.95, blue: 0.97)
    }
    
    var body: some View {
        #if compiler(>=6.0)
        if #available(macOS 26.0, *) {
            ZStack {
                Rectangle()
                    .fill(tint.opacity(alpha * 0.4))
                
                Rectangle()
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            fallbackBody
        }
        #else
        fallbackBody
        #endif
    }
    
    private var fallbackBody: some View {
        ZStack {
            Rectangle()
                .fill(tint.opacity(alpha * 0.4))
            Rectangle()
                .fill(.ultraThinMaterial)
                .cornerRadius(cornerRadius)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
