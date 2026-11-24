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
    let onURLChanged: (URL?) -> Void
    let onLoadingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onURLChanged: onURLChanged, onLoadingChanged: onLoadingChanged)
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
        context.coordinator.load(service: service, reloadToken: reloadToken, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onURLChanged = onURLChanged
        context.coordinator.onLoadingChanged = onLoadingChanged
        context.coordinator.load(service: service, reloadToken: reloadToken, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(webView: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onURLChanged: (URL?) -> Void
        var onLoadingChanged: (Bool) -> Void

        private var loadedServiceID: String?
        private var lastReloadToken: Int = -1
        private weak var primaryWebView: WKWebView?
        private var popupWindows: [ObjectIdentifier: NSWindow] = [:]
        private var popupWebViews: [ObjectIdentifier: WKWebView] = [:]
        private var popupObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]

        init(
            onURLChanged: @escaping (URL?) -> Void,
            onLoadingChanged: @escaping (Bool) -> Void
        ) {
            self.onURLChanged = onURLChanged
            self.onLoadingChanged = onLoadingChanged
        }

        func bind(webView: WKWebView) {
            primaryWebView = webView
        }

        func load(service: StreamingService, reloadToken: Int, in webView: WKWebView) {
            if loadedServiceID != service.id {
                closeAllPopups()
                loadedServiceID = service.id
                lastReloadToken = reloadToken
                onLoadingChanged(true)
                webView.load(URLRequest(url: service.signInURL))
            } else if lastReloadToken != reloadToken {
                lastReloadToken = reloadToken
                onLoadingChanged(true)
                if webView.url != nil {
                    webView.reload()
                } else {
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

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard webView === primaryWebView else { return }
            onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard webView === primaryWebView else { return }
            onURLChanged(webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === primaryWebView else { return }
            onLoadingChanged(false)
            onURLChanged(webView.url)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            guard webView === primaryWebView else { return }
            onLoadingChanged(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            guard webView === primaryWebView else { return }
            onLoadingChanged(false)
        }

        // MARK: - WKUIDelegate (OAuth Child Popups Preserving window.opener)

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            let popupSize = NSSize(width: 520, height: 680)
            let childWebView = WKWebView(frame: NSRect(origin: .zero, size: popupSize), configuration: configuration)
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
    }
}
