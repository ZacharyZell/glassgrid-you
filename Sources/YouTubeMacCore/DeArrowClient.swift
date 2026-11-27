import Foundation

/// Sanitized DeArrow branding result combining an optional clean title and community thumbnail URL.
public struct DeArrowBranding: Equatable, Sendable {
    public let title: String?
    public let thumbnailURL: URL?

    public init(title: String? = nil, thumbnailURL: URL? = nil) {
        self.title = title
        self.thumbnailURL = thumbnailURL
    }
}

/// Privacy-preserving k-anonymous DeArrow branding client (fetches by 4-character SHA-256 video ID prefix).
/// Strictly opt-in, cookieless ephemeral, silent-failing, short-timeout, and bounded 120-entry LRU cached.
public actor DeArrowClient {
    private struct APIBrandingEntry: Decodable {
        let titles: [APITitleEntry]?
        let thumbnails: [APIThumbnailEntry]?
    }

    private struct APITitleEntry: Decodable {
        let title: String
        let original: Bool?
        let votes: Int?
        let locked: Bool?
    }

    private struct APIThumbnailEntry: Decodable {
        let timestamp: Double?
        let original: Bool?
        let votes: Int?
        let locked: Bool?
    }

    private let session: URLSession
    private var cache: [String: DeArrowBranding?] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: [String: Task<DeArrowBranding?, Never>] = [:]
    private let maxCacheEntries = 120

    public init(timeoutInterval: TimeInterval = 3.0) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }

    /// Parses DeArrow k-anonymous branding payload (clean title + thumbnail URL) for `videoID`,
    /// ignoring `original == true`, preferring `locked == true` or highest `votes >= 0`.
    public nonisolated static func parseBranding(from data: Data, videoID: String) -> DeArrowBranding? {
        guard isValidVideoID(videoID),
              let entries = try? JSONDecoder().decode([String: APIBrandingEntry].self, from: data),
              let match = entries[videoID] else {
            return nil
        }

        let bestTitle = selectBestTitle(from: match.titles)
        let bestThumbnailURL = selectBestThumbnailURL(from: match.thumbnails, videoID: videoID)

        guard bestTitle != nil || bestThumbnailURL != nil else {
            return nil
        }
        return DeArrowBranding(title: bestTitle, thumbnailURL: bestThumbnailURL)
    }

    /// Parses DeArrow k-anonymous branding payload for `videoID`, ignoring `original == true`,
    /// preferring `locked == true` or highest `votes >= 0`, and sanitizing via `AgentSecurity.sanitizeWebText`.
    public nonisolated static func parseCleanTitle(from data: Data, videoID: String) -> String? {
        parseBranding(from: data, videoID: videoID)?.title
    }

    /// Fetches community-curated DeArrow branding (clean title and/or thumbnail frame URL) for `videoID`.
    public func fetchBranding(for videoID: String) async -> DeArrowBranding? {
        guard Self.isValidVideoID(videoID) else { return nil }

        if let cached = cache[videoID] {
            touchCacheKey(videoID)
            return cached
        }

        if let existingTask = inFlight[videoID] {
            return await existingTask.value
        }

        let session = self.session
        let prefix = SponsorBlockClient.hashPrefix(for: videoID)

        let task = Task<DeArrowBranding?, Never> {
            guard let url = URL(string: "https://sponsor.ajay.app/api/branding/\(prefix)") else {
                return nil
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 3.0

            do {
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse else {
                    return nil
                }
                if http.statusCode == 404 {
                    return nil
                }
                guard (200...299).contains(http.statusCode) else {
                    return nil
                }
                return Self.parseBranding(from: data, videoID: videoID)
            } catch {
                return nil
            }
        }

        inFlight[videoID] = task
        let result = await task.value
        inFlight[videoID] = nil

        if !Task.isCancelled {
            storeInCache(videoID: videoID, branding: result)
        }
        return result
    }

    /// Fetches a community-curated non-clickbait title for `videoID` with short timeout and silent failure.
    public func fetchCleanTitle(for videoID: String) async -> String? {
        await fetchBranding(for: videoID)?.title
    }

    private nonisolated static func isValidVideoID(_ videoID: String) -> Bool {
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

    private nonisolated static func selectBestTitle(from titles: [APITitleEntry]?) -> String? {
        guard let titles else { return nil }

        let candidates: [(entry: APITitleEntry, sanitized: String)] = titles.compactMap { item in
            if item.original == true {
                return nil
            }
            let isLocked = item.locked == true
            let votes = item.votes ?? 0
            guard isLocked || votes >= 0 else {
                return nil
            }
            let clean = AgentSecurity.sanitizeWebText(item.title, maxLength: AgentSecurity.maxWebTitleLength)
                .text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                return nil
            }
            return (item, clean)
        }

        guard let best = candidates.max(by: { lhs, rhs in
            let lhsLocked = lhs.entry.locked == true
            let rhsLocked = rhs.entry.locked == true
            if lhsLocked != rhsLocked {
                return !lhsLocked && rhsLocked
            }
            let lhsVotes = lhs.entry.votes ?? 0
            let rhsVotes = rhs.entry.votes ?? 0
            return lhsVotes < rhsVotes
        }) else {
            return nil
        }

        return best.sanitized
    }

    private nonisolated static func selectBestThumbnailURL(from thumbnails: [APIThumbnailEntry]?, videoID: String) -> URL? {
        guard let thumbnails else { return nil }

        let candidates: [(entry: APIThumbnailEntry, timestamp: Double)] = thumbnails.compactMap { item in
            if item.original == true {
                return nil
            }
            guard let timestamp = item.timestamp, timestamp.isFinite, timestamp >= 0 else {
                return nil
            }
            let isLocked = item.locked == true
            let votes = item.votes ?? 0
            guard isLocked || votes >= 0 else {
                return nil
            }
            return (item, timestamp)
        }

        guard let best = candidates.max(by: { lhs, rhs in
            let lhsLocked = lhs.entry.locked == true
            let rhsLocked = rhs.entry.locked == true
            if lhsLocked != rhsLocked {
                return !lhsLocked && rhsLocked
            }
            let lhsVotes = lhs.entry.votes ?? 0
            let rhsVotes = rhs.entry.votes ?? 0
            return lhsVotes < rhsVotes
        }) else {
            return nil
        }

        let formattedTime = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), best.timestamp)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "dearrow-thumb.ajay.app"
        components.path = "/api/v1/getThumbnail"
        components.queryItems = [
            URLQueryItem(name: "videoID", value: videoID),
            URLQueryItem(name: "time", value: formattedTime)
        ]

        guard let url = components.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "dearrow-thumb.ajay.app" else {
            return nil
        }
        return url
    }

    private func touchCacheKey(_ videoID: String) {
        if let idx = cacheOrder.firstIndex(of: videoID) {
            cacheOrder.remove(at: idx)
            cacheOrder.append(videoID)
        }
    }

    private func storeInCache(videoID: String, branding: DeArrowBranding?) {
        if let idx = cacheOrder.firstIndex(of: videoID) {
            cacheOrder.remove(at: idx)
        } else if cacheOrder.count >= maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        cacheOrder.append(videoID)
        cache[videoID] = branding
    }
}
