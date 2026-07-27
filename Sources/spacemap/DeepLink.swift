import Foundation

enum DeepLinkAction: String, CaseIterable {
    case toggleHUD = "toggle-hud"
    case pinHUD = "pin-hud"
    case settings
    case menu
    case config
    case themes

    init?(url: URL) {
        guard let scheme = url.scheme,
              scheme.lowercased() == "spacemap" else {
            return nil
        }

        let encodedAction: String
        if let host = url.host, !host.isEmpty {
            guard url.path.isEmpty || url.path == "/" else { return nil }
            encodedAction = host
        } else {
            let absoluteString = url.absoluteString
            guard let colon = absoluteString.firstIndex(of: ":") else { return nil }
            let opaqueAction = absoluteString[absoluteString.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !opaqueAction.isEmpty,
                  !opaqueAction.contains("/"),
                  !opaqueAction.contains("?"),
                  !opaqueAction.contains("#") else {
                return nil
            }
            encodedAction = opaqueAction
        }

        guard let actionName = encodedAction.removingPercentEncoding?.lowercased() else { return nil }
        self.init(rawValue: actionName)
    }
}
