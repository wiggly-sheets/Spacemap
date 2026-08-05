import AppKit

final class MenubarManager {
    private let services: SpacemapServices
    private var statusItem: NSStatusItem?
    private var menubarRefreshWorkItem: DispatchWorkItem?
    private var menubarRefreshGeneration = 0

    init(services: SpacemapServices, currentConfig: GridConfig? = nil) {
        self.services = services
        // currentConfig can be used if needed; currently not stored but passed to methods
    }

    var statusItem: NSStatusItem? {
        get { return self.statusItem }
        set { self.statusItem = newValue }
    }

    func setupMenubarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.services.applyMenubarIcon(to: item)
        self.statusItem = item
    }

    func setMenu(_ menu: NSMenu) {
        statusItem?.menu = menu
    }

    func applyMenubarVisibility(config: GridConfig) {
        if config.hideMenuBarIcon {
            if let item = statusItem {
                item.isVisible = false
            }
            statusItem = nil
        } else if statusItem == nil {
            setupMenubarItem()
        }
    }

    func refreshMenubarPreview(config: GridConfig? = nil) {
        let config = config ?? Config.load()
        guard let item = statusItem else { return }
        menubarRefreshGeneration += 1
        let generation = menubarRefreshGeneration
        menubarRefreshWorkItem?.cancel()

        if config.menuBarDisplayMode == .icon {
            self.services.applyMenubarIcon(to: item)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            DispatchQueue.global(qos: .utility).async {
                let state = self.services.yabaiService.buildGridState(config: config, focusedIndex: nil)
                DispatchQueue.main.async {
                    guard generation == self.menubarRefreshGeneration,
                          let currentItem = self.statusItem else { return }
                    if let image = MenuBarPreviewRenderer.image(for: state) {
                        currentItem.length = image.size.width + 8
                        currentItem.button?.image = image
                        currentItem.button?.imageScaling = .scaleProportionallyDown
                        currentItem.button?.toolTip = NSLocalizedString("Spacemap workspace preview", comment: "")
                    } else {
                        self.services.applyMenubarIcon(to: currentItem)
                    }
                }
            }
        }
        menubarRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func applyMenubarIcon(to item: NSStatusItem) {
        item.length = NSStatusItem.squareLength
        item.button?.image = NSImage(
            systemSymbolName: "square.grid.3x3",
            accessibilityDescription: "Spacemap"
        )
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "Spacemap"
    }

    private func hotkeyMenuString(_ hotkey: HotkeyConfig) -> String {
        switch hotkey.key {
        case .none:
            return "None"
        case .mediaKey(let mediaKey):
            var parts: [String] = []
            if hotkey.modifiers.contains(.maskControl) { parts.append("⌃") }
            if hotkey.modifiers.contains(.maskCommand) { parts.append("⌘") }
            if hotkey.modifiers.contains(.maskAlternate) { parts.append("⌥") }
            if hotkey.modifiers.contains(.maskShift) { parts.append("⇧") }
            parts.append(mediaKey.rawValue)
            return parts.joined(separator: "+")
        case .keyCode(let keyCode):
            var parts: [String] = []
            if hotkey.modifiers.contains(.maskControl) { parts.append("⌃") }
            if hotkey.modifiers.contains(.maskCommand) { parts.append("⌘") }
            if hotkey.modifiers.contains(.maskAlternate) { parts.append("⌥") }
            if hotkey.modifiers.contains(.maskShift) { parts.append("⇧") }
            switch keyCode {
            case 121: parts.append("PgDn")
            case 116: parts.append("PgUp")
            case 49:  parts.append("Space")
            case 48:  parts.append("Tab")
            case 36:  parts.append("Return")
            case 53:  parts.append("Esc")
            case 51:  parts.append("Del")
            case 123: parts.append("←")
            case 124: parts.append("→")
            case 125: parts.append("↓")
            case 126: parts.append("↑")
            default:  parts.append("?")
            }
            return parts.joined(separator: "+")
        }
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        symbolName: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        return item
    }

    private func workspacePreviewsEnabled(for config: GridConfig) -> Bool {
        !config.hideMenuBarIcon && config.menuBarDisplayMode != .icon
    }

    private func windowGeometryPreviewsEnabled(for config: GridConfig) -> Bool {
        workspacePreviewsEnabled(for: config) && config.menuBarDisplayMode != .dots
    }
}
