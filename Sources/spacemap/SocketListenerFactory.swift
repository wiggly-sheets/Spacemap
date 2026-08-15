import Foundation
import ServiceManagement

final class SocketListenerFactory {
    func makeSocketListener(
        socketPath: String,
        healthInterval: Int,
        onRefresh: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) -> SocketListener {
        SocketListener(
            socketPath: socketPath,
            healthInterval: healthInterval,
            onRefresh: onRefresh,
            onShow: onShow,
            onToggle: onToggle,
            onSettings: onSettings
        )
    }
}
