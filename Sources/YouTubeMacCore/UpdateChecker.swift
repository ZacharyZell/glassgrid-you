import Foundation

/// Parsed semantic version (e.g. `1.0.0`, `v1.2.3`, or `1.2`).
public struct SemanticVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
    }

    public init?(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        // Strip optional build metadata (+...) and prerelease suffix (-...)
        if let plusIndex = trimmed.firstIndex(of: "+") {
            trimmed = String(trimmed[..<plusIndex])
        }
        if let dashIndex = trimmed.firstIndex(of: "-") {
            trimmed = String(trimmed[..<dashIndex])
        }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        guard let major = Int(parts[0]), major >= 0,
              let minor = Int(parts[1]), minor >= 0 else {
            return nil
        }

        let patch: Int
        if parts.count == 3 {
            guard let parsedPatch = Int(parts[2]), parsedPatch >= 0 else { return nil }
            patch = parsedPatch
        } else {
            patch = 0
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Verified metadata for a published GitHub release.
public struct ReleaseInfo: Equatable, Sendable {
    public let tagName: String
    public let version: SemanticVersion
    public let releaseURL: URL
    public let dmgDownloadURL: URL?
    public let releaseNotes: String

    public init(
        tagName: String,
        version: SemanticVersion,
        releaseURL: URL,
        dmgDownloadURL: URL?,
        releaseNotes: String
    ) {
        self.tagName = tagName
        self.version = version
        self.releaseURL = releaseURL
        self.dmgDownloadURL = dmgDownloadURL
        self.releaseNotes = releaseNotes
    }

    /// Direct `.dmg` asset download URL when available, otherwise the GitHub Release page.
    public var preferredDownloadURL: URL {
        dmgDownloadURL ?? releaseURL
    }
}

/// Outcome of a user-initiated update check against GitHub Releases.
public enum ReleaseCheckResult: Equatable, Sendable {
    case upToDate(current: SemanticVersion)
    case updateAvailable(current: SemanticVersion, latest: ReleaseInfo)
    case noReleasesPublished
    case failed(String)
}

/// Zero-dependency, strictly user-initiated GitHub Releases update checker.
/// Never sends cookies, never polls in the background, and validates every returned URL
/// against trusted `https://` GitHub hosts before exposing it to the UI.
public enum UpdateChecker {
    public static let defaultRepository = "ZacharyZell/glassgrid-you"
    public static let releasesPageURL = URL(string: "https://github.com/ZacharyZell/glassgrid-you/releases")!
    public static let sponsorsURL = URL(string: "https://github.com/sponsors/ZacharyZell")!

    private struct GitHubReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }

        let tag_name: String?
        let html_url: String?
        let draft: Bool?
        let prerelease: Bool?
        let body: String?
        let assets: [Asset]?
    }

    /// Validates that a URL is `https://` and hosted on `github.com` or `githubusercontent.com`.
    public static func isTrustedGitHubDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host == "githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }

    /// Pure JSON parser for `/repos/<owner>/<repo>/releases/latest`.
    public static func parseLatestRelease(
        from data: Data,
        currentVersion: SemanticVersion
    ) -> ReleaseCheckResult {
        let payload: GitHubReleasePayload
        do {
            payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        } catch {
            return .failed("Could not parse release information from GitHub.")
        }

        if payload.draft == true || payload.prerelease == true {
            return .noReleasesPublished
        }

        guard let tagName = payload.tag_name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tagName.isEmpty,
              let latestVersion = SemanticVersion(tagName) else {
            return .failed("Latest release tag is not a valid version.")
        }

        guard let htmlString = payload.html_url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let releaseURL = URL(string: htmlString),
              isTrustedGitHubDownloadURL(releaseURL) else {
            return .failed("Release link failed security validation.")
        }

        let dmgURL: URL? = payload.assets?
            .first(where: { asset in
                asset.name.lowercased().hasSuffix(".dmg")
                    && URL(string: asset.browser_download_url).map(isTrustedGitHubDownloadURL) == true
            })
            .flatMap { URL(string: $0.browser_download_url) }

        let notes = (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if latestVersion > currentVersion {
            return .updateAvailable(
                current: currentVersion,
                latest: ReleaseInfo(
                    tagName: tagName,
                    version: latestVersion,
                    releaseURL: releaseURL,
                    dmgDownloadURL: dmgURL,
                    releaseNotes: notes
                )
            )
        }
        return .upToDate(current: currentVersion)
    }

    /// Performs a single cookieless, ephemeral network request to check for a newer release.
    public static func checkLatestRelease(
        currentVersionString: String,
        repository: String = defaultRepository,
        session: URLSession? = nil
    ) async -> ReleaseCheckResult {
        let currentVersion = SemanticVersion(currentVersionString) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
        guard let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return .failed("Invalid release endpoint.")
        }

        let activeSession: URLSession
        let ownsSession: Bool
        if let session {
            activeSession = session
            ownsSession = false
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 12
            activeSession = URLSession(configuration: config)
            ownsSession = true
        }
        defer {
            if ownsSession {
                activeSession.finishTasksAndInvalidate()
            }
        }

        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GlassGridYou/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await activeSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Unexpected response from GitHub.")
            }
            if http.statusCode == 404 {
                return .noReleasesPublished
            }
            guard (200...299).contains(http.statusCode) else {
                return .failed("GitHub returned HTTP \(http.statusCode).")
            }
            return parseLatestRelease(from: data, currentVersion: currentVersion)
        } catch {
            return .failed("Could not reach GitHub. Check your internet connection and try again.")
        }
    }
}
