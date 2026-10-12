import SwiftUI

struct GridView: View {
    let state: GridState
    let hoveredCell: Int?
    let onSelect: (Int) -> Void
    let uiScale: Double
    let theme: String
    let displayNumber: Int?
    let resolvedTheme: AppTheme
    
    private var isDarkMode: Bool {
        switch state.config.mode {
        case .light: return false
        case .dark:  return true
        case .auto:  return NSApp.effectiveAppearance.name == .darkAqua
        }
    }

    private var displayNumberColor: Color {
        Color(hex: resolvedTheme.text).opacity(0.9)
    }
    
    private let _visibleSpaceIndices: [Int]
    private let activeSpaceIndices: Set<Int>
    private let labelBySpaceIndex: [Int: String]
    private let displayIndexBySpace: [Int: Int]
    private let boundsByDisplayIndex: [Int: CGRect]

    private struct DisplayBoundary: Identifiable {
        let offset: Int
        let displayIndex: Int

        var id: Int { offset }
    }
    
    var body: some View {
        let cells = visibleSpaceIndices
        let safeCols = max(1, state.config.cols)
        let rows = stride(from: 0, to: cells.count, by: safeCols).map {
            Array(cells[$0..<min($0 + safeCols, cells.count)])
        }
        VStack(spacing: effectiveGap) {
            ForEach(0..<rows.count, id: \.self) { row in
                HStack(spacing: effectiveGap) {
                    ForEach(rows[row], id: \.self) { spaceIndex in
                        makeCell(for: spaceIndex, row: row)
                    }
                }
            }
        }
        .padding(effectivePadding)
        .background(
            LiquidGlassBackground(cornerRadius: 10, alpha: state.config.backgroundAlpha, isDarkMode: isDarkMode, theme: theme)
        )
        .overlay(alignment: .topLeading) {
            displayBoundaryOverlay
        }
        .overlay {
            if let displayNumber {
                Text("\(displayNumber)")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(displayNumberColor)
                    .allowsHitTesting(false)
            }
        }
    }
    
    private func spaceLabel(for index: Int) -> String? {
        labelBySpaceIndex[index]
    }
    
    var visibleSpaceIndices: [Int] {
        _visibleSpaceIndices
    }

    private var displayBoundaries: [DisplayBoundary] {
        guard state.config.multiMonitorHUDMode == .unified,
              state.populatedDisplayIndices.count > 1 else { return [] }

        var boundaries: [DisplayBoundary] = []
        var previousDisplayIndex: Int?
        for (offset, spaceIndex) in visibleSpaceIndices.enumerated() {
            guard let displayIndex = displayIndexBySpace[spaceIndex] else { continue }
            if let previousDisplayIndex, previousDisplayIndex != displayIndex {
                boundaries.append(DisplayBoundary(offset: offset, displayIndex: displayIndex))
            }
            previousDisplayIndex = displayIndex
        }
        return boundaries
    }

    @ViewBuilder
    private var displayBoundaryOverlay: some View {
        GeometryReader { _ in
            ForEach(displayBoundaries) { boundary in
                let columns = max(1, state.config.cols)
                let row = boundary.offset / columns
                let column = boundary.offset % columns
                let slotWidth = effectiveCellWidth + effectiveGap
                let slotHeight = effectiveCellHeight + effectiveGap
                let separatorColor = Color(hex: resolvedTheme.focused).opacity(isDarkMode ? 0.7 : 0.45)

                if column == 0 {
                    Rectangle()
                        .fill(separatorColor)
                        .frame(width: idealSize.width - effectivePadding * 2, height: max(2, effectiveGap * 0.2))
                        .offset(
                            x: effectivePadding,
                            y: effectivePadding + CGFloat(row) * slotHeight - effectiveGap / 2
                        )
                } else {
                    Rectangle()
                        .fill(separatorColor)
                        .frame(width: max(2, effectiveGap * 0.2), height: effectiveCellHeight + effectiveGap)
                        .offset(
                            x: effectivePadding + CGFloat(column) * slotWidth - effectiveGap / 2,
                            y: effectivePadding + CGFloat(row) * slotHeight - effectiveGap / 2
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func makeCell(for spaceIndex: Int, row: Int) -> some View {
        let cellSpaceIndex = spaceIndex
        let cellSpaceLabel = spaceLabel(for: spaceIndex)
        let cellSpaceName = state.config.spaceNames[spaceIndex]
        let cellIsFocused = spaceIndex == state.focusedIndex
        let cellIsDropTarget = spaceIndex == hoveredCell
        let cellWindows = state.windows(forSpace: spaceIndex)
        let cellDisplayBounds = displayIndexBySpace[spaceIndex].flatMap { boundsByDisplayIndex[$0] } ?? state.displayBounds
        let cellStyle = state.config.cellStyle
        let cellIsActive = activeSpaceIndices.contains(spaceIndex)

        return CellView(
            spaceIndex: cellSpaceIndex,
            spaceLabel: cellSpaceLabel,
            spaceName: cellSpaceName,
            isFocused: cellIsFocused,
            isDropTarget: cellIsDropTarget,
            isActive: cellIsActive,
            windows: cellWindows,
            displayBounds: cellDisplayBounds,
            cellStyle: cellStyle,
            onSelect: onSelect,
            uiScale: GridLayout.effectiveScale(for: uiScale),
            resolvedTheme: resolvedTheme,
            mode: state.config.mode,
            iconScale: 0.2 + CGFloat(state.config.iconScale) * 0.8,
            showSpaceNumbers: state.config.showSpaceNumbers,
            showSpaceNames: state.config.showSpaceNames,
            showIconStrip: state.config.showIconStrip,
            showMultiAppIcons: state.config.showMultiAppIcons,
            showExtraWindows: state.config.showExtraWindows
        )
    }
    
    private var effectiveScale: CGFloat { GridLayout.effectiveScale(for: uiScale) }
    var effectiveCellWidth: CGFloat { GridLayout.cellSize(for: uiScale).width }
    var effectiveCellHeight: CGFloat { GridLayout.cellSize(for: uiScale).height }
    var effectiveGap: CGFloat { GridLayout.gap(for: uiScale) }
    var effectivePadding: CGFloat { GridLayout.padding(for: uiScale) }

    var idealSize: CGSize {
        GridLayout.idealSize(visibleIndices: visibleSpaceIndices.count,
                             cols: state.config.cols,
                             uiScale: uiScale)
    }

    init(
        state: GridState,
        hoveredCell: Int?,
        displayNumber: Int? = nil,
        onSelect: @escaping (Int) -> Void,
        uiScale: Double = 1.0,
        theme: String = "default",
        resolvedTheme: AppTheme,
        spaceIndices: [Int]? = nil
    ) {
        self.state = state
        self.hoveredCell = hoveredCell
        self.displayNumber = displayNumber
        self.onSelect = onSelect
        self.uiScale = uiScale
        self.theme = theme
        self.resolvedTheme = resolvedTheme
        if let spaceIndices {
            self._visibleSpaceIndices = spaceIndices.sorted()
        } else {
            let activeSet = Set(state.spaces.map { $0.index })
            self._visibleSpaceIndices = GridLayout.visibleSpaceIndices(
                maxSpaces: state.config.maxSpaces,
                showMode: state.config.showMode,
                activeIndices: activeSet
            )
        }
        self.activeSpaceIndices = Set(state.spaces.map(\.index))
        self.labelBySpaceIndex = Dictionary(
            uniqueKeysWithValues: state.spaces.compactMap { space in
                space.label.map { (space.index, $0) }
            }
        )
        self.displayIndexBySpace = Dictionary(
            uniqueKeysWithValues: state.spaces.map { ($0.index, $0.display) }
        )
        self.boundsByDisplayIndex = Dictionary(
            uniqueKeysWithValues: state.displays.map { ($0.index, $0.frame.cgFrame) }
        )
    }
}
