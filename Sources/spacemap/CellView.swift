import SwiftUI
import AppKit
import Combine
struct CellView: View {
    @ObservedObject var thumbnailStore = ThumbnailStore.shared
    /// Bumped on every IconCache.didChange so async resolves repaint the
    /// cached-only icon reads below. Never read directly: the write alone
    /// invalidates the view.
    @State var iconGeneration = 0

    let spaceIndex: Int
    let spaceLabel: String?
    let spaceName: String?
    let spaceLayoutBadge: String
    let isFocused: Bool
    let isDropTarget: Bool
    let isActive: Bool
    /// The space exists in yabai. A placeholder cell for a space that does not
    /// exist gets a dashed outline so it cannot be mistaken for an empty space.
    let spaceExists: Bool
    let windows: [YabaiWindow]
    let displayBounds: CGRect
    let cellStyle: CellStyle
    let spaceBackground: CellSpaceBackground
    let spaceCornerRadius: CGFloat
    let onSelect: (Int) -> Void
    
    let uiScale: CGFloat
    let resolvedTheme: AppTheme
    let mode: ThemeMode
    let iconScale: CGFloat
    let showSpaceNumbers: Bool
    let showSpaceLayout: Bool
    let showSpaceNames: Bool
    let showIconStrip: Bool
    let showMultiAppIcons: Bool
    let showExtraWindows: Bool
    let iconSource: GlyphStripIconSource
    let stripIconSource: GlyphStripIconSource
    let hudAnimation: HUDAnimationStyle?
    let hudTextColor: String
    let hudFontName: String
    let hudFontSize: Double
    let onDragActive: ((Bool) -> Void)?
    let onDragEnd: ((NSPoint) -> Void)?
    let onSpaceDragStart: ((Int) -> Void)?
    let onWindowDragStart: ((Int) -> Void)?
    let onWindowDrop: (([Int], Int, NSPoint) -> Void)?
    @State var iconDragActive = false

    var isDarkMode: Bool {
        switch mode {
        case .light: return false
        case .dark:  return true
        case .auto:  return NSApp.effectiveAppearance.name == .darkAqua
        }
    }

    var filteredWindows: [YabaiWindow] {
        windows.filter { $0.shouldDisplay(showExtraWindows: showExtraWindows) }
    }

    var spaceLayoutBadgeText: String {
        guard showSpaceNumbers, showSpaceLayout else { return "" }
        return spaceLayoutBadge
    }

init(spaceIndex: Int,
            spaceLabel: String? = nil,
            spaceName: String? = nil,
            spaceLayoutBadge: String = "",
            isFocused: Bool,
            isDropTarget: Bool,
            isActive: Bool,
             spaceExists: Bool = true,
             windows: [YabaiWindow],
             displayBounds: CGRect,
             cellStyle: CellStyle,
             spaceBackground: CellSpaceBackground = .theme,
             spaceCornerRadius: CGFloat = 4,
             onSelect: @escaping (Int) -> Void,
             uiScale: CGFloat = 1.0,
             resolvedTheme: AppTheme = .default,
             mode: ThemeMode = .auto,
             iconScale: CGFloat = 1.0,
             showSpaceNumbers: Bool = true,
             showSpaceLayout: Bool = false,
             showSpaceNames: Bool = true,
             showIconStrip: Bool = true,
             showMultiAppIcons: Bool = false,
             showExtraWindows: Bool = false,
             iconSource: GlyphStripIconSource = .nativeIcons,
             stripIconSource: GlyphStripIconSource? = nil,
             hudAnimation: HUDAnimationStyle? = .natural,
             hudFontName: String = "",
             hudFontSize: Double = 12,
             hudTextColor: String = "",
             onDragActive: ((Bool) -> Void)? = nil,
             onDragEnd: ((NSPoint) -> Void)? = nil,
             onSpaceDragStart: ((Int) -> Void)? = nil,
             onWindowDragStart: ((Int) -> Void)? = nil,
             onWindowDrop: (([Int], Int, NSPoint) -> Void)? = nil) {
        self.spaceIndex = spaceIndex
        self.spaceLabel = spaceLabel
        self.spaceName = spaceName
        self.spaceLayoutBadge = spaceLayoutBadge
        self.isFocused = isFocused
        self.isDropTarget = isDropTarget
        self.isActive = isActive
        self.spaceExists = spaceExists
        self.windows = windows
        self.displayBounds = displayBounds
        self.cellStyle = cellStyle
        self.spaceBackground = spaceBackground
        self.spaceCornerRadius = spaceCornerRadius
        self.onSelect = onSelect
        self.uiScale = uiScale
        self.resolvedTheme = resolvedTheme
        self.mode = mode
        self.iconScale = iconScale
        self.showSpaceNumbers = showSpaceNumbers
        self.showSpaceLayout = showSpaceLayout
        self.showSpaceNames = showSpaceNames
        self.showIconStrip = showIconStrip
        self.showMultiAppIcons = showMultiAppIcons
        self.showExtraWindows = showExtraWindows
        self.iconSource = iconSource
        self.stripIconSource = stripIconSource ?? iconSource
        self.hudAnimation = hudAnimation
        self.hudTextColor = hudTextColor
        self.hudFontName = hudFontName
        self.hudFontSize = hudFontSize
        self.onDragActive = onDragActive
        self.onDragEnd = onDragEnd
        self.onSpaceDragStart = onSpaceDragStart
        self.onWindowDragStart = onWindowDragStart
        self.onWindowDrop = onWindowDrop
    }

    
var body: some View {
        ZStack(alignment: .topLeading) {
            cellBackground

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
                // Glass cells host the capture inside SpaceGlassView so it
                // stays above the native glass.
                if !usesGlassBackground { thumbnailImage(spaceIndex) }
            case .simple:
                EmptyView()
            }

            if showIconStrip {
                iconStrip()
            }

            if showSpaceNumbers {
                Text("\(spaceIndex)\(spaceLayoutBadgeText)")
                    .font(hudFont(points: 12, weight: .bold))
                    .foregroundColor(textColor.opacity(0.7))
                    .fixedSize()
                    .padding(.leading, GridLayout.spaceNumberPosition(for: uiScale).x)
                    .padding(.top, GridLayout.spaceNumberPosition(for: uiScale).y - 6 * uiScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }

            if showSpaceNames, let name = spaceName, !name.isEmpty {
                let cell = GridLayout.cellSize(forEffectiveScale: uiScale)
                Text(name)
                    .font(hudFont(points: 14, weight: .medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(width: max(cell.width - 8 * uiScale, 0))
                    .position(GridLayout.spaceNamePosition(in: cell))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cellCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cellCornerRadius)
                .strokeBorder(borderColor, style: StrokeStyle(lineWidth: borderWidth, dash: borderDash))
        )
        .frame(width: GridLayout.cellSize(forEffectiveScale: uiScale).width, height: GridLayout.cellSize(forEffectiveScale: uiScale).height)
        .onTapGesture { onSelect(spaceIndex) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { _ in
                    guard !iconDragActive else { return }
                    onSpaceDragStart?(spaceIndex)
                    onDragActive?(true)
                }
                .onEnded { _ in
                    guard !iconDragActive else { return }
                    // Resolve the drop before teardown clears the shared target.
                    onDragEnd?(NSEvent.mouseLocation)
                    onDragActive?(false)
                }
        )
        .animation(hudAnimation?.animation, value: filteredWindows.map(\.id))
        .animation(hudAnimation?.animation, value: showMultiAppIcons)
        .onReceive(NotificationCenter.default.publisher(for: IconCache.didChange)) { _ in
            iconGeneration += 1
        }
    }
    
    enum CellOpacity {
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

    enum CellBorder {
        static let emphasized: CGFloat = 2.5
        static let normal: CGFloat = 0.5
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
