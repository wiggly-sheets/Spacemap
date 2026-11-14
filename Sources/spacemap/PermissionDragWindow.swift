import AppKit

/// Small floating helper whose app icon can be dragged into the permission list
/// in System Settings. macOS adds an app when its bundle is dropped there.
final class PermissionDragWindowController: NSWindowController {
    static let shared = PermissionDragWindowController()

    private init() {
        let size = NSSize(width: 180, height: 190)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Drag Spacemap"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.contentView = DraggableAppIconView(frame: NSRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Drag source for the app bundle. A plain `NSImageView` cannot start a file
/// drag, so the icon and its label are drawn here.
private final class DraggableAppIconView: NSView, NSDraggingSource {
    private var icon: NSImage { NSApp.applicationIconImage ?? NSImage() }
    private let iconSide: CGFloat = 96

    private var iconRect: NSRect {
        NSRect(x: (bounds.width - iconSide) / 2, y: 58, width: iconSide, height: iconSide)
    }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: iconRect)
        let text = "Drag into Permissions" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: 28),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(iconRect, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    /// Closes the helper once the drop was accepted, so it does not linger over
    /// System Settings after granting.
    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        guard !operation.isEmpty else { return }
        window?.close()
    }
}
