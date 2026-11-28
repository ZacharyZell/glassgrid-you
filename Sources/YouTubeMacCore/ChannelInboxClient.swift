import Foundation

/// Normalized upload entry parsed from a YouTube Channel Atom RSS feed (`/feeds/videos.xml?channel_id=...`).
public struct ChannelInboxEntry: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let videoID: String
    public let title: String
    public let channelName: String
    public let channelID: String
    public let publishedAt: Date?

    public init(
        videoID: String,
        title: String,
        channelName: String,
        channelID: String,
        publishedAt: Date? = nil
    ) {
        self.id = videoID
        self.videoID = videoID
        self.title = title
        self.channelName = channelName
        self.channelID = channelID
        self.publishedAt = publishedAt
    }

    public var watchURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    public var thumbnailURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }
}

/// Filter selection for per-folder YouTube Channel RSS Inbox decks.
public enum ChannelInboxFilter: Equatable, Hashable, Codable, Sendable {
    case all
    case ungrouped
    case folder(UUID)
}

/// Pure helper extracting deduplicated `UC...` channel IDs per folder filter and filtering watched entries.
public enum ChannelInboxFilterHelper {
    public static func channelIDs(
        for filter: ChannelInboxFilter,
        folders: [PinnedFolder],
        pins: [PinnedItem],
        watchedChannels: [WatchedChannelStat]
    ) -> [String] {
        let validFolderIDs = Set(folders.map(\.id))
        var result: [String] = []
        var seen: Set<String> = []

        func appendChannelID(from rawOrURL: String?) {
            guard let rawOrURL,
                  let cid = ChannelInboxClient.extractChannelID(from: rawOrURL),
                  seen.insert(cid).inserted else {
                return
            }
            result.append(cid)
        }

        switch filter {
        case .all:
            for pin in pins {
                appendChannelID(from: pin.urlString)
            }
            for stat in watchedChannels {
                appendChannelID(from: stat.channelURLString)
            }

        case .folder(let folderID):
            guard folders.isEmpty || validFolderIDs.contains(folderID) else {
                return []
            }
            for pin in pins where pin.folderID == folderID {
                appendChannelID(from: pin.urlString)
            }

        case .ungrouped:
            var folderChannelIDs: Set<String> = []
            for pin in pins {
                if let fid = pin.folderID, validFolderIDs.contains(fid) {
                    if let cid = ChannelInboxClient.extractChannelID(from: pin.urlString) {
                        folderChannelIDs.insert(cid)
                    }
                } else {
                    appendChannelID(from: pin.urlString)
                }
            }
            for stat in watchedChannels {
                if let urlString = stat.channelURLString,
                   let cid = ChannelInboxClient.extractChannelID(from: urlString),
                   !folderChannelIDs.contains(cid),
                   seen.insert(cid).inserted {
                    result.append(cid)
                }
            }
        }

        return result
    }

    public static func filterEntries(
        _ entries: [ChannelInboxEntry],
        watchedVideoIDs: Set<String>,
        hideWatched: Bool
    ) -> [ChannelInboxEntry] {
        guard hideWatched, !watchedVideoIDs.isEmpty else {
            return entries
        }
        return entries.filter { !watchedVideoIDs.contains($0.videoID) }
    }
}

/// Cookieless ephemeral Atom RSS client for YouTube channel upload feeds (`youtube.com/feeds/videos.xml`).
/// Strictly opt-in; never touches cookies, auth headers, or WebKit state.
public actor ChannelInboxClient {
    private let session: URLSession

    public init(timeoutInterval: TimeInterval = 8.0) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = max(timeoutInterval, 12.0)
        self.session = URLSession(configuration: config)
    }

    /// Builds a validated `https://www.youtube.com/feeds/videos.xml?channel_id=...` URL.
    public nonisolated static func feedURL(forChannelID channelID: String) -> URL? {
        let trimmed = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.count <= 64,
              trimmed.unicodeScalars.allSatisfy({ s in
                  (s.value >= 48 && s.value <= 57)
                      || (s.value >= 65 && s.value <= 90)
                      || (s.value >= 97 && s.value <= 122)
                      || s == "-" || s == "_"
              }) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/feeds/videos.xml"
        components.queryItems = [URLQueryItem(name: "channel_id", value: trimmed)]
        return components.url
    }

    /// Extracts a `UC...` YouTube channel ID from a `/channel/<id>` URL or raw channel ID string.
    public nonisolated static func extractChannelID(from rawOrURL: String) -> String? {
        let trimmed = rawOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("UC"), feedURL(forChannelID: trimmed) != nil {
            return trimmed
        }
        if let url = URL(string: trimmed),
           let host = url.host,
           YouTubeURLRouter.isYouTubeHost(host) {
            let segs = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if segs.count >= 2 && segs[0].lowercased() == "channel" {
                let candidate = segs[1]
                return feedURL(forChannelID: candidate) != nil ? candidate : nil
            }
        }
        return nil
    }

    /// Parses YouTube Atom XML payload cleanly, ignoring feed-level metadata outside `<entry>`.
    public nonisolated static func parseAtomFeed(
        from data: Data,
        channelID: String = "",
        limit: Int = 15
    ) -> [ChannelInboxEntry] {
        guard !data.isEmpty, limit > 0 else { return [] }
        // Strip disallowed XML 1.0 C0 control bytes (e.g. NUL) so adversarial/corrupt feeds don't abort parsing
        // while preserving UTF-8 multibyte sequences for AgentSecurity sanitization.
        let sanitizedXMLData: Data
        if data.contains(where: { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }) {
            sanitizedXMLData = Data(data.filter { $0 >= 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D })
        } else {
            sanitizedXMLData = data
        }
        let delegate = AtomFeedParserDelegate(defaultChannelID: channelID, limit: limit)
        let parser = XMLParser(data: sanitizedXMLData)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return delegate.entries
        }
        return delegate.entries
    }

    /// Fetches up to `limit` latest entries for a single YouTube channel ID.
    public func fetchEntries(channelID: String, limit: Int = 10) async -> [ChannelInboxEntry] {
        guard let url = Self.feedURL(forChannelID: channelID) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0
        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return []
            }
            return Self.parseAtomFeed(from: data, channelID: channelID, limit: limit)
        } catch {
            return []
        }
    }

    /// Fetches and merges feeds across multiple channel IDs with bounded concurrency (`<= 3`), sorted newest first.
    public func fetchMergedInbox(
        channelIDs: [String],
        maxConcurrent: Int = 3,
        perChannelLimit: Int = 8,
        totalLimit: Int = 30
    ) async -> [ChannelInboxEntry] {
        let deduped = Array(Set(channelIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !deduped.isEmpty, totalLimit > 0 else { return [] }
        let concurrencyLimit = min(max(1, maxConcurrent), 3)

        var collected: [ChannelInboxEntry] = []
        var nextIndex = 0

        await withTaskGroup(of: [ChannelInboxEntry].self) { group in
            let initialCount = min(concurrencyLimit, deduped.count)
            while nextIndex < initialCount {
                let cid = deduped[nextIndex]
                nextIndex += 1
                group.addTask {
                    await self.fetchEntries(channelID: cid, limit: perChannelLimit)
                }
            }

            while let batch = await group.next() {
                collected.append(contentsOf: batch)
                if nextIndex < deduped.count, !Task.isCancelled {
                    let cid = deduped[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await self.fetchEntries(channelID: cid, limit: perChannelLimit)
                    }
                }
            }
        }

        var seenIDs: Set<String> = []
        let unique = collected.filter { seenIDs.insert($0.videoID).inserted }
        let sorted = unique.sorted { lhs, rhs in
            let lDate = lhs.publishedAt ?? .distantPast
            let rDate = rhs.publishedAt ?? .distantPast
            if lDate != rDate {
                return lDate > rDate
            }
            return lhs.videoID < rhs.videoID
        }
        return Array(sorted.prefix(totalLimit))
    }
}

private final class AtomFeedParserDelegate: NSObject, XMLParserDelegate {
    private let defaultChannelID: String
    private let limit: Int
    var entries: [ChannelInboxEntry] = []

    private var inEntry = false
    private var inAuthor = false
    private var currentElement = ""
    private var buffer = ""

    private var videoID = ""
    private var title = ""
    private var channelName = ""
    private var channelID = ""
    private var publishedRaw = ""

    init(defaultChannelID: String, limit: Int) {
        self.defaultChannelID = defaultChannelID
        self.limit = limit
        self.channelID = defaultChannelID
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        buffer = ""

        if elementName == "entry" {
            inEntry = true
            inAuthor = false
            videoID = ""
            title = ""
            channelName = ""
            channelID = defaultChannelID
            publishedRaw = ""
        } else if inEntry && elementName == "author" {
            inAuthor = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        buffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            buffer = ""
            currentElement = ""
        }

        guard inEntry else { return }

        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "yt:videoId":
            if !trimmed.isEmpty { videoID = trimmed }
        case "yt:channelId":
            if !trimmed.isEmpty { channelID = trimmed }
        case "title":
            if !trimmed.isEmpty { title = trimmed }
        case "published":
            if !trimmed.isEmpty { publishedRaw = trimmed }
        case "name":
            if inAuthor && !trimmed.isEmpty {
                channelName = trimmed
            }
        case "author":
            inAuthor = false
        case "entry":
            inEntry = false
            inAuthor = false
            let cleanTitle = AgentSecurity.sanitizeWebText(title, maxLength: AgentSecurity.maxWebTitleLength).text
            let cleanChannel = AgentSecurity.sanitizeWebText(channelName, maxLength: AgentSecurity.maxChannelNameLength).text
            if !videoID.isEmpty && !cleanTitle.isEmpty {
                entries.append(
                    ChannelInboxEntry(
                        videoID: videoID,
                        title: cleanTitle,
                        channelName: cleanChannel,
                        channelID: channelID,
                        publishedAt: parseISO8601Date(publishedRaw)
                    )
                )
                if entries.count >= limit {
                    parser.abortParsing()
                }
            }
        default:
            break
        }
    }

    private func parseISO8601Date(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        if let fractional = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return fractional
        }
        return try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false))
    }
}
