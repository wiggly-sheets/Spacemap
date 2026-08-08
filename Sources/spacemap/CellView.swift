import SwiftUI
import AppKit

/// CellView displays a single space/cell in the grid.
///
/// Supported cell styles:
/// - .rects:      Colored rectangles representing window positions/sizes
/// - .hybrid:     Rectangles with a small centered app icon
/// - .icons:      Window icons arranged from yabai's window geometry
/// - .thumbnails: Live window content thumbnails (requires screen recording permission)
/// - .simple:     Empty cells with no window content
///
/// Icon strip at the bottom is controlled separately by `showIconStrip`.
struct CellView: View {
    @ObservedObject private var thumbnailStore = ThumbnailStore.shared

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
    private let uiScale: CGFloat
    private let resolvedTheme: AppTheme
    private let mode: ThemeMode
    private let iconScale: CGFloat
    private let showSpaceNumbers: Bool
    private let showSpaceNames: Bool
    private let showIconStrip: Bool
    private let showMultiAppIcons: Bool
    private let showExtraWindows: Bool

    private var isDarkMode: Bool {
        switch mode {
        case .light: return false
        case .dark:  return true
        case .auto:  return NSApp.effectiveAppearance.name == .darkAqua
        }
    }

    private var filteredWindows: [YabaiWindow] {
        windows.filter { $0.shouldDisplay(showExtraWindows: showExtraWindows) }
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
    }

    
var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)

            switch cellStyle {
            case .rects:
                ForEach(filteredWindows, id: \.id) { window in
                    windowRect(window)
                }
            case .hybrid:
                ForEach(filteredWindows, id: \.id) { window in
                    windowRect(window)
                }
                ForEach(filteredWindows, id: \.id) { window in
                    hybridWindowIcon(window)
                }
            case .icons:
                iconGrid()
            case .thumbnails:
                thumbnailImage(spaceIndex)
            case .simple:
                EmptyView()
            }

            if showIconStrip {
                iconStrip()
            }

            // Show space number at top-left when showNames is enabled
            if showSpaceNumbers {
                Text("\(spaceIndex)")
                    .font(.system(size: 12 * uiScale, weight: .bold))
                    .foregroundColor(textColor.opacity(0.7))
                    .position(GridLayout.spaceNumberPosition(for: uiScale))
            }

            // Show space name (if exists) in center
            if showSpaceNames, let name = spaceName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 14 * uiScale, weight: .medium))
                    .foregroundColor(textColor)
                    .position(GridLayout.spaceNamePosition(in: GridLayout.cellSize(forEffectiveScale: uiScale)))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .frame(width: GridLayout.cellSize(forEffectiveScale: uiScale).width, height: GridLayout.cellSize(forEffectiveScale: uiScale).height)
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
        let cs = GridLayout.cellSize(forEffectiveScale: uiScale)
        if let frame = GridLayout.scaledWindowFrame(
            windowFrame: window.cgFrame,
            displayBounds: displayBounds,
            cellSize: cs
        ) {
            RoundedRectangle(cornerRadius: 1)
                .fill(appColor(window.app).opacity(0.6))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
    }

    @ViewBuilder
    private func hybridWindowIcon(_ window: YabaiWindow) -> some View {
        let cs = GridLayout.cellSize(forEffectiveScale: uiScale)
        if let frame = GridLayout.scaledWindowFrame(
            windowFrame: window.cgFrame,
            displayBounds: displayBounds,
            cellSize: cs
        ), let icon = appIcon(for: window.app) {
            let iconSize = GridLayout.hybridIconSize(uiScale: uiScale, windowFrame: frame)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .position(x: frame.midX, y: frame.midY)
        }
    }
    
    @ViewBuilder
    private func iconGrid() -> some View {
        let cs = GridLayout.cellSize(forEffectiveScale: uiScale)
        let layouts = GridLayout.windowIconLayouts(
            windows: filteredWindows,
            displayBounds: displayBounds,
            cellSize: cs
        )

        ForEach(layouts) { layout in
            windowIcon(layout)
        }
    }

    @ViewBuilder
    private func windowIcon(_ layout: GridLayout.WindowIconLayout) -> some View {
        if let icon = appIcon(for: layout.app) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: layout.frame.width, height: layout.frame.height)
                .offset(x: layout.frame.minX, y: layout.frame.minY)
        }
    }
    
    @ViewBuilder
    private func iconStrip() -> some View {
        let icons = Self.iconStripWindows(
            filteredWindows,
            showMultiAppIcons: showMultiAppIcons
        )
        let ic = iconScale
        let baseIconSize = 12 * uiScale * ic * 2
        let spacing = 2 * uiScale * ic * 2
        let padding = 3 * uiScale * ic * 2
        let cs = GridLayout.cellSize(forEffectiveScale: uiScale)
        let availableWidth = cs.width - padding * 2
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
    
    static func iconStripWindows(
        _ displayedWindows: [YabaiWindow],
        showMultiAppIcons: Bool
    ) -> [YabaiWindow] {
        let sorted = displayedWindows.sorted {
            if $0.cgFrame.minX == $1.cgFrame.minX {
                if $0.cgFrame.minY == $1.cgFrame.minY {
                    return $0.id < $1.id
                }
                return $0.cgFrame.minY < $1.cgFrame.minY
            }
            return $0.cgFrame.minX < $1.cgFrame.minX
        }
        return showMultiAppIcons ? sorted : uniqueIconWindows(sorted)
    }

    static func uniqueIconWindows(_ displayedWindows: [YabaiWindow]) -> [YabaiWindow] {
        var seen = Set<String>()
        return displayedWindows.filter { seen.insert($0.app).inserted }
    }
    
    private func appIcon(for appName: String) -> NSImage? {
        IconCache.shared.icon(for: appName)
    }
    
    private func thumbnailImage(_ spaceIndex: Int) -> some View {
        guard #available(macOS 14.0, *),
               let nsImage = thumbnailStore.image(forSpace: spaceIndex) else {
            return AnyView(Color.clear)
        }
        let cs = GridLayout.cellSize(forEffectiveScale: uiScale)
        return AnyView(Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: cs.width, height: cs.height)
            .clipped())
    }
    
    private func appColor(_ name: String) -> Color {
        Self.appColor(name, theme: resolvedTheme, windowCount: windows.count)
    }

    static func appColor(_ name: String, theme: AppTheme, windowCount: Int) -> Color {
        let t = theme
        let rects = [t.rect1, t.rect2, t.rect3]
        let base = rects[(name.hashValue % 3 + 3) % 3]
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
        let hash = name.hashValue % 35
        let sat = 0.35 + Double(hash >= 0 ? hash : hash + 35) / 100.0
        let lit = 0.50 + Double(((hash / 35) % 35 + 35) % 35) / 100.0
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
