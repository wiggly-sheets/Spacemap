import Foundation
import AppKit

extension YabaiClientImpl {
    /// Skips one bad array entry instead of failing the whole query.
    /// One malformed space/window (version skew) must not blank the HUD.
    struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = try? container.decode(T.self)
        }
    }

    /// Last dropped count per label: persistent skew logs once per count,
    /// not once per refresh.
    static var lastDropCounts: [String: Int] = [:]
    static let dropLock = NSLock()

    func decodeTolerant<T: Decodable>(_ type: T.Type, from output: String, label: String) throws -> [T] {
        let decoded = try JSONDecoder().decode([Failable<T>].self, from: Data(output.utf8))
        let dropped = decoded.filter { $0.value == nil }.count
        if dropped > 0 {
            Self.dropLock.lock()
            defer { Self.dropLock.unlock() }
            let last = Self.lastDropCounts[label]
            Self.lastDropCounts[label] = dropped
            if last != dropped { NSLog("spacemap/yabai: dropped %d malformed %@ entries", dropped, label) }
        }
        return decoded.compactMap(\.value)
    }

}
