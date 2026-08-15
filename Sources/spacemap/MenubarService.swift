import AppKit
import Foundation

final class MenubarService {
    private let menubarHandler: MenubarHandler

    init(menubarHandler: MenubarHandler) {
        self.menubarHandler = menubarHandler
    }

    func setupMenubar() {
        menubarHandler.setupMenubar()
    }

    func showMenubarMenu() {
        menubarHandler.showMenubarMenu()
    }

    func applyMenubarVisibility(config: GridConfig) {
        menubarHandler.applyMenubarVisibility(config: config)
    }

    func refreshMenubarPreview(config: GridConfig? = nil) {
        menubarHandler.refreshMenubarPreview(config: config)
    }

    func applyMenubarIcon(to item: NSStatusItem) {
        menubarHandler.applyMenubarIcon(to: item)
    }

    func hotkeyMenuString(_ hotkey: HotkeyConfig) -> String {
        menubarHandler.hotkeyMenuString(hotkey)
    }
}
