import CoreGraphics
import Foundation
import Testing
@testable import YouTubeMacCore

// MARK: - Deterministic Offline URLProtocol Stub

private final class LivePulseMockRouter: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (statusCode: Int, data: Data)

    static let shared = LivePulseMockRouter()

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    func register(id: String, handler: @escaping Handler) {
        lock.lock()
        handlers[id] = handler
        lock.unlock()
    }

    func unregister(id: String) {
        lock.lock()
        handlers.removeValue(forKey: id)
        lock.unlock()
    }

    func handler(for id: String) -> Handler? {
        lock.lock()
        let result = handlers[id]
        lock.unlock()
        return result
    }
}

private final class LivePulseMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let headerName = "X-LivePulse-Mock-ID"

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: headerName) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let mockID = request.value(forHTTPHeaderField: Self.headerName),
              let handler = LivePulseMockRouter.shared.handler(for: mockID),
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockSession(id: String, handler: @escaping LivePulseMockRouter.Handler) -> URLSession {
    LivePulseMockRouter.shared.register(id: id, handler: handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LivePulseMockURLProtocol.self]
    config.httpAdditionalHeaders = [LivePulseMockURLProtocol.headerName: id]
    config.httpCookieAcceptPolicy = .never
    config.httpShouldSetCookies = false
    return URLSession(configuration: config)
}

private func makeSampleGame(
    id: String,
    league: SportsLeague,
    awayCode: String,
    awayName: String,
    homeCode: String,
    homeName: String,
    status: GameStatus = .live,
    broadcasts: [String] = []
) -> LiveGame {
    LiveGame(
        id: id,
        league: league,
        status: status,
        statusDetail: status == .live ? "Q3 8:42" : "Final",
        clock: "8:42",
        period: 3,
        away: TeamScore(espnTeamID: "\(id)-a", abbreviation: awayCode, displayName: awayName, shortName: awayName, score: 21),
        home: TeamScore(espnTeamID: "\(id)-h", abbreviation: homeCode, displayName: homeName, shortName: homeName, score: 17),
        broadcasts: broadcasts
    )
}

// MARK: - 1. SportsEntityMatcher & StreamContextHysteresis

@Suite("SportsEntityMatcher & Hysteresis")
struct SportsEntityMatcherTests {
    @Test("Canonical team lexicons cover NFL 32, NBA 30, MLB 30, NHL 32 and normalize Kalshi/ESPN tricodes")
    func teamLexiconCountsAndTricodeNormalization() {
        #expect(SportsEntityMatcher.nflTeams.count == 32)
        #expect(SportsEntityMatcher.nbaTeams.count == 30)
        #expect(SportsEntityMatcher.mlbTeams.count == 30)
        #expect(SportsEntityMatcher.nhlTeams.count == 32)

        #expect(SportsEntityMatcher.canonicalESPNCode("WSH", league: .nfl) == "WAS")
        #expect(SportsEntityMatcher.canonicalESPNCode("LA", league: .nfl) == "LAR")
        #expect(SportsEntityMatcher.canonicalESPNCode("JAC", league: .nfl) == "JAX")
        #expect(SportsEntityMatcher.canonicalESPNCode("GSW", league: .nba) == "GS")
        #expect(SportsEntityMatcher.canonicalESPNCode("CWS", league: .mlb) == "CHW")
        #expect(SportsEntityMatcher.canonicalESPNCode("LAK", league: .nhl) == "LA")
    }

    @Test("Direct URL extractors parse NFL+, MLB.TV, NBA, and Apple TV+ routes")
    func urlMatchHintExtractionAcrossSportsPlatforms() {
        let nflGame = SportsEntityMatcher.extractURLMatchHint(
            from: URL(string: "https://www.nfl.com/plus/games/chiefs-at-bills")!
        )
        #expect(nflGame?.league == .nfl)
        #expect(nflGame?.awayTeamCode == "KC")
        #expect(nflGame?.homeTeamCode == "BUF")

        let nflRedZone = SportsEntityMatcher.extractURLMatchHint(
            from: URL(string: "https://www.nfl.com/plus/live/nfl-redzone")!
        )
        #expect(nflRedZone?.league == .nfl)
        #expect(nflRedZone?.liveSlateLabel == "NFL RedZone")

        let mlbShort = SportsEntityMatcher.extractURLMatchHint(
            from: URL(string: "https://www.mlb.com/tv/g745123")!
        )
        #expect(mlbShort?.league == .mlb)
        #expect(mlbShort?.externalEventID == "745123")

        let mlbLong = SportsEntityMatcher.extractURLMatchHint(
            from: URL(string: "https://www.mlb.com/tv/games/745999")!
        )
        #expect(mlbLong?.league == .mlb)
        #expect(mlbLong?.externalEventID == "745999")

        let nba = SportsEntityMatcher.extractURLMatchHint(
            from: URL(string: "https://www.nba.com/game/lal-vs-bos-0022400123")!
        )
        #expect(nba?.league == .nba)
        #expect(nba?.awayTeamCode == "LAL")
        #expect(nba?.homeTeamCode == "BOS")

        let appleTV = SportsEntityMatcher.extractURLMatchHint(
            from: URL(string: "https://tv.apple.com/us/sporting-event/dodgers-at-yankees")!
        )
        #expect(appleTV?.league == .mlb)
        #expect(appleTV?.awayTeamCode == "LAD")
        #expect(appleTV?.homeTeamCode == "NYY")
    }

    @Test("Matchup parser matches 'vs', '@', 'at', and URL hints to live games")
    func matchupAndSingleTeamTitleDetection() {
        let games = [
            makeSampleGame(id: "nfl-1", league: .nfl, awayCode: "KC", awayName: "Kansas City Chiefs", homeCode: "BUF", homeName: "Buffalo Bills", broadcasts: ["CBS"]),
            makeSampleGame(id: "nba-1", league: .nba, awayCode: "LAL", awayName: "Los Angeles Lakers", homeCode: "BOS", homeName: "Boston Celtics", broadcasts: ["TNT"])
        ]

        let nflSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://tv.youtube.com/watch/abc")!,
            title: "Chiefs vs Bills - NFL on CBS - YouTube TV"
        )
        #expect(
            SportsEntityMatcher.match(signal: nflSignal, games: games) ==
            .matchedGame(gameID: "nfl-1", league: .nfl, confidence: .high, sourceLabel: "KC @ BUF")
        )

        let nbaSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://www.nba.com/watch")!,
            title: "LAL @ BOS Live Stream"
        )
        #expect(
            SportsEntityMatcher.match(signal: nbaSignal, games: games) ==
            .matchedGame(gameID: "nba-1", league: .nba, confidence: .high, sourceLabel: "LAL @ BOS")
        )
    }

    @Test("Live slate triggers and broadcast network extraction handle whip-around feeds and fallback")
    func liveSlateAndBroadcastNetworkExtraction() {
        let yttvURL = URL(string: "https://tv.youtube.com/watch/redzone")!
        #expect(
            SportsEntityMatcher.detectLiveSlate(from: "NFL RedZone - Sunday Whip-Around", url: yttvURL) ==
            .liveSlate(league: .nfl, label: "NFL RedZone")
        )
        #expect(
            SportsEntityMatcher.detectLiveSlate(from: "MLB Big Inning Live", url: URL(string: "https://www.mlb.com/tv")!) ==
            .liveSlate(league: .mlb, label: "MLB Big Inning")
        )
        #expect(
            SportsEntityMatcher.detectLiveSlate(from: "NBA CrunchTime", url: URL(string: "https://www.nba.com/watch")!) ==
            .liveSlate(league: .nba, label: "NBA CrunchTime")
        )
        #expect(
            SportsEntityMatcher.detectLiveSlate(from: "NHL Frozen Frenzy", url: URL(string: "https://www.espn.com/watch")!) ==
            .liveSlate(league: .nhl, label: "NHL Frozen Frenzy")
        )

        // Generic "redzone" without NFL/sports cue on standard YouTube should not false-trigger.
        #expect(
            SportsEntityMatcher.detectLiveSlate(
                from: "RedZone Gaming Montage",
                url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
            ) == nil
        )

        #expect(SportsEntityMatcher.extractBroadcastNetwork(from: "Sunday Night Football on NBC") == "NBC")
        #expect(SportsEntityMatcher.extractBroadcastNetwork(from: "Inside the NBA on TNT") == "TNT")
        #expect(SportsEntityMatcher.extractBroadcastNetwork(from: "Live Stream", serviceID: "peacock") == "Peacock")

        let nbcGame = makeSampleGame(id: "nfl-snf", league: .nfl, awayCode: "DAL", awayName: "Dallas Cowboys", homeCode: "PHI", homeName: "Philadelphia Eagles", broadcasts: ["NBC"])
        let networkSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://tv.youtube.com/watch/nbc")!,
            title: "Sunday Night Football Pregame - NBC"
        )
        #expect(
            SportsEntityMatcher.match(signal: networkSignal, games: [nbcGame]) ==
            .matchedGame(gameID: "nfl-snf", league: .nfl, confidence: .medium, sourceLabel: "Auto · NBC")
        )
    }

    @Test("Strict ambiguous-nickname guard rejects standalone Cardinals/Giants/Jets/Kings and auth/browse routes")
    func ambiguousNicknameAndAuthBrowseRejection() {
        let activeGames = [
            makeSampleGame(id: "nfl-ari", league: .nfl, awayCode: "ARI", awayName: "Arizona Cardinals", homeCode: "SEA", homeName: "Seattle Seahawks"),
            makeSampleGame(id: "nfl-nyg", league: .nfl, awayCode: "NYG", awayName: "New York Giants", homeCode: "NYJ", homeName: "New York Jets"),
            makeSampleGame(id: "nba-sac", league: .nba, awayCode: "SAC", awayName: "Sacramento Kings", homeCode: "GS", homeName: "Golden State Warriors")
        ]

        let nonSportsTitles = [
            "Cardinals Feeding in Backyard 4K HDR",
            "Giants of Engineering Documentary",
            "Private Jets Tour Inside $75M Cabin",
            "Three Kings Movie Ending Explained"
        ]
        for title in nonSportsTitles {
            let signal = StreamSignal(
                tabID: UUID(),
                windowID: UUID(),
                url: URL(string: "https://www.youtube.com/watch?v=abc123456")!,
                title: title
            )
            #expect(SportsEntityMatcher.match(signal: signal, games: activeGames) == .none)
        }

        let authSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://tv.youtube.com/browse")!,
            title: "Chiefs vs Bills",
            isAuthOrBrowse: true
        )
        #expect(SportsEntityMatcher.match(signal: authSignal, games: activeGames) == .none)
    }

    @Test("StreamContextHysteresis holds matched game for 90s across ad breaks and clears on expiry or browse")
    func streamContextHysteresisNinetySecondRetention() {
        var hysteresis = StreamContextHysteresis()
        let tabID = UUID()
        let windowID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let gameContext = StreamSportContext.matchedGame(
            gameID: "nfl-1",
            league: .nfl,
            confidence: .high,
            sourceLabel: "KC @ BUF"
        )
        let watchSignal = StreamSignal(
            tabID: tabID,
            windowID: windowID,
            url: URL(string: "https://tv.youtube.com/watch/game1")!,
            title: "Chiefs vs Bills"
        )
        #expect(hysteresis.resolve(signal: watchSignal, rawContext: gameContext, at: t0) == gameContext)

        let commercialSignal = StreamSignal(
            tabID: tabID,
            windowID: windowID,
            url: URL(string: "https://tv.youtube.com/watch/game1")!,
            title: "Advertisement - YouTube TV"
        )
        #expect(hysteresis.resolve(signal: commercialSignal, rawContext: .none, at: t0.addingTimeInterval(45)) == gameContext)
        #expect(hysteresis.resolve(signal: commercialSignal, rawContext: .none, at: t0.addingTimeInterval(90)) == gameContext)
        #expect(hysteresis.resolve(signal: commercialSignal, rawContext: .none, at: t0.addingTimeInterval(91)) == .none)

        // Re-confirm then verify immediate clear on auth/browse route even within 90s.
        _ = hysteresis.resolve(signal: watchSignal, rawContext: gameContext, at: t0.addingTimeInterval(100))
        let browseSignal = StreamSignal(
            tabID: tabID,
            windowID: windowID,
            url: URL(string: "https://tv.youtube.com/live")!,
            title: "YouTube TV Guide",
            isAuthOrBrowse: true
        )
        #expect(hysteresis.resolve(signal: browseSignal, rawContext: .none, at: t0.addingTimeInterval(105)) == .none)
        #expect(hysteresis.resolve(signal: commercialSignal, rawContext: .none, at: t0.addingTimeInterval(106)) == .none)
    }
}

// MARK: - 2. SpoilerDelayBuffer

@Suite("SpoilerDelayBuffer")
struct SpoilerDelayBufferTests {
    @Test("Emits immediately at 0s, holds until 20s/35s, and evicts oldest on bounded overflow")
    func spoilerDelayBufferImmediateDelayedAndEviction() {
        var buffer = SpoilerDelayBuffer<String>(maxEntries: 3)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        buffer.enqueue("event-1", at: t0)
        #expect(buffer.latestReady(at: t0, delay: .off) == "event-1")
        #expect(buffer.drainReady(at: t0, delay: .off) == ["event-1"])
        #expect(buffer.isEmpty)

        // 20s delay check
        buffer.enqueue("td-pass", at: t0)
        buffer.enqueue("xp-good", at: t0.addingTimeInterval(5))
        #expect(buffer.drainReady(at: t0.addingTimeInterval(19), delay: .seconds20) == [])
        #expect(buffer.latestReady(at: t0.addingTimeInterval(20), delay: .seconds20) == "td-pass")
        #expect(buffer.drainReady(at: t0.addingTimeInterval(20), delay: .seconds20) == ["td-pass"])
        #expect(buffer.drainReady(at: t0.addingTimeInterval(25), delay: .seconds20) == ["xp-good"])

        // 35s delay check
        buffer.enqueue("goal", at: t0)
        #expect(buffer.drainReady(at: t0.addingTimeInterval(34), delay: .seconds35) == [])
        #expect(buffer.drainReady(at: t0.addingTimeInterval(35), delay: .seconds35) == ["goal"])

        // Bounded capacity eviction (maxEntries == 3)
        for i in 1...5 {
            buffer.enqueue("item-\(i)", at: t0.addingTimeInterval(Double(i)))
        }
        #expect(buffer.count == 3)
        #expect(buffer.drainReady(at: t0.addingTimeInterval(10), delay: .off) == ["item-3", "item-4", "item-5"])
    }
}

// MARK: - 3. ESPNScoreboardClient

@Suite("ESPNScoreboardClient")
struct ESPNScoreboardClientTests {
    @Test("Parses live scoreboard status, broadcasts, red zone situation, and odds from offline JSON")
    func espnScoreboardParserExtractsLiveStatusBroadcastsAndRedZone() throws {
        let json = """
        {
          "events": [
            {
              "id": "401671789",
              "date": "2026-11-22T21:25Z",
              "competitions": [
                {
                  "date": "2026-11-22T21:25Z",
                  "status": {
                    "displayClock": "02:14",
                    "period": 4,
                    "type": {
                      "name": "STATUS_IN_PROGRESS",
                      "state": "in",
                      "shortDetail": "2:14 - 4th"
                    }
                  },
                  "broadcasts": [
                    { "names": ["CBS"] }
                  ],
                  "geoBroadcasts": [
                    { "media": { "shortName": "Paramount+" } }
                  ],
                  "situation": {
                    "possession": "12",
                    "downDistanceText": "1st & Goal at BUF 7",
                    "isRedZone": true,
                    "possessionText": "BUF 7"
                  },
                  "odds": [
                    { "details": "KC -2.5", "overUnder": 48.5 }
                  ],
                  "competitors": [
                    {
                      "homeAway": "away",
                      "score": "24",
                      "team": { "id": "12", "abbreviation": "KC", "displayName": "Kansas City Chiefs", "shortDisplayName": "Chiefs" },
                      "records": [{ "summary": "9-1" }]
                    },
                    {
                      "homeAway": "home",
                      "score": "21",
                      "team": { "id": "2", "abbreviation": "BUF", "displayName": "Buffalo Bills", "shortDisplayName": "Bills" },
                      "records": [{ "summary": "8-2" }]
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let games = ESPNScoreboardClient.parseScoreboard(from: data, league: .nfl)
        #expect(games.count == 1)

        let game = games[0]
        #expect(game.id == "401671789")
        #expect(game.league == .nfl)
        #expect(game.status == .live)
        #expect(game.statusDetail == "2:14 - 4th")
        #expect(game.clock == "02:14")
        #expect(game.period == 4)
        #expect(game.away.abbreviation == "KC")
        #expect(game.away.score == 24)
        #expect(game.away.isPossession == true)
        #expect(game.home.abbreviation == "BUF")
        #expect(game.home.score == 21)
        #expect(game.home.isPossession == false)
        #expect(game.broadcasts == ["CBS", "Paramount+"])
        #expect(game.situation?.isRedZone == true)
        #expect(game.situation?.downDistanceText == "1st & Goal at BUF 7")
        #expect(game.spreadSummary == "KC -2.5")
        #expect(game.overUnder == 48.5)
    }

    @Test("Parses summary winprobability, pickcenter, situation, and boxscore athlete stats")
    func espnSummaryParserExtractsWinProbPickcenterAndBoxscore() throws {
        let json = """
        {
          "situation": {
            "possession": "12",
            "downDistanceText": "2nd & 4 at BUF 14",
            "isRedZone": true
          },
          "winprobability": [
            { "homeWinPercentage": 0.52 },
            { "homeWinPercentage": 0.34 }
          ],
          "pickcenter": [
            { "details": "KC -2.5", "overUnder": 49.0 }
          ],
          "boxscore": {
            "players": [
              {
                "statistics": [
                  {
                    "labels": ["C/ATT", "YDS", "TD"],
                    "athletes": [
                      {
                        "athlete": { "id": "3139477" },
                        "stats": ["24/32", "298", "3"]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let update = try #require(ESPNScoreboardClient.parseSummary(from: data, eventID: "401671789", league: .nfl))

        #expect(update.situation?.isRedZone == true)
        #expect(update.homeWinProb == 0.34)
        #expect(abs((update.awayWinProb ?? 0) - 0.66) < 0.0001)
        #expect(update.spreadSummary == "KC -2.5")
        #expect(update.overUnder == 49.0)
        #expect(update.athleteStats["3139477"] == "24/32 · 298 yds · 3 TD")
    }
}

// MARK: - 4. SleeperClient

@Suite("SleeperClient")
struct SleeperClientTests {
    @Test("Parses user, sport state, leagues, projected players, and matchup rosters offline")
    func sleeperParsersDecodeUserStateLeaguesPlayersAndMatchup() throws {
        let userData = Data(#"{"user_id":"u100","username":"zach","display_name":"Zach"}"#.utf8)
        let user = try #require(SleeperClient.parseUser(from: userData))
        #expect(user == SleeperUser(userID: "u100", username: "zach", displayName: "Zach"))

        let stateData = Data(#"{"season":"2026","week":12,"season_type":"regular"}"#.utf8)
        let state = try #require(SleeperClient.parseSportState(from: stateData))
        #expect(state == SleeperSportState(season: "2026", week: 12, seasonType: "regular"))

        let leaguesData = Data(#"[{"league_id":"lg1","name":"Sunday Legends","sport":"nfl","season":"2026","total_rosters":12,"status":"in_season"}]"#.utf8)
        let leagues = SleeperClient.parseLeagues(from: leaguesData)
        #expect(leagues.count == 1)
        #expect(leagues[0].name == "Sunday Legends")

        let playersJSON = Data("""
        {
          "4046": { "player_id": "4046", "full_name": "Patrick Mahomes", "position": "QB", "team": "KC", "espn_id": 3139477 },
          "6794": { "player_id": "6794", "first_name": "Justin", "last_name": "Jefferson", "position": "WR", "team": "MIN", "espn_id": "4262921" }
        }
        """.utf8)
        let players = SleeperClient.parsePlayerDirectory(from: playersJSON)
        #expect(players["4046"]?.espnID == "3139477")
        #expect(players["6794"]?.fullName == "Justin Jefferson")

        let rostersData = Data(#"[{"roster_id":1,"owner_id":"u100"},{"roster_id":2,"owner_id":"u200"}]"#.utf8)
        let usersData = Data(#"[{"user_id":"u100","display_name":"Zach","metadata":{"team_name":"Gridiron Glass"}},{"user_id":"u200","display_name":"Alex"}]"#.utf8)
        let matchupsData = Data("""
        [
          {
            "roster_id": 1,
            "matchup_id": 7,
            "points": 112.4,
            "starters": ["4046"],
            "players": ["4046", "6794"],
            "players_points": { "4046": 26.8, "6794": 18.2 }
          },
          {
            "roster_id": 2,
            "matchup_id": 7,
            "points": 98.1,
            "starters": ["6794"],
            "players": ["6794"],
            "players_points": { "6794": 18.2 }
          }
        ]
        """.utf8)

        let config = FantasyLeagueConfig(id: "sleeper:lg1", provider: .sleeper, league: .nfl, leagueID: "lg1", leagueName: "Sunday Legends", season: 2026)
        let matchup = try #require(
            SleeperClient.parseMatchup(
                config: config,
                week: 12,
                userID: "u100",
                rostersData: rostersData,
                usersData: usersData,
                matchupsData: matchupsData,
                players: players
            )
        )
        #expect(matchup.userTeamName == "Gridiron Glass")
        #expect(matchup.opponentTeamName == "Alex")
        #expect(matchup.userPoints == 112.4)
        #expect(matchup.opponentPoints == 98.1)
        #expect(matchup.starters.map(\.name) == ["Patrick Mahomes"])
        #expect(matchup.starters.first?.espnPlayerID == "3139477")
        #expect(matchup.bench.map(\.name) == ["Justin Jefferson"])
        #expect(matchup.opponentStarters.map(\.name) == ["Justin Jefferson"])
    }

    @Test("Sleeper player directory enforces 24h temp-directory atomic disk cache, memory eviction, and clearCache")
    func sleeperDiskCacheHitExpiryEvictAndClear() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassGridYou-SleeperCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mockID = "sleeper-cache-\(UUID().uuidString)"
        defer { LivePulseMockRouter.shared.unregister(id: mockID) }

        final class FetchCounter: @unchecked Sendable {
            private let lock = NSLock()
            var count = 0
            func increment() -> Int {
                lock.lock()
                count += 1
                let current = count
                lock.unlock()
                return current
            }
        }
        let counter = FetchCounter()

        let session = makeMockSession(id: mockID) { _ in
            let fetchNum = counter.increment()
            let name = fetchNum == 1 ? "Patrick Mahomes" : "Josh Allen"
            let payload = Data("""
            {
              "4046": { "player_id": "4046", "full_name": "\(name)", "position": "QB", "team": "KC", "espn_id": "3139477" }
            }
            """.utf8)
            return (200, payload)
        }

        let client = SleeperClient(cacheDirectory: tempDir, session: session)
        let now = Date()

        // 1. Cold fetch hits mocked network once and writes players-nfl.json atomically.
        let initial = try await client.loadPlayerDirectory(sport: "nfl", now: now)
        #expect(initial["4046"]?.fullName == "Patrick Mahomes")
        #expect(counter.count == 1)
        #expect(await client.cacheLastUpdatedAt(sport: "nfl") != nil)

        // 2. Evict memory cache -> within 24h TTL hits disk cache with 0 network requests.
        await client.evictMemoryCache()
        let fromDisk = try await client.loadPlayerDirectory(sport: "nfl", now: now.addingTimeInterval(3600))
        #expect(fromDisk["4046"]?.fullName == "Patrick Mahomes")
        #expect(counter.count == 1)

        // 3. Evict memory cache -> past 24h TTL refreshes from network.
        await client.evictMemoryCache()
        let refreshed = try await client.loadPlayerDirectory(sport: "nfl", now: now.addingTimeInterval(SleeperClient.cacheTTLSeconds + 10))
        #expect(refreshed["4046"]?.fullName == "Josh Allen")
        #expect(counter.count == 2)

        // 4. clearCache removes disk file and memory cache.
        await client.clearCache()
        #expect(await client.cacheLastUpdatedAt(sport: "nfl") == nil)
    }
}

// MARK: - 5. ESPNFantasyClient

@Suite("ESPNFantasyClient")
struct ESPNFantasyClientTests {
    @Test("Parses public ESPN fantasy matchup, owner hint, and starter/bench split offline")
    func espnFantasyPublicMatchupParserAndFallbackStats() throws {
        let json = """
        {
          "scoringPeriodId": 12,
          "status": { "currentMatchupPeriod": 12 },
          "settings": { "name": "GlassGrid Public League" },
          "teams": [
            {
              "id": 1,
              "abbrev": "ALT",
              "location": "Other",
              "nickname": "Squad",
              "roster": { "entries": [] }
            },
            {
              "id": 4,
              "abbrev": "GGY",
              "name": "Zach's Champions",
              "roster": {
                "entries": [
                  {
                    "lineupSlotId": 0,
                    "playerPoolEntry": {
                      "appliedStatTotal": 24.6,
                      "player": { "id": 3139477, "fullName": "Patrick Mahomes", "defaultPositionId": 1, "proTeamId": 12 }
                    }
                  },
                  {
                    "lineupSlotId": 20,
                    "playerPoolEntry": {
                      "appliedStatTotal": 0,
                      "player": {
                        "id": 4262921,
                        "fullName": "Justin Jefferson",
                        "defaultPositionId": 3,
                        "proTeamId": 16,
                        "stats": [{ "scoringPeriodId": 12, "statSourceId": 0, "appliedTotal": 14.3 }]
                      }
                    }
                  }
                ]
              }
            }
          ],
          "schedule": [
            {
              "matchupPeriodId": 12,
              "home": { "teamId": 4, "totalPoints": 118.4, "totalProjectedPointsLive": 131.2 },
              "away": { "teamId": 1, "totalPoints": 102.0, "totalProjectedPointsLive": 110.5 }
            }
          ]
        }
        """
        let config = FantasyLeagueConfig(
            id: "espn:998877",
            provider: .espnPublic,
            league: .nfl,
            leagueID: "998877",
            leagueName: "Fallback Name",
            season: 2026,
            teamOwnerHint: "GGY"
        )
        let data = try #require(json.data(using: .utf8))
        let matchup = try #require(ESPNFantasyClient.parsePublicMatchup(from: data, config: config))

        #expect(matchup.leagueName == "GlassGrid Public League")
        #expect(matchup.weekLabel == "Period 12")
        #expect(matchup.userTeamName == "Zach's Champions")
        #expect(matchup.opponentTeamName == "Other Squad")
        #expect(matchup.userPoints == 118.4)
        #expect(matchup.userProjected == 131.2)
        #expect(matchup.starters.count == 1)
        #expect(matchup.starters[0].name == "Patrick Mahomes")
        #expect(matchup.starters[0].position == "QB")
        #expect(matchup.starters[0].nflOrProTeam == "KC")
        #expect(matchup.bench.count == 1)
        #expect(matchup.bench[0].points == 14.3)
        #expect(matchup.bench[0].nflOrProTeam == "MIN")
    }

    @Test("Maps HTTP 401 and 403 responses to privateLeagueRequiresWebTile")
    func espnFantasyPrivateLeague401And403RequireWebTile() async {
        let config = FantasyLeagueConfig(
            id: "espn:12345",
            provider: .espnPublic,
            league: .nfl,
            leagueID: "12345",
            leagueName: "Private League",
            season: 2026
        )

        for statusCode in [401, 403] {
            let mockID = "espn-auth-\(statusCode)-\(UUID().uuidString)"
            defer { LivePulseMockRouter.shared.unregister(id: mockID) }

            let session = makeMockSession(id: mockID) { _ in
                (statusCode, Data("{\"message\":\"Not Authorized\"}".utf8))
            }
            let client = ESPNFantasyClient(session: session)

            await #expect(throws: ESPNFantasyError.privateLeagueRequiresWebTile) {
                _ = try await client.fetchPublicMatchup(config: config)
            }
        }
    }
}

// MARK: - 6. PredictionMarketsClient & ProbabilityDeltaTracker

@Suite("PredictionMarketsClient & ProbabilityDeltaTracker")
struct PredictionMarketsClientTests {
    @Test("Parses Kalshi fixed-point _dollars strings and falls back cleanly to legacy cents")
    func kalshiFixedPointDollarsAndLegacyCentsParsing() throws {
        #expect(PredictionMarketsClient.parseFixedPointDollars("0.6850") == 0.685)
        #expect(PredictionMarketsClient.parseFixedPointDollars("1.25") == 1.0)
        #expect(PredictionMarketsClient.parseFixedPointDollars("-0.10") == 0.0)
        #expect(PredictionMarketsClient.parseFixedPointDollars("invalid") == nil)

        let json = """
        {
          "events": [
            {
              "event_ticker": "KXNFLGAME-26NOV22KCBUF",
              "title": "Chiefs at Bills",
              "markets": [
                {
                  "ticker": "KXNFLGAME-26NOV22KCBUF-KC",
                  "title": "Chiefs win at Bills",
                  "yes_sub_title": "Kansas City",
                  "yes_bid_dollars": "0.6800",
                  "yes_ask_dollars": "0.6900",
                  "volume_fp": "125430.50"
                },
                {
                  "ticker": "KXNFLGAME-26NOV22KCBUF-BUF",
                  "title": "Bills win vs Chiefs",
                  "yes_sub_title": "Buffalo",
                  "yes_bid": 31,
                  "yes_ask": 33,
                  "volume": 84200
                }
              ]
            }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let quotes = PredictionMarketsClient.parseKalshiEvents(from: data, league: .nfl)
        #expect(quotes.count == 2)

        #expect(quotes[0].provider == .kalshi)
        #expect(quotes[0].outcomeLabel == "Kansas City")
        #expect(abs(quotes[0].yesProbability - 0.685) < 0.0001)
        #expect(quotes[0].volumeUSD == 125_430.50)

        #expect(quotes[1].outcomeLabel == "Buffalo")
        #expect(abs(quotes[1].yesProbability - 0.32) < 0.0001)
        #expect(quotes[1].volumeUSD == 84_200)
    }

    @Test("Parses Polymarket Gamma sports events and filters by requested leagues")
    func polymarketGammaSportsEventsParsingAndFiltering() throws {
        let json = """
        [
          {
            "slug": "nfl-chiefs-vs-bills-2026",
            "title": "NFL: Chiefs vs Bills",
            "tags": [{ "slug": "nfl", "label": "NFL" }],
            "markets": [
              {
                "id": "m1",
                "question": "Will Kansas City Chiefs beat Buffalo Bills?",
                "outcomes": "[\\"Chiefs\\", \\"Bills\\"]",
                "outcomePrices": "[\\"0.64\\", \\"0.36\\"]",
                "clobTokenIds": "[\\"token-kc-1\\", \\"token-buf-2\\"]",
                "volumeNum": 450120.25
              }
            ]
          },
          {
            "slug": "nba-lakers-celtics",
            "title": "NBA: Lakers at Celtics",
            "tags": [{ "slug": "nba", "label": "NBA" }],
            "markets": [
              {
                "id": "m2",
                "question": "Lakers vs Celtics Winner",
                "outcomes": ["Lakers", "Celtics"],
                "outcomePrices": ["0.42", "0.58"],
                "clobTokenIds": ["token-lal-1", "token-bos-2"],
                "volume": "190000"
              }
            ]
          }
        ]
        """
        let data = try #require(json.data(using: .utf8))
        let nflOnly = PredictionMarketsClient.parsePolymarketEvents(from: data, leagues: [.nfl])
        #expect(nflOnly.count == 1)
        #expect(nflOnly[0].id == "polymarket:token-kc-1")
        #expect(nflOnly[0].league == .nfl)
        #expect(nflOnly[0].outcomeLabel == "Chiefs")
        #expect(abs(nflOnly[0].yesProbability - 0.64) < 0.0001)
        #expect(nflOnly[0].externalURLString == "https://polymarket.com/event/nfl-chiefs-vs-bills-2026")
    }

    @Test("Parses Polymarket CLOB WebSocket array and object frames and ignores plain PONG")
    func polymarketCLOBWebSocketFramesAndPongIgnore() throws {
        let ts = Date(timeIntervalSince1970: 1_700_000_500)

        // 1. Top-level array of book snapshots
        let bookArrayData = Data("""
        [
          {
            "event_type": "book",
            "asset_id": "asset-book-1",
            "bids": [{ "price": "0.61", "size": "100" }],
            "asks": [{ "price": "0.63", "size": "120" }]
          }
        ]
        """.utf8)
        let bookTicks = PredictionMarketsClient.parsePolymarketWSMessage(from: bookArrayData, at: ts)
        #expect(bookTicks.count == 1)
        #expect(bookTicks[0].assetID == "asset-book-1")
        #expect(abs(bookTicks[0].probability - 0.62) < 0.0001)

        // 2. price_change with nested price_changes array
        let priceChangeData = Data("""
        {
          "event_type": "price_change",
          "price_changes": [
            { "asset_id": "asset-pc-1", "best_bid": "0.70", "best_ask": "0.74" },
            { "asset_id": "asset-pc-2", "price": "0.28" }
          ]
        }
        """.utf8)
        let pcTicks = PredictionMarketsClient.parsePolymarketWSMessage(from: priceChangeData, at: ts)
        #expect(pcTicks.count == 2)
        #expect(pcTicks[0].assetID == "asset-pc-1")
        #expect(abs(pcTicks[0].probability - 0.72) < 0.0001)
        #expect(pcTicks[1].assetID == "asset-pc-2")
        #expect(abs(pcTicks[1].probability - 0.28) < 0.0001)

        // 3. best_bid_ask object
        let bbaData = Data(#"{"event_type":"best_bid_ask","asset_id":"asset-bba","best_bid":"0.55","best_ask":"0.59"}"#.utf8)
        let bbaTicks = PredictionMarketsClient.parsePolymarketWSMessage(from: bbaData, at: ts)
        #expect(bbaTicks.count == 1)
        #expect(abs(bbaTicks[0].probability - 0.57) < 0.0001)

        // 4. last_trade_price object
        let ltpData = Data(#"{"event_type":"last_trade_price","asset_id":"asset-ltp","price":"0.81"}"#.utf8)
        let ltpTicks = PredictionMarketsClient.parsePolymarketWSMessage(from: ltpData, at: ts)
        #expect(ltpTicks.count == 1)
        #expect(abs(ltpTicks[0].probability - 0.81) < 0.0001)

        // 5. Plain-text PONG is safely ignored
        let pongTicks = PredictionMarketsClient.parsePolymarketWSMessage(from: Data("PONG".utf8), at: ts)
        #expect(pongTicks.isEmpty)
    }

    @Test("ProbabilityDeltaTracker calculates rolling 1m/5m deltas and bounds samples per market")
    func probabilityDeltaTracker1m5mAndEviction() {
        var tracker = ProbabilityDeltaTracker(maxSamplesPerMarket: 4)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        tracker.record(marketID: "m1", probability: 0.50, at: t0)
        tracker.record(marketID: "m1", probability: 0.55, at: t0.addingTimeInterval(240)) // 4m in (1m before 5m)
        tracker.record(marketID: "m1", probability: 0.62, at: t0.addingTimeInterval(300))

        let deltas = tracker.deltas(for: "m1", currentProbability: 0.62, at: t0.addingTimeInterval(300))
        #expect(abs((deltas.delta1m ?? 0) - 0.07) < 0.0001)
        #expect(abs((deltas.delta5m ?? 0) - 0.12) < 0.0001)

        // Bounded sample cap eviction (maxSamplesPerMarket == 4)
        for i in 1...6 {
            tracker.record(marketID: "m1", probability: 0.60, at: t0.addingTimeInterval(300 + Double(i)))
        }
        #expect(tracker.sampleCount(for: "m1") == 4)
    }
}

// MARK: - 7. LivePulseLayout & CompanionQuickSite

@Suite("LivePulseLayout & CompanionQuickSite")
struct LivePulseLayoutAndCatalogTests {
    @Test("LivePulseLayout preserves >= 480pt web content at 780pt min width, enforces 1060pt threshold, and clamps non-negatively")
    func livePulseLayoutClampingNarrowWindowAndInsets() {
        // Below-topHeaderBar drawer card insets & constants (#13 Contract Addendum)
        #expect(LivePulseLayout.tickerHeight == 30)
        #expect(LivePulseLayout.drawerDefaultWidth == 320)
        #expect(LivePulseLayout.drawerMinWidth == 280)
        #expect(LivePulseLayout.drawerMaxWidth == 440)
        #expect(LivePulseLayout.drawerDividerWidth == 6)
        #expect(LivePulseLayout.drawerCardTopInset == 4)
        #expect(LivePulseLayout.drawerCardBottomInset == 8)
        #expect(LivePulseLayout.drawerCardLeadingInset == 4)
        #expect(LivePulseLayout.drawerCardTrailingInset == 8)
        #expect(LivePulseLayout.drawerCardCornerRadius == 16)
        #expect(LivePulseLayout.drawerHeaderHeight == 36)
        #expect(LivePulseLayout.minimumWebContentWidth == 480)
        #expect(LivePulseLayout.autoCollapseSidebarThreshold == 1060)

        // Clamping range 280...440
        #expect(LivePulseLayout.clampDrawerWidth(180) == 280)
        #expect(LivePulseLayout.clampDrawerWidth(340) == 340)
        #expect(LivePulseLayout.clampDrawerWidth(600) == 440)
        #expect(LivePulseLayout.clampDrawerWidth(.nan) == 320)

        // 1060pt symmetrical auto-collapse threshold
        #expect(LivePulseLayout.shouldAutoCollapseSidebar(windowWidth: 1059) == true)
        #expect(LivePulseLayout.shouldAutoCollapseSidebar(windowWidth: 1060) == false)

        // At 780pt minimum window width with sidebar collapsed, 780 - 6 - 480 = 294pt (>= 280pt min drawer, >= 480pt TabWebViewHost)
        let collapsed780 = LivePulseLayout.effectiveDrawerWidth(requested: 320, windowWidth: 780, isSidebarVisible: false)
        #expect(collapsed780 == 294)
        #expect(collapsed780 >= LivePulseLayout.drawerMinWidth)
        #expect(780 - collapsed780 - LivePulseLayout.drawerDividerWidth >= LivePulseLayout.minimumWebContentWidth)

        // At 780pt with sidebar expanded (234pt), remaining space is 780 - 234 - 6 - 480 = 60pt (still >= 480pt TabWebViewHost)
        let expanded780 = LivePulseLayout.effectiveDrawerWidth(requested: 320, windowWidth: 780, isSidebarVisible: true)
        #expect(expanded780 == 60)

        // Ultra-narrow edge case never returns negative width
        let ultraNarrow = LivePulseLayout.effectiveDrawerWidth(requested: 320, windowWidth: 400, isSidebarVisible: true)
        #expect(ultraNarrow == 0)
    }

    @Test("CompanionQuickSite.livePulseSites appends all 6 Fantasy & Markets tiles while preserving original 8")
    func companionQuickSitesIncludeAllSixLivePulseTiles() {
        let livePulseIDs = CompanionQuickSite.livePulseSites.map(\.id)
        #expect(livePulseIDs == ["sleeper", "espn-fantasy", "yahoo-fantasy", "nfl-fantasy", "kalshi", "polymarket"])
        for site in CompanionQuickSite.livePulseSites {
            #expect(site.routingMode == .companion)
            #expect(site.url.scheme == "https")
        }

        let catalogIDs = CompanionQuickSite.catalog.map(\.id)
        for originalID in ["twitch", "espn", "nfl", "yttv", "peacock", "paramount", "primevideo", "crunchyroll"] {
            #expect(catalogIDs.contains(originalID))
        }
        for lpID in livePulseIDs {
            #expect(catalogIDs.contains(lpID))
        }
        #expect(CompanionQuickSite.catalog.count == 14)
    }
}

// MARK: - 8. Live Pulse v2 Upgrades

@Suite("Live Pulse v2 Upgrades")
struct LivePulseV2Tests {
    @Test("Formats compact 1-line NFL QB, RB, WR/TE, K, and D/ST boxscores and matches name+team fallback")
    func nflCompactBoxscoresAndNameTeamFallback() throws {
        let json = """
        {
          "header": {
            "competitions": [
              {
                "competitors": [
                  { "homeAway": "away", "score": "14", "team": { "abbreviation": "KC" } },
                  { "homeAway": "home", "score": "24", "team": { "abbreviation": "BUF" } }
                ]
              }
            ]
          },
          "boxscore": {
            "players": [
              {
                "team": { "abbreviation": "BUF" },
                "statistics": [
                  {
                    "name": "passing",
                    "labels": ["C/ATT", "YDS", "AVG", "TD", "INT"],
                    "athletes": [
                      { "athlete": { "id": "qb1", "displayName": "Josh Allen" }, "stats": ["18/25", "242", "9.7", "2", "1"] },
                      { "athlete": { "id": "qb2", "displayName": "Mitchell Trubisky" }, "stats": ["20/28", "215", "7.7", "1", "0"] }
                    ]
                  },
                  {
                    "name": "rushing",
                    "labels": ["CAR", "YDS", "AVG", "TD", "LONG"],
                    "athletes": [
                      { "athlete": { "id": "qb1", "displayName": "Josh Allen" }, "stats": ["6", "38", "6.3", "0", "14"] },
                      { "athlete": { "id": "qb2", "displayName": "Mitchell Trubisky" }, "stats": ["2", "4", "2.0", "1", "3"] },
                      { "athlete": { "id": "rb1", "displayName": "James Cook" }, "stats": ["14", "86", "6.1", "1", "22"] },
                      { "athlete": { "id": "rb2", "displayName": "Ty Johnson" }, "stats": ["0", "0", "0.0", "0", "0"] }
                    ]
                  },
                  {
                    "name": "receiving",
                    "labels": ["REC", "YDS", "AVG", "TD", "LONG", "TGTS"],
                    "athletes": [
                      { "athlete": { "id": "rb1", "displayName": "James Cook" }, "stats": ["3", "24", "8.0", "0", "11", "4"] },
                      { "athlete": { "id": "rb2", "displayName": "Ty Johnson" }, "stats": ["5", "41", "8.2", "0", "15", "6"] },
                      { "athlete": { "id": "wr1", "displayName": "Khalil Shakir" }, "stats": ["6", "94", "15.7", "1", "31", "8"] },
                      { "athlete": { "id": "wr2", "displayName": "Keon Coleman" }, "stats": ["0", "0", "0.0", "0", "0", "3"] }
                    ]
                  },
                  {
                    "name": "kicking",
                    "labels": ["FG", "PCT", "LONG", "XP"],
                    "athletes": [
                      { "athlete": { "id": "k1", "displayName": "Tyler Bass" }, "stats": ["2/2", "100.0", "52", "3/3"] },
                      { "athlete": { "id": "k2", "displayName": "Backup Kicker" }, "stats": ["1/1", "100.0", "38", "2/2"] }
                    ]
                  },
                  {
                    "name": "defensive",
                    "labels": ["TOT", "SOLO", "SACKS", "TFL", "PD", "QB HTS", "TD"],
                    "totals": ["58", "39", "3", "6", "4", "5", "1"],
                    "athletes": []
                  },
                  {
                    "name": "interceptions",
                    "labels": ["INT", "YDS", "TD"],
                    "totals": ["2", "34", "0"],
                    "athletes": []
                  }
                ]
              },
              {
                "team": { "abbreviation": "LA" },
                "statistics": [
                  {
                    "name": "receiving",
                    "labels": ["REC", "YDS", "AVG", "TD", "LONG", "TGTS"],
                    "athletes": [
                      { "athlete": { "id": "4890001", "displayName": "Konata Mumpfield" }, "stats": ["4", "69", "17.3", "0", "28", "4"] }
                    ]
                  },
                  {
                    "name": "fumbles",
                    "labels": ["FUM", "LOST"],
                    "totals": ["1", "1"],
                    "athletes": []
                  }
                ]
              }
            ]
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let update = try #require(ESPNScoreboardClient.parseSummary(from: data, eventID: "nfl-v2", league: .nfl))

        #expect(update.athleteStats["qb1"] == "18/25 · 242 yds · 2 TD · 1 INT · 38 rush")
        #expect(update.athleteStats["qb2"] == "20/28 · 215 yds · 1 TD · 1 rush TD")
        #expect(update.athleteStats["rb1"] == "14 car · 86 yds · 1 TD · 3 rec 24 yds")
        #expect(update.athleteStats["rb2"] == "5 rec · 41 yds · 6 tgts")
        #expect(update.athleteStats["wr1"] == "6 rec · 94 yds · 1 TD")
        #expect(update.athleteStats["wr2"] == "0 rec (3 tgt)")
        #expect(update.athleteStats["k1"] == "2/2 FG · 3/3 XP · L52")
        #expect(update.athleteStats["k2"] == "1/1 FG · 2/2 XP")

        let mumpfieldKey = ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "Konata Mumpfield", team: "LAR", league: .nfl)
        #expect(mumpfieldKey == "konata mumpfield|LAR")
        #expect(update.athleteStatsByNameAndTeam[mumpfieldKey] == "4 rec · 69 yds · 4 tgts")

        let bufDefKey = ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "def", team: "BUF", league: .nfl)
        #expect(update.athleteStatsByNameAndTeam[bufDefKey] == "14 PA · 3 SCK · 2 INT · 1 FR · 1 TD")
    }

    @Test("Formats compact 1-line NBA boxscores with notable extras and ignores didNotPlay")
    func nbaCompactBoxscoreFormattingAndDidNotPlayGuard() throws {
        let json = """
        {
          "boxscore": {
            "players": [
              {
                "team": { "abbreviation": "DEN" },
                "statistics": [
                  {
                    "labels": ["MIN", "FG", "3PT", "FT", "REB", "AST", "STL", "BLK", "PTS"],
                    "athletes": [
                      {
                        "athlete": { "id": "3112335", "displayName": "Nikola Jokić" },
                        "stats": ["36", "11-18", "3-5", "4-4", "12", "9", "2", "1", "29"]
                      },
                      {
                        "athlete": { "id": "4432165", "displayName": "Aaron Gordon" },
                        "stats": ["31", "7-12", "1-3", "2-2", "8", "3", "0", "3", "17"]
                      },
                      {
                        "athlete": { "id": "999999", "displayName": "Bench DNP" },
                        "didNotPlay": true,
                        "stats": ["0", "0-0", "0-0", "0-0", "0", "0", "0", "0", "0"]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let update = try #require(ESPNScoreboardClient.parseSummary(from: data, eventID: "nba-v2", league: .nba))

        #expect(update.athleteStats["3112335"] == "29 PTS · 12 REB · 9 AST · 2 STL · 3 3PM")
        #expect(update.athleteStats["4432165"] == "17 PTS · 8 REB · 3 AST · 3 BLK")
        #expect(update.athleteStats["999999"] == nil)

        let jokicKey = ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "Nikola Jokic", team: "DEN", league: .nba)
        #expect(update.athleteStatsByNameAndTeam[jokicKey] == "29 PTS · 12 REB · 9 AST · 2 STL · 3 3PM")
    }

    @Test("Formats compact 1-line MLB Batter (H-AB & H/AB) and Pitcher boxscores")
    func mlbCompactBatterAndPitcherBoxscores() throws {
        let json = """
        {
          "boxscore": {
            "players": [
              {
                "team": { "abbreviation": "LAD" },
                "statistics": [
                  {
                    "name": "batting",
                    "labels": ["H-AB", "R", "HR", "RBI", "BB", "SO"],
                    "athletes": [
                      { "athlete": { "id": "bat1", "displayName": "Shohei Ohtani" }, "stats": ["2-4", "1", "1", "2", "0", "1"] }
                    ]
                  },
                  {
                    "name": "batting",
                    "labels": ["AB", "R", "H", "RBI", "HR", "BB"],
                    "athletes": [
                      { "athlete": { "id": "bat2", "displayName": "Mookie Betts" }, "stats": ["4", "2", "3", "4", "2", "1"] }
                    ]
                  },
                  {
                    "name": "pitching",
                    "labels": ["IP", "H", "R", "ER", "BB", "K"],
                    "athletes": [
                      { "athlete": { "id": "pit1", "displayName": "Yoshinobu Yamamoto" }, "stats": ["6.0", "4", "1", "1", "1", "8"] }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let update = try #require(ESPNScoreboardClient.parseSummary(from: data, eventID: "mlb-v2", league: .mlb))

        #expect(update.athleteStats["bat1"] == "2-4 · HR · 2 RBI · 1 R")
        #expect(update.athleteStats["bat2"] == "3-4 · 2 HR · 4 RBI · 2 R")
        #expect(update.athleteStats["pit1"] == "6.0 IP · 8 K · 1 ER · 4 H")
    }

    @Test("Formats compact 1-line NHL Skater and Goalie boxscores")
    func nhlCompactSkaterAndGoalieBoxscores() throws {
        let json = """
        {
          "boxscore": {
            "players": [
              {
                "team": { "abbreviation": "EDM" },
                "statistics": [
                  {
                    "name": "forwards",
                    "labels": ["G", "A", "+/-", "SOG", "HIT"],
                    "athletes": [
                      { "athlete": { "id": "sk1", "displayName": "Connor McDavid" }, "stats": ["1", "2", "+2", "4", "1"] },
                      { "athlete": { "id": "sk2", "displayName": "Zach Hyman" }, "stats": ["0", "0", "0", "4", "2"] },
                      { "athlete": { "id": "sk3", "displayName": "Evan Bouchard" }, "stats": ["0", "0", "+1", "3", "0"] },
                      { "athlete": { "id": "sk4", "displayName": "Ryan Nugent-Hopkins" }, "stats": ["0", "0", "0", "2", "0"] }
                    ]
                  },
                  {
                    "name": "goalies",
                    "labels": ["SA", "GA", "SV", "SV%"],
                    "athletes": [
                      { "athlete": { "id": "g1", "displayName": "Stuart Skinner" }, "stats": ["29", "1", "28", "0.966"] },
                      { "athlete": { "id": "g2", "displayName": "Calvin Pickard" }, "stats": ["29", "0", "29", "--"] }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let update = try #require(ESPNScoreboardClient.parseSummary(from: data, eventID: "nhl-v2", league: .nhl))

        #expect(update.athleteStats["sk1"] == "1 G · 2 A · 4 SOG")
        #expect(update.athleteStats["sk2"] == "4 SOG · 2 HIT")
        #expect(update.athleteStats["sk3"] == "3 SOG · +1")
        #expect(update.athleteStats["sk4"] == "0 G · 0 A · 2 SOG")
        #expect(update.athleteStats["g1"] == "28 SV · 1 GA · .966")
        #expect(update.athleteStats["g2"] == "29 SV · 0 GA · 1.000 · SO")
    }

    @Test("Normalizes player name and team keys across diacritics, hyphens, punctuation, and suffixes")
    func normalizedPlayerNameTeamKeyDiacriticsHyphensAndSuffixes() {
        #expect(
            ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "Nikola Jokić", team: "DEN", league: .nba) ==
            "nikola jokic|DEN"
        )
        #expect(
            ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "José Ramírez", team: "CLE", league: .mlb) ==
            "jose ramirez|CLE"
        )
        #expect(
            ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "Amon-Ra St. Brown", team: "DET", league: .nfl) ==
            "amon ra st brown|DET"
        )
        #expect(
            ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "A.J. Brown", team: "PHI", league: .nfl) ==
            "aj brown|PHI"
        )
        #expect(
            ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "Kenneth Walker III", team: "SEA", league: .nfl) ==
            "kenneth walker|SEA"
        )
        #expect(
            ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "Marvin Harrison Jr.", team: "ARI", league: .nfl) ==
            "marvin harrison|ARI"
        )
        #expect(
            ESPNScoreboardClient.normalizedPlayerNameTeamKey(name: "Konata Mumpfield", team: "LA", league: .nfl) ==
            "konata mumpfield|LAR"
        )
    }

    @Test("Matches StreamContextMetadata across YouTube TV, Prime Video, Peacock, ESPN+, regional CBS, and rejects auth/browse")
    func streamContextMetadataMatchingAcrossPlatforms() {
        let games = [
            makeSampleGame(id: "nfl-gb-lar", league: .nfl, awayCode: "GB", awayName: "Green Bay Packers", homeCode: "LAR", homeName: "Los Angeles Rams", broadcasts: ["FOX"]),
            makeSampleGame(id: "nfl-buf-kc", league: .nfl, awayCode: "BUF", awayName: "Buffalo Bills", homeCode: "KC", homeName: "Kansas City Chiefs", broadcasts: ["CBS"]),
            makeSampleGame(id: "nfl-mia-nyj", league: .nfl, awayCode: "MIA", awayName: "Miami Dolphins", homeCode: "NYJ", homeName: "New York Jets", broadcasts: ["CBS"]),
            makeSampleGame(id: "nfl-tnf", league: .nfl, awayCode: "BAL", awayName: "Baltimore Ravens", homeCode: "CIN", homeName: "Cincinnati Bengals", broadcasts: ["Prime Video"]),
            makeSampleGame(id: "nfl-snf", league: .nfl, awayCode: "DAL", awayName: "Dallas Cowboys", homeCode: "PHI", homeName: "Philadelphia Eagles", broadcasts: ["NBC", "Peacock"]),
            makeSampleGame(id: "nhl-edm-tor", league: .nhl, awayCode: "EDM", awayName: "Edmonton Oilers", homeCode: "TOR", homeName: "Toronto Maple Leafs", broadcasts: ["ESPN+"])
        ]

        // 1. YouTube TV: passive MediaSession title + FOX artist
        let yttvSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://tv.youtube.com/watch/live1")!,
            title: "YouTube TV",
            serviceID: "yttv",
            streamContext: StreamContextMetadata(
                mediaSessionTitle: "Packers at Rams",
                mediaSessionArtist: "FOX"
            )
        )
        #expect(
            SportsEntityMatcher.match(signal: yttvSignal, games: games) ==
            .matchedGame(gameID: "nfl-gb-lar", league: .nfl, confidence: .high, sourceLabel: "GB @ LAR")
        )

        // 2. Prime Video single national TNF game via MediaSession artist
        let primeSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://www.primevideo.com/detail/xyz")!,
            title: "Thursday Night Football",
            serviceID: "primevideo",
            streamContext: StreamContextMetadata(mediaSessionArtist: "Prime Video")
        )
        #expect(
            SportsEntityMatcher.match(signal: primeSignal, games: games) ==
            .matchedGame(gameID: "nfl-tnf", league: .nfl, confidence: .medium, sourceLabel: "Auto · Prime Video")
        )

        // 3. Peacock / NBC single national SNF game vs regional 2-game CBS disambiguation
        let peacockSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://www.peacocktv.com/watch/playback/live")!,
            title: "Sunday Night Football",
            serviceID: "peacock",
            streamContext: StreamContextMetadata(mediaSessionArtist: "NBC")
        )
        #expect(
            SportsEntityMatcher.match(signal: peacockSignal, games: games) ==
            .matchedGame(gameID: "nfl-snf", league: .nfl, confidence: .medium, sourceLabel: "Auto · NBC")
        )

        let cbsRegionalSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://tv.youtube.com/watch/cbs")!,
            title: "NFL on CBS",
            serviceID: "yttv",
            streamContext: StreamContextMetadata(mediaSessionArtist: "CBS", mediaSessionAlbum: "NFL Football")
        )
        #expect(
            SportsEntityMatcher.match(signal: cbsRegionalSignal, games: games) ==
            .networkCandidates(network: "CBS", league: .nfl, gameIDs: ["nfl-buf-kc", "nfl-mia-nyj"])
        )

        // 4. ESPN+ via ogTitle & headingHint
        let espnSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://www.espn.com/watch/player/_/id/999")!,
            title: "Watch ESPN",
            serviceID: "espn",
            streamContext: StreamContextMetadata(ogTitle: "Oilers vs. Maple Leafs | ESPN+")
        )
        #expect(
            SportsEntityMatcher.match(signal: espnSignal, games: games) ==
            .matchedGame(gameID: "nhl-edm-tor", league: .nhl, confidence: .high, sourceLabel: "EDM @ TOR")
        )

        let headingSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://www.espn.com/watch/player/_/id/999")!,
            title: "Live Stream",
            streamContext: StreamContextMetadata(headingHint: "NHL: Oilers at Maple Leafs")
        )
        #expect(
            SportsEntityMatcher.match(signal: headingSignal, games: games) ==
            .matchedGame(gameID: "nhl-edm-tor", league: .nhl, confidence: .high, sourceLabel: "EDM @ TOR")
        )

        // 5. Auth / browse routes always reject even when metadata is populated
        let authSignal = StreamSignal(
            tabID: UUID(),
            windowID: UUID(),
            url: URL(string: "https://accounts.google.com/signin")!,
            title: "Sign in",
            isAuthOrBrowse: true,
            streamContext: StreamContextMetadata(
                mediaSessionTitle: "Packers at Rams",
                ogTitle: "Packers at Rams",
                headingHint: "Packers at Rams"
            )
        )
        #expect(SportsEntityMatcher.match(signal: authSignal, games: games) == .none)
    }

    @Test("EnhancementScript passive context extraction includes MediaSession, og:title, auth bailout, and zero forbidden tokens")
    func enhancementScriptPassiveStreamContextAndInvariants() {
        let script = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())

        #expect(script.contains("extractStreamContextMetadata"))
        #expect(script.contains("navigator.mediaSession"))
        #expect(script.contains("meta[property=\"og:title\"]"))
        #expect(script.contains("isCompanionAuthPage"))
        #expect(script.contains("mediaSessionTitle"))
        #expect(script.contains("headingHint"))

        #expect(!script.contains(":has("))
        #expect(!script.contains("MutationObserver"))
        #expect(!script.contains("AudioContext"))
        #expect(!script.contains("ytInitialPlayerResponse"))
    }

    @Test("LivePulseFreshnessFormatter buckets Offline, Syncing, Live/Synced, <1m, 1m, 2m stale, and 5m+")
    func livePulseFreshnessFormatterBuckets() {
        let now = Date(timeIntervalSince1970: 1_700_000_600)

        let offline = LivePulseFreshnessFormatter.format(lastUpdatedAt: now, now: now, hasLiveGames: true, isOffline: true)
        #expect(offline == LivePulseFreshnessState(label: "Offline", isStale: true, isTickerStale: true, isOffline: true, isLiveDot: false))

        let syncing = LivePulseFreshnessFormatter.format(lastUpdatedAt: nil, now: now, hasLiveGames: true, isOffline: false)
        #expect(syncing == LivePulseFreshnessState(label: "Syncing", isStale: false, isTickerStale: false, isOffline: false, isLiveDot: false))

        let live = LivePulseFreshnessFormatter.format(lastUpdatedAt: now.addingTimeInterval(-10), now: now, hasLiveGames: true, isOffline: false)
        #expect(live == LivePulseFreshnessState(label: "Live", isStale: false, isTickerStale: false, isOffline: false, isLiveDot: true))

        let synced = LivePulseFreshnessFormatter.format(lastUpdatedAt: now.addingTimeInterval(-10), now: now, hasLiveGames: false, isOffline: false)
        #expect(synced == LivePulseFreshnessState(label: "Synced", isStale: false, isTickerStale: false, isOffline: false, isLiveDot: false))

        let underOneMinute = LivePulseFreshnessFormatter.format(lastUpdatedAt: now.addingTimeInterval(-45), now: now, hasLiveGames: true, isOffline: false)
        #expect(underOneMinute == LivePulseFreshnessState(label: "<1m", isStale: false, isTickerStale: false, isOffline: false, isLiveDot: false))

        let oneMinuteLive = LivePulseFreshnessFormatter.format(lastUpdatedAt: now.addingTimeInterval(-90), now: now, hasLiveGames: true, isOffline: false)
        #expect(oneMinuteLive == LivePulseFreshnessState(label: "1m", isStale: false, isTickerStale: true, isOffline: false, isLiveDot: false))

        let twoMinutesLive = LivePulseFreshnessFormatter.format(lastUpdatedAt: now.addingTimeInterval(-150), now: now, hasLiveGames: true, isOffline: false)
        #expect(twoMinutesLive == LivePulseFreshnessState(label: "2m", isStale: true, isTickerStale: true, isOffline: false, isLiveDot: false))

        let twoMinutesOffHours = LivePulseFreshnessFormatter.format(lastUpdatedAt: now.addingTimeInterval(-150), now: now, hasLiveGames: false, isOffline: false)
        #expect(twoMinutesOffHours == LivePulseFreshnessState(label: "2m", isStale: false, isTickerStale: false, isOffline: false, isLiveDot: false))

        let fiveMinutesPlus = LivePulseFreshnessFormatter.format(lastUpdatedAt: now.addingTimeInterval(-305), now: now, hasLiveGames: false, isOffline: false)
        #expect(fiveMinutesPlus == LivePulseFreshnessState(label: "5m+", isStale: true, isTickerStale: true, isOffline: false, isLiveDot: false))
    }

    @Test("SportsLeague.normalizedPriority deduplicates and appends all 9 leagues and preserves 4-league default")
    func sportsLeagueNormalizedPriorityDeduplicationAndCompletion() {
        #expect(SportsLeague.allCases.count == 9)
        #expect(SportsLeague.defaultEnabledLeagues == [.nfl, .nba, .mlb, .nhl])
        #expect(SportsLeague.primaryLeagues == [.nfl, .nba, .mlb, .nhl])
        #expect(LivePulseDrawerTab.allCases.count == 6)
        #expect(LivePulseDrawerTab.allCases.contains(.notes))
        #expect(LivePulseDrawerTab.allCases.contains(.chat))
        #expect(LivePulseDrawerTab.notes.requiresLivePulseSports == false)
        #expect(LivePulseDrawerTab.chat.requiresLivePulseSports == false)
        #expect(LivePulseDrawerTab.matchup.requiresLivePulseSports == true)
        #expect(LivePulseDrawerTab.players.requiresLivePulseSports == true)
        #expect(LivePulseDrawerTab.scores.requiresLivePulseSports == true)
        #expect(LivePulseDrawerTab.markets.requiresLivePulseSports == true)

        #expect(
            SportsLeague.normalizedPriority([]) ==
            [.nfl, .nba, .mlb, .nhl, .ncaaf, .ncaab, .mls, .epl, .f1]
        )
        #expect(
            SportsLeague.normalizedPriority([.nhl, .nba, .nhl]) ==
            [.nhl, .nba, .nfl, .mlb, .ncaaf, .ncaab, .mls, .epl, .f1]
        )
        #expect(
            SportsLeague.normalizedPriority([.f1, .epl, .mls, .ncaab, .ncaaf, .mlb, .nfl, .nhl, .nba]) ==
            [.f1, .epl, .mls, .ncaab, .ncaaf, .mlb, .nfl, .nhl, .nba]
        )
    }

    @Test("Parses NCAAF Top 25 rank badges, NCAAB, MLS, EPL, F1 leaderboard, and summary recentPlays")
    func expandedLeaguesF1LeaderboardAndRecentPlaysParsing() throws {
        // 1. NCAAF with Top 25 rank: 1 and unranked (> 25 -> nil)
        let ncaafData = Data("""
        {
          "events": [{
            "id": "ncaaf-1",
            "competitions": [{
              "status": { "displayClock": "05:12", "period": 3, "type": { "name": "STATUS_IN_PROGRESS", "state": "in", "shortDetail": "5:12 - 3rd" } },
              "competitors": [
                { "homeAway": "away", "score": "28", "curatedRank": { "current": 1 }, "team": { "id": "130", "abbreviation": "OSU", "displayName": "Ohio State Buckeyes", "shortDisplayName": "Ohio State" } },
                { "homeAway": "home", "score": "14", "curatedRank": { "current": 99 }, "team": { "id": "2", "abbreviation": "PSU", "displayName": "Penn State Nittany Lions", "shortDisplayName": "Penn State" } }
              ]
            }]
          }]
        }
        """.utf8)
        let ncaafGames = ESPNScoreboardClient.parseScoreboard(from: ncaafData, league: .ncaaf)
        #expect(ncaafGames.count == 1)
        #expect(ncaafGames[0].away.rank == 1)
        #expect(ncaafGames[0].home.rank == nil)

        // 2. NCAAB, MLS, EPL basic scoreboard parity
        for (league, abbrA, abbrB) in [(SportsLeague.ncaab, "DUKE", "UNC"), (.mls, "LAFC", "MIA"), (.epl, "ARS", "MCI")] {
            let leagueData = Data("""
            {
              "events": [{
                "id": "\(league.rawValue)-1",
                "competitions": [{
                  "status": { "type": { "name": "STATUS_IN_PROGRESS", "state": "in", "shortDetail": "Live" } },
                  "competitors": [
                    { "homeAway": "away", "score": "2", "team": { "id": "1", "abbreviation": "\(abbrA)", "displayName": "\(abbrA) Team" } },
                    { "homeAway": "home", "score": "1", "team": { "id": "2", "abbreviation": "\(abbrB)", "displayName": "\(abbrB) Team" } }
                  ]
                }]
              }]
            }
            """.utf8)
            let parsed = ESPNScoreboardClient.parseScoreboard(from: leagueData, league: league)
            #expect(parsed.count == 1)
            #expect(parsed[0].league == league)
            #expect(parsed[0].away.abbreviation == abbrA)
            #expect(parsed[0].home.abbreviation == abbrB)
        }

        // 3. F1 driver leaderboard mapping (home = P1 leader, away = P2)
        let f1Data = Data("""
        {
          "events": [{
            "id": "f1-las-vegas",
            "competitions": [{
              "status": { "period": 42, "type": { "name": "STATUS_IN_PROGRESS", "state": "in", "shortDetail": "Lap 42/50" } },
              "competitors": [
                { "id": "33", "order": 2, "athlete": { "id": "33", "displayName": "Max Verstappen", "shortName": "M. Verstappen", "abbreviation": "VER" } },
                { "id": "4", "order": 1, "athlete": { "id": "4", "displayName": "Lando Norris", "shortName": "L. Norris", "abbreviation": "NOR" } },
                { "id": "16", "order": 3, "athlete": { "id": "16", "displayName": "Charles Leclerc", "shortName": "C. Leclerc" } }
              ]
            }]
          }]
        }
        """.utf8)
        let f1Games = ESPNScoreboardClient.parseScoreboard(from: f1Data, league: .f1)
        #expect(f1Games.count == 1)
        #expect(f1Games[0].home.abbreviation == "NOR")
        #expect(f1Games[0].home.score == 1)
        #expect(f1Games[0].home.record == "P1")
        #expect(f1Games[0].away.abbreviation == "VER")
        #expect(f1Games[0].away.score == 2)
        #expect(f1Games[0].away.record == "P2")

        // 4. Summary recentPlays + winprobability parsing
        let summaryData = Data("""
        {
          "header": {
            "competitions": [{
              "competitors": [
                { "team": { "id": "12", "abbreviation": "KC" } },
                { "team": { "id": "2", "abbreviation": "BUF" } }
              ]
            }]
          },
          "winprobability": [
            { "homeWinPercentage": 48.0 },
            { "homeWinPercentage": 62.5 }
          ],
          "drives": {
            "previous": [{
              "plays": [
                { "id": "p1", "text": "P. Mahomes pass short to T. Kelce for 12 yds.", "period": { "displayValue": "Q4" }, "clock": { "displayValue": "1:52" }, "team": { "id": "12" }, "scoringPlay": false }
              ]
            }],
            "current": {
              "plays": [
                { "id": "p2", "text": "TOUCHDOWN!\u{202E} I. Pacheco 8 yd rush.", "period": { "displayValue": "Q4" }, "clock": { "displayValue": "0:41" }, "team": { "id": "12" }, "scoringPlay": true, "awayScore": 31, "homeScore": 27 }
              ]
            }
          }
        }
        """.utf8)
        let summary = try #require(ESPNScoreboardClient.parseSummary(from: summaryData, eventID: "401671789", league: .nfl))
        #expect(abs((summary.homeWinProb ?? 0) - 0.625) < 0.0001)
        #expect(abs((summary.awayWinProb ?? 0) - 0.375) < 0.0001)
        #expect(summary.recentPlays.count == 2)
        // Newest-first ordering
        #expect(summary.recentPlays[0].id == "p2")
        #expect(summary.recentPlays[0].isScoringPlay == true)
        #expect(summary.recentPlays[0].teamAbbreviation == "KC")
        #expect(summary.recentPlays[0].text == "TOUCHDOWN! I. Pacheco 8 yd rush.")
        #expect(summary.recentPlays[0].awayScore == 31)
        #expect(summary.recentPlays[0].homeScore == 27)
        #expect(summary.recentPlays[1].id == "p1")
    }

    @Test("Downsamples espnWinProbHistory to <= 60 clamped points preserving endpoints and detects PlayByPlayEvent.isKeyPlay")
    func espnWinProbHistoryDownsamplingClampingAndKeyPlayDetection() throws {
        // Build 120 winprobability points including out-of-range endpoints (-0.25 and 150.0)
        // plus a >= 0.08 win-prob swing tied to playId "p-swing".
        var wpEntries: [String] = []
        for idx in 0..<120 {
            if idx == 0 {
                wpEntries.append(#"{ "homeWinPercentage": -0.25, "playId": "p-start" }"#)
            } else if idx == 1 {
                wpEntries.append(#"{ "homeWinPercentage": 0.40, "playId": "p-kickoff" }"#)
            } else if idx == 2 {
                wpEntries.append(#"{ "homeWinPercentage": 0.41, "playId": "p-routine" }"#)
            } else if idx == 3 {
                wpEntries.append(#"{ "homeWinPercentage": 0.55, "playId": "p-swing" }"#)
            } else if idx == 119 {
                wpEntries.append(#"{ "homeWinPercentage": 150.0, "playId": "p-end" }"#)
            } else {
                let pct = 0.40 + (Double(idx) / 120.0) * 0.40
                wpEntries.append(#"{ "homeWinPercentage": \#(pct), "playId": "p-\#(idx)" }"#)
            }
        }

        let summaryData = Data("""
        {
          "header": {
            "competitions": [{
              "competitors": [
                { "team": { "id": "12", "abbreviation": "KC" } },
                { "team": { "id": "2", "abbreviation": "BUF" } }
              ]
            }]
          },
          "winprobability": [\(wpEntries.joined(separator: ","))],
          "plays": [
            { "id": "p-routine", "text": "J. Allen pass short right for 4 yds.", "period": { "displayValue": "Q1" }, "clock": { "displayValue": "11:20" }, "team": { "id": "2" }, "scoringPlay": false },
            { "id": "p-swing", "text": "P. Mahomes pass deep middle for 28 yds.", "period": { "displayValue": "Q1" }, "clock": { "displayValue": "09:45" }, "team": { "id": "12" }, "scoringPlay": false },
            { "id": "p-turnover", "text": "Fumble recovered by KC at BUF 32 (turnover).", "period": { "displayValue": "Q2" }, "clock": { "displayValue": "06:10" }, "team": { "id": "12" }, "scoringPlay": false },
            { "id": "p-hr", "text": "S. Ohtani hits a home run to right center.", "period": { "displayValue": "Top 5th" }, "team": { "id": "12" }, "scoringPlay": false },
            { "id": "p-score", "text": "H. Butker 42 yd field goal is GOOD.", "period": { "displayValue": "Q4" }, "clock": { "displayValue": "00:05" }, "team": { "id": "12" }, "scoringPlay": true }
          ]
        }
        """.utf8)

        let summary = try #require(ESPNScoreboardClient.parseSummary(from: summaryData, eventID: "wp-test-1", league: .nfl))

        // History is clamped 0...1, downsampled <= 60, and preserves first & last endpoints
        #expect(summary.espnWinProbHistory.count == 60)
        #expect(summary.espnWinProbHistory.first?.sequence == 0)
        #expect(summary.espnWinProbHistory.first?.playID == "p-start")
        #expect(summary.espnWinProbHistory.first?.homeWinProb == 0.0)
        #expect(summary.espnWinProbHistory.last?.sequence == 119)
        #expect(summary.espnWinProbHistory.last?.playID == "p-end")
        #expect(summary.espnWinProbHistory.last?.homeWinProb == 1.0)
        for point in summary.espnWinProbHistory {
            #expect(point.homeWinProb >= 0.0 && point.homeWinProb <= 1.0)
            #expect(point.awayWinProb >= 0.0 && point.awayWinProb <= 1.0)
        }

        // PlayByPlayEvent.isKeyPlay assertions
        let byID = Dictionary(uniqueKeysWithValues: summary.recentPlays.map { ($0.id, $0) })
        #expect(byID["p-routine"]?.isKeyPlay == false)
        #expect(byID["p-swing"]?.isKeyPlay == true)
        #expect(byID["p-turnover"]?.isKeyPlay == true)
        #expect(byID["p-hr"]?.isKeyPlay == true)
        #expect(byID["p-score"]?.isKeyPlay == true)
    }
}
