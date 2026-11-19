import AppKit

final class DeepLinkService {
    private let hud: HUDWindowController
    private let themeStore: ThemeStore
    private let showSettings: () -> Void
    private let showMenu: () -> Void
    private var isReady = false
    private var pendingActions: [DeepLinkAction] = []

    init(hud: HUDWindowController, themeStore: ThemeStore, showSettings: @escaping () -> Void, showMenu: @escaping () -> Void) {
        self.hud = hud
        self.themeStore = themeStore
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
            _ = ConfigStore.load()
            NSWorkspace.shared.open(URL(fileURLWithPath: ConfigStore.configPath))
        case .themes:
            themeStore.reload()
            NSWorkspace.shared.open(themeStore.directory)
        }
    }

    func handlePendingDeepLinks() {
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach { handleDeepLink($0) }
    }

    private static let maxPendingActions = 16

    func open(urls: [URL]) {
        for url in urls {
            guard let action = DeepLinkAction(url: url) else {
                NSLog("Spacemap: ignored unsupported deep link scheme=%@ len=%d", url.scheme ?? "nil", url.absoluteString.count)
                continue
            }
            if isReady {
                handleDeepLink(action)
            } else {
                if pendingActions.count >= Self.maxPendingActions {
                    pendingActions.removeFirst()
                    NSLog("Spacemap: deep link queue full, dropped oldest")
                }
                pendingActions.append(action)
            }
        }
    }
}
