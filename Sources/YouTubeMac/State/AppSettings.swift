import AppKit
import Foundation
import Observation
import SwiftUI
import YouTubeMacCore

/// Persistent user preferences for distraction-free behavior, playback quality-of-life, windowing, and pinned destinations.
@MainActor
@Observable
public final class AppSettings {
    private enum Keys {
        static let hideShorts = "ytmac.hideShorts"
        static let redirectShortsToWatch = "ytmac.redirectShortsToWatch"
        static let cleanWebChrome = "ytmac.cleanWebChrome"
        static let hideWebHeader = "ytmac.hideWebHeader"
        static let autoTheaterMode = "ytmac.autoTheaterMode"
        static let hideEndScreens = "ytmac.hideEndScreens"
        static let hideWatchRecommendations = "ytmac.hideWatchRecommendations"
        static let hideComments = "ytmac.hideComments"
        static let hideHomeFeed = "ytmac.hideHomeFeed"
        static let disableAmbientMode = "ytmac.disableAmbientMode"
        static let autoDismissContinueWatching = "ytmac.autoDismissContinueWatching"
        static let preferOriginalAudio = "ytmac.preferOriginalAudio"
        static let preferredQuality = "ytmac.preferredQuality"
        static let defaultPlaybackRate = "ytmac.defaultPlaybackRate"
        static let sponsorBlockEnabled = "ytmac.sponsorBlockEnabled"
        static let openExternalLinksInBrowser = "ytmac.openExternalLinksInBrowser"
        static let alwaysShowTabBar = "ytmac.alwaysShowTabBar"
        static let miniPlayerAllSpaces = "ytmac.miniPlayerAllSpaces"
        static let autoMiniPlayerOnLeave = "ytmac.autoMiniPlayerOnLeave"
        static let showMenuBarControls = "ytmac.showMenuBarControls"
        static let isSidebarVisible = "ytmac.isSidebarVisible"
        static let showHomeShelf = "ytmac.showHomeShelf"
        static let savedMiniPlayerFrame = "ytmac.savedMiniPlayerFrame"
        static let startupDestination = "ytmac.startupDestination"
        static let appearance = "ytmac.appearance"
        static let pinnedItems = "ytmac.pinnedItems"
        static let pinnedFolders = "ytmac.pinnedFolders"
        static let continueWatching = "ytmac.continueWatching"
        static let watchedChannels = "ytmac.watchedChannels"
        static let restoreTabsOnLaunch = "ytmac.restoreTabsOnLaunch"
        static let autoPauseOnSystemEvents = "ytmac.autoPauseOnSystemEvents"
        static let savedSession = "ytmac.savedSession"
        static let searchAutocompleteEnabled = "ytmac.searchAutocompleteEnabled"
        static let savedMultiviewPresets = "ytmac.savedMultiviewPresets"
        static let multiviewQualityCeiling = "ytmac.multiviewQualityCeiling"
        static let multiviewAudioDuckingEnabled = "ytmac.multiviewAudioDuckingEnabled"
        static let automaticallyChecksForUpdates = "ytmac.automaticallyChecksForUpdates"
        static let hasCompletedStreamingOnboarding = "ytmac.hasCompletedStreamingOnboarding"
        static let enabledStreamingServiceIDs = "ytmac.enabledStreamingServiceIDs"
        static let signedInStreamingServiceIDs = "ytmac.signedInStreamingServiceIDs"
        static let miniPlayerOpacity = "ytmac.miniPlayerOpacity"
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    var onWebConfigDidChange: (() -> Void)?

    @ObservationIgnored
    var onWindowPreferencesDidChange: (() -> Void)?

    @ObservationIgnored
    var onAppearanceDidChange: (() -> Void)?

    @ObservationIgnored
    var onSponsorBlockSettingDidChange: ((Bool) -> Void)?

    @ObservationIgnored
    var onSystemPlaybackGuardSettingDidChange: ((Bool) -> Void)?

    @ObservationIgnored
    var onMultiviewAudioDuckingDidChange: ((Bool) -> Void)?

    @ObservationIgnored
    var onMiniPlayerOpacityDidChange: ((Double) -> Void)?

    public var hideShorts: Bool {
        didSet {
            guard hideShorts != oldValue else { return }
            defaults.set(hideShorts, forKey: Keys.hideShorts)
            onWebConfigDidChange?()
        }
    }

    public var redirectShortsToWatch: Bool {
        didSet {
            guard redirectShortsToWatch != oldValue else { return }
            defaults.set(redirectShortsToWatch, forKey: Keys.redirectShortsToWatch)
            onWebConfigDidChange?()
        }
    }

    public var cleanWebChrome: Bool {
        didSet {
            guard cleanWebChrome != oldValue else { return }
            defaults.set(cleanWebChrome, forKey: Keys.cleanWebChrome)
            onWebConfigDidChange?()
        }
    }

    public var hideWebHeader: Bool {
        didSet {
            guard hideWebHeader != oldValue else { return }
            defaults.set(hideWebHeader, forKey: Keys.hideWebHeader)
            onWebConfigDidChange?()
        }
    }

    public var autoTheaterMode: Bool {
        didSet {
            guard autoTheaterMode != oldValue else { return }
            defaults.set(autoTheaterMode, forKey: Keys.autoTheaterMode)
            onWebConfigDidChange?()
        }
    }

    public var hideEndScreens: Bool {
        didSet {
            guard hideEndScreens != oldValue else { return }
            defaults.set(hideEndScreens, forKey: Keys.hideEndScreens)
            onWebConfigDidChange?()
        }
    }

    public var hideWatchRecommendations: Bool {
        didSet {
            guard hideWatchRecommendations != oldValue else { return }
            defaults.set(hideWatchRecommendations, forKey: Keys.hideWatchRecommendations)
            onWebConfigDidChange?()
        }
    }

    public var hideComments: Bool {
        didSet {
            guard hideComments != oldValue else { return }
            defaults.set(hideComments, forKey: Keys.hideComments)
            onWebConfigDidChange?()
        }
    }

    public var hideHomeFeed: Bool {
        didSet {
            guard hideHomeFeed != oldValue else { return }
            defaults.set(hideHomeFeed, forKey: Keys.hideHomeFeed)
            onWebConfigDidChange?()
        }
    }

    public var disableAmbientMode: Bool {
        didSet {
            guard disableAmbientMode != oldValue else { return }
            defaults.set(disableAmbientMode, forKey: Keys.disableAmbientMode)
            onWebConfigDidChange?()
        }
    }

    public var autoDismissContinueWatching: Bool {
        didSet {
            guard autoDismissContinueWatching != oldValue else { return }
            defaults.set(autoDismissContinueWatching, forKey: Keys.autoDismissContinueWatching)
            onWebConfigDidChange?()
        }
    }

    public var preferOriginalAudio: Bool {
        didSet {
            guard preferOriginalAudio != oldValue else { return }
            defaults.set(preferOriginalAudio, forKey: Keys.preferOriginalAudio)
            onWebConfigDidChange?()
        }
    }

    public var preferredQuality: PreferredVideoQuality {
        didSet {
            guard preferredQuality != oldValue else { return }
            defaults.set(preferredQuality.rawValue, forKey: Keys.preferredQuality)
            onWebConfigDidChange?()
        }
    }

    public var defaultPlaybackRate: Double {
        didSet {
            guard abs(defaultPlaybackRate - oldValue) >= 0.001 else { return }
            defaults.set(defaultPlaybackRate, forKey: Keys.defaultPlaybackRate)
            onWebConfigDidChange?()
        }
    }

    public var sponsorBlockEnabled: Bool {
        didSet {
            guard sponsorBlockEnabled != oldValue else { return }
            defaults.set(sponsorBlockEnabled, forKey: Keys.sponsorBlockEnabled)
            onWebConfigDidChange?()
            onSponsorBlockSettingDidChange?(sponsorBlockEnabled)
        }
    }

    public var openExternalLinksInBrowser: Bool {
        didSet {
            guard openExternalLinksInBrowser != oldValue else { return }
            defaults.set(openExternalLinksInBrowser, forKey: Keys.openExternalLinksInBrowser)
        }
    }

    public var alwaysShowTabBar: Bool {
        didSet {
            guard alwaysShowTabBar != oldValue else { return }
            defaults.set(alwaysShowTabBar, forKey: Keys.alwaysShowTabBar)
        }
    }

    public var miniPlayerAllSpaces: Bool {
        didSet {
            guard miniPlayerAllSpaces != oldValue else { return }
            defaults.set(miniPlayerAllSpaces, forKey: Keys.miniPlayerAllSpaces)
            onWindowPreferencesDidChange?()
        }
    }

    public var autoMiniPlayerOnLeave: Bool {
        didSet {
            guard autoMiniPlayerOnLeave != oldValue else { return }
            defaults.set(autoMiniPlayerOnLeave, forKey: Keys.autoMiniPlayerOnLeave)
        }
    }

    public var showMenuBarControls: Bool {
        didSet {
            guard showMenuBarControls != oldValue else { return }
            defaults.set(showMenuBarControls, forKey: Keys.showMenuBarControls)
        }
    }

    public var isSidebarVisible: Bool {
        didSet {
            guard isSidebarVisible != oldValue else { return }
            defaults.set(isSidebarVisible, forKey: Keys.isSidebarVisible)
        }
    }

    public var showHomeShelf: Bool {
        didSet {
            guard showHomeShelf != oldValue else { return }
            defaults.set(showHomeShelf, forKey: Keys.showHomeShelf)
        }
    }

    public var restoreTabsOnLaunch: Bool {
        didSet {
            guard restoreTabsOnLaunch != oldValue else { return }
            defaults.set(restoreTabsOnLaunch, forKey: Keys.restoreTabsOnLaunch)
        }
    }

    public var autoPauseOnSystemEvents: Bool {
        didSet {
            guard autoPauseOnSystemEvents != oldValue else { return }
            defaults.set(autoPauseOnSystemEvents, forKey: Keys.autoPauseOnSystemEvents)
            onSystemPlaybackGuardSettingDidChange?(autoPauseOnSystemEvents)
        }
    }

    public var searchAutocompleteEnabled: Bool {
        didSet {
            guard searchAutocompleteEnabled != oldValue else { return }
            defaults.set(searchAutocompleteEnabled, forKey: Keys.searchAutocompleteEnabled)
        }
    }

    public var savedMultiviewPresets: [MultiviewPreset] {
        didSet {
            guard savedMultiviewPresets != oldValue else { return }
            saveMultiviewPresets()
        }
    }

    public var multiviewQualityCeiling: MultiviewQualityCeiling {
        didSet {
            guard multiviewQualityCeiling != oldValue else { return }
            defaults.set(multiviewQualityCeiling.rawValue, forKey: Keys.multiviewQualityCeiling)
            onWebConfigDidChange?()
        }
    }

    public var multiviewAudioDuckingEnabled: Bool {
        didSet {
            guard multiviewAudioDuckingEnabled != oldValue else { return }
            defaults.set(multiviewAudioDuckingEnabled, forKey: Keys.multiviewAudioDuckingEnabled)
            onMultiviewAudioDuckingDidChange?(multiviewAudioDuckingEnabled)
        }
    }

    public var automaticallyChecksForUpdates: Bool {
        didSet {
            guard automaticallyChecksForUpdates != oldValue else { return }
            defaults.set(automaticallyChecksForUpdates, forKey: Keys.automaticallyChecksForUpdates)
        }
    }

    public var savedSession: SavedSession? {
        get {
            guard let data = defaults.data(forKey: Keys.savedSession),
                  let decoded = try? JSONDecoder().decode(SavedSession.self, from: data) else {
                return nil
            }
            return decoded
        }
        set {
            if let session = newValue, let data = try? JSONEncoder().encode(session) {
                defaults.set(data, forKey: Keys.savedSession)
            } else if defaults.object(forKey: Keys.savedSession) != nil {
                defaults.removeObject(forKey: Keys.savedSession)
            }
        }
    }

    public var startupDestination: StartupDestination {
        didSet {
            guard startupDestination != oldValue else { return }
            defaults.set(startupDestination.rawValue, forKey: Keys.startupDestination)
        }
    }

    public var appearance: AppAppearance {
        didSet {
            guard appearance != oldValue else { return }
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
            onWindowPreferencesDidChange?()
            onAppearanceDidChange?()
        }
    }

    public var pinnedItems: [PinnedItem] {
        didSet {
            guard pinnedItems != oldValue else { return }
            savePinnedItems()
        }
    }

    public var hasCompletedStreamingOnboarding: Bool {
        didSet {
            guard hasCompletedStreamingOnboarding != oldValue else { return }
            defaults.set(hasCompletedStreamingOnboarding, forKey: Keys.hasCompletedStreamingOnboarding)
        }
    }

    public var enabledStreamingServiceIDs: [String] {
        didSet {
            guard enabledStreamingServiceIDs != oldValue else { return }
            defaults.set(enabledStreamingServiceIDs, forKey: Keys.enabledStreamingServiceIDs)
        }
    }

    public var signedInStreamingServiceIDs: [String] {
        didSet {
            guard signedInStreamingServiceIDs != oldValue else { return }
            defaults.set(signedInStreamingServiceIDs, forKey: Keys.signedInStreamingServiceIDs)
        }
    }

    public var miniPlayerOpacity: Double {
        didSet {
            let clamped = min(max(miniPlayerOpacity.isFinite ? miniPlayerOpacity : 1.0, 0.40), 1.0)
            if abs(miniPlayerOpacity - clamped) > 0.0001 {
                miniPlayerOpacity = clamped
                return
            }
            guard abs(miniPlayerOpacity - oldValue) > 0.0001 else { return }
            defaults.set(miniPlayerOpacity, forKey: Keys.miniPlayerOpacity)
            onMiniPlayerOpacityDidChange?(miniPlayerOpacity)
        }
    }

    public var enabledStreamingServices: [StreamingService] {
        StreamingServiceCatalog.resolvedEnabledServices(from: enabledStreamingServiceIDs)
    }

    public func isServiceEnabled(_ serviceID: String) -> Bool {
        enabledStreamingServiceIDs.contains(serviceID)
    }

    public func toggleStreamingService(_ serviceID: String) {
        if let idx = enabledStreamingServiceIDs.firstIndex(of: serviceID) {
            if enabledStreamingServiceIDs.count > 1 {
                enabledStreamingServiceIDs.remove(at: idx)
            }
        } else if StreamingServiceCatalog.service(id: serviceID) != nil {
            let nextSet = Set(enabledStreamingServiceIDs + [serviceID])
            enabledStreamingServiceIDs = StreamingServiceCatalog.all
                .map(\.id)
                .filter { nextSet.contains($0) }
        }
    }

    public func isServiceSignedIn(_ serviceID: String) -> Bool {
        signedInStreamingServiceIDs.contains(serviceID)
    }

    public func setServiceSignedIn(_ serviceID: String, signedIn: Bool) {
        if signedIn {
            if !signedInStreamingServiceIDs.contains(serviceID) {
                signedInStreamingServiceIDs.append(serviceID)
            }
        } else {
            signedInStreamingServiceIDs.removeAll { $0 == serviceID }
        }
    }

    public var pinnedFolders: [PinnedFolder] {
        didSet {
            guard pinnedFolders != oldValue else { return }
            savePinnedFolders()
        }
    }

    public var continueWatching: [ContinueWatchingItem] {
        didSet {
            guard continueWatching != oldValue else { return }
            saveContinueWatching()
        }
    }

    public var watchedChannels: [WatchedChannelStat] {
        didSet {
            guard watchedChannels != oldValue else { return }
            saveWatchedChannels()
        }
    }

    public var savedMiniPlayerFrame: NSRect? {
        get {
            guard let raw = defaults.string(forKey: Keys.savedMiniPlayerFrame) else {
                return nil
            }
            let rect = NSRectFromString(raw)
            return rect.width >= 200 && rect.height >= 112 ? rect : nil
        }
        set {
            if let rect = newValue {
                let encoded = NSStringFromRect(rect)
                if defaults.string(forKey: Keys.savedMiniPlayerFrame) != encoded {
                    defaults.set(encoded, forKey: Keys.savedMiniPlayerFrame)
                }
            } else if defaults.object(forKey: Keys.savedMiniPlayerFrame) != nil {
                defaults.removeObject(forKey: Keys.savedMiniPlayerFrame)
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hideShorts = defaults.object(forKey: Keys.hideShorts) as? Bool ?? true
        self.redirectShortsToWatch = defaults.object(forKey: Keys.redirectShortsToWatch) as? Bool ?? true
        self.cleanWebChrome = defaults.object(forKey: Keys.cleanWebChrome) as? Bool ?? true
        self.hideWebHeader = defaults.object(forKey: Keys.hideWebHeader) as? Bool ?? false
        self.autoTheaterMode = defaults.object(forKey: Keys.autoTheaterMode) as? Bool ?? true
        self.hideEndScreens = defaults.object(forKey: Keys.hideEndScreens) as? Bool ?? true
        self.hideWatchRecommendations = defaults.object(forKey: Keys.hideWatchRecommendations) as? Bool ?? false
        self.hideComments = defaults.object(forKey: Keys.hideComments) as? Bool ?? false
        self.hideHomeFeed = defaults.object(forKey: Keys.hideHomeFeed) as? Bool ?? false
        self.disableAmbientMode = defaults.object(forKey: Keys.disableAmbientMode) as? Bool ?? true
        self.autoDismissContinueWatching = defaults.object(forKey: Keys.autoDismissContinueWatching) as? Bool ?? true
        self.preferOriginalAudio = defaults.object(forKey: Keys.preferOriginalAudio) as? Bool ?? true
        self.sponsorBlockEnabled = defaults.object(forKey: Keys.sponsorBlockEnabled) as? Bool ?? false
        self.openExternalLinksInBrowser = defaults.object(forKey: Keys.openExternalLinksInBrowser) as? Bool ?? true
        self.alwaysShowTabBar = defaults.object(forKey: Keys.alwaysShowTabBar) as? Bool ?? false
        self.miniPlayerAllSpaces = defaults.object(forKey: Keys.miniPlayerAllSpaces) as? Bool ?? true
        self.autoMiniPlayerOnLeave = defaults.object(forKey: Keys.autoMiniPlayerOnLeave) as? Bool ?? true
        self.showMenuBarControls = defaults.object(forKey: Keys.showMenuBarControls) as? Bool ?? true
        self.isSidebarVisible = defaults.object(forKey: Keys.isSidebarVisible) as? Bool ?? true
        self.showHomeShelf = defaults.object(forKey: Keys.showHomeShelf) as? Bool ?? true
        self.restoreTabsOnLaunch = defaults.object(forKey: Keys.restoreTabsOnLaunch) as? Bool ?? true
        self.autoPauseOnSystemEvents = defaults.object(forKey: Keys.autoPauseOnSystemEvents) as? Bool ?? true
        self.searchAutocompleteEnabled = defaults.object(forKey: Keys.searchAutocompleteEnabled) as? Bool ?? true
        self.multiviewAudioDuckingEnabled = defaults.object(forKey: Keys.multiviewAudioDuckingEnabled) as? Bool ?? false
        self.automaticallyChecksForUpdates = defaults.object(forKey: Keys.automaticallyChecksForUpdates) as? Bool ?? true
        self.hasCompletedStreamingOnboarding = defaults.object(forKey: Keys.hasCompletedStreamingOnboarding) as? Bool ?? false

        if let savedServices = defaults.stringArray(forKey: Keys.enabledStreamingServiceIDs), !savedServices.isEmpty {
            let validSet = Set(StreamingServiceCatalog.all.map(\.id))
            let filtered = savedServices.filter { validSet.contains($0) }
            self.enabledStreamingServiceIDs = filtered.isEmpty ? StreamingServiceCatalog.defaultEnabledServiceIDs : filtered
        } else {
            self.enabledStreamingServiceIDs = StreamingServiceCatalog.defaultEnabledServiceIDs
        }

        if let savedSignedIn = defaults.stringArray(forKey: Keys.signedInStreamingServiceIDs) {
            self.signedInStreamingServiceIDs = savedSignedIn
        } else {
            self.signedInStreamingServiceIDs = []
        }

        if let savedOpacity = defaults.object(forKey: Keys.miniPlayerOpacity) as? Double,
           savedOpacity.isFinite {
            self.miniPlayerOpacity = min(max(savedOpacity, 0.40), 1.0)
        } else {
            self.miniPlayerOpacity = 1.0
        }

        if let rawCeiling = defaults.string(forKey: Keys.multiviewQualityCeiling),
           let parsedCeiling = MultiviewQualityCeiling(rawValue: rawCeiling) {
            self.multiviewQualityCeiling = parsedCeiling
        } else {
            self.multiviewQualityCeiling = .auto
        }

        if let rawQuality = defaults.string(forKey: Keys.preferredQuality),
           let parsed = PreferredVideoQuality(rawValue: rawQuality) {
            self.preferredQuality = parsed
        } else {
            self.preferredQuality = .auto
        }

        if let savedSpeed = defaults.object(forKey: Keys.defaultPlaybackRate) as? Double,
           savedSpeed.isFinite, savedSpeed >= 0.25, savedSpeed <= 4.0 {
            self.defaultPlaybackRate = savedSpeed
        } else {
            self.defaultPlaybackRate = 1.0
        }

        if let rawStartup = defaults.string(forKey: Keys.startupDestination),
           let parsed = StartupDestination(rawValue: rawStartup) {
            self.startupDestination = parsed
        } else {
            self.startupDestination = .home
        }

        if let rawAppearance = defaults.string(forKey: Keys.appearance),
           let parsed = AppAppearance(rawValue: rawAppearance) {
            self.appearance = parsed
        } else {
            self.appearance = .system
        }

        if let data = defaults.data(forKey: Keys.pinnedItems),
           let decoded = try? JSONDecoder().decode([PinnedItem].self, from: data) {
            self.pinnedItems = decoded
        } else {
            self.pinnedItems = []
        }

        if let data = defaults.data(forKey: Keys.pinnedFolders),
           let decoded = try? JSONDecoder().decode([PinnedFolder].self, from: data) {
            self.pinnedFolders = decoded
        } else {
            self.pinnedFolders = []
        }

        if let data = defaults.data(forKey: Keys.continueWatching),
           let decoded = try? JSONDecoder().decode([ContinueWatchingItem].self, from: data) {
            self.continueWatching = decoded
        } else {
            self.continueWatching = []
        }

        if let data = defaults.data(forKey: Keys.watchedChannels),
           let decoded = try? JSONDecoder().decode([WatchedChannelStat].self, from: data) {
            self.watchedChannels = decoded
        } else {
            self.watchedChannels = []
        }

        if let data = defaults.data(forKey: Keys.savedMultiviewPresets),
           let decoded = try? JSONDecoder().decode([MultiviewPreset].self, from: data) {
            self.savedMultiviewPresets = decoded
        } else {
            self.savedMultiviewPresets = []
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    public var isEffectivelyDark: Bool {
        switch appearance {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua
        }
    }

    public func applyAppearance() {
        guard let app = NSApp else { return }
        switch appearance {
        case .system:
            app.appearance = nil
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        }
    }

    public func distractionFreeConfig(
        focusMode: Bool,
        miniPlayer: Bool,
        multiviewTile: Bool = false,
        qualityOverride: PreferredVideoQuality? = nil
    ) -> DistractionFreeConfig {
        DistractionFreeConfig(
            hideShorts: hideShorts,
            redirectShortsToWatch: redirectShortsToWatch,
            cleanWebChrome: cleanWebChrome,
            hideWebHeader: hideWebHeader,
            autoTheaterMode: autoTheaterMode,
            hideEndScreens: hideEndScreens,
            hideWatchRecommendations: hideWatchRecommendations,
            hideComments: hideComments,
            hideHomeFeed: hideHomeFeed,
            disableAmbientMode: disableAmbientMode || multiviewTile,
            autoDismissContinueWatching: autoDismissContinueWatching,
            preferOriginalAudio: preferOriginalAudio,
            preferredQuality: qualityOverride ?? preferredQuality,
            defaultPlaybackRate: defaultPlaybackRate,
            sponsorBlockEnabled: sponsorBlockEnabled,
            appearance: appearance,
            focusModeActive: focusMode,
            miniPlayerActive: miniPlayer,
            multiviewTileActive: multiviewTile
        )
    }

    public func clearLocalHistory() {
        continueWatching = []
        watchedChannels = []
        savedMultiviewPresets = []
    }

    private func saveMultiviewPresets() {
        if let data = try? JSONEncoder().encode(savedMultiviewPresets) {
            defaults.set(data, forKey: Keys.savedMultiviewPresets)
        }
    }

    private func savePinnedItems() {
        if let data = try? JSONEncoder().encode(pinnedItems) {
            defaults.set(data, forKey: Keys.pinnedItems)
        }
    }

    private func savePinnedFolders() {
        if let data = try? JSONEncoder().encode(pinnedFolders) {
            defaults.set(data, forKey: Keys.pinnedFolders)
        }
    }

    private func saveContinueWatching() {
        if let data = try? JSONEncoder().encode(continueWatching) {
            defaults.set(data, forKey: Keys.continueWatching)
        }
    }

    private func saveWatchedChannels() {
        if let data = try? JSONEncoder().encode(watchedChannels) {
            defaults.set(data, forKey: Keys.watchedChannels)
        }
    }
}
