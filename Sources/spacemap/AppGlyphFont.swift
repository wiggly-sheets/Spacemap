import AppKit
import CoreText
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
    static let fontName = "sketchybar-app-font"
    static let defaultLigature = ":default:"

    private static let cacheLock = NSLock()
    private static var cachedFont: AppGlyphFont?

    /// Drops the cached font so the next load() re-reads disk. Called on
    /// .settingsChanged and after every install.
    static func invalidateCache() {
        cacheLock.lock()
        cachedFont = nil
        cacheLock.unlock()
    }

    /// True when CoreText can resolve the face for drawing. Metadata parsing
    /// alone is not enough: an unactivated font parses fine but renders wrong.
    static func isFontAvailable() -> Bool {
        NSFont(name: fontName, size: 11) != nil
    }

    /// Registers the bundled copy with CoreText when lookup fails (fresh
    /// install before the updater ever runs). No-op when already resolvable.
    /// Returns whether the face resolves afterwards.
    @discardableResult
    static func ensureRegistered() -> Bool {
        if isFontAvailable() { return true }
        guard let url = bundledURL() else { return false }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if let unmanaged = error {
            let cfError = unmanaged.takeRetainedValue()
            if CFErrorGetCode(cfError) != CTFontManagerError.alreadyRegistered.rawValue {
                NSLog("spacemap/GlyphStrip: could not register %@ — code \(CFErrorGetCode(cfError))", url.path)
            }
        }
        return isFontAvailable()
    }

    /// Direct bundle probe without the filesystem walk: the copy the app
    /// ships (auto-activated via ATSApplicationFontsPath, fallback here).
    static func bundledURL() -> URL? {
        let name = "\(resourceName).ttf"
        let fm = FileManager.default
        var roots: [URL?] = [
            Bundle.main.resourceURL,
            Bundle(for: AppGlyphFont.self).resourceURL,
            findModuleBundle()?.resourceURL,
        ]
        roots.append(contentsOf: ancestorDirs(of: Bundle.main.executableURL, depth: 2))
        for case let root? in roots {
            for candidate in [
                root.appendingPathComponent(name),
                root.appendingPathComponent("spacemap_spacemap.bundle").appendingPathComponent(name),
            ] where fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Release tag of the bundled copy, if it parses. Lets a fresh install
    /// skip a download it does not need.
    static func bundledRelease() -> String? {
        guard let url = bundledURL(),
              let data = try? Data(contentsOf: url),
              let font = parse(data: data) else { return nil }
        return font.release
    }

    let release: String

    private let exact: [String: String]
    private let prefixes: [(prefix: String, glyph: String)]
    private let defaultGlyph: String
    private let appNamesByLigature: [String: [String]]
    private let instanceLock = NSLock()
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
        instanceLock.lock()
        if let cached = cache[app] {
            instanceLock.unlock()
            return cached
        }
        instanceLock.unlock()
        let resolved = exact[app]
            ?? prefixes.first { app.hasPrefix($0.prefix) }?.glyph
            ?? defaultGlyph
        instanceLock.lock()
        cache[app] = resolved
        instanceLock.unlock()
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
    /// When both parse, the newer release tag wins instead of blindly taking
    /// the first file. Thread-safe via cacheLock; file IO stays off-main
    /// through prewarmInBackground.
    static func load() -> AppGlyphFont? {
        cacheLock.lock()
        let cached = cachedFont
        cacheLock.unlock()
        if let cached { return cached }
        var best: AppGlyphFont?
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let font = parse(data: data) else {
                // A font that exists but will not parse is a real fault, not a
                // missing optional, so say so instead of falling through silently.
                NSLog("spacemap/GlyphStrip: %@ has no readable APPM metadata", url.path)
                continue
            }
            if let current = best {
                best = isNewerRelease(font.release, than: current.release) ? font : current
            } else {
                best = font
            }
        }
        if let best {
            cacheLock.lock()
            // Another load filled the cache during our IO: keep theirs, drop ours.
            if let current = cachedFont {
                cacheLock.unlock()
                return current
            }
            cachedFont = best
            cacheLock.unlock()
        }
        return best
    }

    /// "v3.0.5" > "v3.0.4": numeric per-component compare, non-numeric tails
    /// compared lexically. Unparseable tags never displace a known best.
    static func isNewerRelease(_ candidate: String, than current: String) -> Bool {
        compareTags(candidate, current) == .orderedDescending
    }

    private static func compareTags(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        let lParts = lhs.trimmingCharacters(in: .letters).split(separator: ".")
        let rParts = rhs.trimmingCharacters(in: .letters).split(separator: ".")
        for (l, r) in zip(lParts, rParts) {
            if let li = Int(l), let ri = Int(r) {
                if li != ri { return li < ri ? .orderedAscending : .orderedDescending }
            } else if l != r {
                return l.lexicographicallyPrecedes(r) ? .orderedAscending : .orderedDescending
            }
        }
        if lParts.count != rParts.count {
            return lParts.count < rParts.count ? .orderedAscending : .orderedDescending
        }
        return lhs.lexicographicallyPrecedes(rhs) ? .orderedAscending : .orderedDescending
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

    /// `Bundle.module` is avoided by name: its generated accessor
    /// `fatalError`s when the SwiftPM resource bundle is absent, which is the
    /// case inside the hand-assembled `.app` where the ttf sits directly in
    /// `Contents/Resources`. Direct probes only: user/system Fonts dirs plus
    /// `bundledURL()` (no tree walk).
    static func candidateURLs() -> [URL] {
        let name = "\(resourceName).ttf"
        var urls: [URL] = [
            URL(fileURLWithPath: NSString(string: "~/Library/Fonts/\(name)").expandingTildeInPath),
            URL(fileURLWithPath: "/Library/Fonts/\(name)")
        ]
        if let bundled = bundledURL(), !urls.contains(bundled) {
            urls.append(bundled)
        }
        return urls
    }

    /// Returns the SwiftPM resource bundle (`spacemap_spacemap.bundle`) by
    /// replicating the generated `Bundle.module` logic but returning `nil`
    /// instead of `fatalError` when the bundle is absent (the hand-assembled
    /// `.app` layout where the ttf sits directly in `Contents/Resources`).
    private static func findModuleBundle() -> Bundle? {
        let bundleName = "spacemap_spacemap"
        var candidates = [
            Bundle.main.resourceURL,
            Bundle(for: AppGlyphFont.self).resourceURL,
            Bundle.main.bundleURL
        ].compactMap { $0 }
        // ponytail: linear ancestor climb; SwiftPM puts the .bundle beside the
        // xctest dir, 3+ levels above the test executable, and 5.9 does not
        // copy it into Contents/Resources the way 6.4 does.
        candidates.append(contentsOf: ancestorDirs(of: Bundle.main.executableURL, depth: 5))
        candidates.append(contentsOf: ancestorDirs(of: Bundle(for: AppGlyphFont.self).bundleURL, depth: 5))
        for candidate in candidates {
            let bundlePath = candidate.appendingPathComponent(bundleName + ".bundle")
            if FileManager.default.fileExists(atPath: bundlePath.path),
               let bundle = Bundle(url: bundlePath) {
                return bundle
            }
        }
        return nil
    }

    /// Parent dirs of `url`, up to `depth` levels. Covers the Swift 5.9
    /// `swift test` layout where `spacemap_spacemap.bundle` sits beside (not
    /// inside) the `.xctest` dir, several levels above the test executable.
    private static func ancestorDirs(of url: URL?, depth: Int) -> [URL] {
        guard var current = url?.deletingLastPathComponent() else { return [] }
        var dirs: [URL] = []
        for _ in 0..<depth {
            dirs.append(current)
            current = current.deletingLastPathComponent()
        }
        return dirs
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
