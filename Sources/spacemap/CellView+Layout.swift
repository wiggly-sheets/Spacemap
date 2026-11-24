import SwiftUI
import AppKit
import Combine

extension CellView {
    /// HUD badge for a space layout type: float->f, stack->s, bsp->b.
    static func spaceLayoutBadge(
        for type: String?,
        showBSP: Bool = true,
        showStack: Bool = true,
        showFloat: Bool = true
    ) -> String {
        switch type {
        case "float": return showFloat ? "f" : ""
        case "stack": return showStack ? "s" : ""
        case "bsp": return showBSP ? "b" : ""
        default: return ""
        }
    }

    var cellCornerRadius: CGFloat {
        spaceBackground == .theme ? 4 : spaceCornerRadius
    }

    @ViewBuilder
    var cellBackground: some View {
        switch spaceBackground {
        case .theme:
            RoundedRectangle(cornerRadius: cellCornerRadius).fill(backgroundColor)
        case .none:
            Color.clear
        case .solid(let color, let opacity):
            RoundedRectangle(cornerRadius: cellCornerRadius).fill(color.opacity(opacity))
        case .glass(let appearance):
            // The capture for a thumbnail cell rides above the glass inside
            // SpaceGlassView: SwiftUI drawing under a glass effect view reads as
            // the desktop, which is what hid the capture when the glass was a
            // plain SwiftUI background.
            SpaceGlassView(
                appearance: appearance,
                capture: cellStyle.drawsCaptureAboveGlass ? thumbnailCapture : nil
            )
            .clipShape(RoundedRectangle(cornerRadius: cellCornerRadius))
            .overlay {
                // The theme fill would wash out a capture; focus and drop
                // already read from the 2.5 pt border.
                if !cellStyle.drawsCaptureAboveGlass {
                    RoundedRectangle(cornerRadius: cellCornerRadius)
                        .fill(backgroundColor.opacity(0.45))
                }
            }
        }
    }

    var usesGlassBackground: Bool {
        if case .glass = spaceBackground { return true }
        return false
    }

    var backgroundColor: Color {
        let t = resolvedTheme
        let baseColor: Color
        if isDropTarget { baseColor = Color(hex: t.dropTarget).opacity(isDarkMode ? CellOpacity.dropTargetDark : CellOpacity.dropTargetLight) }
        else if isFocused {
            if isDarkMode { baseColor = Color(hex: t.cellBgFocused).opacity(CellOpacity.focusedBgDark) }
            else { baseColor = Color(hex: t.focused).opacity(CellOpacity.focusedBgLight) }
        }
        else if isDarkMode { baseColor = Color(hex: t.cellBg).opacity(CellOpacity.cellBgDark) }
        else { baseColor = Color.white.opacity(CellOpacity.cellBgLight) }

        if !isActive { return baseColor.opacity(CellOpacity.inactive) }
        return baseColor
    }

    var textColor: Color {
        let t = resolvedTheme
        if let value = ThemeCodec.parseHexValue(hudTextColor) { return Color(hex: value) }
        if isFocused { return Color(hex: t.focused) }
        if isDarkMode { return Color(hex: t.text).opacity(CellOpacity.textDarkDim) }
        return Color(hex: 0x333333).opacity(CellOpacity.textDim)
    }

    var borderColor: Color {
        let t = resolvedTheme
        if isDropTarget { return Color(hex: t.dropTarget) }
        if isFocused { return Color(hex: t.focused) }
        if !spaceExists { return Color(hex: t.text).opacity(isDarkMode ? 0.7 : 0.75) }
        if isDarkMode { return Color(hex: t.text).opacity(CellOpacity.borderDark) }
        return Color(hex: 0x999999).opacity(CellOpacity.borderLight)
    }

    /// Dashes mark a space that yabai has not created. Focus and drop targets
    /// keep a solid emphasized outline so the selection still reads first.
    var borderDash: [CGFloat] {
        guard !spaceExists, !isFocused, !isDropTarget else { return [] }
        return [4, 3]
    }

    var borderWidth: CGFloat {
        if isDropTarget || isFocused { return CellBorder.emphasized }
        // A missing space needs to read at a glance, not disappear at 0.5 pt.
        return spaceExists ? CellBorder.normal : 1
    }
    
}
