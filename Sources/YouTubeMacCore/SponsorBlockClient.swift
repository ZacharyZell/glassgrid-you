import CryptoKit
import Foundation

/// Privacy-preserving k-anonymous SponsorBlock API client (fetches by 4-character SHA-256 video ID prefix).
/// Strictly opt-in, silent-failing, short-timeout, and bounded in-memory cached.
public actor SponsorBlockClient {
    private struct APIVideoEntry: Decodable {
        let videoID: String
        let segments: [APISegment]
    }

    private struct APISegment: Decodable {
        let category: String
        let segment: [Double]
    }

    private let session: URLSession
    private var cache: [String: [SponsorSegment]] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: [String: Task<[SponsorSegment], Never>] = [:]
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

    /// Computes the first 4 lowercase hexadecimal characters of the SHA-256 hash of a YouTube video ID.
    public nonisolated static func hashPrefix(for videoID: String) -> String {
        let digest = SHA256.hash(data: Data(videoID.utf8))
        let hex = digest.prefix(2).map { String(format: "%02x", $0) }.joined()
        return hex
    }

    /// Builds the k-anonymous SponsorBlock query URL with JSON-encoded `categories` array via `URLComponents`.
    public nonisolated static func queryURL(
        forPrefix prefix: String,
        categories: Set<String> = SponsorSegmentCategory.defaultCategorySet
    ) -> URL? {
        let effective = resolvedCategories(categories)
        let sorted = effective.sorted()
        guard let encodedArray = try? JSONEncoder().encode(sorted),
              let categoriesJSON = String(data: encodedArray, encoding: .utf8) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "sponsor.ajay.app"
        components.path = "/api/skipSegments/\(prefix)"
        components.queryItems = [
            URLQueryItem(name: "categories", value: categoriesJSON)
        ]
        return components.url
    }

    /// Parses SponsorBlock k-anonymous JSON payload and extracts valid segments matching `allowedCategories`.
    public nonisolated static func parseSegments(
        from data: Data,
        videoID: String,
        allowedCategories: Set<String> = SponsorSegmentCategory.defaultCategorySet
    ) -> [SponsorSegment] {
        let effective = resolvedCategories(allowedCategories)
        guard let entries = try? JSONDecoder().decode([APIVideoEntry].self, from: data),
              let match = entries.first(where: { $0.videoID == videoID }) else {
            return []
        }

        return match.segments
            .compactMap { seg -> SponsorSegment? in
                let normalizedCategory = seg.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard effective.contains(normalizedCategory),
                      seg.segment.count >= 2 else {
                    return nil
                }
                let start = seg.segment[0]
                let end = seg.segment[1]
                let isPointHighlight = normalizedCategory == SponsorSegmentCategory.poiHighlight.rawValue
                guard start.isFinite, end.isFinite, start >= 0 else {
                    return nil
                }
                if isPointHighlight {
                    guard end >= start else {
                        return nil
                    }
                } else {
                    guard end > start + 0.5 else {
                        return nil
                    }
                }
                return SponsorSegment(start: start, end: end, category: normalizedCategory)
            }
            .sorted { $0.start < $1.start }
    }

    /// Fetches skip segments for `videoID` across the requested `categories` with a short timeout and silent failure.
    public func fetchSponsorSegments(
        for videoID: String,
        categories: Set<String> = SponsorSegmentCategory.defaultCategorySet
    ) async -> [SponsorSegment] {
        guard !videoID.isEmpty else { return [] }

        let effective = Self.resolvedCategories(categories)
        let cacheKey = "\(videoID)|\(effective.sorted().joined(separator: ","))"

        if let cached = cache[cacheKey] {
            touchCacheKey(cacheKey)
            return cached
        }

        if let existingTask = inFlight[cacheKey] {
            return await existingTask.value
        }

        let session = self.session
        let prefix = Self.hashPrefix(for: videoID)

        let task = Task<[SponsorSegment], Never> {
            guard let url = Self.queryURL(forPrefix: prefix, categories: effective) else {
                return []
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 3.0

            do {
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse else {
                    return []
                }
                if http.statusCode == 404 {
                    return []
                }
                guard (200...299).contains(http.statusCode) else {
                    return []
                }
                return Self.parseSegments(from: data, videoID: videoID, allowedCategories: effective)
            } catch {
                return []
            }
        }

        inFlight[cacheKey] = task
        let result = await task.value
        inFlight[cacheKey] = nil

        if !Task.isCancelled {
            storeInCache(cacheKey: cacheKey, segments: result)
        }
        return result
    }

    /// Convenience overload accepting typed `SponsorSegmentCategory` values.
    public func fetchSponsorSegments(
        for videoID: String,
        categories: [SponsorSegmentCategory]
    ) async -> [SponsorSegment] {
        await fetchSponsorSegments(for: videoID, categories: Set(categories.map(\.rawValue)))
    }

    private nonisolated static func resolvedCategories(_ categories: Set<String>) -> Set<String> {
        let cleaned = Set(
            categories
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        return cleaned.isEmpty ? SponsorSegmentCategory.defaultCategorySet : cleaned
    }

    private func touchCacheKey(_ cacheKey: String) {
        if let idx = cacheOrder.firstIndex(of: cacheKey) {
            cacheOrder.remove(at: idx)
            cacheOrder.append(cacheKey)
        }
    }

    private func storeInCache(cacheKey: String, segments: [SponsorSegment]) {
        if let idx = cacheOrder.firstIndex(of: cacheKey) {
            cacheOrder.remove(at: idx)
        } else if cacheOrder.count >= maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        cacheOrder.append(cacheKey)
        cache[cacheKey] = segments
    }
}
