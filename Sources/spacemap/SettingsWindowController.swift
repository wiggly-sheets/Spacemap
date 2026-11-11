import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let frameAutosaveName = "Spacemap Settings Window"

    private let hostingController: NSHostingController<SettingsView>

    init(yabaiService: YabaiService) {
        let hostingController = NSHostingController(rootView: SettingsView(yabaiService: yabaiService))
        self.hostingController = hostingController

        let windowRect = NSRect(x: 0, y: 0, width: 900, height: 820)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Spacemap Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 720, height: 520)
        window.maxSize = NSSize(width: 1400, height: 10000)
        if window.setFrameUsingName(Self.frameAutosaveName) {
            Self.clampWidth(window)
        } else {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        super.init(window: window)
        let root = Self.makeEffectRoot()
        window.contentView = root
        Self.pinContent(hostingController.view, in: root)
    }

    /// An autosaved frame from an older, narrower build would leave the sidebar
    /// truncated, so widen it to the minimum. The origin stays put.
    private static func clampWidth(_ window: NSWindow) {
        guard window.frame.width < window.minSize.width else { return }
        var frame = window.frame
        frame.size.width = window.minSize.width
        window.setFrame(frame, display: false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showWindow() {
        super.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Native settings-window backdrop: translucent material behind the
    /// SwiftUI content (mirrors AboutWindowController's root).
    private static func makeEffectRoot() -> NSVisualEffectView {
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        return root
    }

    /// The effect root fills the whole window and the SwiftUI content fills the
    /// root, so the sidebar runs up under the traffic lights like System
    /// Settings. SwiftUI keeps the sidebar rows inside the titlebar safe area.
    private static func pinContent(_ view: NSView, in root: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            view.topAnchor.constraint(equalTo: root.topAnchor),
            view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }
}
