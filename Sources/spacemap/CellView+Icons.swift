import SwiftUI
import AppKit
import Combine

extension CellView {
    func hudFont(points: CGFloat, weight: Font.Weight) -> Font {
        let size = points * uiScale * CGFloat(hudFontSize / 12)
        return HUDFont.font(name: hudFontName, size: size, weight: weight)
    }

    @ViewBuilder
    func windowRect(_ window: YabaiWindow) -> some View {
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
    func hybridWindowIcon(_ window: YabaiWindow) -> some View {
        let cs = GridLayout.cellSize(forEffectiveScale: uiScale)
        if let frame = GridLayout.scaledWindowFrame(
            windowFrame: window.cgFrame,
            displayBounds: displayBounds,
            cellSize: cs
        ) {
            let iconSize = GridLayout.hybridIconSize(uiScale: uiScale, windowFrame: frame)
            appIconView(for: window.app, width: iconSize, height: iconSize)
                .position(x: frame.midX, y: frame.midY)
        }
    }
    
    @ViewBuilder
    func iconGrid() -> some View {
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
    func windowIcon(_ layout: GridLayout.WindowIconLayout) -> some View {
        appIconView(for: layout.app, width: layout.frame.width, height: layout.frame.height)
            .offset(x: layout.frame.minX, y: layout.frame.minY)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
            .highPriorityGesture(appDragGesture(windowID: layout.windowID, app: layout.app))
    }
    
    @ViewBuilder
    func iconStrip() -> some View {
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
                appIconView(for: window.app, width: finalIconSize, height: finalIconSize, source: stripIconSource)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .highPriorityGesture(appDragGesture(windowID: window.id, app: window.app))
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
    
    @ViewBuilder
    func appIconView(
        for app: String,
        width: CGFloat,
        height: CGFloat,
        source: GlyphStripIconSource? = nil
    ) -> some View {
        if (source ?? iconSource) == .sbarFont,
           let font = AppGlyphFont.load(),
           let face = font.face(size: min(width, height) * 0.82) {
            Text(font.glyph(forApp: app))
                .font(Font(face))
                .foregroundColor(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: width, height: height)
        } else if let icon = appIcon(for: app) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)
        } else {
            Color.clear.frame(width: width, height: height)
        }
    }

    func appIcon(for appName: String) -> NSImage? {
        // Reads iconGeneration so didChange bumps repaint this view.
        _ = iconGeneration
        if let cached = IconCache.shared.cachedIcon(for: appName) { return cached }
        IconCache.shared.resolveInBackground(appName: appName)
        return nil
    }
    
    func appColor(_ name: String) -> Color {
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
