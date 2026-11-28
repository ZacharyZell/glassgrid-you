import Foundation

/// Read-only community like/dislike estimate returned by the Return YouTube Dislike API.
public struct ReturnYouTubeDislikeStats: Equatable, Hashable, Codable, Sendable {
    public let videoID: String
    public let likes: Int
    public let dislikes: Int
    public let rating: Double
    public let viewCount: Int?
    public let deleted: Bool
    public let fetchedAt: Date

    public init(
        videoID: String,
        likes: Int,
        dislikes: Int,
        rating: Double,
        viewCount: Int? = nil,
        deleted: Bool = false,
        fetchedAt: Date = Date()
    ) {
        self.videoID = videoID
        self.likes = max(0, likes)
        self.dislikes = max(0, dislikes)
        self.rating = rating.isFinite ? min(max(rating, 0.0), 5.0) : 0.0
        self.viewCount = viewCount.flatMap { $0 >= 0 ? $0 : nil }
        self.deleted = deleted
        self.fetchedAt = fetchedAt
    }

    public var likePercentage: Int? {
        let total = likes + dislikes
        guard total > 0 else { return nil }
        return Int((Double(likes) / Double(total) * 100.0).rounded())
    }

    public var formattedDislikes: String {
        Self.formatCompactCount(dislikes)
    }

    private static func formatCompactCount(_ count: Int) -> String {
        let safe = max(0, count)
        let locale = Locale(identifier: "en_US_POSIX")
        if safe < 1_000 {
            return "\(safe)"
        }
        if safe < 1_000_000 {
            return formatScaled(Double(safe) / 1_000.0, suffix: "K", locale: locale)
        }
        if safe < 1_000_000_000 {
            return formatScaled(Double(safe) / 1_000_000.0, suffix: "M", locale: locale)
        }
        return formatScaled(Double(safe) / 1_000_000_000.0, suffix: "B", locale: locale)
    }

    private static func formatScaled(_ value: Double, suffix: String, locale: Locale) -> String {
        if value >= 100.0 {
            return "\(Int(value.rounded()))\(suffix)"
        }
        let roundedTenth = (value * 10.0).rounded() / 10.0
        if abs(roundedTenth.rounded() - roundedTenth) < 0.05 {
            return "\(Int(roundedTenth.rounded()))\(suffix)"
        }
        return String(format: "%.1f%@", locale: locale, roundedTenth, suffix)
    }
}

/// Strictly opt-in, read-only, cookieless Return YouTube Dislike API client.
/// Never submits votes (`POST`), never sends user IDs, enforces a 60s cooldown on HTTP `429`/`503`,
/// deduplicates in-flight fetches, and keeps a bounded 120-entry LRU cache.
public actor ReturnYouTubeDislikeClient {
    public nonisolated static let attributionURL = URL(string: "https://returnyoutubedislike.com")!
    public nonisolated static let cooldownSeconds: TimeInterval = 60.0

    private struct APIVotesResponse: Decodable {
        let id: String?
        let likes: Int
        let dislikes: Int
        let rating: Double
        let viewCount: Int?
        let deleted: Bool?
    }

    private let session: URLSession
    private let timeoutInterval: TimeInterval
    private var cache: [String: ReturnYouTubeDislikeStats] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: [String: Task<ReturnYouTubeDislikeStats?, Never>] = [:]
    private var cooldownUntil: Date?
    private let maxCacheEntries = 120

    public init(timeoutInterval: TimeInterval = 3.0, session: URLSession? = nil) {
        self.timeoutInterval = max(0.5, timeoutInterval.isFinite ? timeoutInterval : 3.0)
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = self.timeoutInterval
            config.timeoutIntervalForResource = self.timeoutInterval
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = [
                "Accept": "application/json"
            ]
            self.session = URLSession(configuration: config)
        }
    }

    public nonisolated static func isValidVideoID(_ videoID: String) -> Bool {
        guard (6...32).contains(videoID.count) else { return false }
        return videoID.unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return (v >= 65 && v <= 90)      // A-Z
                || (v >= 97 && v <= 122)     // a-z
                || (v >= 48 && v <= 57)      // 0-9
                || scalar == "_"
                || scalar == "-"
        }
    }

    public nonisolated static func queryURL(for videoID: String) -> URL? {
        guard isValidVideoID(videoID) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "returnyoutubedislikeapi.com"
        components.path = "/votes"
        components.queryItems = [
            URLQueryItem(name: "videoId", value: videoID)
        ]
        return components.url
    }

    public nonisolated static func parseStats(
        from data: Data,
        videoID: String,
        now: Date = Date()
    ) -> ReturnYouTubeDislikeStats? {
        guard isValidVideoID(videoID),
              !data.isEmpty,
              let entry = try? JSONDecoder().decode(APIVotesResponse.self, from: data) else {
            return nil
        }
        if let returnedID = entry.id, !returnedID.isEmpty, returnedID != videoID {
            return nil
        }
        guard entry.likes >= 0,
              entry.dislikes >= 0,
              entry.rating.isFinite else {
            return nil
        }
        return ReturnYouTubeDislikeStats(
            videoID: videoID,
            likes: entry.likes,
            dislikes: entry.dislikes,
            rating: min(max(entry.rating, 0.0), 5.0),
            viewCount: entry.viewCount.flatMap { $0 >= 0 ? $0 : nil },
            deleted: entry.deleted ?? false,
            fetchedAt: now
        )
    }

    public func isCoolingDown(at now: Date = Date()) -> Bool {
        guard let cooldownUntil else { return false }
        return now < cooldownUntil
    }

    public func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    public func fetchStats(for videoID: String, now: Date = Date()) async -> ReturnYouTubeDislikeStats? {
        guard Self.isValidVideoID(videoID) else { return nil }

        if let cached = cache[videoID] {
            touchCacheKey(videoID)
            return cached
        }

        if let cooldownUntil, now < cooldownUntil {
            return nil
        }

        if let existingTask = inFlight[videoID] {
            return await existingTask.value
        }

        let session = self.session
        let timeout = self.timeoutInterval

        enum FetchOutcome: Sendable {
            case stats(ReturnYouTubeDislikeStats?)
            case rateLimited
            case failed
        }

        let task = Task<ReturnYouTubeDislikeStats?, Never> {
            guard let url = Self.queryURL(for: videoID) else {
                return nil
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout

            let outcome: FetchOutcome
            do {
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse else {
                    return nil
                }
                if http.statusCode == 429 || http.statusCode == 503 {
                    outcome = .rateLimited
                } else if (200...299).contains(http.statusCode) {
                    outcome = .stats(Self.parseStats(from: data, videoID: videoID, now: now))
                } else {
                    outcome = .failed
                }
            } catch {
                outcome = .failed
            }

            switch outcome {
            case .rateLimited:
                self.activateCooldown(from: now)
                return nil
            case .failed:
                return nil
            case .stats(let stats):
                if let stats {
                    self.storeInCache(videoID: videoID, stats: stats)
                }
                return stats
            }
        }

        inFlight[videoID] = task
        let result = await task.value
        inFlight[videoID] = nil
        return result
    }

    private func activateCooldown(from now: Date) {
        cooldownUntil = now.addingTimeInterval(Self.cooldownSeconds)
    }

    private func touchCacheKey(_ videoID: String) {
        if let idx = cacheOrder.firstIndex(of: videoID) {
            cacheOrder.remove(at: idx)
            cacheOrder.append(videoID)
        }
    }

    private func storeInCache(videoID: String, stats: ReturnYouTubeDislikeStats) {
        if let idx = cacheOrder.firstIndex(of: videoID) {
            cacheOrder.remove(at: idx)
        } else if cacheOrder.count >= maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        cacheOrder.append(videoID)
        cache[videoID] = stats
    }
}
