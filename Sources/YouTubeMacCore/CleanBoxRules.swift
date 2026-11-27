import Foundation

/// Strategy used by Clean-Box rendering to isolate an active player cleanly without breaking controls or DRM.
public enum CleanBoxStrategy: String, Codable, Hashable, Sendable {
    /// Standard `www.youtube.com` `#movie_player` promotion.
    case youtubeNative
    /// `tv.youtube.com` full-viewport passthrough (`ytu-player-controls` renders outside `.html5-video-player`).
    case yttvPassthrough
    /// Direct light-DOM or Shadow-DOM host player container selector on watch routes.
    case companionSelector
    /// Cross-origin player iframe (such as Crunchyroll's Vilos iframe) with companion subframe media bridge.
    case companionIframe
    /// In-page overlay SDK modal mounted over a storefront/detail URL (Prime Video, Apple TV+).
    case companionOverlaySDK
    /// Full-viewport companion watch app (e.g. Disney+) whose Shadow DOM / FairPlay layers stay untouched.
    case companionPassthrough
}

/// High-level route classification determining whether Clean-Box is eligible on a given URL.
public enum CleanBoxRouteClassification: String, Equatable, Codable, Hashable, Sendable {
    case watch
    case overlaySDK
    case browse
    case auth
}

/// Canonical Clean-Box rule profile for a built-in streaming service.
public struct CleanBoxServiceProfile: Equatable, Codable, Hashable, Sendable {
    public let serviceID: String
    public let strategy: CleanBoxStrategy
    public let hosts: [String]
    public let playerSelectors: [String]
    public let iframeSelectors: [String]
    public let allowedIframeHostSuffixes: [String]

    public init(
        serviceID: String,
        strategy: CleanBoxStrategy,
        hosts: [String],
        playerSelectors: [String],
        iframeSelectors: [String] = [],
        allowedIframeHostSuffixes: [String] = []
    ) {
        self.serviceID = serviceID
        self.strategy = strategy
        self.hosts = hosts
        self.playerSelectors = playerSelectors
        self.iframeSelectors = iframeSelectors
        self.allowedIframeHostSuffixes = allowedIframeHostSuffixes
    }
}

/// Pure Foundation watch-vs-browse classifier and service-scoped player iframe allowlist
/// for all 18 catalog streaming services.
public enum CleanBoxRules {
    private static let adOrTrackerHostSuffixes: [String] = [
        "doubleclick.net",
        "googlesyndication.com",
        "imasdk.googleapis.com",
        "adservice.google.com",
        "amazon-adsystem.com",
        "scorecardresearch.com",
        "moatads.com"
    ]

    private static let twitchReservedSingleSegments: Set<String> = [
        "directory", "browse", "following", "search", "settings", "subscriptions",
        "inventory", "drops", "wallet", "turbo", "downloads", "jobs", "p",
        "login", "signup", "activate", "videos", "popout", "moderator",
        "u", "team", "store", "prime", "bits", "friends", "messages",
        "payments", "security", "privacy", "terms", "products", "broadcast",
        "creatorcamp", "redeem", "gift", "clip", "clips"
    ]

    /// All 18 built-in service Clean-Box profiles (`tv.youtube.com` ordered before `youtube.com`).
    public static let allProfiles: [CleanBoxServiceProfile] = [
        CleanBoxServiceProfile(
            serviceID: "yttv",
            strategy: .yttvPassthrough,
            hosts: ["tv.youtube.com"],
            playerSelectors: []
        ),
        CleanBoxServiceProfile(
            serviceID: "youtube",
            strategy: .youtubeNative,
            hosts: ["youtube.com", "youtu.be", "youtube-nocookie.com"],
            playerSelectors: ["#movie_player"]
        ),
        CleanBoxServiceProfile(
            serviceID: "twitch",
            strategy: .companionSelector,
            hosts: ["twitch.tv"],
            playerSelectors: [
                "[data-a-target=\"video-player\"]",
                ".video-player__container",
                ".video-player",
                "[data-a-player-state]"
            ],
            iframeSelectors: [
                "iframe[src*=\"player.twitch.tv\"]",
                "iframe[src*=\"clips.twitch.tv\"]"
            ],
            allowedIframeHostSuffixes: ["player.twitch.tv", "clips.twitch.tv", "twitch.tv"]
        ),
        CleanBoxServiceProfile(
            serviceID: "crunchyroll",
            strategy: .companionIframe,
            hosts: ["crunchyroll.com"],
            playerSelectors: [
                "#vilosRoot",
                "[data-testid=\"vilos-root\"]",
                "[data-testid=\"vilos-player\"]",
                ".vilos-player",
                "[data-testid=\"video-player\"]",
                ".video-player-wrapper",
                "[class*=\"video-player-wrapper\"]",
                "[class*=\"video-player-container\"]",
                ".erc-watch-episode-player"
            ],
            iframeSelectors: [
                "iframe#player0",
                "iframe#vilos-player",
                "iframe.video-player",
                "[data-testid=\"vilos-player\"] iframe",
                "iframe[src*=\"static.crunchyroll.com\"]",
                "iframe[src*=\"crunchyrollsvc.com\"]",
                "iframe[src*=\"vrv.co\"]",
                "iframe[src*=\"vilos\"]"
            ],
            allowedIframeHostSuffixes: ["static.crunchyroll.com", "crunchyrollsvc.com", "vrv.co", "crunchyroll.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "primevideo",
            strategy: .companionOverlaySDK,
            hosts: ["primevideo.com"],
            playerSelectors: [
                "#dv-web-player",
                ".dv-web-player",
                ".webPlayerSDKContainer",
                ".atvwebplayersdk-player-container"
            ],
            allowedIframeHostSuffixes: ["primevideo.com", "amazon.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "espn",
            strategy: .companionSelector,
            hosts: ["espn.com", "espn.go.com"],
            playerSelectors: [
                ".watch-player",
                "[data-testid=\"video-player\"]",
                ".MediaPlayer",
                ".video-player-container",
                ".video-js"
            ],
            iframeSelectors: [
                "iframe[src*=\"espn.com\"]",
                "iframe[src*=\"espncdn.com\"]",
                "iframe[src*=\"bamgrid.com\"]"
            ],
            allowedIframeHostSuffixes: ["espn.com", "espn.go.com", "espncdn.com", "bamgrid.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "nfl",
            strategy: .companionSelector,
            hosts: ["nfl.com"],
            playerSelectors: [
                ".nfl-c-video-player",
                "[data-testid*=\"video-player\"]",
                "[class*=\"VideoPlayer\"]",
                "[class*=\"video-player\"]",
                ".theoplayer-container",
                ".video-js"
            ],
            allowedIframeHostSuffixes: ["nfl.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "mlb",
            strategy: .companionSelector,
            hosts: ["mlb.com"],
            playerSelectors: [
                "#mlb-video-player",
                ".mlbtv-player-wrapper",
                ".mlbtv-players-container",
                ".media-player-container",
                "[class*=\"MediaPlayer\"]",
                "[class*=\"video-player\"]",
                ".video-js"
            ],
            allowedIframeHostSuffixes: ["mlb.com", "mlbstatic.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "nba",
            strategy: .companionSelector,
            hosts: ["nba.com"],
            playerSelectors: [
                "[class*=\"VideoPlayer_\"]",
                "[class*=\"MediaPlayer\"]",
                "[data-testid*=\"video-player\"]",
                ".video-js"
            ],
            allowedIframeHostSuffixes: ["nba.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "peacock",
            strategy: .companionSelector,
            hosts: ["peacocktv.com"],
            playerSelectors: [
                "[data-testid=\"playback-container\"]",
                ".playback-container",
                "[data-testid=\"video-player\"]",
                ".video-player-container",
                ".video-player",
                "[class*=\"PlayerContainer\"]"
            ],
            allowedIframeHostSuffixes: ["peacocktv.com", "nbcuni.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "paramount",
            strategy: .companionSelector,
            hosts: ["paramountplus.com"],
            playerSelectors: [
                "#main-player",
                ".video-player-container",
                ".cbs-player",
                "[class*=\"player-wrapper\"]",
                "[data-testid*=\"player\"]",
                ".av-player"
            ],
            allowedIframeHostSuffixes: ["paramountplus.com", "cbsi.com", "cbs.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "fubo",
            strategy: .companionSelector,
            hosts: ["fubo.tv"],
            playerSelectors: [
                "[data-testid=\"video-player\"]",
                ".player-container",
                "[class*=\"VideoPlayer\"]",
                "#video-container"
            ],
            allowedIframeHostSuffixes: ["fubo.tv"]
        ),
        CleanBoxServiceProfile(
            serviceID: "sling",
            strategy: .companionSelector,
            hosts: ["watch.sling.com", "sling.com"],
            playerSelectors: [
                "#player-container",
                "#video-player-container",
                "[data-testid*=\"player\"]",
                ".player-container",
                "[class*=\"player-container\"]",
                "[class*=\"VideoPlayer\"]"
            ],
            allowedIframeHostSuffixes: ["sling.com", "dish.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "disneyplus",
            strategy: .companionPassthrough,
            hosts: ["disneyplus.com"],
            playerSelectors: [
                "disney-web-player",
                "#hudson-wrapper",
                "btm-media-client-element",
                ".btm-media-client-element",
                ".btm-media-player",
                "[data-testid=\"web-player\"]",
                "[data-testid=\"video-player\"]"
            ],
            allowedIframeHostSuffixes: ["disneyplus.com", "bamgrid.com", "dssott.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "hulu",
            strategy: .companionSelector,
            hosts: ["hulu.com"],
            playerSelectors: [
                ".Player__container",
                "#dash-player-container",
                ".PlaybackContainer",
                ".PlayerRoot",
                "[data-testid=\"player\"]",
                ".video-player"
            ],
            allowedIframeHostSuffixes: ["hulu.com", "bamgrid.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "max",
            strategy: .companionSelector,
            hosts: ["play.hbomax.com", "hbomax.com", "play.max.com", "max.com"],
            playerSelectors: [
                "[data-testid=\"player-ux-wrapper\"]",
                "[data-testid=\"player-container\"]",
                "[data-testid=\"video-player\"]",
                "#layer-root-player",
                ".player-container"
            ],
            allowedIframeHostSuffixes: ["hbomax.com", "max.com", "wbd.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "appletv",
            strategy: .companionOverlaySDK,
            hosts: ["tv.apple.com"],
            playerSelectors: [
                "apple-tv-plus-player",
                "amp-chrome-player",
                "amp-video-player",
                "[data-testid=\"player\"]"
            ],
            allowedIframeHostSuffixes: ["tv.apple.com", "apple.com"]
        ),
        CleanBoxServiceProfile(
            serviceID: "netflix",
            strategy: .companionSelector,
            hosts: ["netflix.com"],
            playerSelectors: [
                "[data-uia=\"watch-video\"]",
                "[data-uia=\"player\"]",
                ".watch-video",
                ".NFPlayer"
            ],
            allowedIframeHostSuffixes: ["netflix.com", "nflxso.net"]
        )
    ]

    /// Flat union of all player iframe host suffixes used by the lightweight JS subframe gate.
    public static let allAllowedPlayerIframeHostSuffixes: [String] = {
        var ordered: [String] = []
        var seen: Set<String> = []
        for profile in allProfiles {
            for suffix in profile.allowedIframeHostSuffixes {
                let norm = normalizeHost(suffix)
                if !norm.isEmpty && seen.insert(norm).inserted {
                    ordered.append(norm)
                }
            }
        }
        return ordered
    }()

    /// Resolves the Clean-Box profile for a top-level URL (`tv.youtube.com` before `youtube.com`, Amazon domains mapped to `primevideo`).
    public static func profile(for url: URL) -> CleanBoxServiceProfile? {
        guard let rawHost = url.host, !rawHost.isEmpty else { return nil }
        let host = normalizeHost(rawHost)
        guard !host.isEmpty else { return nil }

        if host == "tv.youtube.com" {
            return profile(serviceID: "yttv")
        }
        if YouTubeURLRouter.isYouTubeHost(host) {
            return profile(serviceID: "youtube")
        }
        if StreamingServiceCatalog.isAmazonOrPrimeVideoHost(host) {
            return profile(serviceID: "primevideo")
        }

        for item in allProfiles where item.serviceID != "yttv" && item.serviceID != "youtube" {
            if item.hosts.contains(where: { matchesDomain(host, suffix: $0) }) {
                return item
            }
        }
        return nil
    }

    public static func profile(serviceID: String) -> CleanBoxServiceProfile? {
        allProfiles.first { $0.serviceID == serviceID }
    }

    /// Strict Watch vs. Browse vs. Auth route classification for any URL across the 18 catalog services.
    public static func classifyRoute(_ url: URL) -> CleanBoxRouteClassification {
        if StreamingServiceCatalog.isTransientAuthURL(url) {
            return .auth
        }
        guard let rawHost = url.host, !rawHost.isEmpty,
              let prof = profile(for: url) else {
            return .browse
        }

        let host = normalizeHost(rawHost)
        let path = url.standardized.path.lowercased()
        let rawSegments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let normSegments = rawSegments.map(StreamingServiceCatalog.stripOptionalWebExtension)

        switch prof.serviceID {
        case "youtube":
            return YouTubeURLRouter.isWatchURL(url) ? .watch : .browse

        case "yttv":
            return (normSegments.count >= 2 && normSegments[0] == "watch") ? .watch : .browse

        case "twitch":
            if host == "clips.twitch.tv" {
                return normSegments.count >= 1 && !normSegments[0].isEmpty ? .watch : .browse
            }
            if normSegments.count >= 2 && normSegments[0] == "videos" && !normSegments[1].isEmpty {
                return .watch
            }
            if normSegments.count >= 3 && normSegments[1] == "clip" && !normSegments[2].isEmpty {
                return .watch
            }
            // Match strictly 1-segment `/<channel>`, rejecting `/<channel>/videos`, `/<channel>/clips`, `/<channel>/about`, etc.
            if normSegments.count == 1 && !twitchReservedSingleSegments.contains(normSegments[0]) {
                return .watch
            }
            return .browse

        case "crunchyroll":
            let afterLocale = Array(StreamingServiceCatalog.stripLeadingLocaleSegment(normSegments))
            if afterLocale.count >= 2 && afterLocale[0] == "watch" && !afterLocale[1].isEmpty {
                return .watch
            }
            return .browse

        case "primevideo", "appletv":
            return .overlaySDK

        case "espn":
            if path.hasPrefix("/watch/player") || path.hasPrefix("/espnplus/player") || path.hasPrefix("/video/clip") {
                return .watch
            }
            return .browse

        case "nfl":
            if path.hasPrefix("/plus/games/")
                || path.hasPrefix("/plus/live/")
                || path.hasPrefix("/plus/episodes/")
                || path.hasPrefix("/plus/replays/")
                || path.hasPrefix("/network/watch/") {
                return .watch
            }
            return .browse

        case "mlb":
            if normSegments.count >= 2 && normSegments[0] == "tv" && (normSegments[1].hasPrefix("g") || normSegments[1].hasPrefix("c")) {
                return .watch
            }
            if path.hasPrefix("/live-stream-games/") || path.hasPrefix("/video/") {
                return .watch
            }
            return .browse

        case "nba":
            if path.hasPrefix("/watch/event/")
                || path.hasPrefix("/watch/video/")
                || path.hasPrefix("/watch/league-pass") {
                return .watch
            }
            return .browse

        case "peacock":
            if path.hasPrefix("/watch/playback") || path.hasPrefix("/watch/asset") {
                return .watch
            }
            return .browse

        case "paramount":
            if normSegments.count >= 3 && normSegments[0] == "shows" && normSegments[2] == "video" {
                return .watch
            }
            if normSegments.count >= 2 && normSegments[0] == "movies" && normSegments[1] == "video" {
                return .watch
            }
            if path.hasPrefix("/video/") || normSegments.first == "live-tv" {
                return .watch
            }
            return .browse

        case "fubo":
            if path.hasPrefix("/p/watch") || path.hasPrefix("/p/live") || path.hasPrefix("/p/dvr/") {
                return .watch
            }
            return .browse

        case "sling":
            if path.hasPrefix("/1/program/")
                || path.hasPrefix("/1/channel/")
                || path.hasPrefix("/1/asset/")
                || path.hasPrefix("/1/franchise/")
                || normSegments.contains("watch") {
                return .watch
            }
            return .browse

        case "disneyplus":
            let afterLocale = Array(StreamingServiceCatalog.stripLeadingLocaleSegment(normSegments))
            if afterLocale.count >= 2 && (afterLocale[0] == "play" || afterLocale[0] == "video") {
                return .watch
            }
            return .browse

        case "hulu":
            if path.hasPrefix("/watch/") {
                return .watch
            }
            return .browse

        case "max":
            let afterLocale = Array(StreamingServiceCatalog.stripLeadingLocaleSegment(normSegments))
            if (afterLocale.count >= 2 && afterLocale[0] == "video" && afterLocale[1] == "watch") || afterLocale.first == "player" {
                return .watch
            }
            return .browse

        case "netflix":
            let afterLocale = Array(StreamingServiceCatalog.stripLeadingLocaleSegment(normSegments))
            if afterLocale.count >= 2 && afterLocale[0] == "watch" {
                return .watch
            }
            return .browse

        default:
            return .browse
        }
    }

    /// Strict service-scoped validation of a cross-origin player iframe's `securityOrigin.host`
    /// against the top-level tab URL (never allows untrusted origins, ad hosts, or auth pages).
    public static func isAllowedPlayerIframeHost(_ iframeHost: String?, forMainFrameURL mainURL: URL) -> Bool {
        guard let rawIframeHost = iframeHost else { return false }
        let cleanIframe = normalizeHost(rawIframeHost)
        guard !cleanIframe.isEmpty else { return false }
        guard !StreamingServiceCatalog.isTransientAuthURL(mainURL) else { return false }
        guard !StreamingServiceCatalog.isDedicatedAuthHost(cleanIframe) else { return false }
        guard !adOrTrackerHostSuffixes.contains(where: { matchesDomain(cleanIframe, suffix: $0) }) else {
            return false
        }
        guard let profile = profile(for: mainURL) else { return false }
        let route = classifyRoute(mainURL)
        guard route == .watch || route == .overlaySDK else {
            return false
        }
        return profile.allowedIframeHostSuffixes.contains { matchesDomain(cleanIframe, suffix: $0) }
    }

    private static func normalizeHost(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func matchesDomain(_ host: String, suffix: String) -> Bool {
        let cleanSuffix = normalizeHost(suffix)
        guard !cleanSuffix.isEmpty else { return false }
        return host == cleanSuffix || host.hasSuffix("." + cleanSuffix)
    }
}
