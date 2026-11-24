import Foundation
import CoreGraphics

/// One config key: its TOML name and section, where it lands on the config
/// value, how it decodes and encodes, and how a missing or invalid value is
/// repaired.
struct Field<T> {
    let key: String
    /// TOML section the key is written under. `[hudKeys]` is its own section,
    /// so its section equals its key.
    let section: String
    let keyPath: WritableKeyPath<SpacemapConfig, T>
    let decode: (Any) -> T?
    let encode: (T) -> String
    let repair: Repair<T>

    var erased: AnyField { AnyField(self) }
}

/// Repair rules for a missing or invalid key.
enum Repair<T> {
    /// Missing -> default, flags repair.
    case orDefault
    /// Missing -> default, no repair flag (new keys heal silently).
    case silentDefault
    /// Missing or failing the predicate -> default, flags repair.
    case valid((T) -> Bool)
    /// Missing or below range -> default; above range -> the upper bound. Both
    /// flag repair. Stored as comparisons so `Repair` stays unconstrained.
    case clamped(upper: T, isBelow: (T) -> Bool, isAbove: (T) -> Bool)
    /// Clamps to whichever bound the value crossed, without a repair flag: the
    /// next save still writes the clamped value, but no load rewrites the file
    /// just for this.
    case silentClamped(lower: T, upper: T, isBelow: (T) -> Bool, isAbove: (T) -> Bool)
}

extension Repair where T: Comparable {
    static func clampAbove(_ range: ClosedRange<T>) -> Repair<T> {
        .clamped(
            upper: range.upperBound,
            isBelow: { $0 < range.lowerBound },
            isAbove: { $0 > range.upperBound }
        )
    }

    static func silentClampAbove(_ range: ClosedRange<T>) -> Repair<T> {
        .silentClamped(
            lower: range.lowerBound,
            upper: range.upperBound,
            isBelow: { $0 < range.lowerBound },
            isAbove: { $0 > range.upperBound }
        )
    }
}

/// Type-erased `Field` so one section is one array of heterogeneous keys.
struct AnyField {
    let key: String
    let section: String
    private let applyRaw: ([String: Any], inout SpacemapConfig, inout Bool) -> Void
    private let line: (SpacemapConfig) -> String
    private let block: (SpacemapConfig) -> String

    init<T>(_ field: Field<T>) {
        key = field.key
        section = field.section
        applyRaw = { object, config, needsRepair in
            let fallback = config[keyPath: field.keyPath]
            let raw = object[field.key].flatMap(field.decode)
            switch field.repair {
            case .orDefault:
                if raw == nil { needsRepair = true }
                config[keyPath: field.keyPath] = raw ?? fallback
            case .silentDefault:
                config[keyPath: field.keyPath] = raw ?? fallback
            case .valid(let predicate):
                if let raw, predicate(raw) {
                    config[keyPath: field.keyPath] = raw
                } else {
                    needsRepair = true
                    config[keyPath: field.keyPath] = fallback
                }
            case .clamped(let upper, let isBelow, let isAbove):
                if let raw {
                    if isBelow(raw) {
                        needsRepair = true
                        config[keyPath: field.keyPath] = fallback
                    } else if isAbove(raw) {
                        needsRepair = true
                        config[keyPath: field.keyPath] = upper
                    } else {
                        config[keyPath: field.keyPath] = raw
                    }
                } else {
                    needsRepair = true
                    config[keyPath: field.keyPath] = fallback
                }
            case .silentClamped(let lower, let upper, let isBelow, let isAbove):
                if let raw {
                    if isBelow(raw) {
                        config[keyPath: field.keyPath] = lower
                    } else if isAbove(raw) {
                        config[keyPath: field.keyPath] = upper
                    } else {
                        config[keyPath: field.keyPath] = raw
                    }
                } else {
                    config[keyPath: field.keyPath] = fallback
                }
            }
        }
        line = { config in
            "\(field.key) = \(field.encode(config[keyPath: field.keyPath]))"
        }
        block = { config in
            field.encode(config[keyPath: field.keyPath])
        }
    }

    /// Reads this key from one parsed document into `config`, applying its
    /// repair rule and flagging a rewrite when the rule asks for one.
    func apply(from object: [String: Any], into config: inout SpacemapConfig, needsRepair: inout Bool) {
        applyRaw(object, &config, &needsRepair)
    }

    /// One TOML line from the config value.
    func encodeLine(from config: SpacemapConfig) -> String {
        line(config)
    }

    /// Body of a table-shaped key. The writer supplies the `[section]` header.
    func encodeBody(from config: SpacemapConfig) -> String {
        block(config)
    }
}

enum ConfigSchema {
    /// Decoded and repaired through the grid array, and repeated in the
    /// behavior array so the writer keeps emitting its line under `[behavior]`.
    /// Both walks are idempotent for this key.
    static let showThumbnailWallpaperField = Field(
        key: "showThumbnailWallpaper", section: "grid",
        keyPath: \.showThumbnailWallpaper,
        decode: bool, encode: { "\($0)" }, repair: .orDefault
    ).erased
}
