import Foundation

/// Privacy-safe, cookieless native Swift client for YouTube search autocomplete suggestions.
/// Fails silently offline or on timeout (2s) so typing in the Command Palette never blocks.
public struct YouTubeSuggestClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 2.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    /// Parses YouTube's Firefox-client suggest JSON payload: `["query", ["suggestion 1", "suggestion 2", ...]]`.
    public static func parseSuggestions(from data: Data, maxCount: Int = 6) -> [String] {
        guard maxCount > 0,
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              root.count >= 2,
              let rawList = root[1] as? [Any] else {
            return []
        }

        var seen = Set<String>()
        var results: [String] = []
        results.reserveCapacity(min(rawList.count, maxCount))

        for entry in rawList {
            guard let text = entry as? String else { continue }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let key = clean.lowercased()
            if seen.insert(key).inserted {
                results.append(clean)
                if results.count >= maxCount {
                    break
                }
            }
        }
        return results
    }

    /// Fetches up to `maxCount` YouTube autocomplete suggestions for `query`, returning `[]` silently on any error.
    public func fetchSuggestions(for query: String, maxCount: Int = 6) async -> [String] {
        guard CommandPaletteEngine.shouldFetchSuggestions(for: query) else {
            return []
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = components?.url else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.httpShouldHandleCookies = false
            request.timeoutInterval = 2.0
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            return Self.parseSuggestions(from: data, maxCount: maxCount)
        } catch {
            return []
        }
    }
}
