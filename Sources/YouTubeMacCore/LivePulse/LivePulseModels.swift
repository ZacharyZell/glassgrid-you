import CoreGraphics
import Foundation

// MARK: - Sports & Live Score Models

/// Supported sports leagues for Live Pulse scoreboards, fantasy, play-by-play, and markets.
public enum SportsLeague: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case nfl
    case nba
    case mlb
    case nhl
    case ncaaf
    case ncaab
    case mls
    case epl
    case f1

    /// Core 4 pro leagues enabled by default (preserving opt-in privacy/network budget for expanded leagues).
    public static let primaryLeagues: [SportsLeague] = [.nfl, .nba, .mlb, .nhl]
    public static let defaultEnabledLeagues: [SportsLeague] = [.nfl, .nba, .mlb, .nhl]

    public var id: String { rawValue }

    public var espnSportPath: String {
        switch self {
        case .nfl, .ncaaf: return "football"
        case .nba, .ncaab: return "basketball"
        case .mlb: return "baseball"
        case .nhl: return "hockey"
        case .mls, .epl: return "soccer"
        case .f1: return "racing"
        }
    }

    public var espnLeaguePath: String {
        switch self {
        case .nfl: return "nfl"
        case .nba: return "nba"
        case .mlb: return "mlb"
        case .nhl: return "nhl"
        case .ncaaf: return "college-football"
        case .ncaab: return "mens-college-basketball"
        case .mls: return "usa.1"
        case .epl: return "eng.1"
        case .f1: return "f1"
        }
    }

    public var espnFantasyGameCode: String {
        switch self {
        case .nfl, .ncaaf: return "ffl"
        case .nba, .ncaab: return "fba"
        case .mlb: return "flb"
        case .nhl: return "fhl"
        case .mls: return "mls"
        case .epl: return "epl"
        case .f1: return "f1"
        }
    }

    public var supportsESPNFantasy: Bool {
        switch self {
        case .nfl, .nba, .mlb, .nhl: return true
        case .ncaaf, .ncaab, .mls, .epl, .f1: return false
        }
    }

    public var sleeperSportCode: String? {
        switch self {
        case .nfl: return "nfl"
        case .nba: return "nba"
        case .mlb, .nhl, .ncaaf, .ncaab, .mls, .epl, .f1: return nil
        }
    }

    public var kalshiSeriesTicker: String {
        switch self {
        case .nfl: return "KXNFLGAME"
        case .nba: return "KXNBAGAME"
        case .mlb: return "KXMLBGAME"
        case .nhl: return "KXNHLGAME"
        case .ncaaf: return "KXNCAAFGAME"
        case .ncaab: return "KXNCAABGAME"
        case .mls: return "KXMLSGAME"
        case .epl: return "KXEPLGAME"
        case .f1: return "KXF1RACE"
        }
    }

    public var displayName: String {
        switch self {
        case .ncaaf: return "NCAAFB"
        case .ncaab: return "NCAAB"
        default: return rawValue.uppercased()
        }
    }

    public var symbolName: String {
        switch self {
        case .nfl, .ncaaf: return "football.fill"
        case .nba, .ncaab: return "basketball.fill"
        case .mlb: return "baseball.fill"
        case .nhl: return "hockey.puck.fill"
        case .mls, .epl: return "soccerball"
        case .f1: return "flag.checkered"
        }
    }
}

public extension SportsLeague {
    /// Normalizes a league priority list by deduplicating while preserving order and appending any missing leagues.
    static func normalizedPriority(_ raw: [SportsLeague]) -> [SportsLeague] {
        var result: [SportsLeague] = []
        result.reserveCapacity(SportsLeague.allCases.count)
        var seen: Set<SportsLeague> = []
        for league in raw where seen.insert(league).inserted {
            result.append(league)
        }
        for league in SportsLeague.allCases where seen.insert(league).inserted {
            result.append(league)
        }
        return result
    }
}

/// Canonical lifecycle state of a sporting event.
public enum GameStatus: String, Codable, Equatable, Hashable, Sendable {
    case pregame
    case live
    case halftime
    case final
    case postponed
}

/// Scoreboard line for a single competing team or F1 driver.
public struct TeamScore: Equatable, Hashable, Codable, Sendable {
    public let espnTeamID: String
    public let abbreviation: String
    public let displayName: String
    public let shortName: String
    public let score: Int
    public let record: String?
    public let isPossession: Bool
    public let rank: Int?

    public init(
        espnTeamID: String,
        abbreviation: String,
        displayName: String,
        shortName: String,
        score: Int,
        record: String? = nil,
        isPossession: Bool = false,
        rank: Int? = nil
    ) {
        self.espnTeamID = espnTeamID
        self.abbreviation = abbreviation
        self.displayName = displayName
        self.shortName = shortName
        self.score = score
        self.record = record
        self.isPossession = isPossession
        self.rank = rank
    }
}

/// Live in-game situation metadata (football possession/red-zone or baseball count/bases).
public struct GameSituation: Equatable, Hashable, Codable, Sendable {
    public let possessionTeamID: String?
    public let downDistanceText: String?
    public let isRedZone: Bool
    public let yardLineText: String?
    public let balls: Int?
    public let strikes: Int?
    public let outs: Int?
    public let runnersOnBaseText: String?

    public init(
        possessionTeamID: String? = nil,
        downDistanceText: String? = nil,
        isRedZone: Bool = false,
        yardLineText: String? = nil,
        balls: Int? = nil,
        strikes: Int? = nil,
        outs: Int? = nil,
        runnersOnBaseText: String? = nil
    ) {
        self.possessionTeamID = possessionTeamID
        self.downDistanceText = downDistanceText
        self.isRedZone = isRedZone
        self.yardLineText = yardLineText
        self.balls = balls
        self.strikes = strikes
        self.outs = outs
        self.runnersOnBaseText = runnersOnBaseText
    }
}

/// Normalized live sporting event model from ESPN public scoreboard/summary feeds.
public struct LiveGame: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let league: SportsLeague
    public let status: GameStatus
    public let statusDetail: String
    public let clock: String?
    public let period: Int?
    public let startTime: Date?
    public let away: TeamScore
    public let home: TeamScore
    public let broadcasts: [String]
    public let situation: GameSituation?
    public let espnAwayWinProb: Double?
    public let espnHomeWinProb: Double?
    public let spreadSummary: String?
    public let overUnder: Double?

    public init(
        id: String,
        league: SportsLeague,
        status: GameStatus,
        statusDetail: String,
        clock: String? = nil,
        period: Int? = nil,
        startTime: Date? = nil,
        away: TeamScore,
        home: TeamScore,
        broadcasts: [String] = [],
        situation: GameSituation? = nil,
        espnAwayWinProb: Double? = nil,
        espnHomeWinProb: Double? = nil,
        spreadSummary: String? = nil,
        overUnder: Double? = nil
    ) {
        self.id = id
        self.league = league
        self.status = status
        self.statusDetail = statusDetail
        self.clock = clock
        self.period = period
        self.startTime = startTime
        self.away = away
        self.home = home
        self.broadcasts = broadcasts
        self.situation = situation
        self.espnAwayWinProb = espnAwayWinProb
        self.espnHomeWinProb = espnHomeWinProb
        self.spreadSummary = spreadSummary
        self.overUnder = overUnder
    }
}

// MARK: - Fantasy Models

/// Supported read-only fantasy sports providers.
public enum FantasyProvider: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case sleeper
    case espnPublic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sleeper: return "Sleeper"
        case .espnPublic: return "ESPN Public"
        }
    }
}

/// Persisted configuration for a user's fantasy league.
public struct FantasyLeagueConfig: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let provider: FantasyProvider
    public let league: SportsLeague
    public let leagueID: String
    public let leagueName: String
    public let season: Int
    public let teamOwnerHint: String?
    public let isEnabled: Bool

    public init(
        id: String,
        provider: FantasyProvider,
        league: SportsLeague,
        leagueID: String,
        leagueName: String,
        season: Int,
        teamOwnerHint: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.provider = provider
        self.league = league
        self.leagueID = leagueID
        self.leagueName = leagueName
        self.season = season
        self.teamOwnerHint = teamOwnerHint
        self.isEnabled = isEnabled
    }
}

/// Normalized fantasy roster player line item enriched with live game context.
public struct FantasyPlayerLine: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let espnPlayerID: String?
    public let name: String
    public let position: String
    public let nflOrProTeam: String
    public let points: Double
    public let projectedPoints: Double?
    public let isStarter: Bool
    public let isUserRoster: Bool
    public let matchedGameID: String?
    public let isActiveInStream: Bool
    public let isRedZone: Bool
    public let liveStatLine: String?
    public let lastDeltaPoints: Double?

    public init(
        id: String,
        espnPlayerID: String? = nil,
        name: String,
        position: String,
        nflOrProTeam: String,
        points: Double,
        projectedPoints: Double? = nil,
        isStarter: Bool,
        isUserRoster: Bool,
        matchedGameID: String? = nil,
        isActiveInStream: Bool = false,
        isRedZone: Bool = false,
        liveStatLine: String? = nil,
        lastDeltaPoints: Double? = nil
    ) {
        self.id = id
        self.espnPlayerID = espnPlayerID
        self.name = name
        self.position = position
        self.nflOrProTeam = nflOrProTeam
        self.points = points
        self.projectedPoints = projectedPoints
        self.isStarter = isStarter
        self.isUserRoster = isUserRoster
        self.matchedGameID = matchedGameID
        self.isActiveInStream = isActiveInStream
        self.isRedZone = isRedZone
        self.liveStatLine = liveStatLine
        self.lastDeltaPoints = lastDeltaPoints
    }
}

/// Normalized head-to-head fantasy matchup snapshot.
public struct FantasyMatchup: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let configID: String
    public let provider: FantasyProvider
    public let league: SportsLeague
    public let leagueName: String
    public let weekLabel: String
    public let userTeamName: String
    public let opponentTeamName: String
    public let userPoints: Double
    public let opponentPoints: Double
    public let userProjected: Double?
    public let opponentProjected: Double?
    public let starters: [FantasyPlayerLine]
    public let bench: [FantasyPlayerLine]
    public let opponentStarters: [FantasyPlayerLine]

    public init(
        id: String,
        configID: String,
        provider: FantasyProvider,
        league: SportsLeague,
        leagueName: String,
        weekLabel: String,
        userTeamName: String,
        opponentTeamName: String,
        userPoints: Double,
        opponentPoints: Double,
        userProjected: Double? = nil,
        opponentProjected: Double? = nil,
        starters: [FantasyPlayerLine] = [],
        bench: [FantasyPlayerLine] = [],
        opponentStarters: [FantasyPlayerLine] = []
    ) {
        self.id = id
        self.configID = configID
        self.provider = provider
        self.league = league
        self.leagueName = leagueName
        self.weekLabel = weekLabel
        self.userTeamName = userTeamName
        self.opponentTeamName = opponentTeamName
        self.userPoints = userPoints
        self.opponentPoints = opponentPoints
        self.userProjected = userProjected
        self.opponentProjected = opponentProjected
        self.starters = starters
        self.bench = bench
        self.opponentStarters = opponentStarters
    }
}

// MARK: - Prediction Market Models (Strictly Read-Only Informational)

/// Supported read-only public prediction market data sources.
public enum PredictionMarketProvider: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case kalshi
    case polymarket

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kalshi: return "Kalshi"
        case .polymarket: return "Polymarket"
        }
    }
}

/// Read-only implied probability market quote for an active sports outcome.
public struct PredictionMarketQuote: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let provider: PredictionMarketProvider
    public let league: SportsLeague?
    public let matchedGameID: String?
    public let tickerOrSlug: String
    public let title: String
    public let outcomeLabel: String
    public let yesProbability: Double
    public let delta1m: Double?
    public let delta5m: Double?
    public let volumeUSD: Double?
    public let updatedAt: Date
    public let externalURLString: String?

    public init(
        id: String,
        provider: PredictionMarketProvider,
        league: SportsLeague? = nil,
        matchedGameID: String? = nil,
        tickerOrSlug: String,
        title: String,
        outcomeLabel: String,
        yesProbability: Double,
        delta1m: Double? = nil,
        delta5m: Double? = nil,
        volumeUSD: Double? = nil,
        updatedAt: Date = Date(),
        externalURLString: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.league = league
        self.matchedGameID = matchedGameID
        self.tickerOrSlug = tickerOrSlug
        self.title = title
        self.outcomeLabel = outcomeLabel
        self.yesProbability = min(1.0, max(0.0, yesProbability))
        self.delta1m = delta1m
        self.delta5m = delta5m
        self.volumeUSD = volumeUSD
        self.updatedAt = updatedAt
        self.externalURLString = externalURLString
    }
}

// MARK: - Stream Context, Spoiler Delay & UI Layout Models

/// Configurable delay applied to live scores, fantasy deltas, and market ticks to prevent HLS/DASH spoilers.
public enum SpoilerDelayOption: Int, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case off = 0
    case seconds20 = 20
    case seconds35 = 35

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Live (0s)"
        case .seconds20: return "20s Delay"
        case .seconds35: return "35s Delay"
        }
    }

    public var shortLabel: String {
        "\(rawValue)s"
    }
}

/// Top-level tabs inside the right-hand Live Companion Drawer.
public enum LivePulseDrawerTab: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case matchup
    case players
    case scores
    case markets
    case chat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .matchup: return "Matchup"
        case .players: return "Players"
        case .scores: return "Scores"
        case .markets: return "Markets"
        case .chat: return "Chat"
        }
    }

    public var symbolName: String {
        switch self {
        case .matchup: return "trophy.fill"
        case .players: return "person.2.fill"
        case .scores: return "sportscourt.fill"
        case .markets: return "chart.line.uptrend.xyaxis"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }
}

/// Normalized play-by-play or key match event parsed from ESPN game summaries and gated by `SpoilerDelayBuffer`.
public struct PlayByPlayEvent: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let gameID: String
    public let periodText: String
    public let clock: String?
    public let teamAbbreviation: String?
    public let text: String
    public let isScoringPlay: Bool
    public let awayScore: Int?
    public let homeScore: Int?
    public let wallclock: Date?

    public init(
        id: String,
        gameID: String,
        periodText: String = "",
        clock: String? = nil,
        teamAbbreviation: String? = nil,
        text: String,
        isScoringPlay: Bool = false,
        awayScore: Int? = nil,
        homeScore: Int? = nil,
        wallclock: Date? = nil
    ) {
        self.id = id
        self.gameID = gameID
        self.periodText = periodText
        self.clock = clock
        self.teamAbbreviation = teamAbbreviation
        self.text = text
        self.isScoringPlay = isScoringPlay
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.wallclock = wallclock
    }
}

public typealias LivePlayEvent = PlayByPlayEvent

/// Spoiler-delayed scoring alert badge surfaced when a watched or pinned game changes score.
public struct LivePulseScoringAlert: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    public let gameID: String
    public let league: SportsLeague
    public let headline: String
    public let detail: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        gameID: String,
        league: SportsLeague,
        headline: String,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.gameID = gameID
        self.league = league
        self.headline = headline
        self.detail = detail
        self.timestamp = timestamp
    }
}

/// Strict HTTPS allowlist & URL builder for the lazy Companion Drawer Live Chat tab (`twitch.tv/popout/.../chat` and `youtube.com/live_chat`).
public enum CompanionChatURLValidator {
    public static func isAllowedChatURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https",
              let rawHost = url.host?.lowercased(), !rawHost.isEmpty else {
            return false
        }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).lowercased() }
        if rawHost == "www.twitch.tv" || rawHost == "twitch.tv" {
            return segments.count == 3 && segments[0] == "popout" && !segments[1].isEmpty && segments[2] == "chat"
        }
        if rawHost == "www.youtube.com" || rawHost == "youtube.com" {
            guard url.path.lowercased() == "/live_chat",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let vid = components.queryItems?.first(where: { $0.name == "v" })?.value,
                  !vid.isEmpty else {
                return false
            }
            return true
        }
        return false
    }

    public static func twitchPopoutChatURL(channel: String, darkMode: Bool = true) -> URL? {
        let trimmed = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...25).contains(trimmed.count),
              trimmed.unicodeScalars.allSatisfy({ s in
                  (s.value >= 48 && s.value <= 57)
                      || (s.value >= 65 && s.value <= 90)
                      || (s.value >= 97 && s.value <= 122)
                      || s == "_"
              }) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.twitch.tv"
        components.path = "/popout/\(trimmed)/chat"
        if darkMode {
            components.queryItems = [URLQueryItem(name: "darkpopout", value: nil)]
        }
        return components.url
    }

    public static func youtubeLiveChatURL(videoID: String, darkMode: Bool = true) -> URL? {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.count <= 20,
              trimmed.unicodeScalars.allSatisfy({ s in
                  (s.value >= 48 && s.value <= 57)
                      || (s.value >= 65 && s.value <= 90)
                      || (s.value >= 97 && s.value <= 122)
                      || s == "-" || s == "_"
              }) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/live_chat"
        var items = [
            URLQueryItem(name: "v", value: trimmed),
            URLQueryItem(name: "is_popout", value: "1")
        ]
        if darkMode {
            items.append(URLQueryItem(name: "dark_theme", value: "1"))
        }
        components.queryItems = items
        return components.url
    }

    public static func chatURL(forStreamURL streamURL: URL, darkMode: Bool = true) -> URL? {
        guard let host = streamURL.host?.lowercased() else { return nil }
        if host == "www.twitch.tv" || host == "twitch.tv" {
            if CleanBoxRules.classifyRoute(streamURL) == .watch {
                let segments = streamURL.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                if segments.count == 1 {
                    return twitchPopoutChatURL(channel: segments[0], darkMode: darkMode)
                }
            }
            return nil
        }
        if YouTubeURLRouter.isStandardYouTubeHost(host),
           let videoID = YouTubeURLRouter.extractVideoID(from: streamURL) {
            return youtubeLiveChatURL(videoID: videoID, darkMode: darkMode)
        }
        return nil
    }
}

/// Passive tab/tile metadata forwarded from the browser layer to identify the active sporting broadcast.
public struct StreamSignal: Equatable, Hashable, Sendable {
    public let tabID: UUID
    public let windowID: UUID
    public let url: URL
    public let title: String
    public let serviceID: String?
    public let multiviewSlot: Int?
    public let isPrimaryFocus: Bool
    public let isPlaying: Bool
    public let hasVideo: Bool
    public let isAuthOrBrowse: Bool
    public let streamContext: StreamContextMetadata

    public init(
        tabID: UUID,
        windowID: UUID,
        url: URL,
        title: String,
        serviceID: String? = nil,
        multiviewSlot: Int? = nil,
        isPrimaryFocus: Bool = false,
        isPlaying: Bool = false,
        hasVideo: Bool = false,
        isAuthOrBrowse: Bool = false,
        streamContext: StreamContextMetadata = .empty
    ) {
        self.tabID = tabID
        self.windowID = windowID
        self.url = url
        self.title = title
        self.serviceID = serviceID
        self.multiviewSlot = multiviewSlot
        self.isPrimaryFocus = isPrimaryFocus
        self.isPlaying = isPlaying
        self.hasVideo = hasVideo
        self.isAuthOrBrowse = isAuthOrBrowse
        self.streamContext = streamContext
    }
}

/// Confidence tier for a matched live stream context.
public enum MatchConfidence: String, Codable, Equatable, Hashable, Sendable {
    case high
    case medium
    case manual
}

/// Resolved sporting context for a watched tab or tile.
public enum StreamSportContext: Equatable, Hashable, Sendable {
    case none
    case matchedGame(gameID: String, league: SportsLeague, confidence: MatchConfidence, sourceLabel: String)
    case liveSlate(league: SportsLeague, label: String)
    case networkCandidates(network: String, league: SportsLeague?, gameIDs: [String])
}

/// User-selected pin binding a tab/channel scope to a specific game or whip-around slate.
public struct ManualGamePin: Equatable, Hashable, Codable, Sendable {
    public enum PinMode: Equatable, Hashable, Codable, Sendable {
        case game(gameID: String, league: SportsLeague)
        case liveSlate(league: SportsLeague, label: String)
    }

    public let tabID: UUID
    public let scopeKey: String
    public let mode: PinMode
    public let isLocked: Bool

    public init(tabID: UUID, scopeKey: String, mode: PinMode, isLocked: Bool = true) {
        self.tabID = tabID
        self.scopeKey = scopeKey
        self.mode = mode
        self.isLocked = isLocked
    }
}

/// Timestamped live update surfaced in the Ticker Bar and Drawer delta highlights.
public struct LivePulseDeltaEvent: Identifiable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Equatable, Hashable, Sendable {
        case score
        case fantasyPoints
        case marketMove
    }

    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    public let gameID: String?
    public let headline: String
    public let deltaText: String
    public let isPositive: Bool
    public let isBench: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        gameID: String? = nil,
        headline: String,
        deltaText: String,
        isPositive: Bool,
        isBench: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.gameID = gameID
        self.headline = headline
        self.deltaText = deltaText
        self.isPositive = isPositive
        self.isBench = isBench
    }
}

/// Bucketed UI freshness state computed purely from poll timestamps and live-game presence.
public struct LivePulseFreshnessState: Equatable, Sendable {
    public let label: String
    public let isStale: Bool
    public let isTickerStale: Bool
    public let isOffline: Bool
    public let isLiveDot: Bool

    public init(
        label: String,
        isStale: Bool,
        isTickerStale: Bool,
        isOffline: Bool,
        isLiveDot: Bool
    ) {
        self.label = label
        self.isStale = isStale
        self.isTickerStale = isTickerStale
        self.isOffline = isOffline
        self.isLiveDot = isLiveDot
    }
}

/// Pure 15s-bucketed freshness formatter (zero 1Hz timer churn).
public enum LivePulseFreshnessFormatter {
    public static func format(
        lastUpdatedAt: Date?,
        now: Date = Date(),
        hasLiveGames: Bool,
        isOffline: Bool
    ) -> LivePulseFreshnessState {
        if isOffline {
            return LivePulseFreshnessState(
                label: "Offline",
                isStale: true,
                isTickerStale: true,
                isOffline: true,
                isLiveDot: false
            )
        }
        guard let lastUpdatedAt else {
            return LivePulseFreshnessState(
                label: "Syncing",
                isStale: false,
                isTickerStale: false,
                isOffline: false,
                isLiveDot: false
            )
        }

        let elapsed = max(0, now.timeIntervalSince(lastUpdatedAt))
        if elapsed < 30 {
            return LivePulseFreshnessState(
                label: hasLiveGames ? "Live" : "Synced",
                isStale: false,
                isTickerStale: false,
                isOffline: false,
                isLiveDot: hasLiveGames
            )
        }
        if elapsed < 60 {
            return LivePulseFreshnessState(
                label: "<1m",
                isStale: false,
                isTickerStale: false,
                isOffline: false,
                isLiveDot: false
            )
        }
        if elapsed < 300 {
            let mins = Int(elapsed / 60)
            return LivePulseFreshnessState(
                label: "\(mins)m",
                isStale: hasLiveGames && elapsed >= 120,
                isTickerStale: hasLiveGames && elapsed >= 60,
                isOffline: false,
                isLiveDot: false
            )
        }
        return LivePulseFreshnessState(
            label: "5m+",
            isStale: true,
            isTickerStale: true,
            isOffline: false,
            isLiveDot: false
        )
    }
}

/// Coalesced immutable Live Pulse UI snapshot observed by the Ticker Bar, Drawer, and Settings views.
public struct LivePulseSnapshot: Equatable, Sendable {
    public let games: [LiveGame]
    public let matchups: [FantasyMatchup]
    public let markets: [PredictionMarketQuote]
    public let recentDeltas: [LivePulseDeltaEvent]
    public let streamContextByTab: [UUID: StreamSportContext]
    public let primaryContext: StreamSportContext
    public let activeGameIDs: Set<String>
    public let providerStatus: [String: String]
    public let lastUpdatedAt: Date?
    public let playsByGameID: [String: [PlayByPlayEvent]]
    public let scoringAlerts: [LivePulseScoringAlert]
    public let scoringFlashGameIDs: Set<String>

    public init(
        games: [LiveGame] = [],
        matchups: [FantasyMatchup] = [],
        markets: [PredictionMarketQuote] = [],
        recentDeltas: [LivePulseDeltaEvent] = [],
        streamContextByTab: [UUID: StreamSportContext] = [:],
        primaryContext: StreamSportContext = .none,
        activeGameIDs: Set<String> = [],
        providerStatus: [String: String] = [:],
        lastUpdatedAt: Date? = nil,
        playsByGameID: [String: [PlayByPlayEvent]] = [:],
        scoringAlerts: [LivePulseScoringAlert] = [],
        scoringFlashGameIDs: Set<String> = []
    ) {
        self.games = games
        self.matchups = matchups
        self.markets = markets
        self.recentDeltas = recentDeltas
        self.streamContextByTab = streamContextByTab
        self.primaryContext = primaryContext
        self.activeGameIDs = activeGameIDs
        self.providerStatus = providerStatus
        self.lastUpdatedAt = lastUpdatedAt
        self.playsByGameID = playsByGameID
        self.scoringAlerts = scoringAlerts
        self.scoringFlashGameIDs = scoringFlashGameIDs
    }

    public static let empty = LivePulseSnapshot()
}

/// Shared layout geometry constants and clamping helpers for the Live Pulse Ticker Bar and Companion Drawer.
public enum LivePulseLayout {
    public static let tickerHeight: CGFloat = 30
    public static let drawerDefaultWidth: CGFloat = 320
    public static let drawerMinWidth: CGFloat = 280
    public static let drawerMaxWidth: CGFloat = 440
    public static let drawerDividerWidth: CGFloat = 6
    public static let drawerCardTopInset: CGFloat = 4
    public static let drawerCardBottomInset: CGFloat = 8
    public static let drawerCardLeadingInset: CGFloat = 4
    public static let drawerCardTrailingInset: CGFloat = 8
    public static let drawerCardCornerRadius: CGFloat = 16
    public static let drawerHeaderHeight: CGFloat = 36
    public static let minimumWebContentWidth: CGFloat = 480
    public static let autoCollapseSidebarThreshold: CGFloat = 1060

    /// Clamps a requested drawer width strictly to `[drawerMinWidth, drawerMaxWidth]`.
    public static func clampDrawerWidth(_ raw: CGFloat) -> CGFloat {
        guard raw.isFinite else { return drawerDefaultWidth }
        return min(drawerMaxWidth, max(drawerMinWidth, raw))
    }

    /// Computes effective drawer width while preserving `minimumWebContentWidth` (480pt) for `TabWebViewHost`.
    /// Never returns negative values.
    public static func effectiveDrawerWidth(
        requested: CGFloat,
        windowWidth: CGFloat,
        isSidebarVisible: Bool
    ) -> CGFloat {
        let sidebarWidth = isSidebarVisible ? WindowChromeLayout.sidebarWidth : 0
        let availableForDrawer = windowWidth - sidebarWidth - drawerDividerWidth - minimumWebContentWidth
        return max(0, min(clampDrawerWidth(requested), availableForDrawer))
    }

    /// Returns `true` when the window is narrow enough that opening the right drawer auto-collapses the left sidebar.
    public static func shouldAutoCollapseSidebar(windowWidth: CGFloat) -> Bool {
        windowWidth < autoCollapseSidebarThreshold
    }
}
