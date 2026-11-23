import Foundation

/// Represents a navigable chapter marker on a YouTube `/watch` video.
public struct VideoChapter: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let title: String
    public let startSeconds: Double

    public var id: String {
        "\(Int(startSeconds.rounded(.down)))-\(title)"
    }

    public var formattedStartTime: String {
        MediaState.formatTime(startSeconds)
    }

    public init(title: String, startSeconds: Double) {
        self.title = title
        self.startSeconds = max(0, startSeconds.isFinite ? startSeconds : 0)
    }
}

/// Pure parser & normalizer for YouTube structured player markers and video description timestamps.
public enum VideoChapterParser {
    /// Normalizes raw `(title, startSeconds)` chapter entries: filters invalid/empty items, deduplicates
    /// by integer second, sorts ascending, and returns `[]` unless at least 2 valid chapters exist.
    public static func normalize(_ rawEntries: [(title: String, startSeconds: Double)]) -> [VideoChapter] {
        var bySecond: [Int: VideoChapter] = [:]
        for entry in rawEntries {
            guard entry.startSeconds.isFinite, entry.startSeconds >= 0 else { continue }
            let cleanedTitle = entry.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-–—|:•· "))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedTitle.isEmpty else { continue }
            let secKey = Int(entry.startSeconds.rounded(.down))
            if bySecond[secKey] == nil {
                bySecond[secKey] = VideoChapter(title: cleanedTitle, startSeconds: Double(secKey))
            }
        }
        let sorted = bySecond.values.sorted { $0.startSeconds < $1.startSeconds }
        return sorted.count >= 2 ? sorted : []
    }

    /// Extracts chapters from a YouTube video description containing timestamp lines such as `0:00 Intro` or `1:05:22 Outro`.
    public static func parseFromDescription(_ description: String, maxDuration: Double? = nil) -> [VideoChapter] {
        guard !description.isEmpty else { return [] }
        var extracted: [(title: String, startSeconds: Double)] = []
        let lines = description.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let match = parseTimestampLine(line) {
                if let maxDuration, maxDuration.isFinite, maxDuration > 0, match.startSeconds >= maxDuration {
                    continue
                }
                extracted.append(match)
            }
        }
        return normalize(extracted)
    }

    /// Returns the currently playing chapter for `currentTime`, or `nil` if `chapters` is empty.
    public static func activeChapter(at currentTime: Double, in chapters: [VideoChapter]) -> VideoChapter? {
        guard !chapters.isEmpty, currentTime.isFinite, currentTime >= 0 else { return nil }
        var current: VideoChapter?
        for chapter in chapters {
            if chapter.startSeconds <= currentTime + 0.5 {
                current = chapter
            } else {
                break
            }
        }
        return current ?? chapters.first
    }

    private static func parseTimestampLine(_ line: String) -> (title: String, startSeconds: Double)? {
        // Scan for a leading or embedded timestamp token like 0:00, 12:34, or 1:02:03.
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2 else { return nil }

        // Prefer leading timestamp (most common YouTube chapter format: "0:00 Intro" or "(0:00) Intro")
        let firstToken = String(tokens[0]).trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
        if let seconds = parseTimestampToken(firstToken) {
            let remainder = tokens.dropFirst().joined(separator: " ")
            return (remainder, seconds)
        }

        // Also support trailing timestamp ("Intro - 0:00")
        let lastToken = String(tokens[tokens.count - 1]).trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
        if let seconds = parseTimestampToken(lastToken) {
            let remainder = tokens.dropLast().joined(separator: " ")
            return (remainder, seconds)
        }

        return nil
    }

    private static func parseTimestampToken(_ token: String) -> Double? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        if parts.count == 2 {
            guard parts[1].count == 2,
                  let minutes = Int(parts[0]),
                  let seconds = Int(parts[1]),
                  minutes >= 0, seconds >= 0, seconds < 60 else {
                return nil
            }
            return Double(minutes * 60 + seconds)
        } else {
            guard parts[1].count == 2,
                  parts[2].count == 2,
                  let hours = Int(parts[0]),
                  let minutes = Int(parts[1]),
                  let seconds = Int(parts[2]),
                  hours >= 0, minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else {
                return nil
            }
            return Double(hours * 3600 + minutes * 60 + seconds)
        }
    }
}
