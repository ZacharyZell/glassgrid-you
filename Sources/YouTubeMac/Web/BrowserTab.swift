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
    public var isSleeping: Bool = false
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

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = Self.safariUserAgentSuffix

        let userScript = WKUserScript(
            source: EnhancementScript.bootstrapScript(config: initialConfig),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(userScript)

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
        loadError = nil
        chapters = []
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
        mediaStatus = .empty
        chapters = []
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

    public func schedulePostAttachResize(in container: NSView) {
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
                self.evaluate(EnhancementScript.notifyViewportResizeScript)
            }
            self?.postAttachResizeTask = nil
        }
    }

    public func evaluate(_ script: String) {
        guard !isTornDown else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public func pauseMedia() {
        evaluate(EnhancementScript.pauseScript)
    }

    public func pauseAllPlayback() {
        guard !isTornDown else { return }
        pauseMedia()
        webView.pauseAllMediaPlayback(completionHandler: nil)
    }

    public func toggleMute() {
        evaluate(EnhancementScript.toggleMuteScript)
    }

    public func setMuted(_ muted: Bool) {
        evaluate(EnhancementScript.setMutedScript(muted: muted))
    }

    public func setAudioLevel(muted: Bool, volumePercent: Int) {
        evaluate(EnhancementScript.setAudioLevelScript(muted: muted, volumePercent: volumePercent))
    }

    public func seekToLiveEdge() {
        evaluate(EnhancementScript.seekToLiveEdgeScript)
    }

    public func syncPlayerSize() {
        guard !isInFullscreen, webView.fullscreenState == .notInFullscreen else { return }
        evaluate(EnhancementScript.syncPlayerSizeScript)
    }

    public func showAirPlayPicker() async -> AirPlayPickerResult {
        guard !isTornDown else { return .noVideo }
        do {
            let raw = try await webView.evaluateJavaScript(EnhancementScript.showAirPlayPickerScript) as? String
            return raw.flatMap(AirPlayPickerResult.init(rawValue:)) ?? .unavailable
        } catch {
            return .unavailable
        }
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
        let popupSize = NSSize(width: 520, height: 680)
        let popupWebView = WKWebView(frame: NSRect(origin: .zero, size: popupSize), configuration: configuration)
        popupWebView.customUserAgent = webView.customUserAgent
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

    private static func isOAuthPopupURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let authHosts = [
            "accounts.google.com", "accounts.youtube.com",
            "idmsa.apple.com", "appleid.apple.com",
            "sp.auth.adobe.com", "registerdisney.go.com",
            "passport.twitch.tv", "id.twitch.tv",
            "identity.sling.com", "identity.nba.com", "ids.mlb.com", "id.nfl.com",
            "auth.hulu.com", "auth.max.com"
        ]
        if authHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return true
        }
        return path.contains("oauth") || path.contains("/login") || path.contains("/signin") || path.contains("/sign-in") || path.contains("/auth")
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

    private func syncURLFromWebView() {
        guard !isSleeping && pendingLazyURL == nil else { return }
        if let webURL = webView.url, webURL.scheme?.lowercased() != "about", url != webURL {
            let oldVideoID = YouTubeURLRouter.extractVideoID(from: url)
            let newVideoID = YouTubeURLRouter.extractVideoID(from: webURL)
            if oldVideoID != newVideoID {
                chapters = []
            }
            url = webURL
            onURLDidChange?(id, webURL)
            if let host = webURL.host, !YouTubeURLRouter.isStandardYouTubeHost(host) {
                evaluate(EnhancementScript.notifyRouteChangedScript)
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
        }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadError = nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadError = nil
        syncTitleFromWebView()
        syncURLFromWebView()
        applyConfig(configProvider(), force: true)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        handleNavigationFailure(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        handleNavigationFailure(error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
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
        guard let targetURL = navigationAction.request.url else {
            return nil
        }

        // Preserve `window.opener` for OAuth/SSO/MVPD popups (Apple ID, Google OAuth, MyDisney, Adobe Pass).
        if navigationAction.targetFrame == nil && Self.isOAuthPopupURL(targetURL) {
            return presentOAuthPopup(with: configuration, title: "Sign In — GlassGrid You")
        }

        let prefs = routingPreferencesProvider()
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
            if let host = targetURL.host, YouTubeURLRouter.isGoogleAuthHost(host) {
                webView.load(URLRequest(url: targetURL))
            } else if routingMode == .companion,
                      let path = targetURL.path.lowercased() as String?,
                      (path.contains("oauth") || path.contains("login") || path.contains("signin") || path.contains("auth")) {
                webView.load(URLRequest(url: targetURL))
            } else {
                onOpenInNewTab?(targetURL, true)
            }
        case .redirectInApp(let rewritten):
            onOpenInNewTab?(rewritten, true)
        case .openExternal(let externalURL):
            NSWorkspace.shared.open(externalURL)
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
        guard message.name == EnhancementScript.messageHandlerName,
              let body = message.body as? [String: Any] else {
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
                let rawChapters = body["chapters"] as? [[String: Any]] ?? []
                let structuredEntries: [(title: String, startSeconds: Double)] = rawChapters.compactMap { dict in
                    guard let title = dict["title"] as? String else { return nil }
                    let secs = (dict["startSeconds"] as? NSNumber)?.doubleValue ?? -1
                    return (title, secs)
                }
                var parsed = VideoChapterParser.normalize(structuredEntries)
                if parsed.isEmpty, let description = body["description"] as? String, !description.isEmpty {
                    let maxDur = timeline.duration > 0 ? timeline.duration : nil
                    parsed = VideoChapterParser.parseFromDescription(description, maxDuration: maxDur)
                }
                if chapters != parsed {
                    chapters = parsed
                }
            }
            return
        }

        let newStatus = MediaStatus(
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
            isAirPlayActive: body["isAirPlayActive"] as? Bool ?? false
        )
        let wasPlaying = mediaStatus.isPlaying
        if mediaStatus != newStatus {
            mediaStatus = newStatus
        }
        if !wasPlaying && newStatus.isPlaying {
            onStartedPlaying?(id)
        }

        let currentTime = body["currentTime"] as? Double ?? 0
        let duration = body["duration"] as? Double ?? 0
        timeline.update(currentTime: currentTime, duration: duration)

        // Throttled Continue Watching & Most Watched Channel tracking (strictly www.youtube.com — skip tv.youtube.com & Companion sites).
        if newStatus.hasVideo,
           let parsedURL = URL(string: newStatus.urlString) ?? Optional(url),
           YouTubeURLRouter.isStandardYouTubeHost(parsedURL.host),
           let videoID = YouTubeURLRouter.extractVideoID(from: parsedURL) {
            let now = Date()
            let pausedTransition = wasPlaying && !newStatus.isPlaying
            let videoChanged = videoID != lastSavedWatchVideoID
            let elapsed = now.timeIntervalSince(lastSavedWatchProgressTime)
            let isNewChannelRecord = !newStatus.channel.isEmpty && videoID != lastRecordedChannelVideoID && currentTime >= 2

            if pausedTransition || (videoChanged && currentTime >= 3) || (newStatus.isPlaying && elapsed >= 15) || isNewChannelRecord {
                lastSavedWatchProgressTime = now
                lastSavedWatchVideoID = videoID
                if isNewChannelRecord {
                    lastRecordedChannelVideoID = videoID
                }
                let effectiveTitle = newStatus.title.isEmpty ? displayTitle : newStatus.title
                onWatchProgress?(videoID, effectiveTitle, newStatus.channel, newStatus.channelURLString, currentTime, duration, isNewChannelRecord)
            }
        }
    }
}
