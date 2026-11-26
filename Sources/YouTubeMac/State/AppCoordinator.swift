import AppKit
import Foundation
import Observation
import WebKit
import YouTubeMacCore

/// Initial content requested when opening a new window (`⌘N`, `Open in New Window`, or `Launch Preset in New Window`).
public enum WindowLaunchRequest: Sendable {
    case standard
    case url(URL, TabRoutingMode)
    case multiviewPreset(MultiviewPreset)
}

/// App-wide multi-window coordinator owning shared singletons (`AppSettings`, `SystemPlaybackGuard`,
/// single `FloatingMiniPlayerController`, `SparkleUpdaterManager`, and WebKit theme cookie sync) and
/// routing commands, Dock reopen, Menu Bar controls, and deep links cleanly to the active window.
@MainActor
@Observable
public final class AppCoordinator {
    public static weak var sharedActive: AppCoordinator?

    public let settings: AppSettings
    public let updater: SparkleUpdaterManager
    @ObservationIgnored
    public private(set) lazy var agentBridge: AgentBridgeController = AgentBridgeController(coordinator: self)

    @ObservationIgnored
    public private(set) lazy var livePulseStore: LivePulseStore = LivePulseStore(
        settings: settings,
        coordinator: self
    )

    public private(set) var windowOrder: [UUID] = []
    public var activeWindowID: UUID?
    public var floatingMiniPlayerOwnerWindowID: UUID?
    public var currentAudioOutputName: String = "System Output"
    public var isAirPlayAudioActive: Bool = false
    public var connectedDisplays: [ConnectedDisplayDescriptor] = []

    @ObservationIgnored
    public var hasAutoPresentedOnboardingThisSession: Bool = false

    @ObservationIgnored
    private var screenParametersObserver: (any NSObjectProtocol)?

    @ObservationIgnored
    private var controllersByID: [UUID: AppController] = [:]

    @ObservationIgnored
    private var pendingLaunchRequests: [UUID: WindowLaunchRequest] = [:]

    @ObservationIgnored
    let floatingMiniPlayer: FloatingMiniPlayerController

    @ObservationIgnored
    private let systemPlaybackGuard = SystemPlaybackGuard()

    @ObservationIgnored
    public let sponsorBlockClient = SponsorBlockClient()

    @ObservationIgnored
    public let suggestClient = YouTubeSuggestClient()

    @ObservationIgnored
    public var initialThemeCookieSyncTask: Task<Void, Never>?

    @ObservationIgnored
    private var appearanceSyncTask: Task<Void, Never>?

    @ObservationIgnored
    private var serviceResetGeneration: [String: Int] = [:]

    public func resetGeneration(for serviceID: String) -> Int {
        serviceResetGeneration[serviceID, default: 0]
    }

    @ObservationIgnored
    public var openWindowHandler: ((UUID) -> Void)? {
        didSet {
            if openWindowHandler != nil {
                agentBridge.notifyWindowReady()
            }
        }
    }

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.updater = SparkleUpdaterManager(settings: settings)
        self.floatingMiniPlayer = FloatingMiniPlayerController(
            initialSavedFrame: settings.savedMiniPlayerFrame,
            initialSavedGridFrame: settings.savedMiniPlayerGridFrame,
            initialOpacity: settings.miniPlayerOpacity
        )
        _ = self.agentBridge

        bindSharedSettingsObservers()
        bindSharedFloatingMiniPlayerCallbacks()
        refreshAudioOutputStatus()
        refreshConnectedDisplays()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshConnectedDisplays()
            }
        }
        updateSystemPlaybackGuard(enabled: settings.autoPauseOnSystemEvents)

        // Sync YouTube's PREF cookie once before the first window sends its initial HTTP request.
        self.initialThemeCookieSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncThemeCookieToWebKitStore()
            self.initialThemeCookieSyncTask = nil
        }
    }

    /// All currently registered open window controllers in deterministic creation order.
    public var openWindows: [AppController] {
        windowOrder.compactMap { controllersByID[$0] }
    }

    public var hasMultipleWindows: Bool {
        windowOrder.count > 1
    }

    public var hasAnyWindowInLiveFullscreen: Bool {
        openWindows.contains(where: \.hasLiveFullscreenTab)
    }

    /// Active command target for macOS menu shortcuts, Dock actions, and incoming URLs.
    /// Optional so a 0-window state (all windows closed while app stays running) never crashes.
    public var commandTarget: AppController? {
        if let key = NSApp.keyWindow,
           let match = openWindows.first(where: { $0.mainWindow === key }) {
            return match
        }
        if let main = NSApp.mainWindow,
           let match = openWindows.first(where: { $0.mainWindow === main }) {
            return match
        }
        if let activeWindowID, let active = controllersByID[activeWindowID] {
            return active
        }
        return openWindows.first
    }

    /// Controller surfaced in the Menu Bar popover and Dock Now Playing controls.
    /// Prioritizes an actively playing floating Mini-Player owner, then the focused window if playing,
    /// then any playing window, before falling back to `commandTarget`.
    public var nowPlayingController: AppController? {
        if let ownerID = floatingMiniPlayerOwnerWindowID,
           let owner = controllersByID[ownerID],
           owner.nowPlayingStatus.isPlaying {
            return owner
        }
        if let target = commandTarget, target.nowPlayingStatus.isPlaying {
            return target
        }
        if let playing = openWindows.first(where: { $0.nowPlayingStatus.isPlaying }) {
            return playing
        }
        if let ownerID = floatingMiniPlayerOwnerWindowID,
           let owner = controllersByID[ownerID] {
            return owner
        }
        return commandTarget
    }

    /// Strictly idempotent lookup/creation of the `AppController` backing a SwiftUI `WindowGroup` scene ID.
    public func controller(for windowID: UUID) -> AppController {
        if let existing = controllersByID[windowID] {
            return existing
        }

        let isPrimary = windowOrder.isEmpty
        let launchRequest = pendingLaunchRequests.removeValue(forKey: windowID) ?? .standard
        let controller = AppController(
            windowID: windowID,
            isPrimaryWindow: isPrimary,
            launchRequest: launchRequest,
            coordinator: self
        )
        controllersByID[windowID] = controller
        windowOrder.append(windowID)
        if activeWindowID == nil {
            activeWindowID = windowID
        }
        agentBridge.notifyWindowReady()
        return controller
    }

    /// Opens a fresh macOS window (`⌘N`) optionally preloaded with a URL or saved Multiview preset.
    public func openNewWindow(request: WindowLaunchRequest = .standard) {
        let newID = UUID()
        pendingLaunchRequests[newID] = request
        NSApp.activate(ignoringOtherApps: true)
        openWindowHandler?(newID)
    }

    public func openURLInNewWindow(_ url: URL, routingMode: TabRoutingMode? = nil) {
        let mode = routingMode ?? YouTubeURLRouter.preferredRoutingMode(for: url)
        openNewWindow(request: .url(url, mode))
    }

    public func launchPresetInNewWindow(_ preset: MultiviewPreset) {
        openNewWindow(request: .multiviewPreset(preset))
    }

    /// Cascades a newly opened secondary window slightly offset from the currently active window
    /// without ever touching Window 1's saved `setFrameAutosaveName` bounds.
    public func cascadeSecondaryWindow(_ newWindow: NSWindow, excluding windowID: UUID) {
        let reference = (activeWindowID != windowID ? activeWindowID.flatMap { controllersByID[$0]?.mainWindow } : nil)
            ?? openWindows.first(where: { $0.windowID != windowID })?.mainWindow
        guard let reference else { return }

        let refFrame = reference.frame
        var nextOrigin = NSPoint(x: refFrame.origin.x + 26, y: refFrame.origin.y - 26)
        let screenFrame = (reference.screen ?? NSScreen.main)?.visibleFrame ?? refFrame
        let size = newWindow.frame.size

        if nextOrigin.x + size.width > screenFrame.maxX {
            nextOrigin.x = max(screenFrame.minX + 20, screenFrame.minX + 40)
        }
        if nextOrigin.y < screenFrame.minY {
            nextOrigin.y = max(screenFrame.minY + 20, screenFrame.maxY - size.height - 24)
        }
        newWindow.setFrameOrigin(nextOrigin)
    }

    public func markWindowActive(_ windowID: UUID) {
        guard controllersByID[windowID] != nil else { return }
        if activeWindowID != windowID {
            activeWindowID = windowID
        }
    }

    /// Cleans up a closing window's `WKWebView`s, observers, tasks, and shared Mini-Player ownership.
    public func handleWindowWillClose(_ windowID: UUID) {
        guard let closing = controllersByID[windowID] else { return }

        // Persist session before tearing down the last/primary window so relaunch or Dock reopen restores cleanly.
        if closing.isPrimaryWindow || windowOrder.count == 1 {
            closing.persistSessionForClose()
        }

        if floatingMiniPlayerOwnerWindowID == windowID {
            floatingMiniPlayerOwnerWindowID = nil
        }

        closing.teardownWindow()
        controllersByID.removeValue(forKey: windowID)
        windowOrder.removeAll { $0 == windowID }

        if activeWindowID == windowID {
            activeWindowID = windowOrder.last
        }

        livePulseStore.removeWindowSignals(windowID: windowID)
        livePulseStore.reconcileLifecycle()
    }

    /// Enforces single shared `FloatingMiniPlayerController` ownership across all windows,
    /// refusing transfer when a floating tab or the previous owner is currently in live WebKit fullscreen.
    public func prepareMiniPlayerOwnership(for windowID: UUID) -> Bool {
        if floatingMiniPlayer.hasLiveFullscreenTab {
            return false
        }
        if let existingOwnerID = floatingMiniPlayerOwnerWindowID,
           existingOwnerID != windowID,
           let previousOwner = controllersByID[existingOwnerID] {
            if previousOwner.hasLiveFullscreenTab {
                return false
            }
            previousOwner.dockMiniPlayer(selectTab: false, focusMain: false)
            if previousOwner.isMiniPlayer {
                return false
            }
        }
        floatingMiniPlayerOwnerWindowID = windowID
        return true
    }

    public func releaseMiniPlayerOwnership(for windowID: UUID) {
        if floatingMiniPlayerOwnerWindowID == windowID {
            floatingMiniPlayerOwnerWindowID = nil
        }
    }

    // MARK: - AppKit Delegate Lifecycle & Global Actions

    public func handleDockReopen(hasVisibleWindows: Bool) {
        let windows = openWindows
        if windows.isEmpty {
            openNewWindow()
            return
        }
        if windows.count == 1 {
            windows[0].focusMainWindow()
            return
        }
        if let active = activeWindowID.flatMap({ controllersByID[$0] }) ?? windows.first {
            active.focusMainWindow()
        }
    }

    public func bringAllWindowsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if openWindows.isEmpty {
            openNewWindow()
            return
        }
        for controller in openWindows {
            if let window = controller.mainWindow {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.orderFront(nil)
            }
        }
        commandTarget?.focusMainWindow()
    }

    public func handleAppDidResignActive() {
        // Route background auto-pop-out evaluation to a single eligible window so two windows never fight for the floating panel.
        if let ownerID = floatingMiniPlayerOwnerWindowID, let owner = controllersByID[ownerID] {
            owner.handleAppDidResignActive()
            return
        }
        if let target = commandTarget, target.nowPlayingStatus.isPlaying {
            target.handleAppDidResignActive()
            return
        }
        if let playing = openWindows.first(where: { $0.nowPlayingStatus.isPlaying }) {
            playing.handleAppDidResignActive()
            return
        }
        commandTarget?.handleAppDidResignActive()
    }

    public func handleAppDidBecomeActive() {
        if let ownerID = floatingMiniPlayerOwnerWindowID, let owner = controllersByID[ownerID] {
            owner.handleAppDidBecomeActive()
        } else {
            commandTarget?.handleAppDidBecomeActive()
        }
    }

    public func handleAppWillTerminate() {
        let windows = openWindows
        if let sessionOwner = windows.first(where: \.isPrimaryWindow) ?? commandTarget ?? windows.first {
            sessionOwner.persistSessionForClose()
        }
        for controller in windows {
            controller.handleAppWillTerminate()
        }
        appearanceSyncTask?.cancel()
        appearanceSyncTask = nil
        initialThemeCookieSyncTask?.cancel()
        initialThemeCookieSyncTask = nil
        systemPlaybackGuard.stop()
        livePulseStore.shutdown()
        agentBridge.shutdown()
    }

    public func handleIncomingURL(_ url: URL) {
        if AgentURLActionParser.isActionURL(url) {
            agentBridge.handleActionURL(url)
            return
        }
        if let target = commandTarget {
            target.handleIncomingURL(url)
        } else if let resolved = YouTubeURLRouter.resolveCustomSchemeURL(url) {
            let finalURL = settings.redirectShortsToWatch
                ? (YouTubeURLRouter.rewriteShortsURL(resolved) ?? resolved)
                : resolved
            openURLInNewWindow(finalURL)
        }
    }

    public func handleDroppedURL(_ url: URL) {
        if let target = commandTarget {
            target.handleDroppedURL(url)
        } else {
            openURLInNewWindow(url)
        }
    }

    public func openURLFromClipboard() {
        if let target = commandTarget {
            target.openURLFromClipboard()
            return
        }
        guard let clip = NSPasteboard.general.string(forType: .string),
              let url = YouTubeURLRouter.extractYouTubeURLFromString(clip) else {
            return
        }
        let targetURL = settings.redirectShortsToWatch
            ? (YouTubeURLRouter.rewriteShortsURL(url) ?? url)
            : url
        openURLInNewWindow(targetURL)
    }

    func pauseAllWindows(reason: SystemAutoPauseReason? = nil) {
        for controller in openWindows {
            controller.pauseAllPlayingTabs(reason: reason)
        }
    }

    // MARK: - Shared Storage / Website Data Actions (Settings)

    public func clearLocalHistory() {
        settings.clearLocalHistory()
        commandTarget?.showHUD(icon: "trash", message: "Local History Cleared")
    }

    public func clearWebCache() async {
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: cacheTypes)
        await store.removeData(ofTypes: cacheTypes, for: records)
    }

    public var isSigningOutData: Bool = false

    public func clearAllWebsiteData() async {
        guard !isSigningOutData else { return }
        isSigningOutData = true
        defer { isSigningOutData = false }

        let store = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: allTypes)
        await store.removeData(ofTypes: allTypes, for: records)
        await syncThemeCookieToWebKitStore()

        for controller in openWindows {
            controller.reloadAllTabsToStartupDestination()
        }
    }

    public func openSignIn() {
        if let target = commandTarget {
            target.openSignIn()
        } else if let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube") {
            openURLInNewWindow(url, routingMode: .youtube)
        }
    }

    public func openGoogleAccount() {
        if let target = commandTarget {
            target.openGoogleAccount()
        } else if let url = URL(string: "https://myaccount.google.com/") {
            openURLInNewWindow(url, routingMode: .youtube)
        }
    }

    /// Clears WebKit site data and in-memory HTTP cookies strictly matching `service.dataDomains`
    /// without touching unrelated streaming services, then safely refreshes eligible matching open tabs across all windows.
    public func resetServiceData(for service: StreamingService) async {
        serviceResetGeneration[service.id, default: 0] += 1
        for controller in openWindows {
            controller.cancelSignInCheckTasks(forServiceID: service.id)
        }

        let store = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        let records = await store.dataRecords(ofTypes: allTypes)
        let matchingRecords = records.filter { record in
            StreamingServiceCatalog.matchesDataRecord(displayName: record.displayName, for: service)
        }
        if !matchingRecords.isEmpty {
            await store.removeData(ofTypes: allTypes, for: matchingRecords)
        }

        // Also purge in-memory session cookies that can survive record removal until relaunch.
        let cookieStore = store.httpCookieStore
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where StreamingServiceCatalog.matchesCookieDomain(cookie.domain, for: service) {
            await cookieStore.deleteCookie(cookie)
        }

        settings.setServiceSignedIn(service.id, signedIn: false)

        // Safely reload eligible open tabs belonging to the reset service (never mutate fullscreen or sleeping/lazy tabs).
        for controller in openWindows where !controller.hasLiveFullscreenTab {
            for tab in controller.tabs {
                guard !tab.isInFullscreen,
                      tab.webView.fullscreenState == .notInFullscreen,
                      !tab.isSleeping,
                      tab.pendingLazyURL == nil,
                      StreamingServiceCatalog.service(matchingURL: tab.url)?.id == service.id else {
                    continue
                }
                tab.authFlowServiceID = nil
                if StreamingServiceCatalog.isTransientAuthURL(tab.url) {
                    tab.load(service.homeURL)
                } else {
                    tab.loadError = nil
                    tab.webView.reload()
                }
            }
        }
        commandTarget?.showHUD(icon: "arrow.counterclockwise", message: "Reset \(service.name) Login & Data")
    }

    /// Reloads non-playing, non-fullscreen, non-sleeping tabs for `service` after a new sign-in completes elsewhere.
    public func refreshIdleTabs(for service: StreamingService, excludingTabID: UUID? = nil) {
        for controller in openWindows where !controller.hasLiveFullscreenTab {
            for tab in controller.tabs {
                guard tab.id != excludingTabID,
                      !controller.isTabPoppedOut(tab.id),
                      !tab.isInFullscreen,
                      tab.webView.fullscreenState == .notInFullscreen,
                      !tab.mediaStatus.isPlaying,
                      !tab.isSleeping,
                      tab.pendingLazyURL == nil,
                      !tab.isLoading,
                      StreamingServiceCatalog.service(matchingURL: tab.url)?.id == service.id else {
                    continue
                }
                if StreamingServiceCatalog.isTransientAuthURL(tab.url) {
                    tab.load(service.homeURL)
                } else {
                    tab.loadError = nil
                    tab.webView.reload()
                }
            }
        }
    }

    // MARK: - AirPlay Audio Output & Connected Displays

    public func refreshAudioOutputStatus() {
        let status = SystemPlaybackGuard.readCurrentAudioOutputStatus()
        currentAudioOutputName = status.name
        isAirPlayAudioActive = status.isAirPlay
    }

    public func refreshConnectedDisplays() {
        let screens = NSScreen.screens
        let primaryID = screens.first.flatMap(Self.displayID(for:))
        connectedDisplays = screens.compactMap { screen in
            guard let id = Self.displayID(for: screen) else { return nil }
            let scale = screen.backingScaleFactor
            let pixelW = Int((screen.frame.width * scale).rounded())
            let pixelH = Int((screen.frame.height * scale).rounded())
            return ConnectedDisplayDescriptor(
                id: id,
                name: screen.localizedName,
                visibleFrame: screen.visibleFrame,
                pixelWidth: pixelW,
                pixelHeight: pixelH,
                isPrimary: id == primaryID
            )
        }
    }

    public static func displayID(for screen: NSScreen) -> UInt32? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return num.uint32Value
    }

    public func openSoundOutputSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
            NSWorkspace.shared.open(fallback)
        }
    }

    public func openDisplaysSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.displays") {
            NSWorkspace.shared.open(fallback)
        }
    }

    // MARK: - Shared Observers & Theme Cookie Sync

    private func bindSharedSettingsObservers() {
        settings.onWebConfigDidChange = { [weak self] in
            guard let self else { return }
            for controller in self.openWindows {
                controller.applyConfigToAllTabs()
            }
        }
        settings.onWindowPreferencesDidChange = { [weak self] in
            guard let self else { return }
            self.floatingMiniPlayer.updateCollectionBehavior(allSpaces: self.settings.miniPlayerAllSpaces)
            for controller in self.openWindows {
                controller.applyWindowLevelAndCollectionBehavior()
            }
        }
        settings.onAppearanceDidChange = { [weak self] in
            self?.handleAppearanceDidChange()
        }
        settings.onSponsorBlockSettingDidChange = { [weak self] enabled in
            guard let self else { return }
            for controller in self.openWindows {
                controller.handleSponsorBlockSettingChanged(enabled: enabled)
            }
        }
        settings.onSystemPlaybackGuardSettingDidChange = { [weak self] enabled in
            self?.updateSystemPlaybackGuard(enabled: enabled)
        }
        settings.onMultiviewAudioDuckingDidChange = { [weak self] _ in
            guard let self else { return }
            for controller in self.openWindows {
                controller.refreshMultiviewAudioDuckingIfActive()
            }
        }
        settings.onMiniPlayerOpacityDidChange = { [weak self] opacity in
            self?.floatingMiniPlayer.updateOpacity(opacity)
        }
        settings.onAgentSettingsDidChange = { [weak self] in
            self?.agentBridge.reconcileServerState()
        }
        settings.onShortcutsParametersDidChange = {
            GlassGridShortcutsProvider.updateAppShortcutParameters()
        }
        settings.onLivePulseSettingsDidChange = { [weak self] in
            guard let self else { return }
            for controller in self.openWindows {
                controller.syncLivePulseVisibilityFromSettings()
            }
            self.livePulseStore.reconcileLifecycle()
        }
    }

    private func bindSharedFloatingMiniPlayerCallbacks() {
        floatingMiniPlayer.onFrameChanged = { [weak self] frame in
            self?.settings.savedMiniPlayerFrame = frame
        }
        floatingMiniPlayer.onGridFrameChanged = { [weak self] frame in
            self?.settings.savedMiniPlayerGridFrame = frame
        }
        floatingMiniPlayer.onOpacityChanged = { [weak self] opacity in
            self?.settings.miniPlayerOpacity = opacity
        }
        floatingMiniPlayer.onWindowClosedExternally = { [weak self] in
            guard let self,
                  let ownerID = self.floatingMiniPlayerOwnerWindowID,
                  let owner = self.controllersByID[ownerID] else {
                return
            }
            owner.closeMiniPlayerPopup()
        }
    }

    private func updateSystemPlaybackGuard(enabled: Bool) {
        if enabled {
            systemPlaybackGuard.start(
                onAutoPause: { [weak self] reason in
                    self?.pauseAllWindows(reason: reason)
                },
                onAudioRouteChanged: { [weak self] name, isAirPlay in
                    self?.currentAudioOutputName = name
                    self?.isAirPlayAudioActive = isAirPlay
                }
            )
        } else {
            systemPlaybackGuard.stop()
            refreshAudioOutputStatus()
        }
    }

    private func handleAppearanceDidChange() {
        appearanceSyncTask?.cancel()
        appearanceSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncThemeCookieToWebKitStore()
            guard !Task.isCancelled else { return }
            for controller in self.openWindows {
                controller.applyConfigToAllTabs()
            }
        }
    }

    public func syncThemeCookieToWebKitStore() async {
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
}
