import AppKit
import Foundation
import Observation
import WebKit
import YouTubeMacCore

/// Isolated observable playback timeline so per-second progress updates only invalidate the menu bar progress subview.
@MainActor
@Observable
public final class PlaybackTimeline {
    public var currentTime: Double = 0
    public var duration: Double = 0

    public var progressFraction: Double {
        guard duration.isFinite, duration > 0, currentTime.isFinite, currentTime >= 0 else {
            return 0
        }
        return min(max(currentTime / duration, 0), 1)
    }

    public func update(currentTime newTime: Double, duration newDuration: Double) {
        let clampedTime = newTime.isFinite && newTime >= 0 ? newTime : 0
        let clampedDuration = newDuration.isFinite && newDuration >= 0 ? newDuration : 0

        let oldTimeSec = Int(currentTime.rounded(.down))
        let newTimeSec = Int(clampedTime.rounded(.down))
        let oldDurSec = Int(duration.rounded(.down))
        let newDurSec = Int(clampedDuration.rounded(.down))

        if oldTimeSec != newTimeSec || (clampedTime == 0 && currentTime != 0) {
            currentTime = clampedTime
        }
        if oldDurSec != newDurSec || (clampedDuration == 0 && duration != 0) {
            duration = clampedDuration
        }
    }
}

/// `WKWebView` subclass that accepts first-click mouse events immediately (for inactive floating Mini-Player)
/// and notifies click-to-focus in Multiview without consuming the click event.
@MainActor
private final class InteractiveWebView: WKWebView {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

/// Weak proxy preventing `WKUserContentController` from retaining `BrowserTab`.
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: (any WKScriptMessageHandler)?

    init(target: any WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Represents a single persistent WebKit tab with YouTube distraction-free scripting and media state.
@MainActor
@Observable
public final class BrowserTab: NSObject, Identifiable {
    public let id = UUID()
    public let routingMode: TabRoutingMode
    public var title: String = "YouTube"
    public var url: URL
    public var isLoading: Bool = false
    public var estimatedProgress: Double = 0
    public var canGoBack: Bool = false
    public var canGoForward: Bool = false
    public var mediaStatus: MediaStatus = .empty
    public var isInFullscreen: Bool = false
    public var loadError: TabLoadError?
    public var chapters: [VideoChapter] = []
    public var videoDescription: String = ""
    public var videoDescriptionWasTruncated: Bool = false
    public var isSleeping: Bool = false
    public var isCleanBoxBypassed: Bool = false
    public var pageZoom: CGFloat = 1.0 {
        didSet {
            webView.pageZoom = pageZoom
        }
    }

    @ObservationIgnored
    public var pendingLazyURL: URL?

    @ObservationIgnored
    private var lastProcessTerminationAt: Date = .distantPast

    @ObservationIgnored
    public let timeline = PlaybackTimeline()

    @ObservationIgnored
    public let webView: WKWebView

    @ObservationIgnored
    private var observations: [NSKeyValueObservation] = []

    @ObservationIgnored
    private var isTornDown = false

    @ObservationIgnored
    private var lastAppliedConfig: DistractionFreeConfig?

    @ObservationIgnored
    private var lastAppliedSponsorPayload: (videoID: String, segments: [SponsorSegment])?

    @ObservationIgnored
    var needsPostAttachResize = false

    @ObservationIgnored
    private var postAttachResizeTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeMediaFrameInfo: WKFrameInfo?

    @ObservationIgnored
    private var mainFrameMediaStatus: MediaStatus = .empty

    @ObservationIgnored
    private var subframeMediaStatus: MediaStatus?

    @ObservationIgnored
    private var subframeCleanBoxSyncAttempts: Int = 0

    @ObservationIgnored
    private var lastSubframeCleanBoxSyncAt: Date = .distantPast

    @ObservationIgnored
    private var documentLoadedOnCompanionAuthPage: Bool = false

    @ObservationIgnored
    var configProvider: () -> DistractionFreeConfig

    @ObservationIgnored
    var routingPreferencesProvider: () -> (openExternalLinksInBrowser: Bool, redirectShortsToWatch: Bool)

    @ObservationIgnored
    var onOpenInNewTab: ((URL, Bool) -> Void)?

    @ObservationIgnored
    var onStartedPlaying: ((UUID) -> Void)?

    @ObservationIgnored
    var onURLDidChange: ((UUID, URL) -> Void)?

    @ObservationIgnored
    var onSponsorSkipped: ((String) -> Void)?

    @ObservationIgnored
    var onDidClickContent: ((UUID) -> Void)?

    @ObservationIgnored
    var onUnmutedByUser: ((UUID) -> Void)?

    @ObservationIgnored
    var onFullscreenDidChange: ((UUID, Bool) -> Void)?

    @ObservationIgnored
    var onVideoEnded: ((UUID) -> Void)?

    @ObservationIgnored
    var onWatchProgress: ((_ videoID: String, _ title: String, _ channel: String, _ channelURL: String, _ currentTime: Double, _ duration: Double, _ isNewVideoWatch: Bool) -> Void)?

    @ObservationIgnored
    var onDidFinishNavigation: ((UUID, URL) -> Void)?

    @ObservationIgnored
    public var authFlowServiceID: String?

    @ObservationIgnored
    private var lastKnownServiceID: String?

    private static let maxOAuthPopups = 3

    @ObservationIgnored
    private var lastSavedWatchProgressTime: Date = .distantPast

    @ObservationIgnored
    private var lastSavedWatchVideoID: String = ""

    @ObservationIgnored
    private var lastRecordedChannelVideoID: String = ""

    @ObservationIgnored
    private var oauthPopupWindows: [ObjectIdentifier: NSWindow] = [:]

    @ObservationIgnored
    private var oauthPopupWebViews: [ObjectIdentifier: WKWebView] = [:]

    @ObservationIgnored
    private var oauthPopupObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]

    internal static let safariUserAgentSuffix: String = {
        let safariPlistPath = "/Applications/Safari.app/Contents/Info.plist"
        if let plist = NSDictionary(contentsOfFile: safariPlistPath),
           let version = plist["CFBundleShortVersionString"] as? String,
           !version.isEmpty {
            return "Version/\(version) Safari/605.1.15"
        }
        return "Version/18.3 Safari/605.1.15"
    }()

    public init(
        initialURL: URL,
        initialTitle: String? = nil,
        routingMode: TabRoutingMode? = nil,
        initialConfig: DistractionFreeConfig,
        deferInitialLoad: Bool = false,
        lazyLoad: Bool = false,
        configProvider: @escaping () -> DistractionFreeConfig,
        routingPreferencesProvider: @escaping () -> (openExternalLinksInBrowser: Bool, redirectShortsToWatch: Bool),
        onOpenInNewTab: ((URL, Bool) -> Void)? = nil
    ) {
        let resolvedRoutingMode = routingMode ?? YouTubeURLRouter.preferredRoutingMode(for: initialURL)
        self.routingMode = resolvedRoutingMode
        self.url = initialURL
        if let initialTitle, !initialTitle.isEmpty {
            self.title = initialTitle
        } else if resolvedRoutingMode == .companion {
            self.title = initialURL.host?.replacingOccurrences(of: "www.", with: "") ?? "Web"
        }
        if lazyLoad {
            self.pendingLazyURL = initialURL
        }
        self.lastAppliedConfig = initialConfig
        self.configProvider = configProvider
        self.routingPreferencesProvider = routingPreferencesProvider
        self.onOpenInNewTab = onOpenInNewTab
        let initialServiceID = StreamingServiceCatalog.service(matchingURL: initialURL)?.id
        self.lastKnownServiceID = initialServiceID
        if StreamingServiceCatalog.isTransientAuthURL(initialURL) {
            self.authFlowServiceID = initialServiceID
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = Self.safariUserAgentSuffix

        let userScript = WKUserScript(
            source: EnhancementScript.bootstrapScript(config: initialConfig),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(userScript)

        let subframeScript = WKUserScript(
            source: EnhancementScript.subframeMediaBridgeScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(subframeScript)

        let webView = InteractiveWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua
                ? NSColor(calibratedRed: 0.059, green: 0.059, blue: 0.059, alpha: 1.0)
                : .white
        }
        self.webView = webView

        super.init()

        let weakHandler = WeakScriptMessageHandler(target: self)
        configuration.userContentController.add(weakHandler, name: EnhancementScript.messageHandlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.onMouseDown = { [weak self] in
            guard let self else { return }
            self.onDidClickContent?(self.id)
        }

        installObservations()
        if !deferInitialLoad && !lazyLoad {
            webView.load(URLRequest(url: initialURL))
        }
    }

    public var isCompanionTab: Bool {
        if routingMode == .companion {
            return true
        }
        guard let host = url.host else { return false }
        return !YouTubeURLRouter.isYouTubeHost(host) && !YouTubeURLRouter.isGoogleAuthHost(host)
    }

    public var displayTitle: String {
        let cleaned = YouTubeTitleFormatter.clean(title)
        if !cleaned.isEmpty {
            return cleaned
        }
        let mediaCleaned = YouTubeTitleFormatter.clean(mediaStatus.title)
        if !mediaCleaned.isEmpty {
            return mediaCleaned
        }
        if isCompanionTab {
            return url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web"
        }
        return "YouTube"
    }

    public func load(_ targetURL: URL) {
        pendingLazyURL = nil
        isSleeping = false
        isCleanBoxBypassed = false
        loadError = nil
        chapters = []
        videoDescription = ""
        videoDescriptionWasTruncated = false
        mainFrameMediaStatus = .empty
        clearSubframeMediaState()
        documentLoadedOnCompanionAuthPage = false
        if !StreamingServiceCatalog.isTransientAuthURL(targetURL) {
            let nextServiceID = StreamingServiceCatalog.service(matchingURL: targetURL)?.id
            if nextServiceID != authFlowServiceID {
                authFlowServiceID = nil
            }
            lastKnownServiceID = nextServiceID
        } else {
            updateAuthFlowTracking(for: targetURL)
        }
        url = targetURL
        webView.load(URLRequest(url: targetURL))
    }

    public func loadPendingIfNeeded() {
        guard !isTornDown, let pending = pendingLazyURL else { return }
        pendingLazyURL = nil
        isSleeping = false
        loadError = nil
        webView.load(URLRequest(url: pending))
    }

    public func putToSleep() {
        guard !isTornDown, !isSleeping else { return }
        let preservedURL = pendingLazyURL ?? url
        pendingLazyURL = preservedURL
        isSleeping = true
        pauseAllPlayback()
        mainFrameMediaStatus = .empty
        clearSubframeMediaState()
        documentLoadedOnCompanionAuthPage = false
        mediaStatus = .empty
        chapters = []
        videoDescription = ""
        videoDescriptionWasTruncated = false
        loadError = nil
        timeline.update(currentTime: 0, duration: 0)
        if let blankURL = URL(string: "about:blank") {
            webView.load(URLRequest(url: blankURL))
        }
    }

    public func setBackForwardGesturesEnabled(_ enabled: Bool) {
        if webView.allowsBackForwardNavigationGestures != enabled {
            webView.allowsBackForwardNavigationGestures = enabled
        }
    }

    public func goBack() {
        webView.goBack()
    }

    public func goForward() {
        webView.goForward()
    }

    public func reloadOrStop() {
        if pendingLazyURL != nil {
            loadPendingIfNeeded()
            return
        }
        if isLoading {
            webView.stopLoading()
        } else if let failed = loadError {
            loadError = nil
            let retryURL = failed.failingURLString.flatMap(URL.init(string:)) ?? url
            webView.load(URLRequest(url: retryURL))
        } else {
            webView.reload()
        }
    }

    public func findOnPage(_ query: String, backwards: Bool = false) async -> Bool {
        guard !isTornDown, pendingLazyURL == nil else { return false }
        let trimmed = query.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else {
            clearFindHighlight()
            return false
        }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.caseSensitive = false
        config.wraps = true
        return await withCheckedContinuation { continuation in
            webView.find(trimmed, configuration: config) { result in
                continuation.resume(returning: result.matchFound)
            }
        }
    }

    public func clearFindHighlight() {
        guard !isTornDown else { return }
        let config = WKFindConfiguration()
        // Passing "" is a WebKit no-op; a Unicode non-character sentinel clears WebKit's yellow find-indicator overlay cleanly.
        webView.find("\u{FFFF}\u{FFFE}\u{FFFF}", configuration: config) { _ in }
        evaluate(EnhancementScript.clearSelectionScript)
    }

    public func reloadFromOrigin() {
        webView.reloadFromOrigin()
    }

    public func focusWebContent() {
        webView.window?.makeFirstResponder(webView)
    }

    public func applyConfig(_ config: DistractionFreeConfig, force: Bool = false) {
        guard !isTornDown else { return }
        if isCompanionTab && StreamingServiceCatalog.isTransientAuthURL(webView.url ?? url) {
            return
        }
        if !force && config == lastAppliedConfig {
            return
        }
        lastAppliedConfig = config
        // Never fire JS resize from applyConfig: mini-player CSS already pins video to 100%, and dock-back
        // runs a bounded post-attach resize pass in TabWebViewHost after full-size container layout.
        let script = EnhancementScript.applyConfigScript(config, triggerResize: false)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public func cancelPostAttachResize() {
        postAttachResizeTask?.cancel()
        postAttachResizeTask = nil
    }

    public func schedulePostAttachResize(in container: NSView, useMultiviewSync: Bool = false) {
        cancelPostAttachResize()
        postAttachResizeTask = Task { @MainActor [weak self, weak container] in
            for delayMs in [80, 240] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled,
                      let self,
                      let container,
                      !self.isTornDown,
                      !self.isInFullscreen,
                      self.webView.fullscreenState == .notInFullscreen,
                      self.webView.superview === container,
                      !self.webView.isHidden else {
                    return
                }
                if useMultiviewSync {
                    self.evaluate(EnhancementScript.syncPlayerSizeScript)
                } else {
                    self.evaluate(EnhancementScript.notifyViewportResizeScript)
                }
            }
            self?.postAttachResizeTask = nil
        }
    }

    public func evaluate(_ script: String) {
        guard !isTornDown else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public func evaluateMediaCommand(_ script: String) {
        guard !isTornDown else { return }
        if !mainFrameMediaStatus.hasVideo, let targetFrame = activeMediaFrameInfo {
            webView.evaluateJavaScript(script, in: targetFrame, in: .page) { [weak self] result in
                if case .failure = result {
                    Task { @MainActor [weak self] in
                        guard let self, !self.isTornDown else { return }
                        self.clearSubframeMediaState()
                        _ = try? await self.webView.evaluateJavaScript(script)
                    }
                }
            }
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public func evaluateMediaCommandAsync(_ script: String) async -> (value: Any?, usedSubframe: Bool) {
        guard !isTornDown else { return (nil, false) }
        if !mainFrameMediaStatus.hasVideo, let targetFrame = activeMediaFrameInfo {
            do {
                let value = try await webView.evaluateJavaScript(script, in: targetFrame, contentWorld: .page)
                return (value, true)
            } catch {
                clearSubframeMediaState()
            }
        }
        let value = try? await webView.evaluateJavaScript(script)
        return (value, false)
    }

    public func togglePlayPause() {
        evaluateMediaCommand(EnhancementScript.togglePlayPauseScript)
    }

    public func playMedia() {
        evaluateMediaCommand(EnhancementScript.playScript)
    }

    public func pauseMedia() {
        evaluateMediaCommand(EnhancementScript.pauseScript)
    }

    public func pauseAllPlayback() {
        guard !isTornDown else { return }
        pauseMedia()
        webView.pauseAllMediaPlayback(completionHandler: nil)
    }

    public func toggleMute() {
        evaluateMediaCommand(EnhancementScript.toggleMuteScript)
    }

    public func setMuted(_ muted: Bool) {
        evaluateMediaCommand(EnhancementScript.setMutedScript(muted: muted))
    }

    public func setAudioLevel(muted: Bool, volumePercent: Int) {
        evaluateMediaCommand(EnhancementScript.setAudioLevelScript(muted: muted, volumePercent: volumePercent))
    }

    public func seekBy(seconds: Double) {
        evaluateMediaCommand(EnhancementScript.seekByScript(seconds: seconds))
    }

    public func seekTo(seconds: Double) {
        evaluateMediaCommand(EnhancementScript.seekToScript(seconds: seconds))
    }

    public func seekToLiveEdge() {
        evaluateMediaCommand(EnhancementScript.seekToLiveEdgeScript)
    }

    public func setPlaybackRate(_ rate: Double) {
        evaluateMediaCommand(EnhancementScript.setPlaybackRateScript(rate: rate))
    }

    public func togglePictureInPicture() async -> Bool {
        let result = await evaluateMediaCommandAsync(EnhancementScript.togglePictureInPictureScript)
        return (result.value as? Bool) ?? false
    }

    public func syncPlayerSize() {
        guard !isInFullscreen, webView.fullscreenState == .notInFullscreen else { return }
        evaluate(EnhancementScript.syncPlayerSizeScript)
    }

    public func showAirPlayPicker() async -> AirPlayPickerResult {
        guard !isTornDown else { return .noVideo }
        let outcome = await evaluateMediaCommandAsync(EnhancementScript.showAirPlayPickerScript)
        let raw = outcome.value as? String
        return raw.flatMap(AirPlayPickerResult.init(rawValue:)) ?? .unavailable
    }

    public func captureVideoFrame() async -> (result: Any?, usedSubframe: Bool) {
        let outcome = await evaluateMediaCommandAsync(EnhancementScript.captureVideoFrameScript)
        return (result: outcome.value, usedSubframe: outcome.usedSubframe)
    }

    public func closeAllOAuthPopups() {
        let windows = Array(oauthPopupWindows.values)
        let webViews = Array(oauthPopupWebViews.values)
        let observers = Array(oauthPopupObservers.values)
        oauthPopupWindows.removeAll()
        oauthPopupWebViews.removeAll()
        oauthPopupObservers.removeAll()

        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        for childWV in webViews {
            childWV.uiDelegate = nil
            childWV.navigationDelegate = nil
            childWV.stopLoading()
        }
        for win in windows {
            win.close()
        }
    }

    private func cleanupOAuthPopup(for popupWebView: WKWebView) {
        let key = ObjectIdentifier(popupWebView)
        if let obs = oauthPopupObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(obs)
        }
        oauthPopupWebViews.removeValue(forKey: key)
        popupWebView.uiDelegate = nil
        popupWebView.navigationDelegate = nil
        popupWebView.stopLoading()
        if let win = oauthPopupWindows.removeValue(forKey: key) {
            win.close()
        }
    }

    private func presentOAuthPopup(with configuration: WKWebViewConfiguration, title: String) -> WKWebView {
        if let activeID = lastKnownServiceID ?? StreamingServiceCatalog.service(matchingURL: webView.url ?? url)?.id {
            authFlowServiceID = activeID
        }
        let popupSize = NSSize(width: 520, height: 680)
        let popupWebView = WKWebView(frame: NSRect(origin: .zero, size: popupSize), configuration: configuration)
        popupWebView.customUserAgent = webView.customUserAgent
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self

        let popupWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: popupSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Mandatory Gate 1 safety: retain popupWindow cleanly and never double-release on close.
        popupWindow.isReleasedWhenClosed = false
        popupWindow.title = title
        popupWindow.contentView = popupWebView
        popupWindow.center()

        let key = ObjectIdentifier(popupWebView)
        oauthPopupWindows[key] = popupWindow
        oauthPopupWebViews[key] = popupWebView
        oauthPopupObservers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: popupWindow,
            queue: .main
        ) { [weak self, weak popupWebView] _ in
            MainActor.assumeIsolated {
                guard let self, let popupWebView else { return }
                let k = ObjectIdentifier(popupWebView)
                if let obs = self.oauthPopupObservers.removeValue(forKey: k) {
                    NotificationCenter.default.removeObserver(obs)
                }
                self.oauthPopupWebViews.removeValue(forKey: k)
                self.oauthPopupWindows.removeValue(forKey: k)
                popupWebView.uiDelegate = nil
                popupWebView.navigationDelegate = nil
                popupWebView.stopLoading()
            }
        }

        popupWindow.makeKeyAndOrderFront(nil)
        return popupWebView
    }

    private func updateAuthFlowTracking(for targetURL: URL) {
        if StreamingServiceCatalog.isTransientAuthURL(targetURL) {
            if let host = targetURL.host, StreamingServiceCatalog.isSharedThirdPartySSOHost(host) {
                authFlowServiceID = lastKnownServiceID
                    ?? StreamingServiceCatalog.service(matchingURL: targetURL)?.id
                    ?? authFlowServiceID
            } else {
                authFlowServiceID = StreamingServiceCatalog.service(matchingURL: targetURL)?.id
                    ?? lastKnownServiceID
                    ?? authFlowServiceID
            }
        } else if let svcID = StreamingServiceCatalog.service(matchingURL: targetURL)?.id {
            lastKnownServiceID = svcID
        }
    }

    public func applySponsorSegments(videoID: String, segments: [SponsorSegment]) {
        guard !isTornDown else { return }
        if let last = lastAppliedSponsorPayload, last.videoID == videoID && last.segments == segments {
            return
        }
        lastAppliedSponsorPayload = (videoID, segments)
        let script = EnhancementScript.setSponsorSegmentsScript(videoID: videoID, segments: segments)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public func clearSponsorSegments() {
        lastAppliedSponsorPayload = nil
        evaluate(EnhancementScript.setSponsorSegmentsScript(videoID: "", segments: []))
    }

    public func teardown() {
        guard !isTornDown else { return }
        // Pause active video & WebKit media BEFORE setting isTornDown so evaluate() executes cleanly.
        closeAllOAuthPopups()
        cancelPostAttachResize()
        clearSubframeMediaState()
        pauseMedia()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        isTornDown = true

        webView.stopLoading()
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: EnhancementScript.messageHandlerName
        )
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        (webView as? InteractiveWebView)?.onMouseDown = nil
        onOpenInNewTab = nil
        onStartedPlaying = nil
        onURLDidChange = nil
        onSponsorSkipped = nil
        onDidClickContent = nil
        onUnmutedByUser = nil
        onFullscreenDidChange = nil
        onVideoEnded = nil
        onWatchProgress = nil
        onDidFinishNavigation = nil
        authFlowServiceID = nil
        lastKnownServiceID = nil
        documentLoadedOnCompanionAuthPage = false
    }

    private func installObservations() {
        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.syncTitleFromWebView()
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.syncURLFromWebView()
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let loading = self.webView.isLoading
                    if self.isLoading != loading {
                        self.isLoading = loading
                    }
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let progress = self.webView.estimatedProgress
                    if abs(self.estimatedProgress - progress) >= 0.02 || progress == 1.0 {
                        self.estimatedProgress = progress
                    }
                }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let canBack = self.webView.canGoBack
                    if self.canGoBack != canBack {
                        self.canGoBack = canBack
                    }
                }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let canFwd = self.webView.canGoForward
                    if self.canGoForward != canFwd {
                        self.canGoForward = canFwd
                    }
                }
            },
            webView.observe(\.fullscreenState, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let active = self.webView.fullscreenState != .notInFullscreen
                    if self.isInFullscreen != active {
                        self.isInFullscreen = active
                        self.onFullscreenDidChange?(self.id, active)
                    }
                }
            }
        ]
    }

    private func syncTitleFromWebView() {
        guard !isSleeping && pendingLazyURL == nil else { return }
        if let webTitle = webView.title, !webTitle.isEmpty, title != webTitle {
            title = webTitle
        }
    }

    private func clearSubframeMediaState() {
        activeMediaFrameInfo = nil
        subframeMediaStatus = nil
        subframeCleanBoxSyncAttempts = 0
        lastSubframeCleanBoxSyncAt = .distantPast
        if !isTornDown && !isSleeping {
            evaluate(EnhancementScript.clearSubframeMediaActiveScript)
        }
        recomputeMergedMediaStatus()
        if !mainFrameMediaStatus.hasVideo {
            timeline.update(currentTime: 0, duration: 0)
        }
    }

    private func recomputeMergedMediaStatus() {
        let resolved: MediaStatus
        if mainFrameMediaStatus.hasVideo {
            resolved = mainFrameMediaStatus
        } else if let sub = subframeMediaStatus, sub.hasVideo {
            resolved = MediaStatus(
                hasVideo: true,
                isPlaying: sub.isPlaying,
                title: mainFrameMediaStatus.title.isEmpty ? title : mainFrameMediaStatus.title,
                channel: mainFrameMediaStatus.channel,
                channelURLString: mainFrameMediaStatus.channelURLString,
                urlString: mainFrameMediaStatus.urlString.isEmpty ? url.absoluteString : mainFrameMediaStatus.urlString,
                isMuted: sub.isMuted,
                isPiP: sub.isPiP,
                isTheater: mainFrameMediaStatus.isTheater,
                isHDR: sub.isHDR || mainFrameMediaStatus.isHDR,
                playbackRate: sub.playbackRate,
                isHomeFeedEmpty: mainFrameMediaStatus.isHomeFeedEmpty,
                airPlayAvailable: sub.airPlayAvailable,
                isAirPlayActive: sub.isAirPlayActive,
                isCleanBoxActive: mainFrameMediaStatus.isCleanBoxActive,
                isCleanBoxEligible: mainFrameMediaStatus.isCleanBoxEligible || sub.hasVideo
            )
        } else {
            resolved = mainFrameMediaStatus
        }
        if mediaStatus != resolved {
            mediaStatus = resolved
        }
    }

    private func syncURLFromWebView() {
        guard !isSleeping && pendingLazyURL == nil else { return }
        if let webURL = webView.url, webURL.scheme?.lowercased() != "about" {
            updateAuthFlowTracking(for: webURL)
            if url != webURL {
                let oldVideoID = YouTubeURLRouter.extractVideoID(from: url)
                let newVideoID = YouTubeURLRouter.extractVideoID(from: webURL)
                if oldVideoID != newVideoID {
                    chapters = []
                    videoDescription = ""
                    videoDescriptionWasTruncated = false
                }
                let oldPathKey = (url.host ?? "").lowercased() + "|" + url.path.lowercased() + "|" + (oldVideoID ?? "")
                let newPathKey = (webURL.host ?? "").lowercased() + "|" + webURL.path.lowercased() + "|" + (newVideoID ?? "")
                var didResetCleanBoxBypass = false
                if oldPathKey != newPathKey {
                    clearSubframeMediaState()
                    if isCleanBoxBypassed {
                        isCleanBoxBypassed = false
                        didResetCleanBoxBypass = true
                    }
                }
                url = webURL
                onURLDidChange?(id, webURL)
                if isCompanionTab && StreamingServiceCatalog.isTransientAuthURL(webURL) {
                    if didResetCleanBoxBypass, var updatedConfig = lastAppliedConfig {
                        updatedConfig.cleanBoxBypassed = false
                        applyConfig(updatedConfig, force: true)
                    }
                    evaluate(EnhancementScript.teardownCompanionCleanBoxScript)
                } else if isCompanionTab && documentLoadedOnCompanionAuthPage {
                    documentLoadedOnCompanionAuthPage = false
                    var cfg = configProvider()
                    if didResetCleanBoxBypass {
                        cfg.cleanBoxBypassed = false
                    }
                    lastAppliedConfig = cfg
                    evaluate(EnhancementScript.bootstrapScript(config: cfg))
                } else {
                    if didResetCleanBoxBypass, var updatedConfig = lastAppliedConfig {
                        updatedConfig.cleanBoxBypassed = false
                        applyConfig(updatedConfig, force: true)
                    }
                    if let host = webURL.host, !YouTubeURLRouter.isStandardYouTubeHost(host) {
                        evaluate(EnhancementScript.notifyRouteChangedScript)
                    }
                }
            }
        }
    }
}

extension BrowserTab: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let targetURL = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Block internal and third-party app-handoff schemes BEFORE subframe exemptions or popup routing.
        if let scheme = targetURL.scheme, YouTubeURLRouter.isBlockedAppScheme(scheme) {
            decisionHandler(.cancel)
            return
        }

        // Dedicated OAuth popup branch: strict web scheme allowlist only (never parent routing or external open).
        if webView !== self.webView {
            if let scheme = targetURL.scheme, YouTubeURLRouter.isAllowedWebScheme(scheme) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
            return
        }

        // Only intercept top-level frame navigations; allow embedded players/iframes normally.
        if let targetFrame = navigationAction.targetFrame, !targetFrame.isMainFrame {
            decisionHandler(.allow)
            return
        }

        let prefs = routingPreferencesProvider()
        let isUserClick = navigationAction.navigationType == .linkActivated

        // Handle Command-click on links to open in a new tab.
        if isUserClick && navigationAction.modifierFlags.contains(.command) {
            let decision = YouTubeURLRouter.routeNavigation(
                url: targetURL,
                currentPageURL: webView.url,
                isUserLinkClick: true,
                openExternalLinksInBrowser: prefs.openExternalLinksInBrowser,
                redirectShortsToWatch: prefs.redirectShortsToWatch,
                routingMode: routingMode
            )
            switch decision {
            case .allowInApp:
                onOpenInNewTab?(targetURL, false)
                decisionHandler(.cancel)
                return
            case .redirectInApp(let rewritten):
                onOpenInNewTab?(rewritten, false)
                decisionHandler(.cancel)
                return
            case .openExternal(let externalURL):
                NSWorkspace.shared.open(externalURL)
                decisionHandler(.cancel)
                return
            case .block:
                decisionHandler(.cancel)
                return
            }
        }

        let decision = YouTubeURLRouter.routeNavigation(
            url: targetURL,
            currentPageURL: webView.url,
            isUserLinkClick: isUserClick,
            openExternalLinksInBrowser: prefs.openExternalLinksInBrowser,
            redirectShortsToWatch: prefs.redirectShortsToWatch,
            routingMode: routingMode
        )

        switch decision {
        case .allowInApp:
            decisionHandler(.allow)
        case .redirectInApp(let rewritten):
            decisionHandler(.cancel)
            webView.load(URLRequest(url: rewritten))
        case .openExternal(let externalURL):
            NSWorkspace.shared.open(externalURL)
            decisionHandler(.cancel)
        case .block:
            decisionHandler(.cancel)
        }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        loadError = nil
        mainFrameMediaStatus = .empty
        clearSubframeMediaState()
        documentLoadedOnCompanionAuthPage = false
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        loadError = nil
        clearSubframeMediaState()
        documentLoadedOnCompanionAuthPage = isCompanionTab && StreamingServiceCatalog.isTransientAuthURL(webView.url ?? url)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        loadError = nil
        syncTitleFromWebView()
        syncURLFromWebView()
        applyConfig(configProvider(), force: true)
        if !isSleeping && pendingLazyURL == nil {
            onDidFinishNavigation?(id, webView.url ?? url)
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        guard webView === self.webView else { return }
        handleNavigationFailure(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard webView === self.webView else { return }
        handleNavigationFailure(error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView !== self.webView {
            if oauthPopupWebViews[ObjectIdentifier(webView)] != nil {
                cleanupOAuthPopup(for: webView)
            }
            return
        }
        guard !isTornDown else { return }
        let now = Date()
        if now.timeIntervalSince(lastProcessTerminationAt) > 30 {
            lastProcessTerminationAt = now
            loadError = nil
            webView.load(URLRequest(url: url))
        } else {
            loadError = TabLoadError.processTerminated(url: url)
        }
    }

    private func handleNavigationFailure(_ error: any Error) {
        let nsError = error as NSError
        // Ignore benign cancellations and WebKit policy-redirect interruptions (e.g. Shorts rewrite or rapid clicks).
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return
        }
        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url ?? url
        loadError = TabLoadError.from(error: nsError, failingURL: failingURL)
    }
}

extension BrowserTab: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let targetURL = navigationAction.request.url
        let rawScheme = targetURL?.scheme?.lowercased() ?? ""
        if targetURL != nil && !rawScheme.isEmpty && !YouTubeURLRouter.isAllowedWebScheme(rawScheme) {
            return nil
        }

        let lowerURLString = targetURL?.absoluteString.lowercased() ?? ""
        let isBlankOpen = targetURL == nil
            || lowerURLString.isEmpty
            || lowerURLString == "about:blank"
            || lowerURLString.hasPrefix("about:blank?")
            || lowerURLString.hasPrefix("about:blank#")
        let currentURL = self.webView.url ?? self.url
        let isAuthOrServiceContext = StreamingServiceCatalog.isTransientAuthURL(currentURL)
            || StreamingServiceCatalog.service(matchingURL: currentURL) != nil

        let isQualifyingPopup: Bool
        if navigationAction.targetFrame == nil && oauthPopupWindows.count < Self.maxOAuthPopups {
            if !isBlankOpen, let url = targetURL {
                isQualifyingPopup = StreamingServiceCatalog.isAuthOrOAuthPopupURL(url)
            } else {
                isQualifyingPopup = isBlankOpen && isAuthOrServiceContext
            }
        } else {
            isQualifyingPopup = false
        }

        // Preserve `window.opener` for OAuth/SSO/MVPD popups (Apple ID, Google OAuth, Amazon OpenID, Crunchyroll SSO).
        if isQualifyingPopup {
            return presentOAuthPopup(with: configuration, title: "Sign In — GlassGrid You")
        }

        // Guardrail #2: Never allow nested popups or unprompted script window.open calls to spawn tabs or launch external apps.
        guard webView === self.webView,
              navigationAction.navigationType == .linkActivated,
              let targetURL,
              !isBlankOpen else {
            return nil
        }

        let prefs = routingPreferencesProvider()
        let decision = YouTubeURLRouter.routeNavigation(
            url: targetURL,
            currentPageURL: self.webView.url,
            isUserLinkClick: true,
            openExternalLinksInBrowser: prefs.openExternalLinksInBrowser,
            redirectShortsToWatch: prefs.redirectShortsToWatch,
            routingMode: routingMode
        )

        switch decision {
        case .allowInApp:
            if let host = targetURL.host, YouTubeURLRouter.isGoogleAuthHost(host) {
                self.webView.load(URLRequest(url: targetURL))
            } else if routingMode == .companion, StreamingServiceCatalog.isTransientAuthURL(targetURL) {
                self.webView.load(URLRequest(url: targetURL))
            } else {
                onOpenInNewTab?(targetURL, true)
            }
        case .redirectInApp(let rewritten):
            onOpenInNewTab?(rewritten, true)
        case .openExternal(let externalURL):
            NSWorkspace.shared.open(externalURL)
        case .block:
            break
        }
        return nil
    }

    public func webViewDidClose(_ webView: WKWebView) {
        if oauthPopupWebViews[ObjectIdentifier(webView)] != nil {
            cleanupOAuthPopup(for: webView)
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        let alert = NSAlert()
        alert.messageText = "GlassGrid You"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "GlassGrid You"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }
}

extension BrowserTab: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard !isTornDown,
              message.webView === self.webView,
              message.name == EnhancementScript.messageHandlerName,
              let body = message.body as? [String: Any] else {
            return
        }

        // Strict origin-scoped subframe bridge (Cross-origin players like Crunchyroll Vilos).
        if !message.frameInfo.isMainFrame {
            guard !isSleeping, pendingLazyURL == nil else { return }
            let mainURL = webView.url ?? url
            guard !StreamingServiceCatalog.isTransientAuthURL(mainURL) else { return }
            let origin = message.frameInfo.securityOrigin
            guard origin.protocol.lowercased() == "https",
                  !origin.host.isEmpty else {
                return
            }
            let originHost = origin.host.lowercased()
            guard CleanBoxRules.isAllowedPlayerIframeHost(originHost, forMainFrameURL: mainURL) else {
                return
            }

            if let event = body["event"] as? String {
                if event == "userUnmuted" {
                    if mediaStatus.hasVideo,
                       mediaStatus.isMuted,
                       let activeHost = activeMediaFrameInfo?.securityOrigin.host.lowercased(),
                       activeHost == originHost {
                        onUnmutedByUser?(id)
                    }
                } else if event == "videoEnded" {
                    onVideoEnded?(id)
                }
                return
            }

            guard body["subframeMedia"] as? Bool == true else { return }
            let prevSubframeHasVideo = subframeMediaStatus?.hasVideo == true
            let subHasVideo = body["hasVideo"] as? Bool ?? false

            if !subHasVideo {
                clearSubframeMediaState()
                return
            }

            let wasPlaying = mediaStatus.isPlaying
            activeMediaFrameInfo = message.frameInfo
            subframeMediaStatus = MediaStatus(
                hasVideo: true,
                isPlaying: body["isPlaying"] as? Bool ?? false,
                title: "",
                channel: "",
                channelURLString: "",
                urlString: "",
                isMuted: body["isMuted"] as? Bool ?? false,
                isPiP: body["isPiP"] as? Bool ?? false,
                isTheater: false,
                isHDR: false,
                playbackRate: body["playbackRate"] as? Double ?? 1.0,
                isHomeFeedEmpty: false,
                airPlayAvailable: body["airPlayAvailable"] as? Bool ?? false,
                isAirPlayActive: body["isAirPlayActive"] as? Bool ?? false
            )
            recomputeMergedMediaStatus()
            if !wasPlaying && mediaStatus.isPlaying {
                onStartedPlaying?(id)
            }
            if !mainFrameMediaStatus.hasVideo {
                let currentTime = body["currentTime"] as? Double ?? 0
                let duration = body["duration"] as? Double ?? 0
                timeline.update(currentTime: currentTime, duration: duration)
            }
            let shouldSyncCleanBox = !isInFullscreen
                && webView.fullscreenState == .notInFullscreen
                && !isCleanBoxBypassed
                && !mainFrameMediaStatus.isCleanBoxActive
                && configProvider().cleanBoxStreamingPlayers
                && subframeCleanBoxSyncAttempts < 3
                && (!prevSubframeHasVideo
                    || (!wasPlaying && mediaStatus.isPlaying)
                    || Date().timeIntervalSince(lastSubframeCleanBoxSyncAt) >= 1.5)
            if shouldSyncCleanBox {
                subframeCleanBoxSyncAttempts += 1
                lastSubframeCleanBoxSyncAt = Date()
                evaluate(EnhancementScript.syncCompanionCleanBoxScript)
            }
            return
        }

        if let event = body["event"] as? String {
            if event == "sponsorSkipped" {
                let category = body["category"] as? String ?? "sponsor"
                onSponsorSkipped?(category)
            } else if event == "userUnmuted" {
                let eventURL = body["urlString"] as? String ?? ""
                if mediaStatus.hasVideo && mediaStatus.isMuted && mediaStatus.urlString == eventURL {
                    onUnmutedByUser?(id)
                }
            } else if event == "videoEnded" {
                onVideoEnded?(id)
            } else if event == "chaptersUpdated" {
                let eventVideoID = body["videoId"] as? String ?? ""
                if eventVideoID.isEmpty {
                    if !chapters.isEmpty { chapters = [] }
                    if !videoDescription.isEmpty {
                        videoDescription = ""
                        videoDescriptionWasTruncated = false
                    }
                    return
                }
                let activeVideoID = YouTubeURLRouter.extractVideoID(from: url)
                    ?? URL(string: mediaStatus.urlString).flatMap(YouTubeURLRouter.extractVideoID(from:))
                guard activeVideoID == nil || activeVideoID == eventVideoID else {
                    return
                }

                let rawChapters = body["chapters"] as? [[String: Any]] ?? []
                let structuredEntries: [(title: String, startSeconds: Double)] = rawChapters.compactMap { dict in
                    guard let title = dict["title"] as? String else { return nil }
                    let secs = (dict["startSeconds"] as? NSNumber)?.doubleValue ?? -1
                    return (title, secs)
                }
                let description = body["description"] as? String ?? ""
                var parsed = VideoChapterParser.normalize(structuredEntries)
                if parsed.isEmpty, !description.isEmpty {
                    let maxDur = timeline.duration > 0 ? timeline.duration : nil
                    parsed = VideoChapterParser.parseFromDescription(description, maxDuration: maxDur)
                }
                if chapters != parsed {
                    chapters = parsed
                }

                let sanitized = AgentSecurity.sanitizeWebText(description, maxLength: AgentSecurity.maxVideoDescriptionLength)
                let wasTruncated = sanitized.truncated || description.count >= 16_384
                if videoDescription != sanitized.text || videoDescriptionWasTruncated != wasTruncated {
                    videoDescription = sanitized.text
                    videoDescriptionWasTruncated = wasTruncated
                }
            }
            return
        }

        let newMainStatus = MediaStatus(
            hasVideo: body["hasVideo"] as? Bool ?? false,
            isPlaying: body["isPlaying"] as? Bool ?? false,
            title: body["title"] as? String ?? "",
            channel: body["channel"] as? String ?? "",
            channelURLString: body["channelURL"] as? String ?? "",
            urlString: body["urlString"] as? String ?? url.absoluteString,
            isMuted: body["isMuted"] as? Bool ?? false,
            isPiP: body["isPiP"] as? Bool ?? false,
            isTheater: body["isTheater"] as? Bool ?? false,
            isHDR: body["isHDR"] as? Bool ?? false,
            playbackRate: body["playbackRate"] as? Double ?? 1.0,
            isHomeFeedEmpty: body["isHomeFeedEmpty"] as? Bool ?? false,
            airPlayAvailable: body["airPlayAvailable"] as? Bool ?? false,
            isAirPlayActive: body["isAirPlayActive"] as? Bool ?? false,
            isCleanBoxActive: body["isCleanBoxActive"] as? Bool ?? false,
            isCleanBoxEligible: body["isCleanBoxEligible"] as? Bool ?? false
        )
        let wasPlaying = mediaStatus.isPlaying
        mainFrameMediaStatus = newMainStatus
        if newMainStatus.hasVideo {
            subframeMediaStatus = nil
            activeMediaFrameInfo = nil
        }
        recomputeMergedMediaStatus()
        if !wasPlaying && mediaStatus.isPlaying {
            onStartedPlaying?(id)
        }

        if mainFrameMediaStatus.hasVideo {
            let currentTime = body["currentTime"] as? Double ?? 0
            let duration = body["duration"] as? Double ?? 0
            timeline.update(currentTime: currentTime, duration: duration)
        } else if subframeMediaStatus?.hasVideo != true {
            timeline.update(currentTime: 0, duration: 0)
        }

        // Throttled Continue Watching & Most Watched Channel tracking (strictly www.youtube.com — skip tv.youtube.com & Companion sites).
        if mediaStatus.hasVideo,
           let parsedURL = URL(string: mediaStatus.urlString) ?? Optional(url),
           YouTubeURLRouter.isStandardYouTubeHost(parsedURL.host),
           let videoID = YouTubeURLRouter.extractVideoID(from: parsedURL) {
            let currentTime = body["currentTime"] as? Double ?? 0
            let duration = body["duration"] as? Double ?? 0
            let now = Date()
            let pausedTransition = wasPlaying && !mediaStatus.isPlaying
            let videoChanged = videoID != lastSavedWatchVideoID
            let elapsed = now.timeIntervalSince(lastSavedWatchProgressTime)
            let isNewChannelRecord = !mediaStatus.channel.isEmpty && videoID != lastRecordedChannelVideoID && currentTime >= 2

            if pausedTransition || (videoChanged && currentTime >= 3) || (mediaStatus.isPlaying && elapsed >= 15) || isNewChannelRecord {
                lastSavedWatchProgressTime = now
                lastSavedWatchVideoID = videoID
                if isNewChannelRecord {
                    lastRecordedChannelVideoID = videoID
                }
                let effectiveTitle = mediaStatus.title.isEmpty ? displayTitle : mediaStatus.title
                onWatchProgress?(videoID, effectiveTitle, mediaStatus.channel, mediaStatus.channelURLString, currentTime, duration, isNewChannelRecord)
            }
        }
    }
}
