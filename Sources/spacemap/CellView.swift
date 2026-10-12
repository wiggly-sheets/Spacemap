import SwiftUI
import AppKit

struct CellView: View {
    @ObservedObject private var thumbnailStore = ThumbnailStore.shared

    let spaceIndex: Int
    let spaceLabel: String?
    let spaceName: String?
    let isFocused: Bool
    let isDropTarget: Bool
    let isActive: Bool
    let windows: [YabaiWindow]
    let displayBounds: CGRect
    let cellStyle: CellStyle
    let onSelect: (Int) -> Void
    
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

            if showSpaceNumbers {
                Text("\(spaceIndex)")
                    .font(.system(size: 12 * uiScale, weight: .bold))
                    .foregroundColor(textColor.opacity(0.7))
                    .position(GridLayout.spaceNumberPosition(for: uiScale))
            }

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
    
    private enum CellOpacity {
        static let dropTargetDark: CGFloat = 0.35
        static let dropTargetLight: CGFloat = 0.5
        static let focusedBgDark: CGFloat = 0.55
        static let focusedBgLight: CGFloat = 0.2
        static let cellBgDark: CGFloat = 0.25
        static let cellBgLight: CGFloat = 0.8
        static let inactive: CGFloat = 0.35
        static let textDim: CGFloat = 0.7
        static let textDarkDim: CGFloat = 0.4
        static let borderDark: CGFloat = 0.15
        static let borderLight: CGFloat = 0.3
    }

    private enum CellBorder {
        static let emphasized: CGFloat = 2.5
        static let normal: CGFloat = 0.5
    }

    private var backgroundColor: Color {
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

    private var textColor: Color {
        let t = resolvedTheme
        if isFocused { return Color(hex: t.focused) }
        if isDarkMode { return Color(hex: t.text).opacity(CellOpacity.textDarkDim) }
        return Color(hex: 0x333333).opacity(CellOpacity.textDim)
    }

    private var borderColor: Color {
        let t = resolvedTheme
        if isDropTarget { return Color(hex: t.dropTarget) }
        if isFocused { return Color(hex: t.focused) }
        if isDarkMode { return Color(hex: t.text).opacity(CellOpacity.borderDark) }
        return Color(hex: 0x999999).opacity(CellOpacity.borderLight)
    }

    private var borderWidth: CGFloat {
        isDropTarget || isFocused ? CellBorder.emphasized : CellBorder.normal
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
        if let cached = IconCache.shared.cachedIcon(for: appName) { return cached }
        IconCache.shared.resolveInBackground(appName: appName)
        return nil
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
        Self.appColor(name, theme: resolvedTheme)
    }

    static func appColor(_ name: String, theme: AppTheme) -> Color {
        let rects = [theme.rect1, theme.rect2, theme.rect3]
        return Color(hex: rects[Int(stableAppHash(name) % UInt64(rects.count))])
    }

    static func stableAppHash(_ name: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in name.precomposedStringWithCanonicalMapping.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    static func appColorVariation(for name: String) -> (
        paletteIndex: Int,
        saturation: Double,
        lightness: Double
    ) {
        let hash = stableAppHash(name)
        return (
            paletteIndex: Int(hash % 3),
            saturation: 0.35 + Double((hash >> 8) % 35) / 100,
            lightness: 0.42 + Double((hash >> 16) % 17) / 100
        )
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
