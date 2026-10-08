import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let frameAutosaveName = "Spacemap Settings Window"

    private let hostingController: NSHostingController<SettingsView>

    init(yabaiService: YabaiService) {
        let hostingController = NSHostingController(rootView: SettingsView(yabaiService: yabaiService))
        self.hostingController = hostingController

        let windowRect = NSRect(x: 0, y: 0, width: 520, height: 850)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spacemap Settings"
        window.minSize = NSSize(width: 500, height: 400)
        window.maxSize = NSSize(width: 800, height: 10000)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        super.init(window: window)
        window.contentView = Self.makeEffectRoot(hostingView: hostingController.view)
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
    private static func makeEffectRoot(hostingView: NSView) -> NSVisualEffectView {
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: root.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }
}