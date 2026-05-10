import SwiftUI
import AppKit

/// CellView displays a single space/cell in the grid.
///
/// Supported cell styles:
/// - .rects:      Colored rectangles representing window positions/sizes
/// - .icons:      Window icons positioned at their actual locations
/// - .thumbnails: Live window content thumbnails (requires screen recording permission)
/// - .simple:     Empty cells with no window content
///
/// Icon strip at the bottom is controlled separately by `showIconStrip`.
struct CellView: View {
    let spaceIndex: Int
    let spaceLabel: String?
    let spaceName: String? // config-based name
    let isFocused: Bool
    let isDropTarget: Bool
    let isActive: Bool
    let windows: [YabaiWindow]
    let displayBounds: CGRect
    let cellStyle: CellStyle
    let onSelect: (Int) -> Void
    
    // These values will be passed from GridView
    private let baseCellWidth: CGFloat = 80
    private let baseCellHeight: CGFloat = 50
    private let uiScale: CGFloat
    private let resolvedTheme: AppTheme
    private let mode: ThemeMode
    private let iconScale: CGFloat
    private let showSpaceNumbers: Bool
    private let showSpaceNames: Bool
    private let showIconStrip: Bool
    private let showMultiAppIcons: Bool
    private let showExtraWindows: Bool
    private let windowFilter: ([YabaiWindow]) -> [YabaiWindow]

    private var isDarkMode: Bool {
        switch mode {
        case .light: return false
        case .dark:  return true
        case .auto:  return NSApp.effectiveAppearance.name == .darkAqua
        }
    }
    
    private var cellSize: CGSize {
        CGSize(width: baseCellWidth * uiScale, height: baseCellHeight * uiScale)
    }
    
init(spaceIndex: Int,
            spaceLabel: String? = nil,
            spaceName: String? = nil,
            isFocused: Bool,
            isDropTarget: Bool,
            isActive: Bool,
             windows: [YabaiWindow],
             displayBounds: CGRect,
             cellStyle: CellStyle,
             onSelect: @escaping (Int) -> Void,
             uiScale: CGFloat = 1.0,
             resolvedTheme: AppTheme = .default,
             mode: ThemeMode = .auto,
             iconScale: CGFloat = 1.0,
             showSpaceNumbers: Bool = true,
             showSpaceNames: Bool = true,
             showIconStrip: Bool = true,
             showMultiAppIcons: Bool = false,
             showExtraWindows: Bool = false) {
        self.spaceIndex = spaceIndex
        self.spaceLabel = spaceLabel
        self.spaceName = spaceName
        self.isFocused = isFocused
        self.isDropTarget = isDropTarget
        self.isActive = isActive
        self.windows = windows
        self.displayBounds = displayBounds
        self.cellStyle = cellStyle
        self.onSelect = onSelect
        self.uiScale = uiScale
        self.resolvedTheme = resolvedTheme
        self.mode = mode
        self.iconScale = iconScale
        self.showSpaceNumbers = showSpaceNumbers
        self.showSpaceNames = showSpaceNames
        self.showIconStrip = showIconStrip
        self.showMultiAppIcons = showMultiAppIcons
        self.showExtraWindows = showExtraWindows
        self.windowFilter = showExtraWindows
            ? { $0.filter { !$0.isHidden && !$0.isMinimized } }
            : { $0.filter { $0.isRealWindow } }
    }

    
var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)

            if cellStyle != .simple {
                let visibleWindows = windowFilter(windows)
                ForEach(visibleWindows, id: \.id) { window in
                    switch cellStyle {
                    case .rects:      windowRect(window)
                    case .icons:      windowIcon(window)
                    case .thumbnails: thumbnailImage(spaceIndex)
                    case .simple:     EmptyView()
                    }
                }
            }

            if showIconStrip {
                iconStrip()
            }

            // Show space number at top-left when showNames is enabled
            if showSpaceNumbers {
                Text("\(spaceIndex)")
                    .font(.system(size: 12 * uiScale, weight: .bold))
                    .foregroundColor(textColor.opacity(0.7))
                    .position(x: 8, y: 12)
            }

            // Show space name (if exists) in center
            if showSpaceNames, let name = spaceName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 14 * uiScale, weight: .medium))
                    .foregroundColor(textColor)
                    .position(x: cellSize.width / 2, y: cellSize.height / 2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .frame(width: cellSize.width, height: cellSize.height)
        .onTapGesture { onSelect(spaceIndex) }
    }
    
    private var backgroundColor: Color {
        let t = resolvedTheme
        let baseColor: Color
        if isDropTarget { baseColor = Color(hex: t.dropTarget).opacity(isDarkMode ? 0.35 : 0.5) }
        else if isFocused {
            if isDarkMode { baseColor = Color(hex: t.cellBgFocused).opacity(0.55) }
            else { baseColor = Color(hex: t.focused).opacity(0.2) }
        }
        else if isDarkMode { baseColor = Color(hex: t.cellBg).opacity(0.25) }
        else { baseColor = Color.white.opacity(0.8) }
        
        if !isActive { return baseColor.opacity(0.35) }
        return baseColor
    }
    
    private var textColor: Color {
        let t = resolvedTheme
        if isFocused { return Color(hex: t.focused) }
        if isDarkMode { return Color(hex: t.text).opacity(0.4) }
        return Color(hex: 0x333333).opacity(0.7)
    }
    
    private var borderColor: Color {
        let t = resolvedTheme
        if isDropTarget { return Color(hex: t.dropTarget) }
        if isFocused { return Color(hex: t.focused) }
        if isDarkMode { return Color(hex: t.text).opacity(0.15) }
        return Color(hex: 0x999999).opacity(0.3)
    }
    
    private var borderWidth: CGFloat {
        isDropTarget || isFocused ? 2.5 : 0.5
    }
    
    @ViewBuilder
    private func windowRect(_ window: YabaiWindow) -> some View {
        let scaleX = cellSize.width / displayBounds.width
        let scaleY = cellSize.height / displayBounds.height
        let x = (window.cgFrame.minX - displayBounds.minX) * scaleX
        let y = (window.cgFrame.minY - displayBounds.minY) * scaleY
        let w = max(window.cgFrame.width * scaleX, 2)
        let h = max(window.cgFrame.height * scaleY, 2)
        
        RoundedRectangle(cornerRadius: 1)
            .fill(appColor(window.app).opacity(0.6))
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
    
    @ViewBuilder
    private func windowIcon(_ window: YabaiWindow) -> some View {
        let scaleX = cellSize.width / displayBounds.width
        let scaleY = cellSize.height / displayBounds.height
        let x = (window.cgFrame.minX - displayBounds.minX) * scaleX
        let y = (window.cgFrame.minY - displayBounds.minY) * scaleY
        let w = max(window.cgFrame.width * scaleX, 14)
        let h = max(window.cgFrame.height * scaleY, 14)
        let iconSize = min(w, h)

        if let icon = appIcon(for: window.app) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .offset(x: x, y: y)
        }
    }
    
    @ViewBuilder
    private func iconStrip() -> some View {
        let visible = windowFilter(windows)
        let icons = showMultiAppIcons ? visible : Self.uniqueIconWindows(visible)
        let ic = iconScale
        let baseIconSize = 12 * uiScale * ic * 2
        let spacing = 2 * uiScale * ic * 2
        let padding = 3 * uiScale * ic * 2
        let availableWidth = cellSize.width - padding * 2
        let neededWidth = CGFloat(icons.count) * baseIconSize + CGFloat(max(0, icons.count - 1)) * spacing
        let fitScale: CGFloat = neededWidth > availableWidth ? availableWidth / neededWidth : 1.0
        let finalIconSize = baseIconSize * fitScale
        let finalSpacing = spacing * fitScale
        HStack(spacing: finalSpacing) {
            ForEach(icons, id: \.id) { window in
                if let icon = appIcon(for: window.app) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: finalIconSize, height: finalIconSize)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, padding)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, padding)
    }
    
    private func uniqueIconWindows() -> [YabaiWindow] {
        Self.uniqueIconWindows(windows)
    }

    static func uniqueIconWindows(_ windows: [YabaiWindow], showExtraWindows: Bool = false) -> [YabaiWindow] {
        var seen = Set<String>()
        let filter: (YabaiWindow) -> Bool = showExtraWindows
            ? { !$0.isHidden && !$0.isMinimized }
            : { $0.isRealWindow }
        return windows.filter { filter($0) && seen.insert($0.app).inserted }
    }
    
    private func appIcon(for appName: String) -> NSImage? {
        IconCache.shared.icon(for: appName)
    }
    
    private func thumbnailImage(_ spaceIndex: Int) -> some View {
        guard #available(macOS 14.0, *),
              let nsImage = ThumbnailCache.shared.thumbnailNSImage(forSpace: spaceIndex) else {
            return AnyView(Color.clear)
        }
        return AnyView(Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: cellSize.width, height: cellSize.height)
            .clipped())
    }
    
    private func appColor(_ name: String) -> Color {
        Self.appColor(name, theme: resolvedTheme, windowCount: windows.count)
    }

    static func appColor(_ name: String, theme: AppTheme, windowCount: Int) -> Color {
        let t = theme
        let rects = [t.rect1, t.rect2, t.rect3]
        let base = rects[abs(name.hashValue) % 3]
        if windowCount <= 3 {
            return Color(hex: base)
        }
        // HSL variation: keep hue from base, vary sat/lightness for overflow windows
        let r = Double((base >> 16) & 0xFF) / 255.0
        let g = Double((base >> 8) & 0xFF) / 255.0
        let b = Double(base & 0xFF) / 255.0
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let d = maxC - minC
        var h: Double = 0
        if d != 0 {
            if maxC == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        let hash = abs(name.hashValue)
        let sat = 0.35 + Double(hash % 35) / 100.0
        let lit = 0.50 + Double((hash / 35) % 35) / 100.0
        let c = (1 - abs(2 * lit - 1)) * sat
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = lit - c / 2
        var rr: Double = 0, gg: Double = 0, bb: Double = 0
        switch Int(h * 6) % 6 {
        case 0: (rr, gg, bb) = (c, x, 0)
        case 1: (rr, gg, bb) = (x, c, 0)
        case 2: (rr, gg, bb) = (0, c, x)
        case 3: (rr, gg, bb) = (0, x, c)
        case 4: (rr, gg, bb) = (x, 0, c)
        default: (rr, gg, bb) = (c, 0, x)
        }
        return Color(red: rr + m, green: gg + m, blue: bb + m)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
