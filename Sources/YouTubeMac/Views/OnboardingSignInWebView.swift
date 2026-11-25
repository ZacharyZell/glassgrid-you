import AppKit
import SwiftUI
import WebKit
import YouTubeMacCore

/// Stock WebKit sign-in view for the Onboarding Sign-In Hub.
/// Shares `WKWebsiteDataStore.default()`, uses the Safari Desktop User-Agent suffix,
/// injects ZERO `EnhancementScript` (keeping 2FA/CAPTCHA/SSO rock-solid), and hosts
/// OAuth child popups in safe `NSWindow`s (`isReleasedWhenClosed = false`) with full teardown.
struct OnboardingSignInWebView: NSViewRepresentable {
    let service: StreamingService
    let reloadToken: Int
    let freshSignInToken: Int
    let onURLChanged: (String, URL?) -> Void
    let onLoadingChanged: (String, Bool) -> Void
    let onError: (String, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onURLChanged: onURLChanged,
            onLoadingChanged: onLoadingChanged,
            onError: onError
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = BrowserTab.safariUserAgentSuffix
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.bind(webView: webView)
        context.coordinator.load(
            service: service,
            reloadToken: reloadToken,
            freshSignInToken: freshSignInToken,
            in: webView
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onURLChanged = onURLChanged
        context.coordinator.onLoadingChanged = onLoadingChanged
        context.coordinator.onError = onError
        context.coordinator.load(
            service: service,
            reloadToken: reloadToken,
            freshSignInToken: freshSignInToken,
            in: webView
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(webView: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private static let maxPopups = 3

        var onURLChanged: (String, URL?) -> Void
        var onLoadingChanged: (String, Bool) -> Void
        var onError: (String, String?) -> Void

        private var loadedServiceID: String?
        private var lastReloadToken: Int = -1
        private var lastFreshSignInToken: Int = -1
        private var lastMainFrameHTTPStatusCode: Int?
        private weak var primaryWebView: WKWebView?
        private var popupWindows: [ObjectIdentifier: NSWindow] = [:]
        private var popupWebViews: [ObjectIdentifier: WKWebView] = [:]
        private var popupObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]

        init(
            onURLChanged: @escaping (String, URL?) -> Void,
            onLoadingChanged: @escaping (String, Bool) -> Void,
            onError: @escaping (String, String?) -> Void
        ) {
            self.onURLChanged = onURLChanged
            self.onLoadingChanged = onLoadingChanged
            self.onError = onError
        }

        func bind(webView: WKWebView) {
            primaryWebView = webView
        }

        func load(service: StreamingService, reloadToken: Int, freshSignInToken: Int, in webView: WKWebView) {
            if loadedServiceID != service.id || lastFreshSignInToken != freshSignInToken {
                closeAllPopups()
                loadedServiceID = service.id
                lastReloadToken = reloadToken
                lastFreshSignInToken = freshSignInToken
                lastMainFrameHTTPStatusCode = nil
                onError(service.id, nil)
                onLoadingChanged(service.id, true)
                webView.load(URLRequest(url: service.signInURL))
            } else if lastReloadToken != reloadToken {
                lastReloadToken = reloadToken
                onLoadingChanged(service.id, true)
                if webView.url != nil && (lastMainFrameHTTPStatusCode ?? 200) < 400 {
                    webView.reload()
                } else {
                    lastMainFrameHTTPStatusCode = nil
                    onError(service.id, nil)
                    webView.load(URLRequest(url: service.signInURL))
                }
            }
        }

        func teardown(webView: WKWebView) {
            closeAllPopups()
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            primaryWebView = nil
        }

        private func closeAllPopups() {
            let windows = Array(popupWindows.values)
            let webViews = Array(popupWebViews.values)
            let observers = Array(popupObservers.values)
            popupWindows.removeAll()
            popupWebViews.removeAll()
            popupObservers.removeAll()

            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            for wv in webViews {
                wv.uiDelegate = nil
                wv.navigationDelegate = nil
                wv.stopLoading()
            }
            for win in windows {
                win.close()
            }
        }

        private func cleanupPopup(for popupWebView: WKWebView) {
            let key = ObjectIdentifier(popupWebView)
            if let obs = popupObservers.removeValue(forKey: key) {
                NotificationCenter.default.removeObserver(obs)
            }
            popupWebViews.removeValue(forKey: key)
            popupWebView.uiDelegate = nil
            popupWebView.navigationDelegate = nil
            popupWebView.stopLoading()
            if let win = popupWindows.removeValue(forKey: key) {
                win.close()
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            // Strict scheme allowlist checked BEFORE subframe exemptions for both primary and popup WebViews.
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme,
                  YouTubeURLRouter.isAllowedWebScheme(scheme) else {
                return .cancel
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse
        ) async -> WKNavigationResponsePolicy {
            if webView === primaryWebView, navigationResponse.isForMainFrame, let serviceID = loadedServiceID {
                if let http = navigationResponse.response as? HTTPURLResponse {
                    lastMainFrameHTTPStatusCode = http.statusCode
                    if http.statusCode >= 400 {
                        let host = http.url?.host ?? ""
                        let hostSuffix = host.isEmpty ? "" : " (\(host))"
                        onError(serviceID, "Sign-in page returned HTTP \(http.statusCode)\(hostSuffix).")
                    } else {
                        onError(serviceID, nil)
                    }
                }
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard webView === primaryWebView, let serviceID = loadedServiceID else { return }
            lastMainFrameHTTPStatusCode = nil
            onLoadingChanged(serviceID, true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard webView === primaryWebView, let serviceID = loadedServiceID else { return }
            onURLChanged(serviceID, webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === primaryWebView, let serviceID = loadedServiceID else { return }
            onLoadingChanged(serviceID, false)
            onURLChanged(serviceID, webView.url)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            guard webView === primaryWebView, let serviceID = loadedServiceID else { return }
            onLoadingChanged(serviceID, false)
            reportLoadErrorIfRelevant(error, serviceID: serviceID)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            guard webView === primaryWebView, let serviceID = loadedServiceID else { return }
            onLoadingChanged(serviceID, false)
            reportLoadErrorIfRelevant(error, serviceID: serviceID)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if webView !== primaryWebView {
                if popupWebViews[ObjectIdentifier(webView)] != nil {
                    cleanupPopup(for: webView)
                }
                return
            }
            guard let serviceID = loadedServiceID else { return }
            onLoadingChanged(serviceID, false)
            onError(serviceID, "Sign-in web content process restarted. Tap Retry Sign-In to reload.")
        }

        private func reportLoadErrorIfRelevant(_ error: any Error, serviceID: String) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
                return
            }
            onError(serviceID, error.localizedDescription)
        }

        // MARK: - WKUIDelegate (OAuth Child Popups Preserving window.opener)

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil, popupWindows.count < Self.maxPopups else {
                return nil
            }
            if let url = navigationAction.request.url, let scheme = url.scheme, !scheme.isEmpty {
                let lower = scheme.lowercased()
                let isBlank = url.absoluteString.lowercased() == "about:blank"
                guard lower == "http" || lower == "https" || isBlank else {
                    return nil
                }
            }

            let popupSize = NSSize(width: 520, height: 680)
            let childWebView = WKWebView(frame: NSRect(origin: .zero, size: popupSize), configuration: configuration)
            childWebView.customUserAgent = webView.customUserAgent
            childWebView.navigationDelegate = self
            childWebView.uiDelegate = self

            let popupWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: popupSize),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            // Gate 1 guardrail: retain window cleanly until close; never double-release.
            popupWindow.isReleasedWhenClosed = false
            popupWindow.title = "Sign In — GlassGrid You"
            popupWindow.contentView = childWebView
            popupWindow.center()

            let key = ObjectIdentifier(childWebView)
            popupWindows[key] = popupWindow
            popupWebViews[key] = childWebView
            popupObservers[key] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: popupWindow,
                queue: .main
            ) { [weak self, weak childWebView] _ in
                MainActor.assumeIsolated {
                    guard let self, let childWebView else { return }
                    let k = ObjectIdentifier(childWebView)
                    if let obs = self.popupObservers.removeValue(forKey: k) {
                        NotificationCenter.default.removeObserver(obs)
                    }
                    self.popupWebViews.removeValue(forKey: k)
                    self.popupWindows.removeValue(forKey: k)
                    childWebView.uiDelegate = nil
                    childWebView.navigationDelegate = nil
                    childWebView.stopLoading()
                }
            }

            popupWindow.makeKeyAndOrderFront(nil)
            return childWebView
        }

        func webViewDidClose(_ webView: WKWebView) {
            if popupWebViews[ObjectIdentifier(webView)] != nil {
                cleanupPopup(for: webView)
            }
        }

        func webView(
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

        func webView(
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
}
