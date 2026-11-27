import Foundation

/// Rolling 1m and 5m probability delta tracker with a bounded sample ring buffer per market.
public struct ProbabilityDeltaTracker: Sendable {
    public struct Sample: Equatable, Sendable {
        public let probability: Double
        public let timestamp: Date

        public init(probability: Double, timestamp: Date) {
            self.probability = probability
            self.timestamp = timestamp
        }
    }

    public static var defaultMaxSamplesPerMarket: Int { 120 }

    public let maxSamplesPerMarket: Int
    private var samplesByMarket: [String: [Sample]] = [:]

    public init(maxSamplesPerMarket: Int = 120) {
        self.maxSamplesPerMarket = max(2, maxSamplesPerMarket)
    }

    public mutating func record(marketID: String, probability: Double, at timestamp: Date = Date()) {
        let clamped = min(1.0, max(0.0, probability))
        var list = samplesByMarket[marketID] ?? []
        if list.count >= maxSamplesPerMarket {
            list.removeFirst(list.count - maxSamplesPerMarket + 1)
        }
        list.append(Sample(probability: clamped, timestamp: timestamp))
        samplesByMarket[marketID] = list
    }

    public func deltas(
        for marketID: String,
        currentProbability: Double,
        at now: Date = Date()
    ) -> (delta1m: Double?, delta5m: Double?) {
        guard let list = samplesByMarket[marketID], !list.isEmpty else {
            return (nil, nil)
        }
        let target1m = now.addingTimeInterval(-60)
        let target5m = now.addingTimeInterval(-300)

        let baseline1m = list.last(where: { $0.timestamp <= target1m && now.timeIntervalSince($0.timestamp) <= 600 })
        let baseline5m = list.last(where: { $0.timestamp <= target5m && now.timeIntervalSince($0.timestamp) <= 1200 })

        let delta1m = baseline1m.map { currentProbability - $0.probability }
        let delta5m = baseline5m.map { currentProbability - $0.probability }
        return (delta1m, delta5m)
    }

    public func sampleCount(for marketID: String) -> Int {
        samplesByMarket[marketID]?.count ?? 0
    }

    public mutating func clear() {
        samplesByMarket.removeAll()
    }
}

/// Strictly read-only public prediction market client for Kalshi REST and Polymarket Gamma REST + CLOB WebSocket.
public actor PredictionMarketsClient {
    public static let kalshiPrimaryBaseURL = "https://external-api.kalshi.com/trade-api/v2"
    public static let kalshiFallbackBaseURL = "https://api.elections.kalshi.com/trade-api/v2"
    public static let polymarketGammaBaseURL = "https://gamma-api.polymarket.com"
    public static let polymarketWebSocketURL = URL(string: "wss://ws-subscriptions-clob.polymarket.com/ws/market")!
    public static let maxStreamAssets = 24

    private let session: URLSession
    private var deltaTracker = ProbabilityDeltaTracker()

    // Kalshi rate-limit / auth exponential backoff state
    private var kalshiCooldownUntil: Date?
    private var kalshiBackoffSeconds: TimeInterval = 15

    // Polymarket CLOB WebSocket stream state
    private var wsTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var subscribedAssetIDs: [String] = []
    private var subscribedAssetSet: Set<String> = []
    private var streamGeneration: Int = 0
    private var onTickHandler: (@Sendable (String, Double, Date) -> Void)?

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Kalshi Public REST

    public func fetchKalshiMarkets(for leagues: [SportsLeague]) async -> [PredictionMarketQuote] {
        let now = Date()
        if let cooldownUntil = kalshiCooldownUntil, now < cooldownUntil {
            return []
        }

        var quotes: [PredictionMarketQuote] = []
        for league in leagues {
            let path = "/events?series_ticker=\(league.kalshiSeriesTicker)&status=open&with_nested_markets=true"
            if let data = await fetchKalshiWithFallback(path: path, now: now) {
                let parsed = Self.parseKalshiEvents(from: data, league: league, now: now)
                for item in parsed {
                    deltaTracker.record(marketID: item.id, probability: item.yesProbability, at: now)
                    let deltas = deltaTracker.deltas(for: item.id, currentProbability: item.yesProbability, at: now)
                    quotes.append(
                        PredictionMarketQuote(
                            id: item.id,
                            provider: item.provider,
                            league: item.league,
                            matchedGameID: item.matchedGameID,
                            tickerOrSlug: item.tickerOrSlug,
                            title: item.title,
                            outcomeLabel: item.outcomeLabel,
                            yesProbability: item.yesProbability,
                            delta1m: deltas.delta1m,
                            delta5m: deltas.delta5m,
                            volumeUSD: item.volumeUSD,
                            updatedAt: item.updatedAt,
                            externalURLString: item.externalURLString
                        )
                    )
                }
            }
        }
        return quotes
    }

    private func fetchKalshiWithFallback(path: String, now: Date) async -> Data? {
        let hosts = [Self.kalshiPrimaryBaseURL, Self.kalshiFallbackBaseURL]
        for base in hosts {
            guard let url = URL(string: base + path) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 || http.statusCode == 401 || http.statusCode == 403 {
                        kalshiCooldownUntil = now.addingTimeInterval(kalshiBackoffSeconds)
                        kalshiBackoffSeconds = min(120, kalshiBackoffSeconds * 2)
                        continue
                    }
                    guard (200...299).contains(http.statusCode) else { continue }
                }
                kalshiCooldownUntil = nil
                kalshiBackoffSeconds = 15
                return data
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Polymarket Gamma REST

    public func fetchPolymarketSportsMarkets(for leagues: [SportsLeague]) async -> [PredictionMarketQuote] {
        guard !leagues.isEmpty,
              let url = URL(string: "\(Self.polymarketGammaBaseURL)/events?active=true&closed=false&limit=100") else {
            return []
        }
        let now = Date()
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return []
            }
            let parsed = Self.parsePolymarketEvents(from: data, leagues: leagues, now: now)
            return parsed.map { item in
                deltaTracker.record(marketID: item.id, probability: item.yesProbability, at: now)
                let deltas = deltaTracker.deltas(for: item.id, currentProbability: item.yesProbability, at: now)
                return PredictionMarketQuote(
                    id: item.id,
                    provider: item.provider,
                    league: item.league,
                    matchedGameID: item.matchedGameID,
                    tickerOrSlug: item.tickerOrSlug,
                    title: item.title,
                    outcomeLabel: item.outcomeLabel,
                    yesProbability: item.yesProbability,
                    delta1m: deltas.delta1m,
                    delta5m: deltas.delta5m,
                    volumeUSD: item.volumeUSD,
                    updatedAt: item.updatedAt,
                    externalURLString: item.externalURLString
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Polymarket CLOB WebSocket

    public func connectPolymarketStream(
        assetIDs: [String],
        onTick: @escaping @Sendable (String, Double, Date) -> Void
    ) {
        let deduped = Array(Set(assetIDs.filter { !$0.isEmpty })).sorted()
        let capped = Array(deduped.prefix(Self.maxStreamAssets))
        guard !capped.isEmpty else {
            disconnectStream()
            return
        }

        let newSet = Set(capped)
        if newSet == subscribedAssetSet, wsTask != nil {
            onTickHandler = onTick
            return
        }

        disconnectStream()
        streamGeneration += 1
        let gen = streamGeneration
        subscribedAssetIDs = capped
        subscribedAssetSet = newSet
        onTickHandler = onTick
        openWebSocket(generation: gen, backoffIndex: 0)
    }

    public func disconnectStream() {
        streamGeneration += 1
        subscribedAssetIDs = []
        subscribedAssetSet = []
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        onTickHandler = nil
    }

    private func openWebSocket(generation: Int, backoffIndex: Int) {
        guard generation == streamGeneration, !subscribedAssetIDs.isEmpty else { return }

        let task = session.webSocketTask(with: Self.polymarketWebSocketURL)
        wsTask = task
        task.resume()

        let payload: [String: Any] = [
            "assets_ids": subscribedAssetIDs,
            "type": "market",
            "custom_feature_enabled": true
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonText = String(data: jsonData, encoding: .utf8) {
            Task { [weak self] in
                try? await task.send(.string(jsonText))
                await self?.startLoopsIfActive(generation: generation, task: task, backoffIndex: backoffIndex)
            }
        }
    }

    private func startLoopsIfActive(
        generation: Int,
        task: URLSessionWebSocketTask,
        backoffIndex: Int
    ) {
        guard generation == streamGeneration, wsTask === task else { return }

        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                let stillActive = await self?.isGenerationActive(generation) ?? false
                guard stillActive else { break }
                do {
                    try await task.send(.string("PING"))
                } catch {
                    break
                }
            }
        }

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    let rawData: Data?
                    switch message {
                    case .string(let text):
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.caseInsensitiveCompare("PONG") == .orderedSame || trimmed.isEmpty {
                            rawData = nil
                        } else {
                            rawData = trimmed.data(using: .utf8)
                        }
                    case .data(let data):
                        rawData = data
                    @unknown default:
                        rawData = nil
                    }

                    if let data = rawData {
                        let ticks = Self.parsePolymarketWSMessage(from: data, at: Date())
                        if !ticks.isEmpty {
                            await self?.handleParsedTicks(ticks, generation: generation)
                        }
                    }
                } catch {
                    await self?.scheduleReconnect(generation: generation, backoffIndex: backoffIndex)
                    break
                }
            }
        }
    }

    private func isGenerationActive(_ generation: Int) -> Bool {
        generation == streamGeneration && wsTask != nil
    }

    private func handleParsedTicks(
        _ ticks: [(assetID: String, probability: Double, timestamp: Date)],
        generation: Int
    ) {
        guard generation == streamGeneration else { return }
        for tick in ticks {
            deltaTracker.record(marketID: "polymarket:\(tick.assetID)", probability: tick.probability, at: tick.timestamp)
            onTickHandler?(tick.assetID, tick.probability, tick.timestamp)
        }
    }

    private func scheduleReconnect(generation: Int, backoffIndex: Int) {
        guard generation == streamGeneration, !subscribedAssetIDs.isEmpty else { return }
        wsTask = nil
        pingTask?.cancel()
        pingTask = nil

        let scheduleSeconds: [TimeInterval] = [2, 5, 15, 30]
        let delay = scheduleSeconds[min(backoffIndex, scheduleSeconds.count - 1)]
        let nextBackoff = min(backoffIndex + 1, scheduleSeconds.count - 1)

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.openWebSocket(generation: generation, backoffIndex: nextBackoff)
        }
    }

    // MARK: - Pure Offline Parsers

    /// Strictly parses Kalshi fixed-point `_dollars` decimal strings (e.g. `"0.6800"` -> `0.68`) within `0.0...1.0`.
    public nonisolated static func parseFixedPointDollars(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else {
            return nil
        }
        return min(1.0, max(0.0, value))
    }

    public nonisolated static func parseKalshiEvents(
        from data: Data,
        league: SportsLeague,
        now: Date = Date()
    ) -> [PredictionMarketQuote] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            return []
        }

        var quotes: [PredictionMarketQuote] = []
        for event in events {
            let eventTitle = stringValue(event["title"]) ?? ""
            let eventTicker = stringValue(event["event_ticker"]) ?? ""
            let markets = (event["markets"] as? [[String: Any]]) ?? []

            for market in markets {
                guard let ticker = stringValue(market["ticker"]), !ticker.isEmpty else { continue }
                let yesBid = parseFixedPointDollars(stringValue(market["yes_bid_dollars"]))
                    ?? legacyCentsToProb(market["yes_bid"])
                let yesAsk = parseFixedPointDollars(stringValue(market["yes_ask_dollars"]))
                    ?? legacyCentsToProb(market["yes_ask"])
                let lastPrice = parseFixedPointDollars(stringValue(market["last_price_dollars"]))
                    ?? legacyCentsToProb(market["last_price"])

                let probability: Double?
                if let yesBid, let yesAsk {
                    probability = (yesBid + yesAsk) / 2.0
                } else {
                    probability = lastPrice ?? yesBid ?? yesAsk
                }
                guard let prob = probability else { continue }

                let title = stringValue(market["title"]) ?? eventTitle
                let outcomeLabel = stringValue(market["yes_sub_title"])
                    ?? stringValue(market["subtitle"])
                    ?? ticker
                let volume = doubleValue(market["volume_fp"])
                    ?? doubleValue(market["volume"])

                quotes.append(
                    PredictionMarketQuote(
                        id: "kalshi:\(ticker)",
                        provider: .kalshi,
                        league: league,
                        matchedGameID: nil,
                        tickerOrSlug: ticker,
                        title: title.isEmpty ? eventTicker : title,
                        outcomeLabel: outcomeLabel,
                        yesProbability: prob,
                        volumeUSD: volume,
                        updatedAt: now,
                        externalURLString: "https://kalshi.com/markets/\(eventTicker.lowercased())"
                    )
                )
            }
        }
        return quotes
    }

    public nonisolated static func parsePolymarketEvents(
        from data: Data,
        leagues: [SportsLeague],
        now: Date = Date()
    ) -> [PredictionMarketQuote] {
        guard let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let allowedLeagues = Set(leagues)
        var quotes: [PredictionMarketQuote] = []

        for event in events {
            let slug = stringValue(event["slug"]) ?? ""
            let title = stringValue(event["title"]) ?? ""
            let inferredLeague = inferLeagueFromPolymarketEvent(event: event, title: title, slug: slug)
            guard let league = inferredLeague, allowedLeagues.contains(league) else {
                continue
            }

            let markets = (event["markets"] as? [[String: Any]]) ?? []
            for market in markets {
                let outcomes = parseStringArray(market["outcomes"])
                let prices = parseDoubleArray(market["outcomePrices"])
                let tokenIDs = parseStringArray(market["clobTokenIds"])

                guard let firstProb = prices.first else { continue }
                let outcomeLabel = outcomes.first ?? "Yes"
                let tokenID = tokenIDs.first ?? stringValue(market["id"]) ?? slug
                let question = stringValue(market["question"]) ?? title
                let volume = doubleValue(market["volumeNum"]) ?? doubleValue(market["volume"])

                quotes.append(
                    PredictionMarketQuote(
                        id: "polymarket:\(tokenID)",
                        provider: .polymarket,
                        league: league,
                        matchedGameID: nil,
                        tickerOrSlug: tokenID,
                        title: question,
                        outcomeLabel: outcomeLabel,
                        yesProbability: min(1.0, max(0.0, firstProb)),
                        volumeUSD: volume,
                        updatedAt: now,
                        externalURLString: slug.isEmpty ? "https://polymarket.com/sports" : "https://polymarket.com/event/\(slug)"
                    )
                )
            }
        }
        return quotes
    }

    /// Parses top-level Polymarket CLOB WebSocket JSON arrays (`[book, ...]`) and single event objects
    /// (`book`, `price_change` with nested `price_changes`, `best_bid_ask`, `last_trade_price`).
    public nonisolated static func parsePolymarketWSMessage(
        from data: Data,
        at timestamp: Date = Date()
    ) -> [(assetID: String, probability: Double, timestamp: Date)] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let array = json as? [[String: Any]] {
            return array.flatMap { parsePolymarketWSObject($0, at: timestamp) }
        }
        if let object = json as? [String: Any] {
            return parsePolymarketWSObject(object, at: timestamp)
        }
        return []
    }

    // MARK: - Private Parsing Helpers

    private nonisolated static func parsePolymarketWSObject(
        _ object: [String: Any],
        at timestamp: Date
    ) -> [(assetID: String, probability: Double, timestamp: Date)] {
        let eventType = (stringValue(object["event_type"]) ?? "").lowercased()

        // `price_change` payload carries a nested `price_changes` array (or top-level price/asset_id).
        if let changes = object["price_changes"] as? [[String: Any]] {
            var results: [(String, Double, Date)] = []
            for change in changes {
                if let assetID = stringValue(change["asset_id"]),
                   let prob = extractWSProbability(from: change) {
                    results.append((assetID, prob, timestamp))
                }
            }
            return results
        }

        if let assetID = stringValue(object["asset_id"]) {
            if let prob = extractWSProbability(from: object) {
                return [(assetID, prob, timestamp)]
            }
            if eventType == "book" {
                let topBid = (object["bids"] as? [[String: Any]])?.first.flatMap { doubleValue($0["price"]) }
                let topAsk = (object["asks"] as? [[String: Any]])?.first.flatMap { doubleValue($0["price"]) }
                if let topBid, let topAsk {
                    return [(assetID, min(1.0, max(0.0, (topBid + topAsk) / 2.0)), timestamp)]
                }
                if let single = topBid ?? topAsk {
                    return [(assetID, min(1.0, max(0.0, single)), timestamp)]
                }
            }
        }

        return []
    }

    private nonisolated static func extractWSProbability(from dict: [String: Any]) -> Double? {
        if let bestBid = doubleValue(dict["best_bid"]), let bestAsk = doubleValue(dict["best_ask"]) {
            return min(1.0, max(0.0, (bestBid + bestAsk) / 2.0))
        }
        if let lastTrade = doubleValue(dict["last_trade_price"]) {
            return min(1.0, max(0.0, lastTrade))
        }
        if let price = doubleValue(dict["price"]) {
            return min(1.0, max(0.0, price))
        }
        return nil
    }

    private nonisolated static func inferLeagueFromPolymarketEvent(
        event: [String: Any],
        title: String,
        slug: String
    ) -> SportsLeague? {
        var tagsText = ""
        if let tags = event["tags"] as? [[String: Any]] {
            tagsText = tags.compactMap { stringValue($0["slug"]) ?? stringValue($0["label"]) }.joined(separator: " ")
        }
        let haystack = " \(title.lowercased()) \(slug.lowercased().replacingOccurrences(of: "-", with: " ")) \(tagsText.lowercased()) "
        if haystack.contains(" nfl ") || haystack.contains("super bowl") { return .nfl }
        if haystack.contains(" nba ") { return .nba }
        if haystack.contains(" mlb ") || haystack.contains("world series") { return .mlb }
        if haystack.contains(" nhl ") || haystack.contains("stanley cup") { return .nhl }
        if haystack.contains(" ncaaf ") || haystack.contains("college football") || haystack.contains(" cfb ") { return .ncaaf }
        if haystack.contains(" ncaab ") || haystack.contains("college basketball") || haystack.contains("march madness") { return .ncaab }
        if haystack.contains(" mls ") { return .mls }
        if haystack.contains("premier league") || haystack.contains(" epl ") { return .epl }
        if haystack.contains("formula 1") || haystack.contains("formula one") || haystack.contains(" f1 ") || haystack.contains("grand prix") { return .f1 }
        return nil
    }

    private nonisolated static func parseStringArray(_ raw: Any?) -> [String] {
        if let arr = raw as? [String] { return arr }
        if let jsonStr = raw as? String,
           let data = jsonStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        return []
    }

    private nonisolated static func parseDoubleArray(_ raw: Any?) -> [Double] {
        if let arr = raw as? [Double] { return arr }
        if let arr = raw as? [String] { return arr.compactMap(Double.init) }
        if let jsonStr = raw as? String,
           let data = jsonStr.data(using: .utf8),
           let strArr = try? JSONDecoder().decode([String].self, from: data) {
            return strArr.compactMap(Double.init)
        }
        return []
    }

    private nonisolated static func legacyCentsToProb(_ raw: Any?) -> Double? {
        guard let cents = doubleValue(raw), cents.isFinite else { return nil }
        return min(1.0, max(0.0, cents / 100.0))
    }

    private nonisolated static func stringValue(_ raw: Any?) -> String? {
        if let str = raw as? String { return str }
        if let num = raw as? NSNumber { return num.stringValue }
        return nil
    }

    private nonisolated static func doubleValue(_ raw: Any?) -> Double? {
        if let val = raw as? Double { return val }
        if let num = raw as? NSNumber { return num.doubleValue }
        if let str = raw as? String { return Double(str) }
        return nil
    }
}
