import Foundation

/// A single timestamped caption/transcript cue extracted on demand from a YouTube watch page.
public struct TranscriptCue: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: Int
    public let startSeconds: Double
    public let durationSeconds: Double
    public let text: String

    public init(
        id: Int,
        startSeconds: Double,
        durationSeconds: Double = 0,
        text: String
    ) {
        self.id = id
        self.startSeconds = startSeconds.isFinite && startSeconds >= 0 ? startSeconds : 0
        self.durationSeconds = durationSeconds.isFinite && durationSeconds >= 0 ? durationSeconds : 0
        self.text = text
    }

    public var formattedTimestamp: String {
        MediaState.formatTime(startSeconds)
    }
}

/// On-demand YouTube video transcript container tagged explicitly as untrusted web content and bounded to <= 1000 cues.
public struct YouTubeTranscript: Equatable, Hashable, Codable, Sendable {
    public static let maxCues = 1000
    public static let maxCueTextLength = 400
    public static let maxTotalBytes = 65_536

    public let videoID: String
    public let title: String
    public let languageCode: String
    public let source: String
    public let contentTrust: String
    public let cues: [TranscriptCue]

    public init(
        videoID: String,
        title: String,
        languageCode: String = "",
        source: String = "on_demand",
        contentTrust: String = AgentSecurity.untrustedWebContentTag,
        cues: [TranscriptCue]
    ) {
        self.videoID = videoID
        self.title = AgentSecurity.sanitizeWebText(title, maxLength: AgentSecurity.maxWebTitleLength).text
        self.languageCode = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.contentTrust = contentTrust
        self.cues = Array(cues.prefix(Self.maxCues))
    }

    /// Returns cues matching `query` (case-insensitive substring), or all cues when `query` is empty.
    public func matching(query: String) -> [TranscriptCue] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cues }
        return cues.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Builds timestamped plain text capped safely within `maxTotalBytes`.
    public func formattedPlainText(maxCues limit: Int = YouTubeTranscript.maxCues) -> String {
        var lines: [String] = []
        var totalBytes = 0
        for cue in cues.prefix(min(limit, Self.maxCues)) {
            let line = "[\(cue.formattedTimestamp)] \(cue.text)"
            let lineBytes = line.utf8.count + 1
            if totalBytes + lineBytes > Self.maxTotalBytes {
                break
            }
            lines.append(line)
            totalBytes += lineBytes
        }
        return lines.joined(separator: "\n")
    }

    /// Builds a sanitized, bounded `YouTubeTranscript` from raw `(startSeconds, durationSeconds, text)` tuples.
    public static func fromRawSegments(
        _ rawSegments: [(startSeconds: Double, durationSeconds: Double, text: String)],
        videoID: String,
        title: String = "",
        languageCode: String = "",
        source: String = "on_demand"
    ) -> YouTubeTranscript {
        var cues: [TranscriptCue] = []
        cues.reserveCapacity(min(rawSegments.count, maxCues))
        var cumulativeBytes = 0

        for seg in rawSegments {
            guard cues.count < maxCues else { break }
            let collapsed = seg.text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clean = AgentSecurity.sanitizeWebText(collapsed, maxLength: maxCueTextLength).text
            guard !clean.isEmpty else { continue }
            let cueBytes = clean.utf8.count
            if cumulativeBytes + cueBytes > maxTotalBytes {
                break
            }
            cumulativeBytes += cueBytes
            cues.append(
                TranscriptCue(
                    id: cues.count,
                    startSeconds: seg.startSeconds,
                    durationSeconds: seg.durationSeconds,
                    text: clean
                )
            )
        }

        return YouTubeTranscript(
            videoID: videoID,
            title: title,
            languageCode: languageCode,
            source: source,
            contentTrust: AgentSecurity.untrustedWebContentTag,
            cues: cues
        )
    }

    /// Parses YouTube `timedtext` `fmt=json3` payload into a bounded `YouTubeTranscript`.
    public static func parseJSON3(
        from data: Data,
        videoID: String,
        title: String = "",
        languageCode: String = ""
    ) -> YouTubeTranscript? {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            return nil
        }

        var rawSegments: [(Double, Double, String)] = []
        for event in events {
            guard let tStartMs = (event["tStartMs"] as? NSNumber)?.doubleValue else { continue }
            let dDurationMs = (event["dDurationMs"] as? NSNumber)?.doubleValue ?? 0
            guard let segs = event["segs"] as? [[String: Any]] else { continue }
            let text = segs.compactMap { $0["utf8"] as? String }.joined()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            rawSegments.append((max(0, tStartMs / 1000.0), max(0, dDurationMs / 1000.0), trimmed))
            if rawSegments.count >= maxCues {
                break
            }
        }

        guard !rawSegments.isEmpty else { return nil }
        return fromRawSegments(
            rawSegments,
            videoID: videoID,
            title: title,
            languageCode: languageCode,
            source: "json3"
        )
    }

    /// Parses legacy YouTube `timedtext` XML (`<transcript><text start="..." dur="...">...</text></transcript>`).
    public static func parseTimedTextXML(
        from data: Data,
        videoID: String,
        title: String = "",
        languageCode: String = ""
    ) -> YouTubeTranscript? {
        guard !data.isEmpty else { return nil }
        let delegate = TimedTextXMLParserDelegate(maxCues: maxCues)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        _ = parser.parse()
        guard !delegate.segments.isEmpty else { return nil }
        return fromRawSegments(
            delegate.segments,
            videoID: videoID,
            title: title,
            languageCode: languageCode,
            source: "timedtext_xml"
        )
    }
}

private final class TimedTextXMLParserDelegate: NSObject, XMLParserDelegate {
    private let maxCues: Int
    var segments: [(Double, Double, String)] = []
    private var inText = false
    private var currentStart: Double = 0
    private var currentDur: Double = 0
    private var buffer = ""

    init(maxCues: Int) {
        self.maxCues = maxCues
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "text" {
            inText = true
            buffer = ""
            currentStart = Double(attributeDict["start"] ?? "0") ?? 0
            currentDur = Double(attributeDict["dur"] ?? "0") ?? 0
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inText else { return }
        buffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "text", inText else { return }
        inText = false
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        if !trimmed.isEmpty {
            segments.append((max(0, currentStart), max(0, currentDur), trimmed))
            if segments.count >= maxCues {
                parser.abortParsing()
            }
        }
    }
}
