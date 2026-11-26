import Foundation

public struct SleeperUser: Equatable, Codable, Sendable {
    public let userID: String
    public let username: String
    public let displayName: String

    public init(userID: String, username: String, displayName: String) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
    }
}

public struct SleeperSportState: Equatable, Codable, Sendable {
    public let season: String
    public let week: Int
    public let seasonType: String

    public init(season: String, week: Int, seasonType: String) {
        self.season = season
        self.week = week
        self.seasonType = seasonType
    }
}

public struct SleeperLeagueInfo: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    public let sport: String
    public let season: String
    public let totalRosters: Int
    public let status: String

    public init(
        id: String,
        name: String,
        sport: String,
        season: String,
        totalRosters: Int,
        status: String
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.season = season
        self.totalRosters = totalRosters
        self.status = status
    }
}

public struct SleeperPlayerSummary: Equatable, Codable, Sendable {
    public let playerID: String
    public let fullName: String
    public let position: String
    public let team: String
    public let espnID: String?

    public init(
        playerID: String,
        fullName: String,
        position: String,
        team: String,
        espnID: String? = nil
    ) {
        self.playerID = playerID
        self.fullName = fullName
        self.position = position
        self.team = team
        self.espnID = espnID
    }
}

public enum SleeperClientError: Error, Equatable, Sendable {
    case invalidURL
    case userNotFound
    case httpError(Int)
    case decodingFailed
}

/// Minimal Decodable projection for `/v1/players/{sport}` discarding unused bio fields to keep RAM low.
private struct RawSleeperPlayerProjection: Decodable {
    let playerID: String?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let position: String?
    let team: String?
    let espnID: String?

    enum CodingKeys: String, CodingKey {
        case playerID = "player_id"
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case position
        case team
        case espnID = "espn_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerID = try? container.decodeIfPresent(String.self, forKey: .playerID)
        fullName = try? container.decodeIfPresent(String.self, forKey: .fullName)
        firstName = try? container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try? container.decodeIfPresent(String.self, forKey: .lastName)
        position = try? container.decodeIfPresent(String.self, forKey: .position)
        team = try? container.decodeIfPresent(String.self, forKey: .team)
        if let str = try? container.decodeIfPresent(String.self, forKey: .espnID) {
            espnID = str
        } else if let num = try? container.decodeIfPresent(Int.self, forKey: .espnID) {
            espnID = String(num)
        } else {
            espnID = nil
        }
    }
}

/// Cookieless ephemeral client for Sleeper's public read-only API with 24h atomic player directory caching.
public actor SleeperClient {
    public static let cacheTTLSeconds: TimeInterval = 86_400

    private let session: URLSession
    private let cacheDirectory: URL
    private var memoryPlayerCache: [String: [String: SleeperPlayerSummary]] = [:]
    private var inFlightPlayerFetches: [String: Task<[String: SleeperPlayerSummary], Error>] = [:]

    public init(cacheDirectory: URL? = nil, session: URLSession? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.cacheDirectory = appSupport
                .appendingPathComponent("GlassGridYou", isDirectory: true)
                .appendingPathComponent("SleeperCache", isDirectory: true)
        }

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 25
            self.session = URLSession(configuration: config)
        }
    }

    public func fetchUser(username: String) async throws -> SleeperUser {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.sleeper.app/v1/user/\(encoded)") else {
            throw SleeperClientError.invalidURL
        }
        let data = try await fetchData(from: url)
        guard let user = Self.parseUser(from: data) else {
            throw SleeperClientError.userNotFound
        }
        return user
    }

    public func fetchSportState(sport: String) async throws -> SleeperSportState {
        let cleanSport = sport.lowercased()
        guard let url = URL(string: "https://api.sleeper.app/v1/state/\(cleanSport)") else {
            throw SleeperClientError.invalidURL
        }
        let data = try await fetchData(from: url)
        guard let state = Self.parseSportState(from: data) else {
            throw SleeperClientError.decodingFailed
        }
        return state
    }

    public func fetchLeagues(userID: String, sport: String, season: String) async throws -> [SleeperLeagueInfo] {
        guard let encodedUser = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedSeason = season.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.sleeper.app/v1/user/\(encodedUser)/leagues/\(sport.lowercased())/\(encodedSeason)") else {
            throw SleeperClientError.invalidURL
        }
        let data = try await fetchData(from: url)
        return Self.parseLeagues(from: data)
    }

    public func fetchMatchup(
        config: FantasyLeagueConfig,
        userID: String,
        week: Int
    ) async throws -> FantasyMatchup? {
        guard let sport = config.league.sleeperSportCode else { return nil }
        guard let encodedLeague = config.leagueID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let rostersURL = URL(string: "https://api.sleeper.app/v1/league/\(encodedLeague)/rosters"),
              let usersURL = URL(string: "https://api.sleeper.app/v1/league/\(encodedLeague)/users"),
              let matchupsURL = URL(string: "https://api.sleeper.app/v1/league/\(encodedLeague)/matchups/\(week)") else {
            throw SleeperClientError.invalidURL
        }

        async let rostersData = fetchData(from: rostersURL)
        async let usersData = fetchData(from: usersURL)
        async let matchupsData = fetchData(from: matchupsURL)
        async let players = loadPlayerDirectory(sport: sport)

        return try await Self.parseMatchup(
            config: config,
            week: week,
            userID: userID,
            rostersData: rostersData,
            usersData: usersData,
            matchupsData: matchupsData,
            players: players
        )
    }

    /// Loads projected Sleeper player directory with memory cache + 24h atomic disk cache + single-flight deduplication.
    public func loadPlayerDirectory(sport: String, now: Date = Date()) async throws -> [String: SleeperPlayerSummary] {
        let cleanSport = sport.lowercased()
        if let cachedInMem = memoryPlayerCache[cleanSport] {
            return cachedInMem
        }

        if let mtime = cacheLastUpdatedAt(sport: cleanSport),
           now.timeIntervalSince(mtime) < Self.cacheTTLSeconds,
           let diskData = try? Data(contentsOf: cacheFileURL(sport: cleanSport)),
           let decoded = try? JSONDecoder().decode([String: SleeperPlayerSummary].self, from: diskData),
           !decoded.isEmpty {
            memoryPlayerCache[cleanSport] = decoded
            return decoded
        }

        if let existingTask = inFlightPlayerFetches[cleanSport] {
            return try await existingTask.value
        }

        let sessionRef = self.session
        let cacheURL = cacheFileURL(sport: cleanSport)
        let dirURL = self.cacheDirectory

        let task = Task<[String: SleeperPlayerSummary], Error> {
            guard let url = URL(string: "https://api.sleeper.app/v1/players/\(cleanSport)") else {
                throw SleeperClientError.invalidURL
            }
            let (data, response) = try await sessionRef.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SleeperClientError.httpError(http.statusCode)
            }
            let projected = Self.parsePlayerDirectory(from: data)
            if !projected.isEmpty {
                try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                if let encoded = try? JSONEncoder().encode(projected) {
                    try? encoded.write(to: cacheURL, options: .atomic)
                }
            }
            return projected
        }

        inFlightPlayerFetches[cleanSport] = task
        defer { inFlightPlayerFetches.removeValue(forKey: cleanSport) }

        let result = try await task.value
        memoryPlayerCache[cleanSport] = result
        return result
    }

    /// Deletes cached `players-*.json` files on disk and evicts the in-memory player dictionary.
    public func clearCache() async {
        memoryPlayerCache.removeAll()
        for task in inFlightPlayerFetches.values {
            task.cancel()
        }
        inFlightPlayerFetches.removeAll()
        if let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in contents where file.lastPathComponent.hasPrefix("players-") && file.pathExtension == "json" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Evicts the in-memory player dictionary without removing the 24h disk cache.
    public func evictMemoryCache() async {
        memoryPlayerCache.removeAll()
    }

    /// Returns the disk cache file modification timestamp for `sport`, or `nil` if not cached.
    public func cacheLastUpdatedAt(sport: String) -> Date? {
        let url = cacheFileURL(sport: sport.lowercased())
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date else {
            return nil
        }
        return mtime
    }

    private func cacheFileURL(sport: String) -> URL {
        cacheDirectory.appendingPathComponent("players-\(sport).json", isDirectory: false)
    }

    private func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SleeperClientError.httpError(http.statusCode)
        }
        return data
    }

    // MARK: - Pure Offline JSON Parsers

    public nonisolated static func parseUser(from data: Data) -> SleeperUser? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userID = stringValue(root["user_id"]),
              !userID.isEmpty else {
            return nil
        }
        let username = stringValue(root["username"]) ?? userID
        let displayName = stringValue(root["display_name"]) ?? username
        return SleeperUser(userID: userID, username: username, displayName: displayName)
    }

    public nonisolated static func parseSportState(from data: Data) -> SleeperSportState? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let season = stringValue(root["season"]),
              let week = intValue(root["week"]) else {
            return nil
        }
        let seasonType = stringValue(root["season_type"]) ?? "regular"
        return SleeperSportState(season: season, week: week, seasonType: seasonType)
    }

    public nonisolated static func parseLeagues(from data: Data) -> [SleeperLeagueInfo] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { item in
            guard let id = stringValue(item["league_id"]),
                  let name = stringValue(item["name"]) else {
                return nil
            }
            let sport = stringValue(item["sport"]) ?? "nfl"
            let season = stringValue(item["season"]) ?? ""
            let totalRosters = intValue(item["total_rosters"]) ?? 0
            let status = stringValue(item["status"]) ?? "in_season"
            return SleeperLeagueInfo(
                id: id,
                name: name,
                sport: sport,
                season: season,
                totalRosters: totalRosters,
                status: status
            )
        }
    }

    public nonisolated static func parsePlayerDirectory(from data: Data) -> [String: SleeperPlayerSummary] {
        guard let rawDict = try? JSONDecoder().decode([String: RawSleeperPlayerProjection].self, from: data) else {
            return [:]
        }
        var result: [String: SleeperPlayerSummary] = [:]
        result.reserveCapacity(rawDict.count)
        for (key, item) in rawDict {
            let pid = item.playerID ?? key
            let combinedName = [item.firstName, item.lastName].compactMap { $0 }.joined(separator: " ")
            let fullName = (item.fullName?.isEmpty == false ? item.fullName : nil)
                ?? (combinedName.isEmpty ? pid : combinedName)
            let position = item.position ?? ""
            let team = item.team ?? "FA"
            result[pid] = SleeperPlayerSummary(
                playerID: pid,
                fullName: fullName,
                position: position,
                team: team,
                espnID: item.espnID
            )
        }
        return result
    }

    public nonisolated static func parseMatchup(
        config: FantasyLeagueConfig,
        week: Int,
        userID: String,
        rostersData: Data,
        usersData: Data,
        matchupsData: Data,
        players: [String: SleeperPlayerSummary]
    ) -> FantasyMatchup? {
        guard let rosters = try? JSONSerialization.jsonObject(with: rostersData) as? [[String: Any]],
              let users = try? JSONSerialization.jsonObject(with: usersData) as? [[String: Any]],
              let matchups = try? JSONSerialization.jsonObject(with: matchupsData) as? [[String: Any]] else {
            return nil
        }

        var teamNameByOwnerID: [String: String] = [:]
        for user in users {
            guard let uid = stringValue(user["user_id"]) else { continue }
            let metadata = user["metadata"] as? [String: Any]
            let teamName = stringValue(metadata?["team_name"])
                ?? stringValue(user["display_name"])
                ?? stringValue(user["username"])
                ?? "Team"
            teamNameByOwnerID[uid] = teamName
        }

        var ownerByRosterID: [Int: String] = [:]
        var userRosterID: Int?
        for roster in rosters {
            guard let rid = intValue(roster["roster_id"]) else { continue }
            let ownerID = stringValue(roster["owner_id"]) ?? ""
            ownerByRosterID[rid] = ownerID
            if ownerID == userID {
                userRosterID = rid
            } else if let coOwners = roster["co_owners"] as? [String], coOwners.contains(userID) {
                userRosterID = rid
            }
        }

        // Fall back to teamOwnerHint matching if userID wasn't matched directly.
        if userRosterID == nil, let hint = config.teamOwnerHint?.lowercased(), !hint.isEmpty {
            for (rid, ownerID) in ownerByRosterID {
                if ownerID.lowercased() == hint || teamNameByOwnerID[ownerID]?.lowercased().contains(hint) == true {
                    userRosterID = rid
                    break
                }
            }
        }

        guard let targetRosterID = userRosterID ?? rosters.compactMap({ intValue($0["roster_id"]) }).first,
              let userEntry = matchups.first(where: { intValue($0["roster_id"]) == targetRosterID }) else {
            return nil
        }

        let matchupID = intValue(userEntry["matchup_id"])
        let oppEntry = matchups.first {
            intValue($0["roster_id"]) != targetRosterID &&
            matchupID != nil &&
            intValue($0["matchup_id"]) == matchupID
        }

        let userTeamName = teamNameByOwnerID[ownerByRosterID[targetRosterID] ?? ""] ?? "Your Team"
        let oppRosterID = oppEntry.flatMap { intValue($0["roster_id"]) }
        let oppTeamName = oppRosterID.flatMap { teamNameByOwnerID[ownerByRosterID[$0] ?? ""] } ?? "Opponent"

        let userPoints = doubleValue(userEntry["points"]) ?? 0
        let oppPoints = doubleValue(oppEntry?["points"]) ?? 0

        let userStartersSet = Set((userEntry["starters"] as? [String]) ?? [])
        let userPlayerPoints = (userEntry["players_points"] as? [String: Any]) ?? [:]
        let userPlayers = (userEntry["players"] as? [String]) ?? Array(userStartersSet)

        var starters: [FantasyPlayerLine] = []
        var bench: [FantasyPlayerLine] = []
        for pid in userPlayers {
            let info = players[pid]
            let isStarter = userStartersSet.contains(pid)
            let pts = doubleValue(userPlayerPoints[pid]) ?? 0
            let line = FantasyPlayerLine(
                id: "sleeper:\(config.leagueID):\(pid)",
                espnPlayerID: info?.espnID,
                name: info?.fullName ?? pid,
                position: info?.position ?? "FLEX",
                nflOrProTeam: info?.team ?? "FA",
                points: pts,
                isStarter: isStarter,
                isUserRoster: true
            )
            if isStarter {
                starters.append(line)
            } else {
                bench.append(line)
            }
        }

        let oppStartersList = (oppEntry?["starters"] as? [String]) ?? []
        let oppPlayerPoints = (oppEntry?["players_points"] as? [String: Any]) ?? [:]
        let opponentStarters: [FantasyPlayerLine] = oppStartersList.map { pid in
            let info = players[pid]
            return FantasyPlayerLine(
                id: "sleeper:\(config.leagueID):opp:\(pid)",
                espnPlayerID: info?.espnID,
                name: info?.fullName ?? pid,
                position: info?.position ?? "FLEX",
                nflOrProTeam: info?.team ?? "FA",
                points: doubleValue(oppPlayerPoints[pid]) ?? 0,
                isStarter: true,
                isUserRoster: false
            )
        }

        return FantasyMatchup(
            id: "sleeper:\(config.leagueID):w\(week)",
            configID: config.id,
            provider: .sleeper,
            league: config.league,
            leagueName: config.leagueName,
            weekLabel: "Week \(week)",
            userTeamName: userTeamName,
            opponentTeamName: oppTeamName,
            userPoints: userPoints,
            opponentPoints: oppPoints,
            starters: starters,
            bench: bench,
            opponentStarters: opponentStarters
        )
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
