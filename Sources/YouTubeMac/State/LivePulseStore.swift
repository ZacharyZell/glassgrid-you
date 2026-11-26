import Foundation
import Observation
import YouTubeMacCore

/// MainActor observable telemetry store for Live Pulse live sports, fantasy matchups, and read-only prediction markets.
/// Strictly idle (zero network requests, timers, WebSockets, or disk reads) whenever `settings.livePulseEnabled == false`.
@MainActor
@Observable
public final class LivePulseStore {
    public private(set) var snapshot: LivePulseSnapshot = .empty
    public var selectedDrawerTab: LivePulseDrawerTab
    public var selectedLeagueFilter: SportsLeague?
    public var isTickerPaused: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var sleeperLookupStatus: String?
    public private(set) var discoveredSleeperLeagues: [FantasyLeagueConfig] = []
    public private(set) var manualPinsByTab: [UUID: ManualGamePin] = [:]
    public private(set) var sleeperCacheLastUpdated: Date?
    public private(set) var lastManualRefreshCompletedAt: Date?

    @ObservationIgnored
    private let settings: AppSettings

    @ObservationIgnored
    private weak var coordinator: AppCoordinator?

    @ObservationIgnored
    private let scoreboardClient: ESPNScoreboardClient

    @ObservationIgnored
    private let sleeperClient: SleeperClient

    @ObservationIgnored
    private let espnFantasyClient: ESPNFantasyClient

    @ObservationIgnored
    private let marketsClient: PredictionMarketsClient

    @ObservationIgnored
    private var isShutDown = false

    @ObservationIgnored
    private var isPollingActive = false

    @ObservationIgnored
    private var scoreboardTask: Task<Void, Never>?

    @ObservationIgnored
    private var summaryTask: Task<Void, Never>?

    @ObservationIgnored
    private var fantasyTask: Task<Void, Never>?

    @ObservationIgnored
    private var kalshiTask: Task<Void, Never>?

    @ObservationIgnored
    private var delayDrainTask: Task<Void, Never>?

    @ObservationIgnored
    private var commitCoalesceTask: Task<Void, Never>?

    @ObservationIgnored
    private var refreshNowTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastSnapshotCommitAt: Date = .distantPast

    @ObservationIgnored
    private var lastManualRefreshTriggeredAt: Date = .distantPast

    @ObservationIgnored
    private var lastSummaryRequestAt: Date = .distantPast

    @ObservationIgnored
    private var isFetchingSummaries = false

    // Raw telemetry caches (never observed directly by SwiftUI views)
    @ObservationIgnored
    private var rawGamesByLeague: [SportsLeague: [LiveGame]] = [:]

    @ObservationIgnored
    private var summariesByEventID: [String: ESPNGameSummaryUpdate] = [:]

    @ObservationIgnored
    private var rawMatchups: [FantasyMatchup] = []

    @ObservationIgnored
    private var rawKalshiQuotes: [PredictionMarketQuote] = []

    @ObservationIgnored
    private var rawPolymarketQuotes: [PredictionMarketQuote] = []

    @ObservationIgnored
    private var livePolymarketTickProbabilities: [String: (probability: Double, timestamp: Date)] = [:]

    @ObservationIgnored
    private var previousGameScores: [String: (away: Int, home: Int, isRedZone: Bool)] = [:]

    @ObservationIgnored
    private var previousPlayerPoints: [String: Double] = [:]

    @ObservationIgnored
    private var recentPlayerDeltas: [String: (delta: Double, recordedAt: Date)] = [:]

    @ObservationIgnored
    private var providerStatus: [String: String] = [:]

    @ObservationIgnored
    private var signalsByWindowID: [UUID: [StreamSignal]] = [:]

    @ObservationIgnored
    private var streamHysteresis = StreamContextHysteresis()

    @ObservationIgnored
    private var streamContextByTab: [UUID: StreamSportContext] = [:]

    @ObservationIgnored
    private var primaryContext: StreamSportContext = .none

    @ObservationIgnored
    private var activeGameIDs: Set<String> = []

    @ObservationIgnored
    private var resolvedSleeperUserIDByUsername: [String: String] = [:]

    @ObservationIgnored
    private var sleeperSportStateBySport: [String: (state: SleeperSportState, fetchedAt: Date)] = [:]

    // Spoiler delay buffers gating live scores, matchups, markets, and deltas
    @ObservationIgnored
    private var gamesSpoilerBuffer = SpoilerDelayBuffer<[LiveGame]>()

    @ObservationIgnored
    private var matchupsSpoilerBuffer = SpoilerDelayBuffer<[FantasyMatchup]>()

    @ObservationIgnored
    private var marketsSpoilerBuffer = SpoilerDelayBuffer<[PredictionMarketQuote]>()

    @ObservationIgnored
    private var deltaSpoilerBuffer = SpoilerDelayBuffer<LivePulseDeltaEvent>()

    @ObservationIgnored
    private var displayedGames: [LiveGame] = []

    @ObservationIgnored
    private var displayedMatchups: [FantasyMatchup] = []

    @ObservationIgnored
    private var displayedMarkets: [PredictionMarketQuote] = []

    @ObservationIgnored
    private var displayedDeltas: [LivePulseDeltaEvent] = []

    public init(
        settings: AppSettings,
        coordinator: AppCoordinator? = nil,
        scoreboardClient: ESPNScoreboardClient = ESPNScoreboardClient(),
        sleeperClient: SleeperClient = SleeperClient(),
        espnFantasyClient: ESPNFantasyClient = ESPNFantasyClient(),
        marketsClient: PredictionMarketsClient = PredictionMarketsClient()
    ) {
        self.settings = settings
        self.coordinator = coordinator
        self.scoreboardClient = scoreboardClient
        self.sleeperClient = sleeperClient
        self.espnFantasyClient = espnFantasyClient
        self.marketsClient = marketsClient
        self.selectedDrawerTab = settings.livePulseFantasyLeagues.contains(where: \.isEnabled) ? .matchup : .scores
    }

    // MARK: - Lifecycle & Control

    /// Starts or stops polling tasks and Polymarket CLOB WebSocket strictly according to `settings.livePulseEnabled`
    /// and whether at least one non-minimized visible window has the Ticker Bar or Companion Drawer open.
    public func reconcileLifecycle() {
        guard !isShutDown, settings.livePulseEnabled else {
            stopAllNetworkingAndClearRuntimeState()
            return
        }

        let shouldBeActive = hasVisibleActiveSurface
        if shouldBeActive {
            if !isPollingActive {
                isPollingActive = true
                startPollingLoops()
            } else {
                reconcileMarketLoops()
                reconcileFantasyLoop()
                reapplyPriorityOrderingIfNeeded()
            }
        } else {
            pausePollingLoops()
        }
    }

    public func leaguePriorityRank(for league: SportsLeague) -> Int {
        settings.livePulseLeaguePriority.firstIndex(of: league) ?? 99
    }

    public func isGameLive(_ gameID: String?) -> Bool {
        guard let gameID, !gameID.isEmpty else { return false }
        return rawGamesByLeague.values.joined().contains {
            $0.id == gameID && ($0.status == .live || $0.status == .halftime)
        }
    }

    public func updateStreamSignals(windowID: UUID, signals: [StreamSignal]) {
        signalsByWindowID[windowID] = signals
        guard settings.livePulseEnabled, !isShutDown else { return }
        recomputeStreamContexts(now: Date())
        scheduleCoalescedCommit(immediateIfContextChanged: true)
    }

    public func removeWindowSignals(windowID: UUID) {
        signalsByWindowID.removeValue(forKey: windowID)
        recomputeStreamContexts(now: Date())
        if settings.livePulseEnabled && !isShutDown {
            scheduleCoalescedCommit(immediateIfContextChanged: true)
        }
    }

    public func setManualPin(_ pin: ManualGamePin) {
        manualPinsByTab[pin.tabID] = pin
        guard settings.livePulseEnabled, !isShutDown else { return }
        recomputeStreamContexts(now: Date())
        scheduleCoalescedCommit(immediateIfContextChanged: true)
        if isPollingActive {
            triggerImmediateSummaryRefresh()
        }
    }

    public func clearManualPin(tabID: UUID) {
        manualPinsByTab.removeValue(forKey: tabID)
        guard settings.livePulseEnabled, !isShutDown else { return }
        recomputeStreamContexts(now: Date())
        scheduleCoalescedCommit(immediateIfContextChanged: true)
    }

    public func toggleTickerPaused() {
        isTickerPaused.toggle()
    }

    public func refreshNow() {
        guard settings.livePulseEnabled, !isShutDown else { return }
        let triggeredAt = Date()
        guard triggeredAt.timeIntervalSince(lastManualRefreshTriggeredAt) >= 2.0 else { return }
        lastManualRefreshTriggeredAt = triggeredAt
        sleeperSportStateBySport.removeAll()
        refreshNowTask?.cancel()
        isRefreshing = true
        refreshNowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRefreshing = false }
            await self.pullAllWindowSignals()
            await self.fetchScoreboardsCycle()
            guard !Task.isCancelled, self.settings.livePulseEnabled else { return }
            await self.fetchActiveSummariesCycle()
            guard !Task.isCancelled, self.settings.livePulseEnabled else { return }
            await self.fetchFantasyCycle()
            guard !Task.isCancelled, self.settings.livePulseEnabled else { return }
            await self.fetchMarketsCycle()
            guard !Task.isCancelled, self.settings.livePulseEnabled, !self.isShutDown else { return }
            self.flushAllSpoilerBuffersImmediately()
            self.lastManualRefreshCompletedAt = Date()
            self.commitSnapshotNow()
        }
    }

    public func lookupSleeperUsername(_ username: String) async {
        guard settings.livePulseEnabled, !isShutDown else {
            sleeperLookupStatus = "Enable Live Pulse first"
            return
        }
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sleeperLookupStatus = "Enter a Sleeper username"
            discoveredSleeperLeagues = []
            return
        }

        sleeperLookupStatus = "Looking up @\(trimmed)…"
        do {
            let user = try await sleeperClient.fetchUser(username: trimmed)
            guard settings.livePulseEnabled, !isShutDown else { return }

            resolvedSleeperUserIDByUsername[user.username.lowercased()] = user.userID
            resolvedSleeperUserIDByUsername[trimmed.lowercased()] = user.userID
            settings.livePulseSleeperUsername = user.username

            var discovered: [FantasyLeagueConfig] = []
            for league in [SportsLeague.nfl, SportsLeague.nba] {
                guard let sportCode = league.sleeperSportCode else { continue }
                do {
                    let state = try await sleeperClient.fetchSportState(sport: sportCode)
                    sleeperSportStateBySport[sportCode] = (state, Date())
                    let leagues = try await sleeperClient.fetchLeagues(
                        userID: user.userID,
                        sport: sportCode,
                        season: state.season
                    )
                    let seasonInt = Int(state.season) ?? Calendar.current.component(.year, from: Date())
                    for info in leagues {
                        discovered.append(
                            FantasyLeagueConfig(
                                id: "sleeper:\(info.id)",
                                provider: .sleeper,
                                league: league,
                                leagueID: info.id,
                                leagueName: info.name,
                                season: seasonInt,
                                teamOwnerHint: user.userID,
                                isEnabled: true
                            )
                        )
                    }
                } catch {
                    continue
                }
            }

            guard settings.livePulseEnabled, !isShutDown else { return }
            discoveredSleeperLeagues = discovered
            if discovered.isEmpty {
                sleeperLookupStatus = "No active NFL/NBA leagues found for @\(user.username)"
            } else {
                sleeperLookupStatus = "Found \(discovered.count) league\(discovered.count == 1 ? "" : "s") for @\(user.username)"
            }
        } catch SleeperClientError.userNotFound {
            discoveredSleeperLeagues = []
            sleeperLookupStatus = "Sleeper user \"\(trimmed)\" not found"
        } catch {
            discoveredSleeperLeagues = []
            sleeperLookupStatus = "Could not reach Sleeper API"
        }
    }

    public func addESPNPublicLeague(
        league: SportsLeague,
        leagueID: String,
        season: Int,
        teamOwnerHint: String?
    ) {
        let cleanID = leagueID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        let cleanHint = teamOwnerHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHint = (cleanHint?.isEmpty == false) ? cleanHint : nil
        let config = FantasyLeagueConfig(
            id: "espnPublic:\(league.rawValue):\(season):\(cleanID)",
            provider: .espnPublic,
            league: league,
            leagueID: cleanID,
            leagueName: "ESPN \(league.displayName) #\(cleanID)",
            season: season,
            teamOwnerHint: resolvedHint,
            isEnabled: true
        )
        addFantasyLeague(config)
    }

    public func addFantasyLeague(_ config: FantasyLeagueConfig) {
        var list = settings.livePulseFantasyLeagues
        if let idx = list.firstIndex(where: { $0.id == config.id }) {
            list[idx] = config
        } else {
            list.append(config)
        }
        settings.livePulseFantasyLeagues = list
        if isPollingActive {
            reconcileFantasyLoop()
        }
    }

    public func removeFantasyLeague(id: String) {
        var list = settings.livePulseFantasyLeagues
        list.removeAll { $0.id == id }
        settings.livePulseFantasyLeagues = list
        rawMatchups.removeAll { $0.configID == id }
        displayedMatchups.removeAll { $0.configID == id }
        if settings.livePulseEnabled && !isShutDown {
            commitSnapshotNow()
        }
    }

    public func clearSleeperCache() async {
        await sleeperClient.clearCache()
        sleeperCacheLastUpdated = nil
    }

    public func shutdown() {
        isShutDown = true
        stopAllNetworkingAndClearRuntimeState()
    }

    // MARK: - Polling Loops & Lifecycle Helpers

    private var hasVisibleActiveSurface: Bool {
        guard let coordinator, !isShutDown, settings.livePulseEnabled else { return false }
        return coordinator.openWindows.contains { controller in
            !controller.isMainWindowMiniaturized
            && controller.isMainWindowVisible
            && (controller.isLivePulseTickerRendered || controller.isLivePulseDrawerVisible)
        }
    }

    private var hasAnyLiveGame: Bool {
        rawGamesByLeague.values.joined().contains { $0.status == .live || $0.status == .halftime }
    }

    private func startPollingLoops() {
        if scoreboardTask == nil {
            scoreboardTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled && self.isPollingActive && self.settings.livePulseEnabled {
                    await self.pullAllWindowSignals()
                    await self.fetchScoreboardsCycle()
                    let interval: UInt64 = self.hasAnyLiveGame ? 12 : 60
                    try? await Task.sleep(for: .seconds(interval))
                }
            }
        }

        if summaryTask == nil {
            summaryTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled && self.isPollingActive && self.settings.livePulseEnabled {
                    let interval: UInt64 = self.hasAnyLiveGame ? 12 : 60
                    try? await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled && self.isPollingActive && self.settings.livePulseEnabled else { break }
                    await self.fetchActiveSummariesCycle()
                }
            }
        }

        reconcileFantasyLoop()
        reconcileMarketLoops()
        startDelayDrainLoopIfNeeded()
    }

    private func reconcileFantasyLoop() {
        let hasEnabledLeagues = settings.livePulseFantasyLeagues.contains(where: \.isEnabled)
        guard isPollingActive && settings.livePulseEnabled && hasEnabledLeagues else {
            fantasyTask?.cancel()
            fantasyTask = nil
            return
        }
        guard fantasyTask == nil else { return }
        fantasyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isPollingActive && self.settings.livePulseEnabled {
                await self.fetchFantasyCycle()
                let interval: UInt64 = self.hasAnyLiveGame ? 15 : 60
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func reconcileMarketLoops() {
        let shouldPollMarkets = isPollingActive
            && settings.livePulseEnabled
            && settings.livePulseShowMarkets
            && !settings.livePulseEnabledLeagues.isEmpty

        guard shouldPollMarkets else {
            kalshiTask?.cancel()
            kalshiTask = nil
            Task { [marketsClient] in
                await marketsClient.disconnectStream()
            }
            return
        }

        guard kalshiTask == nil else { return }
        kalshiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isPollingActive && self.settings.livePulseEnabled && self.settings.livePulseShowMarkets {
                await self.fetchMarketsCycle()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func startDelayDrainLoopIfNeeded() {
        guard delayDrainTask == nil else { return }
        delayDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isPollingActive && self.settings.livePulseEnabled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled && self.isPollingActive && self.settings.livePulseEnabled else { break }
                self.drainSpoilerBuffersAndCommitIfReady()
            }
        }
    }

    private func pausePollingLoops() {
        isPollingActive = false
        scoreboardTask?.cancel()
        scoreboardTask = nil
        summaryTask?.cancel()
        summaryTask = nil
        fantasyTask?.cancel()
        fantasyTask = nil
        kalshiTask?.cancel()
        kalshiTask = nil
        delayDrainTask?.cancel()
        delayDrainTask = nil
        commitCoalesceTask?.cancel()
        commitCoalesceTask = nil
        Task { [marketsClient] in
            await marketsClient.disconnectStream()
        }
    }

    private func stopAllNetworkingAndClearRuntimeState() {
        pausePollingLoops()
        refreshNowTask?.cancel()
        refreshNowTask = nil

        Task { [marketsClient, sleeperClient] in
            await marketsClient.disconnectStream()
            await sleeperClient.evictMemoryCache()
        }

        rawGamesByLeague.removeAll()
        summariesByEventID.removeAll()
        rawMatchups.removeAll()
        rawKalshiQuotes.removeAll()
        rawPolymarketQuotes.removeAll()
        livePolymarketTickProbabilities.removeAll()
        previousGameScores.removeAll()
        previousPlayerPoints.removeAll()
        recentPlayerDeltas.removeAll()
        providerStatus.removeAll()
        signalsByWindowID.removeAll()
        streamHysteresis.clearAll()
        streamContextByTab.removeAll()
        primaryContext = .none
        activeGameIDs.removeAll()
        resolvedSleeperUserIDByUsername.removeAll()
        sleeperSportStateBySport.removeAll()

        gamesSpoilerBuffer.clear()
        matchupsSpoilerBuffer.clear()
        marketsSpoilerBuffer.clear()
        deltaSpoilerBuffer.clear()

        displayedGames.removeAll()
        displayedMatchups.removeAll()
        displayedMarkets.removeAll()
        displayedDeltas.removeAll()

        isRefreshing = false
        isFetchingSummaries = false
        lastSummaryRequestAt = .distantPast
        lastManualRefreshTriggeredAt = .distantPast
        lastManualRefreshCompletedAt = nil
        sleeperCacheLastUpdated = nil
        snapshot = .empty
    }

    private func triggerImmediateSummaryRefresh() {
        Task { @MainActor [weak self] in
            await self?.fetchActiveSummariesCycle()
        }
    }

    // MARK: - Fetch Cycles

    private func pullAllWindowSignals() async {
        guard let coordinator else { return }
        for controller in coordinator.openWindows {
            signalsByWindowID[controller.windowID] = controller.collectLivePulseStreamSignals()
        }
        recomputeStreamContexts(now: Date())
    }

    private func fetchScoreboardsCycle() async {
        let leagues = settings.livePulseEnabledLeagues
        guard !leagues.isEmpty else {
            rawGamesByLeague.removeAll()
            enqueueScoreboardState(now: Date())
            return
        }

        let client = scoreboardClient
        let fetched = await withTaskGroup(of: (SportsLeague, Result<[LiveGame], Error>).self) { group in
            for league in leagues {
                group.addTask {
                    do {
                        let games = try await client.fetchScoreboard(for: league)
                        return (league, .success(games))
                    } catch {
                        return (league, .failure(error))
                    }
                }
            }
            var results: [(SportsLeague, Result<[LiveGame], Error>)] = []
            for await item in group {
                results.append(item)
            }
            return results
        }

        guard settings.livePulseEnabled, !isShutDown else { return }
        let now = Date()

        let activeLeagues = Set(leagues)
        for key in rawGamesByLeague.keys where !activeLeagues.contains(key) {
            rawGamesByLeague.removeValue(forKey: key)
        }

        var hadSuccess = false
        for (league, result) in fetched {
            switch result {
            case .success(let games):
                hadSuccess = true
                let merged = games.map { applyCachedSummary(to: $0) }
                recordScoreDeltas(for: merged, now: now)
                rawGamesByLeague[league] = merged
            case .failure:
                break
            }
        }

        providerStatus["espnScoreboard"] = hadSuccess ? "OK" : "Unavailable"
        recomputeStreamContexts(now: now)
        enqueueScoreboardState(now: now)
        if !rawMatchups.isEmpty {
            let enriched = sortMatchupsByPriority(rawMatchups.map { enrichMatchup($0, now: now) })
            rawMatchups = enriched
            matchupsSpoilerBuffer.enqueue(enriched, at: now)
        }
        scheduleCoalescedCommit()
        if hadSuccess && summariesByEventID.isEmpty && !isRefreshing {
            triggerImmediateSummaryRefresh()
        }
    }

    private func fetchActiveSummariesCycle() async {
        guard !isFetchingSummaries else { return }
        let targetGames = prioritizedActiveGamesForSummary(limit: 8)
        guard !targetGames.isEmpty else { return }

        isFetchingSummaries = true
        defer { isFetchingSummaries = false }

        for game in targetGames {
            guard settings.livePulseEnabled, !isShutDown, !Task.isCancelled else { return }
            let elapsed = Date().timeIntervalSince(lastSummaryRequestAt)
            if elapsed < 1.05 {
                // Strictly stagger ESPN game summary requests >= 1050ms (<= 1 req/s).
                let waitMs = max(1, Int(((1.05 - elapsed) * 1000).rounded(.up)))
                try? await Task.sleep(for: .milliseconds(waitMs))
                guard settings.livePulseEnabled, !isShutDown, !Task.isCancelled else { return }
            }
            lastSummaryRequestAt = Date()
            if let summary = try? await scoreboardClient.fetchGameSummary(eventID: game.id, league: game.league) {
                summariesByEventID[game.id] = summary
                if var leagueGames = rawGamesByLeague[game.league],
                   let idx = leagueGames.firstIndex(where: { $0.id == game.id }) {
                    leagueGames[idx] = applySummary(summary, to: leagueGames[idx])
                    rawGamesByLeague[game.league] = leagueGames
                }
            }
        }

        let now = Date()
        enqueueScoreboardState(now: now)
        if !rawMatchups.isEmpty {
            let enriched = sortMatchupsByPriority(rawMatchups.map { enrichMatchup($0, now: now) })
            rawMatchups = enriched
            matchupsSpoilerBuffer.enqueue(enriched, at: now)
        }
        scheduleCoalescedCommit()
    }

    private func fetchFantasyCycle() async {
        let enabledConfigs = settings.livePulseFantasyLeagues.filter(\.isEnabled)
        guard !enabledConfigs.isEmpty else {
            rawMatchups = []
            matchupsSpoilerBuffer.enqueue([], at: Date())
            scheduleCoalescedCommit()
            return
        }

        var fetchedMatchups: [FantasyMatchup] = []
        var espnStatus: String?
        var sleeperStatus: String?

        let sleeperConfigs = enabledConfigs.filter { $0.provider == .sleeper }
        if !sleeperConfigs.isEmpty {
            let userID = await resolveSleeperUserIDIfNeeded(configs: sleeperConfigs)
            for config in sleeperConfigs {
                guard settings.livePulseEnabled, !isShutDown else { return }
                guard let sport = config.league.sleeperSportCode else { continue }
                let resolvedUID = userID ?? config.teamOwnerHint ?? ""
                guard !resolvedUID.isEmpty else { continue }

                if let week = await resolveSleeperWeek(for: sport) {
                    do {
                        if let matchup = try await sleeperClient.fetchMatchup(
                            config: config,
                            userID: resolvedUID,
                            week: week
                        ) {
                            fetchedMatchups.append(matchup)
                            sleeperStatus = "OK"
                        }
                        sleeperCacheLastUpdated = await sleeperClient.cacheLastUpdatedAt(sport: sport)
                    } catch {
                        sleeperStatus = "Unavailable"
                    }
                }
            }
        }

        let espnConfigs = enabledConfigs.filter { $0.provider == .espnPublic }
        for config in espnConfigs {
            guard settings.livePulseEnabled, !isShutDown else { return }
            do {
                if let matchup = try await espnFantasyClient.fetchPublicMatchup(config: config) {
                    fetchedMatchups.append(matchup)
                    espnStatus = "OK"
                }
            } catch ESPNFantasyError.privateLeagueRequiresWebTile {
                espnStatus = "Private league — Open ESPN Fantasy in Tile"
            } catch {
                espnStatus = "Unavailable"
            }
        }

        guard settings.livePulseEnabled, !isShutDown else { return }
        if let sleeperStatus { providerStatus["sleeper"] = sleeperStatus }
        if let espnStatus { providerStatus["espnFantasy"] = espnStatus }

        let now = Date()
        let enriched = sortMatchupsByPriority(fetchedMatchups.map { enrichMatchup($0, now: now) })
        rawMatchups = enriched
        matchupsSpoilerBuffer.enqueue(enriched, at: now)
        scheduleCoalescedCommit()
    }

    private func fetchMarketsCycle() async {
        let leagues = settings.livePulseEnabledLeagues
        guard settings.livePulseShowMarkets, !leagues.isEmpty else {
            rawKalshiQuotes = []
            rawPolymarketQuotes = []
            await marketsClient.disconnectStream()
            marketsSpoilerBuffer.enqueue([], at: Date())
            scheduleCoalescedCommit()
            return
        }

        async let kalshiFetch = marketsClient.fetchKalshiMarkets(for: leagues)
        async let polyFetch = marketsClient.fetchPolymarketSportsMarkets(for: leagues)
        let (kalshi, poly) = await (kalshiFetch, polyFetch)

        guard settings.livePulseEnabled, !isShutDown else { return }
        let now = Date()
        let games = combinedRawGames()

        rawKalshiQuotes = kalshi.map { matchQuoteToGame($0, games: games) }
        rawPolymarketQuotes = poly.map { matchQuoteToGame($0, games: games) }

        providerStatus["kalshi"] = kalshi.isEmpty ? "Standby" : "OK"
        providerStatus["polymarket"] = poly.isEmpty ? "Standby" : "OK"

        let allQuotes = mergedMarketQuotes(now: now)
        marketsSpoilerBuffer.enqueue(allQuotes, at: now)

        // Subscribe Polymarket CLOB WS strictly to matched/displayed tokens.
        let activeAssets: [String] = rawPolymarketQuotes
            .filter { quote in
                if let gid = quote.matchedGameID, activeGameIDs.contains(gid) {
                    return true
                }
                return selectedDrawerTab == .markets
            }
            .prefix(PredictionMarketsClient.maxStreamAssets)
            .map(\.tickerOrSlug)

        if activeAssets.isEmpty || !hasVisibleActiveSurface {
            await marketsClient.disconnectStream()
        } else {
            await marketsClient.connectPolymarketStream(assetIDs: activeAssets) { [weak self] assetID, probability, timestamp in
                Task { @MainActor [weak self] in
                    self?.handlePolymarketTick(assetID: assetID, probability: probability, timestamp: timestamp)
                }
            }
        }

        scheduleCoalescedCommit()
    }

    private func handlePolymarketTick(assetID: String, probability: Double, timestamp: Date) {
        guard settings.livePulseEnabled, !isShutDown else { return }
        let prev = livePolymarketTickProbabilities[assetID]?.probability
        livePolymarketTickProbabilities[assetID] = (probability, timestamp)

        if let prev, abs(probability - prev) >= 0.03 {
            let matchedQuote = rawPolymarketQuotes.first(where: { $0.tickerOrSlug == assetID })
            let pctMove = Int(((probability - prev) * 100.0).rounded())
            let sign = pctMove >= 0 ? "+" : ""
            let headline = matchedQuote?.title ?? assetID
            deltaSpoilerBuffer.enqueue(
                LivePulseDeltaEvent(
                    timestamp: timestamp,
                    kind: .marketMove,
                    gameID: matchedQuote?.matchedGameID,
                    headline: headline,
                    deltaText: "\(sign)\(pctMove)%",
                    isPositive: pctMove >= 0
                ),
                at: timestamp
            )
        }

        let merged = mergedMarketQuotes(now: timestamp)
        marketsSpoilerBuffer.enqueue(merged, at: timestamp)
        scheduleCoalescedCommit()
    }

    // MARK: - Enrichment, Matching & Spoiler Buffering

    private func sortGamesByPriority(_ games: [LiveGame]) -> [LiveGame] {
        let statusRank: (GameStatus) -> Int = { status in
            switch status {
            case .live: return 0
            case .halftime: return 1
            case .pregame: return 2
            case .final: return 3
            case .postponed: return 4
            }
        }
        return games.sorted { lhs, rhs in
            let w1 = activeGameIDs.contains(lhs.id) ? 0 : 1
            let w2 = activeGameIDs.contains(rhs.id) ? 0 : 1
            if w1 != w2 { return w1 < w2 }
            let p1 = leaguePriorityRank(for: lhs.league)
            let p2 = leaguePriorityRank(for: rhs.league)
            if p1 != p2 { return p1 < p2 }
            let s1 = statusRank(lhs.status)
            let s2 = statusRank(rhs.status)
            if s1 != s2 { return s1 < s2 }
            return (lhs.startTime ?? .distantFuture) < (rhs.startTime ?? .distantFuture)
        }
    }

    private func watchedStreamLeagues() -> (primary: SportsLeague?, active: Set<SportsLeague>) {
        func extractLeague(from ctx: StreamSportContext) -> SportsLeague? {
            switch ctx {
            case .matchedGame(_, let league, _, _): return league
            case .liveSlate(let league, _): return league
            case .networkCandidates(_, let league, _): return league
            case .none: return nil
            }
        }
        var active: Set<SportsLeague> = []
        let primary = extractLeague(from: primaryContext)
        if let primary { active.insert(primary) }
        for ctx in streamContextByTab.values {
            if let league = extractLeague(from: ctx) {
                active.insert(league)
            }
        }
        for leagueGames in rawGamesByLeague.values {
            for game in leagueGames where activeGameIDs.contains(game.id) {
                active.insert(game.league)
            }
        }
        return (primary, active)
    }

    private func sortMatchupsByPriority(_ matchups: [FantasyMatchup]) -> [FantasyMatchup] {
        let watched = watchedStreamLeagues()
        return matchups.enumerated().sorted { lhs, rhs in
            let lPrimary = lhs.element.league == watched.primary ? 0 : 1
            let rPrimary = rhs.element.league == watched.primary ? 0 : 1
            if lPrimary != rPrimary { return lPrimary < rPrimary }
            let lActive = watched.active.contains(lhs.element.league) ? 0 : 1
            let rActive = watched.active.contains(rhs.element.league) ? 0 : 1
            if lActive != rActive { return lActive < rActive }
            let lRank = leaguePriorityRank(for: lhs.element.league)
            let rRank = leaguePriorityRank(for: rhs.element.league)
            if lRank != rRank { return lRank < rRank }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func sortQuotesByPriority(_ quotes: [PredictionMarketQuote]) -> [PredictionMarketQuote] {
        quotes.sorted { lhs, rhs in
            let m1 = lhs.matchedGameID.map { activeGameIDs.contains($0) } == true ? 0 : 1
            let m2 = rhs.matchedGameID.map { activeGameIDs.contains($0) } == true ? 0 : 1
            if m1 != m2 { return m1 < m2 }
            let p1 = lhs.league.map { leaguePriorityRank(for: $0) } ?? 99
            let p2 = rhs.league.map { leaguePriorityRank(for: $0) } ?? 99
            if p1 != p2 { return p1 < p2 }
            let v1 = lhs.volumeUSD ?? 0
            let v2 = rhs.volumeUSD ?? 0
            if abs(v1 - v2) > 0.01 { return v1 > v2 }
            let d1 = max(abs(lhs.delta1m ?? 0), abs(lhs.delta5m ?? 0))
            let d2 = max(abs(rhs.delta1m ?? 0), abs(rhs.delta5m ?? 0))
            if abs(d1 - d2) > 0.0001 { return d1 > d2 }
            return lhs.title < rhs.title
        }
    }

    private func reapplyPriorityOrderingIfNeeded() {
        var changed = false
        if !rawMatchups.isEmpty {
            rawMatchups = sortMatchupsByPriority(rawMatchups)
        }
        if !displayedGames.isEmpty {
            let sortedGames = sortGamesByPriority(displayedGames)
            if sortedGames != displayedGames {
                displayedGames = sortedGames
                changed = true
            }
        }
        if !displayedMatchups.isEmpty {
            let sortedMatchups = sortMatchupsByPriority(displayedMatchups)
            if sortedMatchups != displayedMatchups {
                displayedMatchups = sortedMatchups
                changed = true
            }
        }
        if !displayedMarkets.isEmpty {
            let sortedMarkets = sortQuotesByPriority(displayedMarkets)
            if sortedMarkets != displayedMarkets {
                displayedMarkets = sortedMarkets
                changed = true
            }
        }
        if changed {
            scheduleCoalescedCommit(immediateIfContextChanged: true)
        }
    }

    private func combinedRawGames() -> [LiveGame] {
        sortGamesByPriority(Array(rawGamesByLeague.values.joined()))
    }

    private func enqueueScoreboardState(now: Date) {
        gamesSpoilerBuffer.enqueue(combinedRawGames(), at: now)
    }

    private func applyCachedSummary(to game: LiveGame) -> LiveGame {
        guard let summary = summariesByEventID[game.id] else { return game }
        return applySummary(summary, to: game)
    }

    private func applySummary(_ summary: ESPNGameSummaryUpdate, to game: LiveGame) -> LiveGame {
        LiveGame(
            id: game.id,
            league: game.league,
            status: game.status,
            statusDetail: game.statusDetail,
            clock: game.clock,
            period: game.period,
            startTime: game.startTime,
            away: game.away,
            home: game.home,
            broadcasts: game.broadcasts,
            situation: summary.situation ?? game.situation,
            espnAwayWinProb: summary.awayWinProb ?? game.espnAwayWinProb,
            espnHomeWinProb: summary.homeWinProb ?? game.espnHomeWinProb,
            spreadSummary: summary.spreadSummary ?? game.spreadSummary,
            overUnder: summary.overUnder ?? game.overUnder
        )
    }

    private func recordScoreDeltas(for games: [LiveGame], now: Date) {
        for game in games {
            let isRedZone = game.situation?.isRedZone ?? false
            let current = (away: game.away.score, home: game.home.score, isRedZone: isRedZone)
            if let prev = previousGameScores[game.id] {
                let awayDiff = current.away - prev.away
                let homeDiff = current.home - prev.home
                if awayDiff > 0 {
                    deltaSpoilerBuffer.enqueue(
                        LivePulseDeltaEvent(
                            timestamp: now,
                            kind: .score,
                            gameID: game.id,
                            headline: "\(game.away.abbreviation) \(current.away) – \(game.home.abbreviation) \(current.home)",
                            deltaText: "\(game.away.abbreviation) +\(awayDiff)",
                            isPositive: true
                        ),
                        at: now
                    )
                }
                if homeDiff > 0 {
                    deltaSpoilerBuffer.enqueue(
                        LivePulseDeltaEvent(
                            timestamp: now,
                            kind: .score,
                            gameID: game.id,
                            headline: "\(game.away.abbreviation) \(current.away) – \(game.home.abbreviation) \(current.home)",
                            deltaText: "\(game.home.abbreviation) +\(homeDiff)",
                            isPositive: true
                        ),
                        at: now
                    )
                }
            }
            previousGameScores[game.id] = current
        }
    }

    private func enrichMatchup(_ matchup: FantasyMatchup, now: Date) -> FantasyMatchup {
        let games = combinedRawGames().filter { $0.league == matchup.league }

        func enrichPlayer(_ player: FantasyPlayerLine) -> FantasyPlayerLine {
            let teamCode = SportsEntityMatcher.canonicalESPNCode(player.nflOrProTeam, league: matchup.league)
            let matchedGame = games.first { game in
                SportsEntityMatcher.canonicalESPNCode(game.away.abbreviation, league: matchup.league) == teamCode
                    || SportsEntityMatcher.canonicalESPNCode(game.home.abbreviation, league: matchup.league) == teamCode
            }

            let isActiveInStream = matchedGame.map { activeGameIDs.contains($0.id) } ?? false

            var isRedZone = false
            if let game = matchedGame, game.status == .live, game.situation?.isRedZone == true {
                if let possID = game.situation?.possessionTeamID {
                    let playerTeamID: String? = {
                        if SportsEntityMatcher.canonicalESPNCode(game.away.abbreviation, league: matchup.league) == teamCode {
                            return game.away.espnTeamID
                        }
                        if SportsEntityMatcher.canonicalESPNCode(game.home.abbreviation, league: matchup.league) == teamCode {
                            return game.home.espnTeamID
                        }
                        return nil
                    }()
                    isRedZone = (playerTeamID == possID)
                } else {
                    isRedZone = true
                }
            }

            let liveStatLine: String? = matchedGame.flatMap { game in
                guard let summary = summariesByEventID[game.id] else { return nil }
                if let espnID = player.espnPlayerID,
                   !espnID.isEmpty,
                   let byID = summary.athleteStats[espnID] {
                    return byID
                }
                let normalizedPos = player.position.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if normalizedPos == "DEF" || normalizedPos == "DST" || normalizedPos == "D/ST" {
                    let defKey = ESPNScoreboardClient.normalizedPlayerNameTeamKey(
                        name: "def",
                        team: teamCode,
                        league: matchup.league
                    )
                    if let defLine = summary.athleteStatsByNameAndTeam[defKey] {
                        return defLine
                    }
                }
                let nameKey = ESPNScoreboardClient.normalizedPlayerNameTeamKey(
                    name: player.name,
                    team: teamCode,
                    league: matchup.league
                )
                return summary.athleteStatsByNameAndTeam[nameKey]
            }

            if let prevPts = previousPlayerPoints[player.id] {
                let diff = player.points - prevPts
                if abs(diff) >= 0.05 {
                    recentPlayerDeltas[player.id] = (diff, now)
                    if player.isUserRoster {
                        let sign = diff >= 0 ? "+" : ""
                        deltaSpoilerBuffer.enqueue(
                            LivePulseDeltaEvent(
                                timestamp: now,
                                kind: .fantasyPoints,
                                gameID: matchedGame?.id,
                                headline: player.name,
                                deltaText: String(format: "%@%.1f pts", sign, diff),
                                isPositive: diff >= 0,
                                isBench: !player.isStarter
                            ),
                            at: now
                        )
                    }
                }
            }
            previousPlayerPoints[player.id] = player.points

            let activeDelta: Double?
            if let recorded = recentPlayerDeltas[player.id], now.timeIntervalSince(recorded.recordedAt) <= 60 {
                activeDelta = recorded.delta
            } else {
                recentPlayerDeltas.removeValue(forKey: player.id)
                activeDelta = nil
            }

            return FantasyPlayerLine(
                id: player.id,
                espnPlayerID: player.espnPlayerID,
                name: player.name,
                position: player.position,
                nflOrProTeam: player.nflOrProTeam,
                points: player.points,
                projectedPoints: player.projectedPoints,
                isStarter: player.isStarter,
                isUserRoster: player.isUserRoster,
                matchedGameID: matchedGame?.id,
                isActiveInStream: isActiveInStream,
                isRedZone: isRedZone,
                liveStatLine: liveStatLine,
                lastDeltaPoints: activeDelta
            )
        }

        return FantasyMatchup(
            id: matchup.id,
            configID: matchup.configID,
            provider: matchup.provider,
            league: matchup.league,
            leagueName: matchup.leagueName,
            weekLabel: matchup.weekLabel,
            userTeamName: matchup.userTeamName,
            opponentTeamName: matchup.opponentTeamName,
            userPoints: matchup.userPoints,
            opponentPoints: matchup.opponentPoints,
            userProjected: matchup.userProjected,
            opponentProjected: matchup.opponentProjected,
            starters: matchup.starters.map(enrichPlayer),
            bench: matchup.bench.map(enrichPlayer),
            opponentStarters: matchup.opponentStarters.map(enrichPlayer)
        )
    }

    private func matchQuoteToGame(_ quote: PredictionMarketQuote, games: [LiveGame]) -> PredictionMarketQuote {
        if quote.matchedGameID != nil { return quote }
        let candidateGames = quote.league.map { league in games.filter { $0.league == league } } ?? games
        let haystack = "\(quote.title) \(quote.tickerOrSlug) \(quote.outcomeLabel)".lowercased()
        let tickerUpper = quote.tickerOrSlug.uppercased()

        let matched = candidateGames.first { game in
            let awayAbbr = SportsEntityMatcher.canonicalESPNCode(game.away.abbreviation, league: game.league)
            let homeAbbr = SportsEntityMatcher.canonicalESPNCode(game.home.abbreviation, league: game.league)
            let awayShort = game.away.shortName.lowercased()
            let homeShort = game.home.shortName.lowercased()

            let titleMatchesBoth = (!awayShort.isEmpty && haystack.contains(awayShort))
                && (!homeShort.isEmpty && haystack.contains(homeShort))
            if titleMatchesBoth {
                return true
            }

            let awayTeam = SportsEntityMatcher.resolveTeam(awayAbbr, in: game.league)
            let homeTeam = SportsEntityMatcher.resolveTeam(homeAbbr, in: game.league)
            if let awayTeam, let homeTeam {
                let awayKalshi = awayTeam.kalshiTricode
                let homeKalshi = homeTeam.kalshiTricode
                if tickerUpper.contains("\(awayKalshi)\(homeKalshi)")
                    || tickerUpper.contains("\(homeKalshi)\(awayKalshi)")
                    || (tickerUpper.contains("-\(awayKalshi)-") && haystack.contains(homeShort))
                    || (tickerUpper.contains("-\(homeKalshi)-") && haystack.contains(awayShort)) {
                    return true
                }
            }
            return false
        }

        guard let matched else { return quote }
        return PredictionMarketQuote(
            id: quote.id,
            provider: quote.provider,
            league: quote.league ?? matched.league,
            matchedGameID: matched.id,
            tickerOrSlug: quote.tickerOrSlug,
            title: quote.title,
            outcomeLabel: quote.outcomeLabel,
            yesProbability: quote.yesProbability,
            delta1m: quote.delta1m,
            delta5m: quote.delta5m,
            volumeUSD: quote.volumeUSD,
            updatedAt: quote.updatedAt,
            externalURLString: quote.externalURLString
        )
    }

    private func mergedMarketQuotes(now: Date) -> [PredictionMarketQuote] {
        let updatedPoly = rawPolymarketQuotes.map { quote -> PredictionMarketQuote in
            guard let liveTick = livePolymarketTickProbabilities[quote.tickerOrSlug] else {
                return quote
            }
            return PredictionMarketQuote(
                id: quote.id,
                provider: quote.provider,
                league: quote.league,
                matchedGameID: quote.matchedGameID,
                tickerOrSlug: quote.tickerOrSlug,
                title: quote.title,
                outcomeLabel: quote.outcomeLabel,
                yesProbability: liveTick.probability,
                delta1m: liveTick.probability - quote.yesProbability,
                delta5m: quote.delta5m,
                volumeUSD: quote.volumeUSD,
                updatedAt: liveTick.timestamp,
                externalURLString: quote.externalURLString
            )
        }
        _ = now
        return sortQuotesByPriority(rawKalshiQuotes + updatedPoly)
    }

    private func recomputeStreamContexts(now: Date) {
        let allSignals = signalsByWindowID.values.flatMap { $0 }
        let games = combinedRawGames()

        var nextContexts: [UUID: StreamSportContext] = [:]
        var nextActiveGameIDs: Set<String> = []
        var chosenPrimary: StreamSportContext = .none

        for signal in allSignals {
            let resolved: StreamSportContext
            if let pin = manualPinsByTab[signal.tabID] {
                let currentScope = scopeKey(for: signal.url)
                if pin.isLocked || pin.scopeKey == currentScope {
                    switch pin.mode {
                    case .game(let gameID, let league):
                        let label = games.first(where: { $0.id == gameID })
                            .map { "\($0.away.abbreviation) @ \($0.home.abbreviation)" }
                            ?? league.displayName
                        resolved = .matchedGame(gameID: gameID, league: league, confidence: .manual, sourceLabel: label)
                    case .liveSlate(let league, let label):
                        resolved = .liveSlate(league: league, label: label)
                    }
                } else {
                    manualPinsByTab.removeValue(forKey: signal.tabID)
                    let raw = SportsEntityMatcher.match(signal: signal, games: games)
                    resolved = streamHysteresis.resolve(signal: signal, rawContext: raw, at: now)
                }
            } else {
                let raw = SportsEntityMatcher.match(signal: signal, games: games)
                resolved = streamHysteresis.resolve(signal: signal, rawContext: raw, at: now)
            }

            nextContexts[signal.tabID] = resolved
            switch resolved {
            case .matchedGame(let gameID, _, _, _):
                nextActiveGameIDs.insert(gameID)
            case .networkCandidates(_, _, let gameIDs):
                nextActiveGameIDs.formUnion(gameIDs)
            case .liveSlate(let league, _):
                for g in games where g.league == league && (g.status == .live || g.status == .halftime) {
                    nextActiveGameIDs.insert(g.id)
                }
            case .none:
                break
            }

            if signal.isPrimaryFocus && resolved != .none {
                chosenPrimary = resolved
            } else if chosenPrimary == .none && resolved != .none {
                chosenPrimary = resolved
            }
        }

        streamContextByTab = nextContexts
        activeGameIDs = nextActiveGameIDs
        primaryContext = chosenPrimary
    }

    private func prioritizedActiveGamesForSummary(limit: Int = 8) -> [LiveGame] {
        let liveGames = combinedRawGames().filter { $0.status == .live || $0.status == .halftime }
        guard !liveGames.isEmpty, limit > 0 else { return [] }

        var prioritized: [LiveGame] = []
        var seen: Set<String> = []

        func appendIfLive(_ game: LiveGame) {
            if seen.insert(game.id).inserted {
                prioritized.append(game)
            }
        }

        // 1a. Primary watched/pinned focus game(s) first.
        switch primaryContext {
        case .matchedGame(let gid, _, _, _):
            if let game = liveGames.first(where: { $0.id == gid }) {
                appendIfLive(game)
            }
        case .networkCandidates(_, _, let gids):
            for gid in gids {
                if let game = liveGames.first(where: { $0.id == gid }) {
                    appendIfLive(game)
                }
            }
        case .liveSlate(let league, _):
            for game in liveGames where game.league == league {
                appendIfLive(game)
            }
        case .none:
            break
        }

        // 1b. Remaining watched/pinned active games (ordered by leaguePriorityRank via liveGames).
        for game in liveGames where activeGameIDs.contains(game.id) {
            appendIfLive(game)
        }

        // 2. Any live/halftime games containing any user fantasy starter OR bench player, ordered by leaguePriorityRank.
        let userRosterTargets: [(league: SportsLeague, teamCode: String, matchedGameID: String?)] = rawMatchups.flatMap { matchup in
            (matchup.starters + matchup.bench)
                .filter(\.isUserRoster)
                .map { player in
                    (
                        league: matchup.league,
                        teamCode: SportsEntityMatcher.canonicalESPNCode(player.nflOrProTeam, league: matchup.league),
                        matchedGameID: player.matchedGameID
                    )
                }
        }

        if !userRosterTargets.isEmpty {
            for game in liveGames where !seen.contains(game.id) {
                let awayCode = SportsEntityMatcher.canonicalESPNCode(game.away.abbreviation, league: game.league)
                let homeCode = SportsEntityMatcher.canonicalESPNCode(game.home.abbreviation, league: game.league)
                let hasUserPlayer = userRosterTargets.contains { target in
                    if let matchedID = target.matchedGameID, matchedID == game.id {
                        return true
                    }
                    return target.league == game.league
                        && !target.teamCode.isEmpty
                        && (target.teamCode == awayCode || target.teamCode == homeCode)
                }
                if hasUserPlayer {
                    appendIfLive(game)
                }
            }
        }

        return Array(prioritized.prefix(limit))
    }

    private func resolveSleeperUserIDIfNeeded(configs: [FantasyLeagueConfig]) async -> String? {
        let username = settings.livePulseSleeperUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty {
            let key = username.lowercased()
            if let cached = resolvedSleeperUserIDByUsername[key] {
                return cached
            }
            if let user = try? await sleeperClient.fetchUser(username: username) {
                resolvedSleeperUserIDByUsername[key] = user.userID
                return user.userID
            }
        }
        return configs.compactMap(\.teamOwnerHint).first
    }

    private func resolveSleeperWeek(for sport: String) async -> Int? {
        let now = Date()
        if let cached = sleeperSportStateBySport[sport], now.timeIntervalSince(cached.fetchedAt) < 300 {
            return cached.state.week
        }
        if let state = try? await sleeperClient.fetchSportState(sport: sport) {
            sleeperSportStateBySport[sport] = (state, now)
            return state.week
        }
        return sleeperSportStateBySport[sport]?.state.week
    }

    private func scopeKey(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        let path = url.standardized.path.lowercased()
        if let videoID = YouTubeURLRouter.extractVideoID(from: url) {
            return "\(host)\(path)?v=\(videoID)"
        }
        return "\(host)\(path)"
    }

    // MARK: - Spoiler Drain & Coalesced Snapshot Commits (<= 1 Hz)

    private func drainSpoilerBuffersAndCommitIfReady() {
        let now = Date()
        let delay = settings.livePulseSpoilerDelay
        var changed = false

        if let readyGames = gamesSpoilerBuffer.drainReady(at: now, delay: delay).last {
            displayedGames = readyGames
            changed = true
        }
        if let readyMatchups = matchupsSpoilerBuffer.drainReady(at: now, delay: delay).last {
            displayedMatchups = readyMatchups
            changed = true
        }
        if let readyMarkets = marketsSpoilerBuffer.drainReady(at: now, delay: delay).last {
            displayedMarkets = readyMarkets
            changed = true
        }
        let readyDeltas = deltaSpoilerBuffer.drainReady(at: now, delay: delay)
        if !readyDeltas.isEmpty {
            displayedDeltas = Array((readyDeltas.reversed() + displayedDeltas).prefix(20))
            changed = true
        }

        if changed {
            commitSnapshotNow()
        }
    }

    private func flushAllSpoilerBuffersImmediately(at now: Date = Date()) {
        if let readyGames = gamesSpoilerBuffer.drainReady(at: now, delay: .off).last {
            displayedGames = readyGames
        }
        if let readyMatchups = matchupsSpoilerBuffer.drainReady(at: now, delay: .off).last {
            displayedMatchups = readyMatchups
        }
        if let readyMarkets = marketsSpoilerBuffer.drainReady(at: now, delay: .off).last {
            displayedMarkets = readyMarkets
        }
        let readyDeltas = deltaSpoilerBuffer.drainReady(at: now, delay: .off)
        if !readyDeltas.isEmpty {
            displayedDeltas = Array((readyDeltas.reversed() + displayedDeltas).prefix(20))
        }
    }

    private func scheduleCoalescedCommit(immediateIfContextChanged: Bool = false) {
        let now = Date()
        let delay = settings.livePulseSpoilerDelay

        if delay == .off {
            flushAllSpoilerBuffersImmediately(at: now)
        } else {
            drainSpoilerBuffersAndCommitIfReady()
        }

        let elapsed = now.timeIntervalSince(lastSnapshotCommitAt)
        if immediateIfContextChanged || elapsed >= 1.0 {
            commitCoalesceTask?.cancel()
            commitCoalesceTask = nil
            commitSnapshotNow()
            return
        }

        guard commitCoalesceTask == nil else { return }
        let remaining = max(0.05, 1.0 - elapsed)
        commitCoalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self, self.settings.livePulseEnabled, !self.isShutDown else { return }
            self.commitCoalesceTask = nil
            self.commitSnapshotNow()
        }
    }

    private func commitSnapshotNow() {
        let now = Date()
        lastSnapshotCommitAt = now
        let nextSnapshot = LivePulseSnapshot(
            games: displayedGames,
            matchups: displayedMatchups,
            markets: settings.livePulseShowMarkets ? displayedMarkets : [],
            recentDeltas: displayedDeltas,
            streamContextByTab: streamContextByTab,
            primaryContext: primaryContext,
            activeGameIDs: activeGameIDs,
            providerStatus: providerStatus,
            lastUpdatedAt: now
        )
        if snapshot != nextSnapshot {
            snapshot = nextSnapshot
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
