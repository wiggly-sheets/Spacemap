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
        let toolbar = NSToolbar()
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.minSize = NSSize(width: 720, height: 520)
        window.maxSize = NSSize(width: 1400, height: 10000)
        if window.setFrameUsingName(Self.frameAutosaveName) {
            Self.clampWidth(window)
        } else {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        super.init(window: window)

        // The glass can only sample the desktop when the window itself is
        // transparent. With the default opaque `windowBackgroundColor` the
        // detail column just shows a flat, frosted window background.
        window.isOpaque = false
        window.backgroundColor = .clear

        window.contentView = Self.makeEffectRoot(hostingView: hostingController.view)
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

    /// Native settings-window backdrop: NSGlassEffectView when
    /// `GlassSupport.isAvailable` (macOS 26+, Reduce Transparency off),
    /// NSVisualEffectView otherwise. The SwiftUI content must be the glass's
    /// `contentView`; arbitrary subviews are not guaranteed to be part of the
    /// glass effect.
    private static func makeEffectRoot(hostingView: NSView) -> NSView {
        // `NSGlassEffectView` only exists in 6.2+ SDKs. Xcode 16 ships Swift
        // 6.0/6.1 with the macOS 15 SDK where the type is absent, so this must
        // be source-excluded rather than only gated by `#available`.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), GlassSupport.isAvailable {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = true
            }
            glass.contentView = hostingView
            return glass
        }
        #endif
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        pinContent(hostingView, in: root)
        return root
    }

    /// The effect root fills the whole window and the SwiftUI content fills the
    /// root, so the sidebar runs up under the traffic lights like System
    /// Settings. SwiftUI keeps the sidebar rows inside the titlebar safe area.
    private static func pinContent(_ view: NSView, in root: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
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
