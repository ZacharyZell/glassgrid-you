import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import YouTubeMacCore

/// Coordinates tabs, omnibox navigation, distraction-free mode, playback enhancements, floating pop-up mini-player, windowing, and site data.
@MainActor
@Observable
public final class AppController {
    public enum PopOutReason: Equatable, Sendable {
        case manual
        case leftPage
        case leftApp
    }

    public let windowID: UUID
    public let isPrimaryWindow: Bool
    public let settings: AppSettings
    public var tabs: [BrowserTab] = []
    public var selectedTabID: UUID
    public var closedTabURLs: [URL] = []

    public var focusModeActive: Bool = false
    public var alwaysOnTop: Bool = false
    public var isSidebarVisible: Bool
    public var isCompactHeaderActive: Bool
    public var poppedOutTabIDs: [UUID] = []

    public var multiviewTabIDs: [UUID] = []
    public var multiviewAudioTabID: UUID?
    public var soloMultiviewTabID: UUID?
    public var multiviewLayoutMode: MultiviewLayoutMode = .auto
    public var multiviewSplitRatios: MultiviewSplitRatios = .default
    public var multiviewCustomVolumes: [UUID: Int] = [:]
    public var hasCustomMultiviewMix: Bool { !multiviewCustomVolumes.isEmpty }
    public var hoveredMultiviewTileID: UUID?
    public var hoveredMultiviewDividerID: MultiviewDividerID?
    public var activeMultiviewDividerDragID: MultiviewDividerID?

    public var omniboxText: String = ""
    public var omniboxFocusTrigger: Int = 0
    public var omniboxClearOnFocus: Bool = false
    public var isMainWindowVisible: Bool = true
    public var isMainWindowMiniaturized: Bool = false
    public var isWindowInNativeFullScreen: Bool = false
    public var isSigningOutData: Bool = false
    public var activeToast: HUDToast?
    public var isContinueWatchingExpanded: Bool = true
    public var selectedHomeTopic: SuggestedTopic = .all

    public var sleepTimerOption: SleepTimerOption?
    public var sleepTimerEndDate: Date?

    public var isFindBarPresented: Bool = false
    public var findQuery: String = ""
    public var findFocusTrigger: Int = 0
    public var findMatchFound: Bool?

    public var isCommandPalettePresented: Bool = false
    public var commandPaletteQuery: String = ""
    public var commandPaletteSuggestions: [String] = []
    public var commandPaletteFocusTrigger: Int = 0

    public var isOnboardingPresented: Bool = false
    public var onboardingInitialStep: Int = 1
    public var onboardingFocusServiceID: String?
    public var isAirPlayPopoverPresented: Bool = false
    public var airPlayVideoHint: String?

    // Live Pulse layout flags ONLY (live telemetry lives exclusively on `LivePulseStore`)
    public var isLivePulseTickerVisible: Bool = false
    public var isLivePulseTickerRendered: Bool {
        isLivePulseTickerVisible && !isCompactHeaderActive
    }
    public var isLivePulseDrawerVisible: Bool = false
    public var livePulseDrawerWidth: CGFloat = LivePulseLayout.drawerDefaultWidth
    public var windowContentWidth: CGFloat = 1280

    @ObservationIgnored
    private var sidebarVisibleBeforeLiveDrawer: Bool?

    public var livePulseStore: LivePulseStore? {
        coordinator?.livePulseStore
    }

    @ObservationIgnored
    public weak var coordinator: AppCoordinator?

    @ObservationIgnored
    weak var mainWindow: NSWindow?

    @ObservationIgnored
    private var hasCascadedSecondaryWindow = false

    @ObservationIgnored
    private var isWindowTornDown = false

    @ObservationIgnored
    private var suggestDebounceTask: Task<Void, Never>?

    @ObservationIgnored
    private var sleepTimerTask: Task<Void, Never>?

    @ObservationIgnored
    private var postSleepTimerEndGuardUntil: Date = .distantPast

    @ObservationIgnored
    private var findDebounceTask: Task<Void, Never>?

    @ObservationIgnored
    private var sessionSaveTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastMultiviewAudioSwitchAt: Date = .distantPast

    @ObservationIgnored
    private var multiviewVolumeDispatchTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var sidebarVisibleBeforeMultiview: Bool?

    @ObservationIgnored
    private let fallbackFloatingMiniPlayer: FloatingMiniPlayerController?

    @ObservationIgnored
    private let fallbackSponsorBlockClient = SponsorBlockClient()

    @ObservationIgnored
    private let fallbackSuggestClient = YouTubeSuggestClient()

    @ObservationIgnored
    private var sponsorFetchTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var signInCheckTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var signInCheckServiceIDs: [UUID: String] = [:]

    @ObservationIgnored
    private var toastDismissTask: Task<Void, Never>?

    @ObservationIgnored
    private var poppedOutReason: PopOutReason?

    @ObservationIgnored
    private var resignActiveTask: Task<Void, Never>?

    @ObservationIgnored
    private var windowObservers: [NSObjectProtocol] = []

    @ObservationIgnored
    private var workspaceObservers: [NSObjectProtocol] = []

    @ObservationIgnored
    private var soloEscapeMonitor: Any?

    private var floatingMiniPlayer: FloatingMiniPlayerController {
        coordinator?.floatingMiniPlayer ?? fallbackFloatingMiniPlayer!
    }

    private var sponsorBlockClient: SponsorBlockClient {
        coordinator?.sponsorBlockClient ?? fallbackSponsorBlockClient
    }

    private var suggestClient: YouTubeSuggestClient {
        coordinator?.suggestClient ?? fallbackSuggestClient
    }

    private var initialThemeCookieSyncTask: Task<Void, Never>? {
        coordinator?.initialThemeCookieSyncTask
    }

    private static let defaultMinSize = NSSize(width: 780, height: 520)

    public init(
        windowID: UUID = UUID(),
        isPrimaryWindow: Bool = true,
        launchRequest: WindowLaunchRequest = .standard,
        coordinator: AppCoordinator? = nil,
        settings: AppSettings? = nil
    ) {
        let resolvedSettings = coordinator?.settings ?? settings ?? AppSettings()
        self.windowID = windowID
        self.isPrimaryWindow = isPrimaryWindow
        self.coordinator = coordinator
        self.settings = resolvedSettings
        self.isSidebarVisible = resolvedSettings.isSidebarVisible
        self.isCompactHeaderActive = resolvedSettings.compactHeaderMode
        self.isLivePulseTickerVisible = resolvedSettings.livePulseEnabled && resolvedSettings.livePulseShowTicker
        self.isLivePulseDrawerVisible = resolvedSettings.livePulseEnabled && resolvedSettings.livePulseShowDrawer
        self.livePulseDrawerWidth = LivePulseLayout.clampDrawerWidth(CGFloat(resolvedSettings.livePulseDrawerWidth))
        self.fallbackFloatingMiniPlayer = coordinator == nil
            ? FloatingMiniPlayerController(
                initialSavedFrame: resolvedSettings.savedMiniPlayerFrame,
                initialSavedGridFrame: resolvedSettings.savedMiniPlayerGridFrame,
                initialOpacity: resolvedSettings.miniPlayerOpacity
            )
            : nil

        let placeholderID = UUID()
        self.selectedTabID = placeholderID

        let pendingSync = coordinator?.initialThemeCookieSyncTask
        let initialSelectedTab: BrowserTab
        let initialSelectedURL: URL
        var presetToLaunch: MultiviewPreset?

        switch launchRequest {
        case .url(let targetURL, let routingMode):
            let tab = makeTab(
                url: targetURL,
                routingMode: routingMode,
                deferInitialLoad: pendingSync != nil
            )
            self.tabs = [tab]
            initialSelectedTab = tab
            initialSelectedURL = targetURL

        case .multiviewPreset(let preset):
            let fallbackURL = resolvedSettings.startupDestination.url
            let fallbackTab = makeTab(url: fallbackURL, deferInitialLoad: true)
            self.tabs = [fallbackTab]
            initialSelectedTab = fallbackTab
            initialSelectedURL = fallbackURL
            presetToLaunch = preset

        case .standard:
            if isPrimaryWindow,
               resolvedSettings.restoreTabsOnLaunch,
               let saved = resolvedSettings.savedSession,
               let sanitized = SessionRestorationFilter.sanitize(tabs: saved.tabs, selectedIndex: saved.selectedIndex) {
                var restoredTabs: [BrowserTab] = []
                restoredTabs.reserveCapacity(sanitized.tabs.count)
                for (idx, snap) in sanitized.tabs.enumerated() {
                    guard let tabURL = snap.url else { continue }
                    let isSelected = (idx == sanitized.selectedIndex)
                    let tab = makeTab(
                        url: tabURL,
                        initialTitle: snap.title,
                        routingMode: snap.routingMode,
                        deferInitialLoad: isSelected && pendingSync != nil,
                        lazyLoad: !isSelected
                    )
                    restoredTabs.append(tab)
                }
                if !restoredTabs.isEmpty {
                    let clampedIdx = min(max(0, sanitized.selectedIndex), restoredTabs.count - 1)
                    self.tabs = restoredTabs
                    initialSelectedTab = restoredTabs[clampedIdx]
                    initialSelectedURL = initialSelectedTab.url
                } else {
                    let fallbackURL = resolvedSettings.startupDestination.url
                    let fallbackTab = makeTab(url: fallbackURL, deferInitialLoad: pendingSync != nil)
                    self.tabs = [fallbackTab]
                    initialSelectedTab = fallbackTab
                    initialSelectedURL = fallbackURL
                }
            } else {
                let fallbackURL = resolvedSettings.startupDestination.url
                let fallbackTab = makeTab(url: fallbackURL, deferInitialLoad: pendingSync != nil)
                self.tabs = [fallbackTab]
                initialSelectedTab = fallbackTab
                initialSelectedURL = fallbackURL
            }
        }

        self.selectedTabID = initialSelectedTab.id
        self.omniboxText = initialSelectedTab.url.absoluteString

        if let preset = presetToLaunch {
            let launchBlock: @MainActor () -> Void = { [weak self] in
                guard let self, !self.isWindowTornDown else { return }
                let placeholderTab = self.tabs.first
                self.launchMultiviewPreset(preset)
                if let placeholderTab,
                   self.tabs.count > 1,
                   !self.multiviewTabIDs.contains(placeholderTab.id) {
                    self.closeTab(id: placeholderTab.id)
                }
            }
            if let pendingSync {
                Task { @MainActor in
                    await pendingSync.value
                    launchBlock()
                }
            } else {
                launchBlock()
            }
        } else if let pendingSync {
            Task { @MainActor [weak initialSelectedTab] in
                await pendingSync.value
                initialSelectedTab?.load(initialSelectedURL)
            }
        }
    }

    public var isMiniPlayer: Bool {
        !poppedOutTabIDs.isEmpty
    }

    public var isFloatingMultiviewGrid: Bool {
        poppedOutTabIDs.count >= 2
    }

    public var poppedOutTabID: UUID? {
        poppedOutTabIDs.count == 1 ? poppedOutTabIDs.first : nil
    }

    public var poppedOutTabs: [BrowserTab] {
        poppedOutTabIDs.compactMap { id in tabs.first(where: { $0.id == id }) }
    }

    public func isTabPoppedOut(_ id: UUID) -> Bool {
        poppedOutTabIDs.contains(id)
    }

    public var isSelectedTabPoppedOut: Bool {
        poppedOutTabIDs.contains(selectedTabID)
    }

    public var isSleepTimerActive: Bool {
        sleepTimerOption != nil
    }

    public var currentShareURL: URL? {
        selectedTab?.url
    }

    public var currentTimestampedShareURL: URL? {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return nil }
        return YouTubeURLRouter.urlWithTimestamp(tab.url, seconds: tab.timeline.currentTime)
    }

    public var poppedOutTab: BrowserTab? {
        guard let poppedOutTabID else { return nil }
        return tabs.first(where: { $0.id == poppedOutTabID })
    }

    public var selectedTab: BrowserTab? {
        tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    public var anyTabInFullscreen: Bool {
        tabs.contains(where: \.isInFullscreen)
    }

    public var hasLiveFullscreenTab: Bool {
        anyTabInFullscreen || tabs.contains { $0.webView.fullscreenState != .notInFullscreen }
    }

    public var isMultiviewActive: Bool {
        multiviewTabIDs.count >= 2
    }

    public var multiviewTabs: [BrowserTab] {
        multiviewTabIDs.compactMap { id in
            tabs.first(where: { $0.id == id })
        }
    }

    public var multiviewAudioTab: BrowserTab? {
        guard isMultiviewActive else { return nil }
        if let audioID = multiviewAudioTabID,
           multiviewTabIDs.contains(audioID),
           let tab = tabs.first(where: { $0.id == audioID }) {
            return tab
        }
        return multiviewTabs.first
    }

    public var canAddMultiviewTile: Bool {
        multiviewTabIDs.count < MultiviewGridLayout.maxTiles
    }

    public func multiviewSlotNumber(for tabID: UUID) -> Int? {
        guard isMultiviewActive, let idx = multiviewTabIDs.firstIndex(of: tabID) else {
            return nil
        }
        return idx + 1
    }

    public func isTabInMultiview(_ tabID: UUID) -> Bool {
        isMultiviewActive && multiviewTabIDs.contains(tabID)
    }

    /// Prioritizes the active-audio Multiview tile, then popped-out video, then selected tab, before falling back.
    public var activeMediaTab: BrowserTab? {
        if isMultiviewActive {
            if let audio = multiviewAudioTab, audio.mediaStatus.hasVideo {
                return audio
            }
            if let playing = multiviewTabs.first(where: { $0.mediaStatus.isPlaying }) {
                return playing
            }
            if let audio = multiviewAudioTab {
                return audio
            }
        }
        if let popped = poppedOutTab, popped.mediaStatus.isPlaying {
            return popped
        }
        if let selected = selectedTab, selected.mediaStatus.isPlaying {
            return selected
        }
        if let playing = tabs.first(where: { $0.mediaStatus.isPlaying }) {
            return playing
        }
        if let popped = poppedOutTab, popped.mediaStatus.hasVideo {
            return popped
        }
        if let selected = selectedTab, selected.mediaStatus.hasVideo {
            return selected
        }
        if let firstVideo = tabs.first(where: { $0.mediaStatus.hasVideo }) {
            return firstVideo
        }
        return selectedTab
    }

    public var nowPlayingStatus: MediaStatus {
        activeMediaTab?.mediaStatus ?? .empty
    }

    public var activeTimeline: PlaybackTimeline? {
        activeMediaTab?.timeline
    }

    public var activeChapters: [VideoChapter] {
        activeMediaTab?.chapters ?? []
    }

    public var canPopOutMultiviewGrid: Bool {
        isMultiviewActive && !hasLiveFullscreenTab && multiviewTabs.contains(where: { $0.mediaStatus.hasVideo })
    }

    public var canPopOutActiveContent: Bool {
        if isMultiviewActive {
            return canPopOutMultiviewGrid
        }
        if let selected = selectedTab, canPopOut(tab: selected) {
            return true
        }
        guard let candidate = activeMediaTab else { return false }
        return canPopOut(tab: candidate)
    }

    public var canPopOutActiveTab: Bool {
        canPopOutActiveContent
    }

    public var isCurrentPagePinned: Bool {
        guard let url = selectedTab?.url else { return false }
        return settings.pinnedItems.contains(where: { $0.urlString == url.absoluteString })
    }

    // MARK: - HUD Toast

    public func showHUD(icon: String, message: String) {
        toastDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            activeToast = HUDToast(icon: icon, message: message)
        }
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1150))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: 0.22)) {
                self.activeToast = nil
            }
        }
    }

    // MARK: - Tab Management

    @discardableResult
    public func createTab(
        url: URL? = nil,
        select: Bool = true,
        routingMode: TabRoutingMode? = nil
    ) -> BrowserTab {
        let targetURL = url ?? settings.startupDestination.url
        let targetIsWatch = YouTubeURLRouter.isWatchURL(targetURL)

        if !isMultiviewActive, select, let leaving = selectedTab {
            if settings.autoMiniPlayerOnLeave,
               !targetIsWatch,
               !isMiniPlayer,
               shouldAutoPopOut(tab: leaving) {
                popOutToMiniPlayer(tab: leaving, reason: .leftPage)
            } else if targetIsWatch && leaving.mediaStatus.isPlaying {
                leaving.pauseMedia()
            }
        }

        let pendingSync = initialThemeCookieSyncTask
        let tab = makeTab(
            url: targetURL,
            routingMode: routingMode,
            deferInitialLoad: pendingSync != nil
        )
        tab.setBackForwardGesturesEnabled(!isMultiviewActive)
        tabs.append(tab)

        if isMultiviewActive {
            if select {
                if canAddMultiviewTile {
                    let next = MultiviewReducer.addTile(tab.id, to: multiviewState)
                    multiviewTabIDs = next.tabIDs
                    multiviewAudioTabID = next.audioTabID
                    selectedTabID = tab.id
                    syncOmniboxToSelectedTab()
                    if isFloatingMultiviewGrid {
                        poppedOutTabIDs = multiviewTabIDs
                        syncFloatingMultiviewGrid()
                    }
                    applyConfigToAllTabs()
                    applyMultiviewAudioFocus(unmuteAudioTab: false)
                } else {
                    if isFloatingMultiviewGrid {
                        dockMiniPlayer(selectTab: false, focusMain: true)
                    }
                    // Already at 4 tiles and user explicitly opened/selected a new tab: cleanly exit Multiview to it.
                    exitMultiview(focusTabID: tab.id, showFeedback: false)
                }
            }
            // Background Cmd-clicks (select == false) remain quietly in the tab strip without disturbing the 4-tile grid.
        } else if select {
            selectedTabID = tab.id
            syncOmniboxToSelectedTab()
        }

        if let pendingSync {
            Task { @MainActor [weak tab] in
                await pendingSync.value
                tab?.load(targetURL)
            }
        }
        refreshSponsorSegmentsIfNeeded(for: tab, url: targetURL)
        scheduleSessionSave()
        syncLivePulseStreamSignals()
        return tab
    }

    public func duplicateTab(id: UUID) {
        guard let source = tabs.first(where: { $0.id == id }) else { return }
        createTab(url: source.pendingLazyURL ?? source.url, select: true)
    }

    public func closeTab(id: UUID) {
        guard !hasLiveFullscreenTab else { return }

        if let closingTab = tabs.first(where: { $0.id == id }) {
            flushWatchProgress(for: closingTab)
        }
        sponsorFetchTasks[id]?.cancel()
        sponsorFetchTasks.removeValue(forKey: id)
        signInCheckTasks[id]?.cancel()
        signInCheckTasks.removeValue(forKey: id)
        signInCheckServiceIDs.removeValue(forKey: id)
        multiviewVolumeDispatchTasks[id]?.cancel()
        multiviewVolumeDispatchTasks.removeValue(forKey: id)

        if tabs.count <= 1 {
            // In multi-window mode, closing the sole tab of a secondary window closes that window cleanly.
            if coordinator?.hasMultipleWindows == true {
                closeWindow()
                return
            }
            // Standard macOS single-window behavior: restore mini-player cleanly, pause active video, then hide window.
            if isTabPoppedOut(id) {
                let detached = floatingMiniPlayer.detachAndHide()
                poppedOutTabIDs = []
                poppedOutReason = nil
                coordinator?.releaseMiniPlayerOwnership(for: windowID)
                if let tab = detached.first ?? tabs.first(where: { $0.id == id }) {
                    tab.needsPostAttachResize = true
                    tab.pauseAllPlayback()
                    tab.applyConfig(configForTab(id: tab.id), force: true)
                }
            } else if let soleTab = tabs.first(where: { $0.id == id }) {
                soleTab.pauseAllPlayback()
            }
            hideMainWindow()
            return
        }

        let wasFloatingGrid = isFloatingMultiviewGrid && isTabPoppedOut(id)
        if !wasFloatingGrid && poppedOutTabID == id {
            floatingMiniPlayer.detachAndHide()
            poppedOutTabIDs = []
            poppedOutReason = nil
            coordinator?.releaseMiniPlayerOwnership(for: windowID)
        }

        if wasFloatingGrid {
            let result = MultiviewReducer.removeTile(id, from: multiviewState)
            let closingReason = poppedOutReason ?? .manual
            if let survivingID = result.remainingSingleTabID {
                // Transition 2->1 cleanly BEFORE tearing down the closed tab so its WKWebView
                // is detached from FloatingMiniPlayerController before teardown() runs.
                multiviewTabIDs = []
                multiviewAudioTabID = nil
                soloMultiviewTabID = nil
                hoveredMultiviewTileID = nil
                cancelAllMultiviewVolumeDispatchTasks()
                multiviewCustomVolumes.removeAll()
                selectedTabID = survivingID

                if let survivor = tabs.first(where: { $0.id == survivingID }), survivor.id != id, canPopOut(tab: survivor) {
                    poppedOutTabIDs = [survivor.id]
                    poppedOutReason = closingReason
                    if survivor.mediaStatus.hasVideo {
                        survivor.setAudioLevel(muted: false, volumePercent: 100)
                    }
                    presentSingleFloatingMiniPlayer(for: survivor)
                } else {
                    _ = floatingMiniPlayer.detachAndHide()
                    poppedOutTabIDs = []
                    poppedOutReason = nil
                    coordinator?.releaseMiniPlayerOwnership(for: windowID)
                    if let survivor = tabs.first(where: { $0.id == survivingID }), survivor.id != id {
                        survivor.needsPostAttachResize = true
                        ensureTabLoaded(survivor)
                        if survivor.mediaStatus.hasVideo {
                            survivor.setAudioLevel(muted: false, volumePercent: 100)
                        }
                    }
                }

                if let idx = tabs.firstIndex(where: { $0.id == id }) {
                    let removed = tabs.remove(at: idx)
                    closedTabURLs.append(removed.pendingLazyURL ?? removed.url)
                    if closedTabURLs.count > 20 { closedTabURLs.removeFirst() }
                    removed.teardown()
                }

                restoreSidebarAfterMultiviewIfNeeded()
                syncBackForwardGestures()
                syncOmniboxToSelectedTab()
                applyConfigToAllTabs()
                scheduleSessionSave()
                return
            } else {
                multiviewTabIDs = result.state.tabIDs
                multiviewAudioTabID = result.state.audioTabID
                soloMultiviewTabID = result.state.soloTabID
                multiviewCustomVolumes = MultiviewAudioMixer.sanitizedCustomVolumes(
                    multiviewCustomVolumes,
                    keeping: Set(result.state.tabIDs)
                )
                if hoveredMultiviewTileID == id {
                    hoveredMultiviewTileID = nil
                }
                if selectedTabID == id {
                    selectedTabID = result.state.audioTabID ?? result.state.tabIDs.first ?? id
                    syncOmniboxToSelectedTab()
                }
                poppedOutTabIDs = multiviewTabIDs
                syncFloatingMultiviewGrid()
                if let idx = tabs.firstIndex(where: { $0.id == id }) {
                    let removed = tabs.remove(at: idx)
                    closedTabURLs.append(removed.pendingLazyURL ?? removed.url)
                    if closedTabURLs.count > 20 { closedTabURLs.removeFirst() }
                    removed.teardown()
                }
                if !multiviewTabIDs.contains(selectedTabID), let fallbackID = multiviewAudioTabID ?? multiviewTabIDs.first {
                    selectedTabID = fallbackID
                    syncOmniboxToSelectedTab()
                }
                applyConfigToAllTabs()
                applyMultiviewAudioFocus(unmuteAudioTab: true)
                scheduleSessionSave()
                return
            }
        }

        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: index)
        closedTabURLs.append(removed.pendingLazyURL ?? removed.url)
        if closedTabURLs.count > 20 {
            closedTabURLs.removeFirst()
        }
        removed.teardown()

        if multiviewTabIDs.contains(id) {
            let result = MultiviewReducer.removeTile(id, from: multiviewState)
            if let survivingID = result.remainingSingleTabID {
                multiviewTabIDs = []
                multiviewAudioTabID = nil
                soloMultiviewTabID = nil
                hoveredMultiviewTileID = nil
                cancelAllMultiviewVolumeDispatchTasks()
                multiviewCustomVolumes.removeAll()
                restoreSidebarAfterMultiviewIfNeeded()
                syncBackForwardGestures()
                selectedTabID = survivingID
                syncOmniboxToSelectedTab()
                if let survivor = tabs.first(where: { $0.id == survivingID }) {
                    survivor.needsPostAttachResize = true
                    ensureTabLoaded(survivor)
                    if survivor.mediaStatus.hasVideo {
                        survivor.setAudioLevel(muted: false, volumePercent: 100)
                    }
                }
                applyConfigToAllTabs()
                scheduleSessionSave()
                return
            } else {
                multiviewTabIDs = result.state.tabIDs
                multiviewAudioTabID = result.state.audioTabID
                soloMultiviewTabID = result.state.soloTabID
                multiviewCustomVolumes = MultiviewAudioMixer.sanitizedCustomVolumes(
                    multiviewCustomVolumes,
                    keeping: Set(result.state.tabIDs)
                )
                if hoveredMultiviewTileID == id {
                    hoveredMultiviewTileID = nil
                }
                if selectedTabID == id {
                    selectedTabID = result.state.audioTabID ?? result.state.tabIDs.first ?? tabs[min(index, tabs.count - 1)].id
                    syncOmniboxToSelectedTab()
                }
                applyConfigToAllTabs()
                applyMultiviewAudioFocus(unmuteAudioTab: true)
                scheduleSessionSave()
                return
            }
        }

        if selectedTabID == id {
            let nextIndex = min(index, tabs.count - 1)
            let nextTab = tabs[nextIndex]
            selectedTabID = nextTab.id
            ensureTabLoaded(nextTab)
            syncOmniboxToSelectedTab()
        }
        scheduleSessionSave()
        syncLivePulseStreamSignals()
    }

    public func closeOtherTabs(keepingID id: UUID) {
        guard !hasLiveFullscreenTab else { return }

        if isFloatingMultiviewGrid || (isMiniPlayer && poppedOutTabID != id) {
            floatingMiniPlayer.detachAndHide()
            poppedOutTabIDs = []
            poppedOutReason = nil
            coordinator?.releaseMiniPlayerOwnership(for: windowID)
        }

        if isMultiviewActive {
            multiviewTabIDs = []
            multiviewAudioTabID = nil
            soloMultiviewTabID = nil
            hoveredMultiviewTileID = nil
            cancelAllMultiviewVolumeDispatchTasks()
            multiviewCustomVolumes.removeAll()
            restoreSidebarAfterMultiviewIfNeeded()
            syncBackForwardGestures()
        }

        let toClose = tabs.filter { $0.id != id }
        for tab in toClose {
            sponsorFetchTasks[tab.id]?.cancel()
            sponsorFetchTasks.removeValue(forKey: tab.id)
            signInCheckTasks[tab.id]?.cancel()
            signInCheckTasks.removeValue(forKey: tab.id)
            signInCheckServiceIDs.removeValue(forKey: tab.id)
            closedTabURLs.append(tab.pendingLazyURL ?? tab.url)
            tab.teardown()
        }
        tabs.removeAll { $0.id != id }
        selectedTabID = id
        syncOmniboxToSelectedTab()
        if let kept = tabs.first(where: { $0.id == id }) {
            ensureTabLoaded(kept)
            kept.needsPostAttachResize = true
            if kept.mediaStatus.hasVideo {
                kept.setAudioLevel(muted: false, volumePercent: 100)
            }
            kept.applyConfig(configForTab(id: id), force: true)
        }
        scheduleSessionSave()
    }

    public func reopenClosedTab() {
        guard let lastURL = closedTabURLs.popLast() else { return }
        createTab(url: lastURL, select: true)
    }

    public func selectTab(id: UUID) {
        guard !hasLiveFullscreenTab else { return }
        guard let targetTab = tabs.first(where: { $0.id == id }) else { return }

        if isFloatingMultiviewGrid {
            ensureTabLoaded(targetTab)
            if multiviewTabIDs.contains(id) {
                focusMultiviewAudio(tabID: id, showFeedback: false)
                scheduleSessionSave()
                return
            }
            dockMiniPlayer(selectTab: false, focusMain: false)
        } else if id == poppedOutTabID {
            // Clicking back on a single popped-out tab smoothly docks it back into the main window.
            dockMiniPlayer(selectTab: true, focusMain: false)
            return
        }

        ensureTabLoaded(targetTab)

        if isMultiviewActive {
            if multiviewTabIDs.contains(id) {
                if targetTab.isCompanionTab && !targetTab.mediaStatus.hasVideo {
                    if selectedTabID != id {
                        selectedTabID = id
                        syncOmniboxToSelectedTab()
                    }
                } else {
                    focusMultiviewAudio(tabID: id, showFeedback: false)
                }
            } else {
                exitMultiview(focusTabID: id, showFeedback: false)
            }
            scheduleSessionSave()
            return
        }

        // If leaving a playing watch tab for another tab, float the playing video as a pop-up.
        if settings.autoMiniPlayerOnLeave,
           !isMiniPlayer,
           let leaving = selectedTab,
           leaving.id != id,
           shouldAutoPopOut(tab: leaving) {
            popOutToMiniPlayer(tab: leaving, reason: .leftPage)
        }

        selectedTabID = id
        syncOmniboxToSelectedTab()
        if isFindBarPresented {
            findMatchFound = nil
            if !findQuery.isEmpty {
                scheduleDebouncedFindOnPage()
            }
        }
        scheduleSessionSave()
        syncLivePulseStreamSignals()
    }

    public func selectNextTab() {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let next = (index + 1) % tabs.count
        selectTab(id: tabs[next].id)
    }

    public func selectPreviousTab() {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let prev = (index - 1 + tabs.count) % tabs.count
        selectTab(id: tabs[prev].id)
    }

    public func selectTab(atIndex oneBasedIndex: Int) {
        let index = oneBasedIndex - 1
        guard tabs.indices.contains(index) else { return }
        selectTab(id: tabs[index].id)
    }

    // MARK: - Navigation & Pins

    public func navigateSelectedTab(to destination: SidebarDestination) {
        navigateSelectedTab(to: destination.url)
    }

    public func navigateSelectedTab(to url: URL) {
        flushWatchProgress(for: selectedTab)
        let finalURL: URL
        if settings.redirectShortsToWatch, let rewritten = YouTubeURLRouter.rewriteShortsURL(url) {
            finalURL = rewritten
        } else {
            finalURL = url
        }

        // If the Multiview grid is currently floating, dock it back cleanly before navigating so
        // `poppedOutTabIDs == multiviewTabIDs` invariant is preserved and the user stays oriented.
        if isFloatingMultiviewGrid {
            dockMiniPlayer(selectTab: true, focusMain: true)
        }

        // If the selected tab is currently popped out (single mode), navigate a docked tab instead so the pop-up keeps playing.
        if let current = selectedTab, current.id == poppedOutTabID {
            if let docked = tabs.first(where: { $0.id != poppedOutTabID }) {
                selectedTabID = docked.id
                docked.load(finalURL)
                omniboxText = finalURL.absoluteString
            } else {
                createTab(url: finalURL, select: true)
            }
            return
        }

        // If leaving a playing watch page for a non-watch page (Home, Subscriptions, Search, etc.),
        // float the playing video in the always-on-top pop-up mini-player while browsing in the main window.
        let navigatingToWatch = YouTubeURLRouter.isWatchURL(finalURL)
        if !isMultiviewActive,
           settings.autoMiniPlayerOnLeave,
           !navigatingToWatch,
           !isMiniPlayer,
           let current = selectedTab,
           shouldAutoPopOut(tab: current) {
            popOutToMiniPlayer(tab: current, reason: .leftPage)
            if let otherDocked = tabs.first(where: { $0.id != current.id }) {
                selectedTabID = otherDocked.id
                otherDocked.load(finalURL)
                omniboxText = finalURL.absoluteString
            } else {
                createTab(url: finalURL, select: true)
            }
            return
        }

        selectedTab?.load(finalURL)
        omniboxText = finalURL.absoluteString
    }

    public func submitOmnibox() {
        guard let resolved = YouTubeURLRouter.resolveOmniboxInput(
            omniboxText,
            redirectShortsToWatch: settings.redirectShortsToWatch
        ) else {
            return
        }
        navigateSelectedTab(to: resolved)
        focusActiveWebView()
    }

    public func focusOmnibox(clearForSearch: Bool = false) {
        omniboxClearOnFocus = clearForSearch
        if !clearForSearch {
            syncOmniboxToSelectedTab()
        }
        omniboxFocusTrigger &+= 1
    }

    public func focusActiveWebView() {
        selectedTab?.focusWebContent()
    }

    public func syncOmniboxToSelectedTab() {
        if let currentURL = selectedTab?.url {
            omniboxText = currentURL.absoluteString
        }
        syncWindowTitle()
    }

    public func openURLFromClipboard() {
        guard let clip = NSPasteboard.general.string(forType: .string),
              let url = YouTubeURLRouter.extractYouTubeURLFromString(clip) else {
            showHUD(icon: "link.badge.plus", message: "No YouTube Link in Clipboard")
            return
        }
        let target = settings.redirectShortsToWatch
            ? (YouTubeURLRouter.rewriteShortsURL(url) ?? url)
            : url
        focusMainWindow()
        createTab(url: target, select: true)
    }

    public func clipboardYouTubeURL() -> URL? {
        guard let clip = NSPasteboard.general.string(forType: .string) else {
            return nil
        }
        return YouTubeURLRouter.extractYouTubeURLFromString(clip)
    }

    public func openCurrentInDefaultBrowser() {
        guard let url = selectedTab?.url else { return }
        NSWorkspace.shared.open(url)
    }

    public func copyCurrentURL() {
        guard let url = selectedTab?.url else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        showHUD(icon: "link", message: "Link Copied")
    }

    public func copyCurrentURLAtTime() {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return }
        let seconds = tab.timeline.currentTime
        let timestamped = YouTubeURLRouter.urlWithTimestamp(tab.url, seconds: seconds)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(timestamped.absoluteString, forType: .string)
        if seconds >= 1 {
            showHUD(icon: "clock", message: "Copied Link at \(MediaState.formatTime(seconds))")
        } else {
            showHUD(icon: "link", message: "Link Copied")
        }
    }

    public func openSignIn() {
        guard let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube") else {
            return
        }
        focusMainWindow()
        navigateSelectedTab(to: url)
    }

    public func openGoogleAccount() {
        guard let url = URL(string: "https://myaccount.google.com/") else { return }
        focusMainWindow()
        createTab(url: url, select: true)
    }

    public func togglePinCurrentPage() {
        guard let tab = selectedTab else { return }
        let urlString = tab.url.absoluteString
        if let idx = settings.pinnedItems.firstIndex(where: { $0.urlString == urlString }) {
            settings.pinnedItems.remove(at: idx)
            showHUD(icon: "pin.slash", message: "Unpinned")
        } else {
            let item = PinnedItem(title: tab.displayTitle, urlString: urlString)
            settings.pinnedItems.append(item)
            showHUD(icon: "pin.fill", message: "Pinned to Sidebar")
        }
    }

    public func removePin(id: UUID) {
        settings.pinnedItems.removeAll { $0.id == id }
    }

    public func renamePin(id: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = settings.pinnedItems.firstIndex(where: { $0.id == id }) else {
            return
        }
        settings.pinnedItems[idx].title = trimmed
        showHUD(icon: "pencil", message: "Renamed Pin")
    }

    public func movePin(id: UUID, by delta: Int) {
        guard let idx = settings.pinnedItems.firstIndex(where: { $0.id == id }) else { return }
        let folderID = settings.pinnedItems[idx].folderID
        let siblingIndices = settings.pinnedItems.indices.filter { settings.pinnedItems[$0].folderID == folderID }
        guard let pos = siblingIndices.firstIndex(of: idx) else { return }
        let targetPos = pos + delta
        guard siblingIndices.indices.contains(targetPos), targetPos != pos else { return }
        settings.pinnedItems.swapAt(idx, siblingIndices[targetPos])
    }

    // MARK: - Sidebar Channel Folders

    @discardableResult
    public func createPinnedFolder(name: String) -> PinnedFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = PinnedFolder(name: trimmed, isExpanded: true)
        settings.pinnedFolders.append(folder)
        showHUD(icon: "folder.badge.plus", message: "Created Folder \"\(trimmed)\"")
        return folder
    }

    public func renamePinnedFolder(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = settings.pinnedFolders.firstIndex(where: { $0.id == id }) else {
            return
        }
        settings.pinnedFolders[idx].name = trimmed
        showHUD(icon: "pencil", message: "Renamed Folder")
    }

    public func togglePinnedFolderExpanded(id: UUID) {
        guard let idx = settings.pinnedFolders.firstIndex(where: { $0.id == id }) else { return }
        settings.pinnedFolders[idx].isExpanded.toggle()
    }

    /// Safe non-destructive folder deletion: keeps all child pins by moving them back to the ungrouped top level.
    public func deletePinnedFolder(id: UUID) {
        guard settings.pinnedFolders.contains(where: { $0.id == id }) else { return }
        var updatedPins = settings.pinnedItems
        var movedAny = false
        for i in updatedPins.indices where updatedPins[i].folderID == id {
            updatedPins[i].folderID = nil
            movedAny = true
        }
        if movedAny {
            settings.pinnedItems = updatedPins
        }
        settings.pinnedFolders.removeAll { $0.id == id }
        showHUD(icon: "folder.badge.minus", message: "Folder deleted — pins kept")
    }

    public func movePinToFolder(pinID: UUID, folderID: UUID?) {
        guard let idx = settings.pinnedItems.firstIndex(where: { $0.id == pinID }) else { return }
        if let folderID, !settings.pinnedFolders.contains(where: { $0.id == folderID }) {
            return
        }
        settings.pinnedItems[idx].folderID = folderID
        if let folderID,
           let folderIdx = settings.pinnedFolders.firstIndex(where: { $0.id == folderID }) {
            settings.pinnedFolders[folderIdx].isExpanded = true
            showHUD(icon: "folder.fill", message: "Moved to \"\(settings.pinnedFolders[folderIdx].name)\"")
        } else {
            showHUD(icon: "pin.fill", message: "Moved to Ungrouped")
        }
    }

    public func pins(inFolder folderID: UUID?) -> [PinnedItem] {
        if let folderID {
            return settings.pinnedItems.filter { $0.folderID == folderID }
        }
        let validFolderIDs = Set(settings.pinnedFolders.map(\.id))
        return settings.pinnedItems.filter { item in
            guard let fid = item.folderID else { return true }
            return !validFolderIDs.contains(fid)
        }
    }

    public func openPinnedItem(_ item: PinnedItem) {
        guard let url = item.url else { return }
        let mode = YouTubeURLRouter.preferredRoutingMode(for: url)
        if mode == .companion {
            if let current = selectedTab, current.routingMode == .companion, !isMultiviewActive {
                navigateSelectedTab(to: url)
            } else {
                createTab(url: url, select: true, routingMode: .companion)
            }
        } else {
            navigateSelectedTab(to: url)
        }
    }

    public func openFolderInMultiview(id: UUID) {
        guard !hasLiveFullscreenTab,
              let folder = settings.pinnedFolders.first(where: { $0.id == id }) else {
            return
        }
        let folderPins = pins(inFolder: id)
        let validURLs: [URL] = folderPins.prefix(MultiviewGridLayout.maxTiles).compactMap { pin in
            guard let url = pin.url else { return nil }
            let mode = YouTubeURLRouter.preferredRoutingMode(for: url)
            return SessionRestorationFilter.isRestorableURLString(url.absoluteString, routingMode: mode) ? url : nil
        }
        guard validURLs.count >= 2 else {
            openFolderInTabs(id: id)
            return
        }

        var usedTabIDs = Set<UUID>()
        var targetTabIDs: [UUID] = []
        targetTabIDs.reserveCapacity(validURLs.count)

        for targetURL in validURLs {
            let mode = YouTubeURLRouter.preferredRoutingMode(for: targetURL)
            if let existing = tabs.first(where: {
                !usedTabIDs.contains($0.id)
                    && $0.routingMode == mode
                    && ($0.pendingLazyURL ?? $0.url).absoluteString == targetURL.absoluteString
            }) {
                usedTabIDs.insert(existing.id)
                ensureTabLoaded(existing)
                targetTabIDs.append(existing.id)
            } else {
                let pendingSync = initialThemeCookieSyncTask
                let newTab = makeTab(url: targetURL, routingMode: mode, deferInitialLoad: pendingSync != nil)
                tabs.append(newTab)
                if let pendingSync {
                    Task { @MainActor [weak newTab] in
                        await pendingSync.value
                        newTab?.load(targetURL)
                    }
                }
                refreshSponsorSegmentsIfNeeded(for: newTab, url: targetURL)
                usedTabIDs.insert(newTab.id)
                targetTabIDs.append(newTab.id)
            }
        }

        enterMultiview(with: targetTabIDs)
        scheduleSessionSave()
        showHUD(icon: "square.grid.2x2.fill", message: "Opened \"\(folder.name)\" in Multiview")
    }

    public func openFolderInTabs(id: UUID) {
        guard !hasLiveFullscreenTab,
              let folder = settings.pinnedFolders.first(where: { $0.id == id }) else {
            return
        }
        let folderPins = pins(inFolder: id)
        let validURLs: [URL] = folderPins.prefix(6).compactMap { pin in
            guard let url = pin.url else { return nil }
            let mode = YouTubeURLRouter.preferredRoutingMode(for: url)
            return SessionRestorationFilter.isRestorableURLString(url.absoluteString, routingMode: mode) ? url : nil
        }
        guard !validURLs.isEmpty else {
            showHUD(icon: "folder", message: "Folder is Empty")
            return
        }

        if isMultiviewActive {
            exitMultiview(focusTabID: selectedTabID, showFeedback: false)
        }

        var usedTabIDs = Set<UUID>()
        var firstTabID: UUID?

        for targetURL in validURLs {
            let mode = YouTubeURLRouter.preferredRoutingMode(for: targetURL)
            if let existing = tabs.first(where: {
                !usedTabIDs.contains($0.id)
                    && $0.routingMode == mode
                    && ($0.pendingLazyURL ?? $0.url).absoluteString == targetURL.absoluteString
            }) {
                usedTabIDs.insert(existing.id)
                ensureTabLoaded(existing)
                if firstTabID == nil { firstTabID = existing.id }
            } else {
                let created = createTab(url: targetURL, select: false, routingMode: mode)
                usedTabIDs.insert(created.id)
                if firstTabID == nil { firstTabID = created.id }
            }
        }

        if let firstTabID {
            selectTab(id: firstTabID)
        }
        scheduleSessionSave()
        showHUD(icon: "folder.fill", message: "Opened \(validURLs.count) \(validURLs.count == 1 ? "pin" : "pins") from \"\(folder.name)\"")
    }

    public func moveTab(fromID: UUID, toID: UUID) {
        guard !hasLiveFullscreenTab,
              fromID != toID,
              let fromIdx = tabs.firstIndex(where: { $0.id == fromID }),
              let toIdx = tabs.firstIndex(where: { $0.id == toID }) else {
            return
        }
        let moved = tabs.remove(at: fromIdx)
        tabs.insert(moved, at: toIdx)
        scheduleSessionSave()
    }

    public func canPutTabToSleep(id: UUID) -> Bool {
        guard id != selectedTabID,
              !isTabPoppedOut(id),
              !isTabInMultiview(id),
              !hasLiveFullscreenTab,
              let tab = tabs.first(where: { $0.id == id }),
              !tab.isSleeping,
              tab.pendingLazyURL == nil,
              !tab.mediaStatus.isPlaying,
              !YouTubeURLRouter.isYouTubeTVHost(tab.url.host) else {
            return false
        }
        return true
    }

    public func putTabToSleep(id: UUID) {
        guard canPutTabToSleep(id: id),
              let tab = tabs.first(where: { $0.id == id }) else {
            return
        }
        flushWatchProgress(for: tab)
        tab.putToSleep()
        showHUD(icon: "moon.zzz", message: "Tab Put to Sleep")
    }

    public func dismissContinueWatching(videoID: String) {
        settings.continueWatching.removeAll { $0.videoID == videoID }
    }

    public func clearContinueWatching() {
        settings.continueWatching = []
    }

    public func clearLocalHistory() {
        settings.clearLocalHistory()
        showHUD(icon: "trash", message: "Local History Cleared")
    }

    public func flushWatchProgress(for tab: BrowserTab?) {
        guard let tab,
              tab.mediaStatus.hasVideo,
              YouTubeURLRouter.isStandardYouTubeHost(tab.url.host),
              let videoID = YouTubeURLRouter.extractVideoID(from: tab.url) else {
            return
        }
        let title = tab.mediaStatus.title.isEmpty ? tab.displayTitle : tab.mediaStatus.title
        settings.continueWatching = ContinueWatchingStore.upsert(
            videoID: videoID,
            title: title,
            channel: tab.mediaStatus.channel,
            currentTime: tab.timeline.currentTime,
            duration: tab.timeline.duration,
            into: settings.continueWatching
        )
    }

    // MARK: - Native Multiview (2-Up / 3-Up / 2×2 Quad-Box)

    private var multiviewState: MultiviewState {
        MultiviewState(
            tabIDs: multiviewTabIDs,
            audioTabID: multiviewAudioTabID,
            layoutMode: multiviewLayoutMode,
            soloTabID: soloMultiviewTabID
        )
    }

    public var isMultiviewSoloActive: Bool {
        guard isMultiviewActive, let soloID = soloMultiviewTabID else { return false }
        return multiviewTabIDs.contains(soloID)
    }

    public var soloMultiviewTab: BrowserTab? {
        guard isMultiviewSoloActive, let soloID = soloMultiviewTabID else { return nil }
        return tabs.first(where: { $0.id == soloID })
    }

    public func toggleMultiview() {
        if isMultiviewActive {
            exitMultiview(focusTabID: multiviewAudioTabID ?? selectedTabID, showFeedback: true)
        } else {
            enterMultiview()
        }
    }

    public func enterMultiview(with explicitTabIDs: [UUID]? = nil) {
        guard !hasLiveFullscreenTab else { return }

        if isMiniPlayer {
            dockMiniPlayer(selectTab: false, focusMain: false)
        }

        let primaryID: UUID
        let candidateIDs: [UUID]

        if let explicitTabIDs, let first = explicitTabIDs.first(where: { id in tabs.contains(where: { $0.id == id }) }) {
            primaryID = first
            candidateIDs = explicitTabIDs.filter { id in tabs.contains(where: { $0.id == id }) }
        } else {
            guard let current = selectedTab ?? tabs.first else { return }
            primaryID = current.id

            // If only 1 tab exists, spawn a ready companion tab so 1-click Multiview enters a 2-Up split immediately.
            if tabs.count < 2 {
                let pendingSync = initialThemeCookieSyncTask
                let companionURL = settings.startupDestination.url
                let companion = makeTab(url: companionURL, deferInitialLoad: pendingSync != nil)
                tabs.append(companion)
                if let pendingSync {
                    Task { @MainActor [weak companion] in
                        await pendingSync.value
                        companion?.load(companionURL)
                    }
                }
            }

            let others = tabs.filter { $0.id != primaryID }
            let watchOthers = others.filter { YouTubeURLRouter.isWatchURL($0.url) || $0.mediaStatus.hasVideo }
            let browseOthers = others.filter { !(YouTubeURLRouter.isWatchURL($0.url) || $0.mediaStatus.hasVideo) }
            candidateIDs = (watchOthers + browseOthers).map(\.id)
        }

        let next = MultiviewReducer.enter(
            primaryTabID: primaryID,
            candidateTabIDs: candidateIDs,
            preferredAudioTabID: primaryID,
            layoutMode: multiviewLayoutMode
        )
        guard next.isActive else { return }

        if sidebarVisibleBeforeMultiview == nil {
            sidebarVisibleBeforeMultiview = isSidebarVisible
        }
        if isSidebarVisible {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                isSidebarVisible = false
            }
        }

        cancelAllMultiviewVolumeDispatchTasks()
        multiviewCustomVolumes.removeAll()
        multiviewTabIDs = next.tabIDs
        multiviewAudioTabID = next.audioTabID
        soloMultiviewTabID = nil
        hoveredMultiviewTileID = nil
        if let activeID = next.audioTabID ?? next.tabIDs.first {
            selectedTabID = activeID
            syncOmniboxToSelectedTab()
        }

        for tile in multiviewTabs {
            ensureTabLoaded(tile)
        }
        syncBackForwardGestures()
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: true)

        for other in tabs where !multiviewTabIDs.contains(other.id) && other.mediaStatus.isPlaying {
            other.pauseMedia()
        }

        showHUD(icon: "square.grid.2x2.fill", message: "Multiview · \(multiviewTabIDs.count) Streams")
        syncLivePulseStreamSignals()
    }

    public func exitMultiview(focusTabID: UUID? = nil, showFeedback: Bool = true) {
        guard isMultiviewActive else { return }
        guard !hasLiveFullscreenTab, !floatingMiniPlayer.hasLiveFullscreenTab else { return }

        if isFloatingMultiviewGrid {
            dockMiniPlayer(selectTab: false, focusMain: false)
        }

        let targetID: UUID
        if let focusTabID, tabs.contains(where: { $0.id == focusTabID }) {
            targetID = focusTabID
        } else if let audioID = multiviewAudioTabID, tabs.contains(where: { $0.id == audioID }) {
            targetID = audioID
        } else {
            targetID = selectedTabID
        }

        let previousTileIDs = multiviewTabIDs
        cancelAllMultiviewVolumeDispatchTasks()
        multiviewCustomVolumes.removeAll()
        multiviewTabIDs = []
        multiviewAudioTabID = nil
        soloMultiviewTabID = nil
        hoveredMultiviewTileID = nil
        selectedTabID = targetID
        syncOmniboxToSelectedTab()

        for id in previousTileIDs {
            guard let tab = tabs.first(where: { $0.id == id }) else { continue }
            tab.needsPostAttachResize = true
            if id == targetID {
                ensureTabLoaded(tab)
                if tab.mediaStatus.hasVideo {
                    tab.setAudioLevel(muted: false, volumePercent: 100)
                }
            } else {
                // Always restore 100% volume before pausing so ducked tiles never remain stuck at 15% volume.
                tab.setAudioLevel(muted: false, volumePercent: 100)
                tab.pauseMedia()
            }
        }

        restoreSidebarAfterMultiviewIfNeeded()
        syncBackForwardGestures()
        applyConfigToAllTabs()

        if showFeedback {
            showHUD(icon: "rectangle.fill", message: "Single View")
        }
        syncLivePulseStreamSignals()
    }

    public func setMultiviewLayoutMode(_ mode: MultiviewLayoutMode, showFeedback: Bool = true) {
        guard multiviewLayoutMode != mode else { return }
        multiviewLayoutMode = mode
        if isFloatingMultiviewGrid {
            syncFloatingMultiviewGrid()
        }
        if isMultiviewActive {
            applyConfigToAllTabs()
        }
        if showFeedback {
            showHUD(icon: mode.systemImage, message: "Multiview: \(mode.title)")
        }
    }

    public func cycleMultiviewLayoutMode() {
        guard isMultiviewActive else { return }
        setMultiviewLayoutMode(multiviewLayoutMode.nextMode, showFeedback: true)
    }

    public func updateMultiviewSplitRatios(_ ratios: MultiviewSplitRatios) {
        guard multiviewSplitRatios != ratios else { return }
        multiviewSplitRatios = ratios
    }

    public func handleMultiviewDividerDoubleClickReset(_ dividerID: MultiviewDividerID) {
        let count = multiviewTabs.count
        guard count >= 2 else { return }
        multiviewSplitRatios = multiviewSplitRatios.resetting(divider: dividerID, tileCount: count)
        showHUD(icon: "arrow.counterclockwise", message: "Layout Proportions Reset")
    }

    public func addTileToMultiview(url: URL? = nil, routingMode: TabRoutingMode? = nil) {
        guard !hasLiveFullscreenTab else { return }
        let targetURL = url ?? settings.startupDestination.url
        let resolvedMode = routingMode ?? YouTubeURLRouter.preferredRoutingMode(for: targetURL)

        if !isMultiviewActive {
            let pendingSync = initialThemeCookieSyncTask
            let newTab = makeTab(url: targetURL, routingMode: resolvedMode, deferInitialLoad: pendingSync != nil)
            tabs.append(newTab)
            if let pendingSync {
                Task { @MainActor [weak newTab] in
                    await pendingSync.value
                    newTab?.load(targetURL)
                }
            }
            refreshSponsorSegmentsIfNeeded(for: newTab, url: targetURL)
            enterMultiview(with: [selectedTabID, newTab.id])
            return
        }

        guard canAddMultiviewTile else {
            showHUD(icon: "square.grid.2x2", message: "Maximum 4 Multiview Streams")
            return
        }

        let pendingSync = initialThemeCookieSyncTask
        let newTab = makeTab(url: targetURL, routingMode: resolvedMode, deferInitialLoad: pendingSync != nil)
        newTab.setBackForwardGesturesEnabled(false)
        tabs.append(newTab)
        if let pendingSync {
            Task { @MainActor [weak newTab] in
                await pendingSync.value
                newTab?.load(targetURL)
            }
        }
        refreshSponsorSegmentsIfNeeded(for: newTab, url: targetURL)

        let next = MultiviewReducer.addTile(newTab.id, to: multiviewState)
        multiviewTabIDs = next.tabIDs
        multiviewAudioTabID = next.audioTabID
        selectedTabID = newTab.id
        syncOmniboxToSelectedTab()
        if isFloatingMultiviewGrid {
            poppedOutTabIDs = multiviewTabIDs
            syncFloatingMultiviewGrid()
        }
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: false)
        scheduleSessionSave()
        let label = resolvedMode == .companion ? "Added Companion Tile" : "Added Stream"
        showHUD(
            icon: resolvedMode == .companion ? "globe" : "plus.square.on.square",
            message: "\(label) (\(multiviewTabIDs.count)/\(MultiviewGridLayout.maxTiles))"
        )
        syncLivePulseStreamSignals()
    }

    public func openCompanionTile(url: URL) {
        guard !hasLiveFullscreenTab else { return }
        let mode = YouTubeURLRouter.preferredRoutingMode(for: url)
        if isMultiviewActive && !canAddMultiviewTile {
            createTab(url: url, select: true, routingMode: mode)
            return
        }
        addTileToMultiview(url: url, routingMode: mode)
    }

    @discardableResult
    public func openCompanionTile(rawInput: String) -> Bool {
        if let ytURL = YouTubeURLRouter.extractYouTubeURLFromString(rawInput) {
            let target = settings.redirectShortsToWatch
                ? (YouTubeURLRouter.rewriteShortsURL(ytURL) ?? ytURL)
                : ytURL
            openCompanionTile(url: target)
            return true
        }
        guard let webURL = YouTubeURLRouter.resolveCompanionURL(rawInput) else {
            showHUD(icon: "exclamationmark.triangle", message: "Enter a Valid Website or HTTPS URL")
            return false
        }
        openCompanionTile(url: webURL)
        return true
    }

    public func openYouTubeTVInMultiview() {
        guard let url = URL(string: "https://tv.youtube.com/live") else { return }
        addTileToMultiview(url: url)
    }

    public func addClipboardURLToMultiview() {
        guard let clip = NSPasteboard.general.string(forType: .string) else {
            showHUD(icon: "link.badge.plus", message: "No Link in Clipboard")
            return
        }
        if let ytURL = YouTubeURLRouter.extractYouTubeURLFromString(clip) {
            let target = settings.redirectShortsToWatch
                ? (YouTubeURLRouter.rewriteShortsURL(ytURL) ?? ytURL)
                : ytURL
            addTileToMultiview(url: target, routingMode: .youtube)
            return
        }
        if let webURL = YouTubeURLRouter.resolveCompanionURL(clip) {
            addTileToMultiview(url: webURL, routingMode: .companion)
            return
        }
        showHUD(icon: "link.badge.plus", message: "No Valid Link in Clipboard")
    }

    public func addExistingTabToMultiview(id: UUID) {
        guard !hasLiveFullscreenTab, tabs.contains(where: { $0.id == id }) else { return }

        if poppedOutTabID == id {
            dockMiniPlayer(selectTab: false, focusMain: false)
        }

        if !isMultiviewActive {
            if id == selectedTabID {
                enterMultiview()
            } else {
                enterMultiview(with: [selectedTabID, id])
            }
            return
        }

        guard !multiviewTabIDs.contains(id) else {
            focusMultiviewAudio(tabID: id, showFeedback: false)
            return
        }
        guard canAddMultiviewTile else {
            showHUD(icon: "square.grid.2x2", message: "Maximum 4 Multiview Streams")
            return
        }

        let next = MultiviewReducer.addTile(id, to: multiviewState)
        multiviewTabIDs = next.tabIDs
        multiviewAudioTabID = next.audioTabID
        selectedTabID = id
        if let addedTab = tabs.first(where: { $0.id == id }) {
            ensureTabLoaded(addedTab)
            addedTab.setBackForwardGesturesEnabled(false)
        }
        syncOmniboxToSelectedTab()
        if isFloatingMultiviewGrid {
            poppedOutTabIDs = multiviewTabIDs
            syncFloatingMultiviewGrid()
        }
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: false)
        showHUD(icon: "square.grid.2x2", message: "Added to Multiview (\(multiviewTabIDs.count)/\(MultiviewGridLayout.maxTiles))")
    }

    public func removeTileFromMultiview(id: UUID, closeTabIfMultiple: Bool = false) {
        guard isMultiviewActive, multiviewTabIDs.contains(id), !hasLiveFullscreenTab else { return }

        if closeTabIfMultiple && tabs.count > 1 {
            closeTab(id: id)
            return
        }

        let wasFloatingGrid = isFloatingMultiviewGrid
        multiviewVolumeDispatchTasks[id]?.cancel()
        multiviewVolumeDispatchTasks.removeValue(forKey: id)
        if let removedTab = tabs.first(where: { $0.id == id }) {
            removedTab.needsPostAttachResize = true
            removedTab.setAudioLevel(muted: false, volumePercent: 100)
            removedTab.pauseMedia()
        }
        let result = MultiviewReducer.removeTile(id, from: multiviewState)
        if let survivingID = result.remainingSingleTabID {
            if wasFloatingGrid {
                let prevReason = poppedOutReason ?? .manual
                cancelAllMultiviewVolumeDispatchTasks()
                multiviewCustomVolumes.removeAll()
                multiviewTabIDs = []
                multiviewAudioTabID = nil
                soloMultiviewTabID = nil
                hoveredMultiviewTileID = nil
                restoreSidebarAfterMultiviewIfNeeded()
                syncBackForwardGestures()
                selectedTabID = survivingID
                syncOmniboxToSelectedTab()
                if let survivor = tabs.first(where: { $0.id == survivingID }), canPopOut(tab: survivor) {
                    poppedOutTabIDs = [survivor.id]
                    poppedOutReason = prevReason
                    survivor.setAudioLevel(muted: false, volumePercent: 100)
                    presentSingleFloatingMiniPlayer(for: survivor)
                    applyConfigToAllTabs()
                } else {
                    dockMiniPlayer(selectTab: false, focusMain: false)
                    if let survivor = tabs.first(where: { $0.id == survivingID }), survivor.mediaStatus.hasVideo {
                        survivor.setAudioLevel(muted: false, volumePercent: 100)
                    }
                    applyConfigToAllTabs()
                }
                return
            }
            exitMultiview(focusTabID: survivingID, showFeedback: true)
            return
        }

        multiviewTabIDs = result.state.tabIDs
        multiviewAudioTabID = result.state.audioTabID
        soloMultiviewTabID = result.state.soloTabID
        multiviewCustomVolumes = MultiviewAudioMixer.sanitizedCustomVolumes(
            multiviewCustomVolumes,
            keeping: Set(result.state.tabIDs)
        )
        if hoveredMultiviewTileID == id {
            hoveredMultiviewTileID = nil
        }
        if selectedTabID == id {
            selectedTabID = result.state.audioTabID ?? result.state.tabIDs.first ?? selectedTabID
            syncOmniboxToSelectedTab()
        }
        if wasFloatingGrid {
            poppedOutTabIDs = multiviewTabIDs
            syncFloatingMultiviewGrid()
        }
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: true)
        syncLivePulseStreamSignals()
    }

    // MARK: - Zero-Latency Multiview Solo & Live Stream Sync

    public func toggleMultiviewSolo(tabID: UUID? = nil) {
        guard isMultiviewActive, !hasLiveFullscreenTab else { return }
        if isFloatingMultiviewGrid {
            dockMiniPlayer(selectTab: false, focusMain: true)
        }
        let targetID = tabID ?? soloMultiviewTabID ?? multiviewAudioTabID ?? selectedTabID
        guard multiviewTabIDs.contains(targetID) else { return }

        let next = MultiviewReducer.toggleSolo(targetID, in: multiviewState)
        soloMultiviewTabID = next.soloTabID
        multiviewAudioTabID = next.audioTabID
        if let soloID = next.soloTabID {
            selectedTabID = soloID
            syncOmniboxToSelectedTab()
        }
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: next.soloTabID != nil)

        // Fire one-shot player viewport resize sync after layout updates so YouTube scrubbers match width.
        let tabsToSync: [BrowserTab] = {
            if let soloID = next.soloTabID, let tab = tabs.first(where: { $0.id == soloID }) {
                return [tab]
            }
            return multiviewTabs
        }()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            for tab in tabsToSync {
                tab.syncPlayerSize()
            }
        }

        if let soloID = next.soloTabID, let tab = tabs.first(where: { $0.id == soloID }) {
            showHUD(icon: "arrow.up.left.and.arrow.down.right", message: "Solo · \(tab.displayTitle)")
        } else {
            showHUD(icon: "square.grid.2x2", message: "Back to Multiview Grid")
        }
        syncLivePulseStreamSignals()
    }

    public func exitMultiviewSolo(showFeedback: Bool = true) {
        guard isMultiviewSoloActive, !hasLiveFullscreenTab else { return }
        soloMultiviewTabID = nil
        applyConfigToAllTabs()
        let currentTiles = multiviewTabs
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            for tab in currentTiles {
                tab.syncPlayerSize()
            }
        }
        if showFeedback {
            showHUD(icon: "square.grid.2x2", message: "Back to Multiview Grid")
        }
        syncLivePulseStreamSignals()
    }

    public func nudgeMultiviewTile(id: UUID, seconds: Double) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.seekBy(seconds: seconds)
        let sign = seconds >= 0 ? "+" : ""
        let formatted = seconds.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(seconds))" : String(format: "%.1f", seconds)
        showHUD(icon: "clock.arrow.2.circlepath", message: "Sync \(sign)\(formatted)s")
    }

    public func jumpMultiviewTileToLive(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.seekToLiveEdge()
        showHUD(icon: "dot.radiowaves.left.and.right", message: "Jumped to Live Edge")
    }

    // MARK: - Streaming Service Onboarding, Launcher & Per-Service Reset

    public func presentStreamingOnboardingIfNeeded() {
        guard isPrimaryWindow,
              !settings.hasCompletedStreamingOnboarding,
              !hasLiveFullscreenTab,
              !isMiniPlayer,
              coordinator?.hasAutoPresentedOnboardingThisSession == false else {
            return
        }
        coordinator?.hasAutoPresentedOnboardingThisSession = true
        onboardingInitialStep = 1
        onboardingFocusServiceID = nil
        isOnboardingPresented = true
    }

    public func openStreamingServicesSetup(step: Int = 1, focusServiceID: String? = nil) {
        guard !hasLiveFullscreenTab else { return }
        onboardingInitialStep = min(max(step, 1), 2)
        onboardingFocusServiceID = focusServiceID
        isOnboardingPresented = true
    }

    public func completeStreamingOnboarding() {
        settings.hasCompletedStreamingOnboarding = true
        isOnboardingPresented = false
        onboardingFocusServiceID = nil
    }

    public func skipStreamingOnboarding() {
        settings.hasCompletedStreamingOnboarding = true
        isOnboardingPresented = false
        onboardingFocusServiceID = nil
    }

    public func openStreamingService(_ service: StreamingService, inNewTab: Bool = false) {
        guard !hasLiveFullscreenTab else { return }
        if isMultiviewActive {
            if canAddMultiviewTile {
                addStreamingServiceToMultiview(service)
            } else {
                createTab(url: service.homeURL, select: true, routingMode: service.routingMode)
            }
            return
        }
        if inNewTab {
            createTab(url: service.homeURL, select: true, routingMode: service.routingMode)
        } else if let tab = selectedTab, tab.routingMode == service.routingMode {
            tab.load(service.homeURL)
            syncOmniboxToSelectedTab()
        } else {
            createTab(url: service.homeURL, select: true, routingMode: service.routingMode)
        }
    }

    public func addStreamingServiceToMultiview(_ service: StreamingService) {
        guard !hasLiveFullscreenTab else { return }
        if isMultiviewSoloActive {
            soloMultiviewTabID = nil
        }
        addTileToMultiview(url: service.homeURL, routingMode: service.routingMode)
    }

    // MARK: - Unified `+` Picker Routing Helpers

    public func openServiceFromPicker(_ service: StreamingService, addToGrid: Bool) {
        if hasLiveFullscreenTab {
            createTab(url: service.homeURL, select: false, routingMode: service.routingMode)
            showHUD(icon: "plus.square", message: "Opened \(service.name) Tab")
            return
        }
        if addToGrid {
            if isMultiviewActive && !canAddMultiviewTile {
                createTab(url: service.homeURL, select: true, routingMode: service.routingMode)
                return
            }
            if isMultiviewSoloActive {
                soloMultiviewTabID = nil
            }
            addStreamingServiceToMultiview(service)
        } else if isMultiviewActive {
            createTab(url: service.homeURL, select: false, routingMode: service.routingMode)
            showHUD(icon: "plus.square", message: "Opened \(service.name) Tab")
        } else {
            openStreamingService(service, inNewTab: true)
        }
    }

    public func openURLFromPicker(_ url: URL, routingMode: TabRoutingMode? = nil, addToGrid: Bool) {
        let targetURL = settings.redirectShortsToWatch
            ? (YouTubeURLRouter.rewriteShortsURL(url) ?? url)
            : url
        let resolvedMode = routingMode ?? YouTubeURLRouter.preferredRoutingMode(for: targetURL)

        if hasLiveFullscreenTab {
            createTab(url: targetURL, select: false, routingMode: resolvedMode)
            showHUD(icon: "plus.square", message: "Opened in New Tab")
            return
        }
        if addToGrid {
            if isMultiviewActive && !canAddMultiviewTile {
                createTab(url: targetURL, select: true, routingMode: resolvedMode)
                return
            }
            if isMultiviewSoloActive {
                soloMultiviewTabID = nil
            }
            addTileToMultiview(url: targetURL, routingMode: resolvedMode)
        } else if isMultiviewActive {
            createTab(url: targetURL, select: false, routingMode: resolvedMode)
            showHUD(icon: "plus.square", message: "Opened in New Tab")
        } else {
            createTab(url: targetURL, select: true, routingMode: resolvedMode)
        }
    }

    @discardableResult
    public func openRawInputFromPicker(_ rawInput: String, addToGrid: Bool) -> Bool {
        if let ytURL = YouTubeURLRouter.extractYouTubeURLFromString(rawInput) {
            openURLFromPicker(ytURL, routingMode: .youtube, addToGrid: addToGrid)
            return true
        }
        guard let webURL = YouTubeURLRouter.resolveCompanionURL(rawInput) else {
            showHUD(icon: "exclamationmark.triangle", message: "Enter a Valid Website or HTTPS URL")
            return false
        }
        openURLFromPicker(webURL, routingMode: .companion, addToGrid: addToGrid)
        return true
    }

    public func openNewYouTubeTabFromPicker(addToGrid: Bool) {
        openURLFromPicker(settings.startupDestination.url, routingMode: .youtube, addToGrid: addToGrid)
    }

    public func openPinnedItemFromPicker(_ item: PinnedItem, addToGrid: Bool) {
        guard let url = item.url else { return }
        let mode = YouTubeURLRouter.preferredRoutingMode(for: url)
        openURLFromPicker(url, routingMode: mode, addToGrid: addToGrid)
    }

    public func openURLInSafari(_ url: URL?) {
        guard let url else { return }
        let safariURL = URL(fileURLWithPath: "/Applications/Safari.app")
        if FileManager.default.fileExists(atPath: safariURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    public func resetStreamingServiceDataAndWait(_ service: StreamingService) async {
        await coordinator?.resetServiceData(for: service)
    }

    public func resetStreamingServiceData(_ service: StreamingService) {
        Task { @MainActor [weak self] in
            await self?.resetStreamingServiceDataAndWait(service)
        }
    }

    public func cancelSignInCheckTasks(forServiceID serviceID: String? = nil) {
        if let serviceID {
            let matchingTabIDs = signInCheckServiceIDs.compactMap { $0.value == serviceID ? $0.key : nil }
            for tabID in matchingTabIDs {
                signInCheckTasks[tabID]?.cancel()
                signInCheckTasks.removeValue(forKey: tabID)
                signInCheckServiceIDs.removeValue(forKey: tabID)
            }
        } else {
            for (_, task) in signInCheckTasks {
                task.cancel()
            }
            signInCheckTasks.removeAll()
            signInCheckServiceIDs.removeAll()
        }
    }

    @discardableResult
    public func evaluateSignInCompletion(
        for service: StreamingService,
        url: URL?,
        fromAuthFlow: Bool,
        refreshIdleTabsOnNewSignIn: Bool = false,
        excludingTabID: UUID? = nil
    ) async -> Bool {
        guard StreamingServiceCatalog.isLikelySignedInNavigation(url: url, for: service) else {
            return false
        }

        let resetGen = coordinator?.resetGeneration(for: service.id) ?? 0
        let now = Date()
        let rawCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        guard !Task.isCancelled, (coordinator?.resetGeneration(for: service.id) ?? 0) == resetGen else {
            return false
        }

        let entries: [(name: String, domain: String)] = rawCookies.compactMap { cookie in
            if let expires = cookie.expiresDate, expires <= now {
                return nil
            }
            return (name: cookie.name, domain: cookie.domain)
        }

        let isSignedIn: Bool
        if let cookieVerdict = StreamingServiceCatalog.hasAuthenticatedSessionCookie(cookieEntries: entries, for: service) {
            isSignedIn = cookieVerdict
        } else {
            isSignedIn = fromAuthFlow
        }

        guard isSignedIn else { return false }

        let wasSignedIn = settings.isServiceSignedIn(service.id)
        settings.setServiceSignedIn(service.id, signedIn: true)
        if !wasSignedIn && refreshIdleTabsOnNewSignIn {
            coordinator?.refreshIdleTabs(for: service, excludingTabID: excludingTabID)
        }
        return true
    }

    private func handleTabDidFinishNavigation(tabID: UUID, url: URL) {
        scheduleSignInCompletionCheck(for: tabID, url: url, requireAuthFlowForNonPrime: false)
        syncLivePulseStreamSignals()
    }

    private func scheduleSignInCompletionCheck(for tabID: UUID, url: URL, requireAuthFlowForNonPrime: Bool) {
        guard !isWindowTornDown,
              let tab = tabs.first(where: { $0.id == tabID }),
              !tab.isSleeping,
              tab.pendingLazyURL == nil,
              let service = StreamingServiceCatalog.service(matchingURL: url) else {
            return
        }
        let fromAuthFlow = (tab.authFlowServiceID == service.id)
        if requireAuthFlowForNonPrime {
            guard fromAuthFlow else { return }
        } else {
            guard fromAuthFlow || service.id == "primevideo" else { return }
        }

        signInCheckTasks[tabID]?.cancel()
        signInCheckServiceIDs[tabID] = service.id
        signInCheckTasks[tabID] = Task { @MainActor [weak self, weak tab] in
            guard let self, let tab else { return }
            let confirmed = await self.evaluateSignInCompletion(
                for: service,
                url: url,
                fromAuthFlow: fromAuthFlow,
                refreshIdleTabsOnNewSignIn: fromAuthFlow,
                excludingTabID: tabID
            )
            guard !Task.isCancelled else { return }
            self.signInCheckTasks.removeValue(forKey: tabID)
            self.signInCheckServiceIDs.removeValue(forKey: tabID)
            if confirmed && tab.authFlowServiceID == service.id {
                tab.authFlowServiceID = nil
            }
        }
    }

    // MARK: - Native macOS AirPlay Video, Audio & TV Display Routing

    public var isAirPlayActive: Bool {
        nowPlayingStatus.isAirPlayActive || (coordinator?.isAirPlayAudioActive ?? false)
    }

    public var currentDisplayID: UInt32? {
        guard let screen = mainWindow?.screen ?? NSScreen.main else { return nil }
        return AppCoordinator.displayID(for: screen)
    }

    public func openAirPlayPopover() {
        guard !hasLiveFullscreenTab else { return }
        airPlayVideoHint = nil
        coordinator?.refreshConnectedDisplays()
        coordinator?.refreshAudioOutputStatus()
        isAirPlayPopoverPresented = true
    }

    public func triggerAirPlayVideo() {
        guard !isMultiviewActive else {
            airPlayVideoHint = "Multiview streams cast best via Send Window to Display below."
            showHUD(icon: "airplayvideo", message: "Use AirPlay Display below for Multiview")
            return
        }
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else {
            airPlayVideoHint = nil
            showHUD(icon: "airplayvideo", message: "Start a video to stream via AirPlay")
            return
        }

        Task { @MainActor [weak self, weak tab] in
            guard let self, let tab else { return }
            let result = await tab.showAirPlayPicker()
            self.handleAirPlayPickerResult(result)
        }
    }

    public func handleAirPlayPickerResult(_ result: AirPlayPickerResult) {
        switch result {
        case .ok:
            airPlayVideoHint = nil
        case .mseUnsupported:
            airPlayVideoHint = "YouTube MSE streams cast best via AirPlay Display below."
            showHUD(icon: "airplayvideo", message: "YouTube MSE casts best via AirPlay Display")
        case .unavailable:
            airPlayVideoHint = "Direct video AirPlay unavailable on this stream — use AirPlay Display below."
            showHUD(icon: "airplayvideo", message: "Use AirPlay Display below to cast to TV")
        case .noVideo:
            airPlayVideoHint = nil
            showHUD(icon: "airplayvideo", message: "Start a video to stream via AirPlay")
        }
    }

    public func moveWindowToDisplay(id: UInt32) {
        // Hard invariant: never move or resize the NSWindow while any tab is in WebKit fullscreen.
        guard !hasLiveFullscreenTab, let window = mainWindow else { return }
        if isFloatingMultiviewGrid {
            dockMiniPlayer(selectTab: false, focusMain: false)
        }
        coordinator?.refreshConnectedDisplays()
        guard let display = coordinator?.connectedDisplays.first(where: { $0.id == id }) else { return }

        let targetFrame = WindowDisplayRouter.targetFrame(
            currentFrame: window.frame,
            targetVisibleFrame: display.visibleFrame,
            maximizeForTV: true
        )
        window.setFrame(targetFrame, display: true, animate: true)
        window.makeKeyAndOrderFront(nil)
        showHUD(icon: "appletv", message: "Moved to \(display.name)")
    }

    public func promoteMultiviewTileToPrimary(id: UUID) {
        guard isMultiviewActive, multiviewTabIDs.contains(id) else { return }
        let next = MultiviewReducer.promoteToPrimary(id, in: multiviewState, transferAudio: true)
        multiviewTabIDs = next.tabIDs
        multiviewAudioTabID = next.audioTabID
        selectedTabID = id
        syncOmniboxToSelectedTab()
        if isFloatingMultiviewGrid {
            poppedOutTabIDs = multiviewTabIDs
            syncFloatingMultiviewGrid()
        }
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: true)
        showHUD(icon: "arrow.up.left.and.arrow.down.right", message: "Promoted to Main Tile")
    }

    public func moveMultiviewTile(id: UUID, by delta: Int) {
        guard isMultiviewActive, !hasLiveFullscreenTab, multiviewTabIDs.contains(id) else { return }
        let next = MultiviewReducer.moveTile(id, by: delta, in: multiviewState)
        guard next.tabIDs != multiviewTabIDs else { return }
        multiviewTabIDs = next.tabIDs
        if isFloatingMultiviewGrid {
            poppedOutTabIDs = multiviewTabIDs
            syncFloatingMultiviewGrid()
        }
        applyConfigToAllTabs()
    }

    public func effectiveMultiviewVolume(for tabID: UUID) -> MultiviewAudioLevel {
        MultiviewAudioMixer.effectiveLevel(
            for: tabID,
            activeAudioTabID: multiviewAudioTabID ?? multiviewTabIDs.first,
            duckBackground: settings.multiviewAudioDuckingEnabled,
            customVolumes: multiviewCustomVolumes,
            singleTabMode: false
        )
    }

    public func setMultiviewTileVolume(tabID: UUID, volumePercent: Int) {
        guard isMultiviewActive,
              multiviewTabIDs.contains(tabID),
              !hasLiveFullscreenTab,
              !floatingMiniPlayer.hasLiveFullscreenTab,
              let tab = tabs.first(where: { $0.id == tabID }) else {
            return
        }
        let clamped = MultiviewAudioMixer.clampVolume(volumePercent)
        guard multiviewCustomVolumes[tabID] != clamped else { return }

        multiviewCustomVolumes[tabID] = clamped
        lastMultiviewAudioSwitchAt = Date()
        let level = MultiviewAudioMixer.levelForSliderChange(clamped)
        tab.applyOptimisticAudioLevel(muted: level.muted, volumePercent: level.volumePercent)

        multiviewVolumeDispatchTasks[tabID]?.cancel()
        multiviewVolumeDispatchTasks[tabID] = Task { @MainActor [weak self, weak tab] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled,
                  let self,
                  !self.isWindowTornDown,
                  self.isMultiviewActive,
                  self.multiviewTabIDs.contains(tabID),
                  let tab else {
                return
            }
            self.multiviewVolumeDispatchTasks.removeValue(forKey: tabID)
            self.lastMultiviewAudioSwitchAt = Date()
            tab.setAudioLevel(muted: level.muted, volumePercent: level.volumePercent)
        }
        syncFloatingMultiviewGrid()
    }

    public func resetMultiviewMixer(showFeedback: Bool = true) {
        cancelAllMultiviewVolumeDispatchTasks()
        multiviewCustomVolumes.removeAll()
        if isMultiviewActive {
            applyMultiviewAudioFocus(unmuteAudioTab: true)
        }
        syncFloatingMultiviewGrid()
        if showFeedback {
            showHUD(icon: "slider.horizontal.3", message: "Multiview Mixer Reset")
        }
    }

    private func cancelAllMultiviewVolumeDispatchTasks() {
        for (_, task) in multiviewVolumeDispatchTasks {
            task.cancel()
        }
        multiviewVolumeDispatchTasks.removeAll()
    }

    public func focusMultiviewAudio(tabID: UUID, showFeedback: Bool = true) {
        guard isMultiviewActive, multiviewTabIDs.contains(tabID) else { return }
        if multiviewCustomVolumes[tabID] == 0 {
            multiviewVolumeDispatchTasks[tabID]?.cancel()
            multiviewVolumeDispatchTasks.removeValue(forKey: tabID)
            multiviewCustomVolumes.removeValue(forKey: tabID)
        }
        let next = MultiviewReducer.focusAudio(tabID, in: multiviewState)
        multiviewAudioTabID = next.audioTabID
        selectedTabID = tabID
        syncOmniboxToSelectedTab()
        applyMultiviewAudioFocus(unmuteAudioTab: true)
        if showFeedback, let slot = multiviewSlotNumber(for: tabID) {
            let title = tabs.first(where: { $0.id == tabID })?.displayTitle ?? "Stream \(slot)"
            showHUD(icon: "speaker.wave.2.fill", message: "Audio \(slot) · \(title)")
        }
        syncLivePulseStreamSignals()
    }

    public func focusMultiviewAudio(slot oneBasedSlot: Int) {
        let index = oneBasedSlot - 1
        guard isMultiviewActive, multiviewTabIDs.indices.contains(index) else { return }
        focusMultiviewAudio(tabID: multiviewTabIDs[index], showFeedback: true)
    }

    public func cycleMultiviewAudioFocus(by delta: Int) {
        guard isMultiviewActive else { return }
        let next = MultiviewReducer.cycleAudioFocus(by: delta, in: multiviewState)
        if let audioID = next.audioTabID {
            focusMultiviewAudio(tabID: audioID, showFeedback: true)
        }
    }

    public func muteAllMultiviewTiles() {
        guard isMultiviewActive else { return }
        cancelAllMultiviewVolumeDispatchTasks()
        multiviewCustomVolumes.removeAll()
        lastMultiviewAudioSwitchAt = Date()
        for tab in multiviewTabs {
            tab.setAudioLevel(muted: true, volumePercent: 100)
        }
        syncFloatingMultiviewGrid()
        showHUD(icon: "speaker.slash.fill", message: "All Streams Muted")
    }

    public func navigateMultiviewTileToBrowse(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = id
        tab.isCleanBoxBypassed = false
        let destination: URL
        if YouTubeURLRouter.isYouTubeTVHost(tab.url.host), let yttvLive = URL(string: "https://tv.youtube.com/live") {
            destination = yttvLive
        } else if let service = StreamingServiceCatalog.service(matchingURL: tab.url) {
            destination = service.homeURL
        } else {
            destination = SidebarDestination.home.url
        }
        tab.load(destination)
        syncOmniboxToSelectedTab()
    }

    public func setHoveredMultiviewTile(_ tabID: UUID?) {
        if hoveredMultiviewTileID != tabID {
            hoveredMultiviewTileID = tabID
        }
    }

    private func applyMultiviewAudioFocus(unmuteAudioTab: Bool) {
        guard isMultiviewActive else { return }
        lastMultiviewAudioSwitchAt = Date()
        let activeAudioID = multiviewAudioTabID ?? multiviewTabIDs.first
        multiviewAudioTabID = activeAudioID
        let duckBackground = settings.multiviewAudioDuckingEnabled
        for tab in multiviewTabs {
            if tab.id == activeAudioID && !unmuteAudioTab && multiviewCustomVolumes[tab.id] == nil {
                continue
            }
            multiviewVolumeDispatchTasks[tab.id]?.cancel()
            multiviewVolumeDispatchTasks.removeValue(forKey: tab.id)
            let level = MultiviewAudioMixer.effectiveLevel(
                for: tab.id,
                activeAudioTabID: activeAudioID,
                duckBackground: duckBackground,
                customVolumes: multiviewCustomVolumes,
                singleTabMode: false
            )
            tab.setAudioLevel(muted: level.muted, volumePercent: level.volumePercent)
        }
        if isFloatingMultiviewGrid {
            syncFloatingMultiviewGrid()
        }
    }

    private func restoreSidebarAfterMultiviewIfNeeded() {
        let shouldRestore = sidebarVisibleBeforeMultiview == true
        sidebarVisibleBeforeMultiview = nil
        if shouldRestore && !isSidebarVisible {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                isSidebarVisible = true
            }
        }
    }

    private func handleTileClicked(tabID: UUID) {
        guard isMultiviewActive, multiviewTabIDs.contains(tabID) else { return }
        if selectedTabID != tabID {
            selectedTabID = tabID
            syncOmniboxToSelectedTab()
        }
        // Silent Companion web tiles (e.g. ESPN scoreboards without <video>) never steal audio focus from an active stream.
        if let clickedTab = tabs.first(where: { $0.id == tabID }),
           clickedTab.isCompanionTab && !clickedTab.mediaStatus.hasVideo {
            return
        }
        if tabID != multiviewAudioTabID {
            focusMultiviewAudio(tabID: tabID, showFeedback: false)
        }
    }

    private func handleTabUnmutedByUser(tabID: UUID) {
        guard isMultiviewActive,
              multiviewTabIDs.contains(tabID),
              tabID != multiviewAudioTabID,
              Date().timeIntervalSince(lastMultiviewAudioSwitchAt) > 0.5 else {
            return
        }
        focusMultiviewAudio(tabID: tabID, showFeedback: false)
    }

    private func handleTabFullscreenDidChange(tabID: UUID, isInFullscreen: Bool) {
        if isInFullscreen {
            if isFindBarPresented {
                dismissFindBar()
            }
            if isCommandPalettePresented {
                dismissCommandPalette(refocusWebView: false)
            }
        } else if !hasLiveFullscreenTab {
            syncCompactHeaderModeFromSettings()
        }
        guard isInFullscreen,
              isMultiviewActive,
              multiviewTabIDs.contains(tabID),
              tabID != multiviewAudioTabID else {
            return
        }
        // Transfer audio focus cleanly without mutating the view hierarchy while entering fullscreen.
        lastMultiviewAudioSwitchAt = Date()
        multiviewAudioTabID = tabID
        selectedTabID = tabID
        applyMultiviewAudioFocus(unmuteAudioTab: true)
    }

    // MARK: - Playback, Floating Pop-Up Mini-Player & Distraction-Free Controls

    public func togglePlayPause() {
        activeMediaTab?.togglePlayPause()
    }

    public func seek(by seconds: Double) {
        activeMediaTab?.seekBy(seconds: seconds)
    }

    /// Deterministically seeks the active media tab to an absolute timestamp, optimistically updating
    /// `PlaybackTimeline` so Menu Bar drag release never snaps backward before JS telemetry arrives.
    public func seek(to seconds: Double) {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return }
        let duration = tab.timeline.duration
        guard duration.isFinite, duration > 0, duration < 86400 else { return }
        let clamped = min(max(seconds.isFinite ? seconds : 0, 0), duration)
        tab.timeline.update(currentTime: clamped, duration: duration)
        tab.seekTo(seconds: clamped)
    }

    public func toggleMute(tabID: UUID? = nil) {
        if let tabID {
            guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
            // In Multiview, unmuting a non-audio tile transfers exclusive audio focus cleanly instead of creating two audible streams.
            if isMultiviewActive && multiviewTabIDs.contains(tabID) && tabID != multiviewAudioTabID {
                focusMultiviewAudio(tabID: tabID, showFeedback: false)
                return
            }
            if isMultiviewActive && multiviewTabIDs.contains(tabID) && multiviewCustomVolumes[tabID] == 0 {
                multiviewVolumeDispatchTasks[tabID]?.cancel()
                multiviewVolumeDispatchTasks.removeValue(forKey: tabID)
                multiviewCustomVolumes.removeValue(forKey: tabID)
                applyMultiviewAudioFocus(unmuteAudioTab: true)
                return
            }
            tab.toggleMute()
            return
        }
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return }
        let willMute = !tab.mediaStatus.isMuted
        tab.toggleMute()
        showHUD(icon: willMute ? "speaker.slash.fill" : "speaker.wave.2.fill", message: willMute ? "Muted" : "Unmuted")
    }

    public func togglePictureInPicture() {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return }
        Task { @MainActor in
            _ = await tab.togglePictureInPicture()
        }
    }

    public func toggleTheaterMode() {
        activeMediaTab?.evaluate(EnhancementScript.toggleTheaterModeScript)
    }

    public func setPlaybackRate(_ rate: Double, showFeedback: Bool = true) {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return }
        let clamped = min(max(rate.isFinite ? rate : 1.0, 0.25), 4.0)
        tab.setPlaybackRate(clamped)
        if showFeedback {
            showHUD(icon: "gauge.with.dots.needle.67percent", message: "Speed \(MediaStatus.formatPlaybackRate(clamped))")
        }
    }

    public func toggleCleanBoxForActiveTab() {
        let targetID = isMultiviewActive ? (multiviewAudioTabID ?? selectedTabID) : selectedTabID
        toggleCleanBox(forTabID: targetID)
    }

    public func toggleCleanBox(forTabID tabID: UUID) {
        guard settings.cleanBoxStreamingPlayers,
              let tab = tabs.first(where: { $0.id == tabID }),
              tab.mediaStatus.isCleanBoxActive || tab.isCleanBoxBypassed else {
            return
        }
        tab.isCleanBoxBypassed.toggle()
        tab.applyConfig(configForTab(id: tab.id), force: true)
        showHUD(
            icon: tab.isCleanBoxBypassed ? "rectangle.inset.filled.and.person.filled" : "rectangle.inset.filled",
            message: tab.isCleanBoxBypassed ? "Showing Full Page" : "Clean-Box Video"
        )
    }

    public func stepPlaybackRate(by delta: Double) {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return }
        let current = tab.mediaStatus.playbackRate
        let stepped = ((current + delta) * 10).rounded() / 10
        let clamped = min(max(stepped, 0.25), 4.0)
        setPlaybackRate(clamped, showFeedback: true)
    }

    public func resetPlaybackRate() {
        setPlaybackRate(1.0, showFeedback: true)
    }

    public func toggleFocusMode() {
        focusModeActive.toggle()
        applyConfigToAllTabs()
        showHUD(
            icon: focusModeActive ? "eye.slash.fill" : "sparkles",
            message: focusModeActive ? "Focus Mode On" : "Focus Mode Off"
        )
    }

    public func setAppearance(_ appearance: AppAppearance, showFeedback: Bool = true) {
        let didChange = settings.appearance != appearance
        settings.appearance = appearance
        if showFeedback && didChange {
            switch appearance {
            case .dark:
                showHUD(icon: "moon.fill", message: "Night Mode")
            case .light:
                showHUD(icon: "sun.max.fill", message: "Day Mode")
            case .system:
                showHUD(icon: "circle.lefthalf.filled", message: "Match System")
            }
        }
    }

    public func toggleDayNightMode(currentColorScheme: ColorScheme? = nil) {
        let isCurrentlyDark: Bool
        switch settings.appearance {
        case .dark:
            isCurrentlyDark = true
        case .light:
            isCurrentlyDark = false
        case .system:
            if let currentColorScheme {
                isCurrentlyDark = (currentColorScheme == .dark)
            } else {
                isCurrentlyDark = settings.isEffectivelyDark
            }
        }
        setAppearance(isCurrentlyDark ? .light : .dark, showFeedback: true)
    }

    public func setHolidayThemeSelection(_ selection: HolidayThemeSelection, showFeedback: Bool = true) {
        settings.holidayThemeSelection = selection
        ThemeRuntime.shared.apply(palette: settings.activeHolidayPalette)
        if showFeedback {
            let palette = settings.activeHolidayPalette
            switch selection {
            case .auto:
                let suffix = palette.id == .classic ? "Classic" : palette.shortName
                showHUD(icon: palette.symbolName, message: "Holiday Theme: Auto (\(suffix))")
            case .classic:
                showHUD(icon: "paintpalette", message: "Holiday Theme: Classic Crimson")
            default:
                showHUD(icon: palette.symbolName, message: "Holiday Theme: \(palette.displayName)")
            }
        }
    }

    public func setHolidayEffectsIntensity(_ intensity: HolidayEffectsIntensity, showFeedback: Bool = true) {
        settings.holidayEffectsIntensity = intensity
        if showFeedback {
            let palette = settings.activeHolidayPalette
            let icon = intensity == .off ? "sparkles.slash" : (palette.id == .classic ? "sparkles" : palette.symbolName)
            let message: String
            switch intensity {
            case .off:
                message = "Ambient Effects: Off"
            case .subtle:
                message = "Ambient Effects: Subtle"
            case .festive:
                message = "Ambient Effects: Festive"
            }
            showHUD(icon: icon, message: message)
        }
    }

    public func toggleHolidayEffects() {
        let next: HolidayEffectsIntensity = settings.holidayEffectsIntensity == .off ? .subtle : .off
        setHolidayEffectsIntensity(next, showFeedback: true)
    }

    public func cycleHolidayTheme() {
        let all = HolidayThemeSelection.allCases
        guard let idx = all.firstIndex(of: settings.holidayThemeSelection) else {
            setHolidayThemeSelection(.auto, showFeedback: true)
            return
        }
        let next = all[(idx + 1) % all.count]
        setHolidayThemeSelection(next, showFeedback: true)
    }

    public func toggleAlwaysOnTop() {
        alwaysOnTop.toggle()
        applyWindowLevelAndCollectionBehavior()
    }

    public func canPopOut(tab: BrowserTab) -> Bool {
        guard !StreamingServiceCatalog.isTransientAuthURL(tab.url) else { return false }
        let isCompanionWatch = tab.isCompanionTab && CleanBoxRules.classifyRoute(tab.url) == .watch
        guard tab.mediaStatus.hasVideo || isCompanionWatch else { return false }
        guard YouTubeURLRouter.isWatchURL(tab.url) || tab.isCompanionTab else { return false }
        guard !tab.isInFullscreen && tab.webView.fullscreenState == .notInFullscreen else { return false }
        return true
    }

    public func toggleMiniPlayer() {
        if isMiniPlayer {
            dockMiniPlayer(selectTab: true, focusMain: true)
            return
        }
        popOutActiveContentToMiniPlayer(reason: .manual)
    }

    @discardableResult
    public func popOutActiveContentToMiniPlayer(reason: PopOutReason) -> Bool {
        guard !hasLiveFullscreenTab else { return false }
        if isMultiviewActive {
            return popOutMultiviewToMiniPlayer(reason: reason)
        }
        if let selected = selectedTab, canPopOut(tab: selected) {
            return popOutToMiniPlayer(tab: selected, reason: reason)
        }
        guard let targetTab = activeMediaTab, canPopOut(tab: targetTab) else {
            return false
        }
        return popOutToMiniPlayer(tab: targetTab, reason: reason)
    }

    @discardableResult
    public func popOutToMiniPlayer(tab: BrowserTab, reason: PopOutReason) -> Bool {
        guard canPopOut(tab: tab), !hasLiveFullscreenTab else {
            return false
        }

        // Always exit Multiview cleanly before floating a single video so hybrid Multiview + Mini-Player states cannot occur.
        if isMultiviewActive {
            exitMultiview(focusTabID: tab.id, showFeedback: false)
        }

        if isMiniPlayer && (isFloatingMultiviewGrid || poppedOutTabID != tab.id) {
            dockMiniPlayer(selectTab: false, focusMain: false)
        }

        if let coordinator, !coordinator.prepareMiniPlayerOwnership(for: windowID) {
            return false
        }

        tab.needsPostAttachResize = false
        tab.cancelPostAttachResize()
        if tab.isCleanBoxBypassed {
            tab.isCleanBoxBypassed = false
        }
        poppedOutTabIDs = [tab.id]
        poppedOutReason = reason
        presentSingleFloatingMiniPlayer(for: tab)
        tab.applyConfig(configForTab(id: tab.id), force: true)
        return true
    }

    private func presentSingleFloatingMiniPlayer(for tab: BrowserTab) {
        floatingMiniPlayer.show(
            tab: tab,
            allSpaces: settings.miniPlayerAllSpaces,
            opacity: settings.miniPlayerOpacity,
            onSeek: { [weak tab] seconds in
                tab?.seekBy(seconds: seconds)
            },
            onTogglePlay: { [weak tab] in
                tab?.togglePlayPause()
            },
            onToggleMute: { [weak tab] in
                tab?.toggleMute()
            },
            onSetPlaybackRate: { [weak tab] rate in
                tab?.setPlaybackRate(rate)
            },
            onAirPlayResult: { [weak self] result in
                self?.handleAirPlayPickerResult(result)
            },
            onOpenDisplaysSettings: { [weak self] in
                self?.coordinator?.openDisplaysSettings()
            },
            onDock: { [weak self] in
                self?.dockMiniPlayer(selectTab: true, focusMain: true)
            },
            onClose: { [weak self] in
                self?.closeMiniPlayerPopup()
            }
        )
    }

    @discardableResult
    public func popOutMultiviewToMiniPlayer(reason: PopOutReason) -> Bool {
        let gridTabs = multiviewTabs
        guard isMultiviewActive,
              gridTabs.count >= 2,
              !hasLiveFullscreenTab,
              !floatingMiniPlayer.hasLiveFullscreenTab,
              gridTabs.contains(where: { $0.mediaStatus.hasVideo }) else {
            return false
        }

        if isMiniPlayer && !isFloatingMultiviewGrid {
            dockMiniPlayer(selectTab: false, focusMain: false)
        }

        if let coordinator, !coordinator.prepareMiniPlayerOwnership(for: windowID) {
            return false
        }

        soloMultiviewTabID = nil
        hoveredMultiviewTileID = nil
        hoveredMultiviewDividerID = nil
        activeMultiviewDividerDragID = nil

        for tab in gridTabs {
            tab.needsPostAttachResize = false
            tab.cancelPostAttachResize()
            if tab.isCleanBoxBypassed {
                tab.isCleanBoxBypassed = false
            }
        }

        poppedOutTabIDs = multiviewTabIDs
        poppedOutReason = reason

        let tileVolumes = gridTabs.reduce(into: [UUID: Int]()) {
            $0[$1.id] = effectiveMultiviewVolume(for: $1.id).volumePercent
        }
        floatingMiniPlayer.showGrid(
            tabs: gridTabs,
            audioTabID: multiviewAudioTabID ?? gridTabs.first?.id,
            layoutMode: multiviewLayoutMode,
            splitRatios: multiviewSplitRatios,
            allSpaces: settings.miniPlayerAllSpaces,
            opacity: settings.miniPlayerOpacity,
            tileVolumes: tileVolumes,
            hasCustomMix: hasCustomMultiviewMix,
            onFocusAudio: { [weak self] tabID in
                self?.focusMultiviewAudio(tabID: tabID, showFeedback: false)
            },
            onCycleLayout: { [weak self] in
                self?.cycleMultiviewLayoutMode()
            },
            onSelectLayout: { [weak self] mode in
                self?.setMultiviewLayoutMode(mode, showFeedback: true)
            },
            onToggleMuteAll: { [weak self] in
                self?.toggleMuteAllFromFloatingGrid()
            },
            onTogglePlayActive: { [weak self] in
                self?.multiviewAudioTab?.togglePlayPause()
            },
            onPlayAll: { [weak self] in
                guard let self else { return }
                for tab in self.multiviewTabs { tab.playMedia() }
            },
            onPauseAll: { [weak self] in
                guard let self else { return }
                for tab in self.multiviewTabs { tab.pauseMedia() }
            },
            onSetTileVolume: { [weak self] tabID, percent in
                self?.setMultiviewTileVolume(tabID: tabID, volumePercent: percent)
            },
            onResetMixer: { [weak self] in
                self?.resetMultiviewMixer(showFeedback: true)
            },
            onDock: { [weak self] in
                self?.dockMiniPlayer(selectTab: true, focusMain: true)
            },
            onClose: { [weak self] in
                self?.closeMiniPlayerPopup()
            }
        )
        applyConfigToAllTabs()
        return true
    }

    func syncFloatingMultiviewGrid() {
        guard isFloatingMultiviewGrid,
              !hasLiveFullscreenTab,
              !floatingMiniPlayer.hasLiveFullscreenTab else {
            return
        }
        let gridTabs = multiviewTabs
        guard gridTabs.count >= 2 else { return }
        let tileVolumes = gridTabs.reduce(into: [UUID: Int]()) {
            $0[$1.id] = effectiveMultiviewVolume(for: $1.id).volumePercent
        }
        floatingMiniPlayer.syncGrid(
            tabs: gridTabs,
            audioTabID: multiviewAudioTabID ?? gridTabs.first?.id,
            layoutMode: multiviewLayoutMode,
            splitRatios: multiviewSplitRatios,
            tileVolumes: tileVolumes,
            hasCustomMix: hasCustomMultiviewMix
        )
    }

    private func toggleMuteAllFromFloatingGrid() {
        guard isMultiviewActive else { return }
        let currentlyAllMuted = multiviewTabs.allSatisfy { !$0.mediaStatus.hasVideo || $0.mediaStatus.isMuted }
        if currentlyAllMuted {
            applyMultiviewAudioFocus(unmuteAudioTab: true)
        } else {
            muteAllMultiviewTiles()
        }
    }

    public func applyFloatingMiniPlayerSizePreset(_ rawPreset: String) {
        if isFloatingMultiviewGrid, let preset = MiniPlayerGridSizePreset(rawValue: rawPreset) {
            floatingMiniPlayer.applyGridSizePreset(preset)
        } else if isMiniPlayer, let preset = MiniPlayerSizePreset(rawValue: rawPreset) {
            floatingMiniPlayer.applySizePreset(preset)
        }
    }

    public func dockMiniPlayer(selectTab: Bool = true, focusMain: Bool = false) {
        guard isMiniPlayer else { return }
        guard !hasLiveFullscreenTab, !floatingMiniPlayer.hasLiveFullscreenTab else { return }

        let returningIDs = poppedOutTabIDs
        let wasGrid = returningIDs.count >= 2
        let detachedTabs = floatingMiniPlayer.detachAndHide()
        poppedOutTabIDs = []
        poppedOutReason = nil
        coordinator?.releaseMiniPlayerOwnership(for: windowID)

        let detachedByID = Dictionary(uniqueKeysWithValues: detachedTabs.map { ($0.id, $0) })
        for tabID in returningIDs {
            if let tab = detachedByID[tabID] ?? tabs.first(where: { $0.id == tabID }) {
                tab.needsPostAttachResize = true
                tab.applyConfig(configForTab(id: tab.id), force: true)
            }
        }

        if selectTab {
            if wasGrid {
                let focusID = (multiviewAudioTabID.flatMap { id in returningIDs.contains(id) ? id : nil })
                    ?? returningIDs.first
                if let focusID {
                    selectedTabID = focusID
                    syncOmniboxToSelectedTab()
                }
            } else if let firstID = returningIDs.first {
                selectedTabID = firstID
                syncOmniboxToSelectedTab()
            }
        }
        if focusMain {
            focusMainWindow()
        }
    }

    public func closeMiniPlayerPopup() {
        guard isMiniPlayer else { return }
        guard !hasLiveFullscreenTab, !floatingMiniPlayer.hasLiveFullscreenTab else { return }

        let closingIDs = poppedOutTabIDs
        let wasGrid = closingIDs.count >= 2
        let detachedTabs = floatingMiniPlayer.detachAndHide()
        poppedOutTabIDs = []
        poppedOutReason = nil
        coordinator?.releaseMiniPlayerOwnership(for: windowID)

        let detachedByID = Dictionary(uniqueKeysWithValues: detachedTabs.map { ($0.id, $0) })
        if wasGrid {
            for tabID in closingIDs {
                if let tab = detachedByID[tabID] ?? tabs.first(where: { $0.id == tabID }) {
                    tab.needsPostAttachResize = true
                    tab.pauseMedia()
                    tab.applyConfig(configForTab(id: tab.id), force: true)
                }
            }
        } else if let poppedID = closingIDs.first,
                  let tab = detachedByID[poppedID] ?? tabs.first(where: { $0.id == poppedID }) {
            tab.needsPostAttachResize = true
            tab.pauseMedia()
            tab.applyConfig(configForTab(id: tab.id), force: true)
            if tabs.count > 1 && selectedTabID != tab.id {
                closeTab(id: tab.id)
            }
        }
    }

    /// Re-evaluates whether the main window is actually occluded behind another app or on another Space
    /// when YouTube resigns active (keeping Split Screen / side-by-side windows docked).
    public func handleAppDidResignActive() {
        scheduleBackgroundOcclusionEvaluation(delayMilliseconds: 180)
    }

    /// Docks an app-switch auto-popped mini-player back into the main window when returning to YouTube,
    /// unless the user activated the app specifically by interacting with the floating Mini-Player panel.
    public func handleAppDidBecomeActive() {
        resignActiveTask?.cancel()
        resignActiveTask = nil

        if poppedOutReason == .leftApp {
            if floatingMiniPlayer.isInteractingWithPanel {
                return
            }
            let needsWindowReveal = !isMainWindowVisible || isMainWindowMiniaturized || (mainWindow?.isMiniaturized ?? false)
            dockMiniPlayer(selectTab: true, focusMain: needsWindowReveal)
        }
    }

    private func scheduleBackgroundOcclusionEvaluation(delayMilliseconds: Int = 180) {
        resignActiveTask?.cancel()
        resignActiveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            self.evaluateBackgroundOcclusionNow()
        }
    }

    private func evaluateBackgroundOcclusionNow() {
        // Ignore clicks inside our own Settings window, MenuBarExtra popover, or app menus.
        guard !NSApp.isActive else { return }
        guard !NSApp.isHidden else { return }
        guard !hasLiveFullscreenTab,
              coordinator?.hasAnyWindowInLiveFullscreen != true,
              !floatingMiniPlayer.hasLiveFullscreenTab else {
            return
        }
        guard let window = mainWindow,
              isMainWindowVisible,
              window.isVisible,
              !isMainWindowMiniaturized,
              !window.isMiniaturized else {
            return
        }

        let snapshot = captureMainWindowOcclusionSnapshot(for: window)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        if !isMiniPlayer {
            guard settings.autoMiniPlayerOnLeave else { return }
            if let coordinator,
               let ownerID = coordinator.floatingMiniPlayerOwnerWindowID,
               ownerID != windowID {
                return
            }
            if let coordinator,
               let activeID = coordinator.activeWindowID,
               activeID != windowID,
               let activeCtrl = coordinator.openWindows.first(where: { $0.windowID == activeID }),
               activeCtrl.nowPlayingStatus.isPlaying {
                return
            }

            let canAutoFloatMultiview = isMultiviewActive
                && multiviewTabs.contains(where: { $0.mediaStatus.isPlaying && !$0.mediaStatus.isPiP })
                && canPopOutMultiviewGrid
            let singleCandidate: BrowserTab? = isMultiviewActive
                ? nil
                : activeMediaTab.flatMap { shouldAutoPopOut(tab: $0) ? $0 : nil }
            guard canAutoFloatMultiview || singleCandidate != nil else {
                return
            }

            let isObstructed = WindowOcclusionCalculator.shouldAutoPopOutWhenInactive(
                isWindowVisible: true,
                isOnActiveSpace: snapshot.isOnActiveSpace,
                isOcclusionStateVisible: snapshot.isOcclusionStateVisible,
                targetBounds: snapshot.targetBounds,
                aboveWindows: snapshot.aboveWindows,
                ownPID: ownPID
            )
            if isObstructed {
                if canAutoFloatMultiview {
                    popOutMultiviewToMiniPlayer(reason: .leftApp)
                } else if let candidate = singleCandidate {
                    popOutToMiniPlayer(tab: candidate, reason: .leftApp)
                }
            }
        } else if poppedOutReason == .leftApp {
            guard !floatingMiniPlayer.isInteractingWithPanel else { return }
            let isUncovered = WindowOcclusionCalculator.shouldAutoDockWhenUncovered(
                isWindowVisible: true,
                isOnActiveSpace: snapshot.isOnActiveSpace,
                isOcclusionStateVisible: snapshot.isOcclusionStateVisible,
                targetBounds: snapshot.targetBounds,
                aboveWindows: snapshot.aboveWindows,
                ownPID: ownPID
            )
            if isUncovered {
                dockMiniPlayer(selectTab: true, focusMain: false)
            }
        }
    }

    private struct MainWindowOcclusionSnapshot {
        let isOnActiveSpace: Bool
        let isOcclusionStateVisible: Bool
        let targetBounds: CGRect
        let aboveWindows: [OccludingWindowDescriptor]
    }

    private func captureMainWindowOcclusionSnapshot(for window: NSWindow) -> MainWindowOcclusionSnapshot {
        let isOnActiveSpace = window.isOnActiveSpace
        let isOcclusionStateVisible = window.occlusionState.contains(.visible)
        let windowID = CGWindowID(max(0, window.windowNumber))

        // Query the main window's own CG bounds directly so both target and above-window rects share
        // the exact same CoreGraphics global coordinate space across single and multi-display layouts.
        var targetBounds: CGRect?
        if windowID != kCGNullWindowID,
           let selfList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
           let selfInfo = selfList.first,
           let boundsDict = selfInfo[kCGWindowBounds as String] as? NSDictionary {
            targetBounds = CGRect(dictionaryRepresentation: boundsDict)
        }
        let resolvedTargetBounds = targetBounds ?? fallbackCGBounds(for: window.frame)

        var aboveWindows: [OccludingWindowDescriptor] = []
        if isOnActiveSpace,
           isOcclusionStateVisible,
           windowID != kCGNullWindowID,
           let rawAbove = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], windowID) as? [[String: Any]] {
            aboveWindows.reserveCapacity(rawAbove.count)
            for info in rawAbove {
                guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                    continue
                }
                let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
                let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
                let isOnscreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
                aboveWindows.append(
                    OccludingWindowDescriptor(
                        ownerPID: ownerPID,
                        layer: layer,
                        alpha: alpha,
                        isOnscreen: isOnscreen,
                        bounds: bounds
                    )
                )
            }
        }

        return MainWindowOcclusionSnapshot(
            isOnActiveSpace: isOnActiveSpace,
            isOcclusionStateVisible: isOcclusionStateVisible,
            targetBounds: resolvedTargetBounds,
            aboveWindows: aboveWindows
        )
    }

    private func fallbackCGBounds(for appKitFrame: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? appKitFrame.maxY
        return CGRect(
            x: appKitFrame.origin.x,
            y: primaryHeight - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    public func toggleSidebar() {
        // Respect manual sidebar changes made during Multiview or Live Drawer so exiting won't revert them.
        sidebarVisibleBeforeMultiview = nil
        sidebarVisibleBeforeLiveDrawer = nil

        let openingSidebar = !isSidebarVisible
        if openingSidebar,
           isLivePulseDrawerVisible,
           LivePulseLayout.shouldAutoCollapseSidebar(windowWidth: windowContentWidth) {
            guard !hasLiveFullscreenTab else { return }
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                isLivePulseDrawerVisible = false
            }
            settings.livePulseShowDrawer = false
            coordinator?.livePulseStore.reconcileLifecycle()
        }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            isSidebarVisible.toggle()
        }
        settings.isSidebarVisible = isSidebarVisible
    }

    public func toggleCompactHeaderMode() {
        setCompactHeaderMode(!isCompactHeaderActive)
    }

    public func setCompactHeaderMode(_ enabled: Bool) {
        guard !hasLiveFullscreenTab else { return }
        let changed = (isCompactHeaderActive != enabled) || (settings.compactHeaderMode != enabled)
        guard changed else { return }
        if isCompactHeaderActive != enabled {
            withAnimation(.snappy(duration: 0.20, extraBounce: 0)) {
                isCompactHeaderActive = enabled
            }
        }
        settings.compactHeaderMode = enabled
        coordinator?.livePulseStore.reconcileLifecycle()
        showHUD(
            icon: enabled ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
            message: enabled ? "Compact Single-Row Header" : "Expanded Header Bars"
        )
    }

    public func syncCompactHeaderModeFromSettings() {
        guard !hasLiveFullscreenTab else { return }
        let wantCompact = settings.compactHeaderMode
        if isCompactHeaderActive != wantCompact {
            withAnimation(.snappy(duration: 0.20, extraBounce: 0)) {
                isCompactHeaderActive = wantCompact
            }
        }
        coordinator?.livePulseStore.reconcileLifecycle()
    }

    // MARK: - Live Pulse Layout & Stream Signals

    public func toggleLivePulseTicker() {
        guard !hasLiveFullscreenTab else { return }
        if isCompactHeaderActive {
            withAnimation(.snappy(duration: 0.20, extraBounce: 0)) {
                isCompactHeaderActive = false
                isLivePulseTickerVisible = true
            }
            settings.compactHeaderMode = false
            if !settings.livePulseEnabled {
                settings.livePulseEnabled = true
                showHUD(icon: "sportscourt.fill", message: "Live Pulse Enabled")
            }
            settings.livePulseShowTicker = true
            syncLivePulseStreamSignals()
            coordinator?.livePulseStore.reconcileLifecycle()
            return
        }
        let nextVisible = !isLivePulseTickerVisible
        if nextVisible && !settings.livePulseEnabled {
            settings.livePulseEnabled = true
            showHUD(icon: "sportscourt.fill", message: "Live Pulse Enabled")
        }
        withAnimation(.snappy(duration: 0.20, extraBounce: 0)) {
            isLivePulseTickerVisible = nextVisible
        }
        settings.livePulseShowTicker = nextVisible
        syncLivePulseStreamSignals()
        coordinator?.livePulseStore.reconcileLifecycle()
    }

    public func toggleLivePulseDrawer() {
        guard !hasLiveFullscreenTab else { return }
        if !isLivePulseDrawerVisible {
            openLivePulseDrawer(tab: coordinator?.livePulseStore.selectedDrawerTab ?? .scores)
            return
        }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            isLivePulseDrawerVisible = false
        }
        settings.livePulseShowDrawer = false

        let shouldRestoreSidebar = sidebarVisibleBeforeLiveDrawer == true
        sidebarVisibleBeforeLiveDrawer = nil
        if shouldRestoreSidebar && !isSidebarVisible {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                isSidebarVisible = true
            }
            settings.isSidebarVisible = true
        }
        coordinator?.livePulseStore.reconcileLifecycle()
    }

    public func openLivePulseDrawer(tab: LivePulseDrawerTab) {
        guard !hasLiveFullscreenTab else { return }
        if !settings.livePulseEnabled {
            settings.livePulseEnabled = true
            showHUD(icon: "sportscourt.fill", message: "Live Pulse Enabled")
        }
        coordinator?.livePulseStore.selectedDrawerTab = tab

        if LivePulseLayout.shouldAutoCollapseSidebar(windowWidth: windowContentWidth) && isSidebarVisible {
            if sidebarVisibleBeforeLiveDrawer == nil {
                sidebarVisibleBeforeLiveDrawer = true
            }
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                isSidebarVisible = false
            }
            settings.isSidebarVisible = false
        }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            isLivePulseDrawerVisible = true
        }
        settings.livePulseShowDrawer = true
        syncLivePulseStreamSignals()
        coordinator?.livePulseStore.reconcileLifecycle()
    }

    public func updateLivePulseDrawerWidth(_ width: CGFloat) {
        guard !hasLiveFullscreenTab else { return }
        let clamped = LivePulseLayout.clampDrawerWidth(width)
        guard abs(livePulseDrawerWidth - clamped) >= 0.5 else { return }
        livePulseDrawerWidth = clamped
        settings.livePulseDrawerWidth = Double(clamped)
    }

    public func resetLivePulseDrawerWidth() {
        guard !hasLiveFullscreenTab else { return }
        livePulseDrawerWidth = LivePulseLayout.drawerDefaultWidth
        settings.livePulseDrawerWidth = Double(LivePulseLayout.drawerDefaultWidth)
        showHUD(icon: "arrow.counterclockwise", message: "Drawer Width Reset")
    }

    func collapseLivePulseSurfacesOnMasterDisable() {
        guard !hasLiveFullscreenTab else { return }
        if isLivePulseTickerVisible {
            isLivePulseTickerVisible = false
        }
        if isLivePulseDrawerVisible {
            isLivePulseDrawerVisible = false
            let shouldRestore = sidebarVisibleBeforeLiveDrawer == true
            sidebarVisibleBeforeLiveDrawer = nil
            if shouldRestore && !isSidebarVisible {
                isSidebarVisible = true
                settings.isSidebarVisible = true
            }
        }
    }

    /// Synchronizes this window's ticker and drawer visibility from `AppSettings` (e.g. when toggled
    /// inside Preferences or after exiting native fullscreen) without writing back into `AppSettings`.
    public func syncLivePulseVisibilityFromSettings() {
        guard !hasLiveFullscreenTab else { return }
        guard settings.livePulseEnabled else {
            collapseLivePulseSurfacesOnMasterDisable()
            return
        }

        let wantTicker = settings.livePulseShowTicker
        let wantDrawer = settings.livePulseShowDrawer

        if isLivePulseTickerVisible != wantTicker {
            withAnimation(.snappy(duration: 0.20, extraBounce: 0)) {
                isLivePulseTickerVisible = wantTicker
            }
        }

        if isLivePulseDrawerVisible != wantDrawer {
            if wantDrawer {
                if LivePulseLayout.shouldAutoCollapseSidebar(windowWidth: windowContentWidth) && isSidebarVisible {
                    if sidebarVisibleBeforeLiveDrawer == nil {
                        sidebarVisibleBeforeLiveDrawer = true
                    }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        isSidebarVisible = false
                    }
                    settings.isSidebarVisible = false
                }
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    isLivePulseDrawerVisible = true
                }
            } else {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    isLivePulseDrawerVisible = false
                }
                let shouldRestoreSidebar = sidebarVisibleBeforeLiveDrawer == true
                sidebarVisibleBeforeLiveDrawer = nil
                if shouldRestoreSidebar && !isSidebarVisible {
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        isSidebarVisible = true
                    }
                    settings.isSidebarVisible = true
                }
            }
        }

        syncLivePulseStreamSignals()
    }

    public func activeTabScopeKey(for tab: BrowserTab) -> String {
        let targetURL = tab.pendingLazyURL ?? tab.url
        let host = (targetURL.host ?? "").lowercased()
        let path = targetURL.standardized.path.lowercased()
        if let videoID = YouTubeURLRouter.extractVideoID(from: targetURL) {
            return "\(host)\(path)?v=\(videoID)"
        }
        return "\(host)\(path)"
    }

    public func effectiveLivePulseDrawerWidth() -> CGFloat {
        LivePulseLayout.effectiveDrawerWidth(
            requested: livePulseDrawerWidth,
            windowWidth: windowContentWidth,
            isSidebarVisible: isSidebarVisible
        )
    }

    public func collectLivePulseStreamSignals() -> [StreamSignal] {
        var orderedTabs: [(tab: BrowserTab, slot: Int?, isPrimary: Bool)] = []
        var seenIDs = Set<UUID>()

        if isMultiviewActive {
            let primaryID = soloMultiviewTabID ?? multiviewAudioTabID ?? multiviewTabIDs.first
            for (index, tab) in multiviewTabs.enumerated() where seenIDs.insert(tab.id).inserted {
                orderedTabs.append((tab, index + 1, tab.id == primaryID))
            }
        } else {
            for tab in poppedOutTabs where seenIDs.insert(tab.id).inserted {
                orderedTabs.append((tab, nil, tab.id == activeMediaTab?.id))
            }
            if let selected = selectedTab, seenIDs.insert(selected.id).inserted {
                orderedTabs.append((selected, nil, true))
            }
        }

        return orderedTabs.map { entry in
            let tab = entry.tab
            let tabURL = tab.pendingLazyURL ?? tab.url
            let serviceID = StreamingServiceCatalog.service(matchingURL: tabURL)?.id
            let route = CleanBoxRules.classifyRoute(tabURL)
            let isAuthOrBrowse = tab.isSleeping
                || tab.pendingLazyURL != nil
                || StreamingServiceCatalog.isTransientAuthURL(tabURL)
                || route == .auth
                || (route == .browse && !tab.mediaStatus.hasVideo)

            let display = tab.displayTitle
            let mediaTitle = tab.mediaStatus.title
            let combinedTitle: String
            if !mediaTitle.isEmpty && mediaTitle.caseInsensitiveCompare(display) != .orderedSame {
                combinedTitle = "\(display) \(mediaTitle)"
            } else {
                combinedTitle = display
            }

            return StreamSignal(
                tabID: tab.id,
                windowID: windowID,
                url: tabURL,
                title: combinedTitle,
                serviceID: serviceID,
                multiviewSlot: entry.slot,
                isPrimaryFocus: entry.isPrimary,
                isPlaying: tab.mediaStatus.isPlaying,
                hasVideo: tab.mediaStatus.hasVideo,
                isAuthOrBrowse: isAuthOrBrowse,
                streamContext: tab.mediaStatus.streamContext
            )
        }
    }

    public func toggleLivePulseStreamFocus() {
        let nextFocus = !settings.livePulseStreamFocusOnly
        if nextFocus && !settings.livePulseEnabled {
            settings.livePulseEnabled = true
            showHUD(icon: "sportscourt.fill", message: "Live Pulse Enabled")
        }
        settings.livePulseStreamFocusOnly = nextFocus
        syncLivePulseStreamSignals()
        coordinator?.livePulseStore.reconcileLifecycle()
    }

    public func syncLivePulseStreamSignals() {
        guard settings.livePulseEnabled else { return }
        coordinator?.livePulseStore.updateStreamSignals(
            windowID: windowID,
            signals: collectLivePulseStreamSignals()
        )
    }

    // MARK: - System Auto-Pause, Sleep Timer, Share Sheet, Find Bar & Session Restoration

    public func pauseAllPlayingTabs(reason: SystemAutoPauseReason? = nil) {
        let playingTabs = tabs.filter { $0.mediaStatus.isPlaying }
        guard !playingTabs.isEmpty else { return }
        for tab in playingTabs {
            tab.pauseAllPlayback()
        }
        if reason == .audioDisconnected {
            showHUD(icon: "headphones", message: "Paused · Audio Disconnected")
        }
    }

    public func setSleepTimer(_ option: SleepTimerOption?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        postSleepTimerEndGuardUntil = .distantPast

        guard let option else {
            let wasActive = sleepTimerOption != nil
            sleepTimerOption = nil
            sleepTimerEndDate = nil
            if wasActive {
                showHUD(icon: "moon.zzz", message: "Sleep Timer Off")
            }
            return
        }

        sleepTimerOption = option
        if let seconds = option.durationSeconds {
            let endDate = Date().addingTimeInterval(seconds)
            sleepTimerEndDate = endDate
            sleepTimerTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                self.sleepTimerTask = nil
                self.sleepTimerOption = nil
                self.sleepTimerEndDate = nil
                self.pauseAllPlayingTabs()
                self.showHUD(icon: "moon.zzz.fill", message: "Sleep Timer Paused Playback")
            }
            showHUD(icon: "moon.zzz.fill", message: "Sleep Timer · \(option.title)")
        } else {
            sleepTimerEndDate = nil
            showHUD(icon: "moon.zzz.fill", message: "Sleep Timer · End of Video")
        }
    }

    public func shareURL(_ url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        if let window = mainWindow, let contentView = window.contentView {
            let anchor = NSRect(x: max(16, contentView.bounds.width - 52), y: max(16, contentView.bounds.height - 46), width: 1, height: 1)
            picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
        }
    }

    public func shareCurrentURL() {
        guard let url = currentShareURL else { return }
        shareURL(url)
    }

    public func shareCurrentURLAtTime() {
        guard let url = currentTimestampedShareURL else { return }
        shareURL(url)
    }

    public func presentFindBar() {
        guard !hasLiveFullscreenTab && !isSelectedTabPoppedOut else { return }
        if isCommandPalettePresented {
            dismissCommandPalette(refocusWebView: false)
        }
        isFindBarPresented = true
        findFocusTrigger &+= 1
        if !findQuery.isEmpty {
            scheduleDebouncedFindOnPage()
        }
    }

    public func dismissFindBar() {
        findDebounceTask?.cancel()
        findDebounceTask = nil
        isFindBarPresented = false
        findMatchFound = nil
        selectedTab?.clearFindHighlight()
        focusActiveWebView()
    }

    public func scheduleDebouncedFindOnPage() {
        findDebounceTask?.cancel()
        let query = findQuery
        if query.isEmpty {
            findMatchFound = nil
            selectedTab?.clearFindHighlight()
            return
        }
        findDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.isFindBarPresented else { return }
            let found = await self.selectedTab?.findOnPage(query, backwards: false) ?? false
            guard !Task.isCancelled, self.findQuery == query else { return }
            self.findMatchFound = found
        }
    }

    public func findNextOnPage() {
        guard !hasLiveFullscreenTab && !isSelectedTabPoppedOut else { return }
        if !isFindBarPresented {
            presentFindBar()
            return
        }
        let query = findQuery
        guard !query.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let found = await self.selectedTab?.findOnPage(query, backwards: false) ?? false
            if self.findQuery == query {
                self.findMatchFound = found
            }
        }
    }

    public func findPreviousOnPage() {
        guard isFindBarPresented, !findQuery.isEmpty else { return }
        let query = findQuery
        Task { @MainActor [weak self] in
            guard let self else { return }
            let found = await self.selectedTab?.findOnPage(query, backwards: true) ?? false
            if self.findQuery == query {
                self.findMatchFound = found
            }
        }
    }

    public func handleAppWillTerminate() {
        for tab in tabs {
            flushWatchProgress(for: tab)
        }
        cancelAllBackgroundTasks()
    }

    /// Cleanly tears down a closing window so zero audio, WKWebView, observer, or Task leaks remain.
    public func teardownWindow() {
        guard !isWindowTornDown else { return }
        isWindowTornDown = true

        if isMiniPlayer {
            _ = floatingMiniPlayer.detachAndHide()
            poppedOutTabIDs = []
            poppedOutReason = nil
            coordinator?.releaseMiniPlayerOwnership(for: windowID)
        }

        for tab in tabs {
            flushWatchProgress(for: tab)
        }

        cancelAllBackgroundTasks()
        clearWindowObservers()

        for tab in tabs {
            tab.teardown()
        }
        tabs.removeAll()
        multiviewTabIDs.removeAll()
        multiviewAudioTabID = nil
        soloMultiviewTabID = nil
        multiviewCustomVolumes.removeAll()
        mainWindow = nil
        isMainWindowVisible = false
    }

    private func cancelAllBackgroundTasks() {
        cancelAllMultiviewVolumeDispatchTasks()
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        findDebounceTask?.cancel()
        findDebounceTask = nil
        suggestDebounceTask?.cancel()
        suggestDebounceTask = nil
        sessionSaveTask?.cancel()
        sessionSaveTask = nil
        toastDismissTask?.cancel()
        toastDismissTask = nil
        resignActiveTask?.cancel()
        resignActiveTask = nil
        for (_, task) in sponsorFetchTasks {
            task.cancel()
        }
        sponsorFetchTasks.removeAll()
        cancelSignInCheckTasks()
    }

    // MARK: - Command Palette, Saved Multiview Presets & Drag-and-Drop

    public func toggleCommandPalette() {
        if isCommandPalettePresented {
            dismissCommandPalette(refocusWebView: true)
        } else {
            presentCommandPalette()
        }
    }

    public func presentCommandPalette() {
        guard !hasLiveFullscreenTab else { return }
        if isFindBarPresented {
            dismissFindBar()
        }
        suggestDebounceTask?.cancel()
        suggestDebounceTask = nil
        commandPaletteQuery = ""
        commandPaletteSuggestions = []
        isCommandPalettePresented = true
        commandPaletteFocusTrigger &+= 1
    }

    public func dismissCommandPalette(refocusWebView: Bool = true) {
        suggestDebounceTask?.cancel()
        suggestDebounceTask = nil
        isCommandPalettePresented = false
        commandPaletteQuery = ""
        commandPaletteSuggestions = []
        if refocusWebView {
            focusActiveWebView()
        }
    }

    public func scheduleCommandPaletteSuggestions() {
        suggestDebounceTask?.cancel()
        let query = commandPaletteQuery
        guard isCommandPalettePresented,
              settings.searchAutocompleteEnabled,
              CommandPaletteEngine.shouldFetchSuggestions(for: query) else {
            if !commandPaletteSuggestions.isEmpty {
                commandPaletteSuggestions = []
            }
            return
        }

        let client = suggestClient
        suggestDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.isCommandPalettePresented, self.commandPaletteQuery == query else {
                return
            }
            let fetched = await client.fetchSuggestions(for: query, maxCount: 6)
            guard !Task.isCancelled, self.isCommandPalettePresented, self.commandPaletteQuery == query else {
                return
            }
            self.commandPaletteSuggestions = fetched
        }
    }

    public var commandPaletteItems: [CommandPaletteItem] {
        let tabSnapshots: [CommandPaletteTabSnapshot] = tabs.map { tab in
            let urlHost = (tab.pendingLazyURL ?? tab.url).host ?? "youtube.com"
            let subtitle = tab.mediaStatus.channel.isEmpty ? urlHost : tab.mediaStatus.channel
            let isAudio = isMultiviewActive
                ? (multiviewAudioTab?.id == tab.id)
                : (tab.mediaStatus.isPlaying && !tab.mediaStatus.isMuted)
            return CommandPaletteTabSnapshot(
                id: tab.id,
                title: tab.displayTitle,
                subtitle: subtitle,
                multiviewSlot: multiviewSlotNumber(for: tab.id),
                isActiveAudio: isAudio,
                isPlaying: tab.mediaStatus.isPlaying,
                isSelected: tab.id == selectedTabID
            )
        }

        var actions: [CommandPaletteActionDescriptor] = [
            CommandPaletteActionDescriptor(
                action: .toggleMultiview,
                title: isMultiviewActive ? "Exit Multiview" : "Enter Multiview (Up to 4 Streams)",
                keywords: "multiview grid quad split sports",
                systemImage: isMultiviewActive ? "rectangle" : "square.grid.2x2",
                shortcutHint: "⌘⇧G",
                isFeaturedWhenEmpty: true
            ),
            CommandPaletteActionDescriptor(
                action: .openYouTubeTVInMultiview,
                title: "Open YouTube TV in Multiview",
                keywords: "yttv tv.youtube.com live guide sports sunday ticket",
                systemImage: "tv",
                isFeaturedWhenEmpty: true
            ),
            CommandPaletteActionDescriptor(
                action: .toggleFocusMode,
                title: focusModeActive ? "Exit Focus Mode" : "Toggle Focus Mode",
                keywords: "distraction free comments recommendations",
                systemImage: focusModeActive ? "eye.slash.fill" : "sparkles",
                shortcutHint: "⌘⇧F",
                isFeaturedWhenEmpty: true
            ),
            CommandPaletteActionDescriptor(
                action: .toggleDayNightMode,
                title: settings.isEffectivelyDark ? "Switch to Day Mode" : "Switch to Night Mode",
                keywords: "theme appearance light dark mode",
                systemImage: settings.isEffectivelyDark ? "sun.max.fill" : "moon.fill",
                shortcutHint: "⌘⇧L",
                isFeaturedWhenEmpty: true
            ),
            CommandPaletteActionDescriptor(
                action: .toggleMiniPlayer,
                title: isMiniPlayer ? "Return Floating Mini-Player" : "Pop Out Floating Mini-Player",
                keywords: "pip float popup window",
                systemImage: isMiniPlayer ? "arrow.down.right.and.arrow.up.left" : "rectangle.inset.bottomright.filled",
                shortcutHint: "⌘⇧M",
                isFeaturedWhenEmpty: true
            ),
            CommandPaletteActionDescriptor(
                action: .togglePictureInPicture,
                title: nowPlayingStatus.isPiP ? "Exit Picture in Picture" : "Picture in Picture",
                keywords: "pip video float",
                systemImage: nowPlayingStatus.isPiP ? "pip.exit" : "pip.enter",
                shortcutHint: "⌘⇧P",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .findOnPage,
                title: "Find on Page",
                keywords: "search text find comments",
                systemImage: "magnifyingglass",
                shortcutHint: "⌘F",
                isFeaturedWhenEmpty: true
            ),
            CommandPaletteActionDescriptor(
                action: .newTab,
                title: "New Tab",
                keywords: "open tab",
                systemImage: "plus.square",
                shortcutHint: "⌘T",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .newWindow,
                title: "New Window",
                keywords: "window multi dual monitor display",
                systemImage: "macwindow.badge.plus",
                shortcutHint: "⌘N",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .openClipboardURL,
                title: "Open YouTube URL from Clipboard",
                keywords: "paste link clipboard",
                systemImage: "link.badge.plus",
                shortcutHint: "⌘⇧V",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .toggleSidebar,
                title: isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                keywords: "sidebar navigation panel",
                systemImage: "sidebar.leading",
                shortcutHint: "⌘⌥S",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .toggleAlwaysOnTop,
                title: alwaysOnTop ? "Disable Always on Top" : "Always on Top",
                keywords: "pin float window top",
                systemImage: alwaysOnTop ? "pin.fill" : "pin",
                shortcutHint: "⌘⌥P",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .sleepTimer15,
                title: "Sleep Timer: 15 Minutes",
                keywords: "sleep pause timer 15",
                systemImage: "moon.zzz",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .sleepTimer30,
                title: "Sleep Timer: 30 Minutes",
                keywords: "sleep pause timer 30",
                systemImage: "moon.zzz",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .sleepTimerEndOfVideo,
                title: "Sleep Timer: End of Current Video",
                keywords: "sleep pause timer end video",
                systemImage: "moon.zzz",
                isFeaturedWhenEmpty: true
            )
        ]

        if nowPlayingStatus.hasVideo {
            actions.append(
                CommandPaletteActionDescriptor(
                    action: .copyVideoFrame,
                    title: "Copy Video Frame",
                    keywords: "screenshot capture frame image clipboard png",
                    systemImage: "camera.viewfinder",
                    isFeaturedWhenEmpty: false
                )
            )
            actions.append(
                CommandPaletteActionDescriptor(
                    action: .saveVideoFrame,
                    title: "Save Video Frame…",
                    keywords: "screenshot export frame image png save",
                    systemImage: "square.and.arrow.down",
                    isFeaturedWhenEmpty: false
                )
            )
        }

        if isSleepTimerActive {
            actions.append(
                CommandPaletteActionDescriptor(
                    action: .cancelSleepTimer,
                    title: "Turn Off Sleep Timer",
                    keywords: "cancel stop sleep timer",
                    systemImage: "moon.zzz.fill",
                    isFeaturedWhenEmpty: true
                )
            )
        }

        actions.append(
            CommandPaletteActionDescriptor(
                action: .manageStreamingServices,
                title: "Manage Streaming Services & Sign-In Hub…",
                keywords: "services onboarding login sign in prime amazon crunchyroll anime netflix hulu disney espn twitch peacock paramount hbo max apple",
                systemImage: "square.grid.3x3.square",
                isFeaturedWhenEmpty: false
            )
        )
        actions.append(
            CommandPaletteActionDescriptor(
                action: .openAirPlayPopover,
                title: "Stream to AirPlay & TV Displays…",
                keywords: "airplay cast tv apple tv homepod display mirror screen",
                systemImage: "airplayvideo",
                isFeaturedWhenEmpty: false
            )
        )
        actions.append(
            CommandPaletteActionDescriptor(
                action: .toggleLivePulseTicker,
                title: isLivePulseTickerRendered ? "Hide Live Pulse Ticker" : "Show Live Pulse Ticker",
                keywords: "live pulse ticker scores sports nfl nba mlb nhl",
                systemImage: "sportscourt",
                shortcutHint: "⌘⌥B",
                isFeaturedWhenEmpty: false
            )
        )
        actions.append(
            CommandPaletteActionDescriptor(
                action: .toggleLivePulseDrawer,
                title: isLivePulseDrawerVisible ? "Hide Live Pulse Drawer" : "Show Live Pulse Drawer",
                keywords: "live pulse drawer fantasy sleeper espn kalshi polymarket markets",
                systemImage: "sidebar.trailing",
                shortcutHint: "⌘⌥I",
                isFeaturedWhenEmpty: false
            )
        )
        actions.append(
            CommandPaletteActionDescriptor(
                action: .toggleCompactHeaderMode,
                title: isCompactHeaderActive ? "Expand Header Bars" : "Compact Single-Row Header",
                keywords: "compact minimize single row header chrome tabs",
                systemImage: isCompactHeaderActive ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                shortcutHint: "⌘⌥\\",
                isFeaturedWhenEmpty: false
            )
        )
        let activeHoliday = settings.activeHolidayPalette
        actions.append(
            CommandPaletteActionDescriptor(
                action: .cycleHolidayTheme,
                title: "Cycle Holiday Theme (\(activeHoliday.shortName))",
                keywords: "holiday theme seasonal thanksgiving winter halloween valentine patrick easter july4 new year color accent",
                systemImage: activeHoliday.symbolName,
                isFeaturedWhenEmpty: false
            )
        )
        let effectsEnabled = settings.holidayEffectsIntensity != .off
        actions.append(
            CommandPaletteActionDescriptor(
                action: .toggleHolidayEffects,
                title: effectsEnabled ? "Turn Off Holiday Ambient Effects" : "Enable Holiday Ambient Effects",
                keywords: "holiday effects snow leaves hearts particles ambient festive subtle",
                systemImage: effectsEnabled ? "sparkles.slash" : "sparkles",
                isFeaturedWhenEmpty: false
            )
        )

        return CommandPaletteEngine.rank(
            query: commandPaletteQuery,
            openTabs: tabSnapshots,
            chapters: activeChapters,
            presets: settings.savedMultiviewPresets,
            continueWatching: settings.continueWatching,
            pinnedItems: settings.pinnedItems,
            pinnedFolders: settings.pinnedFolders,
            watchedChannels: settings.watchedChannels,
            enabledServices: settings.enabledStreamingServices,
            isMultiviewActive: isMultiviewActive,
            canAddMultiviewTile: canAddMultiviewTile,
            actions: actions,
            suggestions: commandPaletteSuggestions
        )
    }

    public func executeCommandPaletteItem(_ item: CommandPaletteItem) {
        let payload = item.payload
        dismissCommandPalette(refocusWebView: false)

        switch payload {
        case .selectTab(let tabID):
            selectTab(id: tabID)
            focusActiveWebView()

        case .seekToChapter(let seconds):
            seek(to: seconds)
            focusActiveWebView()

        case .launchPreset(let presetID):
            if let preset = settings.savedMultiviewPresets.first(where: { $0.id == presetID }) {
                launchMultiviewPreset(preset)
            }
            focusActiveWebView()

        case .openPinnedFolder(let folderID):
            let count = pins(inFolder: folderID).count
            if (2...MultiviewGridLayout.maxTiles).contains(count) && !hasLiveFullscreenTab {
                openFolderInMultiview(id: folderID)
            } else {
                openFolderInTabs(id: folderID)
            }
            focusActiveWebView()

        case .openStreamingService(let serviceID):
            if let service = StreamingServiceCatalog.service(id: serviceID) {
                openStreamingService(service, inNewTab: false)
            }
            focusActiveWebView()

        case .addStreamingServiceToMultiview(let serviceID):
            if let service = StreamingServiceCatalog.service(id: serviceID) {
                addStreamingServiceToMultiview(service)
            }
            focusActiveWebView()

        case .openCompanionURL(let url):
            if isMultiviewActive && canAddMultiviewTile {
                addTileToMultiview(url: url, routingMode: .companion)
            } else {
                createTab(url: url, select: true, routingMode: .companion)
            }
            focusActiveWebView()

        case .openURL(let url):
            navigateSelectedTab(to: url)
            focusActiveWebView()

        case .searchYouTube(let query):
            if let searchURL = YouTubeURLRouter.resolveOmniboxInput(
                query,
                redirectShortsToWatch: settings.redirectShortsToWatch
            ) {
                navigateSelectedTab(to: searchURL)
            }
            focusActiveWebView()

        case .runAction(let action):
            switch action {
            case .toggleMultiview:
                toggleMultiview()
            case .openYouTubeTVInMultiview:
                openYouTubeTVInMultiview()
            case .toggleMiniPlayer:
                toggleMiniPlayer()
            case .togglePictureInPicture:
                togglePictureInPicture()
            case .toggleFocusMode:
                toggleFocusMode()
            case .toggleDayNightMode:
                toggleDayNightMode()
            case .toggleSidebar:
                toggleSidebar()
            case .findOnPage:
                presentFindBar()
                return
            case .newTab:
                createTab()
            case .newWindow:
                openNewWindow()
                return
            case .openClipboardURL:
                openURLFromClipboard()
            case .copyVideoFrame:
                copyVideoFrame()
            case .saveVideoFrame:
                saveVideoFrame()
            case .sleepTimer15:
                setSleepTimer(.minutes15)
            case .sleepTimer30:
                setSleepTimer(.minutes30)
            case .sleepTimerEndOfVideo:
                setSleepTimer(.endOfVideo)
            case .cancelSleepTimer:
                setSleepTimer(nil)
            case .toggleAlwaysOnTop:
                toggleAlwaysOnTop()
            case .manageStreamingServices:
                openStreamingServicesSetup(step: 1)
                return
            case .openAirPlayPopover:
                openAirPlayPopover()
                return
            case .toggleLivePulseTicker:
                toggleLivePulseTicker()
            case .toggleLivePulseDrawer:
                toggleLivePulseDrawer()
            case .toggleCompactHeaderMode:
                toggleCompactHeaderMode()
            case .toggleHolidayEffects:
                toggleHolidayEffects()
            case .cycleHolidayTheme:
                cycleHolidayTheme()
            }
            focusActiveWebView()
        }
    }

    // MARK: - Clean Video Frame Capture (Canvas -> WKWebView Snapshot Fallback, DRM Guarded)

    public func copyVideoFrame() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let image = await self.captureActiveVideoFrame() else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let png = Self.pngData(from: image) {
                pasteboard.setData(png, forType: .png)
            }
            if let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            self.showHUD(icon: "camera.viewfinder", message: "Video Frame Copied")
        }
    }

    public func saveVideoFrame() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let tab = self.activeMediaTab else { return }
            guard let image = await self.captureActiveVideoFrame(),
                  let png = Self.pngData(from: image) else {
                return
            }

            let rawTitle = (tab.mediaStatus.title.isEmpty ? tab.displayTitle : tab.mediaStatus.title)
            let safeTitle = rawTitle
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let timeText = MediaState.formatTime(tab.timeline.currentTime).replacingOccurrences(of: ":", with: "-")
            let prefix = safeTitle.isEmpty ? "YouTube-Frame" : String(safeTitle.prefix(48))

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(prefix)-\(timeText).png"
            let response = panel.runModal()
            guard response == .OK, let destinationURL = panel.url else { return }
            do {
                try png.write(to: destinationURL, options: .atomic)
                self.showHUD(icon: "checkmark.circle.fill", message: "Video Frame Saved")
            } catch {
                self.showHUD(icon: "exclamationmark.triangle", message: "Could Not Save Frame")
            }
        }
    }

    private func captureActiveVideoFrame() async -> NSImage? {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else {
            showHUD(icon: "video.slash", message: "No Active Video")
            return nil
        }
        if YouTubeURLRouter.isYouTubeTVHost(tab.url.host) {
            showHUD(icon: "lock.shield", message: "Frame capture unavailable for DRM-protected streams")
            return nil
        }

        let outcome = await tab.captureVideoFrame()
        let rawResult = outcome.result
        guard let rawResult else {
            showHUD(icon: "exclamationmark.triangle", message: "Unable to Capture Video Frame")
            return nil
        }

        guard let dict = rawResult as? [String: Any],
              let status = dict["status"] as? String else {
            showHUD(icon: "exclamationmark.triangle", message: "Unable to Capture Video Frame")
            return nil
        }

        switch status {
        case "drm":
            showHUD(icon: "lock.shield", message: "Frame capture unavailable for DRM-protected streams")
            return nil
        case "no_video":
            showHUD(icon: "video.slash", message: "No Active Video Frame")
            return nil
        case "ok":
            guard let dataURL = dict["dataURL"] as? String,
                  let commaIdx = dataURL.firstIndex(of: ",") else {
                showHUD(icon: "exclamationmark.triangle", message: "Unable to Decode Video Frame")
                return nil
            }
            let base64 = String(dataURL[dataURL.index(after: commaIdx)...])
            guard let data = Data(base64Encoded: base64),
                  let image = NSImage(data: data) else {
                showHUD(icon: "exclamationmark.triangle", message: "Unable to Decode Video Frame")
                return nil
            }
            return image
        case "cors_fallback":
            let snapshotConfig = WKSnapshotConfiguration()
            if outcome.usedSubframe && !tab.mediaStatus.isCleanBoxActive {
                snapshotConfig.rect = tab.webView.bounds
            } else {
                let x = (dict["x"] as? NSNumber)?.doubleValue ?? 0
                let y = (dict["y"] as? NSNumber)?.doubleValue ?? 0
                let w = (dict["width"] as? NSNumber)?.doubleValue ?? 0
                let h = (dict["height"] as? NSNumber)?.doubleValue ?? 0
                let rawRect = CGRect(x: x, y: y, width: w, height: h)
                let clippedRect = rawRect.intersection(tab.webView.bounds)
                guard !clippedRect.isNull, !clippedRect.isEmpty else {
                    showHUD(icon: "exclamationmark.triangle", message: "Video Frame Not Visible")
                    return nil
                }
                snapshotConfig.rect = clippedRect
            }
            do {
                return try await tab.webView.takeSnapshot(configuration: snapshotConfig)
            } catch {
                showHUD(icon: "exclamationmark.triangle", message: "Unable to Capture Video Frame")
                return nil
            }
        default:
            return nil
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    public func saveCurrentMultiviewAsPreset(name: String) {
        guard isMultiviewActive else { return }
        let validURLStrings = multiviewTabs.compactMap { tab -> String? in
            let url = tab.pendingLazyURL ?? tab.url
            let urlString = url.absoluteString
            let mode = tab.isCompanionTab ? TabRoutingMode.companion : tab.routingMode
            return SessionRestorationFilter.isRestorableURLString(urlString, routingMode: mode) ? urlString : nil
        }
        guard validURLStrings.count >= 2 else {
            showHUD(icon: "exclamationmark.triangle", message: "Need at Least 2 Streams to Save")
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Multiview · \(validURLStrings.count) Streams" : trimmedName
        let preset = MultiviewPreset(
            name: finalName,
            urlStrings: validURLStrings,
            layoutMode: multiviewLayoutMode,
            splitRatios: multiviewSplitRatios
        )
        settings.savedMultiviewPresets.append(preset)
        showHUD(icon: "bookmark.fill", message: "Saved \"\(finalName)\"")
    }

    public func launchMultiviewPreset(_ preset: MultiviewPreset) {
        guard !hasLiveFullscreenTab else { return }

        let validEntries: [(url: URL, mode: TabRoutingMode)] = preset.urlStrings.prefix(MultiviewGridLayout.maxTiles).compactMap { raw in
            guard let url = URL(string: raw) else { return nil }
            let mode = YouTubeURLRouter.preferredRoutingMode(for: url)
            guard SessionRestorationFilter.isRestorableURLString(raw, routingMode: mode) else {
                return nil
            }
            return (url, mode)
        }
        guard validEntries.count >= 2 else {
            showHUD(icon: "exclamationmark.triangle", message: "Preset Needs at Least 2 Valid Streams")
            return
        }

        var usedTabIDs = Set<UUID>()
        var targetTabIDs: [UUID] = []
        targetTabIDs.reserveCapacity(validEntries.count)

        for entry in validEntries {
            if let existing = tabs.first(where: {
                !usedTabIDs.contains($0.id)
                    && $0.routingMode == entry.mode
                    && ($0.pendingLazyURL ?? $0.url).absoluteString == entry.url.absoluteString
            }) {
                usedTabIDs.insert(existing.id)
                ensureTabLoaded(existing)
                targetTabIDs.append(existing.id)
            } else {
                let pendingSync = initialThemeCookieSyncTask
                let newTab = makeTab(url: entry.url, routingMode: entry.mode, deferInitialLoad: pendingSync != nil)
                tabs.append(newTab)
                if let pendingSync {
                    Task { @MainActor [weak newTab] in
                        await pendingSync.value
                        newTab?.load(entry.url)
                    }
                }
                refreshSponsorSegmentsIfNeeded(for: newTab, url: entry.url)
                usedTabIDs.insert(newTab.id)
                targetTabIDs.append(newTab.id)
            }
        }

        multiviewLayoutMode = preset.layoutMode
        multiviewSplitRatios = preset.splitRatios ?? .default
        soloMultiviewTabID = nil
        enterMultiview(with: targetTabIDs)
        scheduleSessionSave()
        showHUD(icon: "square.grid.2x2.fill", message: "Launched \"\(preset.name)\"")
    }

    public func renameMultiviewPreset(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = settings.savedMultiviewPresets.firstIndex(where: { $0.id == id }) else {
            return
        }
        settings.savedMultiviewPresets[idx].name = trimmed
        showHUD(icon: "pencil", message: "Renamed Preset")
    }

    public func deleteMultiviewPreset(id: UUID) {
        settings.savedMultiviewPresets.removeAll { $0.id == id }
        showHUD(icon: "trash", message: "Deleted Preset")
    }

    public func handleDroppedURL(_ url: URL) {
        let normalized = settings.redirectShortsToWatch
            ? (YouTubeURLRouter.rewriteShortsURL(url) ?? url)
            : url
        focusMainWindow()
        if isMultiviewActive && canAddMultiviewTile {
            addTileToMultiview(url: normalized)
        } else {
            createTab(url: normalized, select: true)
        }
    }

    public func handleDroppedCompanionURL(_ url: URL) {
        focusMainWindow()
        if isMultiviewActive && canAddMultiviewTile {
            addTileToMultiview(url: url, routingMode: .companion)
        } else {
            createTab(url: url, select: true, routingMode: .companion)
        }
    }

    public func openNewWindow() {
        coordinator?.openNewWindow()
    }

    public func closeWindow() {
        mainWindow?.performClose(nil)
    }

    public func openTabInNewWindow(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let baseURL = tab.pendingLazyURL ?? tab.url
        let targetURL: URL
        if tab.mediaStatus.hasVideo, tab.timeline.currentTime >= 1 {
            targetURL = YouTubeURLRouter.urlWithTimestamp(baseURL, seconds: tab.timeline.currentTime)
        } else {
            targetURL = baseURL
        }
        coordinator?.openURLInNewWindow(targetURL, routingMode: tab.routingMode)
    }

    public func openURLInNewWindow(_ url: URL) {
        coordinator?.openURLInNewWindow(url)
    }

    public func launchPresetInNewWindow(_ preset: MultiviewPreset) {
        coordinator?.launchPresetInNewWindow(preset)
    }

    func refreshMultiviewAudioDuckingIfActive() {
        guard isMultiviewActive else { return }
        applyMultiviewAudioFocus(unmuteAudioTab: true)
    }

    func persistSessionForClose() {
        persistSessionNow()
    }

    func reloadAllTabsToStartupDestination() {
        if isMiniPlayer {
            dockMiniPlayer(selectTab: true, focusMain: false)
        }
        if isMultiviewActive {
            exitMultiview(focusTabID: selectedTabID, showFeedback: false)
        }
        for tab in tabs {
            tab.load(settings.startupDestination.url)
        }
    }

    private func ensureTabLoaded(_ tab: BrowserTab) {
        guard tab.pendingLazyURL != nil else { return }
        if let pendingSync = initialThemeCookieSyncTask {
            Task { @MainActor [weak tab] in
                await pendingSync.value
                tab?.loadPendingIfNeeded()
            }
        } else {
            tab.loadPendingIfNeeded()
        }
    }

    private func syncBackForwardGestures() {
        let allowGestures = !isMultiviewActive
        for tab in tabs {
            tab.setBackForwardGesturesEnabled(allowGestures)
        }
    }

    private func scheduleSessionSave() {
        // Only persist session from the primary window (or sole open window) so secondary windows don't overwrite it.
        guard isPrimaryWindow || coordinator?.hasMultipleWindows != true else { return }
        sessionSaveTask?.cancel()
        sessionSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.sessionSaveTask = nil
            self.persistSessionNow()
        }
    }

    private func persistSessionNow() {
        let snapshots = tabs.map { tab in
            SavedTabSnapshot(
                urlString: (tab.pendingLazyURL ?? tab.url).absoluteString,
                title: tab.displayTitle,
                routingMode: tab.routingMode
            )
        }
        let selectedIdx = tabs.firstIndex(where: { $0.id == selectedTabID }) ?? 0
        settings.savedSession = SessionRestorationFilter.sanitize(
            tabs: snapshots,
            selectedIndex: selectedIdx
        )
    }

    private func handleTabVideoEnded(tabID: UUID) {
        guard sleepTimerOption == .endOfVideo else { return }
        let targetID = isMultiviewActive ? multiviewAudioTab?.id : activeMediaTab?.id
        guard tabID == targetID else { return }

        sleepTimerOption = nil
        sleepTimerEndDate = nil
        postSleepTimerEndGuardUntil = Date().addingTimeInterval(4.0)
        pauseAllPlayingTabs()
        showHUD(icon: "moon.zzz.fill", message: "Sleep Timer Paused Playback")
    }

    public func zoomIn() {
        guard let tab = selectedTab else { return }
        tab.pageZoom = min(tab.pageZoom + 0.1, 2.0)
    }

    public func zoomOut() {
        guard let tab = selectedTab else { return }
        tab.pageZoom = max(tab.pageZoom - 0.1, 0.6)
    }

    public func resetZoom() {
        selectedTab?.pageZoom = 1.0
    }

    // MARK: - Window Management

    public func syncWindowTitle() {
        guard let window = mainWindow else { return }
        let isHome: Bool
        if let tab = selectedTab {
            isHome = !tab.isCompanionTab && SidebarDestination.matching(url: tab.url) == .home
        } else {
            isHome = true
        }
        let nextTitle = WindowTitleFormatter.title(
            isMultiview: isMultiviewActive,
            multiviewCount: multiviewTabs.count,
            tabTitle: selectedTab?.displayTitle ?? "",
            isHome: isHome
        )
        if window.title != nextTitle {
            window.title = nextTitle
        }
    }

    private func installUnifiedToolbar(on window: NSWindow) {
        if window.toolbar?.identifier == NSToolbar.Identifier("GlassGridYouUnifiedTitlebar"),
           window.toolbar?.isVisible == true {
            return
        }
        // Attach an empty unified NSToolbar so macOS positions the traffic-light buttons inside a
        // 52pt unified titlebar (centerY = 26pt, inset cleanly inside the floating Liquid Glass
        // sidebar card's 16pt corner radius instead of clipping the top-left border).
        let toolbar = NSToolbar(identifier: "GlassGridYouUnifiedTitlebar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.isVisible = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
    }

    private func syncUnifiedToolbarForFullScreenState(on window: NSWindow) {
        let inNativeFullScreen = window.styleMask.contains(.fullScreen)
        if isWindowInNativeFullScreen != inNativeFullScreen {
            isWindowInNativeFullScreen = inNativeFullScreen
        }
        if inNativeFullScreen {
            if window.toolbar != nil {
                window.toolbar = nil
            }
        } else {
            installUnifiedToolbar(on: window)
        }
    }

    public func attachMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        clearWindowObservers()
        mainWindow = window
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let inNativeFullScreen = window.styleMask.contains(.fullScreen)
        if inNativeFullScreen {
            window.toolbar = nil
        } else {
            installUnifiedToolbar(on: window)
        }
        window.isMovableByWindowBackground = false
        window.minSize = Self.defaultMinSize
        // SwiftUI's AppKitWindowController owns every WindowGroup NSWindow and requires isReleasedWhenClosed = false
        // (setting true double-releases the NSWindow on close).
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.backgroundColor = AppleTheme.canvasNSColor

        if isPrimaryWindow {
            window.setFrameAutosaveName("GlassGridYouMainWindow")
        } else if !hasCascadedSecondaryWindow {
            hasCascadedSecondaryWindow = true
            coordinator?.cascadeSecondaryWindow(window, excluding: windowID)
        }

        syncWindowTitle()
        settings.applyAppearance()
        applyWindowLevelAndCollectionBehavior()
        isMainWindowVisible = window.isVisible
        isMainWindowMiniaturized = window.isMiniaturized
        isWindowInNativeFullScreen = inNativeFullScreen
        let initialWidth = window.contentLayoutRect.width
        if initialWidth >= 200 {
            windowContentWidth = initialWidth
        }
        if isLivePulseDrawerVisible,
           !hasLiveFullscreenTab,
           LivePulseLayout.shouldAutoCollapseSidebar(windowWidth: windowContentWidth),
           isSidebarVisible {
            if sidebarVisibleBeforeLiveDrawer == nil {
                sidebarVisibleBeforeLiveDrawer = true
            }
            isSidebarVisible = false
            settings.isSidebarVisible = false
        }
        syncLivePulseStreamSignals()
        coordinator?.livePulseStore.reconcileLifecycle()

        let center = NotificationCenter.default
        // Window-scoped local key monitor so pressing Esc exits Multiview Solo even when
        // the soloed WKWebView holds first responder focus (SwiftUI .onExitCommand does not fire there).
        soloEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
                return event
            }
            let targetWindowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self,
                      let win = self.mainWindow,
                      win.windowNumber == targetWindowNumber,
                      self.isMultiviewSoloActive,
                      !self.isFindBarPresented,
                      !self.isCommandPalettePresented,
                      !self.isOnboardingPresented,
                      !self.isAirPlayPopoverPresented,
                      !self.hasLiveFullscreenTab,
                      !(win.firstResponder is NSTextView) else {
                    return false
                }
                self.exitMultiviewSolo()
                return true
            }
            return consumed ? nil : event
        }
        windowObservers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isMainWindowVisible = true
                    self.isMainWindowMiniaturized = false
                    if let win = self.mainWindow {
                        self.syncUnifiedToolbarForFullScreenState(on: win)
                    }
                    self.coordinator?.markWindowActive(self.windowID)
                    self.coordinator?.livePulseStore.reconcileLifecycle()
                    if self.poppedOutReason == .leftApp {
                        self.dockMiniPlayer(selectTab: true, focusMain: false)
                    }
                }
            },
            center.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.coordinator?.markWindowActive(self.windowID)
                }
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hoveredMultiviewTileID = nil
                }
            },
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isMainWindowVisible = false
                    self.coordinator?.handleWindowWillClose(self.windowID)
                }
            },
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isMainWindowMiniaturized = true
                    self.coordinator?.livePulseStore.reconcileLifecycle()
                }
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isMainWindowMiniaturized = false
                    self.isMainWindowVisible = true
                    self.coordinator?.livePulseStore.reconcileLifecycle()
                }
            },
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.hasLiveFullscreenTab, let win = self.mainWindow else { return }
                    let width = win.contentLayoutRect.width
                    if width >= 200 && abs(self.windowContentWidth - width) >= 1 {
                        self.windowContentWidth = width
                    }
                    if self.isLivePulseDrawerVisible,
                       LivePulseLayout.shouldAutoCollapseSidebar(windowWidth: self.windowContentWidth),
                       self.isSidebarVisible {
                        if self.sidebarVisibleBeforeLiveDrawer == nil {
                            self.sidebarVisibleBeforeLiveDrawer = true
                        }
                        self.isSidebarVisible = false
                        self.settings.isSidebarVisible = false
                    }
                }
            },
            center.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isWindowInNativeFullScreen = true
                    self.mainWindow?.toolbar = nil
                }
            },
            center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let win = self.mainWindow else { return }
                    self.syncUnifiedToolbarForFullScreenState(on: win)
                }
            },
            center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isWindowInNativeFullScreen = false
                    if let window = self.mainWindow {
                        self.installUnifiedToolbar(on: window)
                        let width = window.contentLayoutRect.width
                        if width >= 200 {
                            self.windowContentWidth = width
                        }
                    }
                    self.syncLivePulseVisibilityFromSettings()
                }
            },
            center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !NSApp.isActive else { return }
                    self.scheduleBackgroundOcclusionEvaluation(delayMilliseconds: 180)
                }
            }
        ]

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNotifications: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        workspaceObservers = workspaceNotifications.map { name in
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !NSApp.isActive else { return }
                    self.scheduleBackgroundOcclusionEvaluation(delayMilliseconds: 180)
                }
            }
        }
    }

    public func applyWindowLevelAndCollectionBehavior() {
        guard let window = mainWindow else { return }
        window.level = alwaysOnTop ? .floating : .normal
        window.backgroundColor = AppleTheme.canvasNSColor
        for tab in tabs {
            tab.webView.underPageBackgroundColor = AppleTheme.canvasNSColor
        }

        var behavior = window.collectionBehavior
        // AppKit throws if .canJoinAllSpaces and .moveToActiveSpace are both set.
        behavior.remove(.moveToActiveSpace)
        behavior.remove(.canJoinAllSpaces)
        behavior.insert(.fullScreenPrimary)
        window.collectionBehavior = behavior
    }

    public func focusMainWindow() {
        NSApp.activate()
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            isMainWindowVisible = true
            isMainWindowMiniaturized = false
            coordinator?.livePulseStore.reconcileLifecycle()
        }
    }

    public func hideMainWindow() {
        mainWindow?.orderOut(nil)
        isMainWindowVisible = false
        coordinator?.livePulseStore.reconcileLifecycle()
    }

    public func handleIncomingURL(_ url: URL) {
        if AgentURLActionParser.isActionURL(url) {
            coordinator?.agentBridge.handleActionURL(url)
            return
        }
        guard let targetURL = YouTubeURLRouter.resolveCustomSchemeURL(url) else {
            return
        }
        let normalized = settings.redirectShortsToWatch
            ? (YouTubeURLRouter.rewriteShortsURL(targetURL) ?? targetURL)
            : targetURL
        focusMainWindow()
        createTab(url: normalized, select: true)
    }

    // MARK: - Cache & Account Data

    public func clearWebCache() async {
        let store = WKWebsiteDataStore.default()
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        let records = await store.dataRecords(ofTypes: cacheTypes)
        await store.removeData(ofTypes: cacheTypes, for: records)
        selectedTab?.reloadFromOrigin()
    }

    public func clearAllWebsiteData() async {
        if let coordinator {
            await coordinator.clearAllWebsiteData()
            return
        }
        isSigningOutData = true
        defer { isSigningOutData = false }

        if isMiniPlayer {
            dockMiniPlayer(selectTab: true, focusMain: false)
        }
        if isMultiviewActive {
            exitMultiview(focusTabID: selectedTabID, showFeedback: false)
        }

        let store = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: allTypes)
        await store.removeData(ofTypes: allTypes, for: records)

        for tab in tabs {
            tab.load(settings.startupDestination.url)
        }
    }

    // MARK: - SponsorBlock Integration (Strictly Opt-In)

    func handleSponsorBlockSettingChanged(enabled: Bool) {
        if enabled {
            for tab in tabs {
                refreshSponsorSegmentsIfNeeded(for: tab, url: tab.url)
            }
        } else {
            for (_, task) in sponsorFetchTasks {
                task.cancel()
            }
            sponsorFetchTasks.removeAll()
            for tab in tabs {
                tab.clearSponsorSegments()
            }
        }
    }

    private func refreshSponsorSegmentsIfNeeded(for tab: BrowserTab, url: URL) {
        let tabID = tab.id
        sponsorFetchTasks[tabID]?.cancel()
        sponsorFetchTasks.removeValue(forKey: tabID)

        guard settings.sponsorBlockEnabled,
              YouTubeURLRouter.isStandardYouTubeHost(url.host),
              let videoID = YouTubeURLRouter.extractVideoID(from: url) else {
            return
        }

        let client = sponsorBlockClient
        sponsorFetchTasks[tabID] = Task { [weak self, weak tab] in
            let segments = await client.fetchSponsorSegments(for: videoID)
            guard !Task.isCancelled,
                  let self,
                  let tab,
                  self.settings.sponsorBlockEnabled,
                  YouTubeURLRouter.extractVideoID(from: tab.url) == videoID else {
                return
            }
            tab.applySponsorSegments(videoID: videoID, segments: segments)
        }
    }

    // MARK: - Helpers

    private func shouldAutoPopOut(tab: BrowserTab) -> Bool {
        if isMultiviewActive {
            guard canPopOutMultiviewGrid else { return false }
            return multiviewTabs.contains { $0.mediaStatus.isPlaying && !$0.mediaStatus.isPiP }
        }
        guard canPopOut(tab: tab) else { return false }
        guard tab.mediaStatus.isPlaying else { return false }
        guard !tab.mediaStatus.isPiP else { return false }
        return true
    }

    private func configForTab(id: UUID) -> DistractionFreeConfig {
        let bypassed = tabs.first(where: { $0.id == id })?.isCleanBoxBypassed ?? false
        if isMultiviewActive, let slotIndex = multiviewTabIDs.firstIndex(of: id) {
            let isSoloed = (soloMultiviewTabID == id)
            let isPrimary = isSoloed || MultiviewGridLayout.isPrimarySlot(
                index: slotIndex,
                count: multiviewTabIDs.count,
                mode: multiviewLayoutMode
            )
            let clampedQuality = isSoloed
                ? settings.preferredQuality
                : PreferredVideoQuality.clampedForMultiview(
                    userPreference: settings.preferredQuality,
                    isPrimaryOrTwoUp: isPrimary,
                    ceilingOverride: settings.multiviewQualityCeiling
                )
            return settings.distractionFreeConfig(
                focusMode: focusModeActive,
                miniPlayer: isTabPoppedOut(id),
                multiviewTile: true,
                qualityOverride: clampedQuality,
                cleanBoxBypassed: bypassed
            )
        }
        return settings.distractionFreeConfig(
            focusMode: focusModeActive,
            miniPlayer: isTabPoppedOut(id),
            cleanBoxBypassed: bypassed
        )
    }

    private func makeTab(
        url: URL,
        initialTitle: String? = nil,
        routingMode: TabRoutingMode? = nil,
        deferInitialLoad: Bool = false,
        lazyLoad: Bool = false
    ) -> BrowserTab {
        let initialConfig = settings.distractionFreeConfig(
            focusMode: focusModeActive,
            miniPlayer: false
        )
        let tab = BrowserTab(
            initialURL: url,
            initialTitle: initialTitle,
            routingMode: routingMode,
            initialConfig: initialConfig,
            deferInitialLoad: deferInitialLoad,
            lazyLoad: lazyLoad,
            configProvider: { [weak self] in
                guard let self else { return DistractionFreeConfig() }
                return self.settings.distractionFreeConfig(
                    focusMode: self.focusModeActive,
                    miniPlayer: false
                )
            },
            routingPreferencesProvider: { [weak self] in
                guard let self else { return (true, true) }
                return (
                    self.settings.openExternalLinksInBrowser,
                    self.settings.redirectShortsToWatch
                )
            },
            onOpenInNewTab: { [weak self] targetURL, shouldSelect in
                self?.createTab(url: targetURL, select: shouldSelect)
            }
        )
        let tabID = tab.id
        tab.configProvider = { [weak self] in
            guard let self else { return DistractionFreeConfig() }
            return self.configForTab(id: tabID)
        }
        tab.onStartedPlaying = { [weak self] startedTabID in
            self?.handleTabStartedPlaying(startedTabID)
        }
        tab.onURLDidChange = { [weak self] changedTabID, newURL in
            self?.handleTabURLDidChange(tabID: changedTabID, newURL: newURL)
        }
        tab.onDidFinishNavigation = { [weak self] finishedTabID, finishedURL in
            self?.handleTabDidFinishNavigation(tabID: finishedTabID, url: finishedURL)
        }
        tab.onDidClickContent = { [weak self] clickedTabID in
            self?.handleTileClicked(tabID: clickedTabID)
        }
        tab.onUnmutedByUser = { [weak self] unmutedTabID in
            self?.handleTabUnmutedByUser(tabID: unmutedTabID)
        }
        tab.onFullscreenDidChange = { [weak self] fsTabID, isInFS in
            self?.handleTabFullscreenDidChange(tabID: fsTabID, isInFullscreen: isInFS)
        }
        tab.onVideoEnded = { [weak self] endedTabID in
            self?.handleTabVideoEnded(tabID: endedTabID)
        }
        tab.onSponsorSkipped = { [weak self] _ in
            self?.showHUD(icon: "forward.end.fill", message: "Skipped Sponsor")
        }
        tab.onWatchProgress = { [weak self] videoID, title, channel, channelURL, currentTime, duration, isNewChannelRecord in
            guard let self else { return }
            self.settings.continueWatching = ContinueWatchingStore.upsert(
                videoID: videoID,
                title: title,
                channel: channel,
                currentTime: currentTime,
                duration: duration,
                into: self.settings.continueWatching
            )
            if isNewChannelRecord {
                self.settings.watchedChannels = ContinueWatchingStore.recordChannel(
                    name: channel,
                    urlString: channelURL.isEmpty ? nil : channelURL,
                    into: self.settings.watchedChannels
                )
            }
        }
        return tab
    }

    private func handleTabStartedPlaying(_ startedTabID: UUID) {
        // Suppress YouTube autoplay-next briefly after an End-of-Video Sleep Timer fires.
        if Date() < postSleepTimerEndGuardUntil {
            if let autoTab = tabs.first(where: { $0.id == startedTabID }) {
                autoTab.pauseAllPlayback()
            }
            return
        }

        if isMultiviewActive {
            if multiviewTabIDs.contains(startedTabID) {
                // Allow all Multiview tiles to play video simultaneously, applying custom mix, ducking (15%), or hard mute.
                if (startedTabID != multiviewAudioTabID || multiviewCustomVolumes[startedTabID] != nil),
                   let tile = tabs.first(where: { $0.id == startedTabID }) {
                    multiviewVolumeDispatchTasks[startedTabID]?.cancel()
                    multiviewVolumeDispatchTasks.removeValue(forKey: startedTabID)
                    let level = effectiveMultiviewVolume(for: startedTabID)
                    tile.setAudioLevel(muted: level.muted, volumePercent: level.volumePercent)
                }
                for other in tabs where !multiviewTabIDs.contains(other.id) && other.mediaStatus.isPlaying {
                    other.pauseMedia()
                }
                syncLivePulseStreamSignals()
                return
            }
            // Background tab outside Multiview should not hijack audio.
            if let backgroundTab = tabs.first(where: { $0.id == startedTabID }) {
                backgroundTab.pauseMedia()
            }
            return
        }

        // Prevent background tabs from auto-playing audio on load and hijacking the active video.
        if startedTabID != selectedTabID && !isTabPoppedOut(startedTabID) {
            if let backgroundTab = tabs.first(where: { $0.id == startedTabID }) {
                backgroundTab.pauseMedia()
            }
            return
        }

        // Single-audio enforcement: pause any other playing tabs.
        for other in tabs where other.id != startedTabID && other.mediaStatus.isPlaying {
            other.pauseMedia()
        }

        // If a different docked tab started playing while an auto-popped mini-player was floating, dock the stale panel cleanly.
        if !isTabPoppedOut(startedTabID), !poppedOutTabIDs.isEmpty {
            for tab in poppedOutTabs {
                tab.pauseMedia()
            }
            if poppedOutReason != .manual {
                dockMiniPlayer(selectTab: false, focusMain: false)
            }
        }
        syncLivePulseStreamSignals()
    }

    private func handleTabURLDidChange(tabID: UUID, newURL: URL) {
        if !isFloatingMultiviewGrid, tabID == poppedOutTabID {
            let isCompanion = tabs.first(where: { $0.id == tabID })?.isCompanionTab ?? false
            let shouldDock = isCompanion
                ? StreamingServiceCatalog.isTransientAuthURL(newURL)
                : !YouTubeURLRouter.isWatchURL(newURL)
            if shouldDock {
                dockMiniPlayer(selectTab: true, focusMain: false)
            }
        }
        if let tab = tabs.first(where: { $0.id == tabID }) {
            refreshSponsorSegmentsIfNeeded(for: tab, url: newURL)
            if tab.authFlowServiceID != nil && !StreamingServiceCatalog.isTransientAuthURL(newURL) {
                scheduleSignInCompletionCheck(for: tabID, url: newURL, requireAuthFlowForNonPrime: true)
            }
        }
        if isFloatingMultiviewGrid && multiviewTabIDs.contains(tabID) {
            syncFloatingMultiviewGrid()
        }
        if tabID == selectedTabID {
            syncWindowTitle()
        }
        scheduleSessionSave()
        syncLivePulseStreamSignals()
    }

    func applyConfigToAllTabs() {
        for tab in tabs {
            tab.applyConfig(configForTab(id: tab.id))
        }
    }

    private func clearWindowObservers() {
        if let monitor = soloEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            soloEscapeMonitor = nil
        }

        let center = NotificationCenter.default
        for token in windowObservers {
            center.removeObserver(token)
        }
        windowObservers.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            workspaceCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }
}
