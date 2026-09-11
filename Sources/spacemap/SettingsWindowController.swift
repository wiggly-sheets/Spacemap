import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let frameAutosaveName = "Spacemap Settings Window"

    convenience init(yabaiService: YabaiService) {
        let hostingController = NSHostingController(rootView: SettingsView(yabaiService: yabaiService))
        let windowRect = NSRect(x: 0, y: 0, width: 520, height: 850)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spacemap Settings"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 500, height: 400)
        window.maxSize = NSSize(width: 800, height: 10000)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        self.init(window: window)
    }

    func showWindow() {
        super.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
