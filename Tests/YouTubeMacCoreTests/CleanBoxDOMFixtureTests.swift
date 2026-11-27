import AppKit
import Foundation
import WebKit
import XCTest
@testable import YouTubeMacCore

@MainActor
final class CleanBoxDOMFixtureTests: XCTestCase {
    private final class OfflineFixtureHost: NSObject, WKNavigationDelegate {
        let window: NSWindow
        let webView: WKWebView
        private var didAllowInitialMainLoad = false
        private var loadContinuation: CheckedContinuation<Void, Error>?

        init(size: NSSize, config: DistractionFreeConfig) {
            _ = NSApplication.shared
            let wkConfig = WKWebViewConfiguration()
            wkConfig.userContentController.addUserScript(
                WKUserScript(
                    source: EnhancementScript.bootstrapScript(config: config),
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
            let wv = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: wkConfig)
            let win = NSWindow(
                contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isReleasedWhenClosed = false
            win.contentView = wv
            win.orderBack(nil)
            self.window = win
            self.webView = wv
            super.init()
            wv.navigationDelegate = self
        }

        func loadFixture(html: String, baseURL: URL) async throws {
            didAllowInitialMainLoad = false
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.loadContinuation = cont
                self.webView.loadHTMLString(html, baseURL: baseURL)
            }
            // Allow one layout frame after document-end script runs.
            try await Task.sleep(for: .milliseconds(80))
        }

        func resizeViewport(to size: NSSize) async throws {
            window.setContentSize(size)
            webView.frame = NSRect(origin: .zero, size: size)
            try await Task.sleep(for: .milliseconds(60))
        }

        func eval(_ script: String) async throws -> Any? {
            try await webView.evaluateJavaScript(script)
        }

        func teardown() {
            webView.navigationDelegate = nil
            webView.stopLoading()
            window.contentView = nil
            window.close()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            let isMain = navigationAction.targetFrame?.isMainFrame ?? false
            if isMain && !didAllowInitialMainLoad {
                didAllowInitialMainLoad = true
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadContinuation?.resume()
            loadContinuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            loadContinuation?.resume(throwing: error)
            loadContinuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            loadContinuation?.resume(throwing: error)
            loadContinuation = nil
        }
    }

    private func makeTileConfig(bypassed: Bool = false) -> DistractionFreeConfig {
        DistractionFreeConfig(
            multiviewTileActive: true,
            cleanBoxStreamingPlayers: true,
            cleanBoxBypassed: bypassed
        )
    }

    func testCrunchyrollVilosIframeFillsTileWithNoAttributeClobberOrWrapperShrinkage() async throws {
        let host = OfflineFixtureHost(size: NSSize(width: 640, height: 360), config: makeTileConfig())
        defer { host.teardown() }

        let html = """
        <!DOCTYPE html>
        <html>
        <head><style>
          body { margin: 0; background: #111; color: #fff; }
          header { height: 60px; background: #222; }
          .page-stage { max-width: 1280px; margin: 0 auto; padding-top: 20px; }
          .erc-watch-episode-player { max-width: 900px; max-height: 70vh; margin: 0 auto; }
          .aspect-box { position: relative; width: 100%; height: 0; padding-top: 56.25%; }
          .aspect-box iframe { position: absolute; top: 50%; left: 50%; width: 100%; height: 100%; transform: translate(-50%, -50%); border: 0; }
        </style></head>
        <body>
          <header id="cr-nav">Simulcast Nav</header>
          <main>
            <div class="page-stage">
              <div class="erc-watch-episode-player">
                <div class="aspect-box">
                  <iframe id="player0" src="https://static.crunchyroll.com/vilos-v2/web/vilos/player.html"></iframe>
                </div>
              </div>
              <section id="episode-meta"><h1>Gachiakuta E5</h1></section>
            </div>
          </main>
        </body>
        </html>
        """

        try await host.loadFixture(
            html: html,
            baseURL: URL(string: "https://www.crunchyroll.com/watch/GX9U34054/raiders")!
        )

        let raw = try await host.eval("""
        (() => {
            const iframe = document.getElementById('player0');
            const r = iframe.getBoundingClientRect();
            const topHit = document.elementFromPoint(320, 12);
            return {
                active: document.documentElement.dataset.ytmacCleanBox,
                attr: iframe.getAttribute('data-ytmac-cb'),
                x: Math.round(r.left),
                y: Math.round(r.top),
                w: Math.round(r.width),
                h: Math.round(r.height),
                topHitId: topHit ? topHit.id : ''
            };
        })()
        """) as? [String: Any]

        XCTAssertEqual(raw?["active"] as? String, "true")
        XCTAssertEqual(raw?["attr"] as? String, "player")
        XCTAssertEqual((raw?["x"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((raw?["y"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((raw?["w"] as? NSNumber)?.intValue, 640)
        XCTAssertEqual((raw?["h"] as? NSNumber)?.intValue, 360)
        XCTAssertEqual(raw?["topHitId"] as? String, "player0")
    }

    func testCrunchyrollKatamariInlineVideoFillsTileWithVisibleControlsAndSubtitleCanvas() async throws {
        let host = OfflineFixtureHost(size: NSSize(width: 640, height: 360), config: makeTileConfig())
        defer { host.teardown() }

        let html = """
        <!DOCTYPE html>
        <html>
        <head><style>
          body { margin: 0; background: #111; color: #fff; }
          nav { height: 60px; }
          .erc-watch-episode-player { max-width: 1200px; max-height: 60vh; margin: 0 auto; }
          [data-testid="vilos-player"] { display: flex; flex-direction: column; width: 420px; height: 220px; background: #000; position: relative; }
          .ratio-wrap { position: relative; flex: 1 1 auto; aspect-ratio: 16 / 9; max-height: 200px; overflow: hidden; }
          video { position: absolute; top: 50%; left: 50%; width: 100%; height: 100%; transform: translate(-50%, -50%); }
          #sub-canvas { position: absolute; inset: 0; pointer-events: none; width: 100%; height: 100%; }
          .controls-bar { height: 40px; flex-shrink: 0; display: flex; align-items: center; z-index: 2; }
        </style></head>
        <body>
          <nav>Simulcast</nav>
          <div class="erc-watch-episode-player">
            <div data-testid="vilos-player" id="katamari-root">
              <div class="ratio-wrap" id="ratio-wrap">
                <video id="cr-vid" aria-hidden="true" src="https://cdn.example.invalid/stream.mp4"></video>
              </div>
              <canvas id="sub-canvas"></canvas>
              <div class="controls-bar">
                <button id="play-btn" type="button" style="width:80px;height:32px;">Pause</button>
              </div>
            </div>
          </div>
          <script>
            const v = document.getElementById('cr-vid');
            Object.defineProperty(v, 'readyState', { value: 4, configurable: true });
            Object.defineProperty(v, 'duration', { value: 1440, configurable: true });
          </script>
        </body>
        </html>
        """

        try await host.loadFixture(
            html: html,
            baseURL: URL(string: "https://www.crunchyroll.com/watch/GX9U34054/raiders")!
        )

        let raw = try await host.eval("""
        (() => {
            window.__ytmacSyncCleanBox('test');
            const root = document.getElementById('katamari-root');
            const wrap = document.getElementById('ratio-wrap');
            const vid = document.getElementById('cr-vid');
            const btn = document.getElementById('play-btn');
            const sub = document.getElementById('sub-canvas');
            const rr = root.getBoundingClientRect();
            const vr = vid.getBoundingClientRect();
            const br = btn.getBoundingClientRect();
            const sr = sub.getBoundingClientRect();
            const btnHit = document.elementFromPoint(br.left + br.width / 2, br.top + br.height / 2);
            return {
                active: document.documentElement.dataset.ytmacCleanBox,
                rootAttr: root.getAttribute('data-ytmac-cb'),
                wrapAttr: wrap.getAttribute('data-ytmac-cb'),
                vidAttr: vid.getAttribute('data-ytmac-cb'),
                rw: Math.round(rr.width),
                rh: Math.round(rr.height),
                vx: Math.round(vr.left),
                vy: Math.round(vr.top),
                vw: Math.round(vr.width),
                vh: Math.round(vr.height),
                btnVisible: br.height > 20 && br.bottom <= 361 && br.top >= 0,
                btnHitId: btnHit ? btnHit.id : '',
                subVisible: sr.width > 100 && sr.height > 100
            };
        })()
        """) as? [String: Any]

        XCTAssertEqual(raw?["active"] as? String, "true")
        XCTAssertEqual(raw?["rootAttr"] as? String, "player")
        XCTAssertEqual(raw?["wrapAttr"] as? String, "chain")
        XCTAssertEqual(raw?["vidAttr"] as? String, "video")
        XCTAssertEqual((raw?["rw"] as? NSNumber)?.intValue, 640)
        XCTAssertEqual((raw?["rh"] as? NSNumber)?.intValue, 360)
        // Video with centered translate(-50%,-50%) must align cleanly at (0,0) and stay inside 640x360.
        XCTAssertEqual((raw?["vx"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((raw?["vy"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((raw?["vw"] as? NSNumber)?.intValue, 640)
        XCTAssertEqual(raw?["btnVisible"] as? Bool, true)
        XCTAssertEqual(raw?["btnHitId"] as? String, "play-btn")
        XCTAssertEqual(raw?["subVisible"] as? Bool, true)
    }

    func testTallPortraitTilePreservesSymmetricLetterboxedPlayerWhileRejectingAsymmetricDocWrapper() async throws {
        let host = OfflineFixtureHost(size: NSSize(width: 500, height: 700), config: makeTileConfig())
        defer { host.teardown() }

        let html = """
        <!DOCTYPE html>
        <html>
        <head><style>
          body { margin: 0; }
          .asymmetric-doc-wrap { width: 500px; height: 900px; padding-top: 20px; }
          .sym-player { width: 500px; height: 700px; display: flex; flex-direction: column; justify-content: center; background: #000; position: relative; }
          video { width: 500px; height: 281px; }
        </style></head>
        <body>
          <div class="erc-watch-episode-player asymmetric-doc-wrap" id="outer-doc">
            <div data-testid="vilos-player" class="sym-player" id="sym-player">
              <video id="v" src="https://cdn.example.invalid/stream.mp4"></video>
            </div>
            <h1>Show Title Below Player</h1>
          </div>
          <script>
            Object.defineProperty(document.getElementById('v'), 'readyState', { value: 4, configurable: true });
            Object.defineProperty(document.getElementById('v'), 'duration', { value: 1200, configurable: true });
          </script>
        </body>
        </html>
        """

        // Using asymmetric first order won't happen since crunchyroll selectors check sym-player before erc-watch-episode-player;
        // verify specifically that sym-player at 500x700 wrapping 500x281 centered video IS kept, while if a profile put .erc-watch-episode-player alone it stays safe.
        try await host.loadFixture(
            html: html,
            baseURL: URL(string: "https://www.crunchyroll.com/watch/GX9U34054/raiders")!
        )

        let raw = try await host.eval("""
        (() => {
            window.__ytmacSyncCleanBox('test');
            return {
                active: document.documentElement.dataset.ytmacCleanBox,
                symAttr: document.getElementById('sym-player').getAttribute('data-ytmac-cb'),
                docAttr: document.getElementById('outer-doc').getAttribute('data-ytmac-cb')
            };
        })()
        """) as? [String: Any]

        XCTAssertEqual(raw?["active"] as? String, "true")
        XCTAssertEqual(raw?["symAttr"] as? String, "player")
        XCTAssertEqual(raw?["docAttr"] as? String, "ancestor")
    }

    func testSecurityNegativeFixturesModalRecoveryAndBypassTeardown() async throws {
        let host = OfflineFixtureHost(size: NSSize(width: 640, height: 360), config: makeTileConfig())
        defer { host.teardown() }

        // 1. srcdoc iframe MUST be rejected even when __ytmacSubframeMediaActive === true
        let srcdocHTML = """
        <!DOCTYPE html><html><body style="margin:0">
          <div data-testid="vilos-player" style="width:640px;height:360px">
            <iframe id="evil" srcdoc="<video></video>" style="width:640px;height:360px"></iframe>
            <iframe id="ad" src="https://doubleclick.net/ad.html" style="width:640px;height:360px"></iframe>
          </div>
        </body></html>
        """
        try await host.loadFixture(
            html: srcdocHTML,
            baseURL: URL(string: "https://www.crunchyroll.com/watch/GX9U34054/raiders")!
        )
        let srcdocRes = try await host.eval("""
        (() => {
            window.__ytmacSubframeMediaActive = true;
            window.__ytmacSyncCleanBox('subframe');
            return {
                active: document.documentElement.dataset.ytmacCleanBox,
                taggedCount: document.querySelectorAll('[data-ytmac-cb]').length
            };
        })()
        """) as? [String: Any]
        XCTAssertNotEqual(srcdocRes?["active"] as? String, "true")
        XCTAssertEqual((srcdocRes?["taggedCount"] as? NSNumber)?.intValue, 0)

        // 2. Discover browse ambient trailer MUST be rejected
        let discoverHTML = """
        <!DOCTYPE html><html><body style="margin:0">
          <video id="trailer" muted loop style="width:640px;height:360px" src="https://cdn.example.invalid/trailer.mp4"></video>
          <script>
            Object.defineProperty(document.getElementById('trailer'), 'readyState', { value: 4 });
            Object.defineProperty(document.getElementById('trailer'), 'duration', { value: 30 });
          </script>
        </body></html>
        """
        try await host.loadFixture(
            html: discoverHTML,
            baseURL: URL(string: "https://www.crunchyroll.com/discover")!
        )
        let discoverActive = try await host.eval("document.documentElement.dataset.ytmacCleanBox") as? String
        XCTAssertNotEqual(discoverActive, "true")

        // 3. Non-modal #onetrust-banner-sdk does NOT block; aria-modal="true" DOES block & recovers on dismiss; bypass tears down cleanly.
        let modalHTML = """
        <!DOCTYPE html><html><body style="margin:0">
          <div id="onetrust-banner-sdk" role="dialog" style="position:fixed;bottom:0;left:0;width:640px;height:140px;background:#333;">Cookie Bar</div>
          <div id="gate" role="dialog" aria-modal="true" style="position:fixed;inset:0;width:640px;height:360px;background:#222;">Age Gate</div>
          <div class="aspect-box" style="width:640px;height:360px">
            <iframe id="player0" src="https://static.crunchyroll.com/vilos-v2/player.html" style="width:640px;height:360px"></iframe>
          </div>
        </body></html>
        """
        try await host.loadFixture(
            html: modalHTML,
            baseURL: URL(string: "https://www.crunchyroll.com/watch/GX9U34054/raiders")!
        )
        let blocked = try await host.eval("document.documentElement.dataset.ytmacCleanBox") as? String
        XCTAssertNotEqual(blocked, "true")

        // Hide aria-modal dialog (OneTrust banner remains) and trigger click recovery
        _ = try await host.eval("""
        (() => {
            document.getElementById('gate').style.display = 'none';
            document.body.click();
        })()
        """)
        try await Task.sleep(for: .milliseconds(220))
        let recovered = try await host.eval("document.documentElement.dataset.ytmacCleanBox") as? String
        XCTAssertEqual(recovered, "true")

        // Toggle bypass -> clean teardown
        _ = try await host.eval(EnhancementScript.applyConfigScript(makeTileConfig(bypassed: true), triggerResize: false))
        let afterBypass = try await host.eval("""
        (() => ({
            active: document.documentElement.dataset.ytmacCleanBox,
            tagged: document.querySelectorAll('[data-ytmac-cb]').length
        }))()
        """) as? [String: Any]
        XCTAssertEqual(afterBypass?["active"] as? String, "false")
        XCTAssertEqual((afterBypass?["tagged"] as? NSNumber)?.intValue, 0)
    }

    func testDisneyPlusAndHBOMaxAuthBailoutWatchFillAndSPAAuthExitRecovery() async throws {
        let host = OfflineFixtureHost(size: NSSize(width: 640, height: 360), config: makeTileConfig())
        defer { host.teardown() }

        // 1. Disney+ /identity/login/enter-password must bail out completely
        let disneyAuthHTML = """
        <!DOCTYPE html><html><body style="margin:0">
          <div data-testid="video-player" style="width:640px;height:360px">
            <video id="login-bg" muted loop src="https://cdn.example.invalid/bg.mp4" style="width:640px;height:360px"></video>
          </div>
          <script>
            Object.defineProperty(document.getElementById('login-bg'), 'readyState', { value: 4 });
            Object.defineProperty(document.getElementById('login-bg'), 'duration', { value: 300 });
          </script>
        </body></html>
        """
        try await host.loadFixture(
            html: disneyAuthHTML,
            baseURL: URL(string: "https://www.disneyplus.com/identity/login/enter-password")!
        )
        let disneyAuthInit = try await host.eval("typeof window.__ytmacInitialized") as? String
        XCTAssertEqual(disneyAuthInit, "undefined")

        // 2. Simulate SPA pushState exit from Disney+ auth -> Shadow DOM /en-us/play/123 + bootstrap injection (twice for idempotency)
        let bootstrapJS = EnhancementScript.bootstrapScript(config: makeTileConfig())
        _ = try await host.eval("""
        (() => {
            history.pushState({}, '', '/en-us/play/123');
            document.body.innerHTML = '';
            const header = document.createElement('header');
            header.textContent = 'Disney Nav';
            document.body.appendChild(header);
            const player = document.createElement('disney-web-player');
            player.id = 'd-player';
            player.style.cssText = 'width:400px;height:200px;display:block;';
            const sr = player.attachShadow({ mode: 'open' });
            const v = document.createElement('video');
            v.src = 'https://cdn.example.invalid/ep.mp4';
            Object.defineProperty(v, 'readyState', { value: 4, configurable: true });
            Object.defineProperty(v, 'duration', { value: 1800, configurable: true });
            sr.appendChild(v);
            document.body.appendChild(player);
        })()
        """)
        _ = try await host.eval(bootstrapJS)
        _ = try await host.eval(bootstrapJS)

        let spaRecovered = try await host.eval("""
        (() => {
            const p = document.getElementById('d-player');
            const r = p.getBoundingClientRect();
            return {
                init: Boolean(window.__ytmacInitialized),
                active: document.documentElement.dataset.ytmacCleanBox ?? '',
                hasAttr: p.hasAttribute('data-ytmac-cb'),
                styleEl: document.getElementById('ytmac-cleanbox-style') !== null,
                mainVideo: Boolean(window.__ytmacGetMainVideo && window.__ytmacGetMainVideo()),
                w: Math.round(r.width),
                h: Math.round(r.height)
            };
        })()
        """) as? [String: Any]
        XCTAssertEqual(spaRecovered?["init"] as? Bool, true)
        XCTAssertEqual(spaRecovered?["active"] as? String, "false")
        XCTAssertEqual(spaRecovered?["hasAttr"] as? Bool, false)
        XCTAssertEqual(spaRecovered?["styleEl"] as? Bool, false)
        XCTAssertEqual(spaRecovered?["mainVideo"] as? Bool, true)
        XCTAssertEqual((spaRecovered?["w"] as? NSNumber)?.intValue, 400)
        XCTAssertEqual((spaRecovered?["h"] as? NSNumber)?.intValue, 200)

        // 3. HBO Max auth page must bail out, and play.hbomax.com/video/watch/123 must fill 640x360
        try await host.loadFixture(
            html: disneyAuthHTML,
            baseURL: URL(string: "https://www.hbomax.com/auth/login")!
        )
        let hboAuthInit = try await host.eval("typeof window.__ytmacInitialized") as? String
        XCTAssertEqual(hboAuthInit, "undefined")

        let hboWatchHTML = """
        <!DOCTYPE html><html><body style="margin:0">
          <nav style="height:60px">HBO Max</nav>
          <div style="max-width:900px;max-height:220px">
            <div data-testid="player-ux-wrapper" id="hbo-root" style="width:480px;height:200px">
              <div style="aspect-ratio:16/9;max-height:180px">
                <video id="hbo-v" src="https://cdn.example.invalid/hbo.mp4"></video>
              </div>
            </div>
          </div>
          <script>
            Object.defineProperty(document.getElementById('hbo-v'), 'readyState', { value: 4, configurable: true });
            Object.defineProperty(document.getElementById('hbo-v'), 'duration', { value: 3600, configurable: true });
          </script>
        </body></html>
        """
        try await host.loadFixture(
            html: hboWatchHTML,
            baseURL: URL(string: "https://play.hbomax.com/video/watch/123")!
        )
        let hboRes = try await host.eval("""
        (() => {
            window.__ytmacSyncCleanBox('test');
            const r = document.getElementById('hbo-root').getBoundingClientRect();
            return {
                active: document.documentElement.dataset.ytmacCleanBox,
                attr: document.getElementById('hbo-root').getAttribute('data-ytmac-cb'),
                w: Math.round(r.width),
                h: Math.round(r.height)
            };
        })()
        """) as? [String: Any]
        XCTAssertEqual(hboRes?["active"] as? String, "true")
        XCTAssertEqual(hboRes?["attr"] as? String, "player")
        XCTAssertEqual((hboRes?["w"] as? NSNumber)?.intValue, 640)
        XCTAssertEqual((hboRes?["h"] as? NSNumber)?.intValue, 360)
    }
}
