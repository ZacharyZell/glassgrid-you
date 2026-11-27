import Foundation

/// Privacy-preserving k-anonymous DeArrow branding client (fetches by 4-character SHA-256 video ID prefix).
/// Strictly opt-in, cookieless ephemeral, silent-failing, short-timeout, and bounded 120-entry LRU cached.
public actor DeArrowClient {
    private struct APIBrandingEntry: Decodable {
        let titles: [APITitleEntry]?
    }

    private struct APITitleEntry: Decodable {
        let title: String
        let original: Bool?
        let votes: Int?
        let locked: Bool?
    }

    private let session: URLSession
    private var cache: [String: String?] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: [String: Task<String?, Never>] = [:]
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

    /// Parses DeArrow k-anonymous branding payload for `videoID`, ignoring `original == true`,
    /// preferring `locked == true` or highest `votes >= 0`, and sanitizing via `AgentSecurity.sanitizeWebText`.
    public nonisolated static func parseCleanTitle(from data: Data, videoID: String) -> String? {
        guard !videoID.isEmpty,
              let entries = try? JSONDecoder().decode([String: APIBrandingEntry].self, from: data),
              let match = entries[videoID],
              let titles = match.titles else {
            return nil
        }

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

    /// Fetches a community-curated non-clickbait title for `videoID` with short timeout and silent failure.
    public func fetchCleanTitle(for videoID: String) async -> String? {
        guard !videoID.isEmpty else { return nil }

        if let cached = cache[videoID] {
            touchCacheKey(videoID)
            return cached
        }

        if let existingTask = inFlight[videoID] {
            return await existingTask.value
        }

        let session = self.session
        let prefix = SponsorBlockClient.hashPrefix(for: videoID)

        let task = Task<String?, Never> {
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
                return Self.parseCleanTitle(from: data, videoID: videoID)
            } catch {
                return nil
            }
        }

        inFlight[videoID] = task
        let result = await task.value
        inFlight[videoID] = nil

        if !Task.isCancelled {
            storeInCache(videoID: videoID, title: result)
        }
        return result
    }

    private func touchCacheKey(_ videoID: String) {
        if let idx = cacheOrder.firstIndex(of: videoID) {
            cacheOrder.remove(at: idx)
            cacheOrder.append(videoID)
        }
    }

    private func storeInCache(videoID: String, title: String?) {
        if let idx = cacheOrder.firstIndex(of: videoID) {
            cacheOrder.remove(at: idx)
        } else if cacheOrder.count >= maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        cacheOrder.append(videoID)
        cache[videoID] = title
    }
}
