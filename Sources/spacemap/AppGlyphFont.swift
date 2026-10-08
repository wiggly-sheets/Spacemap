import Foundation

/// App-name to sketchybar-app-font glyph lookup.
///
/// The mapping is not shipped as data: it lives in the font's own `meta` table
/// under the `APPM` tag as JSON, so the ttf is the single source of truth.
final class AppGlyphFont {

    private struct Metadata: Decodable {
        /// The APPM payload stores each icon as a positional triple
        /// `[ligature, codepoint, appNames]`, with `appNames` occasionally null.
        struct Icon: Decodable {
            let ligature: String
            let codepoint: Int
            let appNames: [String]?

            init(from decoder: Decoder) throws {
                var values = try decoder.unkeyedContainer()
                ligature = try values.decode(String.self)
                codepoint = try values.decode(Int.self)
                appNames = try values.decodeIfPresent([String].self)
            }
        }

        let release: String
        let icons: [Icon]
    }

    static let resourceName = "sketchybar-app-font"
    static let defaultLigature = ":default:"

    private static let cacheLock = NSLock()
    private static var cachedFont: AppGlyphFont?

    let release: String

    private let exact: [String: String]
    private let prefixes: [(prefix: String, glyph: String)]
    private let defaultGlyph: String
    private let appNamesByLigature: [String: [String]]
    private var cache: [String: String] = [:]

    private init(metadata: Metadata) {
        var exact: [String: String] = [:]
        var prefixes: [(prefix: String, glyph: String)] = []
        var defaultGlyph = ""
        var appNamesByLigature: [String: [String]] = [:]

        for icon in metadata.icons {
            guard let scalar = UnicodeScalar(icon.codepoint) else { continue }
            let glyph = String(Character(scalar))
            let names = icon.appNames ?? []
            appNamesByLigature[icon.ligature] = names
            for name in names {
                if name.hasSuffix("*") {
                    let prefix = String(name.dropLast())
                    if !prefix.isEmpty { prefixes.append((prefix, glyph)) }
                } else {
                    exact[name] = glyph
                }
            }
            if icon.ligature == Self.defaultLigature { defaultGlyph = glyph }
        }

        // Longest prefix wins so "Google Chrome Beta" beats "Google".
        prefixes.sort { $0.prefix.count > $1.prefix.count }

        self.release = metadata.release
        self.exact = exact
        self.prefixes = prefixes
        self.defaultGlyph = defaultGlyph
        self.appNamesByLigature = appNamesByLigature
    }

    func appNames(forLigature ligature: String) -> [String]? {
        appNamesByLigature[ligature]
    }

    /// Longest-prefix match beats exact match only when no exact entry exists,
    /// mirroring the sketchybarrc lookup order.
    func glyph(forApp app: String) -> String {
        if let cached = cache[app] { return cached }
        let resolved = exact[app]
            ?? prefixes.first { app.hasPrefix($0.prefix) }?.glyph
            ?? defaultGlyph
        cache[app] = resolved
        return resolved
    }

    /// Used when the font cannot be loaded at all, so the strip still shows
    /// something identifiable instead of blank glyphs.
    static func initials(forApp app: String) -> String {
        let words = app.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters = words.compactMap { $0.first.map(String.init) }
        let combined = letters.prefix(2).joined()
        return combined.isEmpty ? "?" : combined.uppercased()
    }

    // MARK: - Loading

    /// User-installed copies first: the updater writes to `~/Library/Fonts`,
    /// so a newer downloaded font must beat the (possibly older) bundled one.
    static func load() -> AppGlyphFont? {
        cacheLock.lock()
        let cached = cachedFont
        cacheLock.unlock()
        if let cached { return cached }
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let font = parse(data: data) {
                cacheLock.lock()
                cachedFont = font
                cacheLock.unlock()
                return font
            }
            // A font that exists but will not parse is a real fault, not a
            // missing optional, so say so instead of falling through silently.
            NSLog("spacemap/GlyphStrip: %@ has no readable APPM metadata", url.path)
        }
        return nil
    }

    /// Off-main warmup so first HUD/strip paint never blocks on font IO.
    static func prewarmInBackground(completion: ((AppGlyphFont?) -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            let font = load()
            if let completion {
                DispatchQueue.main.async { completion(font) }
            }
        }
    }

    static func parse(data: Data) -> AppGlyphFont? {
        guard let payload = appMetadataPayload(in: data),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: payload) else { return nil }
        return AppGlyphFont(metadata: metadata)
    }

    /// `Bundle.module` is deliberately avoided: its generated accessor
    /// `fatalError`s when the SwiftPM resource bundle is absent, which is the
    /// case inside the hand-assembled `.app` where the ttf sits directly in
    /// `Contents/Resources`.
    static func candidateURLs() -> [URL] {
        let name = "\(resourceName).ttf"
        let spmBundle = "spacemap_spacemap.bundle/Contents/Resources/\(name)"
        var urls: [URL] = [
            URL(fileURLWithPath: NSString(string: "~/Library/Fonts/\(name)").expandingTildeInPath),
            URL(fileURLWithPath: "/Library/Fonts/\(name)")
        ]
        if let resources = Bundle.main.resourceURL {
            urls.append(resources.appendingPathComponent(name))
            urls.append(resources.appendingPathComponent(spmBundle))
        }
        let bundlePath = Bundle.main.bundleURL.path
        if !bundlePath.isEmpty {
            urls.append(Bundle.main.bundleURL.appendingPathComponent(spmBundle))
        }
        return urls
    }

    /// Reads the `APPM` record out of the font's `meta` table.
    ///
    /// Table records are 16 bytes (tag, checksum, offset, length); the `meta`
    /// table's own records are 12 bytes with the same field order.
    static func appMetadataPayload(in data: Data) -> Data? {
        let bytes = [UInt8](data)

        func uint16(at offset: Int) -> Int? {
            guard offset >= 0, offset + 2 <= bytes.count else { return nil }
            return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        func uint32(at offset: Int) -> Int? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        func tag(at offset: Int) -> String? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return String(bytes: bytes[offset..<(offset + 4)], encoding: .isoLatin1)
        }

        guard let tableCount = uint16(at: 4) else { return nil }

        for index in 0..<tableCount {
            let record = 12 + index * 16
            guard tag(at: record) == "meta",
                  let tableOffset = uint32(at: record + 8),
                  let tableLength = uint32(at: record + 12),
                  tableOffset + tableLength <= bytes.count,
                  let recordCount = uint32(at: tableOffset + 12) else { continue }

            for entry in 0..<recordCount {
                let metaRecord = tableOffset + 16 + entry * 12
                guard tag(at: metaRecord) == "APPM",
                      let payloadOffset = uint32(at: metaRecord + 4),
                      let payloadLength = uint32(at: metaRecord + 8),
                      payloadOffset + payloadLength <= tableLength else { continue }
                let start = tableOffset + payloadOffset
                return Data(bytes[start..<(start + payloadLength)])
            }
        }
        return nil
    }
}
