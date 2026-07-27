import Foundation

enum DeepLinkAction: String, CaseIterable {
    case toggleHUD = "toggle-hud"
    case pinHUD = "pin-hud"
    case settings
    case menu
    case config
    case themes

    init?(url: URL) {
        guard url.scheme?.lowercased() == "spacemap" else { return nil }

        let pathAction = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let actionName = (url.host?.isEmpty == false ? url.host : pathAction)?
            .removingPercentEncoding?
            .lowercased()

        guard url.path.isEmpty || url.path == "/" || url.host == nil,
              let actionName else {
            return nil
        }
        self.init(rawValue: actionName)
    }
}
