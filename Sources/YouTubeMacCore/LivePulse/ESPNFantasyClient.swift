import Foundation

public enum ESPNFantasyError: Error, Equatable, Sendable {
    case privateLeagueRequiresWebTile
    case invalidURL
    case httpError(Int)
    case decodingFailed
}

/// Cookieless ephemeral client for ESPN Public Fantasy Leagues (`lm-api-reads.fantasy.espn.com`).
public actor ESPNFantasyClient {
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

    public func fetchPublicMatchup(config: FantasyLeagueConfig) async throws -> FantasyMatchup? {
        let encodedLeagueID = config.leagueID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.leagueID
        let urlString = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/\(config.league.espnFantasyGameCode)/seasons/\(config.season)/segments/0/leagues/\(encodedLeagueID)?view=mTeam&view=mRoster&view=mMatchupScore&view=mLiveScoring"
        guard let url = URL(string: urlString) else {
            throw ESPNFantasyError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ESPNFantasyError.privateLeagueRequiresWebTile
            }
            if !(200...299).contains(http.statusCode) {
                throw ESPNFantasyError.httpError(http.statusCode)
            }
        }
        return Self.parsePublicMatchup(from: data, config: config)
    }

    // MARK: - Pure Offline JSON Parser

    public nonisolated static func parsePublicMatchup(
        from data: Data,
        config: FantasyLeagueConfig
    ) -> FantasyMatchup? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let teams = root["teams"] as? [[String: Any]],
              !teams.isEmpty else {
            return nil
        }

        let statusObj = root["status"] as? [String: Any]
        let currentPeriod = intValue(statusObj?["currentMatchupPeriod"])
            ?? intValue(root["scoringPeriodId"])
            ?? 1

        let settingsObj = root["settings"] as? [String: Any]
        let leagueName = stringValue(settingsObj?["name"]) ?? config.leagueName

        // Identify user's team by hint (team name, abbrev, or owner ID), falling back to team[0].
        let hint = config.teamOwnerHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let userTeamDict: [String: Any] = teams.first(where: { team in
            guard let hint, !hint.isEmpty else { return false }
            let name = espnTeamName(team).lowercased()
            let abbrev = (stringValue(team["abbrev"]) ?? "").lowercased()
            let owners = (team["owners"] as? [String]) ?? []
            return name.contains(hint) || abbrev == hint || owners.contains(where: { $0.lowercased() == hint })
        }) ?? teams[0]

        guard let userTeamID = intValue(userTeamDict["id"]) else {
            return nil
        }

        var teamByID: [Int: [String: Any]] = [:]
        for team in teams {
            if let tid = intValue(team["id"]) {
                teamByID[tid] = team
            }
        }

        let schedule = (root["schedule"] as? [[String: Any]]) ?? []
        let matchupObj = schedule.first { item in
            let periodMatches = (intValue(item["matchupPeriodId"]) ?? currentPeriod) == currentPeriod
            guard periodMatches else { return false }
            let homeID = intValue((item["home"] as? [String: Any])?["teamId"])
            let awayID = intValue((item["away"] as? [String: Any])?["teamId"])
            return homeID == userTeamID || awayID == userTeamID
        }

        let homeSide = matchupObj?["home"] as? [String: Any]
        let awaySide = matchupObj?["away"] as? [String: Any]
        let userIsHome = intValue(homeSide?["teamId"]) == userTeamID
        let userSide = userIsHome ? homeSide : awaySide
        let oppSide = userIsHome ? awaySide : homeSide

        let oppTeamID = intValue(oppSide?["teamId"])
        let oppTeamDict = oppTeamID.flatMap { teamByID[$0] }

        let userTeamName = espnTeamName(userTeamDict)
        let oppTeamName = oppTeamDict.map(espnTeamName) ?? "Opponent"

        let userPoints = doubleValue(userSide?["totalPoints"])
            ?? doubleValue((userTeamDict["record"] as? [String: Any])?["pointsFor"])
            ?? 0
        let oppPoints = doubleValue(oppSide?["totalPoints"]) ?? 0
        let userProjected = doubleValue(userSide?["totalProjectedPointsLive"])
        let oppProjected = doubleValue(oppSide?["totalProjectedPointsLive"])

        let userRoster = parseRosterLines(
            from: userTeamDict,
            config: config,
            scoringPeriodID: currentPeriod,
            isUserRoster: true
        )
        let oppRoster = oppTeamDict.map {
            parseRosterLines(from: $0, config: config, scoringPeriodID: currentPeriod, isUserRoster: false)
        } ?? []

        return FantasyMatchup(
            id: "espn:\(config.leagueID):p\(currentPeriod)",
            configID: config.id,
            provider: .espnPublic,
            league: config.league,
            leagueName: leagueName,
            weekLabel: "Period \(currentPeriod)",
            userTeamName: userTeamName,
            opponentTeamName: oppTeamName,
            userPoints: userPoints,
            opponentPoints: oppPoints,
            userProjected: userProjected,
            opponentProjected: oppProjected,
            starters: userRoster.filter(\.isStarter),
            bench: userRoster.filter { !$0.isStarter },
            opponentStarters: oppRoster.filter(\.isStarter)
        )
    }

    // MARK: - Helpers

    private nonisolated static func parseRosterLines(
        from teamDict: [String: Any],
        config: FantasyLeagueConfig,
        scoringPeriodID: Int,
        isUserRoster: Bool
    ) -> [FantasyPlayerLine] {
        guard let roster = teamDict["roster"] as? [String: Any],
              let entries = roster["entries"] as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry in
            let lineupSlotID = intValue(entry["lineupSlotId"]) ?? 0
            let isStarter = lineupSlotID != 20 && lineupSlotID != 21 // 20 = Bench, 21 = IR
            let poolEntry = entry["playerPoolEntry"] as? [String: Any]
            let player = poolEntry?["player"] as? [String: Any]
            let pid = stringValue(player?["id"]) ?? stringValue(entry["playerId"]) ?? UUID().uuidString
            let fullName = stringValue(player?["fullName"]) ?? "Player \(pid)"
            let proTeamID = intValue(player?["proTeamId"]) ?? 0
            let positionID = intValue(player?["defaultPositionId"]) ?? 0

            var points = doubleValue(poolEntry?["appliedStatTotal"]) ?? 0
            if points == 0, let stats = player?["stats"] as? [[String: Any]] {
                if let liveStat = stats.first(where: {
                    intValue($0["scoringPeriodId"]) == scoringPeriodID && intValue($0["statSourceId"]) == 0
                }) ?? stats.first(where: { intValue($0["statSourceId"]) == 0 }) {
                    points = doubleValue(liveStat["appliedTotal"]) ?? 0
                }
            }

            return FantasyPlayerLine(
                id: "espn:\(config.leagueID):\(isUserRoster ? "u" : "o"):\(pid)",
                espnPlayerID: pid,
                name: fullName,
                position: espnPositionLabel(positionID, league: config.league),
                nflOrProTeam: espnProTeamAbbreviation(proTeamID, league: config.league),
                points: points,
                isStarter: isStarter,
                isUserRoster: isUserRoster
            )
        }
    }

    private nonisolated static func espnTeamName(_ team: [String: Any]) -> String {
        if let name = stringValue(team["name"]), !name.isEmpty {
            return name
        }
        let loc = stringValue(team["location"]) ?? ""
        let nick = stringValue(team["nickname"]) ?? ""
        let combined = "\(loc) \(nick)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.isEmpty { return combined }
        return stringValue(team["abbrev"]) ?? "Team"
    }

    private nonisolated static func espnPositionLabel(_ id: Int, league: SportsLeague) -> String {
        switch league {
        case .nfl, .ncaaf:
            switch id {
            case 1: return "QB"
            case 2: return "RB"
            case 3: return "WR"
            case 4: return "TE"
            case 5: return "K"
            case 16: return "D/ST"
            default: return "FLEX"
            }
        case .nba, .ncaab:
            switch id {
            case 1: return "PG"
            case 2: return "SG"
            case 3: return "SF"
            case 4: return "PF"
            case 5: return "C"
            default: return "G/F"
            }
        case .mlb:
            switch id {
            case 1: return "SP"
            case 2: return "C"
            case 3: return "1B"
            case 4: return "2B"
            case 5: return "3B"
            case 6: return "SS"
            case 7, 8, 9: return "OF"
            case 11: return "RP"
            default: return "DH"
            }
        case .nhl:
            switch id {
            case 1: return "C"
            case 2: return "LW"
            case 3: return "RW"
            case 4: return "D"
            case 5: return "G"
            default: return "F"
            }
        case .mls, .epl:
            switch id {
            case 1: return "GK"
            case 2: return "D"
            case 3: return "M"
            case 4: return "F"
            default: return "POS"
            }
        case .f1:
            return "DRV"
        }
    }

    private nonisolated static func espnProTeamAbbreviation(_ id: Int, league: SportsLeague) -> String {
        guard league == .nfl else { return id == 0 ? "FA" : "\(id)" }
        let nflMap: [Int: String] = [
            1: "ATL", 2: "BUF", 3: "CHI", 4: "CIN", 5: "CLE", 6: "DAL", 7: "DEN", 8: "DET",
            9: "GB", 10: "TEN", 11: "IND", 12: "KC", 13: "LV", 14: "LAR", 15: "MIA", 16: "MIN",
            17: "NE", 18: "NO", 19: "NYG", 20: "NYJ", 21: "PHI", 22: "ARI", 23: "PIT", 24: "LAC",
            25: "SF", 26: "SEA", 27: "TB", 28: "WAS", 29: "CAR", 30: "JAX", 33: "BAL", 34: "HOU"
        ]
        return nflMap[id] ?? "FA"
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

    private nonisolated static func doubleValue(_ raw: Any?) -> Double? {
        if let val = raw as? Double { return val }
        if let num = raw as? NSNumber { return num.doubleValue }
        if let str = raw as? String { return Double(str) }
        return nil
    }
}
