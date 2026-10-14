import CryptoKit
import Foundation
import CoreText

/// GitHub-release updater for the sketchybar-app-font glyph font.
///
/// The ttf is not in the repo (dist/ is gitignored) — it ships only as a
/// release asset named `sketchybar-app-font.ttf`, so the release API is the
/// single source of truth for new versions.
struct AppFontUpdater {

    struct ReleaseInfo: Equatable {
        let tag: String
        let downloadURL: URL
        let size: Int
        /// GitHub asset `digest` ("sha256:…") when the API provides one.
        /// Upstream publishes no sidecar hash file, so nil means
        /// magic-bytes-only validation (vendor limitation, noted).
        let sha256: String?
    }

    enum UpdateError: LocalizedError, Equatable {
        case httpStatus(Int)
        case unreadableRelease
        case assetMissing
        case notAFont
        case hashMismatch
        case tooLarge
        case untrustedHost
        case symlinkRefused
        case installFailed

        var errorDescription: String? {
            switch self {
            case .httpStatus(let code) where code == 403 || code == 429:
                return "GitHub rate limit hit (HTTP \(code)) — retry later, no state changed"
            case .httpStatus(let code): return "HTTP \(code)"
            case .unreadableRelease: return "unreadable release metadata"
            case .assetMissing: return "release has no ttf asset"
            case .notAFont: return "downloaded file is not a font"
            case .hashMismatch: return "download hash does not match release digest"
            case .tooLarge: return "download exceeds size limit"
            case .untrustedHost: return "download host is not trusted"
            case .symlinkRefused: return "refusing symlinked font destination"
            case .installFailed: return "font install failed"
            }
        }
    }

    enum CheckResult: Equatable {
        case upToDate(tag: String)
        case updated(ReleaseInfo)
    }

    static let assetName = "sketchybar-app-font.ttf"
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/kvndrsslr/sketchybar-app-font/releases/latest"
    )!
    /// Releases ship daily-ish; auto mode must not hammer the unauthenticated
    /// API across restarts.
    static let checkInterval: TimeInterval = 24 * 60 * 60
    static let maxDownloadBytes = 20 * 1024 * 1024
    static let downloadTimeout: TimeInterval = 30

    static var installURL: URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Fonts/\(assetName)").expandingTildeInPath)
    }

    // MARK: - Pure logic (no I/O, testable)

    /// Picks the ttf asset out of GitHub's `/releases/latest` JSON.
    static func parseRelease(_ data: Data) throws -> ReleaseInfo {
        struct Payload: Decodable {
            let tag_name: String
            let assets: [Asset]

            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
                let size: Int
                let digest: String?
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw UpdateError.unreadableRelease
        }
        guard let asset = payload.assets.first(where: { $0.name == assetName }),
              let url = URL(string: asset.browser_download_url),
              url.scheme == "https" else {
            throw UpdateError.assetMissing
        }
        return ReleaseInfo(tag: payload.tag_name, downloadURL: url, size: asset.size, sha256: canonicalDigest(asset.digest))
    }

    /// Accepts "sha256:<64 hex>" or bare 64-hex; anything else = no pin.
    static func canonicalDigest(_ raw: String?) -> String? {
        guard var hex = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !hex.isEmpty else { return nil }
        if hex.hasPrefix("sha256:") { hex = String(hex.dropFirst(7)) }
        let isHex = hex.count == 64 && hex.unicodeScalars.allSatisfy({ "0123456789abcdef".unicodeScalars.contains($0) })
        return isHex ? hex : nil
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Empty installed tag = bundled copy only, which may already be current —
    /// but the tag comparison is the only cheap way to know, so the first check
    /// downloads once and tracks from then on.
    static func needsUpdate(installedTag: String, latestTag: String) -> Bool {
        installedTag != latestTag
    }

    /// Sanity check before anything touches disk: size floor plus the sfnt
    /// magic bytes (`00 01 00 00` TrueType, `true` Apple TrueType, `OTTO` CFF).
    static func isValidFontData(_ data: Data) -> Bool {
        guard data.count > 100_000 else { return false }
        let magic = [UInt8](data.prefix(4))
        return magic == [0x00, 0x01, 0x00, 0x00]
            || magic == Array("true".utf8)
            || magic == Array("OTTO".utf8)
    }

    /// Full download gate: magic bytes plus a real APPM metadata payload — a
    /// valid sfnt without the mapping table is useless to the strip and must
    /// not install.
    static func isInstallableFontData(_ data: Data) -> Bool {
        guard isValidFontData(data) else { return false }
        return AppGlyphFont.appMetadataPayload(in: data) != nil
    }

    static func isTrustedDownloadHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    // MARK: - I/O

    static func latestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: downloadTimeout)
        request.setValue("spacemap", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral, delegate: RedirectGuard(), delegateQueue: nil)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try parseRelease(data)
    }

    static func downloadAndInstall(_ info: ReleaseInfo) async throws {
        guard isTrustedDownloadHost(info.downloadURL) else { throw UpdateError.untrustedHost }
        guard info.size <= maxDownloadBytes else { throw UpdateError.tooLarge }
        let request = URLRequest(url: info.downloadURL, timeoutInterval: downloadTimeout)
        let session = URLSession(configuration: .ephemeral, delegate: RedirectGuard(), delegateQueue: nil)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard data.count <= maxDownloadBytes else { throw UpdateError.tooLarge }
        guard isValidFontData(data) else { throw UpdateError.notAFont }
        guard AppGlyphFont.appMetadataPayload(in: data) != nil else { throw UpdateError.notAFont }
        // Verify before anything touches disk when the release pins a digest.
        if let pinned = info.sha256, sha256Hex(of: data) != pinned {
            throw UpdateError.hashMismatch
        }

        let destination = installURL
        // Fail closed on a planted link: rename() below replaces the link
        // itself, but a pre-existing symlink still means someone staged the
        // path — refuse instead of installing through it.
        guard !ConfigLoader.isSymlink(at: destination.path) else { throw UpdateError.symlinkRefused }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try secureWriteData(data, to: destination)

        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &error),
           let unmanaged = error {
            let cfError = unmanaged.takeRetainedValue()
            // Re-registering an already-installed font is not a failure; the
            // valid file on disk is what matters (glyph metadata is read
            // straight from the file, not from CoreText).
            if CFErrorGetCode(cfError) != CTFontManagerError.alreadyRegistered.rawValue {
                NSLog("spacemap/AppFont: could not register \(destination.path) — code \(CFErrorGetCode(cfError))")
            }
        }

        // The glyph strip caches its font lookup; a fresh install must make the
        // next refresh rebuild its runs against the new face.
        AppGlyphFont.invalidateCache()
        AppGlyphFont.ensureRegistered()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    /// Binary mirror of ConfigLoader.secureWrite: temp file born 0600 via
    /// O_NOFOLLOW, then renamed. Rename over a symlink replaces the link
    /// itself, and the pre-write isSymlink gate above refuses planted links.
    private static func secureWriteData(_ data: Data, to destination: URL) throws {
        guard !ConfigLoader.isSymlink(at: destination.path) else { throw UpdateError.symlinkRefused }
        let dir = destination.deletingLastPathComponent().path
        let tmpPath = (dir as NSString).appendingPathComponent(
            ".spacemap.font.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp")
        let fd = open(tmpPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw UpdateError.installFailed }
        defer { close(fd) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == data.count else {
            unlink(tmpPath)
            throw UpdateError.installFailed
        }
        _ = fchmod(fd, mode_t(0o600))
        guard rename(tmpPath, destination.path) == 0 else {
            unlink(tmpPath)
            throw UpdateError.installFailed
        }
    }

    /// One check: fetch latest, download only when the tag differs. A fresh
    /// install (empty tag) compares against the bundled copy's release, so an
    /// already-current bundle never triggers a pointless download.
    static func runCheck(installedTag: String) async throws -> CheckResult {
        let effectiveTag = installedTag.isEmpty
            ? (AppGlyphFont.load()?.release ?? "")
            : installedTag
        let latest = try await latestRelease()
        guard needsUpdate(installedTag: effectiveTag, latestTag: latest.tag) else {
            return .upToDate(tag: latest.tag)
        }
        try await downloadAndInstall(latest)
        return .updated(latest)
    }

    /// Persists check state into `[appFont]`; pass the tag only after a
    /// successful install. Failures record nothing so the next launch retries.
    static func recordCheck(installedTag: String?) {
        var config = AppConfig.load()
        if let installedTag {
            config.appFont.installedVersion = installedTag
        }
        config.appFont.lastCheck = Int(Date().timeIntervalSince1970)
        AppConfig.saveConfig(config)
    }

    /// Deny redirects off the download allowlist. Same-host API redirects
    /// (api.github.com) stay allowed; everything else must be a trusted host.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url,
                  isTrustedDownloadHost(url) || url.host?.lowercased() == "api.github.com" else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }
}
