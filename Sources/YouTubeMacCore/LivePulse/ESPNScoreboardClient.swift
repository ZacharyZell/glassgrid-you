import Foundation

/// Supplemental summary details fetched on demand for an active or pinned ESPN game.
public struct ESPNGameSummaryUpdate: Equatable, Sendable {
    public let eventID: String
    public let league: SportsLeague
    public let situation: GameSituation?
    public let awayWinProb: Double?
    public let homeWinProb: Double?
    public let espnWinProbHistory: [WinProbabilityPoint]
    public let spreadSummary: String?
    public let overUnder: Double?
    public let athleteStats: [String: String]
    public let athleteStatsByNameAndTeam: [String: String]
    public let recentPlays: [PlayByPlayEvent]

    public init(
        eventID: String,
        league: SportsLeague,
        situation: GameSituation? = nil,
        awayWinProb: Double? = nil,
        homeWinProb: Double? = nil,
        spreadSummary: String? = nil,
        overUnder: Double? = nil,
        athleteStats: [String: String] = [:],
        athleteStatsByNameAndTeam: [String: String] = [:],
        recentPlays: [PlayByPlayEvent] = [],
        espnWinProbHistory: [WinProbabilityPoint] = []
    ) {
        self.eventID = eventID
        self.league = league
        self.situation = situation
        self.awayWinProb = awayWinProb
        self.homeWinProb = homeWinProb
        self.espnWinProbHistory = espnWinProbHistory
        self.spreadSummary = spreadSummary
        self.overUnder = overUnder
        self.athleteStats = athleteStats
        self.athleteStatsByNameAndTeam = athleteStatsByNameAndTeam
        self.recentPlays = recentPlays
    }
}

public enum ESPNScoreboardError: Error, Equatable, Sendable {
    case invalidURL
    case httpError(Int)
    case decodingFailed
}

/// Cookieless ephemeral client for ESPN's public scoreboard and game summary JSON endpoints.
public actor ESPNScoreboardClient {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: config)
        }
    }

    public func fetchScoreboard(for league: SportsLeague) async throws -> [LiveGame] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.espnSportPath)/\(league.espnLeaguePath)/scoreboard") else {
            throw ESPNScoreboardError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ESPNScoreboardError.httpError(http.statusCode)
        }
        return Self.parseScoreboard(from: data, league: league)
    }

    public func fetchGameSummary(eventID: String, league: SportsLeague) async throws -> ESPNGameSummaryUpdate? {
        let encodedID = eventID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? eventID
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.espnSportPath)/\(league.espnLeaguePath)/summary?event=\(encodedID)") else {
            throw ESPNScoreboardError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ESPNScoreboardError.httpError(http.statusCode)
        }
        return Self.parseSummary(from: data, eventID: eventID, league: league)
    }

    // MARK: - Pure Offline JSON Parsers

    public nonisolated static func parseScoreboard(
        from data: Data,
        league: SportsLeague,
        now: Date = Date()
    ) -> [LiveGame] {
        _ = now
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            return []
        }

        var games: [LiveGame] = []
        games.reserveCapacity(events.count)

        for event in events {
            guard let id = stringValue(event["id"]),
                  let competitions = event["competitions"] as? [[String: Any]],
                  let comp = competitions.first,
                  let competitors = comp["competitors"] as? [[String: Any]] else {
                continue
            }

            let statusObj = (comp["status"] as? [String: Any]) ?? (event["status"] as? [String: Any])
            let typeObj = statusObj?["type"] as? [String: Any]
            let statusName = stringValue(typeObj?["name"]) ?? ""
            let statusState = stringValue(typeObj?["state"]) ?? ""
            let statusDetail = stringValue(typeObj?["shortDetail"])
                ?? stringValue(typeObj?["detail"])
                ?? statusName
            let clock = stringValue(statusObj?["displayClock"])
            let period = intValue(statusObj?["period"])
            let status = mapGameStatus(name: statusName, state: statusState)
            let startTime = parseISO8601Date(stringValue(comp["date"]) ?? stringValue(event["date"]))

            let situationDict = comp["situation"] as? [String: Any]
            let possessionTeamID = stringValue(situationDict?["possession"])

            var awayScore: TeamScore?
            var homeScore: TeamScore?

            if league == .f1 {
                let topTwo = extractF1TopTwo(from: competitors)
                awayScore = topTwo?.away
                homeScore = topTwo?.home
            } else {
                for competitor in competitors {
                    guard let teamObj = competitor["team"] as? [String: Any],
                          let teamID = stringValue(teamObj["id"]) ?? stringValue(competitor["id"]),
                          let abbr = stringValue(teamObj["abbreviation"]) else {
                        continue
                    }
                    let displayName = stringValue(teamObj["displayName"]) ?? abbr
                    let shortName = stringValue(teamObj["shortDisplayName"]) ?? stringValue(teamObj["name"]) ?? abbr
                    let score = intValue(competitor["score"]) ?? 0
                    let records = competitor["records"] as? [[String: Any]]
                    let recordSummary = stringValue(records?.first?["summary"])
                    let isPossession = possessionTeamID != nil && possessionTeamID == teamID
                    let rawRank = intValue((competitor["curatedRank"] as? [String: Any])?["current"])
                    let rank = (rawRank != nil && (1...25).contains(rawRank!)) ? rawRank : nil

                    let teamScore = TeamScore(
                        espnTeamID: teamID,
                        abbreviation: abbr,
                        displayName: displayName,
                        shortName: shortName,
                        score: score,
                        record: recordSummary,
                        isPossession: isPossession,
                        rank: rank
                    )

                    let homeAway = stringValue(competitor["homeAway"])?.lowercased()
                    if homeAway == "away" {
                        awayScore = teamScore
                    } else if homeAway == "home" {
                        homeScore = teamScore
                    } else if awayScore == nil {
                        awayScore = teamScore
                    } else if homeScore == nil {
                        homeScore = teamScore
                    }
                }
            }

            guard let away = awayScore, let home = homeScore else {
                continue
            }

            let broadcasts = extractBroadcasts(from: comp)
            let situation = parseSituation(from: situationDict)

            var spreadSummary: String?
            var overUnder: Double?
            if let oddsList = comp["odds"] as? [[String: Any]], let firstOdds = oddsList.first {
                spreadSummary = stringValue(firstOdds["details"])
                overUnder = doubleValue(firstOdds["overUnder"])
            }

            games.append(
                LiveGame(
                    id: id,
                    league: league,
                    status: status,
                    statusDetail: statusDetail,
                    clock: clock,
                    period: period,
                    startTime: startTime,
                    away: away,
                    home: home,
                    broadcasts: broadcasts,
                    situation: situation,
                    espnAwayWinProb: nil,
                    espnHomeWinProb: nil,
                    spreadSummary: spreadSummary,
                    overUnder: overUnder
                )
            )
        }

        return games
    }

    public nonisolated static func parseSummary(
        from data: Data,
        eventID: String,
        league: SportsLeague
    ) -> ESPNGameSummaryUpdate? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var situationDict = root["situation"] as? [String: Any]
        if situationDict == nil,
           let header = root["header"] as? [String: Any],
           let competitions = header["competitions"] as? [[String: Any]],
           let first = competitions.first {
            situationDict = first["situation"] as? [String: Any]
        }
        let situation = parseSituation(from: situationDict)

        var homeWinProb: Double?
        var awayWinProb: Double?
        var rawWinProbPoints: [WinProbabilityPoint] = []
        var winProbSwingByPlayID: [String: Double] = [:]

        if let winProbs = root["winprobability"] as? [[String: Any]] {
            for (idx, point) in winProbs.enumerated() {
                guard let rawHome = doubleValue(point["homeWinPercentage"]), rawHome.isFinite else {
                    continue
                }
                let normalizedHome = min(1.0, max(0.0, rawHome > 1.0 ? rawHome / 100.0 : rawHome))
                let normalizedAway = 1.0 - normalizedHome
                let playID = stringValue(point["playId"]) ?? stringValue(point["playID"])
                let wp = WinProbabilityPoint(
                    sequence: idx,
                    homeWinProb: normalizedHome,
                    awayWinProb: normalizedAway,
                    playID: playID
                )
                if let prev = rawWinProbPoints.last, let pid = playID, !pid.isEmpty {
                    let swing = abs(wp.homeWinProb - prev.homeWinProb)
                    winProbSwingByPlayID[pid] = max(winProbSwingByPlayID[pid] ?? 0, swing)
                }
                rawWinProbPoints.append(wp)
            }
            if let latest = rawWinProbPoints.last {
                homeWinProb = latest.homeWinProb
                awayWinProb = latest.awayWinProb
            }
        }

        let espnWinProbHistory = downsampleWinProbabilityPoints(rawWinProbPoints, maxCount: 60)

        var spreadSummary: String?
        var overUnder: Double?
        if let pickcenter = root["pickcenter"] as? [[String: Any]], let firstPick = pickcenter.first {
            spreadSummary = stringValue(firstPick["details"])
            overUnder = doubleValue(firstPick["overUnder"])
        }

        var athleteStats: [String: String] = [:]
        var athleteStatsByNameAndTeam: [String: String] = [:]

        if let boxscore = root["boxscore"] as? [String: Any],
           let teamGroups = boxscore["players"] as? [[String: Any]] {
            let parsedBoxscore = Self.parseBoxscoreStats(
                root: root,
                boxscore: boxscore,
                teamGroups: teamGroups,
                league: league
            )
            athleteStats = parsedBoxscore.byID
            athleteStatsByNameAndTeam = parsedBoxscore.byNameAndTeam
        }

        let teamAbbrByID = extractTeamAbbreviationMap(from: root)
        let recentPlays = extractRecentPlays(
            from: root,
            eventID: eventID,
            teamAbbrByID: teamAbbrByID,
            winProbSwingByPlayID: winProbSwingByPlayID,
            limit: 15
        )

        return ESPNGameSummaryUpdate(
            eventID: eventID,
            league: league,
            situation: situation,
            awayWinProb: awayWinProb,
            homeWinProb: homeWinProb,
            spreadSummary: spreadSummary,
            overUnder: overUnder,
            athleteStats: athleteStats,
            athleteStatsByNameAndTeam: athleteStatsByNameAndTeam,
            recentPlays: recentPlays,
            espnWinProbHistory: espnWinProbHistory
        )
    }

    /// Normalizes a player name + team code into a deterministic lookup key (`"normalized name|TEAM"`).
    public nonisolated static func normalizedPlayerNameTeamKey(
        name: String,
        team: String,
        league: SportsLeague
    ) -> String {
        let folded = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: ".", with: "")
        var tokens = folded
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "v"]
        while tokens.count > 1, let last = tokens.last, suffixes.contains(last) {
            tokens.removeLast()
        }
        let normalizedName = tokens.joined(separator: " ")
        let canonicalTeam = SportsEntityMatcher.canonicalESPNCode(team, league: league)
        return "\(normalizedName)|\(canonicalTeam)"
    }

    // MARK: - Boxscore Parsing & Formatting Helpers

    private struct NFLAccumulatedAthlete {
        var name: String = ""
        var cAtt: String?
        var passYds: Int?
        var passTD: Int?
        var passINT: Int?
        var car: Int?
        var rushYds: Int?
        var rushTD: Int?
        var rec: Int?
        var recYds: Int?
        var recTD: Int?
        var tgts: Int?
        var fg: String?
        var xp: String?
        var kickLong: Int?
        var fallbackTokens: [String] = []
    }

    private struct NFLTeamDefenseStats {
        var sacks: Double = 0
        var hasSacks: Bool = false
        var interceptions: Int = 0
        var hasInterceptions: Bool = false
        var fumbleRecoveries: Int = 0
        var hasFumbleRecoveries: Bool = false
        var touchdowns: Int = 0
        var offensiveFumblesLost: Int = 0
    }

    private nonisolated static func parseBoxscoreStats(
        root: [String: Any],
        boxscore: [String: Any],
        teamGroups: [[String: Any]],
        league: SportsLeague
    ) -> (byID: [String: String], byNameAndTeam: [String: String]) {
        var byID: [String: String] = [:]
        var byNameAndTeam: [String: String] = [:]

        if league == .nfl || league == .ncaaf {
            let opponentScoresByTeam = extractOpponentScoresByTeam(from: root, league: league)
            var defenseByTeam = extractNFLTeamStatsFromTeamsBoxscore(from: boxscore, league: league)
            var teamOrder: [String] = []

            for group in teamGroups {
                let teamObj = group["team"] as? [String: Any]
                let rawAbbr = stringValue(teamObj?["abbreviation"]) ?? ""
                let teamCode = rawAbbr.isEmpty ? "" : SportsEntityMatcher.canonicalESPNCode(rawAbbr, league: league)
                if !teamCode.isEmpty && !teamOrder.contains(teamCode) {
                    teamOrder.append(teamCode)
                }

                guard let statCategories = group["statistics"] as? [[String: Any]] else { continue }
                var athletesByID: [String: NFLAccumulatedAthlete] = [:]
                var athleteOrder: [String] = []

                var defStats = defenseByTeam[teamCode] ?? NFLTeamDefenseStats()

                for category in statCategories {
                    let labels = (category["labels"] as? [String]) ?? []
                    let catName = (stringValue(category["name"]) ?? "").lowercased()
                    let inferred = inferNFLCategory(catName: catName, labels: labels)
                    let athletes = (category["athletes"] as? [[String: Any]]) ?? []

                    if inferred == "defensive" || inferred == "interceptions" || inferred == "fumbles" {
                        accumulateNFLTeamDefenseCategory(
                            categoryName: inferred,
                            category: category,
                            labels: labels,
                            athletes: athletes,
                            into: &defStats
                        )
                    }

                    for entry in athletes {
                        if (entry["didNotPlay"] as? Bool) == true { continue }
                        guard let athlete = entry["athlete"] as? [String: Any],
                              let athleteID = stringValue(athlete["id"]),
                              let stats = entry["stats"] as? [String],
                              !stats.isEmpty else {
                            continue
                        }
                        let athleteName = stringValue(athlete["displayName"])
                            ?? stringValue(athlete["fullName"])
                            ?? stringValue(athlete["shortName"])
                            ?? ""
                        let map = makeLabelMap(labels: labels, stats: stats)
                        var acc = athletesByID[athleteID] ?? NFLAccumulatedAthlete(name: athleteName)
                        if acc.name.isEmpty { acc.name = athleteName }
                        if athletesByID[athleteID] == nil {
                            athleteOrder.append(athleteID)
                        }

                        switch inferred {
                        case "passing":
                            acc.cAtt = map["C/ATT"] ?? map["COMP/ATT"] ?? acc.cAtt
                            acc.passYds = intValue(map["YDS"]) ?? acc.passYds
                            acc.passTD = intValue(map["TD"]) ?? acc.passTD
                            acc.passINT = intValue(map["INT"]) ?? acc.passINT
                        case "rushing":
                            acc.car = intValue(map["CAR"]) ?? intValue(map["ATT"]) ?? acc.car
                            acc.rushYds = intValue(map["YDS"]) ?? acc.rushYds
                            acc.rushTD = intValue(map["TD"]) ?? acc.rushTD
                        case "receiving":
                            acc.rec = intValue(map["REC"]) ?? acc.rec
                            acc.recYds = intValue(map["YDS"]) ?? acc.recYds
                            acc.recTD = intValue(map["TD"]) ?? acc.recTD
                            acc.tgts = intValue(map["TGTS"]) ?? intValue(map["TAR"]) ?? acc.tgts
                        case "kicking":
                            acc.fg = map["FG"] ?? map["FGM/FGA"] ?? acc.fg
                            acc.xp = map["XP"] ?? map["XPM/XPA"] ?? acc.xp
                            acc.kickLong = intValue(map["LONG"]) ?? intValue(map["LNG"]) ?? acc.kickLong
                        default:
                            if acc.fallbackTokens.isEmpty {
                                acc.fallbackTokens = buildFallbackTokens(labels: labels, stats: stats)
                            }
                        }

                        athletesByID[athleteID] = acc
                    }
                }

                if !teamCode.isEmpty {
                    defenseByTeam[teamCode] = defStats
                }

                for athleteID in athleteOrder {
                    guard let acc = athletesByID[athleteID],
                          let line = formatNFLAthleteLine(acc),
                          !line.isEmpty else {
                        continue
                    }
                    byID[athleteID] = line
                    if !teamCode.isEmpty, !acc.name.isEmpty {
                        let key = normalizedPlayerNameTeamKey(name: acc.name, team: teamCode, league: .nfl)
                        byNameAndTeam[key] = line
                    }
                }
            }

            // Populate NFL D/ST stats (PA from opponent score + defensive/interceptions/opponent fumbles lost)
            let allDefenseTeams = Set(teamOrder).union(opponentScoresByTeam.keys)
            for teamCode in allDefenseTeams where !teamCode.isEmpty {
                var def = defenseByTeam[teamCode] ?? NFLTeamDefenseStats()
                if !def.hasFumbleRecoveries && teamOrder.count == 2,
                   let oppTeam = teamOrder.first(where: { $0 != teamCode }),
                   let oppLost = defenseByTeam[oppTeam]?.offensiveFumblesLost,
                   oppLost > 0 {
                    def.fumbleRecoveries = oppLost
                    def.hasFumbleRecoveries = true
                }
                if let dstLine = formatNFLDefenseLine(
                    pointsAllowed: opponentScoresByTeam[teamCode],
                    stats: def
                ), !dstLine.isEmpty {
                    let key = normalizedPlayerNameTeamKey(name: "def", team: teamCode, league: .nfl)
                    byNameAndTeam[key] = dstLine
                }
            }

            return (byID, byNameAndTeam)
        }

        // NBA, MLB, NHL
        for group in teamGroups {
            let teamObj = group["team"] as? [String: Any]
            let rawAbbr = stringValue(teamObj?["abbreviation"]) ?? ""
            let teamCode = rawAbbr.isEmpty ? "" : SportsEntityMatcher.canonicalESPNCode(rawAbbr, league: league)
            guard let statCategories = group["statistics"] as? [[String: Any]] else { continue }

            for category in statCategories {
                let labels = (category["labels"] as? [String]) ?? []
                let catName = (stringValue(category["name"]) ?? "").lowercased()
                let athletes = (category["athletes"] as? [[String: Any]]) ?? []

                for entry in athletes {
                    if (entry["didNotPlay"] as? Bool) == true { continue }
                    guard let athlete = entry["athlete"] as? [String: Any],
                          let athleteID = stringValue(athlete["id"]),
                          let stats = entry["stats"] as? [String],
                          !stats.isEmpty else {
                        continue
                    }
                    let athleteName = stringValue(athlete["displayName"])
                        ?? stringValue(athlete["fullName"])
                        ?? stringValue(athlete["shortName"])
                        ?? ""
                    let map = makeLabelMap(labels: labels, stats: stats)
                    let line: String?
                    switch league {
                    case .nba, .ncaab:
                        line = formatNBAAthleteLine(map: map, labels: labels, stats: stats)
                    case .mlb:
                        line = formatMLBAthleteLine(catName: catName, map: map, labels: labels, stats: stats)
                    case .nhl:
                        line = formatNHLAthleteLine(catName: catName, map: map, labels: labels, stats: stats)
                    case .nfl, .ncaaf, .mls, .epl, .f1:
                        line = nil
                    }
                    guard let line, !line.isEmpty else { continue }
                    byID[athleteID] = line
                    if !teamCode.isEmpty, !athleteName.isEmpty {
                        let key = normalizedPlayerNameTeamKey(name: athleteName, team: teamCode, league: league)
                        byNameAndTeam[key] = line
                    }
                }
            }
        }

        return (byID, byNameAndTeam)
    }

    private nonisolated static func makeLabelMap(labels: [String], stats: [String]) -> [String: String] {
        var map: [String: String] = [:]
        for (label, value) in zip(labels, stats) {
            let key = label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !key.isEmpty {
                map[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return map
    }

    private nonisolated static func buildFallbackTokens(labels: [String], stats: [String]) -> [String] {
        var tokens: [String] = []
        for (label, stat) in zip(labels, stats) {
            let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let cleanStat = stat.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanLabel == "MIN" || cleanLabel == "AVG" || cleanLabel == "LNG" || cleanLabel == "LONG" { continue }
            if cleanStat.isEmpty || cleanStat == "0" || cleanStat == "0/0" || cleanStat == "--" { continue }
            tokens.append("\(cleanStat) \(cleanLabel)")
            if tokens.count >= 3 { break }
        }
        return tokens
    }

    private nonisolated static func inferNFLCategory(catName: String, labels: [String]) -> String {
        if !catName.isEmpty {
            if catName.contains("pass") { return "passing" }
            if catName.contains("rush") { return "rushing" }
            if catName.contains("receiv") { return "receiving" }
            if catName.contains("kick") { return "kicking" }
            if catName.contains("defen") { return "defensive" }
            if catName.contains("intercep") { return "interceptions" }
            if catName.contains("fumbl") { return "fumbles" }
            return catName
        }
        let upper = Set(labels.map { $0.uppercased() })
        if upper.contains("C/ATT") || upper.contains("COMP/ATT") { return "passing" }
        if upper.contains("CAR") { return "rushing" }
        if upper.contains("REC") { return "receiving" }
        if upper.contains("FG") || upper.contains("XP") { return "kicking" }
        if upper.contains("SCK") || upper.contains("SACKS") || upper.contains("SOLO") || upper.contains("TOT") { return "defensive" }
        if upper.contains("INT") { return "interceptions" }
        if upper.contains("FUM") { return "fumbles" }
        return ""
    }

    private nonisolated static func formatNFLAthleteLine(_ acc: NFLAccumulatedAthlete) -> String? {
        if acc.cAtt != nil || acc.passYds != nil {
            var parts: [String] = []
            if let cAtt = acc.cAtt, !cAtt.isEmpty { parts.append(cAtt) }
            if let passYds = acc.passYds { parts.append("\(passYds) yds") }
            if let passTD = acc.passTD, passTD > 0 { parts.append("\(passTD) TD") }
            if let passINT = acc.passINT, passINT > 0 { parts.append("\(passINT) INT") }
            if let rushTD = acc.rushTD, rushTD > 0 {
                parts.append("\(rushTD) rush TD")
            } else if let rushYds = acc.rushYds, rushYds >= 15 {
                parts.append("\(rushYds) rush")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        if let car = acc.car, car > 0 {
            var parts: [String] = ["\(car) car"]
            if let rushYds = acc.rushYds { parts.append("\(rushYds) yds") }
            if let rushTD = acc.rushTD, rushTD > 0 { parts.append("\(rushTD) TD") }
            if let rec = acc.rec, rec > 0 {
                if let recYds = acc.recYds {
                    parts.append("\(rec) rec \(recYds) yds")
                } else {
                    parts.append("\(rec) rec")
                }
                if let recTD = acc.recTD, recTD > 0 {
                    parts.append("\(recTD) rec TD")
                }
            }
            return parts.joined(separator: " · ")
        }

        if acc.rec != nil || acc.recYds != nil || acc.tgts != nil {
            let rec = acc.rec ?? 0
            if rec == 0 {
                if let tgts = acc.tgts, tgts > 0 {
                    return "0 rec (\(tgts) tgt)"
                }
                if let rushYds = acc.rushYds, rushYds >= 10 {
                    return "\(rushYds) rush"
                }
                return nil
            }
            var parts: [String] = ["\(rec) rec"]
            if let recYds = acc.recYds { parts.append("\(recYds) yds") }
            if let recTD = acc.recTD, recTD > 0 {
                parts.append("\(recTD) TD")
            } else if let tgts = acc.tgts, tgts > 0 {
                parts.append("\(tgts) tgts")
            }
            if let rushTD = acc.rushTD, rushTD > 0 {
                parts.append("\(rushTD) rush TD")
            } else if let rushYds = acc.rushYds, rushYds >= 10 {
                parts.append("\(rushYds) rush")
            }
            return parts.joined(separator: " · ")
        }

        if acc.fg != nil || acc.xp != nil {
            var parts: [String] = []
            if let fg = acc.fg, !fg.isEmpty, fg != "0/0" { parts.append("\(fg) FG") }
            if let xp = acc.xp, !xp.isEmpty, xp != "0/0" { parts.append("\(xp) XP") }
            if parts.isEmpty, let fg = acc.fg, !fg.isEmpty { parts.append("\(fg) FG") }
            if parts.isEmpty, let xp = acc.xp, !xp.isEmpty { parts.append("\(xp) XP") }
            if let kickLong = acc.kickLong, kickLong >= 45 { parts.append("L\(kickLong)") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        return acc.fallbackTokens.isEmpty ? nil : acc.fallbackTokens.joined(separator: " · ")
    }

    private nonisolated static func extractOpponentScoresByTeam(from root: [String: Any], league: SportsLeague) -> [String: Int] {
        guard let header = root["header"] as? [String: Any],
              let competitions = header["competitions"] as? [[String: Any]],
              let comp = competitions.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              competitors.count == 2 else {
            return [:]
        }
        var entries: [(teamCode: String, score: Int)] = []
        for c in competitors {
            guard let teamObj = c["team"] as? [String: Any],
                  let abbr = stringValue(teamObj["abbreviation"]),
                  let score = intValue(c["score"]) else {
                continue
            }
            entries.append((SportsEntityMatcher.canonicalESPNCode(abbr, league: league), score))
        }
        guard entries.count == 2 else { return [:] }
        return [
            entries[0].teamCode: entries[1].score,
            entries[1].teamCode: entries[0].score
        ]
    }

    private nonisolated static func extractNFLTeamStatsFromTeamsBoxscore(
        from boxscore: [String: Any],
        league: SportsLeague
    ) -> [String: NFLTeamDefenseStats] {
        guard let teams = boxscore["teams"] as? [[String: Any]] else { return [:] }
        var result: [String: NFLTeamDefenseStats] = [:]
        for teamEntry in teams {
            guard let teamObj = teamEntry["team"] as? [String: Any],
                  let abbr = stringValue(teamObj["abbreviation"]) else { continue }
            let code = SportsEntityMatcher.canonicalESPNCode(abbr, league: league)
            var stats = NFLTeamDefenseStats()
            if let statItems = teamEntry["statistics"] as? [[String: Any]] {
                for item in statItems {
                    let name = (stringValue(item["name"]) ?? "").lowercased()
                    let valStr = stringValue(item["displayValue"]) ?? ""
                    if name == "sacks" || name == "totalsacks" {
                        if let v = doubleValue(valStr) {
                            stats.sacks = v
                            stats.hasSacks = true
                        }
                    } else if name == "interceptions" {
                        if let v = intValue(valStr) {
                            stats.interceptions = v
                            stats.hasInterceptions = true
                        }
                    } else if name == "fumblesrecovered" || name == "fumbles_recovered" {
                        if let v = intValue(valStr) {
                            stats.fumbleRecoveries = v
                            stats.hasFumbleRecoveries = true
                        }
                    } else if name == "defensivetouchdowns" || name == "defensive_touchdowns" {
                        if let v = intValue(valStr) {
                            stats.touchdowns += v
                        }
                    }
                }
            }
            result[code] = stats
        }
        return result
    }

    private nonisolated static func accumulateNFLTeamDefenseCategory(
        categoryName: String,
        category: [String: Any],
        labels: [String],
        athletes: [[String: Any]],
        into defStats: inout NFLTeamDefenseStats
    ) {
        let totals = category["totals"] as? [String]
        let rows: [[String]] = (totals != nil && !(totals?.isEmpty ?? true))
            ? [totals!]
            : athletes.compactMap { entry in
                if (entry["didNotPlay"] as? Bool) == true { return nil }
                return entry["stats"] as? [String]
            }

        for row in rows {
            let map = makeLabelMap(labels: labels, stats: row)
            switch categoryName {
            case "defensive":
                if let sck = doubleValue(map["SACKS"] ?? map["SCK"]), !defStats.hasSacks || totals == nil {
                    if totals != nil {
                        defStats.sacks = sck
                    } else {
                        defStats.sacks += sck
                    }
                }
                if let fr = intValue(map["FR"]), !defStats.hasFumbleRecoveries || totals == nil {
                    if totals != nil {
                        defStats.fumbleRecoveries = fr
                    } else {
                        defStats.fumbleRecoveries += fr
                    }
                }
                if let td = intValue(map["TD"]) {
                    defStats.touchdowns += td
                }
            case "interceptions":
                if let ints = intValue(map["INT"]), !defStats.hasInterceptions || totals == nil {
                    if totals != nil {
                        defStats.interceptions = ints
                    } else {
                        defStats.interceptions += ints
                    }
                }
                if let td = intValue(map["TD"]) {
                    defStats.touchdowns += td
                }
            case "fumbles":
                if let lost = intValue(map["LOST"]) {
                    if totals != nil {
                        defStats.offensiveFumblesLost = lost
                    } else {
                        defStats.offensiveFumblesLost += lost
                    }
                }
            default:
                break
            }
        }
        if categoryName == "defensive" && defStats.sacks > 0 { defStats.hasSacks = true }
        if categoryName == "defensive" && defStats.fumbleRecoveries > 0 { defStats.hasFumbleRecoveries = true }
        if categoryName == "interceptions" && defStats.interceptions > 0 { defStats.hasInterceptions = true }
    }

    private nonisolated static func formatNFLDefenseLine(pointsAllowed: Int?, stats: NFLTeamDefenseStats) -> String? {
        var parts: [String] = []
        if let pointsAllowed {
            parts.append("\(pointsAllowed) PA")
        }
        if stats.sacks > 0 {
            let sackStr = stats.sacks.rounded() == stats.sacks
                ? "\(Int(stats.sacks))"
                : String(format: "%.1f", stats.sacks)
            parts.append("\(sackStr) SCK")
        }
        if stats.interceptions > 0 {
            parts.append("\(stats.interceptions) INT")
        }
        if stats.fumbleRecoveries > 0 {
            parts.append("\(stats.fumbleRecoveries) FR")
        }
        if stats.touchdowns > 0 {
            parts.append("\(stats.touchdowns) TD")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private nonisolated static func formatNBAAthleteLine(
        map: [String: String],
        labels: [String],
        stats: [String]
    ) -> String? {
        let pts = intValue(map["PTS"])
        let reb = intValue(map["REB"])
        let ast = intValue(map["AST"])

        guard pts != nil || reb != nil || ast != nil else {
            let fallback = buildFallbackTokens(labels: labels, stats: stats)
            return fallback.isEmpty ? nil : fallback.joined(separator: " · ")
        }

        var parts: [String] = []
        if let pts { parts.append("\(pts) PTS") }
        if let reb { parts.append("\(reb) REB") }
        if let ast { parts.append("\(ast) AST") }

        var extras: [String] = []
        if let stl = intValue(map["STL"]), stl >= 2 {
            extras.append("\(stl) STL")
        }
        if let blk = intValue(map["BLK"]), blk >= 2 {
            extras.append("\(blk) BLK")
        }
        if let threePT = map["3PT"],
           let madeStr = threePT.split(separator: "-").first,
           let threePM = Int(madeStr),
           threePM >= 3 {
            extras.append("\(threePM) 3PM")
        }
        parts.append(contentsOf: extras.prefix(2))
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private nonisolated static func formatMLBAthleteLine(
        catName: String,
        map: [String: String],
        labels: [String],
        stats: [String]
    ) -> String? {
        let isPitcher = catName.contains("pitch") || map["IP"] != nil
        if isPitcher {
            var parts: [String] = []
            if let ip = map["IP"], !ip.isEmpty { parts.append("\(ip) IP") }
            if let k = intValue(map["K"] ?? map["SO"]) { parts.append("\(k) K") }
            if let er = intValue(map["ER"]) { parts.append("\(er) ER") }
            if let h = intValue(map["H"]), h > 0 {
                let candidate = (parts + ["\(h) H"]).joined(separator: " · ")
                if candidate.count <= 32 {
                    parts.append("\(h) H")
                }
            }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
            let fallback = buildFallbackTokens(labels: labels, stats: stats)
            return fallback.isEmpty ? nil : fallback.joined(separator: " · ")
        }

        // Batter
        var tokens: [String] = []
        if let hAb = map["H-AB"], !hAb.isEmpty, hAb != "0-0" {
            tokens.append(hAb)
        } else if let h = intValue(map["H"]), let ab = intValue(map["AB"]), (ab > 0 || h > 0) {
            tokens.append("\(h)-\(ab)")
        }
        if let hr = intValue(map["HR"]), hr > 0 {
            tokens.append(hr >= 2 ? "\(hr) HR" : "HR")
        }
        if let rbi = intValue(map["RBI"]), rbi > 0 {
            tokens.append("\(rbi) RBI")
        }
        if let runs = intValue(map["R"]), runs > 0 {
            tokens.append("\(runs) R")
        }
        if let sb = intValue(map["SB"]), sb > 0 {
            tokens.append("\(sb) SB")
        }
        if let bb = intValue(map["BB"]), bb > 0 {
            tokens.append("\(bb) BB")
        }
        if tokens.isEmpty {
            let fallback = buildFallbackTokens(labels: labels, stats: stats)
            return fallback.isEmpty ? nil : fallback.joined(separator: " · ")
        }
        return tokens.prefix(4).joined(separator: " · ")
    }

    private nonisolated static func formatNHLAthleteLine(
        catName: String,
        map: [String: String],
        labels: [String],
        stats: [String]
    ) -> String? {
        let isGoalie = catName.contains("goalie")
            || map["SV"] != nil
            || map["GA"] != nil
            || map["SV%"] != nil
        if isGoalie {
            var parts: [String] = []
            let sv = intValue(map["SV"])
            let ga = intValue(map["GA"])
            let sa = intValue(map["SA"])
            if let sv { parts.append("\(sv) SV") }
            if let ga { parts.append("\(ga) GA") }
            if let rawPct = map["SV%"], !rawPct.isEmpty, rawPct != "--" {
                if rawPct.hasPrefix("0.") {
                    parts.append(String(rawPct.dropFirst()))
                } else {
                    parts.append(rawPct)
                }
            } else if let sv, let sa, sa > 0 {
                let pct = Double(sv) / Double(sa)
                let formatted = String(format: "%.3f", pct)
                parts.append(formatted.hasPrefix("0.") ? String(formatted.dropFirst()) : formatted)
            }
            if let ga, ga == 0, (sv ?? 0) > 0 || (sa ?? 0) > 0 {
                parts.append("SO")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        // Skater
        let goals = intValue(map["G"]) ?? 0
        let assists = intValue(map["A"]) ?? 0
        let sog = intValue(map["SOG"] ?? map["S"])
        if goals > 0 || assists > 0 {
            var parts: [String] = ["\(goals) G", "\(assists) A"]
            if let sog { parts.append("\(sog) SOG") }
            return parts.joined(separator: " · ")
        }

        var quietParts: [String] = []
        if let sog { quietParts.append("\(sog) SOG") }
        if let hit = intValue(map["HIT"]), hit > 0 {
            quietParts.append("\(hit) HIT")
        } else if let pmRaw = map["+/-"], let pmVal = intValue(pmRaw), pmVal != 0 {
            quietParts.append(pmVal > 0 ? "+\(pmVal)" : "\(pmVal)")
        } else if let blk = intValue(map["BLK"] ?? map["BS"]), blk > 0 {
            quietParts.append("\(blk) BLK")
        }
        if quietParts.count >= 2 {
            return quietParts.joined(separator: " · ")
        }
        if let sog {
            return "0 G · 0 A · \(sog) SOG"
        }
        let fallback = buildFallbackTokens(labels: labels, stats: stats)
        return fallback.isEmpty ? nil : fallback.joined(separator: " · ")
    }

    // MARK: - Helpers

    private nonisolated static func mapGameStatus(name: String, state: String) -> GameStatus {
        switch name.uppercased() {
        case "STATUS_HALFTIME":
            return .halftime
        case "STATUS_FINAL", "STATUS_FULL_TIME":
            return .final
        case "STATUS_POSTPONED", "STATUS_CANCELED", "STATUS_SUSPENDED":
            return .postponed
        case "STATUS_IN_PROGRESS", "STATUS_FIRST_HALF", "STATUS_SECOND_HALF", "STATUS_END_PERIOD", "STATUS_OVERTIME":
            return .live
        case "STATUS_SCHEDULED":
            return .pregame
        default:
            switch state.lowercased() {
            case "in": return .live
            case "post": return .final
            default: return .pregame
            }
        }
    }

    private nonisolated static func extractBroadcasts(from competition: [String: Any]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        if let broadcasts = competition["broadcasts"] as? [[String: Any]] {
            for b in broadcasts {
                if let bNames = b["names"] as? [String] {
                    for item in bNames where !item.isEmpty && seen.insert(item).inserted {
                        names.append(item)
                    }
                }
            }
        }
        if let geoBroadcasts = competition["geoBroadcasts"] as? [[String: Any]] {
            for g in geoBroadcasts {
                if let media = g["media"] as? [String: Any],
                   let shortName = stringValue(media["shortName"]),
                   !shortName.isEmpty,
                   seen.insert(shortName).inserted {
                    names.append(shortName)
                }
            }
        }
        return names
    }

    private nonisolated static func parseSituation(from dict: [String: Any]?) -> GameSituation? {
        guard let dict else { return nil }
        let possession = stringValue(dict["possession"])
        let downDistance = stringValue(dict["downDistanceText"]) ?? stringValue(dict["shortDownDistanceText"])
        let isRedZone = (dict["isRedZone"] as? Bool) ?? false
        let yardLine = stringValue(dict["possessionText"])
        let balls = intValue(dict["balls"])
        let strikes = intValue(dict["strikes"])
        let outs = intValue(dict["outs"])

        var baseParts: [String] = []
        if (dict["onFirst"] as? Bool) == true { baseParts.append("1st") }
        if (dict["onSecond"] as? Bool) == true { baseParts.append("2nd") }
        if (dict["onThird"] as? Bool) == true { baseParts.append("3rd") }
        let runnersText = baseParts.isEmpty ? nil : baseParts.joined(separator: " & ")

        if possession == nil && downDistance == nil && !isRedZone && yardLine == nil
            && balls == nil && strikes == nil && outs == nil && runnersText == nil {
            return nil
        }

        return GameSituation(
            possessionTeamID: possession,
            downDistanceText: downDistance,
            isRedZone: isRedZone,
            yardLineText: yardLine,
            balls: balls,
            strikes: strikes,
            outs: outs,
            runnersOnBaseText: runnersText
        )
    }

    private nonisolated static func parseISO8601Date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let fractional = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return fractional
        }
        return try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false))
    }

    private nonisolated static func stringValue(_ raw: Any?) -> String? {
        if let str = raw as? String { return str }
        if let num = raw as? NSNumber { return num.stringValue }
        return nil
    }

    private nonisolated static func intValue(_ raw: Any?) -> Int? {
        if let val = raw as? Int { return val }
        if let num = raw as? NSNumber { return num.intValue }
        if let str = raw as? String { return Int(str) }
        return nil
    }

    private nonisolated static func extractF1TopTwo(
        from competitors: [[String: Any]]
    ) -> (away: TeamScore, home: TeamScore)? {
        struct RankedDriver {
            let order: Int
            let score: TeamScore
        }

        var drivers: [RankedDriver] = []
        for (idx, comp) in competitors.enumerated() {
            let athlete = comp["athlete"] as? [String: Any]
            let team = comp["team"] as? [String: Any]
            let id = stringValue(comp["id"]) ?? stringValue(athlete?["id"]) ?? stringValue(team?["id"]) ?? "\(idx + 1)"
            let displayName = stringValue(athlete?["displayName"])
                ?? stringValue(athlete?["fullName"])
                ?? stringValue(team?["displayName"])
                ?? "Driver \(idx + 1)"
            let shortName = stringValue(athlete?["shortName"])
                ?? stringValue(team?["shortDisplayName"])
                ?? displayName
            let explicitAbbr = stringValue(athlete?["abbreviation"]) ?? stringValue(team?["abbreviation"])
            let abbr: String
            if let explicitAbbr, !explicitAbbr.isEmpty {
                abbr = explicitAbbr.uppercased()
            } else {
                let lastWord = displayName.split(separator: " ").last.map(String.init) ?? displayName
                let letters = lastWord.uppercased().filter(\.isLetter)
                abbr = String((letters.isEmpty ? "F1" : letters).prefix(3))
            }
            let position = intValue(comp["order"]) ?? (idx + 1)
            let driverScore = TeamScore(
                espnTeamID: id,
                abbreviation: abbr,
                displayName: displayName,
                shortName: shortName,
                score: position,
                record: "P\(position)",
                isPossession: false
            )
            drivers.append(RankedDriver(order: position, score: driverScore))
        }

        drivers.sort { $0.order < $1.order }
        guard drivers.count >= 2 else { return nil }
        return (away: drivers[1].score, home: drivers[0].score)
    }

    private nonisolated static func extractTeamAbbreviationMap(from root: [String: Any]) -> [String: String] {
        guard let header = root["header"] as? [String: Any],
              let competitions = header["competitions"] as? [[String: Any]],
              let comp = competitions.first,
              let competitors = comp["competitors"] as? [[String: Any]] else {
            return [:]
        }
        var map: [String: String] = [:]
        for c in competitors {
            guard let teamObj = c["team"] as? [String: Any],
                  let tid = stringValue(teamObj["id"]) ?? stringValue(c["id"]),
                  let abbr = stringValue(teamObj["abbreviation"]) else {
                continue
            }
            map[tid] = abbr
        }
        return map
    }

    private nonisolated static func downsampleWinProbabilityPoints(
        _ points: [WinProbabilityPoint],
        maxCount: Int
    ) -> [WinProbabilityPoint] {
        guard maxCount >= 2, points.count > maxCount else {
            return points
        }
        var result: [WinProbabilityPoint] = []
        result.reserveCapacity(maxCount)
        let lastIndex = points.count - 1
        for idx in 0..<maxCount {
            let mappedIndex: Int
            if idx == maxCount - 1 {
                mappedIndex = lastIndex
            } else {
                mappedIndex = Int((Double(idx) * Double(lastIndex) / Double(maxCount - 1)).rounded())
            }
            result.append(points[mappedIndex])
        }
        return result
    }

    private nonisolated static func extractRecentPlays(
        from root: [String: Any],
        eventID: String,
        teamAbbrByID: [String: String],
        winProbSwingByPlayID: [String: Double] = [:],
        limit: Int
    ) -> [PlayByPlayEvent] {
        var rawPlayObjects: [[String: Any]] = []
        var sourcedFromKeyEvents = false

        var keyEventIDs: Set<String> = []
        if let keyEvents = root["keyEvents"] as? [[String: Any]] {
            for ev in keyEvents {
                if let eid = stringValue(ev["id"]), !eid.isEmpty {
                    keyEventIDs.insert(eid)
                }
            }
        }

        if let drives = root["drives"] as? [String: Any] {
            if let previous = drives["previous"] as? [[String: Any]] {
                for drive in previous {
                    if let drivePlays = drive["plays"] as? [[String: Any]] {
                        rawPlayObjects.append(contentsOf: drivePlays)
                    }
                }
            }
            if let current = drives["current"] as? [String: Any],
               let currentPlays = current["plays"] as? [[String: Any]] {
                rawPlayObjects.append(contentsOf: currentPlays)
            }
        }

        if rawPlayObjects.isEmpty, let plays = root["plays"] as? [[String: Any]] {
            rawPlayObjects = plays
        }

        if rawPlayObjects.isEmpty, let keyEvents = root["keyEvents"] as? [[String: Any]] {
            rawPlayObjects = keyEvents
            sourcedFromKeyEvents = true
        }

        guard !rawPlayObjects.isEmpty else { return [] }

        var parsed: [PlayByPlayEvent] = []
        parsed.reserveCapacity(min(rawPlayObjects.count, limit))

        for (index, play) in rawPlayObjects.enumerated() {
            let rawText = stringValue(play["text"])
                ?? stringValue(play["shortDescription"])
                ?? stringValue((play["type"] as? [String: Any])?["text"])
                ?? ""
            let cleanText = AgentSecurity.sanitizeWebText(rawText, maxLength: 240).text
            guard !cleanText.isEmpty else { continue }

            let explicitPlayID = stringValue(play["id"])
            let playID = explicitPlayID ?? "\(eventID):p:\(index)"
            let periodObj = play["period"] as? [String: Any]
            let periodText = stringValue(periodObj?["displayValue"])
                ?? intValue(periodObj?["number"]).map { "P\($0)" }
                ?? ""
            let clockObj = play["clock"] as? [String: Any]
            let clock = stringValue(clockObj?["displayValue"])
            let teamObj = play["team"] as? [String: Any]
            let teamID = stringValue(teamObj?["id"])
            let teamAbbr = stringValue(teamObj?["abbreviation"]) ?? teamID.flatMap { teamAbbrByID[$0] }
            let isScoring = (play["scoringPlay"] as? Bool) ?? false
            let awayScore = intValue(play["awayScore"])
            let homeScore = intValue(play["homeScore"])
            let wallclock = parseISO8601Date(stringValue(play["wallclock"]))
            let swing = explicitPlayID.flatMap { winProbSwingByPlayID[$0] } ?? winProbSwingByPlayID[playID] ?? 0
            let isKey = isScoring
                || sourcedFromKeyEvents
                || (explicitPlayID.map { keyEventIDs.contains($0) } ?? false)
                || swing >= 0.08
                || isHighImpactPlayText(cleanText)

            parsed.append(
                PlayByPlayEvent(
                    id: playID,
                    gameID: eventID,
                    periodText: periodText,
                    clock: clock,
                    teamAbbreviation: teamAbbr,
                    text: cleanText,
                    isScoringPlay: isScoring,
                    awayScore: awayScore,
                    homeScore: homeScore,
                    wallclock: wallclock,
                    isKeyPlay: isKey
                )
            )
        }

        // Return newest-first capped at `limit`.
        return Array(parsed.suffix(limit).reversed())
    }

    private nonisolated static func isHighImpactPlayText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = [
            "interception", "intercepted", "fumble", "turnover",
            "sack", "sacked", "fourth down", "4th down",
            "home run", "grand slam", "red card", "penalty",
            "power play", "touchdown", "goal", "safety"
        ]
        return keywords.contains { lower.contains($0) }
    }

    private nonisolated static func doubleValue(_ raw: Any?) -> Double? {
        if let val = raw as? Double { return val }
        if let num = raw as? NSNumber { return num.doubleValue }
        if let str = raw as? String { return Double(str) }
        return nil
    }
}
