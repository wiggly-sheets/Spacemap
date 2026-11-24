import SwiftUI
import AppKit
import Combine

extension CellView {
    var thumbnailCapture: NSImage? {
        guard #available(macOS 14.0, *) else { return nil }
        return thumbnailStore.image(forSpace: spaceIndex)
    }

    func appDragGesture(windowID: Int, app: String) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { _ in
                guard !iconDragActive else { return }
                iconDragActive = true
                onWindowDragStart?(spaceIndex)
                onDragActive?(true)
            }
            .onEnded { _ in
                // One icon per window moves that window; a deduped app icon
                // moves every window of the app.
                let ids = showMultiAppIcons
                    ? [windowID]
                    : windows.filter { $0.app == app }.map(\.id)
                onWindowDrop?(ids, spaceIndex, NSEvent.mouseLocation)
                onDragActive?(false)
                iconDragActive = false
            }
    }

    func thumbnailImage(_ spaceIndex: Int) -> some View {
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
    
}
