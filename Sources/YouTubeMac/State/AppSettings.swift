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
        static let savedMiniPlayerGridFrame = "ytmac.savedMiniPlayerGridFrame"
        static let cleanBoxStreamingPlayers = "ytmac.cleanBoxStreamingPlayers"
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
        static let agentControlEnabled = "ytmac.agentControlEnabled"
        static let agentPermissionLevel = "ytmac.agentPermissionLevel"
        static let agentShowHUDToasts = "ytmac.agentShowHUDToasts"
        static let allowURLSchemeActions = "ytmac.allowURLSchemeActions"
        static let agentHTTPServerEnabled = "ytmac.agentHTTPServerEnabled"
        static let agentHTTPPort = "ytmac.agentHTTPPort"
        static let livePulseEnabled = "ytmac.livePulse.enabled"
        static let livePulseShowTicker = "ytmac.livePulse.showTicker"
        static let livePulseShowDrawer = "ytmac.livePulse.showDrawer"
        static let livePulseDrawerWidth = "ytmac.livePulse.drawerWidth"
        static let livePulseSpoilerDelay = "ytmac.livePulse.spoilerDelay"
        static let livePulseEnabledLeagues = "ytmac.livePulse.enabledLeagues"
        static let livePulseLeaguePriority = "ytmac.livePulse.leaguePriority"
        static let livePulseStreamFocusOnly = "ytmac.livePulse.streamFocusOnly"
        static let livePulseShowMarkets = "ytmac.livePulse.showMarkets"
        static let livePulseSleeperUsername = "ytmac.livePulse.sleeperUsername"
        static let livePulseFantasyLeagues = "ytmac.livePulse.fantasyLeagues"
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

    @ObservationIgnored
    var onAgentSettingsDidChange: (() -> Void)?

    @ObservationIgnored
    var onShortcutsParametersDidChange: (() -> Void)?

    @ObservationIgnored
    public var onLivePulseSettingsDidChange: (() -> Void)?

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

    public var cleanBoxStreamingPlayers: Bool {
        didSet {
            guard cleanBoxStreamingPlayers != oldValue else { return }
            defaults.set(cleanBoxStreamingPlayers, forKey: Keys.cleanBoxStreamingPlayers)
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
            onShortcutsParametersDidChange?()
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
            onShortcutsParametersDidChange?()
        }
    }

    public var agentControlEnabled: Bool {
        didSet {
            guard agentControlEnabled != oldValue else { return }
            defaults.set(agentControlEnabled, forKey: Keys.agentControlEnabled)
            onAgentSettingsDidChange?()
        }
    }

    public var agentPermissionLevel: AgentPermissionLevel {
        didSet {
            guard agentPermissionLevel != oldValue else { return }
            defaults.set(agentPermissionLevel.rawValue, forKey: Keys.agentPermissionLevel)
        }
    }

    public var agentShowHUDToasts: Bool {
        didSet {
            guard agentShowHUDToasts != oldValue else { return }
            defaults.set(agentShowHUDToasts, forKey: Keys.agentShowHUDToasts)
        }
    }

    public var allowURLSchemeActions: Bool {
        didSet {
            guard allowURLSchemeActions != oldValue else { return }
            defaults.set(allowURLSchemeActions, forKey: Keys.allowURLSchemeActions)
        }
    }

    public var agentHTTPServerEnabled: Bool {
        didSet {
            guard agentHTTPServerEnabled != oldValue else { return }
            defaults.set(agentHTTPServerEnabled, forKey: Keys.agentHTTPServerEnabled)
            onAgentSettingsDidChange?()
        }
    }

    public var agentHTTPPort: Int {
        didSet {
            let clamped = min(max(agentHTTPPort, 1024), 65535)
            if agentHTTPPort != clamped {
                agentHTTPPort = clamped
                return
            }
            guard agentHTTPPort != oldValue else { return }
            defaults.set(agentHTTPPort, forKey: Keys.agentHTTPPort)
            onAgentSettingsDidChange?()
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

    public var livePulseEnabled: Bool {
        didSet {
            guard livePulseEnabled != oldValue else { return }
            defaults.set(livePulseEnabled, forKey: Keys.livePulseEnabled)
            onLivePulseSettingsDidChange?()
        }
    }

    public var livePulseShowTicker: Bool {
        didSet {
            guard livePulseShowTicker != oldValue else { return }
            defaults.set(livePulseShowTicker, forKey: Keys.livePulseShowTicker)
            onLivePulseSettingsDidChange?()
        }
    }

    public var livePulseShowDrawer: Bool {
        didSet {
            guard livePulseShowDrawer != oldValue else { return }
            defaults.set(livePulseShowDrawer, forKey: Keys.livePulseShowDrawer)
            onLivePulseSettingsDidChange?()
        }
    }

    public var livePulseDrawerWidth: Double {
        didSet {
            let finite = livePulseDrawerWidth.isFinite ? CGFloat(livePulseDrawerWidth) : LivePulseLayout.drawerDefaultWidth
            let clamped = Double(LivePulseLayout.clampDrawerWidth(finite))
            if abs(livePulseDrawerWidth - clamped) > 0.0001 {
                livePulseDrawerWidth = clamped
                return
            }
            guard abs(livePulseDrawerWidth - oldValue) > 0.0001 else { return }
            defaults.set(livePulseDrawerWidth, forKey: Keys.livePulseDrawerWidth)
        }
    }

    public var livePulseSpoilerDelay: SpoilerDelayOption {
        didSet {
            guard livePulseSpoilerDelay != oldValue else { return }
            defaults.set(livePulseSpoilerDelay.rawValue, forKey: Keys.livePulseSpoilerDelay)
            onLivePulseSettingsDidChange?()
        }
    }

    public var livePulseEnabledLeagues: [SportsLeague] {
        didSet {
            guard livePulseEnabledLeagues != oldValue else { return }
            defaults.set(livePulseEnabledLeagues.map(\.rawValue), forKey: Keys.livePulseEnabledLeagues)
            onLivePulseSettingsDidChange?()
        }
    }

    public var livePulseLeaguePriority: [SportsLeague] {
        didSet {
            let normalized = SportsLeague.normalizedPriority(livePulseLeaguePriority)
            if livePulseLeaguePriority != normalized {
                livePulseLeaguePriority = normalized
                return
            }
            guard livePulseLeaguePriority != oldValue else { return }
            defaults.set(livePulseLeaguePriority.map(\.rawValue), forKey: Keys.livePulseLeaguePriority)
            onLivePulseSettingsDidChange?()
        }
    }

    public var livePulseStreamFocusOnly: Bool {
        didSet {
            guard livePulseStreamFocusOnly != oldValue else { return }
            defaults.set(livePulseStreamFocusOnly, forKey: Keys.livePulseStreamFocusOnly)
            onLivePulseSettingsDidChange?()
        }
    }

    public var orderedEnabledLivePulseLeagues: [SportsLeague] {
        livePulseLeaguePriority.filter { livePulseEnabledLeagues.contains($0) }
    }

    public func moveLivePulseLeagueToTop(_ league: SportsLeague) {
        var updated = SportsLeague.normalizedPriority(livePulseLeaguePriority)
        updated.removeAll { $0 == league }
        updated.insert(league, at: 0)
        livePulseLeaguePriority = updated
    }

    public func moveLivePulseLeague(_ league: SportsLeague, direction: Int) {
        guard direction != 0 else { return }
        var updated = SportsLeague.normalizedPriority(livePulseLeaguePriority)
        guard let currentIndex = updated.firstIndex(of: league) else { return }
        let targetIndex = min(max(currentIndex + direction, 0), updated.count - 1)
        guard targetIndex != currentIndex else { return }
        updated.remove(at: currentIndex)
        updated.insert(league, at: targetIndex)
        livePulseLeaguePriority = updated
    }

    public func moveLivePulseLeagues(from source: IndexSet, to destination: Int) {
        var updated = SportsLeague.normalizedPriority(livePulseLeaguePriority)
        updated.move(fromOffsets: source, toOffset: destination)
        livePulseLeaguePriority = updated
    }

    public var livePulseShowMarkets: Bool {
        didSet {
            guard livePulseShowMarkets != oldValue else { return }
            defaults.set(livePulseShowMarkets, forKey: Keys.livePulseShowMarkets)
            onLivePulseSettingsDidChange?()
        }
    }

    public var livePulseSleeperUsername: String {
        didSet {
            guard livePulseSleeperUsername != oldValue else { return }
            defaults.set(livePulseSleeperUsername, forKey: Keys.livePulseSleeperUsername)
            onLivePulseSettingsDidChange?()
        }
    }

    public var livePulseFantasyLeagues: [FantasyLeagueConfig] {
        didSet {
            guard livePulseFantasyLeagues != oldValue else { return }
            saveLivePulseFantasyLeagues()
            onLivePulseSettingsDidChange?()
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

    public var savedMiniPlayerGridFrame: NSRect? {
        get {
            guard let raw = defaults.string(forKey: Keys.savedMiniPlayerGridFrame) else {
                return nil
            }
            let rect = NSRectFromString(raw)
            return rect.width >= 440 && rect.height >= 248 ? rect : nil
        }
        set {
            if let rect = newValue {
                let encoded = NSStringFromRect(rect)
                if defaults.string(forKey: Keys.savedMiniPlayerGridFrame) != encoded {
                    defaults.set(encoded, forKey: Keys.savedMiniPlayerGridFrame)
                }
            } else if defaults.object(forKey: Keys.savedMiniPlayerGridFrame) != nil {
                defaults.removeObject(forKey: Keys.savedMiniPlayerGridFrame)
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hideShorts = defaults.object(forKey: Keys.hideShorts) as? Bool ?? true
        self.redirectShortsToWatch = defaults.object(forKey: Keys.redirectShortsToWatch) as? Bool ?? true
        self.cleanWebChrome = defaults.object(forKey: Keys.cleanWebChrome) as? Bool ?? true
        self.cleanBoxStreamingPlayers = defaults.object(forKey: Keys.cleanBoxStreamingPlayers) as? Bool ?? true
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
        self.agentControlEnabled = defaults.object(forKey: Keys.agentControlEnabled) as? Bool ?? false
        if let rawTier = defaults.string(forKey: Keys.agentPermissionLevel),
           let parsedTier = AgentPermissionLevel(rawValue: rawTier) {
            self.agentPermissionLevel = parsedTier
        } else {
            self.agentPermissionLevel = .playbackAndNavigation
        }
        self.agentShowHUDToasts = defaults.object(forKey: Keys.agentShowHUDToasts) as? Bool ?? true
        self.allowURLSchemeActions = defaults.object(forKey: Keys.allowURLSchemeActions) as? Bool ?? false
        self.agentHTTPServerEnabled = defaults.object(forKey: Keys.agentHTTPServerEnabled) as? Bool ?? false
        let storedPort = defaults.object(forKey: Keys.agentHTTPPort) as? Int ?? 41773
        self.agentHTTPPort = min(max(storedPort, 1024), 65535)

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

        self.livePulseEnabled = defaults.object(forKey: Keys.livePulseEnabled) as? Bool ?? false
        self.livePulseShowTicker = defaults.object(forKey: Keys.livePulseShowTicker) as? Bool ?? false
        self.livePulseShowDrawer = defaults.object(forKey: Keys.livePulseShowDrawer) as? Bool ?? false

        if let savedDrawerWidth = defaults.object(forKey: Keys.livePulseDrawerWidth) as? Double,
           savedDrawerWidth.isFinite {
            self.livePulseDrawerWidth = Double(LivePulseLayout.clampDrawerWidth(CGFloat(savedDrawerWidth)))
        } else {
            self.livePulseDrawerWidth = Double(LivePulseLayout.drawerDefaultWidth)
        }

        if let rawDelay = defaults.object(forKey: Keys.livePulseSpoilerDelay) as? Int,
           let parsedDelay = SpoilerDelayOption(rawValue: rawDelay) {
            self.livePulseSpoilerDelay = parsedDelay
        } else {
            self.livePulseSpoilerDelay = .off
        }

        if let rawLeagues = defaults.stringArray(forKey: Keys.livePulseEnabledLeagues) {
            self.livePulseEnabledLeagues = rawLeagues.compactMap(SportsLeague.init(rawValue:))
        } else {
            self.livePulseEnabledLeagues = SportsLeague.allCases
        }

        if let rawPriority = defaults.stringArray(forKey: Keys.livePulseLeaguePriority) {
            self.livePulseLeaguePriority = SportsLeague.normalizedPriority(rawPriority.compactMap(SportsLeague.init(rawValue:)))
        } else {
            self.livePulseLeaguePriority = SportsLeague.normalizedPriority([.nfl, .nba, .mlb, .nhl])
        }

        self.livePulseStreamFocusOnly = defaults.object(forKey: Keys.livePulseStreamFocusOnly) as? Bool ?? false

        self.livePulseShowMarkets = defaults.object(forKey: Keys.livePulseShowMarkets) as? Bool ?? true
        self.livePulseSleeperUsername = defaults.string(forKey: Keys.livePulseSleeperUsername) ?? ""

        if let data = defaults.data(forKey: Keys.livePulseFantasyLeagues),
           let decoded = try? JSONDecoder().decode([FantasyLeagueConfig].self, from: data) {
            self.livePulseFantasyLeagues = decoded
        } else {
            self.livePulseFantasyLeagues = []
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
        qualityOverride: PreferredVideoQuality? = nil,
        cleanBoxBypassed: Bool = false
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
            multiviewTileActive: multiviewTile,
            cleanBoxStreamingPlayers: cleanBoxStreamingPlayers,
            cleanBoxBypassed: cleanBoxBypassed
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

    private func saveLivePulseFantasyLeagues() {
        if let data = try? JSONEncoder().encode(livePulseFantasyLeagues) {
            defaults.set(data, forKey: Keys.livePulseFantasyLeagues)
        }
    }
}
