import Foundation

/// Built-in YouTube destinations presented in the native macOS sidebar.
public enum SidebarDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case home
    case subscriptions
    case history
    case watchLater
    case likedVideos
    case playlists
    case shorts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Home"
        case .subscriptions: return "Subscriptions"
        case .history: return "History"
        case .watchLater: return "Watch Later"
        case .likedVideos: return "Liked Videos"
        case .playlists: return "Playlists"
        case .shorts: return "Shorts"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "house"
        case .subscriptions: return "rectangle.stack.badge.play"
        case .history: return "clock.arrow.circlepath"
        case .watchLater: return "clock"
        case .likedVideos: return "hand.thumbsup"
        case .playlists: return "list.bullet.rectangle"
        case .shorts: return "bolt.fill"
        }
    }

    public var url: URL {
        switch self {
        case .home:
            return URL(string: "https://www.youtube.com/")!
        case .subscriptions:
            return URL(string: "https://www.youtube.com/feed/subscriptions")!
        case .history:
            return URL(string: "https://www.youtube.com/feed/history")!
        case .watchLater:
            return URL(string: "https://www.youtube.com/playlist?list=WL")!
        case .likedVideos:
            return URL(string: "https://www.youtube.com/playlist?list=LL")!
        case .playlists:
            return URL(string: "https://www.youtube.com/feed/playlists")!
        case .shorts:
            return URL(string: "https://www.youtube.com/shorts")!
        }
    }

    /// Returns the matching sidebar destination for a given YouTube URL, if any.
    /// Explicitly returns `nil` on `tv.youtube.com` so Home Shelf overlays never cover YouTube TV.
    public static func matching(url: URL) -> SidebarDestination? {
        guard let host = url.host?.lowercased(),
              YouTubeURLRouter.isYouTubeHost(host),
              !YouTubeURLRouter.isYouTubeTVHost(host) else {
            return nil
        }

        let path = url.path.lowercased()
        if path == "/" || path.isEmpty {
            return .home
        }
        if path == "/feed/subscriptions" {
            return .subscriptions
        }
        if path == "/feed/history" {
            return .history
        }
        if path == "/feed/playlists" {
            return .playlists
        }
        if path == "/shorts" || path.hasPrefix("/shorts/") {
            return .shorts
        }
        if path == "/playlist",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let list = components.queryItems?.first(where: { $0.name == "list" })?.value {
            switch list {
            case "WL": return .watchLater
            case "LL": return .likedVideos
            default: return nil
            }
        }
        return nil
    }
}

/// Destination opened on launch and for new blank tabs.
public enum StartupDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case home
    case subscriptions
    case watchLater

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Home"
        case .subscriptions: return "Subscriptions"
        case .watchLater: return "Watch Later"
        }
    }

    public var url: URL {
        switch self {
        case .home: return SidebarDestination.home.url
        case .subscriptions: return SidebarDestination.subscriptions.url
        case .watchLater: return SidebarDestination.watchLater.url
        }
    }
}

/// Pure helper for merging YouTube's `PREF` cookie `f6` theme bits without disturbing other preferences.
public enum YouTubeThemeCookie {
    private static let darkBit: UInt64 = 0x400
    private static let lightBit: UInt64 = 0x80000
    private static let themeMask: UInt64 = darkBit | lightBit

    /// Merges the resolved theme bit (`0x400` for Night/Dark, `0x80000` for Day/Light) into YouTube's `PREF` cookie value
    /// while preserving all other key-value parameters (`tz`, `hl`, `f4`, `f7`, etc.) and all non-theme `f6` bits.
    public static func mergedPREFValue(
        _ existingValue: String?,
        appearance: AppAppearance,
        systemIsDark: Bool = false
    ) -> String {
        let effectiveDark: Bool
        switch appearance {
        case .dark:
            effectiveDark = true
        case .light:
            effectiveDark = false
        case .system:
            effectiveDark = systemIsDark
        }

        let raw = (existingValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.isEmpty ? [] : raw.split(separator: "&").map(String.init)

        var currentF6: UInt64 = 0
        var preservedParts: [String] = []
        for part in parts where !part.isEmpty {
            if part.hasPrefix("f6=") {
                let hexString = String(part.dropFirst(3))
                currentF6 = UInt64(hexString, radix: 16) ?? 0
            } else {
                preservedParts.append(part)
            }
        }

        let clearedF6 = currentF6 & ~themeMask
        let nextF6 = clearedF6 | (effectiveDark ? darkBit : lightBit)
        preservedParts.append("f6=\(String(nextF6, radix: 16))")
        return preservedParts.joined(separator: "&")
    }
}

/// Preferred macOS window and YouTube webpage appearance.
public enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Day (Light)"
        case .dark: return "Night (Dark)"
        }
    }
}

/// Preferred YouTube playback video quality tier.
public enum PreferredVideoQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    case uhd2160
    case qhd1440
    case fhd1080
    case hd720

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto (YouTube Default)"
        case .uhd2160: return "4K (2160p)"
        case .qhd1440: return "1440p (QHD)"
        case .fhd1080: return "1080p (HD)"
        case .hd720: return "720p"
        }
    }

    /// Corresponding YouTube `movie_player` quality identifier, or empty string for Auto.
    public var youtubeQualityLevel: String {
        switch self {
        case .auto: return ""
        case .uhd2160: return "hd2160"
        case .qhd1440: return "hd1440"
        case .fhd1080: return "hd1080"
        case .hd720: return "hd720"
        }
    }

    private var resolutionRank: Int {
        switch self {
        case .auto: return 4
        case .uhd2160: return 4
        case .qhd1440: return 3
        case .fhd1080: return 2
        case .hd720: return 1
        }
    }

    /// Computes the adaptive Multiview quality ceiling (including when user preference is `.auto`)
    /// so 2–4 concurrent streams stay smoothly hardware-decoded without exhausting VideoToolbox.
    public static func clampedForMultiview(
        userPreference: PreferredVideoQuality,
        isPrimaryOrTwoUp: Bool,
        ceilingOverride: MultiviewQualityCeiling = .auto
    ) -> PreferredVideoQuality {
        let ceiling: PreferredVideoQuality
        switch ceilingOverride {
        case .auto:
            ceiling = isPrimaryOrTwoUp ? .fhd1080 : .hd720
        case .uhd2160:
            // Allow full 4K ABR when user explicitly chooses Up to 4K ceiling
            if userPreference == .auto {
                return .auto
            }
            return userPreference
        case .fhd1080:
            ceiling = .fhd1080
        case .hd720:
            ceiling = .hd720
        }

        if userPreference == .auto {
            return ceiling
        }
        return userPreference.resolutionRank <= ceiling.resolutionRank ? userPreference : ceiling
    }
}

/// User-configurable maximum resolution ceiling applied to tiles while Native Multiview is active.
public enum MultiviewQualityCeiling: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    case uhd2160
    case fhd1080
    case hd720

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto (1080p Main / 720p Secondary)"
        case .uhd2160: return "Up to 4K (2160p)"
        case .fhd1080: return "Up to 1080p (HD)"
        case .hd720: return "Up to 720p (Battery Saver)"
        }
    }
}

/// A single SponsorBlock skip segment interval in seconds.
public struct SponsorSegment: Equatable, Codable, Sendable {
    public let start: Double
    public let end: Double
    public let category: String

    public init(start: Double, end: Double, category: String = "sponsor") {
        self.start = start
        self.end = end
        self.category = category
    }
}

/// Recently watched video persisted for the native Continue Watching shelf.
public struct ContinueWatchingItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String { videoID }
    public let videoID: String
    public var title: String
    public var channel: String
    public var currentTime: Double
    public var duration: Double
    public var lastWatchedAt: Date

    public init(
        videoID: String,
        title: String,
        channel: String,
        currentTime: Double,
        duration: Double,
        lastWatchedAt: Date = Date()
    ) {
        self.videoID = videoID
        self.title = title
        self.channel = channel
        self.currentTime = currentTime
        self.duration = duration
        self.lastWatchedAt = lastWatchedAt
    }

    public var progressFraction: Double {
        guard duration.isFinite, duration > 0, currentTime.isFinite, currentTime >= 0 else {
            return 0
        }
        return min(max(currentTime / duration, 0), 1)
    }

    public var remainingTimeText: String {
        guard duration.isFinite, duration > 0, currentTime.isFinite else {
            return ""
        }
        let remaining = max(0, duration - currentTime)
        return "\(MediaState.formatTime(remaining)) left"
    }

    public var thumbnailURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }

    public var resumeURL: URL? {
        let secs = max(0, Int(currentTime.rounded(.down)))
        if secs >= 1 {
            return URL(string: "https://www.youtube.com/watch?v=\(videoID)&t=\(secs)s")
        }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }
}

/// Locally tracked channel watch frequency powering the Most Watched Channels strip.
public struct WatchedChannelStat: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var channelURLString: String?
    public var watchCount: Int
    public var lastWatchedAt: Date

    public init(
        name: String,
        channelURLString: String? = nil,
        watchCount: Int = 1,
        lastWatchedAt: Date = Date()
    ) {
        self.id = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.channelURLString = channelURLString
        self.watchCount = watchCount
        self.lastWatchedAt = lastWatchedAt
    }

    public var url: URL? {
        if let channelURLString, let parsed = URL(string: channelURLString), !channelURLString.isEmpty {
            return parsed
        }
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: name)]
        return components.url
    }
}

/// Discovery topic filter for the populated Home Screen.
public enum SuggestedTopic: String, CaseIterable, Identifiable, Sendable {
    case all
    case hdr4k
    case tech
    case science
    case cinema
    case music

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "For You"
        case .hdr4k: return "4K & HDR"
        case .tech: return "Tech"
        case .science: return "Science"
        case .cinema: return "Cinema"
        case .music: return "Music"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "sparkles"
        case .hdr4k: return "4k.tv"
        case .tech: return "cpu"
        case .science: return "atom"
        case .cinema: return "film"
        case .music: return "music.note"
        }
    }
}

/// Curated discovery video item shown when YouTube's signed-out or paused-history Home feed returns 0 videos.
public struct SuggestedVideoItem: Identifiable, Hashable, Sendable {
    public var id: String { videoID }
    public let videoID: String
    public let title: String
    public let channel: String
    public let topic: SuggestedTopic
    public let durationText: String

    public init(videoID: String, title: String, channel: String, topic: SuggestedTopic, durationText: String) {
        self.videoID = videoID
        self.title = title
        self.channel = channel
        self.topic = topic
        self.durationText = durationText
    }

    public var thumbnailURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }

    public var watchURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    public static let curatedCatalog: [SuggestedVideoItem] = [
        SuggestedVideoItem(videoID: "LXb3EKWsInQ", title: "COSTA RICA IN 4K 60fps HDR (ULTRA HD)", channel: "Jacob + Katie Schwarz", topic: .hdr4k, durationText: "5:14"),
        SuggestedVideoItem(videoID: "aqz-KE-bpKQ", title: "Big Buck Bunny 60fps 4K - Official Blender Open Movie", channel: "Blender", topic: .cinema, durationText: "10:35"),
        SuggestedVideoItem(videoID: "aircAruvnKk", title: "But what is a neural network? | Deep learning", channel: "3Blue1Brown", topic: .science, durationText: "19:13"),
        SuggestedVideoItem(videoID: "MnrJzXM7a6o", title: "Steve Jobs introduces iPhone in 2007", channel: "John Schroter", topic: .tech, durationText: "10:20"),
        SuggestedVideoItem(videoID: "tO01J-M3g0U", title: "The World in HDR in 4K (ULTRA HD)", channel: "Jacob + Katie Schwarz", topic: .hdr4k, durationText: "3:12"),
        SuggestedVideoItem(videoID: "ysz5S6PUM-U", title: "NASA 4K: Thermonuclear Art - The Sun in Ultra-HD", channel: "NASA Goddard", topic: .science, durationText: "30:07"),
        SuggestedVideoItem(videoID: "6stlCkUDG_s", title: "4K HDR 60fps Dolby Vision Underwater Demo", channel: "8K World", topic: .hdr4k, durationText: "4:22"),
        SuggestedVideoItem(videoID: "spUNpyF58BY", title: "But what is the Fourier Transform? A visual introduction", channel: "3Blue1Brown", topic: .science, durationText: "20:57"),
        SuggestedVideoItem(videoID: "R6MlUcmOul8", title: "Tears of Steel - Blender Open Movie 4K", channel: "Blender", topic: .cinema, durationText: "12:14"),
        SuggestedVideoItem(videoID: "pQN-pnXPaVg", title: "HTML Full Course - Build a Website Tutorial", channel: "freeCodeCamp.org", topic: .tech, durationText: "2:02:32"),
        SuggestedVideoItem(videoID: "kXYiU_JCYtU", title: "Numb (Official Music Video) [4K Upgrade]", channel: "Linkin Park", topic: .music, durationText: "3:08"),
        SuggestedVideoItem(videoID: "eRsGyueVLvQ", title: "Sintel - Open Movie by Blender Foundation", channel: "Blender", topic: .cinema, durationText: "14:48"),
        SuggestedVideoItem(videoID: "rfscVS0vtbw", title: "Learn Python - Full Course for Beginners", channel: "freeCodeCamp.org", topic: .tech, durationText: "4:26:52"),
        SuggestedVideoItem(videoID: "fLexgOxsZu0", title: "Uptown Funk (Official Video)", channel: "Mark Ronson", topic: .music, durationText: "4:31"),
        SuggestedVideoItem(videoID: "e-ORhEE9VVg", title: "Blank Space", channel: "Taylor Swift", topic: .music, durationText: "4:33")
    ]
}

/// Pure, unit-testable state transitions for Continue Watching and Most Watched Channels.
public enum ContinueWatchingStore {
    /// Updates or inserts a Continue Watching item, removing completed videos (`>= 95%` watched) and ignoring very short snippets.
    public static func upsert(
        videoID: String,
        title: String,
        channel: String,
        currentTime: Double,
        duration: Double,
        now: Date = Date(),
        into items: [ContinueWatchingItem],
        maxCount: Int = 12
    ) -> [ContinueWatchingItem] {
        guard !videoID.isEmpty,
              duration.isFinite, duration >= 15,
              currentTime.isFinite else {
            return items
        }

        let progress = min(max(currentTime / duration, 0), 1)
        let remaining = max(0, duration - currentTime)
        let isCompleted = progress >= 0.95 || (duration >= 30 && remaining < 10)

        var updated = items.filter { $0.videoID != videoID }
        if isCompleted || currentTime < 3 {
            return updated
        }

        let cleanTitle = YouTubeTitleFormatter.clean(title)
        let displayTitle = cleanTitle.isEmpty ? "YouTube Video" : cleanTitle
        let item = ContinueWatchingItem(
            videoID: videoID,
            title: displayTitle,
            channel: channel.trimmingCharacters(in: .whitespacesAndNewlines),
            currentTime: currentTime,
            duration: duration,
            lastWatchedAt: now
        )
        updated.insert(item, at: 0)
        if updated.count > maxCount {
            updated = Array(updated.prefix(maxCount))
        }
        return updated
    }

    /// Increments watch count for a channel and keeps channels sorted by watch count then recency.
    public static func recordChannel(
        name: String,
        urlString: String?,
        now: Date = Date(),
        into stats: [WatchedChannelStat],
        maxCount: Int = 16
    ) -> [WatchedChannelStat] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return stats }
        let key = trimmed.lowercased()

        var updated = stats
        if let idx = updated.firstIndex(where: { $0.id == key }) {
            updated[idx].watchCount += 1
            updated[idx].lastWatchedAt = now
            if let urlString, !urlString.isEmpty {
                updated[idx].channelURLString = urlString
            }
        } else {
            updated.append(WatchedChannelStat(name: trimmed, channelURLString: urlString, watchCount: 1, lastWatchedAt: now))
        }

        updated.sort { lhs, rhs in
            if lhs.watchCount != rhs.watchCount {
                return lhs.watchCount > rhs.watchCount
            }
            return lhs.lastWatchedAt > rhs.lastWatchedAt
        }
        if updated.count > maxCount {
            updated = Array(updated.prefix(maxCount))
        }
        return updated
    }
}

/// User-pinned YouTube channel, playlist, or video shown in the sidebar.
public struct PinnedItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var urlString: String
    public var addedAt: Date

    public init(id: UUID = UUID(), title: String, urlString: String, addedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.addedAt = addedAt
    }

    public var url: URL? {
        URL(string: urlString)
    }
}

/// Formats raw YouTube page titles by stripping unread notification counts like "(76) " and trailing " - YouTube".
public enum YouTubeTitleFormatter {
    public static func clean(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("("), let closeIdx = result.firstIndex(of: ")") {
            let inside = result[result.index(after: result.startIndex)..<closeIdx]
            if !inside.isEmpty && inside.allSatisfy(\.isNumber) {
                let afterClose = result.index(after: closeIdx)
                result = String(result[afterClose...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if result.hasSuffix(" - YouTube TV") {
            result = String(result.dropLast(" - YouTube TV".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if result.lowercased().hasSuffix(" - youtube tv") {
            result = String(result.dropLast(13)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if result.hasSuffix(" - YouTube") {
            result = String(result.dropLast(" - YouTube".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if result.lowercased().hasSuffix(" - youtube") {
            result = String(result.dropLast(10)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}

/// Low-frequency playback status reported to UI controls without triggering per-second timeline churn.
public struct MediaStatus: Equatable, Sendable {
    public var hasVideo: Bool
    public var isPlaying: Bool
    public var title: String
    public var channel: String
    public var channelURLString: String
    public var urlString: String
    public var isMuted: Bool
    public var isPiP: Bool
    public var isTheater: Bool
    public var isHDR: Bool
    public var playbackRate: Double
    public var isHomeFeedEmpty: Bool

    public static let empty = MediaStatus(
        hasVideo: false,
        isPlaying: false,
        title: "",
        channel: "",
        channelURLString: "",
        urlString: "",
        isMuted: false,
        isPiP: false,
        isTheater: false,
        isHDR: false,
        playbackRate: 1.0,
        isHomeFeedEmpty: false
    )

    public init(
        hasVideo: Bool,
        isPlaying: Bool,
        title: String,
        channel: String,
        channelURLString: String = "",
        urlString: String,
        isMuted: Bool,
        isPiP: Bool,
        isTheater: Bool,
        isHDR: Bool = false,
        playbackRate: Double = 1.0,
        isHomeFeedEmpty: Bool = false
    ) {
        self.hasVideo = hasVideo
        self.isPlaying = isPlaying
        self.title = title
        self.channel = channel
        self.channelURLString = channelURLString
        self.urlString = urlString
        self.isMuted = isMuted
        self.isPiP = isPiP
        self.isTheater = isTheater
        self.isHDR = isHDR
        self.playbackRate = playbackRate.isFinite && playbackRate > 0 ? playbackRate : 1.0
        self.isHomeFeedEmpty = isHomeFeedEmpty
    }

    /// Compact speed badge string (e.g. `"1.5×"`), or `nil` when playing at normal `1×` speed.
    public var formattedPlaybackRate: String? {
        guard hasVideo, abs(playbackRate - 1.0) >= 0.01 else {
            return nil
        }
        return Self.formatPlaybackRate(playbackRate)
    }

    public static func formatPlaybackRate(_ rate: Double) -> String {
        let clamped = min(max(rate.isFinite ? rate : 1.0, 0.25), 4.0)
        let rounded = (clamped * 100).rounded() / 100
        if abs(rounded.rounded() - rounded) < 0.005 {
            return "\(Int(rounded.rounded()))×"
        }
        if abs((rounded * 10).rounded() - rounded * 10) < 0.05 {
            return String(format: "%.1f×", rounded)
        }
        return String(format: "%.2f×", rounded)
    }
}

/// Snapshot of active HTML5 video playback reported by the page script bridge.
public struct MediaState: Equatable, Sendable {
    public var hasVideo: Bool
    public var isPlaying: Bool
    public var title: String
    public var channel: String
    public var urlString: String
    public var currentTime: Double
    public var duration: Double
    public var isMuted: Bool
    public var isPiP: Bool
    public var isTheater: Bool

    public static let empty = MediaState(
        hasVideo: false,
        isPlaying: false,
        title: "",
        channel: "",
        urlString: "",
        currentTime: 0,
        duration: 0,
        isMuted: false,
        isPiP: false,
        isTheater: false
    )

    public init(
        hasVideo: Bool,
        isPlaying: Bool,
        title: String,
        channel: String,
        urlString: String,
        currentTime: Double,
        duration: Double,
        isMuted: Bool,
        isPiP: Bool,
        isTheater: Bool
    ) {
        self.hasVideo = hasVideo
        self.isPlaying = isPlaying
        self.title = title
        self.channel = channel
        self.urlString = urlString
        self.currentTime = currentTime
        self.duration = duration
        self.isMuted = isMuted
        self.isPiP = isPiP
        self.isTheater = isTheater
    }

    public var progressFraction: Double {
        guard duration.isFinite, duration > 0, currentTime.isFinite, currentTime >= 0 else {
            return 0
        }
        return min(max(currentTime / duration, 0), 1)
    }

    /// Formats playback timestamps as `M:SS` or `H:MM:SS`, clamping invalid values to `0:00`.
    public static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Configuration snapshot synced to the injected YouTube distraction-free & playback script.
public struct DistractionFreeConfig: Equatable, Sendable {
    public var hideShorts: Bool
    public var redirectShortsToWatch: Bool
    public var cleanWebChrome: Bool
    public var hideWebHeader: Bool
    public var autoTheaterMode: Bool
    public var hideEndScreens: Bool
    public var hideWatchRecommendations: Bool
    public var hideComments: Bool
    public var hideHomeFeed: Bool
    public var disableAmbientMode: Bool
    public var autoDismissContinueWatching: Bool
    public var preferOriginalAudio: Bool
    public var preferredQuality: PreferredVideoQuality
    public var defaultPlaybackRate: Double
    public var sponsorBlockEnabled: Bool
    public var appearance: AppAppearance
    public var focusModeActive: Bool
    public var miniPlayerActive: Bool
    public var multiviewTileActive: Bool

    public init(
        hideShorts: Bool = true,
        redirectShortsToWatch: Bool = true,
        cleanWebChrome: Bool = true,
        hideWebHeader: Bool = false,
        autoTheaterMode: Bool = true,
        hideEndScreens: Bool = true,
        hideWatchRecommendations: Bool = false,
        hideComments: Bool = false,
        hideHomeFeed: Bool = false,
        disableAmbientMode: Bool = true,
        autoDismissContinueWatching: Bool = true,
        preferOriginalAudio: Bool = true,
        preferredQuality: PreferredVideoQuality = .auto,
        defaultPlaybackRate: Double = 1.0,
        sponsorBlockEnabled: Bool = false,
        appearance: AppAppearance = .system,
        focusModeActive: Bool = false,
        miniPlayerActive: Bool = false,
        multiviewTileActive: Bool = false
    ) {
        self.hideShorts = hideShorts
        self.redirectShortsToWatch = redirectShortsToWatch
        self.cleanWebChrome = cleanWebChrome
        self.hideWebHeader = hideWebHeader
        self.autoTheaterMode = autoTheaterMode
        self.hideEndScreens = hideEndScreens
        self.hideWatchRecommendations = hideWatchRecommendations
        self.hideComments = hideComments
        self.hideHomeFeed = hideHomeFeed
        self.disableAmbientMode = disableAmbientMode
        self.autoDismissContinueWatching = autoDismissContinueWatching
        self.preferOriginalAudio = preferOriginalAudio
        self.preferredQuality = preferredQuality
        self.defaultPlaybackRate = min(max(defaultPlaybackRate.isFinite ? defaultPlaybackRate : 1.0, 0.25), 4.0)
        self.sponsorBlockEnabled = sponsorBlockEnabled
        self.appearance = appearance
        self.focusModeActive = focusModeActive
        self.miniPlayerActive = miniPlayerActive
        self.multiviewTileActive = multiviewTileActive
    }

    public var effectiveTilePlayerActive: Bool {
        miniPlayerActive || multiviewTileActive
    }

    public var effectiveHideWatchRecommendations: Bool {
        hideWatchRecommendations || focusModeActive
    }

    public var effectiveHideComments: Bool {
        hideComments || focusModeActive
    }
}
