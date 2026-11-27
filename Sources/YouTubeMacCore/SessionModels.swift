import Foundation

/// Persisted representation of an open tab for fast, lazy session restoration on launch.
public struct SavedTabSnapshot: Codable, Equatable, Sendable {
    public let urlString: String
    public let title: String
    public let routingMode: TabRoutingMode

    enum CodingKeys: String, CodingKey {
        case urlString
        case title
        case routingMode
    }

    public init(urlString: String, title: String, routingMode: TabRoutingMode = .youtube) {
        self.urlString = urlString
        self.title = title
        self.routingMode = routingMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urlString = try container.decode(String.self, forKey: .urlString)
        title = try container.decode(String.self, forKey: .title)
        routingMode = try container.decodeIfPresent(TabRoutingMode.self, forKey: .routingMode) ?? .youtube
    }

    public var url: URL? {
        URL(string: urlString)
    }
}

/// Persisted tab session snapshot.
public struct SavedSession: Codable, Equatable, Sendable {
    public let tabs: [SavedTabSnapshot]
    public let selectedIndex: Int

    public init(tabs: [SavedTabSnapshot], selectedIndex: Int) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex
    }
}

/// Filters transient auth/blank tabs, caps count at 20, and remaps `selectedIndex` safely for session restoration.
public enum SessionRestorationFilter {
    public static let maxRestoredTabs: Int = 20

    public static func sanitize(
        tabs: [SavedTabSnapshot],
        selectedIndex: Int
    ) -> SavedSession? {
        var sanitized: [SavedTabSnapshot] = []
        sanitized.reserveCapacity(min(tabs.count, maxRestoredTabs))
        var mappedSelectedIndex: Int?

        for (originalIndex, snapshot) in tabs.enumerated() {
            guard sanitized.count < maxRestoredTabs else { break }
            guard isRestorableURLString(snapshot.urlString, routingMode: snapshot.routingMode) else { continue }
            let cleanTitle = YouTubeTitleFormatter.clean(snapshot.title)
            let fallbackTitle = snapshot.routingMode == .companion
                ? (URL(string: snapshot.urlString)?.host ?? "Web")
                : "YouTube"
            let resolvedTitle = cleanTitle.isEmpty ? fallbackTitle : cleanTitle
            if originalIndex == selectedIndex {
                mappedSelectedIndex = sanitized.count
            }
            sanitized.append(
                SavedTabSnapshot(
                    urlString: snapshot.urlString,
                    title: resolvedTitle,
                    routingMode: snapshot.routingMode
                )
            )
        }

        guard !sanitized.isEmpty else {
            return nil
        }

        let finalIndex: Int
        if let mappedSelectedIndex {
            finalIndex = mappedSelectedIndex
        } else {
            finalIndex = min(max(0, selectedIndex), sanitized.count - 1)
        }
        return SavedSession(tabs: sanitized, selectedIndex: finalIndex)
    }

    public static func isRestorableURLString(
        _ urlString: String,
        routingMode: TabRoutingMode = .youtube
    ) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        if YouTubeURLRouter.isGoogleAuthHost(host) {
            return false
        }
        if StreamingServiceCatalog.isTransientAuthURL(url) {
            return false
        }
        if routingMode == .companion {
            return true
        }
        return YouTubeURLRouter.isYouTubeHost(host)
    }
}

/// Native macOS Sleep Timer presets supported across Playback menu, Menu Bar, and Dock menu.
public enum SleepTimerOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case minutes15
    case minutes30
    case minutes45
    case minutes60
    case endOfVideo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .minutes15: return "15 Minutes"
        case .minutes30: return "30 Minutes"
        case .minutes45: return "45 Minutes"
        case .minutes60: return "60 Minutes"
        case .endOfVideo: return "End of Current Video"
        }
    }

    public var shortTitle: String {
        switch self {
        case .minutes15: return "15m"
        case .minutes30: return "30m"
        case .minutes45: return "45m"
        case .minutes60: return "60m"
        case .endOfVideo: return "End of Video"
        }
    }

    public var durationSeconds: TimeInterval? {
        switch self {
        case .minutes15: return 15 * 60
        case .minutes30: return 30 * 60
        case .minutes45: return 45 * 60
        case .minutes60: return 60 * 60
        case .endOfVideo: return nil
        }
    }

    public static func formatRemaining(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds.rounded(.up)))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Per-tab navigation failure or WebContent process termination state for Liquid Glass recovery cards.
public struct TabLoadError: Equatable, Sendable {
    public let code: Int
    public let domain: String
    public let message: String
    public let isOffline: Bool
    public let isProcessCrash: Bool
    public let failingURLString: String?

    public init(
        code: Int,
        domain: String,
        message: String,
        isOffline: Bool,
        isProcessCrash: Bool = false,
        failingURLString: String? = nil
    ) {
        self.code = code
        self.domain = domain
        self.message = message
        self.isOffline = isOffline
        self.isProcessCrash = isProcessCrash
        self.failingURLString = failingURLString
    }

    public static func processTerminated(url: URL?) -> TabLoadError {
        TabLoadError(
            code: -1,
            domain: "WebKitProcess",
            message: "This YouTube page ran out of memory or stopped responding.",
            isOffline: false,
            isProcessCrash: true,
            failingURLString: url?.absoluteString
        )
    }

    public static func from(error: NSError, failingURL: URL?) -> TabLoadError {
        let offlineCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorTimedOut,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed
        ]
        let isOffline = error.domain == NSURLErrorDomain && offlineCodes.contains(error.code)
        let message: String
        if isOffline {
            message = "You appear to be offline or YouTube could not be reached."
        } else {
            message = error.localizedDescription
        }
        return TabLoadError(
            code: error.code,
            domain: error.domain,
            message: message,
            isOffline: isOffline,
            isProcessCrash: false,
            failingURLString: failingURL?.absoluteString
        )
    }
}

/// Snapshot of macOS CoreAudio default output routing (transport + active data source).
public struct AudioRouteSnapshot: Equatable, Sendable {
    public let deviceID: UInt32
    public let transportType: UInt32
    public let dataSource: UInt32

    // Standard CoreAudio FourCC constants (defined here so YouTubeMacCore stays Foundation-only & testable).
    public static let transportBuiltIn: UInt32 = 0x626C746E     // 'bltn'
    public static let transportBluetooth: UInt32 = 0x626C7565   // 'blue'
    public static let transportBluetoothLE: UInt32 = 0x626C6561 // 'blea'
    public static let transportUSB: UInt32 = 0x75736220         // 'usb '
    public static let transportAirPlay: UInt32 = 0x61697270     // 'airp'
    public static let transportHDMI: UInt32 = 0x68646D69        // 'hdmi'
    public static let transportDisplayPort: UInt32 = 0x64707274 // 'dprt'
    public static let transportThunderbolt: UInt32 = 0x7468756E // 'thun'
    public static let transportFireWire: UInt32 = 0x31333934    // '1394'

    public static let dataSourceHeadphones: UInt32 = 0x6864706E       // 'hdpn'
    public static let dataSourceInternalSpeakers: UInt32 = 0x6973706B // 'ispk'

    public init(deviceID: UInt32, transportType: UInt32, dataSource: UInt32 = 0) {
        self.deviceID = deviceID
        self.transportType = transportType
        self.dataSource = dataSource
    }

    public var isBuiltInInternalSpeakers: Bool {
        transportType == Self.transportBuiltIn && dataSource != Self.dataSourceHeadphones
    }

    public var isHeadphonesOrExternal: Bool {
        if transportType == Self.transportBuiltIn {
            return dataSource == Self.dataSourceHeadphones
        }
        return transportType != 0
    }
}

/// Pure policy deciding whether a CoreAudio output route transition represents unplugging headphones
/// or disconnecting Bluetooth/external audio onto built-in internal speakers.
public enum AudioOutputDisconnectDetector {
    public static func shouldAutoPause(
        from previous: AudioRouteSnapshot?,
        to current: AudioRouteSnapshot
    ) -> Bool {
        guard let previous else { return false }
        // Ignore duplicate/no-op notifications where neither device nor data source changed.
        guard previous.deviceID != current.deviceID || previous.dataSource != current.dataSource else {
            return false
        }

        // Case 1: Apple Silicon / Mac 3.5mm jack unplug on the shared built-in device ('hdpn' -> 'ispk').
        // On desktop Macs without a data source selector (dataSource == 0), do not falsely trigger.
        if previous.transportType == AudioRouteSnapshot.transportBuiltIn,
           current.transportType == AudioRouteSnapshot.transportBuiltIn {
            return previous.dataSource == AudioRouteSnapshot.dataSourceHeadphones
                && current.dataSource != AudioRouteSnapshot.dataSourceHeadphones
                && current.dataSource != 0
        }

        // Case 2: External device (AirPods/Bluetooth/USB/AirPlay/HDMI/etc.) dropped back to Built-In Speakers.
        return previous.isHeadphonesOrExternal && current.isBuiltInInternalSpeakers
    }
}

/// User-saved timestamped video or stream bookmark (`⌘⇧K`).
public struct VideoBookmark: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let videoID: String?
    public var urlString: String
    public var title: String
    public var channel: String
    public var note: String
    public var timestampSeconds: Double
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case videoID
        case urlString
        case title
        case channel
        case note
        case timestampSeconds
        case createdAt
    }

    public init(
        id: UUID = UUID(),
        videoID: String? = nil,
        urlString: String,
        title: String,
        channel: String = "",
        note: String = "",
        timestampSeconds: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.videoID = videoID
        self.urlString = urlString
        self.title = title
        self.channel = channel
        self.note = note
        self.timestampSeconds = timestampSeconds.isFinite && timestampSeconds >= 0 ? timestampSeconds : 0
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        videoID = try container.decodeIfPresent(String.self, forKey: .videoID)
        urlString = try container.decode(String.self, forKey: .urlString)
        title = try container.decode(String.self, forKey: .title)
        channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        let rawSeconds = try container.decodeIfPresent(Double.self, forKey: .timestampSeconds) ?? 0
        timestampSeconds = rawSeconds.isFinite && rawSeconds >= 0 ? rawSeconds : 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    public var formattedTimestamp: String {
        MediaState.formatTime(timestampSeconds)
    }

    public var url: URL? {
        guard let parsed = URL(string: urlString) else { return nil }
        if timestampSeconds >= 1 {
            return YouTubeURLRouter.urlWithTimestamp(parsed, seconds: timestampSeconds)
        }
        return parsed
    }
}

/// Individual user-defined content filter rule for hiding distracting channels or topic keywords on YouTube feeds.
public struct ContentFilterRule: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case keyword
        case channel
    }

    public let id: UUID
    public var kind: Kind
    public var pattern: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        pattern: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
    }
}

/// Opt-in YouTube feed content filter configuration (`isEnabled` defaults to `false`).
public struct ContentFilterConfig: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var blockedChannels: [String]
    public var blockedKeywords: [String]

    public static let empty = ContentFilterConfig()

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case blockedChannels
        case blockedKeywords
    }

    public init(
        isEnabled: Bool = false,
        blockedChannels: [String] = [],
        blockedKeywords: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.blockedChannels = blockedChannels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.blockedKeywords = blockedKeywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let channels = try container.decodeIfPresent([String].self, forKey: .blockedChannels) ?? []
        let keywords = try container.decodeIfPresent([String].self, forKey: .blockedKeywords) ?? []
        blockedChannels = channels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        blockedKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var effectiveBlockedChannels: [String] {
        isEnabled ? blockedChannels : []
    }

    public var effectiveBlockedKeywords: [String] {
        isEnabled ? blockedKeywords : []
    }

    /// Returns `true` when `isEnabled` is true and either `channel` or `title` matches any configured filter rule.
    public func matches(title: String, channel: String) -> Bool {
        guard isEnabled else { return false }
        let normChannel = channel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !normChannel.isEmpty {
            for blocked in blockedChannels {
                let needle = blocked.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !needle.isEmpty && (normChannel == needle || normChannel.contains(needle)) {
                    return true
                }
            }
        }
        if !normTitle.isEmpty {
            for keyword in blockedKeywords {
                let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !needle.isEmpty && normTitle.contains(needle) {
                    return true
                }
            }
        }
        return false
    }
}

public typealias ContentFilterRules = ContentFilterConfig
