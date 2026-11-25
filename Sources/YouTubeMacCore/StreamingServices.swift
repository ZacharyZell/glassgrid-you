import Foundation

/// Top-level grouping for streaming services in the Onboarding Intro and Add Screen Service Picker.
public enum StreamingServiceCategory: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case videoAndLiveTV
    case moviesAndShows
    case liveSports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .videoAndLiveTV: return "Video & Live TV"
        case .moviesAndShows: return "Movies & Shows"
        case .liveSports: return "Live Sports"
        }
    }

    public var systemImage: String {
        switch self {
        case .videoAndLiveTV: return "tv.inset.filled"
        case .moviesAndShows: return "film.stack"
        case .liveSports: return "sportscourt.fill"
        }
    }
}

/// Canonical descriptor for a streaming service supported by GlassGrid You.
/// Uses strictly IP-safe native SF Symbols and monogram color gradients (never scraped third-party trademark logos).
public struct StreamingService: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let category: StreamingServiceCategory
    public let homeURLString: String
    public let signInURLString: String
    /// Registrable eTLD+1 domains matched strictly against `WKWebsiteDataRecord.displayName` and `HTTPCookie.domain`.
    public let dataDomains: [String]
    /// Additional auth/OAuth host hints allowed during embedded sign-in flows.
    public let authHostHints: [String]
    public let routingMode: TabRoutingMode
    /// `true` when the provider frequently enforces Safari-only Verified Media Path / FairPlay CDM checks in third-party `WKWebView`.
    public let requiresStrictDRM: Bool
    public let symbolName: String
    public let monogram: String?
    public let accentHexStart: String
    public let accentHexEnd: String

    public init(
        id: String,
        name: String,
        subtitle: String,
        category: StreamingServiceCategory,
        homeURLString: String,
        signInURLString: String,
        dataDomains: [String],
        authHostHints: [String] = [],
        routingMode: TabRoutingMode,
        requiresStrictDRM: Bool = false,
        symbolName: String,
        monogram: String? = nil,
        accentHexStart: String,
        accentHexEnd: String
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.category = category
        self.homeURLString = homeURLString
        self.signInURLString = signInURLString
        self.dataDomains = dataDomains
        self.authHostHints = authHostHints
        self.routingMode = routingMode
        self.requiresStrictDRM = requiresStrictDRM
        self.symbolName = symbolName
        self.monogram = monogram
        self.accentHexStart = accentHexStart
        self.accentHexEnd = accentHexEnd
    }

    public var homeURL: URL {
        URL(string: homeURLString) ?? SidebarDestination.home.url
    }

    public var signInURL: URL {
        URL(string: signInURLString) ?? homeURL
    }
}

/// Single source of truth for GlassGrid You's 18 built-in streaming services,
/// per-service site-data domain isolation, and passive sign-in navigation heuristics.
public enum StreamingServiceCatalog {
    public static let defaultEnabledServiceIDs: [String] = ["youtube"]

    /// Explicit allowlist of canonical Amazon retail domains for Prime Video resolution (prevents substring spoofing).
    public static let amazonRetailDomains: Set<String> = [
        "amazon.com", "amazon.co.uk", "amazon.de", "amazon.co.jp", "amazon.ca",
        "amazon.fr", "amazon.it", "amazon.es", "amazon.com.au", "amazon.in",
        "amazon.com.br", "amazon.com.mx", "amazon.nl", "amazon.se", "amazon.pl",
        "amazon.sg", "amazon.ae", "amazon.sa",
        "amazon.com.tr", "amazon.com.be", "amazon.ie", "amazon.eg", "amazon.co.za"
    ]

    /// Shared third-party SSO / IdP hosts used across multiple streaming services.
    public static let sharedThirdPartySSOHosts: Set<String> = [
        "accounts.google.com", "accounts.youtube.com",
        "idmsa.apple.com", "appleid.apple.com",
        "sp.auth.adobe.com", "registerdisney.go.com", "cdn.registerdisney.go.com",
        "my.disney.com"
    ]

    /// Host prefixes belonging exclusively to authentication, SSO, or identity subdomains.
    public static let authHostPrefixes: [String] = [
        "auth.", "sso.", "login.", "signin.", "sign-in.",
        "id.", "ids.", "identity.", "passport.", "accounts.", "oauth."
    ]

    public static let iso639LocaleCodes: [String] = [
        "ar", "cs", "da", "de", "el", "en", "es", "fi", "fr", "he",
        "hi", "hu", "id", "it", "ja", "ko", "nb", "nl", "no", "pl",
        "pt", "ro", "ru", "sv", "th", "tr", "uk", "vi", "zh"
    ]

    private static let iso639LocaleCodeSet: Set<String> = Set(iso639LocaleCodes)

    /// Explicit two-letter regional storefronts used by streaming SPAs (`netflix.com/us/login`, `/gb/watch/...`).
    /// Deliberately excludes non-country route roots like `ap`, `ax`, `gp`, `tv`, `v1`, `v2`, `p`.
    public static let regionLocalePrefixes: [String] = [
        "au", "br", "ca", "gb", "jp", "kr", "mx", "uk", "us"
    ]

    private static let regionLocalePrefixSet: Set<String> = Set(regionLocalePrefixes)

    /// All 18 major streaming services grouped across Video & Live TV, Movies & Shows, and Live Sports.
    public static let all: [StreamingService] = [
        // MARK: - Video & Live TV (Tier 1 Native WKWebView)
        StreamingService(
            id: "youtube",
            name: "YouTube",
            subtitle: "4K HDR videos & live streams",
            category: .videoAndLiveTV,
            homeURLString: "https://www.youtube.com/",
            signInURLString: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/",
            dataDomains: ["youtube.com", "google.com", "googleusercontent.com"],
            authHostHints: ["accounts.google.com", "accounts.youtube.com"],
            routingMode: .youtube,
            requiresStrictDRM: false,
            symbolName: "play.rectangle.fill",
            monogram: nil,
            accentHexStart: "#B9141C",
            accentHexEnd: "#FF363D"
        ),
        StreamingService(
            id: "yttv",
            name: "YouTube TV",
            subtitle: "Live TV & FairPlay DRM sports",
            category: .videoAndLiveTV,
            homeURLString: "https://tv.youtube.com/",
            signInURLString: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://tv.youtube.com/",
            dataDomains: ["tv.youtube.com", "youtube.com", "google.com"],
            authHostHints: ["accounts.google.com", "accounts.youtube.com"],
            routingMode: .youtube,
            requiresStrictDRM: false,
            symbolName: "tv.fill",
            monogram: "TV",
            accentHexStart: "#9E1118",
            accentHexEnd: "#E6242D"
        ),
        StreamingService(
            id: "twitch",
            name: "Twitch",
            subtitle: "Live gaming, IRL & esports",
            category: .videoAndLiveTV,
            homeURLString: "https://www.twitch.tv/",
            signInURLString: "https://www.twitch.tv/login",
            dataDomains: ["twitch.tv", "ttvnw.net"],
            authHostHints: ["passport.twitch.tv", "id.twitch.tv", "accounts.google.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "gamecontroller.fill",
            monogram: "TW",
            accentHexStart: "#5E2FD4",
            accentHexEnd: "#9146FF"
        ),
        StreamingService(
            id: "fubo",
            name: "Fubo",
            subtitle: "Live sports & cable channels",
            category: .videoAndLiveTV,
            homeURLString: "https://www.fubo.tv/welcome",
            signInURLString: "https://www.fubo.tv/signin",
            dataDomains: ["fubo.tv"],
            authHostHints: ["accounts.google.com", "appleid.apple.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "antenna.radiowaves.left.and.right",
            monogram: "FB",
            accentHexStart: "#C94715",
            accentHexEnd: "#FF6B2B"
        ),
        StreamingService(
            id: "sling",
            name: "Sling TV",
            subtitle: "Live cable & news channels",
            category: .videoAndLiveTV,
            homeURLString: "https://watch.sling.com/",
            signInURLString: "https://watch.sling.com/",
            dataDomains: ["sling.com", "dish.com"],
            authHostHints: ["identity.sling.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "tv.and.mediabox",
            monogram: "SL",
            accentHexStart: "#0069B4",
            accentHexEnd: "#00A3E0"
        ),

        // MARK: - Live Sports (Tier 1 Native WKWebView)
        StreamingService(
            id: "espn",
            name: "ESPN / ESPN+",
            subtitle: "Live games, scores & ESPN+",
            category: .liveSports,
            homeURLString: "https://www.espn.com/watch/",
            signInURLString: "https://www.espn.com/watch/",
            dataDomains: ["espn.com", "espn.go.com", "go.com", "disney.com", "adobe.com"],
            authHostHints: ["sp.auth.adobe.com", "registerdisney.go.com", "cdn.registerdisney.go.com", "my.disney.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "sportscourt.fill",
            monogram: "ES",
            accentHexStart: "#A80F17",
            accentHexEnd: "#E5252C"
        ),
        StreamingService(
            id: "nfl",
            name: "NFL+",
            subtitle: "Live games, RedZone & replays",
            category: .liveSports,
            homeURLString: "https://www.nfl.com/plus/",
            signInURLString: "https://id.nfl.com/",
            dataDomains: ["nfl.com", "adobe.com"],
            authHostHints: ["id.nfl.com", "sp.auth.adobe.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "football.fill",
            monogram: "NFL",
            accentHexStart: "#0B2963",
            accentHexEnd: "#1F56B5"
        ),
        StreamingService(
            id: "mlb",
            name: "MLB.TV",
            subtitle: "Out-of-market live baseball",
            category: .liveSports,
            homeURLString: "https://www.mlb.com/tv",
            signInURLString: "https://www.mlb.com/login",
            dataDomains: ["mlb.com", "mlbstatic.com"],
            authHostHints: ["ids.mlb.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "baseball.fill",
            monogram: "MLB",
            accentHexStart: "#0A2351",
            accentHexEnd: "#C41E3A"
        ),
        StreamingService(
            id: "nba",
            name: "NBA League Pass",
            subtitle: "Live basketball & multi-game",
            category: .liveSports,
            homeURLString: "https://www.nba.com/watch",
            signInURLString: "https://www.nba.com/account/sign-in",
            dataDomains: ["nba.com"],
            authHostHints: ["identity.nba.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "basketball.fill",
            monogram: "NBA",
            accentHexStart: "#17408B",
            accentHexEnd: "#C9082A"
        ),

        // MARK: - Movies & Shows (Peacock & Paramount+ Tier 1; 6 Strict-DRM SVODs Tier 2)
        StreamingService(
            id: "peacock",
            name: "Peacock",
            subtitle: "NBC live sports, shows & films",
            category: .moviesAndShows,
            homeURLString: "https://www.peacocktv.com/watch/home",
            signInURLString: "https://www.peacocktv.com/signin",
            dataDomains: ["peacocktv.com", "nbcuni.com"],
            authHostHints: ["id.peacocktv.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "sparkles.tv.fill",
            monogram: "PK",
            accentHexStart: "#1D1F29",
            accentHexEnd: "#F5B800"
        ),
        StreamingService(
            id: "paramount",
            name: "Paramount+",
            subtitle: "CBS Sports, NFL & originals",
            category: .moviesAndShows,
            homeURLString: "https://www.paramountplus.com/home/",
            signInURLString: "https://www.paramountplus.com/account/signin/",
            dataDomains: ["paramountplus.com", "cbs.com", "cbsi.com"],
            authHostHints: ["sp.auth.adobe.com"],
            routingMode: .companion,
            requiresStrictDRM: false,
            symbolName: "mountain.2.fill",
            monogram: "P+",
            accentHexStart: "#003B99",
            accentHexEnd: "#0064FF"
        ),
        StreamingService(
            id: "primevideo",
            name: "Prime Video",
            subtitle: "TNF, originals & live channels",
            category: .moviesAndShows,
            homeURLString: "https://www.amazon.com/gp/video/storefront",
            signInURLString: "https://www.amazon.com/ap/signin?openid.pape.max_auth_age=0&openid.return_to=https%3A%2F%2Fwww.amazon.com%2Fgp%2Fvideo%2Fstorefront&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.assoc_handle=usflex&openid.mode=checkid_setup&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0",
            dataDomains: ["amazon.com", "primevideo.com"],
            authHostHints: ["na.account.amazon.com", "eu.account.amazon.com", "fe.account.amazon.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "play.square.stack.fill",
            monogram: "PV",
            accentHexStart: "#0A4F7A",
            accentHexEnd: "#00A8E1"
        ),
        StreamingService(
            id: "disneyplus",
            name: "Disney+",
            subtitle: "Disney, Pixar, Marvel & Star Wars",
            category: .moviesAndShows,
            homeURLString: "https://www.disneyplus.com/home",
            signInURLString: "https://www.disneyplus.com/login",
            dataDomains: ["disneyplus.com", "disney.com", "bamgrid.com", "dssott.com", "registerdisney.go.com"],
            authHostHints: ["registerdisney.go.com", "cdn.registerdisney.go.com", "my.disney.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "wand.and.stars",
            monogram: "D+",
            accentHexStart: "#0A1D56",
            accentHexEnd: "#1E66F5"
        ),
        StreamingService(
            id: "hulu",
            name: "Hulu",
            subtitle: "Live TV, FX & on-demand series",
            category: .moviesAndShows,
            homeURLString: "https://www.hulu.com/hub/home",
            signInURLString: "https://auth.hulu.com/web/login",
            dataDomains: ["hulu.com", "disney.com", "bamgrid.com", "registerdisney.go.com"],
            authHostHints: ["auth.hulu.com", "registerdisney.go.com", "cdn.registerdisney.go.com", "my.disney.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "rectangle.stack.fill",
            monogram: "HU",
            accentHexStart: "#0C6E42",
            accentHexEnd: "#1CE783"
        ),
        StreamingService(
            id: "max",
            name: "HBO Max",
            subtitle: "HBO, TNT Sports & Warner Bros.",
            category: .moviesAndShows,
            homeURLString: "https://play.hbomax.com/",
            signInURLString: "https://www.hbomax.com/auth/login",
            dataDomains: ["hbomax.com", "max.com", "wbd.com"],
            authHostHints: ["auth.hbomax.com", "auth.max.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "film.fill",
            monogram: "HBO",
            accentHexStart: "#0F1D73",
            accentHexEnd: "#415CF5"
        ),
        StreamingService(
            id: "appletv",
            name: "Apple TV+",
            subtitle: "Apple Originals, MLS & Friday MLB",
            category: .moviesAndShows,
            homeURLString: "https://tv.apple.com/",
            signInURLString: "https://tv.apple.com/",
            dataDomains: ["tv.apple.com", "apple.com", "icloud.com"],
            authHostHints: ["idmsa.apple.com", "appleid.apple.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "appletv.fill",
            monogram: "TV+",
            accentHexStart: "#262629",
            accentHexEnd: "#5A5A62"
        ),
        StreamingService(
            id: "netflix",
            name: "Netflix",
            subtitle: "Series, films & live events",
            category: .moviesAndShows,
            homeURLString: "https://www.netflix.com/browse",
            signInURLString: "https://www.netflix.com/login",
            dataDomains: ["netflix.com", "nflxso.net"],
            authHostHints: [],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "popcorn.fill",
            monogram: "N",
            accentHexStart: "#8C0910",
            accentHexEnd: "#E50914"
        ),
        StreamingService(
            id: "crunchyroll",
            name: "Crunchyroll",
            subtitle: "Anime series, simulcasts & films",
            category: .moviesAndShows,
            homeURLString: "https://www.crunchyroll.com/",
            signInURLString: "https://www.crunchyroll.com/login",
            dataDomains: ["crunchyroll.com", "crunchyrollsvc.com", "vrv.co"],
            authHostHints: ["sso.crunchyroll.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "play.tv.fill",
            monogram: "CR",
            accentHexStart: "#C24600",
            accentHexEnd: "#F47521"
        )
    ]

    /// Union of dedicated auth/SSO hosts declared across the catalog and third-party SSO providers.
    public static var dedicatedAuthHosts: Set<String> {
        var hosts = sharedThirdPartySSOHosts
        for svc in all {
            for hint in svc.authHostHints {
                let clean = normalizeDomain(hint)
                if !clean.isEmpty {
                    hosts.insert(clean)
                }
            }
        }
        return hosts
    }

    public static func service(id: String) -> StreamingService? {
        all.first { $0.id == id }
    }

    private static let serviceAliases: [String: String] = [
        "hbomax": "max",
        "hbo-max": "max",
        "hbo_max": "max",
        "hbo max": "max",
        "hbo": "max",
        "disney+": "disneyplus",
        "disney-plus": "disneyplus",
        "disney_plus": "disneyplus",
        "disney plus": "disneyplus",
        "disney": "disneyplus",
        "paramount+": "paramount",
        "paramount-plus": "paramount",
        "paramount_plus": "paramount",
        "paramount plus": "paramount",
        "appletv+": "appletv",
        "apple-tv": "appletv",
        "apple-tv+": "appletv",
        "apple_tv": "appletv",
        "apple tv": "appletv",
        "apple tv+": "appletv",
        "appletvplus": "appletv",
        "prime": "primevideo",
        "prime-video": "primevideo",
        "prime_video": "primevideo",
        "prime video": "primevideo",
        "amazon": "primevideo",
        "youtube-tv": "yttv",
        "youtube_tv": "yttv",
        "youtube tv": "yttv",
        "youtubetv": "yttv",
        "espn+": "espn",
        "espn-plus": "espn",
        "espn_plus": "espn",
        "espn plus": "espn",
        "nfl+": "nfl",
        "nfl-plus": "nfl",
        "nfl_plus": "nfl",
        "nfl plus": "nfl",
        "mlb.tv": "mlb",
        "mlbtv": "mlb",
        "mlb tv": "mlb",
        "peacocktv": "peacock",
        "peacock tv": "peacock"
    ]

    /// Resolves a canonical service ID or common user/AI alias (e.g. `hbomax`, `disney+`, `apple tv+`, `prime`).
    public static func resolveService(identifierOrAlias raw: String) -> StreamingService? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let exact = service(id: trimmed) {
            return exact
        }
        if let mapped = serviceAliases[trimmed] {
            return service(id: mapped)
        }
        return nil
    }

    private static let nonExclusiveServiceMatchingDomains: Set<String> = [
        "google.com", "disney.com", "adobe.com", "go.com", "registerdisney.go.com",
        "apple.com", "icloud.com", "cbs.com", "cbsi.com", "nbcuni.com",
        "wbd.com", "dish.com", "bamgrid.com", "dssott.com"
    ]

    public static func services(in category: StreamingServiceCategory) -> [StreamingService] {
        all.filter { $0.category == category }
    }

    /// Resolves enabled service IDs in canonical catalog order, falling back to `["youtube"]` if empty/unknown.
    public static func resolvedEnabledServices(from ids: [String]) -> [StreamingService] {
        let validSet = Set(ids)
        let ordered = all.filter { validSet.contains($0.id) }
        return ordered.isEmpty ? all.filter { defaultEnabledServiceIDs.contains($0.id) } : ordered
    }

    /// Finds the canonical streaming service matching a URL's host (preferring `tv.youtube.com` before `youtube.com`).
    public static func service(matchingURL url: URL?) -> StreamingService? {
        guard let rawHost = url?.host, !rawHost.isEmpty else { return nil }
        let host = normalizeDomain(rawHost)
        guard !host.isEmpty else { return nil }
        if host == "tv.youtube.com" {
            return service(id: "yttv")
        }
        if YouTubeURLRouter.isYouTubeHost(host) {
            return service(id: "youtube")
        }
        if isAmazonOrPrimeVideoHost(host) {
            return service(id: "primevideo")
        }
        for svc in all where svc.id != "youtube" && svc.id != "yttv" && svc.id != "primevideo" {
            if let homeHost = svc.homeURL.host.map(normalizeDomain),
               host == homeHost || host.hasSuffix("." + homeHost) {
                return svc
            }
            for domain in svc.dataDomains where !nonExclusiveServiceMatchingDomains.contains(domain) {
                let clean = normalizeDomain(domain)
                if host == clean || host.hasSuffix("." + clean) {
                    return svc
                }
            }
        }
        return nil
    }

    /// Strict exact/subdomain check against canonical Amazon retail storefronts and `primevideo.com`.
    public static func isAmazonOrPrimeVideoHost(_ host: String) -> Bool {
        let lower = normalizeDomain(host)
        guard !lower.isEmpty else { return false }
        if lower == "primevideo.com" || lower.hasSuffix(".primevideo.com") {
            return true
        }
        return amazonRetailDomains.contains { lower == $0 || lower.hasSuffix("." + $0) }
    }

    /// Returns true if `host` is a shared multi-provider SSO domain (Google, Apple, Adobe Pass, MyDisney).
    public static func isSharedThirdPartySSOHost(_ host: String) -> Bool {
        let lower = normalizeDomain(host)
        guard !lower.isEmpty else { return false }
        if YouTubeURLRouter.isGoogleAuthHost(lower) {
            return true
        }
        return sharedThirdPartySSOHosts.contains { lower == $0 || lower.hasSuffix("." + $0) }
    }

    /// Returns true when `host` belongs to a dedicated authentication/SSO/IdP endpoint.
    public static func isDedicatedAuthHost(_ host: String) -> Bool {
        let lower = normalizeDomain(host)
        guard !lower.isEmpty else { return false }
        if YouTubeURLRouter.isGoogleAuthHost(lower) {
            return true
        }
        if dedicatedAuthHosts.contains(where: { lower == $0 || lower.hasSuffix("." + $0) }) {
            return true
        }
        return authHostPrefixes.contains { lower.hasPrefix($0) }
    }

    /// Strips optional web file extensions (`.html`, `.htm`, `.php`, `.aspx`) before matching auth/logout tokens.
    public static func stripOptionalWebExtension(_ segment: String) -> String {
        let lower = segment.lowercased()
        for ext in [".html", ".htm", ".php", ".aspx"] where lower.hasSuffix(ext) {
            return String(lower.dropLast(ext.count))
        }
        return lower
    }

    /// Strips a single leading ISO-639-1 (`en`, `es`, `pt`, ...) or BCP-47 (`es-es`, `pt-br`, `es-419`) locale path segment.
    /// Restricts strictly to an explicit language allowlist so 2-letter route roots (`ap`, `ax`, `gp`) are never stripped.
    public static func stripLeadingLocaleSegment(_ segments: [String]) -> ArraySlice<String> {
        guard let first = segments.first?.lowercased(), !first.isEmpty else {
            return segments[...]
        }
        if iso639LocaleCodeSet.contains(first) || regionLocalePrefixSet.contains(first) {
            return segments.dropFirst()
        }
        let parts = first.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2 {
            let lang = String(parts[0])
            let region = String(parts[1])
            let isRegionLetters = region.count == 2 && region.unicodeScalars.allSatisfy { $0.value >= 97 && $0.value <= 122 }
            let isRegionDigits = region.count == 3 && region.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
            if (iso639LocaleCodeSet.contains(lang) || regionLocalePrefixSet.contains(lang)) && (isRegionLetters || isRegionDigits) {
                return segments.dropFirst()
            }
        }
        return segments[...]
    }

    /// Returns true when `url` is a transient authentication, OAuth, OpenID, MFA/CVF, or logout step
    /// that must not be treated as a signed-in landing page or persisted in session restoration.
    public static func isTransientAuthURL(_ url: URL) -> Bool {
        guard let rawHost = url.host, !rawHost.isEmpty else { return false }
        let host = normalizeDomain(rawHost)
        if isDedicatedAuthHost(host) {
            return true
        }

        let standardizedPath = url.standardized.path.lowercased()
        let rawSegments = standardizedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let normSegments = rawSegments.map(stripOptionalWebExtension)

        if isAmazonOrPrimeVideoHost(host) {
            let amzSegs = stripAmazonRegionPrefix(normSegments)
            if let first = amzSegs.first, first == "ap" || first == "ax" {
                return true
            }
            if amzSegs.count >= 3 && amzSegs[0] == "gp" && amzSegs[1] == "video" && (amzSegs[2] == "auth" || amzSegs[2] == "splash") {
                return true
            }
            if amzSegs.count >= 2 && amzSegs[0] == "gp" && amzSegs[1] == "sign-in" {
                return true
            }
            if amzSegs.contains("auth-redirect") {
                return true
            }
            if amzSegs.contains(where: { ["signin", "sign-in", "sign_in", "signout", "sign-out"].contains($0) }) {
                return true
            }
        }

        let authTokens: Set<String> = [
            "signin", "sign-in", "sign_in", "oauth", "oauth2",
            "authorize", "servicelogin", "auth-redirect", "mfa", "cvf", "captcha",
            "register", "reset-password", "signout", "sign-out", "logout", "log-out"
        ]
        if normSegments.contains(where: { authTokens.contains($0) }) {
            return true
        }

        let afterLocale = Array(stripLeadingLocaleSegment(normSegments))
        if afterLocale.first == "login" {
            return true
        }
        if afterLocale.count >= 2,
           ["web", "account", "accounts", "auth", "sso", "user", "identity"].contains(afterLocale[0]),
           afterLocale[1] == "login" {
            return true
        }
        if (host == "disneyplus.com" || host.hasSuffix(".disneyplus.com")) && afterLocale.first == "identity" {
            return true
        }
        if (host == "hbomax.com" || host.hasSuffix(".hbomax.com") || host == "max.com" || host.hasSuffix(".max.com")) && afterLocale.first == "auth" {
            return true
        }

        for i in 0..<max(0, normSegments.count - 1) {
            let pair = (normSegments[i], normSegments[i + 1])
            if pair == ("oauth", "callback")
                || pair == ("oauth2", "callback")
                || pair == ("auth", "callback")
                || pair == ("sso", "callback")
                || pair == ("auth", "return") {
                return true
            }
        }

        if let query = url.query?.lowercased() {
            if query.contains("servicelogin")
                || query.contains("openid.mode=checkid_setup")
                || query.contains("openid.mode=checkid_immediate")
                || (query.contains("oauth") && query.contains("client_id=")) {
                return true
            }
        }
        return false
    }

    /// Single source of truth determining whether a `createWebViewWith` popup URL belongs to an auth/OAuth/SSO flow.
    public static func isAuthOrOAuthPopupURL(_ url: URL) -> Bool {
        if isTransientAuthURL(url) {
            return true
        }
        let segments = url.standardized.path.lowercased()
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { stripOptionalWebExtension(String($0)) }
        let afterLocale = Array(stripLeadingLocaleSegment(segments))
        return afterLocale.first == "auth"
    }

    /// Inspects non-expired cookie `(name, domain)` tuples (never values) to verify active server session cookies.
    /// Returns `nil` for services that rely on URL-based auth-flow completion detection.
    public static func hasAuthenticatedSessionCookie(
        cookieEntries: [(name: String, domain: String)],
        for service: StreamingService
    ) -> Bool? {
        guard service.id == "primevideo" else {
            return nil
        }
        let exactNames: Set<String> = [
            "at-main", "sess-at-main",
            "at-main-av", "sess-at-main-av",
            "at-av", "sess-at-av"
        ]
        for entry in cookieEntries {
            guard matchesCookieDomain(entry.domain, for: service) else { continue }
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if exactNames.contains(name) || name.hasPrefix("at-acb") || name.hasPrefix("sess-at-acb") {
                return true
            }
        }
        return false
    }

    private static func stripAmazonRegionPrefix(_ segments: [String]) -> ArraySlice<String> {
        guard segments.count >= 2, segments[0] == "region" else {
            return segments[...]
        }
        let cc = segments[1]
        if (2...3).contains(cc.count) && cc.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) {
            return segments.dropFirst(2)
        }
        return segments[...]
    }

    /// Strict domain match for `WKWebsiteDataRecord.displayName` (never uses `.contains()` to prevent accidental cross-service nukes).
    public static func matchesDataRecord(displayName: String, for service: StreamingService) -> Bool {
        let normalized = normalizeDomain(displayName)
        guard !normalized.isEmpty else { return false }
        if service.id == "primevideo" && isAmazonOrPrimeVideoHost(normalized) {
            return true
        }
        return service.dataDomains.contains { rawDomain in
            let domain = normalizeDomain(rawDomain)
            guard !domain.isEmpty else { return false }
            return normalized == domain || normalized.hasSuffix("." + domain)
        }
    }

    /// Strict domain match for `HTTPCookie.domain` (handles leading dots like `.twitch.tv`).
    public static func matchesCookieDomain(_ cookieDomain: String, for service: StreamingService) -> Bool {
        matchesDataRecord(displayName: cookieDomain, for: service)
    }

    /// Honest shared-SSO confirmation note when clearing site data affects sibling accounts (Google or MyDisney).
    public static func sharedSSOWarning(for service: StreamingService) -> String? {
        switch service.id {
        case "youtube", "yttv":
            return "YouTube and YouTube TV share Google sign-in cookies. Resetting this service may also sign you out of your other Google-based tab."
        case "disneyplus", "hulu", "espn":
            return "Disney+, Hulu, and ESPN share MyDisney sign-in cookies. Resetting this service may also sign you out of the other MyDisney services."
        default:
            return nil
        }
    }

    /// Conservative passive heuristic detecting when an embedded sign-in web view has completed login
    /// and landed on an authenticated home/browse path (never claims sign-in while still on login/auth/OAuth routes).
    public static func isLikelySignedInNavigation(url: URL?, for service: StreamingService) -> Bool {
        guard let url, let rawHost = url.host, !rawHost.isEmpty else { return false }
        guard !isTransientAuthURL(url) else { return false }

        let host = normalizeDomain(rawHost)
        let path = url.standardized.path.lowercased()
        let rawSegments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let normSegments = rawSegments.map(stripOptionalWebExtension)

        if service.id == "primevideo" {
            guard isAmazonOrPrimeVideoHost(host) else { return false }
            let amzSegs = Array(stripAmazonRegionPrefix(normSegments))
            if amzSegs.first == "splash" || amzSegs.first == "offers" {
                return false
            }
            if amzSegs.count >= 2 && amzSegs[0] == "offers" && amzSegs[1] == "nonprimehomepage" {
                return false
            }
            if amzSegs.count >= 3 && amzSegs[0] == "gp" && amzSegs[1] == "video" && (amzSegs[2] == "splash" || amzSegs[2] == "offers") {
                return false
            }
            if path.hasPrefix("/gp/video") || path.contains("/video/") {
                return true
            }
            let isPrimeVideoHost = host == "primevideo.com" || host.hasSuffix(".primevideo.com")
            if isPrimeVideoHost && amzSegs.isEmpty {
                return true
            }
            if let first = amzSegs.first {
                let allowedPrimeRoutes: Set<String> = ["storefront", "mystuff", "watchlist", "profiles", "detail", "livetv"]
                if allowedPrimeRoutes.contains(first) {
                    return true
                }
                if isPrimeVideoHost && ["home", "sports", "watch"].contains(first) {
                    return true
                }
            }
            return false
        }

        if service.id == "max" {
            let isMaxHost = host == "hbomax.com" || host.hasSuffix(".hbomax.com")
                || host == "max.com" || host.hasSuffix(".max.com")
            guard isMaxHost else { return false }
            let afterLocale = Array(stripLeadingLocaleSegment(normSegments))
            let first = afterLocale.first ?? ""
            if host == "play.hbomax.com" || host == "play.max.com" {
                let loggedOutRoutes: Set<String> = [
                    "login", "auth", "subscribe", "plans", "pricing",
                    "signup", "sign-up", "welcome", "activate", "redeem", "offers"
                ]
                return !loggedOutRoutes.contains(first)
            }
            let signedInRoots: Set<String> = [
                "home", "profile", "profiles", "select-profile", "profile-select",
                "player", "my-stuff", "my-list"
            ]
            if signedInRoots.contains(first) {
                return true
            }
            if afterLocale.count >= 2 && afterLocale[0] == "video" && afterLocale[1] == "watch" {
                return true
            }
            return false
        }

        guard let rawHomeHost = service.homeURL.host else { return false }
        let normalizedHomeHost = normalizeDomain(rawHomeHost)
        let bareHomeHost = normalizedHomeHost.hasPrefix("www.") ? String(normalizedHomeHost.dropFirst(4)) : normalizedHomeHost
        let hostMatchesHome = (host == bareHomeHost || host.hasSuffix("." + bareHomeHost))
        guard hostMatchesHome else { return false }

        // Require authenticated-looking landing paths for services whose home URL also serves logged-out walls.
        let afterLocale = Array(stripLeadingLocaleSegment(normSegments))
        switch service.id {
        case "netflix":
            return ["browse", "profiles", "watch", "latest", "my-list"].contains(afterLocale.first ?? "")
        case "disneyplus":
            return ["home", "select-profile", "browse", "play", "video"].contains(afterLocale.first ?? "")
        case "hulu":
            return ["hub", "profile", "profiles", "watch", "my-stuff"].contains(afterLocale.first ?? "")
        case "peacock":
            return path.hasPrefix("/watch")
        case "paramount":
            return path.hasPrefix("/home") || path.hasPrefix("/user-profile") || path.hasPrefix("/shows") || path.hasPrefix("/movies") || path.hasPrefix("/live-tv")
        case "fubo":
            return path.hasPrefix("/p/") || path.hasPrefix("/home") || path.hasPrefix("/guide") || path.hasPrefix("/sports") || path.hasPrefix("/movies") || path.hasPrefix("/shows")
        case "crunchyroll":
            let loggedOutRoutes: Set<String> = [
                "login", "register", "reset-password", "welcome",
                "freetrial", "premium", "offer", "try", "auth", "callback", "oauth"
            ]
            if let first = afterLocale.first, loggedOutRoutes.contains(first) {
                return false
            }
            return true
        case "yttv":
            guard host == "tv.youtube.com" else { return false }
            let loggedOutYTTV: Set<String> = [
                "welcome", "start", "signup", "sign-up", "landing", "try", "promo", "offer", "offers"
            ]
            if let first = normSegments.first, loggedOutYTTV.contains(first) {
                return false
            }
            if let query = url.query?.lowercased(), query.contains("rd_rsn=lo") {
                return false
            }
            return true
        case "youtube":
            // Only mark YouTube signed-in when redirected back off Google Accounts (caller can also let user click Done).
            return host == "www.youtube.com" && !path.hasPrefix("/signin")
        default:
            return true
        }
    }

    private static func normalizeDomain(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
