import AppKit

/// Handles deep link operations.
final class DeepLinkService: DeepLinkHandling {
    private let hud: HUDWindowController
    private let themeService: ThemeService
    private let showSettings: () -> Void
    private let showMenu: () -> Void
    private var isReady = false
    private var pendingActions: [DeepLinkAction] = []

    init(hud: HUDWindowController, themeService: ThemeService, showSettings: @escaping () -> Void, showMenu: @escaping () -> Void) {
        self.hud = hud
        self.themeService = themeService
        self.showSettings = showSettings
        self.showMenu = showMenu
    }

    func setReady(_ ready: Bool) {
        isReady = ready
        if ready {
            handlePendingDeepLinks()
        }
    }

    func handleDeepLink(_ action: DeepLinkAction) {
        switch action {
        case .toggleHUD:
            hud.toggle()
        case .pinHUD:
            hud.pin()
        case .settings:
            showSettings()
        case .menu:
            showMenu()
        case .config:
            _ = Config.load()
            NSWorkspace.shared.open(URL(fileURLWithPath: Config.configPath))
        case .themes:
            themeService.reload()
            NSWorkspace.shared.open(ThemeManager.themesDir())
        }
    }

    func handlePendingDeepLinks() {
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach { handleDeepLink($0) }
    }

    func open(urls: [URL]) {
        for url in urls {
            guard let action = DeepLinkAction(url: url) else {
                NSLog("Spacemap: ignored unsupported deep link \(url.absoluteString)")
                continue
            }
            if isReady {
                handleDeepLink(action)
            } else {
                pendingActions.append(action)
            }
        }
    }
}