import Foundation

/// Canonical team entry used for zero-network stream matching across ESPN and Kalshi tricodes.
public struct CanonicalTeamEntry: Equatable, Hashable, Sendable {
    public let league: SportsLeague
    public let espnTricode: String
    public let kalshiTricode: String
    public let city: String
    public let nickname: String
    public let fullName: String
    public let aliases: [String]
    public let isAmbiguousNickname: Bool

    public init(
        league: SportsLeague,
        espnTricode: String,
        kalshiTricode: String? = nil,
        city: String,
        nickname: String,
        aliases: [String] = [],
        isAmbiguousNickname: Bool = false
    ) {
        self.league = league
        self.espnTricode = espnTricode.uppercased()
        self.kalshiTricode = (kalshiTricode ?? espnTricode).uppercased()
        self.city = city
        self.nickname = nickname
        self.fullName = "\(city) \(nickname)"
        self.aliases = aliases
        self.isAmbiguousNickname = isAmbiguousNickname
    }
}

/// Extracted game/slate clue parsed from a streaming service's URL path.
public struct URLSportMatchHint: Equatable, Hashable, Sendable {
    public let league: SportsLeague
    public let awayTeamCode: String?
    public let homeTeamCode: String?
    public let externalEventID: String?
    public let liveSlateLabel: String?

    public init(
        league: SportsLeague,
        awayTeamCode: String? = nil,
        homeTeamCode: String? = nil,
        externalEventID: String? = nil,
        liveSlateLabel: String? = nil
    ) {
        self.league = league
        self.awayTeamCode = awayTeamCode
        self.homeTeamCode = homeTeamCode
        self.externalEventID = externalEventID
        self.liveSlateLabel = liveSlateLabel
    }
}

/// Pure Foundation, sub-millisecond sports entity & broadcast matcher with strict ambiguous-nickname guards.
public enum SportsEntityMatcher {
    private static let ambiguousNicknames: Set<String> = [
        "cardinals", "giants", "rangers", "kings", "jets", "panthers",
        "lions", "bears", "bulls", "heat", "magic", "jazz", "wild",
        "stars", "suns", "nets", "reds", "cubs", "rays"
    ]

    public static let allTeams: [CanonicalTeamEntry] = nflTeams + nbaTeams + mlbTeams + nhlTeams

    // MARK: - Canonical Lexicons (NFL 32, NBA 30, MLB 30, NHL 32)

    public static let nflTeams: [CanonicalTeamEntry] = [
        CanonicalTeamEntry(league: .nfl, espnTricode: "ARI", city: "Arizona", nickname: "Cardinals", aliases: ["az cardinals"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nfl, espnTricode: "ATL", city: "Atlanta", nickname: "Falcons"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "BAL", city: "Baltimore", nickname: "Ravens"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "BUF", city: "Buffalo", nickname: "Bills"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "CAR", city: "Carolina", nickname: "Panthers", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nfl, espnTricode: "CHI", city: "Chicago", nickname: "Bears", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nfl, espnTricode: "CIN", city: "Cincinnati", nickname: "Bengals"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "CLE", city: "Cleveland", nickname: "Browns"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "DAL", city: "Dallas", nickname: "Cowboys"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "DEN", city: "Denver", nickname: "Broncos"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "DET", city: "Detroit", nickname: "Lions", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nfl, espnTricode: "GB", kalshiTricode: "GB", city: "Green Bay", nickname: "Packers", aliases: ["gnb"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "HOU", city: "Houston", nickname: "Texans"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "IND", city: "Indianapolis", nickname: "Colts", aliases: ["indy colts"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "JAX", kalshiTricode: "JAC", city: "Jacksonville", nickname: "Jaguars", aliases: ["jac", "jags"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "KC", kalshiTricode: "KC", city: "Kansas City", nickname: "Chiefs", aliases: ["kcc"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "LV", kalshiTricode: "LV", city: "Las Vegas", nickname: "Raiders", aliases: ["lvr", "oakland raiders"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "LAC", city: "Los Angeles", nickname: "Chargers", aliases: ["la chargers"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "LAR", kalshiTricode: "LA", city: "Los Angeles", nickname: "Rams", aliases: ["la rams", "la"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "MIA", city: "Miami", nickname: "Dolphins"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "MIN", city: "Minnesota", nickname: "Vikings"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "NE", kalshiTricode: "NE", city: "New England", nickname: "Patriots", aliases: ["nwe", "pats"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "NO", kalshiTricode: "NO", city: "New Orleans", nickname: "Saints", aliases: ["nor"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "NYG", city: "New York", nickname: "Giants", aliases: ["ny giants"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nfl, espnTricode: "NYJ", city: "New York", nickname: "Jets", aliases: ["ny jets"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nfl, espnTricode: "PHI", city: "Philadelphia", nickname: "Eagles", aliases: ["philly eagles"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "PIT", city: "Pittsburgh", nickname: "Steelers"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "SF", kalshiTricode: "SF", city: "San Francisco", nickname: "49ers", aliases: ["sfo", "niners"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "SEA", city: "Seattle", nickname: "Seahawks"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "TB", kalshiTricode: "TB", city: "Tampa Bay", nickname: "Buccaneers", aliases: ["tbb", "bucs"]),
        CanonicalTeamEntry(league: .nfl, espnTricode: "TEN", city: "Tennessee", nickname: "Titans"),
        CanonicalTeamEntry(league: .nfl, espnTricode: "WAS", kalshiTricode: "WSH", city: "Washington", nickname: "Commanders", aliases: ["wsh"])
    ]

    public static let nbaTeams: [CanonicalTeamEntry] = [
        CanonicalTeamEntry(league: .nba, espnTricode: "ATL", city: "Atlanta", nickname: "Hawks"),
        CanonicalTeamEntry(league: .nba, espnTricode: "BOS", city: "Boston", nickname: "Celtics"),
        CanonicalTeamEntry(league: .nba, espnTricode: "BKN", city: "Brooklyn", nickname: "Nets", aliases: ["brk"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nba, espnTricode: "CHA", city: "Charlotte", nickname: "Hornets"),
        CanonicalTeamEntry(league: .nba, espnTricode: "CHI", city: "Chicago", nickname: "Bulls", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nba, espnTricode: "CLE", city: "Cleveland", nickname: "Cavaliers", aliases: ["cavs"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "DAL", city: "Dallas", nickname: "Mavericks", aliases: ["mavs"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "DEN", city: "Denver", nickname: "Nuggets"),
        CanonicalTeamEntry(league: .nba, espnTricode: "DET", city: "Detroit", nickname: "Pistons"),
        CanonicalTeamEntry(league: .nba, espnTricode: "GS", kalshiTricode: "GSW", city: "Golden State", nickname: "Warriors", aliases: ["gsw", "dubs"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "HOU", city: "Houston", nickname: "Rockets"),
        CanonicalTeamEntry(league: .nba, espnTricode: "IND", city: "Indiana", nickname: "Pacers"),
        CanonicalTeamEntry(league: .nba, espnTricode: "LAC", city: "LA", nickname: "Clippers", aliases: ["los angeles clippers"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "LAL", city: "Los Angeles", nickname: "Lakers", aliases: ["la lakers"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "MEM", city: "Memphis", nickname: "Grizzlies", aliases: ["grizz"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "MIA", city: "Miami", nickname: "Heat", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nba, espnTricode: "MIL", city: "Milwaukee", nickname: "Bucks"),
        CanonicalTeamEntry(league: .nba, espnTricode: "MIN", city: "Minnesota", nickname: "Timberwolves", aliases: ["wolves"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "NO", kalshiTricode: "NOP", city: "New Orleans", nickname: "Pelicans", aliases: ["nop", "pels"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "NY", kalshiTricode: "NYK", city: "New York", nickname: "Knicks", aliases: ["nyk", "ny knicks"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "OKC", city: "Oklahoma City", nickname: "Thunder"),
        CanonicalTeamEntry(league: .nba, espnTricode: "ORL", city: "Orlando", nickname: "Magic", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nba, espnTricode: "PHI", city: "Philadelphia", nickname: "76ers", aliases: ["sixers"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "PHX", city: "Phoenix", nickname: "Suns", aliases: ["pho"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nba, espnTricode: "POR", city: "Portland", nickname: "Trail Blazers", aliases: ["blazers"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "SA", kalshiTricode: "SAS", city: "San Antonio", nickname: "Spurs", aliases: ["sas"]),
        CanonicalTeamEntry(league: .nba, espnTricode: "SAC", city: "Sacramento", nickname: "Kings", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nba, espnTricode: "TOR", city: "Toronto", nickname: "Raptors"),
        CanonicalTeamEntry(league: .nba, espnTricode: "UTAH", kalshiTricode: "UTA", city: "Utah", nickname: "Jazz", aliases: ["uta"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nba, espnTricode: "WSH", kalshiTricode: "WAS", city: "Washington", nickname: "Wizards", aliases: ["was"])
    ]

    public static let mlbTeams: [CanonicalTeamEntry] = [
        CanonicalTeamEntry(league: .mlb, espnTricode: "ARI", kalshiTricode: "AZ", city: "Arizona", nickname: "Diamondbacks", aliases: ["az", "d-backs", "dbacks"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "ATL", city: "Atlanta", nickname: "Braves"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "BAL", city: "Baltimore", nickname: "Orioles", aliases: ["o's"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "BOS", city: "Boston", nickname: "Red Sox"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "CHC", city: "Chicago", nickname: "Cubs", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .mlb, espnTricode: "CHW", kalshiTricode: "CWS", city: "Chicago", nickname: "White Sox", aliases: ["cws"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "CIN", city: "Cincinnati", nickname: "Reds", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .mlb, espnTricode: "CLE", city: "Cleveland", nickname: "Guardians"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "COL", city: "Colorado", nickname: "Rockies"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "DET", city: "Detroit", nickname: "Tigers"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "HOU", city: "Houston", nickname: "Astros"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "KC", kalshiTricode: "KCR", city: "Kansas City", nickname: "Royals", aliases: ["kcr"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "LAA", city: "Los Angeles", nickname: "Angels", aliases: ["la angels"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "LAD", city: "Los Angeles", nickname: "Dodgers", aliases: ["la dodgers"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "MIA", city: "Miami", nickname: "Marlins"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "MIL", city: "Milwaukee", nickname: "Brewers"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "MIN", city: "Minnesota", nickname: "Twins"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "NYM", city: "New York", nickname: "Mets", aliases: ["ny mets"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "NYY", city: "New York", nickname: "Yankees", aliases: ["ny yankees"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "ATH", kalshiTricode: "OAK", city: "Athletics", nickname: "Athletics", aliases: ["oak", "oakland athletics", "a's"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "PHI", city: "Philadelphia", nickname: "Phillies"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "PIT", city: "Pittsburgh", nickname: "Pirates"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "SD", kalshiTricode: "SDP", city: "San Diego", nickname: "Padres", aliases: ["sdp"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "SEA", city: "Seattle", nickname: "Mariners"),
        CanonicalTeamEntry(league: .mlb, espnTricode: "SF", kalshiTricode: "SFO", city: "San Francisco", nickname: "Giants", aliases: ["sfo", "sf giants"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .mlb, espnTricode: "STL", city: "St. Louis", nickname: "Cardinals", aliases: ["saint louis cardinals", "st louis cardinals"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .mlb, espnTricode: "TB", kalshiTricode: "TBR", city: "Tampa Bay", nickname: "Rays", aliases: ["tbr"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .mlb, espnTricode: "TEX", city: "Texas", nickname: "Rangers", aliases: ["texas rangers"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .mlb, espnTricode: "TOR", city: "Toronto", nickname: "Blue Jays", aliases: ["jays"]),
        CanonicalTeamEntry(league: .mlb, espnTricode: "WSH", kalshiTricode: "WAS", city: "Washington", nickname: "Nationals", aliases: ["was", "nats"])
    ]

    public static let nhlTeams: [CanonicalTeamEntry] = [
        CanonicalTeamEntry(league: .nhl, espnTricode: "ANA", city: "Anaheim", nickname: "Ducks"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "BOS", city: "Boston", nickname: "Bruins"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "BUF", city: "Buffalo", nickname: "Sabres"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "CAR", city: "Carolina", nickname: "Hurricanes", aliases: ["canes"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "CBJ", city: "Columbus", nickname: "Blue Jackets"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "CGY", city: "Calgary", nickname: "Flames"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "CHI", city: "Chicago", nickname: "Blackhawks"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "COL", city: "Colorado", nickname: "Avalanche", aliases: ["avs"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "DAL", city: "Dallas", nickname: "Stars", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nhl, espnTricode: "DET", city: "Detroit", nickname: "Red Wings"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "EDM", city: "Edmonton", nickname: "Oilers"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "FLA", city: "Florida", nickname: "Panthers", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nhl, espnTricode: "LA", kalshiTricode: "LAK", city: "Los Angeles", nickname: "Kings", aliases: ["lak", "la kings"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nhl, espnTricode: "MIN", city: "Minnesota", nickname: "Wild", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nhl, espnTricode: "MTL", city: "Montreal", nickname: "Canadiens", aliases: ["habs"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "NJ", kalshiTricode: "NJD", city: "New Jersey", nickname: "Devils", aliases: ["njd"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "NSH", city: "Nashville", nickname: "Predators", aliases: ["preds"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "NYI", city: "New York", nickname: "Islanders", aliases: ["isles"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "NYR", city: "New York", nickname: "Rangers", aliases: ["ny rangers"], isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nhl, espnTricode: "OTT", city: "Ottawa", nickname: "Senators", aliases: ["sens"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "PHI", city: "Philadelphia", nickname: "Flyers"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "PIT", city: "Pittsburgh", nickname: "Penguins", aliases: ["pens"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "SEA", city: "Seattle", nickname: "Kraken"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "SJ", kalshiTricode: "SJS", city: "San Jose", nickname: "Sharks", aliases: ["sjs"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "STL", city: "St. Louis", nickname: "Blues"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "TB", kalshiTricode: "TBL", city: "Tampa Bay", nickname: "Lightning", aliases: ["tbl", "bolts"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "TOR", city: "Toronto", nickname: "Maple Leafs", aliases: ["leafs"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "UTAH", kalshiTricode: "UTA", city: "Utah", nickname: "Mammoth", aliases: ["uta", "utah hockey club"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "VAN", city: "Vancouver", nickname: "Canucks"),
        CanonicalTeamEntry(league: .nhl, espnTricode: "VGK", city: "Vegas", nickname: "Golden Knights", aliases: ["las vegas golden knights"]),
        CanonicalTeamEntry(league: .nhl, espnTricode: "WPG", city: "Winnipeg", nickname: "Jets", isAmbiguousNickname: true),
        CanonicalTeamEntry(league: .nhl, espnTricode: "WSH", kalshiTricode: "WAS", city: "Washington", nickname: "Capitals", aliases: ["was", "caps"])
    ]

    private static let teamsByLeague: [SportsLeague: [CanonicalTeamEntry]] = [
        .nfl: nflTeams,
        .nba: nbaTeams,
        .mlb: mlbTeams,
        .nhl: nhlTeams
    ]

    private static let knownBroadcastNetworks: [(canonical: String, patterns: [String])] = [
        ("NFL Network", ["nfl network", "nflnet"]),
        ("NBA TV", ["nba tv", "nbatv"]),
        ("MLB Network", ["mlb network", "mlbnet"]),
        ("NHL Network", ["nhl network", "nhlnet"]),
        ("Prime Video", ["prime video", "amazon prime"]),
        ("ESPN+", ["espn+", "espn plus"]),
        ("ESPN2", ["espn2"]),
        ("ESPN", ["espn"]),
        ("Peacock", ["peacock"]),
        ("Paramount+", ["paramount+", "paramount plus"]),
        ("CBS", ["cbs"]),
        ("FOX", ["fox"]),
        ("NBC", ["nbc"]),
        ("ABC", ["abc"]),
        ("TNT", ["tnt"]),
        ("TBS", ["tbs"]),
        ("FS1", ["fs1"])
    ]

    private static let slateTriggers: [(phrase: String, league: SportsLeague, label: String)] = [
        ("nfl redzone", .nfl, "NFL RedZone"),
        ("redzone", .nfl, "NFL RedZone"),
        ("red zone", .nfl, "NFL RedZone"),
        ("mlb big inning", .mlb, "MLB Big Inning"),
        ("big inning", .mlb, "MLB Big Inning"),
        ("nba crunchtime", .nba, "NBA CrunchTime"),
        ("nba crunch time", .nba, "NBA CrunchTime"),
        ("crunchtime", .nba, "NBA CrunchTime"),
        ("nhl frozen frenzy", .nhl, "NHL Frozen Frenzy"),
        ("frozen frenzy", .nhl, "NHL Frozen Frenzy"),
        ("goal line", .nfl, "Goal Line")
    ]

    // MARK: - Public API

    /// Normalizes an ESPN or Kalshi team code into the canonical ESPN tricode for the given league.
    public static func canonicalESPNCode(_ rawCode: String, league: SportsLeague) -> String {
        let cleaned = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let teams = teamsByLeague[league] else { return cleaned }
        for team in teams {
            if team.espnTricode == cleaned || team.kalshiTricode == cleaned {
                return team.espnTricode
            }
            if team.aliases.contains(where: { $0.uppercased() == cleaned }) {
                return team.espnTricode
            }
        }
        return cleaned
    }

    /// Normalizes a team code or name fragment into the canonical team entry in a league.
    public static func resolveTeam(_ raw: String, in league: SportsLeague) -> CanonicalTeamEntry? {
        let normalized = normalizeText(raw)
        guard !normalized.isEmpty, let teams = teamsByLeague[league] else { return nil }
        let upper = normalized.uppercased()
        for team in teams {
            if team.espnTricode == upper || team.kalshiTricode == upper {
                return team
            }
            if normalizeText(team.fullName) == normalized || normalizeText(team.nickname) == normalized {
                return team
            }
            if team.aliases.contains(where: { normalizeText($0) == normalized }) {
                return team
            }
        }
        return nil
    }

    /// Extracts direct URL game or slate hints from NFL+, MLB.TV, NBA League Pass, or Apple TV+ routes.
    public static func extractURLMatchHint(from url: URL) -> URLSportMatchHint? {
        guard let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let segments = url.path.lowercased().split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !segments.isEmpty else { return nil }

        // NFL+: /plus/live/nfl-redzone, /plus/games/<away>-at-<home>
        if host == "nfl.com" || host.hasSuffix(".nfl.com") {
            if segments.contains(where: { $0.contains("redzone") }) {
                return URLSportMatchHint(league: .nfl, liveSlateLabel: "NFL RedZone")
            }
            if segments.count >= 3 && segments[0] == "plus" && segments[1] == "games" {
                let slug = segments[2]
                if let pair = splitSlugPair(slug, league: .nfl) {
                    return URLSportMatchHint(league: .nfl, awayTeamCode: pair.0, homeTeamCode: pair.1)
                }
            }
        }

        // MLB.TV: /tv/g<gamePk> or /tv/games/<gamePk>
        if host == "mlb.com" || host.hasSuffix(".mlb.com") {
            if segments.count >= 2 && segments[0] == "tv" {
                let target = segments[1]
                if target == "games", segments.count >= 3 {
                    let digits = segments[2].filter(\.isNumber)
                    if !digits.isEmpty {
                        return URLSportMatchHint(league: .mlb, externalEventID: digits)
                    }
                } else if target.hasPrefix("g") {
                    let digits = String(target.dropFirst()).filter(\.isNumber)
                    if !digits.isEmpty {
                        return URLSportMatchHint(league: .mlb, externalEventID: digits)
                    }
                }
            }
        }

        // NBA: /game/<away>-vs-<home>-<id> or /watch/event/...
        if host == "nba.com" || host.hasSuffix(".nba.com") {
            if let idx = segments.firstIndex(of: "game"), idx + 1 < segments.count {
                let slug = segments[idx + 1]
                if let pair = splitSlugPair(slug, league: .nba) {
                    return URLSportMatchHint(league: .nba, awayTeamCode: pair.0, homeTeamCode: pair.1)
                }
            }
        }

        // Apple TV+: /sporting-event/<teamA>-at-<teamB> or /<locale>/sporting-event/<teamA>-at-<teamB>
        if host == "tv.apple.com" {
            if let idx = segments.firstIndex(of: "sporting-event"), idx + 1 < segments.count {
                let slug = segments[idx + 1]
                for league in SportsLeague.allCases {
                    if let pair = splitSlugPair(slug, league: league) {
                        return URLSportMatchHint(league: league, awayTeamCode: pair.0, homeTeamCode: pair.1)
                    }
                }
            }
        }

        return nil
    }

    /// Extracts an explicit broadcast network token (`CBS`, `NBC`, `TNT`, etc.) from a stream title or URL.
    public static func extractBroadcastNetwork(from title: String, serviceID: String? = nil) -> String? {
        let lower = " \(normalizeText(title)) "
        for entry in knownBroadcastNetworks {
            for pattern in entry.patterns {
                if containsWholePhrase(lower, phrase: pattern) {
                    return entry.canonical
                }
            }
        }
        switch serviceID {
        case "peacock": return "Peacock"
        case "paramount": return "Paramount+"
        case "primevideo": return "Prime Video"
        default: return nil
        }
    }

    /// Detects whip-around / multi-game live slates such as NFL RedZone, MLB Big Inning, NBA CrunchTime, or NHL Frozen Frenzy.
    public static func detectLiveSlate(from title: String, url: URL) -> StreamSportContext? {
        if let urlHint = extractURLMatchHint(from: url), let slate = urlHint.liveSlateLabel {
            return .liveSlate(league: urlHint.league, label: slate)
        }
        let lowerTitle = normalizeText(title)
        for trigger in slateTriggers where containsWholePhrase(" \(lowerTitle) ", phrase: trigger.phrase) {
            // Avoid matching generic "redzone" / "goal line" on random non-sports YouTube channels unless paired with NFL/sports context.
            if trigger.phrase == "redzone" || trigger.phrase == "red zone" || trigger.phrase == "goal line" {
                let hasSportsCue = lowerTitle.contains("nfl")
                    || lowerTitle.contains("football")
                    || url.host?.lowercased().contains("nfl") == true
                    || url.host?.lowercased() == "tv.youtube.com"
                guard hasSportsCue else { continue }
            }
            return .liveSlate(league: trigger.league, label: trigger.label)
        }
        return nil
    }

    /// Matches a passive `StreamSignal` against current `LiveGame` entries without any network I/O.
    public static func match(signal: StreamSignal, games: [LiveGame]) -> StreamSportContext {
        if signal.isAuthOrBrowse {
            return .none
        }

        let ctx = signal.streamContext
        let prioritizedTitles = deduplicatedNonEmpty([
            ctx.mediaSessionTitle,
            ctx.ogTitle,
            ctx.headingHint,
            signal.title
        ])
        let slateCandidates = deduplicatedNonEmpty([
            ctx.mediaSessionTitle,
            ctx.ogTitle,
            ctx.headingHint,
            signal.title,
            ctx.mediaSessionArtist
        ])

        // 1. Direct URL game / slate clues (NFL+, MLB.TV, NBA, Apple TV+)
        if let hint = extractURLMatchHint(from: signal.url) {
            if let slate = hint.liveSlateLabel {
                return .liveSlate(league: hint.league, label: slate)
            }
            if let eventID = hint.externalEventID,
               let byID = games.first(where: { $0.league == hint.league && $0.id == eventID }) {
                return .matchedGame(
                    gameID: byID.id,
                    league: hint.league,
                    confidence: .high,
                    sourceLabel: "\(byID.away.abbreviation) @ \(byID.home.abbreviation)"
                )
            }
            if let awayCode = hint.awayTeamCode, let homeCode = hint.homeTeamCode,
               let matched = findGame(league: hint.league, teamA: awayCode, teamB: homeCode, in: games) {
                return .matchedGame(
                    gameID: matched.id,
                    league: hint.league,
                    confidence: .high,
                    sourceLabel: "\(matched.away.abbreviation) @ \(matched.home.abbreviation)"
                )
            }
        }

        // 2. Whip-around slates (RedZone, Big Inning, CrunchTime, Frozen Frenzy)
        for candidate in slateCandidates {
            if let slate = detectLiveSlate(from: candidate, url: signal.url) {
                return slate
            }
        }

        // 3. Explicit "Team A vs / at / @ Team B" or multi-team matchup parsing
        for candidate in prioritizedTitles {
            if let matchup = matchPairInTitle(candidate, games: games) {
                return matchup
            }
        }

        // 4. Explicit league keyword + unambiguous single-team + active live game
        let leagueTextCandidates = deduplicatedNonEmpty([
            ctx.mediaSessionTitle,
            ctx.ogTitle,
            ctx.headingHint,
            signal.title,
            ctx.mediaSessionAlbum
        ])
        let explicitLeagueOverride = leagueTextCandidates
            .lazy
            .compactMap { detectExplicitLeagueKeyword(in: normalizeText($0)) }
            .first
            ?? (!ctx.mediaSessionArtist.isEmpty ? detectExplicitLeagueKeyword(in: normalizeText(ctx.mediaSessionArtist)) : nil)
            ?? leagueFromDedicatedService(signal.serviceID)

        for candidate in leagueTextCandidates {
            if let leagueAndTeam = matchExplicitLeagueSingleTeam(
                text: candidate,
                serviceID: signal.serviceID,
                explicitLeagueOverride: explicitLeagueOverride,
                games: games
            ) {
                return leagueAndTeam
            }
        }

        // 5. Broadcast network fallback (mediaSessionArtist -> mediaSessionAlbum -> title -> ogTitle -> serviceID)
        let networkCandidates = deduplicatedNonEmpty([
            ctx.mediaSessionArtist,
            ctx.mediaSessionAlbum,
            signal.title,
            ctx.ogTitle
        ])
        let extractedNetwork = networkCandidates
            .lazy
            .compactMap { extractBroadcastNetwork(from: $0, serviceID: nil) }
            .first
            ?? extractBroadcastNetwork(from: "", serviceID: signal.serviceID)

        if let network = extractedNetwork {
            let matching = games.filter { game in
                (game.status == .live || game.status == .halftime || game.status == .pregame) &&
                game.broadcasts.contains { normalizeBroadcast($0) == normalizeBroadcast(network) }
            }
            if matching.count == 1, let single = matching.first {
                return .matchedGame(
                    gameID: single.id,
                    league: single.league,
                    confidence: .medium,
                    sourceLabel: "Auto · \(network)"
                )
            } else if matching.count > 1 {
                let leagues = Set(matching.map(\.league))
                let inferredLeague = leagues.count == 1 ? leagues.first : nil
                return .networkCandidates(
                    network: network,
                    league: inferredLeague,
                    gameIDs: matching.map(\.id)
                )
            }
        }

        return .none
    }

    // MARK: - Private Matching Helpers

    private static func deduplicatedNonEmpty(_ items: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private static func matchPairInTitle(_ rawTitle: String, games: [LiveGame]) -> StreamSportContext? {
        let normalized = normalizeText(rawTitle)
        guard !normalized.isEmpty else { return nil }

        // Check explicit separators: " vs ", " vs. ", " at ", " @ "
        let separators = [" vs. ", " vs ", " at ", " @ "]
        for separator in separators {
            guard let range = normalized.range(of: separator) else { continue }
            let leftText = String(normalized[..<range.lowerBound])
            let rightText = String(normalized[range.upperBound...])
            let explicitLeague = detectExplicitLeagueKeyword(in: normalized)

            let candidateLeagues = explicitLeague.map { [$0] } ?? SportsLeague.allCases
            for league in candidateLeagues {
                guard let teams = teamsByLeague[league] else { continue }
                let leftTeam = findTeamSuffix(in: leftText, teams: teams)
                let rightTeam = findTeamPrefix(in: rightText, teams: teams)
                if let leftTeam, let rightTeam, leftTeam.espnTricode != rightTeam.espnTricode {
                    if let matched = findGame(league: league, teamA: leftTeam.espnTricode, teamB: rightTeam.espnTricode, in: games) {
                        return .matchedGame(
                            gameID: matched.id,
                            league: league,
                            confidence: .high,
                            sourceLabel: "\(matched.away.abbreviation) @ \(matched.home.abbreviation)"
                        )
                    }
                }
            }
        }

        // Fallback: scan for two distinct teams from the same league in the title (requiring either explicit league or full names/tricodes).
        let explicitLeague = detectExplicitLeagueKeyword(in: normalized)
        let candidateLeagues = explicitLeague.map { [$0] } ?? SportsLeague.allCases
        for league in candidateLeagues {
            guard let teams = teamsByLeague[league] else { continue }
            var found: [CanonicalTeamEntry] = []
            for team in teams where titleContainsTeam(normalized, team: team, allowBareAmbiguousNickname: false) {
                if !found.contains(where: { $0.espnTricode == team.espnTricode }) {
                    found.append(team)
                }
            }
            if found.count >= 2 {
                for i in 0..<found.count {
                    for j in (i + 1)..<found.count {
                        if let matched = findGame(league: league, teamA: found[i].espnTricode, teamB: found[j].espnTricode, in: games) {
                            return .matchedGame(
                                gameID: matched.id,
                                league: league,
                                confidence: .high,
                                sourceLabel: "\(matched.away.abbreviation) @ \(matched.home.abbreviation)"
                            )
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func matchExplicitLeagueSingleTeam(
        text: String,
        serviceID: String?,
        explicitLeagueOverride: SportsLeague?,
        games: [LiveGame]
    ) -> StreamSportContext? {
        let normalized = normalizeText(text)
        let explicitLeague = detectExplicitLeagueKeyword(in: normalized)
            ?? explicitLeagueOverride
            ?? leagueFromDedicatedService(serviceID)
        guard let league = explicitLeague, let teams = teamsByLeague[league] else {
            return nil
        }

        let liveGames = games.filter { $0.league == league && ($0.status == .live || $0.status == .halftime) }
        guard !liveGames.isEmpty else { return nil }

        for team in teams {
            let allowsBare = !team.isAmbiguousNickname && !ambiguousNicknames.contains(team.nickname.lowercased())
            // With explicit league keyword, even ambiguous nicknames can match ONLY if an active live game exists for that league & team.
            let matchedByFullOrAlias = titleContainsTeam(normalized, team: team, allowBareAmbiguousNickname: explicitLeague != nil && !liveGames.isEmpty)
            guard matchedByFullOrAlias || (allowsBare && containsWholePhrase(" \(normalized) ", phrase: team.nickname.lowercased())) else {
                continue
            }
            if let game = liveGames.first(where: {
                canonicalESPNCode($0.away.abbreviation, league: league) == team.espnTricode ||
                canonicalESPNCode($0.home.abbreviation, league: league) == team.espnTricode
            }) {
                return .matchedGame(
                    gameID: game.id,
                    league: league,
                    confidence: .medium,
                    sourceLabel: "\(game.away.abbreviation) @ \(game.home.abbreviation)"
                )
            }
        }
        return nil
    }

    private static func findGame(league: SportsLeague, teamA: String, teamB: String, in games: [LiveGame]) -> LiveGame? {
        let normA = canonicalESPNCode(teamA, league: league)
        let normB = canonicalESPNCode(teamB, league: league)
        return games.first { game in
            guard game.league == league else { return false }
            let away = canonicalESPNCode(game.away.abbreviation, league: league)
            let home = canonicalESPNCode(game.home.abbreviation, league: league)
            return (away == normA && home == normB) || (away == normB && home == normA)
        }
    }

    private static func findTeamSuffix(in text: String, teams: [CanonicalTeamEntry]) -> CanonicalTeamEntry? {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return nil }
        for count in stride(from: min(3, words.count), through: 1, by: -1) {
            let candidate = words.suffix(count).joined(separator: " ")
            if let team = matchTeamPhrase(candidate, teams: teams, allowAmbiguousNickname: true) {
                return team
            }
        }
        return nil
    }

    private static func findTeamPrefix(in text: String, teams: [CanonicalTeamEntry]) -> CanonicalTeamEntry? {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return nil }
        for count in stride(from: min(3, words.count), through: 1, by: -1) {
            let candidate = words.prefix(count).joined(separator: " ")
            if let team = matchTeamPhrase(candidate, teams: teams, allowAmbiguousNickname: true) {
                return team
            }
        }
        return nil
    }

    private static func matchTeamPhrase(_ phrase: String, teams: [CanonicalTeamEntry], allowAmbiguousNickname: Bool) -> CanonicalTeamEntry? {
        let norm = normalizeText(phrase)
        guard !norm.isEmpty else { return nil }
        let upper = norm.uppercased()
        for team in teams {
            if team.espnTricode == upper || team.kalshiTricode == upper {
                return team
            }
            if normalizeText(team.fullName) == norm {
                return team
            }
            if team.aliases.contains(where: { normalizeText($0) == norm }) {
                return team
            }
            if normalizeText(team.nickname) == norm {
                if allowAmbiguousNickname || !team.isAmbiguousNickname {
                    return team
                }
            }
        }
        return nil
    }

    private static func titleContainsTeam(_ normalizedTitle: String, team: CanonicalTeamEntry, allowBareAmbiguousNickname: Bool) -> Bool {
        let padded = " \(normalizedTitle) "
        if containsWholePhrase(padded, phrase: normalizeText(team.fullName)) {
            return true
        }
        for alias in team.aliases {
            let normAlias = normalizeText(alias)
            if normAlias.count >= 3 && containsWholePhrase(padded, phrase: normAlias) {
                return true
            }
        }
        let nick = normalizeText(team.nickname)
        if !team.isAmbiguousNickname || allowBareAmbiguousNickname {
            if containsWholePhrase(padded, phrase: nick) {
                return true
            }
        }
        if containsWholePhrase(padded, phrase: team.espnTricode.lowercased()) && team.espnTricode.count >= 3 {
            return true
        }
        return false
    }

    private static func splitSlugPair(_ slug: String, league: SportsLeague) -> (String, String)? {
        let parts = slug.lowercased().split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        for sep in ["at", "vs"] {
            if let sepIdx = parts.firstIndex(of: sep), sepIdx > 0, sepIdx + 1 < parts.count {
                let leftParts = Array(parts[..<sepIdx])
                var rightParts = Array(parts[(sepIdx + 1)...])
                // Strip trailing numeric game ID if present (e.g. `lal-vs-bos-0022400123`)
                if let last = rightParts.last, last.allSatisfy(\.isNumber), rightParts.count > 1 {
                    rightParts.removeLast()
                }
                if let leftTeam = resolveSlugTeam(leftParts, league: league),
                   let rightTeam = resolveSlugTeam(rightParts, league: league) {
                    return (leftTeam.espnTricode, rightTeam.espnTricode)
                }
            }
        }
        return nil
    }

    private static func resolveSlugTeam(_ tokens: [String], league: SportsLeague) -> CanonicalTeamEntry? {
        guard let teams = teamsByLeague[league], !tokens.isEmpty else { return nil }
        let joined = tokens.joined(separator: " ")
        if let exact = matchTeamPhrase(joined, teams: teams, allowAmbiguousNickname: true) {
            return exact
        }
        if let last = tokens.last, let byLast = matchTeamPhrase(last, teams: teams, allowAmbiguousNickname: true) {
            return byLast
        }
        return nil
    }

    private static func detectExplicitLeagueKeyword(in normalized: String) -> SportsLeague? {
        let padded = " \(normalized) "
        if containsWholePhrase(padded, phrase: "nfl") || containsWholePhrase(padded, phrase: "football") {
            return .nfl
        }
        if containsWholePhrase(padded, phrase: "nba") || containsWholePhrase(padded, phrase: "basketball") {
            return .nba
        }
        if containsWholePhrase(padded, phrase: "mlb") || containsWholePhrase(padded, phrase: "baseball") {
            return .mlb
        }
        if containsWholePhrase(padded, phrase: "nhl") || containsWholePhrase(padded, phrase: "hockey") {
            return .nhl
        }
        return nil
    }

    private static func leagueFromDedicatedService(_ serviceID: String?) -> SportsLeague? {
        switch serviceID {
        case "nfl": return .nfl
        case "nba": return .nba
        case "mlb": return .mlb
        default: return nil
        }
    }

    private static func normalizeText(_ raw: String) -> String {
        var result = ""
        result.reserveCapacity(raw.count)
        var lastWasSpace = true
        for scalar in raw.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "@" || scalar == "+" {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        if result.hasSuffix(" ") {
            result.removeLast()
        }
        return result
    }

    private static func normalizeBroadcast(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "+", with: "plus")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func containsWholePhrase(_ paddedHaystack: String, phrase: String) -> Bool {
        paddedHaystack.contains(" \(phrase) ")
    }
}

/// Pure 90-second ad-break hysteresis preserving active game context across brief commercial breaks.
public struct StreamContextHysteresis: Sendable {
    public static let defaultRetentionInterval: TimeInterval = 90

    private struct Entry: Equatable, Sendable {
        let context: StreamSportContext
        let confirmedAt: Date
    }

    private var entriesByTab: [UUID: Entry] = [:]
    public let retentionInterval: TimeInterval

    public init(retentionInterval: TimeInterval = StreamContextHysteresis.defaultRetentionInterval) {
        self.retentionInterval = max(0, retentionInterval)
    }

    /// Resolves the effective `StreamSportContext` for `signal` given `rawContext` at `now`.
    /// Clears immediately on auth/browse routes, new game matches, or after `retentionInterval` (90s) expires.
    public mutating func resolve(
        signal: StreamSignal,
        rawContext: StreamSportContext,
        at now: Date = Date()
    ) -> StreamSportContext {
        if signal.isAuthOrBrowse {
            entriesByTab.removeValue(forKey: signal.tabID)
            return .none
        }

        if rawContext != .none {
            entriesByTab[signal.tabID] = Entry(context: rawContext, confirmedAt: now)
            return rawContext
        }

        if let existing = entriesByTab[signal.tabID] {
            let elapsed = now.timeIntervalSince(existing.confirmedAt)
            if elapsed >= 0 && elapsed <= retentionInterval {
                return existing.context
            }
            entriesByTab.removeValue(forKey: signal.tabID)
        }
        return .none
    }

    public mutating func clear(tabID: UUID) {
        entriesByTab.removeValue(forKey: tabID)
    }

    public mutating func clearAll() {
        entriesByTab.removeAll()
    }
}
