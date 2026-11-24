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

/// Single source of truth for GlassGrid You's 17 built-in streaming services,
/// per-service site-data domain isolation, and passive sign-in navigation heuristics.
public enum StreamingServiceCatalog {
    public static let defaultEnabledServiceIDs: [String] = ["youtube"]

    /// All 17 major streaming services grouped across Video & Live TV, Movies & Shows, and Live Sports.
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
            authHostHints: ["sp.auth.adobe.com", "registerdisney.go.com", "cdn.registerdisney.go.com"],
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
            signInURLString: "https://www.amazon.com/ap/signin",
            dataDomains: ["amazon.com", "primevideo.com"],
            authHostHints: ["www.amazon.com"],
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
            dataDomains: ["disneyplus.com", "disney.com", "bamgrid.com", "dssott.com"],
            authHostHints: ["registerdisney.go.com"],
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
            dataDomains: ["hulu.com", "disney.com", "bamgrid.com"],
            authHostHints: ["auth.hulu.com", "registerdisney.go.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "rectangle.stack.fill",
            monogram: "HU",
            accentHexStart: "#0C6E42",
            accentHexEnd: "#1CE783"
        ),
        StreamingService(
            id: "max",
            name: "Max",
            subtitle: "HBO, TNT Sports & Warner Bros.",
            category: .moviesAndShows,
            homeURLString: "https://play.max.com/",
            signInURLString: "https://play.max.com/login",
            dataDomains: ["max.com", "hbomax.com", "wbd.com"],
            authHostHints: ["auth.max.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "film.fill",
            monogram: "MX",
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
            authHostHints: ["www.netflix.com"],
            routingMode: .companion,
            requiresStrictDRM: true,
            symbolName: "popcorn.fill",
            monogram: "N",
            accentHexStart: "#8C0910",
            accentHexEnd: "#E50914"
        )
    ]

    public static func service(id: String) -> StreamingService? {
        all.first { $0.id == id }
    }

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
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        if host == "tv.youtube.com" {
            return service(id: "yttv")
        }
        if YouTubeURLRouter.isYouTubeHost(host) {
            return service(id: "youtube")
        }
        for svc in all where svc.id != "youtube" && svc.id != "yttv" {
            if let homeHost = svc.homeURL.host?.lowercased(),
               host == homeHost || host.hasSuffix("." + homeHost) {
                return svc
            }
            for domain in svc.dataDomains where domain != "google.com" && domain != "disney.com" && domain != "adobe.com" {
                let clean = domain.lowercased()
                if host == clean || host.hasSuffix("." + clean) {
                    return svc
                }
            }
        }
        return nil
    }

    /// Strict domain match for `WKWebsiteDataRecord.displayName` (never uses `.contains()` to prevent accidental cross-service nukes).
    public static func matchesDataRecord(displayName: String, for service: StreamingService) -> Bool {
        let normalized = normalizeDomain(displayName)
        guard !normalized.isEmpty else { return false }
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
        guard let url, let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let path = url.path.lowercased()
        let query = (url.query ?? "").lowercased()

        // Never treat dedicated auth/SSO/OAuth hosts or paths as signed-in destinations.
        let authHostFragments = [
            "accounts.google.com", "accounts.youtube.com",
            "passport.", "id.", "ids.", "identity.", "auth.",
            "idmsa.apple.com", "appleid.apple.com",
            "sp.auth.adobe.com", "registerdisney.go.com"
        ]
        if authHostFragments.contains(where: { host == $0 || host.hasPrefix($0) || host.hasSuffix("." + $0) }) {
            return false
        }

        let authPathTokens = [
            "/login", "/signin", "/sign-in", "/sign_in", "/ap/signin",
            "/oauth", "/authorize", "/account/signin", "/account/sign-in",
            "/welcome", "/ServiceLogin".lowercased(), "/servicelogin", "/v3/signin"
        ]
        if authPathTokens.contains(where: { path.contains($0) }) || query.contains("servicelogin") {
            return false
        }

        guard let homeHost = service.homeURL.host?.lowercased() else { return false }
        let hostMatchesHome = (host == homeHost || host.hasSuffix("." + homeHost))
        guard hostMatchesHome else { return false }

        // Require authenticated-looking landing paths for services whose home URL also serves logged-out walls.
        switch service.id {
        case "netflix":
            return path.hasPrefix("/browse") || path.hasPrefix("/profiles") || path.hasPrefix("/watch")
        case "disneyplus":
            return path.hasPrefix("/home") || path.hasPrefix("/select-profile") || path.hasPrefix("/browse")
        case "hulu":
            return path.hasPrefix("/hub") || path.hasPrefix("/profiles") || path.hasPrefix("/watch")
        case "peacock":
            return path.hasPrefix("/watch")
        case "paramount":
            return path.hasPrefix("/home") || path.hasPrefix("/shows") || path.hasPrefix("/live-tv")
        case "primevideo":
            return path.hasPrefix("/gp/video") || path.contains("/video/")
        case "yttv":
            return host == "tv.youtube.com"
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
