import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController {
    convenience init() {
        let hostingController = NSHostingController(rootView: SettingsView())
        let windowRect = NSRect(x: 0, y: 0, width: 520, height: 850)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Spacemap Settings"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 500, height: 400)
        window.maxSize = NSSize(width: 800, height: 10000)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.setFrameUsingName("Settings Window")
        if !window.frameAutosaveName.isEmpty {
            window.setFrameAutosaveName("")
        }
        window.setFrame(windowRect, display: true)
        self.init(window: window)
    }
    
    func showWindow() {
        super.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}