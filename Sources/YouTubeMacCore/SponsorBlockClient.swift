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

    /// Parses SponsorBlock k-anonymous JSON payload and extracts valid `"sponsor"` segments for `videoID`.
    public nonisolated static func parseSegments(from data: Data, videoID: String) -> [SponsorSegment] {
        guard let entries = try? JSONDecoder().decode([APIVideoEntry].self, from: data),
              let match = entries.first(where: { $0.videoID == videoID }) else {
            return []
        }

        return match.segments
            .compactMap { seg -> SponsorSegment? in
                guard seg.category == "sponsor",
                      seg.segment.count >= 2 else {
                    return nil
                }
                let start = seg.segment[0]
                let end = seg.segment[1]
                guard start.isFinite, end.isFinite, start >= 0, end > start + 0.5 else {
                    return nil
                }
                return SponsorSegment(start: start, end: end, category: seg.category)
            }
            .sorted { $0.start < $1.start }
    }

    /// Fetches `"sponsor"` skip segments for `videoID` with a short timeout and silent failure.
    public func fetchSponsorSegments(for videoID: String) async -> [SponsorSegment] {
        guard !videoID.isEmpty else { return [] }

        if let cached = cache[videoID] {
            return cached
        }

        if let existingTask = inFlight[videoID] {
            return await existingTask.value
        }

        let session = self.session
        let prefix = Self.hashPrefix(for: videoID)

        let task = Task<[SponsorSegment], Never> {
            guard let url = URL(string: "https://sponsor.ajay.app/api/skipSegments/\(prefix)?category=sponsor") else {
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
                return Self.parseSegments(from: data, videoID: videoID)
            } catch {
                return []
            }
        }

        inFlight[videoID] = task
        let result = await task.value
        inFlight[videoID] = nil

        if !Task.isCancelled {
            storeInCache(videoID: videoID, segments: result)
        }
        return result
    }

    private func storeInCache(videoID: String, segments: [SponsorSegment]) {
        if cache[videoID] == nil {
            cacheOrder.append(videoID)
            if cacheOrder.count > maxCacheEntries {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[videoID] = segments
    }
}
