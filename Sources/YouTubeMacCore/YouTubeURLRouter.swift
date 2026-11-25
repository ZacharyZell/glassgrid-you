import Foundation

/// Controls whether a tab applies strict YouTube routing or allows general HTTPS Companion sites in-app.
public enum TabRoutingMode: String, Codable, Equatable, Hashable, Sendable {
    case youtube
    case companion
}

/// Curated quick-launch streaming & live-score sites for Companion / Mixed-Stream Multiview tiles.
public struct CompanionQuickSite: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let urlString: String
    public let systemImage: String

    public init(id: String, name: String, subtitle: String, urlString: String, systemImage: String) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.urlString = urlString
        self.systemImage = systemImage
    }

    public var url: URL {
        URL(string: urlString)!
    }

    public var routingMode: TabRoutingMode {
        if let host = url.host, YouTubeURLRouter.isYouTubeHost(host) {
            return .youtube
        }
        return .companion
    }

    public static let catalog: [CompanionQuickSite] = [
        CompanionQuickSite(id: "twitch", name: "Twitch", subtitle: "Live Streams", urlString: "https://www.twitch.tv", systemImage: "gamecontroller"),
        CompanionQuickSite(id: "espn", name: "ESPN Scores", subtitle: "Live Scoreboard", urlString: "https://www.espn.com/scoreboard", systemImage: "sportscourt"),
        CompanionQuickSite(id: "nfl", name: "NFL.com", subtitle: "Live Scores", urlString: "https://www.nfl.com/scores/", systemImage: "football"),
        CompanionQuickSite(id: "yttv", name: "YouTube TV", subtitle: "Live TV", urlString: "https://tv.youtube.com", systemImage: "tv"),
        CompanionQuickSite(id: "peacock", name: "Peacock", subtitle: "Live & Sports", urlString: "https://www.peacocktv.com", systemImage: "play.tv"),
        CompanionQuickSite(id: "paramount", name: "Paramount+", subtitle: "CBS & Sports", urlString: "https://www.paramountplus.com", systemImage: "sparkles.tv"),
        CompanionQuickSite(id: "primevideo", name: "Prime Video", subtitle: "Live & TNF", urlString: "https://www.amazon.com/gp/video/storefront", systemImage: "film"),
        CompanionQuickSite(id: "crunchyroll", name: "Crunchyroll", subtitle: "Anime & Simulcasts", urlString: "https://www.crunchyroll.com", systemImage: "play.tv")
    ]
}

/// Outcome for deciding how WebKit should handle a navigation request.
public enum URLRouteDecision: Equatable, Sendable {
    case allowInApp
    case redirectInApp(URL)
    case openExternal(URL)
    case block
}

/// Pure URL routing, Shorts rewriting, and omnibox parsing helpers.
public enum YouTubeURLRouter {
    private static let inAppSchemes: Set<String> = ["about", "data", "blob", "javascript"]
    private static let blockedAppSchemes: Set<String> = [
        "file",
        "glassgridyou", "youtubemac",
        "aiv", "amzn", "amazon", "primevideo", "crunchyroll",
        "disneyplus", "hulu", "hbomax", "max", "nflx", "netflix",
        "peacock", "peacocktv", "pplus", "paramountplus", "cbs", "cbsaa",
        "videos", "com.apple.tv", "appletv", "itmss", "itms",
        "espn", "sportscenter", "twitch", "fubotv", "slingtv"
    ]

    /// Returns true for app-handoff and internal custom schemes that WebKit must never open inside or launch externally.
    public static func isBlockedAppScheme(_ scheme: String) -> Bool {
        blockedAppSchemes.contains(scheme.lowercased())
    }

    /// Returns true strictly for safe web & inline WebKit document schemes (`http`, `https`, `about`, `data`, `blob`, `javascript`).
    public static func isAllowedWebScheme(_ scheme: String) -> Bool {
        let lower = scheme.lowercased()
        return lower == "http" || lower == "https" || inAppSchemes.contains(lower)
    }

    private static let fixedGoogleAuthHosts: Set<String> = [
        "accounts.youtube.com",
        "myaccount.google.com",
        "consent.youtube.com",
        "consent.google.com",
        "gds.google.com",
        "ogs.google.com",
        "gsuite.google.com",
        "workspace.google.com",
        "passwords.google.com"
    ]

    /// Returns true for YouTube primary, shortener, and embed domains.
    public static func isYouTubeHost(_ host: String) -> Bool {
        let lower = normalizedHost(host)
        return matchesDomain(lower, root: "youtube.com")
            || matchesDomain(lower, root: "youtu.be")
            || matchesDomain(lower, root: "youtube-nocookie.com")
    }

    /// Returns true specifically for `tv.youtube.com` (YouTube TV).
    public static func isYouTubeTVHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return normalizedHost(host) == "tv.youtube.com"
    }

    /// Returns true for standard YouTube (`youtube.com`, `youtu.be`, `youtube-nocookie.com`) excluding `tv.youtube.com`.
    public static func isStandardYouTubeHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return isYouTubeHost(host) && !isYouTubeTVHost(host)
    }

    /// Infers the appropriate `TabRoutingMode` for a destination URL.
    public static func preferredRoutingMode(for url: URL) -> TabRoutingMode {
        if let host = url.host, isYouTubeHost(host) || isGoogleAuthHost(host) {
            return .youtube
        }
        return .companion
    }

    /// Resolves a user-entered website or URL (e.g. `twitch.tv/nfl`, `https://espn.com/scoreboard`) into a safe `http(s)` URL.
    /// Rejects dangerous or non-web schemes (`javascript:`, `file:`, `data:`, etc.).
    public static func resolveCompanionURL(_ rawInput: String) -> URL? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(" "),
              !trimmed.contains("\n"),
              !trimmed.contains("\t") else {
            return nil
        }

        let candidateString: String
        if trimmed.contains("://") {
            candidateString = trimmed
        } else {
            // Reject explicit non-HTTP schemes like `javascript:alert(1)`, `file:/etc/passwd`, `mailto:a@b.com`.
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let beforeColon = trimmed[..<colonIndex]
                let afterColon = trimmed[trimmed.index(after: colonIndex)...]
                let isPortNumber = !afterColon.isEmpty && afterColon.prefix(while: { $0 != "/" }).allSatisfy(\.isNumber)
                if !isPortNumber && !beforeColon.contains(".") && !beforeColon.contains("/") {
                    return nil
                }
            }
            candidateString = "https://" + trimmed
        }

        guard let parsed = URL(string: candidateString),
              let scheme = parsed.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = parsed.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        // Require a valid public-looking domain (dot-separated labels) or localhost.
        if host != "localhost" {
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.count >= 2,
                  labels.allSatisfy({ !$0.isEmpty }),
                  let tld = labels.last,
                  tld.count >= 2,
                  tld.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
                return nil
            }
        }

        return parsed
    }

    /// Returns a semantic SF Symbol name for a pinned YouTube, YouTube TV, or Companion destination URL.
    public static func pinnedItemIcon(for urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "pin.fill" }
        if isYouTubeTVHost(url.host) {
            return "tv"
        }
        if let host = url.host, !isYouTubeHost(host) {
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "http" || scheme == "https" {
                return "globe"
            }
        }
        let path = url.path.lowercased()
        if path.hasPrefix("/playlist") {
            return "list.bullet.rectangle"
        }
        if path.hasPrefix("/@")
            || path.hasPrefix("/channel/")
            || path.hasPrefix("/c/")
            || path.hasPrefix("/user/") {
            return "person.crop.circle"
        }
        if isWatchURL(url) {
            return "play.rectangle"
        }
        return "pin.fill"
    }

    /// Returns true when `url` is an active video/live playback watch URL on either `youtube.com` or `tv.youtube.com`.
    /// Note: `tv.youtube.com/live` is the Live TV EPG Guide (not a watch page); YTTV streams use `/watch/<id>`.
    public static func isWatchURL(_ url: URL) -> Bool {
        guard let host = url.host, isYouTubeHost(host) else {
            return false
        }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)
        if isYouTubeTVHost(host) {
            return segments.count >= 2 && segments[0].lowercased() == "watch"
        }
        if matchesDomain(normalizedHost(host), root: "youtu.be") {
            return !segments.isEmpty
        }
        guard let first = segments.first?.lowercased() else {
            return false
        }
        if first == "watch" {
            return true
        }
        if first == "live" && segments.count >= 2 {
            return true
        }
        return false
    }

    /// Returns true for Google / YouTube authentication, consent, and account hosts.
    public static func isGoogleAuthHost(_ host: String) -> Bool {
        let lower = normalizedHost(host)
        if fixedGoogleAuthHosts.contains(lower) {
            return true
        }
        // Handle accounts.google.com as well as regional ccTLDs such as accounts.google.co.uk.
        return lower == "accounts.google.com" || lower.hasPrefix("accounts.google.")
    }

    /// Extracts the real destination URL from `youtube.com/redirect?q=...` wrappers.
    public static func unwrapYouTubeRedirect(_ url: URL) -> URL? {
        guard let host = url.host, isYouTubeHost(host) else {
            return nil
        }
        guard url.path.lowercased() == "/redirect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?.first(where: { $0.name == "q" })?.value,
              let parsed = URL(string: target),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return parsed
    }

    /// Rewrites `/shorts/<id>` URLs into standard `/watch?v=<id>` URLs while keeping safe parameters like `t`.
    public static func rewriteShortsURL(_ url: URL) -> URL? {
        guard let host = url.host, isYouTubeHost(host) else {
            return nil
        }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count >= 2,
              segments[0].lowercased() == "shorts" else {
            return nil
        }
        let videoID = String(segments[1])
        guard !videoID.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"

        var queryItems = [URLQueryItem(name: "v", value: videoID)]
        if let existing = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            let safeNames: Set<String> = ["t", "start", "list", "index"]
            for item in existing where safeNames.contains(item.name) {
                queryItems.append(item)
            }
        }
        components.queryItems = queryItems
        return components.url
    }

    /// Decides whether a navigation stays inside WebKit, rewrites in-app, or opens in the default browser.
    public static func routeNavigation(
        url: URL,
        currentPageURL: URL?,
        isUserLinkClick: Bool,
        openExternalLinksInBrowser: Bool,
        redirectShortsToWatch: Bool,
        routingMode: TabRoutingMode = .youtube
    ) -> URLRouteDecision {
        let scheme = url.scheme?.lowercased() ?? ""
        if isBlockedAppScheme(scheme) {
            return .block
        }
        if inAppSchemes.contains(scheme) {
            return .allowInApp
        }

        if scheme != "http" && scheme != "https" {
            return isUserLinkClick ? .openExternal(url) : .block
        }

        // Companion web tabs allow all HTTP/HTTPS navigations (same-site browsing & third-party OAuth/SSO) in-app.
        if routingMode == .companion {
            if redirectShortsToWatch, let rewritten = rewriteShortsURL(url) {
                return .redirectInApp(rewritten)
            }
            return .allowInApp
        }

        if redirectShortsToWatch, let rewritten = rewriteShortsURL(url) {
            return .redirectInApp(rewritten)
        }

        if let unwrapped = unwrapYouTubeRedirect(url) {
            if openExternalLinksInBrowser,
               let targetHost = unwrapped.host,
               !isYouTubeHost(targetHost),
               !isGoogleAuthHost(targetHost) {
                return .openExternal(unwrapped)
            }
            return .redirectInApp(unwrapped)
        }

        // Preserve non-link navigations (OAuth/SAML redirects, 2FA callbacks, embed frames).
        if !isUserLinkClick {
            return .allowInApp
        }

        if let host = url.host {
            if isYouTubeHost(host) || isGoogleAuthHost(host) {
                return .allowInApp
            }
        }

        // Preserve links clicked inside an active Google Auth / SSO page (help, passkeys, SSO).
        if let currentHost = currentPageURL?.host, isGoogleAuthHost(currentHost) {
            return .allowInApp
        }

        return openExternalLinksInBrowser ? .openExternal(url) : .allowInApp
    }

    /// Resolves omnibox input into a direct YouTube URL or a YouTube search query URL.
    public static func resolveOmniboxInput(_ rawInput: String, redirectShortsToWatch: Bool) -> URL? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let directURL = parseCandidateYouTubeURL(trimmed) {
            if redirectShortsToWatch, let rewritten = rewriteShortsURL(directURL) {
                return rewritten
            }
            return directURL
        }

        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: trimmed)]
        return components.url
    }

    /// Extracts a valid YouTube URL from clipboard text if present.
    public static func extractYouTubeURLFromString(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else {
            return nil
        }
        return parseCandidateYouTubeURL(trimmed)
    }

    /// Converts custom `glassgridyou://` (and legacy `youtubemac://`) deep links into HTTPS YouTube URLs.
    public static func resolveCustomSchemeURL(_ url: URL) -> URL? {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            if let host = url.host, isYouTubeHost(host) {
                return url
            }
            return nil
        }

        guard let scheme = url.scheme?.lowercased(),
              scheme == "glassgridyou" || scheme == "youtubemac" else {
            return nil
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"

        let rawHost = components.host?.lowercased() ?? ""
        if rawHost.isEmpty {
            components.host = "www.youtube.com"
        } else if !isYouTubeHost(rawHost) {
            // Treat e.g. `youtubemac://watch?v=123` as path `/watch?v=123` on `www.youtube.com`.
            let originalPath = components.path
            components.host = "www.youtube.com"
            components.path = "/" + rawHost + originalPath
        }
        return components.url
    }

    /// Extracts a YouTube or YouTube TV video ID from watch, shortener, Shorts, live, or embed URLs.
    /// Explicitly returns `nil` for `tv.youtube.com/live` (Live TV EPG Guide).
    public static func extractVideoID(from url: URL) -> String? {
        guard let host = url.host, isYouTubeHost(host) else {
            return nil
        }

        let lowerHost = normalizedHost(host)
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)

        let candidate: String?
        if isYouTubeTVHost(host) {
            if segments.count >= 2 && segments[0].lowercased() == "watch" {
                candidate = String(segments[1])
            } else {
                candidate = nil
            }
        } else if matchesDomain(lowerHost, root: "youtu.be") {
            candidate = segments.first.map(String.init)
        } else if segments.first?.lowercased() == "watch" {
            if let queryV = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value {
                candidate = queryV
            } else if segments.count >= 2 {
                candidate = String(segments[1])
            } else {
                candidate = nil
            }
        } else if segments.count >= 2,
                  let prefix = segments.first?.lowercased(),
                  prefix == "shorts" || prefix == "embed" || prefix == "live" {
            candidate = String(segments[1])
        } else {
            candidate = nil
        }

        guard let id = candidate, isValidVideoID(id) else {
            return nil
        }
        return id
    }

    /// Returns a copy of a YouTube video URL annotated with `&t=<seconds>s` (or replaces any existing `t` parameter).
    public static func urlWithTimestamp(_ url: URL, seconds: Double) -> URL {
        guard extractVideoID(from: url) != nil,
              seconds.isFinite,
              seconds >= 1,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let wholeSeconds = Int(seconds.rounded(.down))
        var items = (components.queryItems ?? []).filter { $0.name != "t" && $0.name != "start" }
        items.append(URLQueryItem(name: "t", value: "\(wholeSeconds)s"))
        components.queryItems = items
        return components.url ?? url
    }

    private static func isValidVideoID(_ id: String) -> Bool {
        guard id.count >= 6 && id.count <= 20 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) // 0-9
                || (scalar.value >= 65 && scalar.value <= 90) // A-Z
                || (scalar.value >= 97 && scalar.value <= 122) // a-z
                || scalar == "-" || scalar == "_"
        }
    }

    private static func parseCandidateYouTubeURL(_ input: String) -> URL? {
        guard !input.contains(" ") else {
            return nil
        }

        if let parsed = URL(string: input),
           let scheme = parsed.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           let host = parsed.host,
           isYouTubeHost(host) {
            return parsed
        }

        if !input.contains("://"),
           let parsed = URL(string: "https://" + input),
           let host = parsed.host,
           isYouTubeHost(host) {
            return parsed
        }

        return nil
    }

    private static func normalizedHost(_ host: String) -> String {
        var lower = host.lowercased()
        if lower.hasSuffix(".") {
            lower.removeLast()
        }
        return lower
    }

    private static func matchesDomain(_ host: String, root: String) -> Bool {
        host == root || host.hasSuffix("." + root)
    }
}
