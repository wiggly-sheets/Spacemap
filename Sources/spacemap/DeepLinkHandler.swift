import AppKit

class DeepLinkHandler {
    private let hud: HUDWindowController
    private let themeService: ThemeService
    private let showSettings: () -> Void
    private let showMenu: () -> Void

    var isReady = false
    private var pendingActions: [DeepLinkAction] = []

    init(hud: HUDWindowController, themeService: ThemeService, showSettings: @escaping () -> Void, showMenu: @escaping () -> Void) {
        self.hud = hud
        self.themeService = themeService
        self.showSettings = showSettings
        self.showMenu = showMenu
    }

    func open(urls: [URL]) {
        for url in urls {
            guard let action = DeepLinkAction(url: url) else {
                NSLog("Spacemap: ignored unsupported deep link \(url.absoluteString)")
                continue
            }
            if isReady {
                handle(action)
            } else {
                pendingActions.append(action)
            }
        }
    }

    func handlePending() {
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach(handle)
    }

    func handle(_ action: DeepLinkAction) {
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
}
