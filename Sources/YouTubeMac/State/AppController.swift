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

    public let settings: AppSettings
    public var tabs: [BrowserTab] = []
    public var selectedTabID: UUID
    public var closedTabURLs: [URL] = []

    public var focusModeActive: Bool = false
    public var alwaysOnTop: Bool = false
    public var isSidebarVisible: Bool
    public var poppedOutTabID: UUID?

    public var multiviewTabIDs: [UUID] = []
    public var multiviewAudioTabID: UUID?
    public var multiviewLayoutMode: MultiviewLayoutMode = .auto
    public var hoveredMultiviewTileID: UUID?

    public var omniboxText: String = ""
    public var omniboxFocusTrigger: Int = 0
    public var omniboxClearOnFocus: Bool = false
    public var isMainWindowVisible: Bool = true
    public var isMainWindowMiniaturized: Bool = false
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

    public var isCheckingForUpdates: Bool = false
    public var lastUpdateCheckResult: ReleaseCheckResult?

    @ObservationIgnored
    weak var mainWindow: NSWindow?

    @ObservationIgnored
    private let systemPlaybackGuard = SystemPlaybackGuard()

    @ObservationIgnored
    private let suggestClient = YouTubeSuggestClient()

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
    private var sidebarVisibleBeforeMultiview: Bool?

    @ObservationIgnored
    private let floatingMiniPlayer: FloatingMiniPlayerController

    @ObservationIgnored
    private let sponsorBlockClient = SponsorBlockClient()

    @ObservationIgnored
    private var sponsorFetchTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var toastDismissTask: Task<Void, Never>?

    @ObservationIgnored
    private var poppedOutReason: PopOutReason?

    @ObservationIgnored
    private var resignActiveTask: Task<Void, Never>?

    @ObservationIgnored
    private var initialThemeCookieSyncTask: Task<Void, Never>?

    @ObservationIgnored
    private var appearanceSyncTask: Task<Void, Never>?

    @ObservationIgnored
    private var windowObservers: [NSObjectProtocol] = []

    @ObservationIgnored
    private var workspaceObservers: [NSObjectProtocol] = []

    private static let defaultMinSize = NSSize(width: 780, height: 520)

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.isSidebarVisible = settings.isSidebarVisible
        self.floatingMiniPlayer = FloatingMiniPlayerController(initialSavedFrame: settings.savedMiniPlayerFrame)

        let placeholderID = UUID()
        self.selectedTabID = placeholderID

        let initialSelectedTab: BrowserTab
        let initialSelectedURL: URL

        if settings.restoreTabsOnLaunch,
           let saved = settings.savedSession,
           let sanitized = SessionRestorationFilter.sanitize(tabs: saved.tabs, selectedIndex: saved.selectedIndex) {
            var restoredTabs: [BrowserTab] = []
            restoredTabs.reserveCapacity(sanitized.tabs.count)
            for (idx, snap) in sanitized.tabs.enumerated() {
                guard let tabURL = snap.url else { continue }
                let isSelected = (idx == sanitized.selectedIndex)
                let tab = makeTab(
                    url: tabURL,
                    initialTitle: snap.title,
                    deferInitialLoad: isSelected,
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
                let fallbackURL = settings.startupDestination.url
                let fallbackTab = makeTab(url: fallbackURL, deferInitialLoad: true)
                self.tabs = [fallbackTab]
                initialSelectedTab = fallbackTab
                initialSelectedURL = fallbackURL
            }
        } else {
            let fallbackURL = settings.startupDestination.url
            let fallbackTab = makeTab(url: fallbackURL, deferInitialLoad: true)
            self.tabs = [fallbackTab]
            initialSelectedTab = fallbackTab
            initialSelectedURL = fallbackURL
        }

        self.selectedTabID = initialSelectedTab.id
        self.omniboxText = initialSelectedTab.url.absoluteString

        settings.onWebConfigDidChange = { [weak self] in
            self?.applyConfigToAllTabs()
        }
        settings.onWindowPreferencesDidChange = { [weak self] in
            self?.applyWindowLevelAndCollectionBehavior()
            self?.floatingMiniPlayer.updateCollectionBehavior(allSpaces: self?.settings.miniPlayerAllSpaces ?? true)
        }
        settings.onAppearanceDidChange = { [weak self] in
            self?.handleAppearanceDidChange()
        }
        settings.onSponsorBlockSettingDidChange = { [weak self] enabled in
            self?.handleSponsorBlockSettingChanged(enabled: enabled)
        }
        settings.onSystemPlaybackGuardSettingDidChange = { [weak self] enabled in
            self?.updateSystemPlaybackGuard(enabled: enabled)
        }
        settings.onMultiviewAudioDuckingDidChange = { [weak self] _ in
            guard let self, self.isMultiviewActive else { return }
            self.applyMultiviewAudioFocus(unmuteAudioTab: true)
        }

        floatingMiniPlayer.onFrameChanged = { [weak self] frame in
            self?.settings.savedMiniPlayerFrame = frame
        }
        floatingMiniPlayer.onWindowClosedExternally = { [weak self] in
            self?.closeMiniPlayerPopup()
        }

        updateSystemPlaybackGuard(enabled: settings.autoPauseOnSystemEvents)

        // Sync YouTube's PREF cookie in WKHTTPCookieStore BEFORE the very first HTTP request goes out.
        self.initialThemeCookieSyncTask = Task { @MainActor [weak self, weak initialSelectedTab] in
            guard let self else { return }
            await self.syncThemeCookieToWebKitStore()
            self.initialThemeCookieSyncTask = nil
            initialSelectedTab?.load(initialSelectedURL)
        }
    }

    public var isMiniPlayer: Bool {
        poppedOutTabID != nil
    }

    public var isSelectedTabPoppedOut: Bool {
        poppedOutTabID != nil && selectedTabID == poppedOutTabID
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

    public var canPopOutActiveTab: Bool {
        guard let candidate = activeMediaTab else { return false }
        return canPopOut(tab: candidate)
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
    public func createTab(url: URL? = nil, select: Bool = true) -> BrowserTab {
        let targetURL = url ?? settings.startupDestination.url
        let targetIsWatch = YouTubeURLRouter.isWatchURL(targetURL)

        if !isMultiviewActive, select, let leaving = selectedTab {
            if settings.autoMiniPlayerOnLeave,
               !targetIsWatch,
               poppedOutTabID == nil,
               shouldAutoPopOut(tab: leaving) {
                popOutToMiniPlayer(tab: leaving, reason: .leftPage)
            } else if targetIsWatch && leaving.mediaStatus.isPlaying {
                leaving.pauseMedia()
            }
        }

        let pendingSync = initialThemeCookieSyncTask
        let tab = makeTab(url: targetURL, deferInitialLoad: pendingSync != nil)
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
                    applyConfigToAllTabs()
                    applyMultiviewAudioFocus(unmuteAudioTab: false)
                } else {
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
        return tab
    }

    public func duplicateTab(id: UUID) {
        guard let source = tabs.first(where: { $0.id == id }) else { return }
        createTab(url: source.pendingLazyURL ?? source.url, select: true)
    }

    public func closeTab(id: UUID) {
        guard !anyTabInFullscreen else { return }

        if let closingTab = tabs.first(where: { $0.id == id }) {
            flushWatchProgress(for: closingTab)
        }
        sponsorFetchTasks[id]?.cancel()
        sponsorFetchTasks.removeValue(forKey: id)

        if tabs.count <= 1 {
            // Standard macOS single-tab behavior: restore mini-player cleanly, pause active video, then hide window.
            if id == poppedOutTabID {
                let detached = floatingMiniPlayer.detachAndHide()
                poppedOutTabID = nil
                poppedOutReason = nil
                if let tab = detached ?? tabs.first(where: { $0.id == id }) {
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

        if id == poppedOutTabID {
            floatingMiniPlayer.detachAndHide()
            poppedOutTabID = nil
            poppedOutReason = nil
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
                hoveredMultiviewTileID = nil
                restoreSidebarAfterMultiviewIfNeeded()
                syncBackForwardGestures()
                selectedTabID = survivingID
                syncOmniboxToSelectedTab()
                if let survivor = tabs.first(where: { $0.id == survivingID }) {
                    survivor.needsPostAttachResize = true
                    ensureTabLoaded(survivor)
                    if survivor.mediaStatus.hasVideo {
                        survivor.setMuted(false)
                    }
                }
                applyConfigToAllTabs()
                scheduleSessionSave()
                return
            } else {
                multiviewTabIDs = result.state.tabIDs
                multiviewAudioTabID = result.state.audioTabID
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
    }

    public func closeOtherTabs(keepingID id: UUID) {
        guard !anyTabInFullscreen else { return }

        if isMultiviewActive {
            multiviewTabIDs = []
            multiviewAudioTabID = nil
            hoveredMultiviewTileID = nil
            restoreSidebarAfterMultiviewIfNeeded()
            syncBackForwardGestures()
        }

        if let popped = poppedOutTabID, popped != id {
            floatingMiniPlayer.detachAndHide()
            poppedOutTabID = nil
            poppedOutReason = nil
        }

        let toClose = tabs.filter { $0.id != id }
        for tab in toClose {
            sponsorFetchTasks[tab.id]?.cancel()
            sponsorFetchTasks.removeValue(forKey: tab.id)
            closedTabURLs.append(tab.pendingLazyURL ?? tab.url)
            tab.teardown()
        }
        tabs.removeAll { $0.id != id }
        selectedTabID = id
        syncOmniboxToSelectedTab()
        if let kept = tabs.first(where: { $0.id == id }) {
            ensureTabLoaded(kept)
            kept.needsPostAttachResize = true
            kept.applyConfig(configForTab(id: id), force: true)
        }
        scheduleSessionSave()
    }

    public func reopenClosedTab() {
        guard let lastURL = closedTabURLs.popLast() else { return }
        createTab(url: lastURL, select: true)
    }

    public func selectTab(id: UUID) {
        guard !anyTabInFullscreen else { return }
        guard let targetTab = tabs.first(where: { $0.id == id }) else { return }

        // Clicking back on a popped-out tab smoothly docks it back into the main window.
        if id == poppedOutTabID {
            dockMiniPlayer(selectTab: true, focusMain: false)
            return
        }

        ensureTabLoaded(targetTab)

        if isMultiviewActive {
            if multiviewTabIDs.contains(id) {
                focusMultiviewAudio(tabID: id, showFeedback: false)
            } else {
                exitMultiview(focusTabID: id, showFeedback: false)
            }
            scheduleSessionSave()
            return
        }

        // If leaving a playing watch tab for another tab, float the playing video as a pop-up.
        if settings.autoMiniPlayerOnLeave,
           poppedOutTabID == nil,
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

        // If the selected tab is currently popped out, navigate a docked tab instead so the pop-up keeps playing.
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
           poppedOutTabID == nil,
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
        let target = idx + delta
        guard settings.pinnedItems.indices.contains(target), target != idx else { return }
        settings.pinnedItems.swapAt(idx, target)
    }

    public func moveTab(fromID: UUID, toID: UUID) {
        guard !anyTabInFullscreen,
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
              id != poppedOutTabID,
              !isTabInMultiview(id),
              !anyTabInFullscreen,
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
              !YouTubeURLRouter.isYouTubeTVHost(tab.url.host),
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
            layoutMode: multiviewLayoutMode
        )
    }

    public func toggleMultiview() {
        if isMultiviewActive {
            exitMultiview(focusTabID: multiviewAudioTabID ?? selectedTabID, showFeedback: true)
        } else {
            enterMultiview()
        }
    }

    public func enterMultiview(with explicitTabIDs: [UUID]? = nil) {
        guard !anyTabInFullscreen else { return }

        if poppedOutTabID != nil {
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

        multiviewTabIDs = next.tabIDs
        multiviewAudioTabID = next.audioTabID
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
    }

    public func exitMultiview(focusTabID: UUID? = nil, showFeedback: Bool = true) {
        guard isMultiviewActive else { return }
        guard !anyTabInFullscreen else { return }

        let targetID: UUID
        if let focusTabID, tabs.contains(where: { $0.id == focusTabID }) {
            targetID = focusTabID
        } else if let audioID = multiviewAudioTabID, tabs.contains(where: { $0.id == audioID }) {
            targetID = audioID
        } else {
            targetID = selectedTabID
        }

        let previousTileIDs = multiviewTabIDs
        multiviewTabIDs = []
        multiviewAudioTabID = nil
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
    }

    public func setMultiviewLayoutMode(_ mode: MultiviewLayoutMode, showFeedback: Bool = true) {
        guard multiviewLayoutMode != mode else { return }
        multiviewLayoutMode = mode
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

    public func addTileToMultiview(url: URL? = nil) {
        guard !anyTabInFullscreen else { return }
        let targetURL = url ?? settings.startupDestination.url

        if !isMultiviewActive {
            let pendingSync = initialThemeCookieSyncTask
            let newTab = makeTab(url: targetURL, deferInitialLoad: pendingSync != nil)
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
        let newTab = makeTab(url: targetURL, deferInitialLoad: pendingSync != nil)
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
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: false)
        scheduleSessionSave()
        showHUD(icon: "plus.square.on.square", message: "Added Stream (\(multiviewTabIDs.count)/\(MultiviewGridLayout.maxTiles))")
    }

    public func openYouTubeTVInMultiview() {
        guard let url = URL(string: "https://tv.youtube.com/live") else { return }
        addTileToMultiview(url: url)
    }

    public func addClipboardURLToMultiview() {
        guard let clipURL = clipboardYouTubeURL() else {
            showHUD(icon: "link.badge.plus", message: "No YouTube Link in Clipboard")
            return
        }
        let target = settings.redirectShortsToWatch
            ? (YouTubeURLRouter.rewriteShortsURL(clipURL) ?? clipURL)
            : clipURL
        addTileToMultiview(url: target)
    }

    public func addExistingTabToMultiview(id: UUID) {
        guard !anyTabInFullscreen, tabs.contains(where: { $0.id == id }) else { return }

        if id == poppedOutTabID {
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
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: false)
        showHUD(icon: "square.grid.2x2", message: "Added to Multiview (\(multiviewTabIDs.count)/\(MultiviewGridLayout.maxTiles))")
    }

    public func removeTileFromMultiview(id: UUID, closeTabIfMultiple: Bool = false) {
        guard isMultiviewActive, multiviewTabIDs.contains(id), !anyTabInFullscreen else { return }

        if closeTabIfMultiple && tabs.count > 1 {
            closeTab(id: id)
            return
        }

        if let removedTab = tabs.first(where: { $0.id == id }) {
            removedTab.needsPostAttachResize = true
            removedTab.setAudioLevel(muted: false, volumePercent: 100)
            removedTab.pauseMedia()
        }
        let result = MultiviewReducer.removeTile(id, from: multiviewState)
        if let survivingID = result.remainingSingleTabID {
            exitMultiview(focusTabID: survivingID, showFeedback: true)
            return
        }

        multiviewTabIDs = result.state.tabIDs
        multiviewAudioTabID = result.state.audioTabID
        if hoveredMultiviewTileID == id {
            hoveredMultiviewTileID = nil
        }
        if selectedTabID == id {
            selectedTabID = result.state.audioTabID ?? result.state.tabIDs.first ?? selectedTabID
            syncOmniboxToSelectedTab()
        }
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: true)
    }

    public func promoteMultiviewTileToPrimary(id: UUID) {
        guard isMultiviewActive, multiviewTabIDs.contains(id) else { return }
        let next = MultiviewReducer.promoteToPrimary(id, in: multiviewState, transferAudio: true)
        multiviewTabIDs = next.tabIDs
        multiviewAudioTabID = next.audioTabID
        selectedTabID = id
        syncOmniboxToSelectedTab()
        applyConfigToAllTabs()
        applyMultiviewAudioFocus(unmuteAudioTab: true)
        showHUD(icon: "arrow.up.left.and.arrow.down.right", message: "Promoted to Main Tile")
    }

    public func moveMultiviewTile(id: UUID, by delta: Int) {
        guard isMultiviewActive, !anyTabInFullscreen, multiviewTabIDs.contains(id) else { return }
        let next = MultiviewReducer.moveTile(id, by: delta, in: multiviewState)
        guard next.tabIDs != multiviewTabIDs else { return }
        multiviewTabIDs = next.tabIDs
        applyConfigToAllTabs()
    }

    public func focusMultiviewAudio(tabID: UUID, showFeedback: Bool = true) {
        guard isMultiviewActive, multiviewTabIDs.contains(tabID) else { return }
        let next = MultiviewReducer.focusAudio(tabID, in: multiviewState)
        multiviewAudioTabID = next.audioTabID
        selectedTabID = tabID
        syncOmniboxToSelectedTab()
        applyMultiviewAudioFocus(unmuteAudioTab: true)
        if showFeedback, let slot = multiviewSlotNumber(for: tabID) {
            let title = tabs.first(where: { $0.id == tabID })?.displayTitle ?? "Stream \(slot)"
            showHUD(icon: "speaker.wave.2.fill", message: "Audio \(slot) · \(title)")
        }
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
        lastMultiviewAudioSwitchAt = Date()
        for tab in multiviewTabs {
            tab.setAudioLevel(muted: true, volumePercent: 100)
        }
        showHUD(icon: "speaker.slash.fill", message: "All Streams Muted")
    }

    public func navigateMultiviewTileToBrowse(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = id
        let destination: URL
        if YouTubeURLRouter.isYouTubeTVHost(tab.url.host), let yttvLive = URL(string: "https://tv.youtube.com/live") {
            destination = yttvLive
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
            if tab.id == activeAudioID {
                if unmuteAudioTab {
                    tab.setAudioLevel(muted: false, volumePercent: 100)
                }
            } else if duckBackground {
                tab.setAudioLevel(muted: false, volumePercent: 15)
            } else {
                tab.setAudioLevel(muted: true, volumePercent: 100)
            }
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
        activeMediaTab?.evaluate(EnhancementScript.togglePlayPauseScript)
    }

    public func seek(by seconds: Double) {
        activeMediaTab?.evaluate(EnhancementScript.seekByScript(seconds: seconds))
    }

    /// Deterministically seeks the active media tab to an absolute timestamp, optimistically updating
    /// `PlaybackTimeline` so Menu Bar drag release never snaps backward before JS telemetry arrives.
    public func seek(to seconds: Double) {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return }
        let duration = tab.timeline.duration
        guard duration.isFinite, duration > 0, duration < 86400 else { return }
        let clamped = min(max(seconds.isFinite ? seconds : 0, 0), duration)
        tab.timeline.update(currentTime: clamped, duration: duration)
        tab.evaluate(EnhancementScript.seekToScript(seconds: clamped))
    }

    public func toggleMute(tabID: UUID? = nil) {
        if let tabID {
            guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
            // In Multiview, unmuting a non-audio tile transfers exclusive audio focus cleanly instead of creating two audible streams.
            if isMultiviewActive && multiviewTabIDs.contains(tabID) && tabID != multiviewAudioTabID {
                focusMultiviewAudio(tabID: tabID, showFeedback: false)
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
        tab.evaluate(EnhancementScript.togglePictureInPictureScript)
    }

    public func toggleTheaterMode() {
        activeMediaTab?.evaluate(EnhancementScript.toggleTheaterModeScript)
    }

    public func setPlaybackRate(_ rate: Double, showFeedback: Bool = true) {
        guard let tab = activeMediaTab, tab.mediaStatus.hasVideo else { return }
        let clamped = min(max(rate.isFinite ? rate : 1.0, 0.25), 4.0)
        tab.evaluate(EnhancementScript.setPlaybackRateScript(rate: clamped))
        if showFeedback {
            showHUD(icon: "gauge.with.dots.needle.67percent", message: "Speed \(MediaStatus.formatPlaybackRate(clamped))")
        }
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

    public func toggleAlwaysOnTop() {
        alwaysOnTop.toggle()
        applyWindowLevelAndCollectionBehavior()
    }

    public func canPopOut(tab: BrowserTab) -> Bool {
        guard tab.mediaStatus.hasVideo else { return false }
        guard YouTubeURLRouter.isWatchURL(tab.url) else { return false }
        guard !tab.isInFullscreen && tab.webView.fullscreenState == .notInFullscreen else { return false }
        return true
    }

    public func toggleMiniPlayer() {
        if poppedOutTabID != nil {
            dockMiniPlayer(selectTab: true, focusMain: true)
            return
        }

        guard let targetTab = activeMediaTab, canPopOut(tab: targetTab) else {
            return
        }
        if isMultiviewActive {
            exitMultiview(focusTabID: targetTab.id, showFeedback: false)
        }
        popOutToMiniPlayer(tab: targetTab, reason: .manual)
    }

    public func popOutToMiniPlayer(tab: BrowserTab, reason: PopOutReason) {
        guard canPopOut(tab: tab) else {
            return
        }

        // Always exit Multiview cleanly before floating a video so hybrid Multiview + Mini-Player states cannot occur.
        if isMultiviewActive {
            exitMultiview(focusTabID: tab.id, showFeedback: false)
        }

        if let existingID = poppedOutTabID, existingID != tab.id {
            dockMiniPlayer(selectTab: false, focusMain: false)
        }

        tab.needsPostAttachResize = false
        tab.cancelPostAttachResize()
        poppedOutTabID = tab.id
        poppedOutReason = reason

        floatingMiniPlayer.show(
            tab: tab,
            allSpaces: settings.miniPlayerAllSpaces,
            onSeek: { [weak tab] seconds in
                tab?.evaluate(EnhancementScript.seekByScript(seconds: seconds))
            },
            onTogglePlay: { [weak tab] in
                tab?.evaluate(EnhancementScript.togglePlayPauseScript)
            },
            onToggleMute: { [weak tab] in
                tab?.toggleMute()
            },
            onDock: { [weak self] in
                self?.dockMiniPlayer(selectTab: true, focusMain: true)
            },
            onClose: { [weak self] in
                self?.closeMiniPlayerPopup()
            }
        )
        tab.applyConfig(configForTab(id: tab.id), force: true)
    }

    public func dockMiniPlayer(selectTab: Bool = true, focusMain: Bool = false) {
        guard let poppedID = poppedOutTabID else { return }
        if let existing = tabs.first(where: { $0.id == poppedID }),
           existing.isInFullscreen || existing.webView.fullscreenState != .notInFullscreen {
            return
        }

        let detachedTab = floatingMiniPlayer.detachAndHide()
        poppedOutTabID = nil
        poppedOutReason = nil

        if let tab = detachedTab ?? tabs.first(where: { $0.id == poppedID }) {
            tab.needsPostAttachResize = true
            tab.applyConfig(configForTab(id: tab.id), force: true)
            if selectTab {
                selectedTabID = tab.id
                syncOmniboxToSelectedTab()
            }
        }
        if focusMain {
            focusMainWindow()
        }
    }

    public func closeMiniPlayerPopup() {
        guard let poppedID = poppedOutTabID else { return }
        if let existing = tabs.first(where: { $0.id == poppedID }),
           existing.isInFullscreen || existing.webView.fullscreenState != .notInFullscreen {
            return
        }

        let detachedTab = floatingMiniPlayer.detachAndHide()
        poppedOutTabID = nil
        poppedOutReason = nil

        if let tab = detachedTab ?? tabs.first(where: { $0.id == poppedID }) {
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
        guard let window = mainWindow,
              isMainWindowVisible,
              window.isVisible,
              !isMainWindowMiniaturized,
              !window.isMiniaturized else {
            return
        }

        let snapshot = captureMainWindowOcclusionSnapshot(for: window)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        if poppedOutTabID == nil {
            guard !isMultiviewActive,
                  settings.autoMiniPlayerOnLeave,
                  let candidate = activeMediaTab,
                  shouldAutoPopOut(tab: candidate) else {
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
                popOutToMiniPlayer(tab: candidate, reason: .leftApp)
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
        // Respect manual sidebar changes made during Multiview so exiting Multiview won't revert them.
        sidebarVisibleBeforeMultiview = nil
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            isSidebarVisible.toggle()
        }
        settings.isSidebarVisible = isSidebarVisible
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
        guard !anyTabInFullscreen && !isSelectedTabPoppedOut else { return }
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
        guard !anyTabInFullscreen && !isSelectedTabPoppedOut else { return }
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
        persistSessionNow()
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        findDebounceTask?.cancel()
        findDebounceTask = nil
        suggestDebounceTask?.cancel()
        suggestDebounceTask = nil
        sessionSaveTask?.cancel()
        sessionSaveTask = nil
        systemPlaybackGuard.stop()
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
        guard !anyTabInFullscreen else { return }
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

        return CommandPaletteEngine.rank(
            query: commandPaletteQuery,
            openTabs: tabSnapshots,
            chapters: activeChapters,
            presets: settings.savedMultiviewPresets,
            continueWatching: settings.continueWatching,
            pinnedItems: settings.pinnedItems,
            watchedChannels: settings.watchedChannels,
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

        let rawResult: Any?
        do {
            rawResult = try await tab.webView.evaluateJavaScript(EnhancementScript.captureVideoFrameScript)
        } catch {
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
            let snapshotConfig = WKSnapshotConfiguration()
            snapshotConfig.rect = clippedRect
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
            let urlString = (tab.pendingLazyURL ?? tab.url).absoluteString
            return SessionRestorationFilter.isRestorableURLString(urlString) ? urlString : nil
        }
        guard validURLStrings.count >= 2 else {
            showHUD(icon: "exclamationmark.triangle", message: "Need at Least 2 YouTube Streams to Save")
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Multiview · \(validURLStrings.count) Streams" : trimmedName
        let preset = MultiviewPreset(
            name: finalName,
            urlStrings: validURLStrings,
            layoutMode: multiviewLayoutMode
        )
        settings.savedMultiviewPresets.append(preset)
        showHUD(icon: "bookmark.fill", message: "Saved \"\(finalName)\"")
    }

    public func launchMultiviewPreset(_ preset: MultiviewPreset) {
        guard !anyTabInFullscreen else { return }

        let validURLs: [URL] = preset.urlStrings.prefix(MultiviewGridLayout.maxTiles).compactMap { raw in
            guard SessionRestorationFilter.isRestorableURLString(raw), let url = URL(string: raw) else {
                return nil
            }
            return url
        }
        guard validURLs.count >= 2 else {
            showHUD(icon: "exclamationmark.triangle", message: "Preset Needs at Least 2 Valid Streams")
            return
        }

        var usedTabIDs = Set<UUID>()
        var targetTabIDs: [UUID] = []
        targetTabIDs.reserveCapacity(validURLs.count)

        for targetURL in validURLs {
            if let existing = tabs.first(where: {
                !usedTabIDs.contains($0.id) && ($0.pendingLazyURL ?? $0.url).absoluteString == targetURL.absoluteString
            }) {
                usedTabIDs.insert(existing.id)
                ensureTabLoaded(existing)
                targetTabIDs.append(existing.id)
            } else {
                let pendingSync = initialThemeCookieSyncTask
                let newTab = makeTab(url: targetURL, deferInitialLoad: pendingSync != nil)
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

        multiviewLayoutMode = preset.layoutMode
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

    private func updateSystemPlaybackGuard(enabled: Bool) {
        if enabled {
            systemPlaybackGuard.start { [weak self] reason in
                self?.pauseAllPlayingTabs(reason: reason)
            }
        } else {
            systemPlaybackGuard.stop()
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
                title: tab.displayTitle
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

    public func attachMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        clearWindowObservers()
        mainWindow = window
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.minSize = Self.defaultMinSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.backgroundColor = AppleTheme.canvasNSColor
        window.setFrameAutosaveName("GlassGridYouMainWindow")
        settings.applyAppearance()
        applyWindowLevelAndCollectionBehavior()
        isMainWindowVisible = window.isVisible
        isMainWindowMiniaturized = window.isMiniaturized

        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isMainWindowVisible = true
                    self.isMainWindowMiniaturized = false
                    if self.poppedOutReason == .leftApp {
                        self.dockMiniPlayer(selectTab: true, focusMain: false)
                    }
                }
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.hoveredMultiviewTileID = nil
                }
            },
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isMainWindowVisible = false
                }
            },
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isMainWindowMiniaturized = true
                }
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isMainWindowMiniaturized = false
                    self?.isMainWindowVisible = true
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
        }
    }

    public func hideMainWindow() {
        mainWindow?.orderOut(nil)
        isMainWindowVisible = false
    }

    public func handleIncomingURL(_ url: URL) {
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
        isSigningOutData = true
        defer { isSigningOutData = false }

        if isMultiviewActive {
            exitMultiview(focusTabID: selectedTabID, showFeedback: false)
        }
        if poppedOutTabID != nil {
            dockMiniPlayer(selectTab: true, focusMain: false)
        }

        let store = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: allTypes)
        await store.removeData(ofTypes: allTypes, for: records)
        await syncThemeCookieToWebKitStore()

        for tab in tabs {
            tab.load(settings.startupDestination.url)
        }
    }

    // MARK: - SponsorBlock Integration (Strictly Opt-In)

    private func handleSponsorBlockSettingChanged(enabled: Bool) {
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
              !YouTubeURLRouter.isYouTubeTVHost(url.host),
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

    // MARK: - Theme Cookie Sync

    private func handleAppearanceDidChange() {
        appearanceSyncTask?.cancel()
        appearanceSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncThemeCookieToWebKitStore()
            guard !Task.isCancelled else { return }
            self.applyConfigToAllTabs()
        }
    }

    private func syncThemeCookieToWebKitStore() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let allCookies = await cookieStore.allCookies()
        let existingPREF = allCookies.first { cookie in
            cookie.name == "PREF"
                && YouTubeURLRouter.isYouTubeHost(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        let systemIsDark = (NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .darkAqua) == .darkAqua
        let merged = YouTubeThemeCookie.mergedPREFValue(
            existingPREF?.value,
            appearance: settings.appearance,
            systemIsDark: systemIsDark
        )
        if existingPREF?.value == merged {
            return
        }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: ".youtube.com",
            .path: "/",
            .name: "PREF",
            .value: merged,
            .expires: Date().addingTimeInterval(365 * 24 * 60 * 60),
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax
        ]
        if existingPREF?.isSecure == true {
            properties[.secure] = "TRUE"
        }
        if let cookie = HTTPCookie(properties: properties) {
            await cookieStore.setCookie(cookie)
        }
    }

    // MARK: - Helpers

    private func shouldAutoPopOut(tab: BrowserTab) -> Bool {
        guard !isMultiviewActive else { return false }
        guard canPopOut(tab: tab) else { return false }
        guard tab.mediaStatus.isPlaying else { return false }
        guard !tab.mediaStatus.isPiP else { return false }
        return true
    }

    private func configForTab(id: UUID) -> DistractionFreeConfig {
        if isMultiviewActive, let slotIndex = multiviewTabIDs.firstIndex(of: id) {
            let isPrimary = MultiviewGridLayout.isPrimarySlot(
                index: slotIndex,
                count: multiviewTabIDs.count,
                mode: multiviewLayoutMode
            )
            let clampedQuality = PreferredVideoQuality.clampedForMultiview(
                userPreference: settings.preferredQuality,
                isPrimaryOrTwoUp: isPrimary,
                ceilingOverride: settings.multiviewQualityCeiling
            )
            return settings.distractionFreeConfig(
                focusMode: focusModeActive,
                miniPlayer: poppedOutTabID == id,
                multiviewTile: true,
                qualityOverride: clampedQuality
            )
        }
        return settings.distractionFreeConfig(
            focusMode: focusModeActive,
            miniPlayer: poppedOutTabID == id
        )
    }

    private func makeTab(
        url: URL,
        initialTitle: String? = nil,
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
                // Allow all Multiview tiles to play video simultaneously, applying ducking (15%) or hard mute to non-audio tiles.
                if startedTabID != multiviewAudioTabID,
                   let bgTile = tabs.first(where: { $0.id == startedTabID }) {
                    if settings.multiviewAudioDuckingEnabled {
                        bgTile.setAudioLevel(muted: false, volumePercent: 15)
                    } else {
                        bgTile.setAudioLevel(muted: true, volumePercent: 100)
                    }
                }
                for other in tabs where !multiviewTabIDs.contains(other.id) && other.mediaStatus.isPlaying {
                    other.pauseMedia()
                }
                return
            }
            // Background tab outside Multiview should not hijack audio.
            if let backgroundTab = tabs.first(where: { $0.id == startedTabID }) {
                backgroundTab.pauseMedia()
            }
            return
        }

        // Prevent background tabs from auto-playing audio on load and hijacking the active video.
        if startedTabID != selectedTabID && startedTabID != poppedOutTabID {
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
        if let poppedID = poppedOutTabID, poppedID != startedTabID {
            poppedOutTab?.pauseMedia()
            if poppedOutReason != .manual {
                dockMiniPlayer(selectTab: false, focusMain: false)
            }
        }
    }

    private func handleTabURLDidChange(tabID: UUID, newURL: URL) {
        if tabID == poppedOutTabID && !YouTubeURLRouter.isWatchURL(newURL) {
            dockMiniPlayer(selectTab: true, focusMain: false)
        }
        if let tab = tabs.first(where: { $0.id == tabID }) {
            refreshSponsorSegmentsIfNeeded(for: tab, url: newURL)
        }
        scheduleSessionSave()
    }

    private func applyConfigToAllTabs() {
        for tab in tabs {
            tab.applyConfig(configForTab(id: tab.id))
        }
    }

    public var currentAppVersion: String {
        if let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "1.0.0"
    }

    /// Opens a validated `https://` GitHub URL in the user's default browser.
    public func openTrustedGitHubURL(_ url: URL) {
        guard UpdateChecker.isTrustedGitHubDownloadURL(url) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Strictly user-initiated update check against GitHub Releases (zero startup/background polling).
    public func checkForUpdates(presentAlert: Bool) {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        let versionString = currentAppVersion

        Task { @MainActor [weak self] in
            let result = await UpdateChecker.checkLatestRelease(currentVersionString: versionString)
            guard let self else { return }
            self.lastUpdateCheckResult = result
            self.isCheckingForUpdates = false
            if presentAlert {
                self.presentUpdateCheckAlert(result)
            }
        }
    }

    private func presentUpdateCheckAlert(_ result: ReleaseCheckResult) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch result {
        case .updateAvailable(let current, let latest):
            alert.messageText = "GlassGrid You \(latest.tagName) is Available"
            alert.informativeText = "You are currently running v\(current). Would you like to download the latest release from GitHub?"
            alert.addButton(withTitle: "Download Release")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                openTrustedGitHubURL(latest.preferredDownloadURL)
            }

        case .upToDate(let current):
            alert.messageText = "You’re Up to Date"
            alert.informativeText = "GlassGrid You v\(current) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .noReleasesPublished:
            alert.messageText = "No Releases Published Yet"
            alert.informativeText = "GlassGrid You v\(currentAppVersion) has no published GitHub Release builds yet."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "View Releases")
            if alert.runModal() == .alertSecondButtonReturn {
                openTrustedGitHubURL(UpdateChecker.releasesPageURL)
            }

        case .failed(let message):
            alert.messageText = "Unable to Check for Updates"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func clearWindowObservers() {
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
