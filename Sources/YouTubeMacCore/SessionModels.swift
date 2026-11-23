import Foundation

/// Persisted representation of an open tab for fast, lazy session restoration on launch.
public struct SavedTabSnapshot: Codable, Equatable, Sendable {
    public let urlString: String
    public let title: String

    public init(urlString: String, title: String) {
        self.urlString = urlString
        self.title = title
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
            guard isRestorableURLString(snapshot.urlString) else { continue }
            let cleanTitle = YouTubeTitleFormatter.clean(snapshot.title)
            let resolvedTitle = cleanTitle.isEmpty ? "YouTube" : cleanTitle
            if originalIndex == selectedIndex {
                mappedSelectedIndex = sanitized.count
            }
            sanitized.append(SavedTabSnapshot(urlString: snapshot.urlString, title: resolvedTitle))
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

    public static func isRestorableURLString(_ urlString: String) -> Bool {
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
