import XCTest
@testable import YouTubeMacCore

final class YouTubeMacCoreTests: XCTestCase {
    func testHostClassification() {
        XCTAssertTrue(YouTubeURLRouter.isYouTubeHost("youtube.com"))
        XCTAssertTrue(YouTubeURLRouter.isYouTubeHost("www.youtube.com"))
        XCTAssertTrue(YouTubeURLRouter.isYouTubeHost("m.youtube.com"))
        XCTAssertTrue(YouTubeURLRouter.isYouTubeHost("youtu.be"))
        XCTAssertTrue(YouTubeURLRouter.isYouTubeHost("www.youtube-nocookie.com"))
        XCTAssertFalse(YouTubeURLRouter.isYouTubeHost("notyoutube.com"))
        XCTAssertFalse(YouTubeURLRouter.isYouTubeHost("example.com"))

        XCTAssertTrue(YouTubeURLRouter.isGoogleAuthHost("accounts.google.com"))
        XCTAssertTrue(YouTubeURLRouter.isGoogleAuthHost("accounts.google.co.uk"))
        XCTAssertTrue(YouTubeURLRouter.isGoogleAuthHost("accounts.youtube.com"))
        XCTAssertTrue(YouTubeURLRouter.isGoogleAuthHost("myaccount.google.com"))
        XCTAssertFalse(YouTubeURLRouter.isGoogleAuthHost("evilgoogle.com"))
    }

    func testUnwrapYouTubeRedirect() {
        let wrapped = URL(string: "https://www.youtube.com/redirect?event=video_description&q=https%3A%2F%2Fexample.com%2Fdocs%3Fa%3D1")!
        let unwrapped = YouTubeURLRouter.unwrapYouTubeRedirect(wrapped)
        XCTAssertEqual(unwrapped?.absoluteString, "https://example.com/docs?a=1")

        let nonRedirect = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertNil(YouTubeURLRouter.unwrapYouTubeRedirect(nonRedirect))
    }

    func testRewriteShortsURL() {
        let shorts = URL(string: "https://www.youtube.com/shorts/abc123XYZ?t=42&feature=share")!
        let rewritten = YouTubeURLRouter.rewriteShortsURL(shorts)
        XCTAssertEqual(rewritten?.absoluteString, "https://www.youtube.com/watch?v=abc123XYZ&t=42")

        let rootShorts = URL(string: "https://www.youtube.com/shorts")!
        XCTAssertNil(YouTubeURLRouter.rewriteShortsURL(rootShorts))
    }

    func testRouteNavigationExternalAndAuthFlows() {
        let externalURL = URL(string: "https://github.com/apple/swift")!
        let youtubePage = URL(string: "https://www.youtube.com/watch?v=123")!
        let authPage = URL(string: "https://accounts.google.com/v3/signin")!

        // External link clicked on YouTube opens in default browser.
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: externalURL,
                currentPageURL: youtubePage,
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: true
            ),
            .openExternal(externalURL)
        )

        // Non-user redirect (e.g., SAML/SSO callback) stays in-app.
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: externalURL,
                currentPageURL: authPage,
                isUserLinkClick: false,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: true
            ),
            .allowInApp
        )

        // Link clicked during active Google Auth stays in-app.
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: URL(string: "https://support.google.com/accounts")!,
                currentPageURL: authPage,
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: true
            ),
            .allowInApp
        )

        // Wrapped YouTube /redirect link unwraps straight to external browser.
        let wrapped = URL(string: "https://www.youtube.com/redirect?q=https%3A%2F%2Fswift.org")!
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: wrapped,
                currentPageURL: youtubePage,
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: true
            ),
            .openExternal(URL(string: "https://swift.org")!)
        )

        // Shorts link redirects to standard watch player when enabled.
        let shorts = URL(string: "https://www.youtube.com/shorts/xyz987")!
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: shorts,
                currentPageURL: youtubePage,
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: true
            ),
            .redirectInApp(URL(string: "https://www.youtube.com/watch?v=xyz987")!)
        )
    }

    func testOmniboxAndCustomSchemeResolution() {
        XCTAssertNil(YouTubeURLRouter.resolveOmniboxInput("   ", redirectShortsToWatch: true))

        XCTAssertEqual(
            YouTubeURLRouter.resolveOmniboxInput("youtu.be/dQw4w9WgXcQ", redirectShortsToWatch: true)?.absoluteString,
            "https://youtu.be/dQw4w9WgXcQ"
        )

        XCTAssertEqual(
            YouTubeURLRouter.resolveOmniboxInput("https://www.youtube.com/shorts/shortId1", redirectShortsToWatch: true)?.absoluteString,
            "https://www.youtube.com/watch?v=shortId1"
        )

        XCTAssertEqual(
            YouTubeURLRouter.resolveOmniboxInput("swift concurrency tutorial", redirectShortsToWatch: true)?.absoluteString,
            "https://www.youtube.com/results?search_query=swift%20concurrency%20tutorial"
        )

        XCTAssertEqual(
            YouTubeURLRouter.resolveCustomSchemeURL(URL(string: "youtubemac://watch?v=abc")!)?.absoluteString,
            "https://www.youtube.com/watch?v=abc"
        )
    }

    func testEnhancementScriptAndFocusModeFlags() {
        let base = DistractionFreeConfig(
            hideShorts: true,
            redirectShortsToWatch: true,
            cleanWebChrome: true,
            hideWebHeader: false,
            autoTheaterMode: true,
            hideEndScreens: true,
            hideWatchRecommendations: false,
            hideComments: false,
            hideHomeFeed: false,
            focusModeActive: true,
            miniPlayerActive: true
        )

        XCTAssertTrue(base.effectiveHideWatchRecommendations)
        XCTAssertTrue(base.effectiveHideComments)

        let script = EnhancementScript.bootstrapScript(config: base)
        XCTAssertTrue(script.contains("\"hideShorts\": true"))
        XCTAssertTrue(script.contains("\"hideWatchRecommendations\": true"))
        XCTAssertTrue(script.contains("\"hideComments\": true"))
        XCTAssertTrue(script.contains("\"miniPlayerActive\": true"))
        XCTAssertTrue(script.contains("ytmacBridge"))
        XCTAssertTrue(script.contains("ytd-reel-shelf-renderer"))
        XCTAssertFalse(script.contains(":has("))
        XCTAssertFalse(script.contains("MutationObserver"))
        // Ensure Mini-Player CSS only promotes #movie_player and never covers it with #player-container-outer
        XCTAssertTrue(script.contains("data-ytmac-on-watch=\"true\"] #movie_player"))
        XCTAssertFalse(script.contains("data-ytmac-mini-player=\"true\"] #player-container-outer"))
        XCTAssertTrue(script.contains("detectHDR"))
        XCTAssertTrue(script.contains("getPlaybackQualityLabel"))

        let nonResizeApply = EnhancementScript.applyConfigScript(base, triggerResize: false)
        XCTAssertFalse(nonResizeApply.contains("dispatchEvent"))
        XCTAssertFalse(nonResizeApply.contains("emitMediaState"))

        let resizeApply = EnhancementScript.applyConfigScript(base, triggerResize: true)
        XCTAssertTrue(resizeApply.contains("requestAnimationFrame(() => window.dispatchEvent(new Event('resize')))"))
        XCTAssertFalse(resizeApply.contains("emitMediaState"))
        XCTAssertTrue(EnhancementScript.notifyViewportResizeScript.contains("window.dispatchEvent(new Event('resize'))"))
        XCTAssertTrue(EnhancementScript.notifyViewportResizeScript.contains("p.setSize()"))
        XCTAssertTrue(EnhancementScript.notifyViewportResizeScript.contains("p.setInternalSize()"))
    }

    func testTitleFormatting() {
        XCTAssertEqual(
            YouTubeTitleFormatter.clean("(76) Costa Rica in 4K 60fps HDR - YouTube"),
            "Costa Rica in 4K 60fps HDR"
        )
        XCTAssertEqual(
            YouTubeTitleFormatter.clean("(3) Home - YouTube"),
            "Home"
        )
        XCTAssertEqual(
            YouTubeTitleFormatter.clean("Swift Concurrency (2026) - YouTube"),
            "Swift Concurrency (2026)"
        )
        XCTAssertEqual(
            YouTubeTitleFormatter.clean("YouTube"),
            "YouTube"
        )
    }

    func testMediaStatusAndFormatTime() {
        let a = MediaStatus(
            hasVideo: true,
            isPlaying: true,
            title: "Demo",
            channel: "Channel",
            urlString: "https://www.youtube.com/watch?v=1",
            isMuted: false,
            isPiP: false,
            isTheater: true
        )
        let b = a
        XCTAssertEqual(a, b)
        XCTAssertEqual(MediaStatus.empty.hasVideo, false)

        XCTAssertEqual(MediaState.formatTime(0), "0:00")
        XCTAssertEqual(MediaState.formatTime(-5), "0:00")
        XCTAssertEqual(MediaState.formatTime(.nan), "0:00")
        XCTAssertEqual(MediaState.formatTime(.infinity), "0:00")
        XCTAssertEqual(MediaState.formatTime(245), "4:05")
        XCTAssertEqual(MediaState.formatTime(3729), "1:02:09")
    }

    func testExtractVideoIDAndTimestampedURL() {
        XCTAssertEqual(
            YouTubeURLRouter.extractVideoID(from: URL(string: "https://www.youtube.com/watch?v=LXb3EKWsInQ&list=PL123")!),
            "LXb3EKWsInQ"
        )
        XCTAssertEqual(
            YouTubeURLRouter.extractVideoID(from: URL(string: "https://youtu.be/dQw4w9WgXcQ?t=10")!),
            "dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            YouTubeURLRouter.extractVideoID(from: URL(string: "https://www.youtube.com/shorts/abc123XYZ")!),
            "abc123XYZ"
        )
        XCTAssertEqual(
            YouTubeURLRouter.extractVideoID(from: URL(string: "https://www.youtube.com/live/liveID_1234")!),
            "liveID_1234"
        )
        XCTAssertNil(YouTubeURLRouter.extractVideoID(from: URL(string: "https://www.youtube.com/")!))
        XCTAssertNil(YouTubeURLRouter.extractVideoID(from: URL(string: "https://example.com/watch?v=LXb3EKWsInQ")!))

        let watch = URL(string: "https://www.youtube.com/watch?v=LXb3EKWsInQ")!
        XCTAssertEqual(
            YouTubeURLRouter.urlWithTimestamp(watch, seconds: 102.9).absoluteString,
            "https://www.youtube.com/watch?v=LXb3EKWsInQ&t=102s"
        )

        let existingTimestamp = URL(string: "https://www.youtube.com/watch?v=LXb3EKWsInQ&t=10s&list=WL")!
        XCTAssertEqual(
            YouTubeURLRouter.urlWithTimestamp(existingTimestamp, seconds: 245.2).absoluteString,
            "https://www.youtube.com/watch?v=LXb3EKWsInQ&list=WL&t=245s"
        )

        // Sub-second or non-finite timestamps leave URL unchanged.
        XCTAssertEqual(YouTubeURLRouter.urlWithTimestamp(watch, seconds: 0.4), watch)
        XCTAssertEqual(YouTubeURLRouter.urlWithTimestamp(watch, seconds: .nan), watch)

        // Non-video pages are never mutated.
        let home = URL(string: "https://www.youtube.com/")!
        XCTAssertEqual(YouTubeURLRouter.urlWithTimestamp(home, seconds: 50), home)
    }

    func testPlaybackRateFormattingAndBadgeVisibility() {
        let normal = MediaStatus(
            hasVideo: true,
            isPlaying: true,
            title: "Test",
            channel: "Chan",
            urlString: "https://www.youtube.com/watch?v=LXb3EKWsInQ",
            isMuted: false,
            isPiP: false,
            isTheater: true,
            isHDR: false,
            playbackRate: 1.0
        )
        XCTAssertNil(normal.formattedPlaybackRate)

        var faster = normal
        faster.playbackRate = 1.5
        XCTAssertEqual(faster.formattedPlaybackRate, "1.5×")

        faster.playbackRate = 1.25
        XCTAssertEqual(faster.formattedPlaybackRate, "1.25×")

        faster.playbackRate = 2.0
        XCTAssertEqual(faster.formattedPlaybackRate, "2×")

        faster.playbackRate = 1.1
        XCTAssertEqual(faster.formattedPlaybackRate, "1.1×")

        faster.hasVideo = false
        XCTAssertNil(faster.formattedPlaybackRate)
    }

    func testSponsorBlockHashPrefixAndParsing() {
        // SHA-256("dQw4w9WgXcQ") starts with "6f7c"
        let prefix = SponsorBlockClient.hashPrefix(for: "dQw4w9WgXcQ")
        XCTAssertEqual(prefix.count, 4)
        XCTAssertEqual(prefix, prefix.lowercased())

        let payload = """
        [
          {
            "videoID": "otherVideo1",
            "segments": [
              { "category": "sponsor", "segment": [5.0, 25.0] }
            ]
          },
          {
            "videoID": "LXb3EKWsInQ",
            "segments": [
              { "category": "sponsor", "segment": [120.5, 165.0] },
              { "category": "intro", "segment": [0.0, 12.0] },
              { "category": "sponsor", "segment": [30.0, 45.2] },
              { "category": "sponsor", "segment": [50.0, 50.2] }
            ]
          }
        ]
        """.data(using: .utf8)!

        let parsed = SponsorBlockClient.parseSegments(from: payload, videoID: "LXb3EKWsInQ")
        XCTAssertEqual(parsed, [
            SponsorSegment(start: 30.0, end: 45.2, category: "sponsor"),
            SponsorSegment(start: 120.5, end: 165.0, category: "sponsor")
        ])

        XCTAssertEqual(SponsorBlockClient.parseSegments(from: Data(), videoID: "LXb3EKWsInQ"), [])
    }

    func testNewEnhancementScriptFeaturesAndInvariants() {
        let cfg = DistractionFreeConfig(
            disableAmbientMode: true,
            autoDismissContinueWatching: true,
            preferOriginalAudio: true,
            preferredQuality: .uhd2160,
            defaultPlaybackRate: 1.25,
            sponsorBlockEnabled: true
        )

        let script = EnhancementScript.bootstrapScript(config: cfg)
        // Hard invariants
        XCTAssertFalse(script.contains(":has("))
        XCTAssertFalse(script.contains("MutationObserver"))

        // New config keys & QoL features
        XCTAssertTrue(script.contains("\"disableAmbientMode\": true"))
        XCTAssertTrue(script.contains("\"autoDismissContinueWatching\": true"))
        XCTAssertTrue(script.contains("\"preferOriginalAudio\": true"))
        XCTAssertTrue(script.contains("\"preferredQuality\": \"hd2160\""))
        XCTAssertTrue(script.contains("\"defaultPlaybackRate\": 1.25"))
        XCTAssertTrue(script.contains("\"sponsorBlockEnabled\": true"))
        XCTAssertTrue(script.contains("data-ytmac-disable-ambient=\"true\"] #cinematics"))
        XCTAssertTrue(script.contains("setPlaybackQualityRange"))
        XCTAssertTrue(script.contains("getAvailableAudioTracks"))
        XCTAssertTrue(script.contains("yt-confirm-dialog-renderer"))
        XCTAssertTrue(script.contains("__ytmacSetSponsorSegments"))
        XCTAssertTrue(script.contains("ratechange"))
        XCTAssertTrue(script.contains("getMainVideo"))

        let sponsorPush = EnhancementScript.setSponsorSegmentsScript(
            videoID: "LXb3EKWsInQ",
            segments: [SponsorSegment(start: 10.0, end: 35.5, category: "sponsor")]
        )
        XCTAssertTrue(sponsorPush.contains("__ytmacSetSponsorSegments(\"LXb3EKWsInQ\", [[10.0,35.5,\"sponsor\"]])"))

        let rateScript = EnhancementScript.setPlaybackRateScript(rate: 1.5)
        XCTAssertTrue(rateScript.contains("setPlaybackRate(1.5)"))
        XCTAssertTrue(EnhancementScript.toggleMuteScript.contains("p.mute()"))

        // Scrubber drag stability invariants (left-edge guide overlay, dragstart prevention, scrub stabilization, seeked sync)
        XCTAssertTrue(script.contains("html[data-ytmac-clean-chrome=\"true\"] tp-yt-app-drawer#guide,"))
        XCTAssertFalse(script.contains("tp-yt-app-drawer#guide[persistent]"))
        XCTAssertTrue(script.contains("pointer-events: none !important;"))
        XCTAssertTrue(script.contains("-webkit-user-drag: none !important;"))
        XCTAssertTrue(script.contains("addEventListener('dragstart'"))
        XCTAssertTrue(script.contains("beginScrubInteraction"))
        XCTAssertTrue(script.contains("endScrubInteraction"))
        XCTAssertTrue(script.contains("'seeked'"))
    }

    func testAppearanceThemeSyncAndInvariants() {
        XCTAssertEqual(AppAppearance.system.title, "Match System")
        XCTAssertEqual(AppAppearance.light.title, "Day (Light)")
        XCTAssertEqual(AppAppearance.dark.title, "Night (Dark)")

        for mode in AppAppearance.allCases {
            let cfg = DistractionFreeConfig(appearance: mode)
            let bootstrap = EnhancementScript.bootstrapScript(config: cfg)
            XCTAssertTrue(bootstrap.contains("\"appearance\": \"\(mode.rawValue)\""))
            XCTAssertTrue(bootstrap.contains("applyTheme"))
            XCTAssertTrue(bootstrap.contains("syncPrefThemeCookie"))
            XCTAssertTrue(bootstrap.contains("swapKevlarStylesheetAndCommit"))
            XCTAssertTrue(bootstrap.contains("prefers-color-scheme: dark"))
            XCTAssertFalse(bootstrap.contains(":has("))
            XCTAssertFalse(bootstrap.contains("MutationObserver"))

            let liveUpdate = EnhancementScript.applyConfigScript(cfg, triggerResize: false)
            XCTAssertTrue(liveUpdate.contains("\"appearance\": \"\(mode.rawValue)\""))
            XCTAssertFalse(liveUpdate.contains("dispatchEvent"))
            XCTAssertFalse(liveUpdate.contains("emitMediaState"))
        }
    }

    func testYouTubeThemeCookiePREFMerging() {
        // Fresh cookie (no existing PREF)
        XCTAssertEqual(
            YouTubeThemeCookie.mergedPREFValue(nil, appearance: .dark),
            "f6=400"
        )
        XCTAssertEqual(
            YouTubeThemeCookie.mergedPREFValue("", appearance: .light),
            "f6=80000"
        )

        // Preserves unrelated params (tz, f4, f7) and high f6 flags (0x40000000) when switching Dark -> Light -> Dark
        let existingDark = "f6=40000400&tz=America.Los_Angeles&f4=4000000&f7=100"
        let switchedLight = YouTubeThemeCookie.mergedPREFValue(existingDark, appearance: .light)
        XCTAssertEqual(switchedLight, "tz=America.Los_Angeles&f4=4000000&f7=100&f6=40080000")

        let switchedBackDark = YouTubeThemeCookie.mergedPREFValue(switchedLight, appearance: .dark)
        XCTAssertEqual(switchedBackDark, "tz=America.Los_Angeles&f4=4000000&f7=100&f6=40000400")

        // Match System follows resolved macOS system appearance
        XCTAssertEqual(
            YouTubeThemeCookie.mergedPREFValue("tz=UTC&f6=80000", appearance: .system, systemIsDark: true),
            "tz=UTC&f6=400"
        )
        XCTAssertEqual(
            YouTubeThemeCookie.mergedPREFValue("tz=UTC&f6=400", appearance: .system, systemIsDark: false),
            "tz=UTC&f6=80000"
        )
    }

    func testContinueWatchingAndMostWatchedChannelsStore() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var items: [ContinueWatchingItem] = []

        // Ignores < 3s watched or short < 15s clips
        items = ContinueWatchingStore.upsert(
            videoID: "LXb3EKWsInQ",
            title: "Costa Rica",
            channel: "Jacob + Katie Schwarz",
            currentTime: 2.0,
            duration: 314.0,
            now: t0,
            into: items
        )
        XCTAssertTrue(items.isEmpty)

        items = ContinueWatchingStore.upsert(
            videoID: "shortClip1",
            title: "Short",
            channel: "Chan",
            currentTime: 5.0,
            duration: 10.0,
            now: t0,
            into: items
        )
        XCTAssertTrue(items.isEmpty)

        // Inserts valid in-progress video with cleaned title & resume URL
        items = ContinueWatchingStore.upsert(
            videoID: "LXb3EKWsInQ",
            title: "(5) COSTA RICA IN 4K - YouTube",
            channel: "Jacob + Katie Schwarz",
            currentTime: 120.7,
            duration: 314.0,
            now: t0,
            into: items
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "COSTA RICA IN 4K")
        XCTAssertEqual(items[0].resumeURL?.absoluteString, "https://www.youtube.com/watch?v=LXb3EKWsInQ&t=120s")
        XCTAssertEqual(items[0].thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/LXb3EKWsInQ/mqdefault.jpg")
        XCTAssertEqual(items[0].remainingTimeText, "3:13 left")

        // Deduplicates & moves updated video to front
        items = ContinueWatchingStore.upsert(
            videoID: "aqz-KE-bpKQ",
            title: "Big Buck Bunny",
            channel: "Blender",
            currentTime: 90.0,
            duration: 635.0,
            now: t0.addingTimeInterval(10),
            into: items
        )
        items = ContinueWatchingStore.upsert(
            videoID: "LXb3EKWsInQ",
            title: "COSTA RICA IN 4K",
            channel: "Jacob + Katie Schwarz",
            currentTime: 200.0,
            duration: 314.0,
            now: t0.addingTimeInterval(20),
            into: items
        )
        XCTAssertEqual(items.map(\.videoID), ["LXb3EKWsInQ", "aqz-KE-bpKQ"])
        XCTAssertEqual(items[0].currentTime, 200.0)

        // Auto-removes completed video (>= 95% or < 10s remaining)
        items = ContinueWatchingStore.upsert(
            videoID: "LXb3EKWsInQ",
            title: "COSTA RICA IN 4K",
            channel: "Jacob + Katie Schwarz",
            currentTime: 308.0,
            duration: 314.0,
            now: t0.addingTimeInterval(30),
            into: items
        )
        XCTAssertEqual(items.map(\.videoID), ["aqz-KE-bpKQ"])

        // Most Watched Channels ranking
        var channels: [WatchedChannelStat] = []
        channels = ContinueWatchingStore.recordChannel(name: "Blender", urlString: "https://www.youtube.com/@BlenderOfficial", now: t0, into: channels)
        channels = ContinueWatchingStore.recordChannel(name: "3Blue1Brown", urlString: "https://www.youtube.com/@3blue1brown", now: t0.addingTimeInterval(5), into: channels)
        channels = ContinueWatchingStore.recordChannel(name: "3Blue1Brown", urlString: nil, now: t0.addingTimeInterval(15), into: channels)
        XCTAssertEqual(channels.map(\.name), ["3Blue1Brown", "Blender"])
        XCTAssertEqual(channels[0].watchCount, 2)
        XCTAssertEqual(channels[0].channelURLString, "https://www.youtube.com/@3blue1brown")

        // Curated Suggested Content catalog covers all topics cleanly
        XCTAssertGreaterThanOrEqual(SuggestedVideoItem.curatedCatalog.count, 12)
        for topic in SuggestedTopic.allCases where topic != .all {
            XCTAssertFalse(SuggestedVideoItem.curatedCatalog.filter { $0.topic == topic }.isEmpty)
        }
    }

    func testSafeShortsHidingAndEmptyHomeFeedDetectionInScript() {
        let script = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())
        XCTAssertFalse(script.contains(":has("))
        XCTAssertFalse(script.contains("MutationObserver"))
        XCTAssertTrue(script.contains("SHORTS_SHELF_SELECTOR"))
        XCTAssertTrue(script.contains("isPureShortsShelf"))
        XCTAssertTrue(script.contains("detectEmptyHomeFeed"))
        XCTAssertTrue(script.contains("isHomeFeedEmpty"))
        XCTAssertTrue(script.contains("channelURL"))
    }

    func testWindowOcclusionSplitScreenVsCovered() {
        let ownPID: Int32 = 1000
        let leftHalf = CGRect(x: 0, y: 54, width: 1032, height: 1221)
        let rightHalf = CGRect(x: 1032, y: 54, width: 1032, height: 1222)

        // System overlays (MenuBarAgent, Dock), floating Mini-Player (own PID, layer 3),
        // invisible helpers, and side-by-side Split Screen app on the right half must NOT pop out.
        let splitScreenAbove: [OccludingWindowDescriptor] = [
            OccludingWindowDescriptor(ownerPID: 693, layer: 26, alpha: 1.0, bounds: CGRect(x: 0, y: 0, width: 2064, height: 1347)),
            OccludingWindowDescriptor(ownerPID: 753, layer: 20, alpha: 1.0, bounds: CGRect(x: 0, y: 0, width: 2064, height: 1347)),
            OccludingWindowDescriptor(ownerPID: ownPID, layer: 3, alpha: 1.0, bounds: CGRect(x: 61, y: 940, width: 468, height: 263)),
            OccludingWindowDescriptor(ownerPID: 2001, layer: 0, alpha: 0.0, bounds: leftHalf),
            OccludingWindowDescriptor(ownerPID: 2002, layer: 0, alpha: 1.0, bounds: CGRect(x: 10, y: 60, width: 20, height: 20)),
            OccludingWindowDescriptor(ownerPID: 90288, layer: 0, alpha: 1.0, bounds: rightHalf)
        ]

        XCTAssertFalse(
            WindowOcclusionCalculator.shouldAutoPopOutWhenInactive(
                isWindowVisible: true,
                isOnActiveSpace: true,
                isOcclusionStateVisible: true,
                targetBounds: leftHalf,
                aboveWindows: splitScreenAbove,
                ownPID: ownPID
            )
        )

        // Another app covering the left half (behind-app case) MUST pop out.
        let coveredAbove = splitScreenAbove + [
            OccludingWindowDescriptor(ownerPID: 46871, layer: 0, alpha: 1.0, bounds: CGRect(x: 0, y: 54, width: 1032, height: 1214))
        ]
        XCTAssertTrue(
            WindowOcclusionCalculator.shouldAutoPopOutWhenInactive(
                isWindowVisible: true,
                isOnActiveSpace: true,
                isOcclusionStateVisible: true,
                targetBounds: leftHalf,
                aboveWindows: coveredAbove,
                ownPID: ownPID
            )
        )

        // Switching to another Space or full-screen app MUST pop out even with empty aboveWindows.
        XCTAssertTrue(
            WindowOcclusionCalculator.shouldAutoPopOutWhenInactive(
                isWindowVisible: true,
                isOnActiveSpace: false,
                isOcclusionStateVisible: false,
                targetBounds: leftHalf,
                aboveWindows: [],
                ownPID: ownPID
            )
        )

        // Hidden/closed window must NOT auto-pop-out.
        XCTAssertFalse(
            WindowOcclusionCalculator.shouldAutoPopOutWhenInactive(
                isWindowVisible: false,
                isOnActiveSpace: false,
                isOcclusionStateVisible: false,
                targetBounds: leftHalf,
                aboveWindows: coveredAbove,
                ownPID: ownPID
            )
        )
    }

    func testWindowOcclusionUnionAreaAndHysteresis() {
        let ownPID: Int32 = 1000
        let target = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        // Two overlapping windows that each cover 25% of target in the exact same region have union = 25% (not 50%).
        let duplicatedRects = [
            CGRect(x: 0, y: 0, width: 500, height: 500),
            CGRect(x: 0, y: 0, width: 500, height: 500)
        ]
        XCTAssertEqual(WindowOcclusionCalculator.coveredFraction(of: target, by: duplicatedRects), 0.25, accuracy: 0.0001)

        // Two partially overlapping windows: [0..500, 0..500] (25%) U [250..750, 0..500] (25%) = [0..750, 0..500] (37.5%).
        let partialOverlapRects = [
            CGRect(x: 0, y: 0, width: 500, height: 500),
            CGRect(x: 250, y: 0, width: 500, height: 500)
        ]
        XCTAssertEqual(WindowOcclusionCalculator.coveredFraction(of: target, by: partialOverlapRects), 0.375, accuracy: 0.0001)

        // Hysteresis band (25% covered): neither triggers pop-out (>= 35%) nor auto-dock (<= 15%).
        let hysteresisAbove = [
            OccludingWindowDescriptor(ownerPID: 2000, layer: 0, alpha: 1.0, bounds: CGRect(x: 0, y: 0, width: 500, height: 500))
        ]
        XCTAssertFalse(
            WindowOcclusionCalculator.shouldAutoPopOutWhenInactive(
                isWindowVisible: true,
                isOnActiveSpace: true,
                isOcclusionStateVisible: true,
                targetBounds: target,
                aboveWindows: hysteresisAbove,
                ownPID: ownPID
            )
        )
        XCTAssertFalse(
            WindowOcclusionCalculator.shouldAutoDockWhenUncovered(
                isWindowVisible: true,
                isOnActiveSpace: true,
                isOcclusionStateVisible: true,
                targetBounds: target,
                aboveWindows: hysteresisAbove,
                ownPID: ownPID
            )
        )

        // Uncovered (<= 15%) on active Space docks back cleanly.
        let minorEdgeOverlap = [
            OccludingWindowDescriptor(ownerPID: 2000, layer: 0, alpha: 1.0, bounds: CGRect(x: 900, y: 0, width: 500, height: 1000))
        ]
        XCTAssertTrue(
            WindowOcclusionCalculator.shouldAutoDockWhenUncovered(
                isWindowVisible: true,
                isOnActiveSpace: true,
                isOcclusionStateVisible: true,
                targetBounds: target,
                aboveWindows: minorEdgeOverlap,
                ownPID: ownPID
            )
        )
    }

    // MARK: - Native Multiview & YouTube TV Tests

    func testMultiviewGridLayoutProducesIntegralNonOverlappingFrames() {
        let oddContainer = CGSize(width: 1281, height: 779)
        for mode in MultiviewLayoutMode.allCases {
            for count in 2...4 {
                let frames = MultiviewGridLayout.frames(forCount: count, in: oddContainer, mode: mode)
                XCTAssertEqual(frames.count, count)
                for (i, rect) in frames.enumerated() {
                    XCTAssertEqual(rect.origin.x, rect.origin.x.rounded(), "Non-integral x for count \(count), mode \(mode)")
                    XCTAssertEqual(rect.origin.y, rect.origin.y.rounded(), "Non-integral y for count \(count), mode \(mode)")
                    XCTAssertEqual(rect.width, rect.width.rounded(), "Non-integral width for count \(count), mode \(mode)")
                    XCTAssertEqual(rect.height, rect.height.rounded(), "Non-integral height for count \(count), mode \(mode)")
                    XCTAssertGreaterThan(rect.width, 0)
                    XCTAssertGreaterThan(rect.height, 0)
                    for j in (i + 1)..<frames.count {
                        XCTAssertFalse(rect.intersects(frames[j]), "Frames \(i) and \(j) overlapped in mode \(mode)")
                    }
                }
            }
        }
    }

    func testMultiviewTwoUpStacksVerticallyInNarrowSplitScreen() {
        let narrow = CGSize(width: 640, height: 820)
        let frames = MultiviewGridLayout.frames(forCount: 2, in: narrow, mode: .auto)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].minX, frames[1].minX)
        XCTAssertLessThan(frames[0].maxY, frames[1].minY)

        let wide = CGSize(width: 1280, height: 720)
        let wideFrames = MultiviewGridLayout.frames(forCount: 2, in: wide, mode: .auto)
        XCTAssertEqual(wideFrames.count, 2)
        XCTAssertEqual(wideFrames[0].minY, wideFrames[1].minY)
        XCTAssertLessThan(wideFrames[0].maxX, wideFrames[1].minX)
    }

    func testMultiviewPrimarySlotEligibility() {
        XCTAssertTrue(MultiviewGridLayout.isPrimarySlot(index: 0, count: 2, mode: .auto))
        XCTAssertTrue(MultiviewGridLayout.isPrimarySlot(index: 1, count: 2, mode: .auto))
        XCTAssertTrue(MultiviewGridLayout.isPrimarySlot(index: 0, count: 3, mode: .auto))
        XCTAssertFalse(MultiviewGridLayout.isPrimarySlot(index: 1, count: 3, mode: .auto))
        XCTAssertFalse(MultiviewGridLayout.isPrimarySlot(index: 0, count: 4, mode: .auto))
        XCTAssertTrue(MultiviewGridLayout.isPrimarySlot(index: 0, count: 4, mode: .spotlight))
        XCTAssertFalse(MultiviewGridLayout.isPrimarySlot(index: 1, count: 4, mode: .spotlight))
        XCTAssertFalse(MultiviewGridLayout.isPrimarySlot(index: 0, count: 3, mode: .stacked))
    }

    func testMultiviewReducerLifecycleAndAudioCycling() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        let e = UUID()

        var state = MultiviewReducer.enter(primaryTabID: a, candidateTabIDs: [a, b, c, d, e])
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.tabIDs, [a, b, c, d])
        XCTAssertEqual(state.audioTabID, a)

        // Adding beyond 4 is a no-op
        let capped = MultiviewReducer.addTile(e, to: state)
        XCTAssertEqual(capped.tabIDs.count, 4)

        // Cycle audio forward & backward with wraparound
        state = MultiviewReducer.cycleAudioFocus(by: 1, in: state)
        XCTAssertEqual(state.audioTabID, b)
        state = MultiviewReducer.cycleAudioFocus(by: -2, in: state)
        XCTAssertEqual(state.audioTabID, d)

        // Promote tile d to primary slot 0
        state = MultiviewReducer.promoteToPrimary(d, in: state, transferAudio: true)
        XCTAssertEqual(state.tabIDs, [d, a, b, c])
        XCTAssertEqual(state.audioTabID, d)

        // Removing active audio tile transfers audio cleanly
        let afterRemoveD = MultiviewReducer.removeTile(d, from: state)
        XCTAssertNil(afterRemoveD.remainingSingleTabID)
        XCTAssertEqual(afterRemoveD.state.tabIDs, [a, b, c])
        XCTAssertEqual(afterRemoveD.state.audioTabID, a)

        // Removing down to 1 tile auto-exits and returns surviving tab
        let afterRemoveB = MultiviewReducer.removeTile(b, from: afterRemoveD.state)
        XCTAssertEqual(afterRemoveB.state.tabIDs, [a, c])
        let afterRemoveA = MultiviewReducer.removeTile(a, from: afterRemoveB.state)
        XCTAssertFalse(afterRemoveA.state.isActive)
        XCTAssertEqual(afterRemoveA.remainingSingleTabID, c)
    }

    func testYouTubeTVAndLiveWatchURLRouting() throws {
        let yttvWatch = try XCTUnwrap(URL(string: "https://tv.youtube.com/watch/dQw4w9WgXcQ"))
        let yttvGuide = try XCTUnwrap(URL(string: "https://tv.youtube.com/live"))
        let yttvHome = try XCTUnwrap(URL(string: "https://tv.youtube.com/"))
        let ytLive = try XCTUnwrap(URL(string: "https://www.youtube.com/live/dQw4w9WgXcQ"))
        let ytWatch = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let ytHome = try XCTUnwrap(URL(string: "https://www.youtube.com/"))

        XCTAssertTrue(YouTubeURLRouter.isYouTubeTVHost(yttvWatch.host))
        XCTAssertFalse(YouTubeURLRouter.isYouTubeTVHost(ytWatch.host))
        XCTAssertFalse(YouTubeURLRouter.isYouTubeTVHost(nil))

        XCTAssertTrue(YouTubeURLRouter.isWatchURL(yttvWatch))
        XCTAssertFalse(YouTubeURLRouter.isWatchURL(yttvGuide))
        XCTAssertFalse(YouTubeURLRouter.isWatchURL(yttvHome))
        XCTAssertTrue(YouTubeURLRouter.isWatchURL(ytLive))
        XCTAssertTrue(YouTubeURLRouter.isWatchURL(ytWatch))
        XCTAssertFalse(YouTubeURLRouter.isWatchURL(ytHome))

        XCTAssertEqual(YouTubeURLRouter.extractVideoID(from: yttvWatch), "dQw4w9WgXcQ")
        XCTAssertNil(YouTubeURLRouter.extractVideoID(from: yttvGuide))
        XCTAssertEqual(YouTubeURLRouter.extractVideoID(from: ytLive), "dQw4w9WgXcQ")

        XCTAssertNil(SidebarDestination.matching(url: yttvHome))
        XCTAssertNil(SidebarDestination.matching(url: yttvGuide))
        XCTAssertEqual(SidebarDestination.matching(url: ytHome), .home)

        XCTAssertEqual(YouTubeTitleFormatter.clean("NFL RedZone - YouTube TV"), "NFL RedZone")
    }

    func testPreferredVideoQualityClampingForMultiview() {
        // Applies ceiling even when user preference is .auto
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .auto, isPrimaryOrTwoUp: true),
            .fhd1080
        )
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .auto, isPrimaryOrTwoUp: false),
            .hd720
        )
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .uhd2160, isPrimaryOrTwoUp: true),
            .fhd1080
        )
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .uhd2160, isPrimaryOrTwoUp: false),
            .hd720
        )
        // Never upgrades above user's lower preference
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .hd720, isPrimaryOrTwoUp: true),
            .hd720
        )
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .qhd1440, isPrimaryOrTwoUp: true),
            .fhd1080
        )
    }

    func testEnhancementScriptMultiviewAndYouTubeTVInvariants() {
        let script = EnhancementScript.bootstrapScript(config: DistractionFreeConfig(multiviewTileActive: true))
        XCTAssertFalse(script.contains(":has("))
        XCTAssertFalse(script.contains("MutationObserver"))
        // Fixed movie_player promotion MUST be strictly scoped to www.youtube.com, never tv.youtube.com
        XCTAssertTrue(script.contains(#"html[data-ytmac-host="youtube"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"]"#))
        XCTAssertTrue(script.contains(#"html[data-ytmac-host="yttv"][data-ytmac-tile-player="true"][data-ytmac-on-watch="true"]"#))
        // ABR unlock when returning to .auto
        XCTAssertTrue(script.contains("setPlaybackQualityRange('tiny', 'highres')"))
        // Dual-layer mute suppression helper & route sync
        XCTAssertTrue(script.contains("__ytmacMarkProgrammaticMute"))
        XCTAssertTrue(script.contains("__ytmacHandleRouteChange"))

        let muteJS = EnhancementScript.setMutedScript(muted: true)
        XCTAssertTrue(muteJS.contains("__ytmacMarkProgrammaticMute"))
        XCTAssertTrue(muteJS.contains("v.muted = true"))

        let unmuteJS = EnhancementScript.setMutedScript(muted: false)
        XCTAssertTrue(unmuteJS.contains("v.muted = false"))
        XCTAssertTrue(unmuteJS.contains("v.volume = 1.0"))

        let updateJS = EnhancementScript.applyConfigScript(DistractionFreeConfig(multiviewTileActive: true))
        XCTAssertTrue(updateJS.contains(#""multiviewTileActive": true"#))

        XCTAssertTrue(EnhancementScript.notifyRouteChangedScript.contains("__ytmacHandleRouteChange"))
    }

    // MARK: - Wave 1 Reliability & Native macOS Integration Tests

    func testSessionRestorationFilterStripsAuthAndCapsTabs() {
        let rawTabs: [SavedTabSnapshot] = [
            SavedTabSnapshot(urlString: "https://accounts.google.com/ServiceLogin?service=youtube", title: "Sign in"),
            SavedTabSnapshot(urlString: "about:blank", title: "Blank"),
            SavedTabSnapshot(urlString: "https://www.youtube.com/watch?v=abc12345678", title: "(3) Cool Video - YouTube"),
            SavedTabSnapshot(urlString: "https://tv.youtube.com/live", title: "Live - YouTube TV"),
            SavedTabSnapshot(urlString: "https://example.com/news", title: "External")
        ]

        // Originally selected index 3 (tv.youtube.com/live) should remap to index 1 after stripping indices 0 and 1.
        let sanitized = SessionRestorationFilter.sanitize(tabs: rawTabs, selectedIndex: 3)
        XCTAssertNotNil(sanitized)
        XCTAssertEqual(sanitized?.tabs.count, 2)
        XCTAssertEqual(sanitized?.tabs[0].urlString, "https://www.youtube.com/watch?v=abc12345678")
        XCTAssertEqual(sanitized?.tabs[0].title, "Cool Video")
        XCTAssertEqual(sanitized?.tabs[1].urlString, "https://tv.youtube.com/live")
        XCTAssertEqual(sanitized?.tabs[1].title, "Live")
        XCTAssertEqual(sanitized?.selectedIndex, 1)

        // Cap at 20 tabs
        let manyTabs = (0..<25).map { idx in
            SavedTabSnapshot(urlString: "https://www.youtube.com/watch?v=vid\(idx)", title: "Video \(idx)")
        }
        let capped = SessionRestorationFilter.sanitize(tabs: manyTabs, selectedIndex: 22)
        XCTAssertEqual(capped?.tabs.count, SessionRestorationFilter.maxRestoredTabs)
        XCTAssertEqual(capped?.selectedIndex, SessionRestorationFilter.maxRestoredTabs - 1)

        // All-auth session returns nil
        let authOnly = SessionRestorationFilter.sanitize(
            tabs: [SavedTabSnapshot(urlString: "https://accounts.google.com/", title: "Google")],
            selectedIndex: 0
        )
        XCTAssertNil(authOnly)
    }

    func testAudioOutputDisconnectDetectorTransitions() {
        let airpods = AudioRouteSnapshot(deviceID: 101, transportType: AudioRouteSnapshot.transportBluetooth, dataSource: 0)
        let usbDac = AudioRouteSnapshot(deviceID: 102, transportType: AudioRouteSnapshot.transportUSB, dataSource: 0)
        let builtInSpeakers = AudioRouteSnapshot(
            deviceID: 42,
            transportType: AudioRouteSnapshot.transportBuiltIn,
            dataSource: AudioRouteSnapshot.dataSourceInternalSpeakers
        )
        let builtInJackHeadphones = AudioRouteSnapshot(
            deviceID: 42,
            transportType: AudioRouteSnapshot.transportBuiltIn,
            dataSource: AudioRouteSnapshot.dataSourceHeadphones
        )
        let desktopBuiltInNoSource = AudioRouteSnapshot(
            deviceID: 42,
            transportType: AudioRouteSnapshot.transportBuiltIn,
            dataSource: 0
        )

        // Initial snapshot must never trigger pause
        XCTAssertFalse(AudioOutputDisconnectDetector.shouldAutoPause(from: nil, to: builtInSpeakers))
        // Duplicate/no-op notifications must never trigger pause
        XCTAssertFalse(AudioOutputDisconnectDetector.shouldAutoPause(from: builtInSpeakers, to: builtInSpeakers))
        XCTAssertFalse(AudioOutputDisconnectDetector.shouldAutoPause(from: airpods, to: airpods))

        // AirPods / USB disconnect -> Built-In Speakers MUST pause
        XCTAssertTrue(AudioOutputDisconnectDetector.shouldAutoPause(from: airpods, to: builtInSpeakers))
        XCTAssertTrue(AudioOutputDisconnectDetector.shouldAutoPause(from: usbDac, to: builtInSpeakers))
        XCTAssertTrue(AudioOutputDisconnectDetector.shouldAutoPause(from: airpods, to: desktopBuiltInNoSource))

        // Apple Silicon 3.5mm jack unplug ('hdpn' -> 'ispk' on same deviceID) MUST pause
        XCTAssertTrue(AudioOutputDisconnectDetector.shouldAutoPause(from: builtInJackHeadphones, to: builtInSpeakers))
        // Desktop Mac with dataSource == 0 must NOT falsely trigger
        XCTAssertFalse(AudioOutputDisconnectDetector.shouldAutoPause(from: builtInJackHeadphones, to: desktopBuiltInNoSource))

        // Connecting headphones or switching between external devices must NOT pause
        XCTAssertFalse(AudioOutputDisconnectDetector.shouldAutoPause(from: builtInSpeakers, to: airpods))
        XCTAssertFalse(AudioOutputDisconnectDetector.shouldAutoPause(from: builtInSpeakers, to: builtInJackHeadphones))
        XCTAssertFalse(AudioOutputDisconnectDetector.shouldAutoPause(from: usbDac, to: airpods))
    }

    func testSleepTimerFormattingTabLoadErrorAndVideoEndedInvariant() {
        XCTAssertEqual(SleepTimerOption.formatRemaining(0), "0:00")
        XCTAssertEqual(SleepTimerOption.formatRemaining(65), "1:05")
        XCTAssertEqual(SleepTimerOption.formatRemaining(3661), "1:01:01")
        XCTAssertEqual(SleepTimerOption.minutes15.durationSeconds, 900)
        XCTAssertNil(SleepTimerOption.endOfVideo.durationSeconds)

        let offlineNSError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let offline = TabLoadError.from(error: offlineNSError, failingURL: URL(string: "https://www.youtube.com/"))
        XCTAssertTrue(offline.isOffline)
        XCTAssertFalse(offline.isProcessCrash)

        let crash = TabLoadError.processTerminated(url: URL(string: "https://www.youtube.com/watch?v=abc"))
        XCTAssertTrue(crash.isProcessCrash)
        XCTAssertFalse(crash.isOffline)

        let script = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())
        XCTAssertTrue(script.contains("event: 'videoEnded'"))
        XCTAssertFalse(script.contains(":has("))
        XCTAssertFalse(script.contains("MutationObserver"))
        XCTAssertTrue(EnhancementScript.clearSelectionScript.contains("removeAllRanges"))
    }

    // MARK: - Wave 2 Command Palette, Presets & Menu Bar Scrubber Tests

    func testCommandPaletteEnginePrivacyAndRanking() throws {
        // Privacy guardrail: never send URLs or private domains to suggestqueries.google.com
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: ""))
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: "a"))
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: "https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: "https://tv.youtube.com/live"))
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: "https://private.corp.org/token=123"))
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: "www.mybank.com"))
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: "internal.net/docs"))
        XCTAssertTrue(CommandPaletteEngine.shouldFetchSuggestions(for: "4k hdr"))
        XCTAssertTrue(CommandPaletteEngine.shouldFetchSuggestions(for: "nfl redzone highlights"))

        // Fuzzy score ordering: exact > prefix > word boundary > substring > subsequence
        let exact = try XCTUnwrap(CommandPaletteEngine.fuzzyScore(query: "multiview", in: "Multiview"))
        let prefix = try XCTUnwrap(CommandPaletteEngine.fuzzyScore(query: "multi", in: "Multiview Mode"))
        let wordBoundary = try XCTUnwrap(CommandPaletteEngine.fuzzyScore(query: "multi", in: "Enter Multiview"))
        let substring = try XCTUnwrap(CommandPaletteEngine.fuzzyScore(query: "view", in: "Multiview"))
        let subseq = try XCTUnwrap(CommandPaletteEngine.fuzzyScore(query: "mv", in: "Multiview"))
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, wordBoundary)
        XCTAssertGreaterThan(wordBoundary, substring)
        XCTAssertGreaterThan(substring, subseq)

        let tabA = CommandPaletteTabSnapshot(
            id: UUID(),
            title: "Big Buck Bunny 4K",
            subtitle: "Blender",
            multiviewSlot: 1,
            isActiveAudio: true,
            isPlaying: true,
            isSelected: true
        )
        let preset = MultiviewPreset(
            name: "NFL Sunday Quad",
            urlStrings: ["https://www.youtube.com/watch?v=1", "https://tv.youtube.com/live"],
            layoutMode: .auto
        )
        let cont = ContinueWatchingItem(videoID: "abc12345678", title: "Space Walk 4K", channel: "NASA", currentTime: 120, duration: 600)
        let action = CommandPaletteActionDescriptor(
            action: .toggleMultiview,
            title: "Enter Multiview",
            keywords: "quad grid",
            systemImage: "square.grid.2x2",
            shortcutHint: "⌘⇧G",
            isFeaturedWhenEmpty: true
        )

        // Empty query shows open tabs, presets, continue watching, and featured actions
        let emptyItems = CommandPaletteEngine.rank(
            query: "",
            openTabs: [tabA],
            presets: [preset],
            continueWatching: [cont],
            pinnedItems: [],
            watchedChannels: [],
            actions: [action],
            suggestions: []
        )
        XCTAssertEqual(emptyItems.map(\.section), [.openTabs, .multiviewPresets, .continueWatching, .actions])

        // Non-empty query ranks matches + suggestions + guaranteed offline fallback search
        let queryItems = CommandPaletteEngine.rank(
            query: "nfl",
            openTabs: [tabA],
            presets: [preset],
            continueWatching: [cont],
            pinnedItems: [],
            watchedChannels: [],
            actions: [action],
            suggestions: ["nfl", "nfl highlights", "NFL Highlights"]
        )
        XCTAssertEqual(queryItems.first?.section, .multiviewPresets)
        XCTAssertEqual(queryItems.filter { $0.section == .suggestions }.map(\.title), ["nfl highlights"])
        XCTAssertEqual(queryItems.last?.section, .directSearch)

        // Direct YouTube URL puts Open YouTube Link at #1 without search fallback
        let urlItems = CommandPaletteEngine.rank(
            query: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            openTabs: [tabA],
            presets: [preset],
            continueWatching: [],
            pinnedItems: [],
            watchedChannels: [],
            actions: [action],
            suggestions: []
        )
        XCTAssertEqual(urlItems.first?.title, "Open YouTube Link")
        XCTAssertEqual(urlItems.filter { $0.section == .directSearch }.count, 1)
    }

    func testYouTubeSuggestClientParsing() throws {
        let json = #"["4k hdr",["4k hdr","4k hdr nature","4K HDR","4k hdr 60fps","4k hdr dolby","4k hdr oled","4k hdr extra","4k hdr overflow"]]"#
        let parsed = YouTubeSuggestClient.parseSuggestions(from: Data(json.utf8), maxCount: 6)
        XCTAssertEqual(parsed.count, 6)
        XCTAssertEqual(parsed[0], "4k hdr")
        XCTAssertEqual(parsed[1], "4k hdr nature")
        XCTAssertEqual(parsed[2], "4k hdr 60fps") // "4K HDR" deduplicated cleanly

        // Malformed / empty inputs fail silently to []
        XCTAssertEqual(YouTubeSuggestClient.parseSuggestions(from: Data()), [])
        XCTAssertEqual(YouTubeSuggestClient.parseSuggestions(from: Data("not json".utf8)), [])
        XCTAssertEqual(YouTubeSuggestClient.parseSuggestions(from: Data("{}".utf8)), [])
    }

    func testSeekToScriptAndMultiviewPresetCodableCap() throws {
        let seekJS = EnhancementScript.seekToScript(seconds: 125.5)
        XCTAssertTrue(seekJS.contains("125.5"))
        XCTAssertTrue(seekJS.contains("p.seekTo(next, true)"))
        XCTAssertTrue(seekJS.contains("__ytmacEmitStateNow"))
        XCTAssertFalse(seekJS.contains(":has("))
        XCTAssertFalse(seekJS.contains("MutationObserver"))

        // Non-finite and negative values clamp cleanly to 0
        let nanSeekJS = EnhancementScript.seekToScript(seconds: .nan)
        XCTAssertTrue(nanSeekJS.contains("Math.min(v.duration, 0.0)"))
        let negSeekJS = EnhancementScript.seekToScript(seconds: -42)
        XCTAssertTrue(negSeekJS.contains("Math.min(v.duration, 0.0)"))

        // MultiviewPreset caps at 4 URLs and round-trips via Codable
        let preset = MultiviewPreset(
            name: "Sunday Quad",
            urlStrings: [
                "https://www.youtube.com/watch?v=1",
                "https://www.youtube.com/watch?v=2",
                "https://tv.youtube.com/live",
                "https://www.youtube.com/watch?v=4",
                "https://www.youtube.com/watch?v=5"
            ],
            layoutMode: .spotlight
        )
        XCTAssertEqual(preset.urlStrings.count, 4)
        let encoded = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(MultiviewPreset.self, from: encoded)
        XCTAssertEqual(decoded, preset)
    }

    // MARK: - Wave 3 Pro Media & Viewing Ergonomics Tests

    func testMiniPlayerGeometryCornerSnapAndSizePresets() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = MiniPlayerSizePreset.standard.size // 480x270

        // Within 48pt of bottom-right corner -> snaps cleanly to (1440 - 480 - 20, 20) = (940, 20)
        let nearBottomRight = CGRect(x: 925, y: 34, width: size.width, height: size.height)
        let snappedBR = MiniPlayerGeometry.snappedFrame(nearBottomRight, in: visible)
        XCTAssertEqual(snappedBR.origin.x, 940)
        XCTAssertEqual(snappedBR.origin.y, 20)
        XCTAssertEqual(snappedBR.size, size)

        // Mid-screen placement (> 48pt from all corners) -> untouched
        let midScreen = CGRect(x: 480, y: 320, width: size.width, height: size.height)
        XCTAssertEqual(MiniPlayerGeometry.snappedFrame(midScreen, in: visible), midScreen)

        // Edge-anchored resize from bottom-right Compact -> Large keeps right & bottom edges anchored
        let compactBR = CGRect(x: 1060, y: 20, width: 360, height: 203)
        let resizedLarge = MiniPlayerGeometry.resizedFrame(from: compactBR, to: .large, in: visible)
        XCTAssertEqual(resizedLarge.maxX, compactBR.maxX)
        XCTAssertEqual(resizedLarge.minY, compactBR.minY)
        XCTAssertEqual(resizedLarge.width, 640)
        XCTAssertEqual(resizedLarge.height, 360)

        // Clamping on tiny screen preserves 16:9 ratio
        let tinyScreen = CGRect(x: 0, y: 0, width: 500, height: 320)
        let clamped = MiniPlayerGeometry.resizedFrame(from: CGRect(x: 20, y: 20, width: 360, height: 203), to: .extraLarge, in: tinyScreen)
        XCTAssertLessThanOrEqual(clamped.maxX, tinyScreen.maxX)
        XCTAssertLessThanOrEqual(clamped.maxY, tinyScreen.maxY)
        XCTAssertEqual(clamped.width / clamped.height, 16.0 / 9.0, accuracy: 0.05)

        // XL preset & tolerance-aware Shrink/Expand stepping
        XCTAssertEqual(MiniPlayerSizePreset.extraLarge.size, CGSize(width: 880, height: 495))
        XCTAssertEqual(MiniPlayerSizePreset.extraLarge.shortTitle, "XL")
        XCTAssertEqual(MiniPlayerSizePreset.stepLarger(from: CGSize(width: 360, height: 203)), .standard)
        XCTAssertEqual(MiniPlayerSizePreset.stepLarger(from: CGSize(width: 640, height: 360)), .extraLarge)
        XCTAssertEqual(MiniPlayerSizePreset.stepLarger(from: CGSize(width: 880, height: 495)), .extraLarge)
        XCTAssertEqual(MiniPlayerSizePreset.stepLarger(from: CGSize(width: 472, height: 266)), .large)
        XCTAssertEqual(MiniPlayerSizePreset.stepSmaller(from: CGSize(width: 880, height: 495)), .large)
        XCTAssertEqual(MiniPlayerSizePreset.stepSmaller(from: CGSize(width: 488, height: 275)), .compact)
        XCTAssertEqual(MiniPlayerSizePreset.stepSmaller(from: CGSize(width: 360, height: 203)), .compact)

        // Live 8-edge / corner drag resizing in Single mode (16:9 aspect-locked, opposite edge anchored, clamped)
        let start = CGRect(x: 500, y: 200, width: 480, height: 270)
        let singleMin = CGSize(width: 300, height: 169)
        let topDrag = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: start, edge: .top, delta: CGSize(width: 0, height: 90),
            maintainAspectRatio: true, minSize: singleMin, in: visible
        )
        XCTAssertEqual(topDrag.minY, start.minY, accuracy: 1.0)
        XCTAssertEqual(topDrag.midX, start.midX, accuracy: 1.0)
        XCTAssertEqual(topDrag.height, 360, accuracy: 1.0)
        XCTAssertEqual(topDrag.width, 640, accuracy: 1.0)

        let leftDrag = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: start, edge: .left, delta: CGSize(width: -160, height: 0),
            maintainAspectRatio: true, minSize: singleMin, in: visible
        )
        XCTAssertEqual(leftDrag.maxX, start.maxX, accuracy: 1.0)
        XCTAssertEqual(leftDrag.midY, start.midY, accuracy: 1.0)
        XCTAssertEqual(leftDrag.width, 640, accuracy: 1.0)
        XCTAssertEqual(leftDrag.height, 360, accuracy: 1.0)

        let rightShrinkClamp = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: start, edge: .right, delta: CGSize(width: -400, height: 0),
            maintainAspectRatio: true, minSize: singleMin, in: visible
        )
        XCTAssertEqual(rightShrinkClamp.minX, start.minX, accuracy: 1.0)
        XCTAssertEqual(rightShrinkClamp.width, 300, accuracy: 1.0)
        XCTAssertEqual(rightShrinkClamp.height, 169, accuracy: 1.0)

        let topLeftCorner = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: start, edge: .topLeft, delta: CGSize(width: -160, height: 90),
            maintainAspectRatio: true, minSize: singleMin, in: visible
        )
        XCTAssertEqual(topLeftCorner.maxX, start.maxX, accuracy: 1.0)
        XCTAssertEqual(topLeftCorner.minY, start.minY, accuracy: 1.0)
        XCTAssertEqual(topLeftCorner.width, 640, accuracy: 1.0)

        let bottomRightExpand = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: start, edge: .bottomRight, delta: CGSize(width: 160, height: -90),
            maintainAspectRatio: true, minSize: singleMin, in: visible
        )
        XCTAssertEqual(bottomRightExpand.minX, start.minX, accuracy: 1.0)
        XCTAssertEqual(bottomRightExpand.maxY, start.maxY, accuracy: 1.0)
        XCTAssertEqual(bottomRightExpand.width, 640, accuracy: 1.0)

        let bottomLeftExpand = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: start, edge: .bottomLeft, delta: CGSize(width: -160, height: -90),
            maintainAspectRatio: true, minSize: singleMin, in: visible
        )
        XCTAssertEqual(bottomLeftExpand.maxX, start.maxX, accuracy: 1.0)
        XCTAssertEqual(bottomLeftExpand.maxY, start.maxY, accuracy: 1.0)
        XCTAssertEqual(bottomLeftExpand.width, 640, accuracy: 1.0)

        let topRightCorner = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: start, edge: .topRight, delta: CGSize(width: 160, height: 90),
            maintainAspectRatio: true, minSize: singleMin, in: visible
        )
        XCTAssertEqual(topRightCorner.minX, start.minX, accuracy: 1.0)
        XCTAssertEqual(topRightCorner.minY, start.minY, accuracy: 1.0)
        XCTAssertEqual(topRightCorner.width, 640, accuracy: 1.0)

        let bottomDrag = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: start, edge: .bottom, delta: CGSize(width: 0, height: -90),
            maintainAspectRatio: true, minSize: singleMin, in: visible
        )
        XCTAssertEqual(bottomDrag.maxY, start.maxY, accuracy: 1.0)
        XCTAssertEqual(bottomDrag.height, 360, accuracy: 1.0)
        XCTAssertEqual(bottomDrag.width, 640, accuracy: 1.0)
    }

    func testVideoChapterParserStructuredAndDescription() {
        let single = VideoChapterParser.normalize([(title: "Only One", startSeconds: 0)])
        XCTAssertTrue(single.isEmpty, "Must require >= 2 valid chapters")

        let normalized = VideoChapterParser.normalize([
            (title: "Outro", startSeconds: 300),
            (title: " - Intro ", startSeconds: 0),
            (title: "Duplicate Zero", startSeconds: 0.4),
            (title: "Main Demo", startSeconds: 65)
        ])
        XCTAssertEqual(normalized.map(\.title), ["Intro", "Main Demo", "Outro"])
        XCTAssertEqual(normalized[1].formattedStartTime, "1:05")

        let desc = """
        Check out the chapters below:
        0:00 Intro & Overview
        02:15 - Architecture Walkthrough
        1:05:10 Deep Dive Benchmarks
        99:00 Beyond Duration
        """
        let fromDesc = VideoChapterParser.parseFromDescription(desc, maxDuration: 4200)
        XCTAssertEqual(fromDesc.count, 3)
        XCTAssertEqual(fromDesc[0].title, "Intro & Overview")
        XCTAssertEqual(fromDesc[1].startSeconds, 135)
        XCTAssertEqual(fromDesc[2].startSeconds, 3910)

        let active = VideoChapterParser.activeChapter(at: 200, in: fromDesc)
        XCTAssertEqual(active?.title, "Architecture Walkthrough")
    }

    func testMultiviewTileMoveQualityCeilingAndPinnedIcons() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let state = MultiviewState(tabIDs: [a, b, c], audioTabID: b, layoutMode: .spotlight)

        let movedRight = MultiviewReducer.moveTile(a, by: 1, in: state)
        XCTAssertEqual(movedRight.tabIDs, [b, a, c])
        XCTAssertEqual(movedRight.audioTabID, b)
        XCTAssertEqual(movedRight.layoutMode, .spotlight)

        let movedOutOfBounds = MultiviewReducer.moveTile(c, by: 1, in: state)
        XCTAssertEqual(movedOutOfBounds.tabIDs, [a, b, c])

        // Multiview quality ceiling override matrix
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .auto, isPrimaryOrTwoUp: false, ceilingOverride: .uhd2160),
            .auto
        )
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .uhd2160, isPrimaryOrTwoUp: false, ceilingOverride: .fhd1080),
            .fhd1080
        )
        XCTAssertEqual(
            PreferredVideoQuality.clampedForMultiview(userPreference: .uhd2160, isPrimaryOrTwoUp: true, ceilingOverride: .hd720),
            .hd720
        )

        // Semantic pinned item icons
        XCTAssertEqual(YouTubeURLRouter.pinnedItemIcon(for: "https://tv.youtube.com/live"), "tv")
        XCTAssertEqual(YouTubeURLRouter.pinnedItemIcon(for: "https://www.youtube.com/playlist?list=PL123"), "list.bullet.rectangle")
        XCTAssertEqual(YouTubeURLRouter.pinnedItemIcon(for: "https://www.youtube.com/@3blue1brown"), "person.crop.circle")
        XCTAssertEqual(YouTubeURLRouter.pinnedItemIcon(for: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "play.rectangle")
        XCTAssertEqual(YouTubeURLRouter.pinnedItemIcon(for: "https://www.youtube.com/feed/subscriptions"), "pin.fill")
    }

    func testEnhancementScriptWave3FrameCaptureAudioLevelAndChaptersInvariants() {
        let duckJS = EnhancementScript.setAudioLevelScript(muted: false, volumePercent: 15)
        XCTAssertTrue(duckJS.contains("__ytmacMarkProgrammaticMute"))
        XCTAssertTrue(duckJS.contains("p.setVolume(15)"))
        XCTAssertTrue(duckJS.contains("v.volume = 0.15"))
        XCTAssertTrue(duckJS.contains("v.muted = false"))
        XCTAssertFalse(duckJS.contains("AudioContext"))

        // Muting with 100% restore must set player volume BEFORE mute so unmuting never stays stuck at 15%
        let muteRestoreJS = EnhancementScript.setAudioLevelScript(muted: true, volumePercent: 100)
        XCTAssertTrue(muteRestoreJS.contains("p.setVolume(100)"))
        XCTAssertTrue(muteRestoreJS.contains("p.mute()"))
        if let volRange = muteRestoreJS.range(of: "p.setVolume(100)"),
           let muteRange = muteRestoreJS.range(of: "p.mute()") {
            XCTAssertLessThan(volRange.lowerBound, muteRange.lowerBound)
        }

        let captureJS = EnhancementScript.captureVideoFrameScript
        XCTAssertTrue(captureJS.contains("tv.youtube.com"))
        XCTAssertTrue(captureJS.contains("v.mediaKeys"))
        XCTAssertTrue(captureJS.contains("v.webkitKeys"))
        XCTAssertTrue(captureJS.contains("cors_fallback"))

        let boot = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())
        XCTAssertTrue(boot.contains("chaptersUpdated"))
        XCTAssertTrue(boot.contains("getPlayerResponse"))
        XCTAssertFalse(boot.contains("ytInitialPlayerResponse"))
        XCTAssertFalse(boot.contains(":has("))
        XCTAssertFalse(boot.contains("MutationObserver"))
        XCTAssertFalse(boot.contains("AudioContext"))
    }

    func testGlassGridYouCustomURLSchemeResolution() throws {
        let primary = try XCTUnwrap(URL(string: "glassgridyou://watch?v=LXb3EKWsInQ"))
        XCTAssertEqual(
            YouTubeURLRouter.resolveCustomSchemeURL(primary)?.absoluteString,
            "https://www.youtube.com/watch?v=LXb3EKWsInQ"
        )

        let yttv = try XCTUnwrap(URL(string: "glassgridyou://tv.youtube.com/live"))
        XCTAssertEqual(
            YouTubeURLRouter.resolveCustomSchemeURL(yttv)?.absoluteString,
            "https://tv.youtube.com/live"
        )

        let legacy = try XCTUnwrap(URL(string: "youtubemac://watch?v=aqz-KE-bpKQ"))
        XCTAssertEqual(
            YouTubeURLRouter.resolveCustomSchemeURL(legacy)?.absoluteString,
            "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
        )
    }

    func testSemanticVersionParsingAndComparison() {
        XCTAssertEqual(SemanticVersion("1.0.0"), SemanticVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion("V2.4"), SemanticVersion(major: 2, minor: 4, patch: 0))
        XCTAssertEqual(SemanticVersion("1.5.0-beta.1+42"), SemanticVersion(major: 1, minor: 5, patch: 0))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("not-a-version"))
        XCTAssertNil(SemanticVersion("1"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))

        XCTAssertTrue(SemanticVersion(major: 1, minor: 0, patch: 0) < SemanticVersion(major: 1, minor: 0, patch: 1))
        XCTAssertTrue(SemanticVersion(major: 1, minor: 2, patch: 9) < SemanticVersion(major: 1, minor: 3, patch: 0))
        XCTAssertTrue(SemanticVersion(major: 1, minor: 9, patch: 9) < SemanticVersion(major: 2, minor: 0, patch: 0))
        XCTAssertFalse(SemanticVersion(major: 2, minor: 0, patch: 0) < SemanticVersion(major: 2, minor: 0, patch: 0))
    }

    func testUpdateCheckerTrustedURLValidationAndReleaseParsing() throws {
        // Trusted URL validation
        XCTAssertTrue(UpdateChecker.isTrustedGitHubDownloadURL(try XCTUnwrap(URL(string: "https://github.com/ZacharyZell/glassgrid-you/releases/tag/v1.1.0"))))
        XCTAssertTrue(UpdateChecker.isTrustedGitHubDownloadURL(try XCTUnwrap(URL(string: "https://objects.githubusercontent.com/glassgrid/GlassGrid-You-1.1.0.dmg"))))
        XCTAssertFalse(UpdateChecker.isTrustedGitHubDownloadURL(try XCTUnwrap(URL(string: "http://github.com/ZacharyZell/glassgrid-you/releases"))))
        XCTAssertFalse(UpdateChecker.isTrustedGitHubDownloadURL(try XCTUnwrap(URL(string: "https://evil-github.com/malware.dmg"))))
        XCTAssertFalse(UpdateChecker.isTrustedGitHubDownloadURL(try XCTUnwrap(URL(string: "https://example.com/GlassGrid-You-1.1.0.dmg"))))

        let current = SemanticVersion(major: 1, minor: 0, patch: 0)

        // Newer release with trusted .dmg asset
        let newerJSON = """
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/ZacharyZell/glassgrid-you/releases/tag/v1.2.0",
          "draft": false,
          "prerelease": false,
          "body": "Signed macOS release.",
          "assets": [
            {
              "name": "GlassGrid-You-1.2.0.dmg.sha256",
              "browser_download_url": "https://github.com/ZacharyZell/glassgrid-you/releases/download/v1.2.0/GlassGrid-You-1.2.0.dmg.sha256"
            },
            {
              "name": "GlassGrid-You-1.2.0.dmg",
              "browser_download_url": "https://github.com/ZacharyZell/glassgrid-you/releases/download/v1.2.0/GlassGrid-You-1.2.0.dmg"
            }
          ]
        }
        """.data(using: .utf8)!

        let newerResult = UpdateChecker.parseLatestRelease(from: newerJSON, currentVersion: current)
        guard case .updateAvailable(let parsedCurrent, let info) = newerResult else {
            return XCTFail("Expected .updateAvailable, got \(newerResult)")
        }
        XCTAssertEqual(parsedCurrent, current)
        XCTAssertEqual(info.tagName, "v1.2.0")
        XCTAssertEqual(info.version, SemanticVersion(major: 1, minor: 2, patch: 0))
        XCTAssertEqual(
            info.dmgDownloadURL?.absoluteString,
            "https://github.com/ZacharyZell/glassgrid-you/releases/download/v1.2.0/GlassGrid-You-1.2.0.dmg"
        )
        XCTAssertEqual(info.preferredDownloadURL, info.dmgDownloadURL)

        // Up-to-date release
        let sameVersionJSON = """
        {
          "tag_name": "v1.0.0",
          "html_url": "https://github.com/ZacharyZell/glassgrid-you/releases/tag/v1.0.0",
          "draft": false,
          "prerelease": false
        }
        """.data(using: .utf8)!
        XCTAssertEqual(
            UpdateChecker.parseLatestRelease(from: sameVersionJSON, currentVersion: current),
            .upToDate(current: current)
        )

        // Draft and prerelease skipped cleanly
        let prereleaseJSON = """
        {
          "tag_name": "v2.0.0-beta.1",
          "html_url": "https://github.com/ZacharyZell/glassgrid-you/releases/tag/v2.0.0-beta.1",
          "draft": false,
          "prerelease": true
        }
        """.data(using: .utf8)!
        XCTAssertEqual(
            UpdateChecker.parseLatestRelease(from: prereleaseJSON, currentVersion: current),
            .noReleasesPublished
        )

        // Untrusted release URL rejected
        let untrustedReleaseJSON = """
        {
          "tag_name": "v1.3.0",
          "html_url": "https://phishing.example.com/v1.3.0",
          "draft": false,
          "prerelease": false
        }
        """.data(using: .utf8)!
        if case .failed = UpdateChecker.parseLatestRelease(from: untrustedReleaseJSON, currentVersion: current) {
            // expected
        } else {
            XCTFail("Expected untrusted release URL to fail security validation")
        }

        // Untrusted .dmg asset falls back safely to releaseURL
        let untrustedAssetJSON = """
        {
          "tag_name": "v1.3.0",
          "html_url": "https://github.com/ZacharyZell/glassgrid-you/releases/tag/v1.3.0",
          "draft": false,
          "prerelease": false,
          "assets": [
            {
              "name": "GlassGrid-You-1.3.0.dmg",
              "browser_download_url": "https://untrusted.example.com/GlassGrid-You-1.3.0.dmg"
            }
          ]
        }
        """.data(using: .utf8)!
        if case .updateAvailable(_, let safeInfo) = UpdateChecker.parseLatestRelease(from: untrustedAssetJSON, currentVersion: current) {
            XCTAssertNil(safeInfo.dmgDownloadURL)
            XCTAssertEqual(safeInfo.preferredDownloadURL, safeInfo.releaseURL)
        } else {
            XCTFail("Expected valid releaseURL with nil untrusted dmgDownloadURL")
        }

        // Malformed JSON fails gracefully
        let malformed = Data("not json".utf8)
        if case .failed = UpdateChecker.parseLatestRelease(from: malformed, currentVersion: current) {
            // expected
        } else {
            XCTFail("Expected malformed JSON to fail gracefully")
        }
    }

    // MARK: - Wave A: Draggable Multiview Dividers, Companion Web Tiles & Sidebar Folders

    func testMultiviewSplitRatiosAndDividersGeometryAndPresetCodable() throws {
        XCTAssertEqual(MultiviewGridLayout.defaultSpacing, 10)

        // Clamping & stacked floor
        let clamped = MultiviewSplitRatios(columnRatio: 0.05, rowRatio: 0.99, spotlightRatio: 0.95)
        XCTAssertEqual(clamped.columnRatio, MultiviewSplitRatios.minRatio, accuracy: 0.0001)
        XCTAssertEqual(clamped.rowRatio, MultiviewSplitRatios.maxRatio, accuracy: 0.0001)
        XCTAssertEqual(clamped.spotlightRatio ?? 0, MultiviewSplitRatios.maxRatio, accuracy: 0.0001)

        let stacked3 = MultiviewSplitRatios.default.updating(divider: .stacked(0), to: 0.02, tileCount: 3)
        let weights3 = stacked3.resolvedStackedWeights(for: 3)
        XCTAssertEqual(weights3.count, 3)
        XCTAssertGreaterThanOrEqual(weights3[0], MultiviewSplitRatios.minStackedWeight - 0.001)
        XCTAssertEqual(weights3.reduce(0, +), 1.0, accuracy: 0.001)

        // Reset restores defaults
        let reset = clamped.resetting(divider: .column, tileCount: 4).resetting(divider: .spotlight, tileCount: 3)
        XCTAssertEqual(reset.columnRatio, 0.50, accuracy: 0.0001)
        XCTAssertNil(reset.spotlightRatio)

        // Pixel-exact non-overlapping tiles & 10pt gutter dividers across all layouts & container shapes
        let customRatios = MultiviewSplitRatios(columnRatio: 0.65, rowRatio: 0.35, spotlightRatio: 0.70)
        let containers = [CGSize(width: 1281, height: 779), CGSize(width: 640, height: 820)]
        for size in containers {
            for mode in MultiviewLayoutMode.allCases {
                for count in 2...4 {
                    let frames = MultiviewGridLayout.frames(forCount: count, in: size, mode: mode, ratios: customRatios)
                    let dividers = MultiviewGridLayout.dividers(forCount: count, in: size, mode: mode, ratios: customRatios)
                    XCTAssertEqual(frames.count, count)
                    XCTAssertFalse(dividers.isEmpty, "Expected at least one divider for count \(count), mode \(mode)")

                    for divider in dividers {
                        XCTAssertEqual(divider.frame.origin.x, divider.frame.origin.x.rounded())
                        XCTAssertEqual(divider.frame.origin.y, divider.frame.origin.y.rounded())
                        XCTAssertEqual(divider.frame.width, divider.frame.width.rounded())
                        XCTAssertEqual(divider.frame.height, divider.frame.height.rounded())
                        if divider.axis == .vertical {
                            XCTAssertEqual(divider.frame.width, MultiviewGridLayout.defaultSpacing)
                        } else {
                            XCTAssertEqual(divider.frame.height, MultiviewGridLayout.defaultSpacing)
                        }
                        for (idx, tile) in frames.enumerated() {
                            XCTAssertFalse(
                                divider.frame.intersects(tile),
                                "Divider \(divider.id) overlapped tile \(idx) in mode \(mode) count \(count)"
                            )
                        }
                    }
                }
            }
        }

        // Backward-compatible MultiviewPreset decoding when splitRatios key is absent
        let legacyPresetJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy Quad",
          "urlStrings": ["https://www.youtube.com/watch?v=LXb3EKWsInQ", "https://tv.youtube.com/live"],
          "layoutMode": "auto"
        }
        """.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(MultiviewPreset.self, from: legacyPresetJSON)
        XCTAssertEqual(decodedLegacy.name, "Legacy Quad")
        XCTAssertNil(decodedLegacy.splitRatios)

        // Round-trip with splitRatios persisted
        let withRatios = MultiviewPreset(
            name: "70/30 Game + Scores",
            urlStrings: ["https://tv.youtube.com/live", "https://www.espn.com/scoreboard"],
            layoutMode: .spotlight,
            splitRatios: customRatios
        )
        let encoded = try JSONEncoder().encode(withRatios)
        let decodedWithRatios = try JSONDecoder().decode(MultiviewPreset.self, from: encoded)
        XCTAssertEqual(decodedWithRatios.splitRatios, customRatios)
    }

    func testCompanionRoutingURLsSessionRestorationAndIcons() throws {
        // Companion URL resolution & dangerous scheme rejection
        XCTAssertEqual(
            YouTubeURLRouter.resolveCompanionURL("twitch.tv/nfl")?.absoluteString,
            "https://twitch.tv/nfl"
        )
        XCTAssertEqual(
            YouTubeURLRouter.resolveCompanionURL("https://www.espn.com/scoreboard")?.absoluteString,
            "https://www.espn.com/scoreboard"
        )
        XCTAssertNil(YouTubeURLRouter.resolveCompanionURL("javascript:alert(1)"))
        XCTAssertNil(YouTubeURLRouter.resolveCompanionURL("file:///etc/passwd"))
        XCTAssertNil(YouTubeURLRouter.resolveCompanionURL("data:text/html,<h1>x</h1>"))
        XCTAssertNil(YouTubeURLRouter.resolveCompanionURL("nfl live scores"))

        // Host classification
        XCTAssertTrue(YouTubeURLRouter.isStandardYouTubeHost("www.youtube.com"))
        XCTAssertFalse(YouTubeURLRouter.isStandardYouTubeHost("tv.youtube.com"))
        XCTAssertFalse(YouTubeURLRouter.isStandardYouTubeHost("www.twitch.tv"))

        // Navigation routing in .companion vs .youtube mode
        let twitchChannel = try XCTUnwrap(URL(string: "https://www.twitch.tv/esl_cs"))
        let espnHome = try XCTUnwrap(URL(string: "https://www.espn.com/scoreboard"))
        let mailto = try XCTUnwrap(URL(string: "mailto:support@example.com"))

        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: twitchChannel,
                currentPageURL: espnHome,
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: true,
                routingMode: .companion
            ),
            .allowInApp
        )
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: twitchChannel,
                currentPageURL: URL(string: "https://www.youtube.com"),
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: true,
                routingMode: .youtube
            ),
            .openExternal(twitchChannel)
        )
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: mailto,
                currentPageURL: espnHome,
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: true,
                routingMode: .companion
            ),
            .openExternal(mailto)
        )

        // Companion icon & Session restoration
        XCTAssertEqual(YouTubeURLRouter.pinnedItemIcon(for: "https://www.espn.com/scoreboard"), "globe")
        XCTAssertEqual(YouTubeURLRouter.pinnedItemIcon(for: "https://tv.youtube.com/live"), "tv")

        let legacySnapJSON = """
        {"urlString": "https://www.youtube.com/watch?v=LXb3EKWsInQ", "title": "Costa Rica"}
        """.data(using: .utf8)!
        let decodedSnap = try JSONDecoder().decode(SavedTabSnapshot.self, from: legacySnapJSON)
        XCTAssertEqual(decodedSnap.routingMode, .youtube)

        let mixedSession = SessionRestorationFilter.sanitize(
            tabs: [
                SavedTabSnapshot(urlString: "https://www.youtube.com/watch?v=LXb3EKWsInQ", title: "4K HDR", routingMode: .youtube),
                SavedTabSnapshot(urlString: "https://www.espn.com/scoreboard", title: "ESPN Scores", routingMode: .companion),
                SavedTabSnapshot(urlString: "https://accounts.google.com/ServiceLogin", title: "Sign in", routingMode: .companion),
                SavedTabSnapshot(urlString: "https://example.com/rogue", title: "Rogue", routingMode: .youtube)
            ],
            selectedIndex: 1
        )
        XCTAssertEqual(mixedSession?.tabs.count, 2)
        XCTAssertEqual(mixedSession?.tabs[1].urlString, "https://www.espn.com/scoreboard")
        XCTAssertEqual(mixedSession?.tabs[1].routingMode, .companion)
        XCTAssertEqual(mixedSession?.selectedIndex, 1)
    }

    func testPinnedFoldersBackwardCompatibilityAndCommandPalette() throws {
        // Legacy PinnedItem without folderID decodes cleanly
        let legacyPinJSON = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "title": "MKBHD",
          "urlString": "https://www.youtube.com/@mkbhd",
          "addedAt": 0
        }
        """.data(using: .utf8)!
        let decodedLegacyPin = try JSONDecoder().decode(PinnedItem.self, from: legacyPinJSON)
        XCTAssertNil(decodedLegacyPin.folderID)

        let sportsFolder = PinnedFolder(name: "Sports", isExpanded: true)
        let espnPin = PinnedItem(title: "ESPN Scores", urlString: "https://www.espn.com/scoreboard", folderID: sportsFolder.id)
        let yttvPin = PinnedItem(title: "YouTube TV", urlString: "https://tv.youtube.com/live", folderID: sportsFolder.id)

        // Folder search & grouped pin subtitle in Command Palette
        let folderResults = CommandPaletteEngine.rank(
            query: "Sports",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [espnPin, yttvPin],
            pinnedFolders: [sportsFolder],
            watchedChannels: [],
            actions: [],
            suggestions: []
        )
        XCTAssertTrue(folderResults.contains(where: { $0.payload == .openPinnedFolder(sportsFolder.id) }))
        XCTAssertTrue(folderResults.contains(where: { $0.title == "ESPN Scores" && $0.subtitle == "Pinned • Sports" }))

        // Companion URL detection in Command Palette without leaking to autocomplete suggestions
        XCTAssertFalse(CommandPaletteEngine.shouldFetchSuggestions(for: "espn.com/scoreboard"))
        let urlResults = CommandPaletteEngine.rank(
            query: "espn.com/scoreboard",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [],
            pinnedFolders: [],
            watchedChannels: [],
            actions: [],
            suggestions: []
        )
        XCTAssertEqual(
            urlResults.first?.payload,
            .openCompanionURL(try XCTUnwrap(URL(string: "https://espn.com/scoreboard")))
        )

        // Quick-site Companion search ("Twitch")
        let twitchResults = CommandPaletteEngine.rank(
            query: "Twitch",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [],
            pinnedFolders: [],
            watchedChannels: [],
            actions: [],
            suggestions: []
        )
        XCTAssertTrue(twitchResults.contains(where: {
            if case .openCompanionURL(let url) = $0.payload {
                return url.host?.contains("twitch.tv") == true
            }
            return false
        }))
    }

    func testEnhancementScriptWebCompanionIsolationAndUniversalVideoFallback() {
        let boot = EnhancementScript.bootstrapScript(config: DistractionFreeConfig(multiviewTileActive: true))
        XCTAssertTrue(boot.contains("isWebCompanionHost()"))
        XCTAssertTrue(boot.contains("if (isWebCompanionHost() || !document.head || document.getElementById('ytmac-style')) return;"))
        XCTAssertTrue(boot.contains("source[src]"))
        XCTAssertTrue(boot.contains("isStdYT ? 'youtube' : 'web'"))
        XCTAssertTrue(boot.contains("window.__ytmacGetMainVideo = getMainVideo"))
        XCTAssertTrue(boot.contains("window.addEventListener('play', handleCapturedVideoEvent, true)"))
        XCTAssertTrue(boot.contains("window.addEventListener('playing', handleCapturedVideoEvent, true)"))
        XCTAssertTrue(boot.contains("window.addEventListener('loadedmetadata', handleCapturedVideoEvent, true)"))

        // Standalone playback scripts include universal non-YouTube <video> & <source src> fallback
        for script in [
            EnhancementScript.setMutedScript(muted: true),
            EnhancementScript.setAudioLevelScript(muted: false, volumePercent: 15),
            EnhancementScript.pauseScript,
            EnhancementScript.togglePlayPauseScript
        ] {
            XCTAssertTrue(script.contains("__ytmacGetMainVideo"))
            XCTAssertTrue(script.contains("root.querySelectorAll('video')"))
            XCTAssertTrue(script.contains("collectVids(document, 0)"))
            XCTAssertTrue(script.contains("source[src]"))
        }

        // Hard engineering invariants preserved
        XCTAssertFalse(boot.contains(":has("))
        XCTAssertFalse(boot.contains("MutationObserver"))
        XCTAssertFalse(boot.contains("AudioContext"))
        XCTAssertFalse(boot.contains("ytInitialPlayerResponse"))
    }

    // MARK: - Wave B: Multi-Window Title Formatting & Sparkle 2 Configuration Guard

    func testSparkleConfigurationValidation() {
        XCTAssertEqual(SparkleConfiguration.defaultFeedURLString, "https://glassgridyou.com/appcast.xml")

        let validKey = Data(repeating: 0x42, count: 32).base64EncodedString()
        let shortKey = Data(repeating: 0x42, count: 16).base64EncodedString()

        XCTAssertTrue(
            SparkleConfiguration.isConfigured(infoDictionary: [
                SparkleConfiguration.feedURLKey: SparkleConfiguration.defaultFeedURLString,
                SparkleConfiguration.publicEDKey: validKey
            ])
        )
        XCTAssertFalse(SparkleConfiguration.isConfigured(infoDictionary: nil))
        XCTAssertFalse(SparkleConfiguration.isConfigured(infoDictionary: [:]))
        XCTAssertFalse(
            SparkleConfiguration.isConfigured(infoDictionary: [
                SparkleConfiguration.feedURLKey: SparkleConfiguration.defaultFeedURLString,
                SparkleConfiguration.publicEDKey: ""
            ])
        )
        XCTAssertFalse(
            SparkleConfiguration.isConfigured(infoDictionary: [
                SparkleConfiguration.feedURLKey: "http://example.com/appcast.xml",
                SparkleConfiguration.publicEDKey: validKey
            ])
        )
        XCTAssertFalse(
            SparkleConfiguration.isConfigured(infoDictionary: [
                SparkleConfiguration.feedURLKey: SparkleConfiguration.defaultFeedURLString,
                SparkleConfiguration.publicEDKey: shortKey
            ])
        )
        XCTAssertFalse(
            SparkleConfiguration.isConfigured(infoDictionary: [
                SparkleConfiguration.feedURLKey: SparkleConfiguration.defaultFeedURLString,
                SparkleConfiguration.publicEDKey: "not-valid-base64!!!"
            ])
        )
    }

    func testWindowTitleFormatterForMultiviewSingleAndHome() {
        XCTAssertEqual(
            WindowTitleFormatter.title(isMultiview: true, multiviewCount: 4, tabTitle: "ESPN", isHome: false),
            "Multiview (4 Streams) — GlassGrid You"
        )
        XCTAssertEqual(
            WindowTitleFormatter.title(isMultiview: false, multiviewCount: 0, tabTitle: "(12) Costa Rica 4K HDR - YouTube", isHome: false),
            "Costa Rica 4K HDR — GlassGrid You"
        )
        XCTAssertEqual(
            WindowTitleFormatter.title(isMultiview: false, multiviewCount: 0, tabTitle: "YouTube", isHome: true),
            "GlassGrid You"
        )
        XCTAssertEqual(
            WindowTitleFormatter.title(isMultiview: false, multiviewCount: 0, tabTitle: "", isHome: false),
            "GlassGrid You"
        )
    }

    // MARK: - v1.1.1: Window Chrome Rounded-Arc Containment & Unified Titlebar Geometry

    func testWindowChromeLayoutTahoeAndSequoiaUnifiedPassAllInvariants() {
        XCTAssertEqual(WindowChromeLayout.sidebarHeaderCenterY, 26.0, accuracy: 0.001)
        XCTAssertEqual(WindowChromeLayout.topHeaderBarCenterY, 26.0, accuracy: 0.001)

        // Sidebar Expanded / Collapsed / Native Fullscreen padding contract
        XCTAssertEqual(WindowChromeLayout.sidebarHeaderLeadingPadding(isNativeFullScreen: false), 78.0, accuracy: 0.001)
        XCTAssertEqual(WindowChromeLayout.sidebarHeaderLeadingPadding(isNativeFullScreen: true), 8.0, accuracy: 0.001)
        XCTAssertEqual(WindowChromeLayout.collapsedNavLeadingPadding(isSidebarVisible: true, isNativeFullScreen: false), 8.0, accuracy: 0.001)
        XCTAssertEqual(WindowChromeLayout.collapsedNavLeadingPadding(isSidebarVisible: false, isNativeFullScreen: false), 90.0, accuracy: 0.001)
        XCTAssertEqual(WindowChromeLayout.collapsedNavLeadingPadding(isSidebarVisible: false, isNativeFullScreen: true), 12.0, accuracy: 0.001)

        // macOS 26/27 Tahoe unified 52pt titlebar
        let tahoeAudit = WindowChromeLayout.audit(trafficLights: .tahoeUnified)
        XCTAssertTrue(tahoeAudit.passed, "Tahoe unified audit failed: \(tahoeAudit.violations)")
        XCTAssertEqual(tahoeAudit.minInwardClearance, 11.0, accuracy: 0.01)
        XCTAssertEqual(tahoeAudit.sidebarHeaderCenterDelta, 0.0, accuracy: 0.01)
        XCTAssertEqual(tahoeAudit.topHeaderBarCenterDelta, 0.0, accuracy: 0.01)
        XCTAssertEqual(tahoeAudit.expandedSidebarLeadingClearance, 7.0, accuracy: 0.01)
        XCTAssertEqual(tahoeAudit.collapsedNavLeadingClearance, 11.0, accuracy: 0.01)

        // macOS 15 Sequoia unified 52pt titlebar
        let sequoiaAudit = WindowChromeLayout.audit(trafficLights: .sequoiaUnified)
        XCTAssertTrue(sequoiaAudit.passed, "Sequoia unified audit failed: \(sequoiaAudit.violations)")
        XCTAssertEqual(sequoiaAudit.minInwardClearance, 11.0, accuracy: 0.01)
        XCTAssertEqual(sequoiaAudit.sidebarHeaderCenterDelta, 1.0, accuracy: 0.01)
        XCTAssertEqual(sequoiaAudit.topHeaderBarCenterDelta, 1.0, accuracy: 0.01)
        XCTAssertEqual(sequoiaAudit.expandedSidebarLeadingClearance, 14.0, accuracy: 0.01)
        XCTAssertEqual(sequoiaAudit.collapsedNavLeadingClearance, 18.0, accuracy: 0.01)
    }

    func testWindowChromeLayoutDetectsCompactTitlebarCornerArcClipAndCollapsedOverlap() {
        // Negative regression 1: historical compact 32pt titlebar clips the 16pt corner arc by ~2.31pt
        let legacyAudit = WindowChromeLayout.audit(trafficLights: .legacyCompact32)
        XCTAssertFalse(legacyAudit.passed)
        XCTAssertLessThan(legacyAudit.minInwardClearance, 0.0)
        XCTAssertEqual(legacyAudit.minInwardClearance, -2.3137, accuracy: 0.01)
        XCTAssertGreaterThan(legacyAudit.sidebarHeaderCenterDelta, WindowChromeLayout.maximumCenterlineDelta)
        XCTAssertGreaterThan(legacyAudit.topHeaderBarCenterDelta, WindowChromeLayout.maximumCenterlineDelta)

        // Negative regression 2: old 78pt collapsed padding overlaps Tahoe zoom.maxX = 79pt
        let oldCollapsedPaddingAudit = WindowChromeLayout.audit(
            trafficLights: .tahoeUnified,
            collapsedLeadingPaddingOverride: 78.0
        )
        XCTAssertFalse(oldCollapsedPaddingAudit.passed)
        XCTAssertLessThan(oldCollapsedPaddingAudit.collapsedNavLeadingClearance, 0.0)

        // Safety check: degenerate small rounded rect clamps corner radius cleanly without NaN/Inf
        let degenerateClearance = WindowChromeLayout.inwardClearance(
            ofCircleIn: CGRect(x: 2, y: 2, width: 10, height: 10),
            insideRoundedRect: CGRect(x: 0, y: 0, width: 6, height: 6),
            cornerRadius: 40
        )
        XCTAssertTrue(degenerateClearance.isFinite)
        XCTAssertLessThan(degenerateClearance, 0.0)
    }

    // MARK: - v1.2.0: Streaming Services, Solo Multiview, Live Sync, Shadow DOM & AirPlay

    func testStreamingServiceCatalogIntegrityDomainIsolationAndSignInDetection() {
        let services = StreamingServiceCatalog.all
        XCTAssertEqual(services.count, 18)
        XCTAssertEqual(Set(services.map(\.id)).count, 18)

        let tier1Count = services.filter { !$0.requiresStrictDRM }.count
        let tier2Count = services.filter { $0.requiresStrictDRM }.count
        XCTAssertEqual(tier1Count, 11)
        XCTAssertEqual(tier2Count, 7)
        XCTAssertEqual(StreamingServiceCatalog.services(in: .moviesAndShows).count, 9)

        for service in services {
            XCTAssertEqual(service.homeURL.scheme, "https", "Invalid home URL for \(service.id)")
            XCTAssertEqual(service.signInURL.scheme, "https", "Invalid sign-in URL for \(service.id)")
            XCTAssertFalse(service.dataDomains.isEmpty, "Missing dataDomains for \(service.id)")
            if service.id == "youtube" || service.id == "yttv" {
                XCTAssertEqual(service.routingMode, .youtube)
            } else {
                XCTAssertEqual(service.routingMode, .companion)
            }
            if let homeHost = service.homeURL.host?.lowercased() {
                for authHint in service.authHostHints {
                    let lowerHint = authHint.lowercased()
                    XCTAssertFalse(
                        homeHost == lowerHint || homeHost.hasSuffix("." + lowerHint) || lowerHint.hasSuffix("." + homeHost),
                        "Service \(service.id) must not place shared content host \(homeHost) in authHostHints (\(lowerHint))"
                    )
                }
            }
        }

        // Strict per-service domain isolation (never matches sibling or substring lookalike domains)
        let twitch = StreamingServiceCatalog.service(id: "twitch")!
        XCTAssertTrue(StreamingServiceCatalog.matchesDataRecord(displayName: "twitch.tv", for: twitch))
        XCTAssertTrue(StreamingServiceCatalog.matchesDataRecord(displayName: "passport.twitch.tv", for: twitch))
        XCTAssertTrue(StreamingServiceCatalog.matchesCookieDomain(".ttvnw.net", for: twitch))
        XCTAssertFalse(StreamingServiceCatalog.matchesDataRecord(displayName: "not-twitch.tv", for: twitch))
        XCTAssertFalse(StreamingServiceCatalog.matchesDataRecord(displayName: "youtube.com", for: twitch))
        XCTAssertFalse(StreamingServiceCatalog.matchesDataRecord(displayName: "espn.com", for: twitch))
        XCTAssertFalse(StreamingServiceCatalog.matchesDataRecord(displayName: "disneyplus.com", for: twitch))

        // Honest shared-SSO warnings
        XCTAssertNotNil(StreamingServiceCatalog.sharedSSOWarning(for: StreamingServiceCatalog.service(id: "youtube")!))
        XCTAssertNotNil(StreamingServiceCatalog.sharedSSOWarning(for: StreamingServiceCatalog.service(id: "disneyplus")!))
        XCTAssertNil(StreamingServiceCatalog.sharedSSOWarning(for: twitch))

        // Conservative passive sign-in detection (Netflix & YouTube)
        let netflix = StreamingServiceCatalog.service(id: "netflix")!
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.netflix.com/login"), for: netflix))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.netflix.com/browse"), for: netflix))
        let youtube = StreamingServiceCatalog.service(id: "youtube")!
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://accounts.google.com/ServiceLogin?service=youtube"), for: youtube))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.youtube.com/"), for: youtube))

        // Prime Video OpenID sign-in URL, regional resolution, cookie checks & sign-in detection
        let prime = StreamingServiceCatalog.service(id: "primevideo")!
        let primeSignInQuery = prime.signInURL.query ?? ""
        XCTAssertTrue(primeSignInQuery.contains("openid.mode=checkid_setup"))
        XCTAssertTrue(primeSignInQuery.contains("gp%2Fvideo%2Fstorefront"))
        XCTAssertTrue(primeSignInQuery.contains("openid.ns="))

        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://www.amazon.com/gp/video/storefront"))?.id, "primevideo")
        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://www.amazon.co.uk/gp/video/storefront"))?.id, "primevideo")
        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://www.amazon.de/gp/video/detail/B001"))?.id, "primevideo")
        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://www.primevideo.com/storefront"))?.id, "primevideo")
        XCTAssertTrue(StreamingServiceCatalog.matchesDataRecord(displayName: "amazon.co.uk", for: prime))
        XCTAssertFalse(StreamingServiceCatalog.matchesDataRecord(displayName: "evil-amazon.com", for: prime))

        for notSignedIn in [
            "https://www.amazon.com/ap/signin",
            "https://www.amazon.com/ax/claim?arb=123",
            "https://www.amazon.com/ap/mfa",
            "https://www.amazon.com/ap/cvf",
            "https://www.amazon.com/gp/video/splash/t/signIn",
            "https://www.amazon.com/gp/video/offers",
            "https://www.primevideo.com/offers/nonprimehomepage"
        ] {
            XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: notSignedIn), for: prime), "Should not be signed-in: \(notSignedIn)")
        }
        for signedInCandidate in [
            "https://www.amazon.com/gp/video/storefront",
            "https://amazon.com/gp/video/home",
            "https://www.amazon.co.uk/gp/video/storefront",
            "https://www.primevideo.com/storefront"
        ] {
            XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: signedInCandidate), for: prime), "Expected candidate signed-in path: \(signedInCandidate)")
        }

        XCTAssertEqual(StreamingServiceCatalog.hasAuthenticatedSessionCookie(cookieEntries: [("session-id", ".amazon.com")], for: prime), false)
        XCTAssertEqual(StreamingServiceCatalog.hasAuthenticatedSessionCookie(cookieEntries: [("x-main", ".amazon.com")], for: prime), false)
        XCTAssertEqual(StreamingServiceCatalog.hasAuthenticatedSessionCookie(cookieEntries: [("at-main", ".evil-amazon.com")], for: prime), false)
        for cookieName in ["at-main", "sess-at-main", "at-main-av", "sess-at-main-av", "at-av", "sess-at-av", "at-acbuk", "sess-at-acbde"] {
            let domain = cookieName.contains("-av") ? ".primevideo.com" : ".amazon.co.uk"
            XCTAssertEqual(
                StreamingServiceCatalog.hasAuthenticatedSessionCookie(cookieEntries: [(cookieName, domain)], for: prime),
                true,
                "Expected cookie \(cookieName) on \(domain) to confirm Prime Video session"
            )
        }

        // Crunchyroll catalog, domain isolation, BCP-47 locales & sign-in detection
        let crunchy = StreamingServiceCatalog.service(id: "crunchyroll")!
        XCTAssertEqual(crunchy.category, .moviesAndShows)
        XCTAssertTrue(crunchy.requiresStrictDRM)
        XCTAssertNil(StreamingServiceCatalog.sharedSSOWarning(for: crunchy))
        XCTAssertTrue(StreamingServiceCatalog.matchesDataRecord(displayName: "crunchyroll.com", for: crunchy))
        XCTAssertTrue(StreamingServiceCatalog.matchesDataRecord(displayName: "sso.crunchyroll.com", for: crunchy))
        XCTAssertTrue(StreamingServiceCatalog.matchesCookieDomain(".crunchyroll.com", for: crunchy))
        XCTAssertTrue(StreamingServiceCatalog.matchesDataRecord(displayName: "cr-play-service.prd.crunchyrollsvc.com", for: crunchy))
        XCTAssertTrue(StreamingServiceCatalog.matchesDataRecord(displayName: "v.vrv.co", for: crunchy))
        XCTAssertFalse(StreamingServiceCatalog.matchesDataRecord(displayName: "not-crunchyroll.com", for: crunchy))
        XCTAssertFalse(StreamingServiceCatalog.matchesDataRecord(displayName: "netflix.com", for: crunchy))

        for blockedCR in [
            "https://sso.crunchyroll.com/login",
            "https://www.crunchyroll.com/login",
            "https://www.crunchyroll.com/es-es/login",
            "https://www.crunchyroll.com/pt-br/welcome",
            "https://www.crunchyroll.com/pt-br/freetrial",
            "https://www.crunchyroll.com/es-es/premium",
            "https://www.crunchyroll.com/es-es/register"
        ] {
            XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: blockedCR), for: crunchy), "Expected logged-out/auth for \(blockedCR)")
        }
        for allowedCR in [
            "https://www.crunchyroll.com/",
            "https://www.crunchyroll.com/discover",
            "https://www.crunchyroll.com/watch/G12345/ep-1"
        ] {
            XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: allowedCR), for: crunchy), "Expected signed-in destination for \(allowedCR)")
        }

        // Auth/OAuth popup & transient auth URL detection
        for transientURL in [
            "https://www.amazon.com/ap/signin",
            "https://www.amazon.com/ax/claim?arb=1",
            "https://www.amazon.com/ap/mfa",
            "https://na.account.amazon.com/",
            "https://sso.crunchyroll.com/login",
            "https://www.primevideo.com/auth-redirect/ref=dv"
        ] {
            let parsed = URL(string: transientURL)!
            XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(parsed))
            XCTAssertTrue(StreamingServiceCatalog.isAuthOrOAuthPopupURL(parsed))
        }
        for nonAuthURL in [
            "https://www.amazon.com/gp/video/storefront",
            "https://www.crunchyroll.com/discover",
            "https://www.netflix.com/browse",
            "https://www.espn.com/tournament-challenge"
        ] {
            let parsed = URL(string: nonAuthURL)!
            XCTAssertFalse(StreamingServiceCatalog.isTransientAuthURL(parsed))
            XCTAssertFalse(StreamingServiceCatalog.isAuthOrOAuthPopupURL(parsed))
        }

        // Session restoration strips transient auth URLs while keeping valid companion tabs (like ESPN Tournament Challenge)
        let snapshots = [
            SavedTabSnapshot(urlString: "https://www.amazon.com/ax/claim?arb=123", title: "Sign-In", routingMode: .companion),
            SavedTabSnapshot(urlString: "https://sso.crunchyroll.com/login", title: "Login", routingMode: .companion),
            SavedTabSnapshot(urlString: "https://www.amazon.com/gp/video/storefront", title: "Prime Video", routingMode: .companion),
            SavedTabSnapshot(urlString: "https://www.crunchyroll.com/discover", title: "Crunchyroll", routingMode: .companion),
            SavedTabSnapshot(urlString: "https://www.espn.com/tournament-challenge", title: "ESPN", routingMode: .companion)
        ]
        let sanitizedSession = SessionRestorationFilter.sanitize(tabs: snapshots, selectedIndex: 0)!
        XCTAssertEqual(sanitizedSession.tabs.map(\.urlString), [
            "https://www.amazon.com/gp/video/storefront",
            "https://www.crunchyroll.com/discover",
            "https://www.espn.com/tournament-challenge"
        ])

        // App-handoff & internal schemes blocked even on companion subframes/links
        for blockedScheme in ["aiv://detail", "amzn://home", "amazon://gp", "primevideo://open", "crunchyroll://watch/1", "glassgridyou://action/play", "youtubemac://watch?v=1"] {
            XCTAssertEqual(
                YouTubeURLRouter.routeNavigation(
                    url: URL(string: blockedScheme)!,
                    currentPageURL: URL(string: "https://www.amazon.com/gp/video/storefront"),
                    isUserLinkClick: true,
                    openExternalLinksInBrowser: true,
                    redirectShortsToWatch: true,
                    routingMode: .companion
                ),
                .block
            )
        }
        XCTAssertTrue(YouTubeURLRouter.isBlockedAppScheme("aiv"))
        XCTAssertTrue(YouTubeURLRouter.isBlockedAppScheme("crunchyroll"))
        XCTAssertTrue(YouTubeURLRouter.isAllowedWebScheme("https"))
        XCTAssertFalse(YouTubeURLRouter.isAllowedWebScheme("aiv"))

        // CompanionQuickSite & EnhancementScript auth bailout invariant
        XCTAssertTrue(CompanionQuickSite.catalog.contains { $0.id == "crunchyroll" })
        let boot = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())
        XCTAssertTrue(boot.contains("isCompanionAuthPage"))
        XCTAssertFalse(boot.contains(":has("))
        XCTAssertFalse(boot.contains("MutationObserver"))
        XCTAssertFalse(boot.contains("AudioContext"))
        XCTAssertFalse(boot.contains("ytInitialPlayerResponse"))
    }

    func testMultiviewReducerSoloToggleAndAutoClear() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let initial = MultiviewState(tabIDs: [a, b, c], audioTabID: a, layoutMode: .auto)

        // Enter solo on tile B -> transfers audio focus to B while preserving tile order
        let soloed = MultiviewReducer.toggleSolo(b, in: initial)
        XCTAssertEqual(soloed.soloTabID, b)
        XCTAssertEqual(soloed.audioTabID, b)
        XCTAssertEqual(soloed.tabIDs, [a, b, c])

        // Toggling B again exits solo cleanly
        let unsoloed = MultiviewReducer.toggleSolo(b, in: soloed)
        XCTAssertNil(unsoloed.soloTabID)
        XCTAssertEqual(unsoloed.audioTabID, b)

        // Removing the currently soloed tile clears soloTabID cleanly
        let afterRemoveSolo = MultiviewReducer.removeTile(b, from: soloed)
        XCTAssertNil(afterRemoveSolo.state.soloTabID)
        XCTAssertEqual(afterRemoveSolo.state.tabIDs, [a, c])

        // Removing down to 1 tile exits Multiview and clears soloTabID
        let soloA = MultiviewReducer.toggleSolo(a, in: afterRemoveSolo.state)
        let afterExit = MultiviewReducer.removeTile(c, from: soloA)
        XCTAssertFalse(afterExit.state.isActive)
        XCTAssertNil(afterExit.state.soloTabID)
        XCTAssertEqual(afterExit.remainingSingleTabID, a)
    }

    func testEnhancementScriptV120ShadowDOMLiveSyncSoloAndAirPlayInvariants() {
        let boot = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())
        XCTAssertTrue(boot.contains("collectVideos(document, 0)"))
        XCTAssertTrue(boot.contains("ev.composedPath"))
        XCTAssertTrue(boot.contains("x-webkit-airplay"))
        XCTAssertTrue(boot.contains("webkitplaybacktargetavailabilitychanged"))
        XCTAssertTrue(boot.contains("webkitcurrentplaybacktargetiswirelesschanged"))

        let seekScript = EnhancementScript.seekByScript(seconds: 1.0)
        XCTAssertTrue(seekScript.contains("v.seekable"))
        XCTAssertTrue(seekScript.contains("maxT - 0.25"))

        let liveScript = EnhancementScript.seekToLiveEdgeScript
        XCTAssertTrue(liveScript.contains("v.seekable"))
        XCTAssertTrue(liveScript.contains("maxT - 0.5"))

        let syncScript = EnhancementScript.syncPlayerSizeScript
        XCTAssertTrue(syncScript.contains("document.fullscreenElement"))
        XCTAssertTrue(syncScript.contains("requestAnimationFrame"))

        let airPlayScript = EnhancementScript.showAirPlayPickerScript
        XCTAssertTrue(airPlayScript.contains("webkitShowPlaybackTargetPicker"))
        XCTAssertTrue(airPlayScript.contains("mse_unsupported"))

        let speedScript = EnhancementScript.setPlaybackRateScript(rate: 1.5)
        XCTAssertTrue(speedScript.contains("v.playbackRate = 1.5"))

        for script in [boot, seekScript, liveScript, syncScript, airPlayScript, speedScript] {
            XCTAssertFalse(script.contains(":has("))
            XCTAssertFalse(script.contains("MutationObserver"))
            XCTAssertFalse(script.contains("AudioContext"))
            XCTAssertFalse(script.contains("ytInitialPlayerResponse"))
        }
    }

    func testCommandPaletteEngineV120EnabledServicesAndMultiviewAddScreen() {
        let enabled = [
            StreamingServiceCatalog.service(id: "youtube")!,
            StreamingServiceCatalog.service(id: "espn")!,
            StreamingServiceCatalog.service(id: "netflix")!,
            StreamingServiceCatalog.service(id: "crunchyroll")!
        ]

        let items = CommandPaletteEngine.rank(
            query: "espn",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [],
            watchedChannels: [],
            enabledServices: enabled,
            isMultiviewActive: true,
            canAddMultiviewTile: true,
            actions: [],
            suggestions: []
        )

        XCTAssertTrue(items.contains { $0.payload == .addStreamingServiceToMultiview("espn") && $0.title == "Add ESPN / ESPN+ Screen" })
        XCTAssertTrue(items.contains { $0.payload == .openStreamingService("espn") && $0.title == "Open ESPN / ESPN+" })

        let crunchyItems = CommandPaletteEngine.rank(
            query: "crunchyroll",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [],
            watchedChannels: [],
            enabledServices: enabled,
            isMultiviewActive: true,
            canAddMultiviewTile: true,
            actions: [],
            suggestions: []
        )
        XCTAssertTrue(crunchyItems.contains { $0.payload == .addStreamingServiceToMultiview("crunchyroll") && $0.title == "Add Crunchyroll Screen" })
        XCTAssertTrue(crunchyItems.contains { $0.payload == .openStreamingService("crunchyroll") && $0.title == "Open Crunchyroll" })
    }

    func testWindowDisplayRouterTargetFrameAndNegativeOriginDisplays() {
        // Maximize onto secondary TV display with negative X origin (left of built-in screen)
        let tvVisible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let current = CGRect(x: 100, y: 100, width: 1280, height: 800)
        let tvFrame = WindowDisplayRouter.targetFrame(
            currentFrame: current,
            targetVisibleFrame: tvVisible,
            maximizeForTV: true
        )
        XCTAssertEqual(tvFrame, tvVisible)

        // Preserved-size move clamps cleanly inside smaller display bounds
        let smallVisible = CGRect(x: 1920, y: 25, width: 1024, height: 743)
        let clampedFrame = WindowDisplayRouter.targetFrame(
            currentFrame: current,
            targetVisibleFrame: smallVisible,
            maximizeForTV: false
        )
        XCTAssertEqual(clampedFrame.width, 1024)
        XCTAssertEqual(clampedFrame.height, 743)
        XCTAssertGreaterThanOrEqual(clampedFrame.minX, smallVisible.minX)
        XCTAssertLessThanOrEqual(clampedFrame.maxX, smallVisible.maxX)
        XCTAssertGreaterThanOrEqual(clampedFrame.minY, smallVisible.minY)
        XCTAssertLessThanOrEqual(clampedFrame.maxY, smallVisible.maxY)
    }

    func testCleanBoxRulesAll18ServicesAndIframeAllowlist() {
        XCTAssertEqual(StreamingServiceCatalog.all.count, 18)
        for service in StreamingServiceCatalog.all {
            XCTAssertNotNil(
                CleanBoxRules.profile(serviceID: service.id),
                "Expected CleanBoxServiceProfile for \(service.id)"
            )
        }

        let cases: [(String, CleanBoxRouteClassification)] = [
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", .watch),
            ("https://www.youtube.com/", .browse),
            ("https://tv.youtube.com/watch/abc123", .watch),
            ("https://tv.youtube.com/live", .browse),
            ("https://www.twitch.tv/shroud", .watch),
            ("https://www.twitch.tv/directory", .browse),
            ("https://www.twitch.tv/login", .auth),
            ("https://www.crunchyroll.com/watch/G12345/ep-1", .watch),
            ("https://www.crunchyroll.com/es-es/watch/G12345/ep-1", .watch),
            ("https://www.crunchyroll.com/discover", .browse),
            ("https://www.crunchyroll.com/es-es/login", .auth),
            ("https://www.amazon.com/gp/video/detail/B001", .overlaySDK),
            ("https://www.amazon.com/ap/signin", .auth),
            ("https://tv.apple.com/us/show/severance/umc.cmc.1", .overlaySDK),
            ("https://www.espn.com/watch/player/_/id/123", .watch),
            ("https://www.espn.com/", .browse),
            ("https://www.nfl.com/plus/games/123", .watch),
            ("https://www.nfl.com/news/", .browse),
            ("https://www.mlb.com/tv/g717234", .watch),
            ("https://www.mlb.com/scores", .browse),
            ("https://www.nba.com/watch/event/0022", .watch),
            ("https://www.nba.com/games", .browse),
            ("https://www.peacocktv.com/watch/playback/vod/123", .watch),
            ("https://www.peacocktv.com/", .browse),
            ("https://www.paramountplus.com/shows/halo/video/123/", .watch),
            ("https://www.paramountplus.com/home/", .browse),
            ("https://www.fubo.tv/p/watch/123", .watch),
            ("https://www.fubo.tv/welcome", .browse),
            ("https://watch.sling.com/1/channel/123", .watch),
            ("https://www.sling.com/", .browse),
            ("https://www.disneyplus.com/play/abc", .watch),
            ("https://www.disneyplus.com/home", .browse),
            ("https://www.hulu.com/watch/123", .watch),
            ("https://www.hulu.com/hub/home", .browse),
            ("https://play.max.com/video/watch/123", .watch),
            ("https://www.max.com/", .browse),
            ("https://www.netflix.com/watch/80057281", .watch),
            ("https://www.netflix.com/browse", .browse)
        ]

        for (raw, expected) in cases {
            let url = URL(string: raw)!
            XCTAssertEqual(CleanBoxRules.classifyRoute(url), expected, "Route mismatch for \(raw)")
        }

        let crWatch = URL(string: "https://www.crunchyroll.com/watch/G12345/ep-1")!
        let crDiscover = URL(string: "https://www.crunchyroll.com/discover")!
        let twitchWatch = URL(string: "https://www.twitch.tv/shroud")!

        XCTAssertTrue(CleanBoxRules.isAllowedPlayerIframeHost("static.crunchyroll.com", forMainFrameURL: crWatch))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost("static.crunchyroll.com", forMainFrameURL: crDiscover))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost("static.crunchyroll.com", forMainFrameURL: twitchWatch))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost("doubleclick.net", forMainFrameURL: crWatch))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost("sso.crunchyroll.com", forMainFrameURL: crWatch))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost(nil, forMainFrameURL: crWatch))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost("", forMainFrameURL: crWatch))
    }

    func testEnhancementScriptCleanBoxSubframeAndAuthTeardownInvariants() {
        let bootstrap = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())
        let subframe = EnhancementScript.subframeMediaBridgeScript()
        let teardown = EnhancementScript.teardownCompanionCleanBoxScript
        let sync = EnhancementScript.syncCompanionCleanBoxScript
        let noResizeApply = EnhancementScript.applyConfigScript(DistractionFreeConfig(), triggerResize: false)

        XCTAssertTrue(bootstrap.contains("ytmac-cleanbox-style"))
        XCTAssertTrue(bootstrap.contains("data-ytmac-cb"))
        XCTAssertTrue(bootstrap.contains("syncCompanionCleanBox"))
        XCTAssertTrue(bootstrap.contains("if (isWebCompanionHost() || !document.head || document.getElementById('ytmac-style')) return;"))
        XCTAssertTrue(bootstrap.contains("collectVideos(document, 0)"))
        XCTAssertTrue(subframe.contains("window === window.top"))
        XCTAssertTrue(subframe.contains("subframeMedia: true"))
        XCTAssertTrue(teardown.contains("data-ytmac-cb"))
        XCTAssertTrue(sync.contains("__ytmacSyncCleanBox"))

        XCTAssertFalse(noResizeApply.contains("dispatchEvent"))
        XCTAssertFalse(noResizeApply.contains("emitMediaState"))

        for snippet in [bootstrap, subframe, teardown, sync] {
            XCTAssertFalse(snippet.contains(":has("))
            XCTAssertFalse(snippet.contains("MutationObserver"))
            XCTAssertFalse(snippet.contains("AudioContext"))
            XCTAssertFalse(snippet.contains("ytInitialPlayerResponse"))
        }
    }

    func testCleanBoxRulesDisneyPlusPassthrough() {
        let profile = CleanBoxRules.profile(serviceID: "disneyplus")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.strategy, .companionPassthrough)
        XCTAssertEqual(profile?.hosts.contains("disneyplus.com"), true)
    }

    func testFloatingMultiviewGridGeometryAndPresets() {
        XCTAssertEqual(MiniPlayerGridSizePreset.compact.size, CGSize(width: 540, height: 304))
        XCTAssertEqual(MiniPlayerGridSizePreset.standard.size, CGSize(width: 680, height: 383))
        XCTAssertEqual(MiniPlayerGridSizePreset.large.size, CGSize(width: 880, height: 495))
        XCTAssertEqual(MiniPlayerGridSizePreset.extraLarge.size, CGSize(width: 1040, height: 585))
        XCTAssertEqual(MiniPlayerGridSizePreset.extraLarge.shortTitle, "XL")
        XCTAssertEqual(MiniPlayerGeometry.gridMinimumSize, CGSize(width: 440, height: 248))

        XCTAssertEqual(MiniPlayerGridSizePreset.stepLarger(from: CGSize(width: 540, height: 304)), .standard)
        XCTAssertEqual(MiniPlayerGridSizePreset.stepLarger(from: CGSize(width: 880, height: 495)), .extraLarge)
        XCTAssertEqual(MiniPlayerGridSizePreset.stepSmaller(from: CGSize(width: 1040, height: 585)), .large)
        XCTAssertEqual(MiniPlayerGridSizePreset.stepSmaller(from: CGSize(width: 540, height: 304)), .compact)

        XCTAssertEqual(MultiviewGridLayout.floatingMiniPlayerPadding, 6)
        XCTAssertEqual(MultiviewGridLayout.floatingMiniPlayerSpacing, 6)
        XCTAssertEqual(MultiviewGridLayout.floatingTileCornerRadius, 10)

        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let bottomRightCompact = CGRect(x: 880, y: 45, width: 540, height: 304)
        let grown = MiniPlayerGeometry.resizedGridFrame(
            from: bottomRightCompact,
            to: .extraLarge,
            in: visible,
            inset: 20
        )
        XCTAssertEqual(grown.size, CGSize(width: 1040, height: 585))
        XCTAssertEqual(grown.maxX, bottomRightCompact.maxX, accuracy: 1.0)
        XCTAssertEqual(grown.minY, bottomRightCompact.minY, accuracy: 1.0)
        XCTAssertGreaterThanOrEqual(grown.minX, visible.minX + 8)
        XCTAssertLessThanOrEqual(grown.maxY, visible.maxY - 8)

        // Free-aspect drag resize in Grid mode clamped to gridMinimumSize
        let freeGrid = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: bottomRightCompact,
            edge: .topLeft,
            delta: CGSize(width: -120, height: 40),
            maintainAspectRatio: false,
            minSize: MiniPlayerGeometry.gridMinimumSize,
            in: visible
        )
        XCTAssertEqual(freeGrid.maxX, bottomRightCompact.maxX, accuracy: 1.0)
        XCTAssertEqual(freeGrid.minY, bottomRightCompact.minY, accuracy: 1.0)
        XCTAssertEqual(freeGrid.width, 660, accuracy: 1.0)
        XCTAssertEqual(freeGrid.height, 344, accuracy: 1.0)
    }

    func testCleanBoxRulesCrunchyrollDualPathAndAllowlist() {
        let profile = CleanBoxRules.profile(serviceID: "crunchyroll")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.strategy, .companionIframe)
        XCTAssertTrue(profile?.playerSelectors.contains("#vilosRoot") == true)
        XCTAssertTrue(profile?.playerSelectors.contains("[data-testid=\"vilos-root\"]") == true)
        XCTAssertTrue(profile?.playerSelectors.contains("[data-testid=\"vilos-player\"]") == true)
        XCTAssertTrue(profile?.playerSelectors.contains("[data-testid=\"video-player\"]") == true)
        XCTAssertTrue(profile?.playerSelectors.contains(".erc-watch-episode-player") == true)
        XCTAssertTrue(profile?.iframeSelectors.contains("iframe[src*=\"crunchyrollsvc.com\"]") == true)
        XCTAssertTrue(profile?.iframeSelectors.contains("iframe[src*=\"vrv.co\"]") == true)

        let watch = URL(string: "https://www.crunchyroll.com/watch/GX9U34054/raiders")!
        let localeWatch = URL(string: "https://www.crunchyroll.com/es-es/watch/GX9U34054/raiders")!
        let series = URL(string: "https://www.crunchyroll.com/series/G123/gachiakuta")!
        let discover = URL(string: "https://www.crunchyroll.com/discover")!
        let ssoLogin = URL(string: "https://sso.crunchyroll.com/login")!
        let ptLogin = URL(string: "https://www.crunchyroll.com/pt-br/login")!

        XCTAssertEqual(CleanBoxRules.classifyRoute(watch), .watch)
        XCTAssertEqual(CleanBoxRules.classifyRoute(localeWatch), .watch)
        XCTAssertEqual(CleanBoxRules.classifyRoute(series), .browse)
        XCTAssertEqual(CleanBoxRules.classifyRoute(discover), .browse)
        XCTAssertEqual(CleanBoxRules.classifyRoute(ssoLogin), .auth)
        XCTAssertEqual(CleanBoxRules.classifyRoute(ptLogin), .auth)

        XCTAssertTrue(CleanBoxRules.isAllowedPlayerIframeHost("static.crunchyroll.com", forMainFrameURL: watch))
        XCTAssertTrue(CleanBoxRules.isAllowedPlayerIframeHost("cr-play-service.prd.crunchyrollsvc.com", forMainFrameURL: watch))
        XCTAssertTrue(CleanBoxRules.isAllowedPlayerIframeHost("v.vrv.co", forMainFrameURL: watch))
        XCTAssertTrue(CleanBoxRules.isAllowedPlayerIframeHost("www.crunchyroll.com", forMainFrameURL: watch))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost("doubleclick.net", forMainFrameURL: watch))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost("sso.crunchyroll.com", forMainFrameURL: watch))
        XCTAssertFalse(CleanBoxRules.isAllowedPlayerIframeHost("static.crunchyroll.com", forMainFrameURL: series))
    }

    func testCleanBoxScriptDualPathChainCSSNoClobberAndLazySubframe() {
        let bootstrap = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())
        let subframe = EnhancementScript.subframeMediaBridgeScript()
        let syncPlayer = EnhancementScript.syncPlayerSizeScript
        let notifyResize = EnhancementScript.notifyViewportResizeScript
        let syncSubframe = EnhancementScript.syncCompanionCleanBoxScript
        let clearSubframe = EnhancementScript.clearSubframeMediaActiveScript

        XCTAssertTrue(bootstrap.contains("resolveIframeCandidate"))
        XCTAssertTrue(bootstrap.contains("resolveInlineVideoCandidate"))
        XCTAssertTrue(bootstrap.contains("cand.iframe !== cand.root"))
        XCTAssertTrue(bootstrap.contains("setAttribute('data-ytmac-cb', 'chain')"))
        XCTAssertTrue(bootstrap.contains("hasHiddenAncestor"))
        XCTAssertTrue(bootstrap.contains("[data-ytmac-cb=\"chain\"]"))
        XCTAssertTrue(bootstrap.contains("min-width: 0 !important;"))
        XCTAssertTrue(bootstrap.contains("min-height: 0 !important;"))
        XCTAssertTrue(bootstrap.contains("aspect-ratio: auto !important;"))
        XCTAssertTrue(bootstrap.contains("iframe[data-ytmac-cb=\"player\"]"))
        XCTAssertTrue(bootstrap.contains("[650, 1500, 3000, 5500]"))
        XCTAssertTrue(bootstrap.contains("hasMediaSource"))
        XCTAssertTrue(bootstrap.contains("srcObject"))

        // Lazy subframe size gate & passive resize wake-up
        XCTAssertFalse(subframe.contains("if (window.innerWidth < 100 || window.innerHeight < 56) return;"))
        XCTAssertTrue(subframe.contains("hasSubframeSize()"))
        XCTAssertTrue(subframe.contains("addEventListener('resize'"))
        XCTAssertTrue(subframe.contains("'loadeddata', 'canplay'"))

        XCTAssertTrue(syncPlayer.contains("__ytmacSyncCleanBox('resizeSync')"))
        XCTAssertTrue(notifyResize.contains("webkitFullscreenElement"))
        XCTAssertTrue(notifyResize.contains("__ytmacSyncCleanBox('resizeSync')"))
        XCTAssertTrue(syncSubframe.contains("__ytmacSubframeMediaActive = true"))
        XCTAssertTrue(clearSubframe.contains("__ytmacSubframeMediaActive = false"))

        for snippet in [bootstrap, subframe, syncPlayer, notifyResize, syncSubframe, clearSubframe] {
            XCTAssertFalse(snippet.contains(":has("))
            XCTAssertFalse(snippet.contains("MutationObserver"))
            XCTAssertFalse(snippet.contains("AudioContext"))
            XCTAssertFalse(snippet.contains("ytInitialPlayerResponse"))
        }
    }

    func testAll11ConnectedServicesAuthSignInCleanBoxAndSchemeBlocking() {
        // 1. Disney+: /identity/login, my.disney.com, locale watch routes, MyDisney isolation
        let disney = StreamingServiceCatalog.service(id: "disneyplus")!
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://www.disneyplus.com/identity/login")!))
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://www.disneyplus.com/identity/login/enter-password")!))
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://www.disneyplus.com/en-us/identity/login/enter-passcode")!))
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://my.disney.com/")!))
        XCTAssertTrue(StreamingServiceCatalog.isAuthOrOAuthPopupURL(URL(string: "https://www.disneyplus.com/identity/login")!))
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.disneyplus.com/identity/login")!, for: disney))
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.disneyplus.com/en-us")!, for: disney))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.disneyplus.com/en-us/home")!, for: disney))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.disneyplus.com/en-us/select-profile")!, for: disney))
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://www.disneyplus.com/identity/login")!), .auth)
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://www.disneyplus.com/en-us/play/abc123")!), .watch)
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://www.disneyplus.com/en-us/home")!), .browse)
        XCTAssertTrue(StreamingServiceCatalog.matchesDataRecord(displayName: "registerdisney.go.com", for: disney))

        // 2. HBO Max (`id: "max"`): hbomax.com rebrand, multi-step /auth/*, logged-out vs play.hbomax.com
        let maxSvc = StreamingServiceCatalog.service(id: "max")!
        XCTAssertEqual(maxSvc.name, "HBO Max")
        XCTAssertEqual(maxSvc.monogram, "HBO")
        XCTAssertEqual(maxSvc.homeURLString, "https://play.hbomax.com/")
        XCTAssertEqual(maxSvc.signInURLString, "https://www.hbomax.com/auth/login")
        XCTAssertTrue(maxSvc.authHostHints.contains("auth.hbomax.com"))
        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://play.hbomax.com/")!)?.id, "max")
        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://www.hbomax.com/auth/login")!)?.id, "max")
        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://play.max.com/")!)?.id, "max")
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://www.hbomax.com/auth/login")!))
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://www.hbomax.com/auth/password")!))
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://auth.hbomax.com/login")!))
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.hbomax.com/")!, for: maxSvc))
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.hbomax.com/plans")!, for: maxSvc))
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.hbomax.com/auth/login")!, for: maxSvc))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://play.hbomax.com/")!, for: maxSvc))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.hbomax.com/video/watch/abc")!, for: maxSvc))
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://www.hbomax.com/auth/login")!), .auth)
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://play.hbomax.com/video/watch/abc")!), .watch)
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://www.hbomax.com/en-us/video/watch/abc")!), .watch)
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://play.hbomax.com/")!), .browse)

        // 3. YouTube TV /welcome, Paramount+, Hulu, Netflix locale/country, Fubo, Corporate domain exclusions
        let yttv = StreamingServiceCatalog.service(id: "yttv")!
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://tv.youtube.com/welcome/?utm_servlet=prod&rd_rsn=lo")!, for: yttv))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://tv.youtube.com/")!, for: yttv))

        let paramount = StreamingServiceCatalog.service(id: "paramount")!
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.paramountplus.com/user-profile/whos-watching/")!, for: paramount))
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://www.paramountplus.com/live-tv")!), .watch)

        let hulu = StreamingServiceCatalog.service(id: "hulu")!
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.hulu.com/profiles")!, for: hulu))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.hulu.com/my-stuff")!, for: hulu))
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.hulu.com/welcome")!, for: hulu))

        let netflix = StreamingServiceCatalog.service(id: "netflix")!
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://www.netflix.com/us/login")!))
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.netflix.com/us/login")!, for: netflix))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.netflix.com/es-es/browse")!, for: netflix))
        XCTAssertEqual(CleanBoxRules.classifyRoute(URL(string: "https://www.netflix.com/es-es/watch/80057281")!), .watch)

        let fubo = StreamingServiceCatalog.service(id: "fubo")!
        XCTAssertFalse(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.fubo.tv/welcome")!, for: fubo))
        XCTAssertTrue(StreamingServiceCatalog.isLikelySignedInNavigation(url: URL(string: "https://www.fubo.tv/p/home")!, for: fubo))

        XCTAssertNil(StreamingServiceCatalog.service(matchingURL: URL(string: "https://www.icloud.com/")!))
        XCTAssertNil(StreamingServiceCatalog.service(matchingURL: URL(string: "https://www.apple.com/")!))
        XCTAssertNil(StreamingServiceCatalog.service(matchingURL: URL(string: "https://registerdisney.go.com/")!))
        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://tv.apple.com/")!)?.id, "appletv")
        XCTAssertEqual(StreamingServiceCatalog.service(matchingURL: URL(string: "https://www.espn.go.com/watch")!)?.id, "espn")
        XCTAssertTrue(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://oauth.xfinity.com/login")!))
        XCTAssertFalse(StreamingServiceCatalog.isTransientAuthURL(URL(string: "https://www.espn.com/tournament-challenge")!))

        // 4. App-handoff scheme blocking & non-link external protection
        for blocked in ["videos://play", "com.apple.tv://show", "disneyplus://home", "hbomax://feature", "nflx://watch", "peacocktv://watch", "paramountplus://home", "hulu://watch", "file:///etc/passwd"] {
            let decision = YouTubeURLRouter.routeNavigation(
                url: URL(string: blocked)!,
                currentPageURL: nil,
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: false,
                routingMode: .companion
            )
            XCTAssertEqual(decision, .block, "Expected .block for \(blocked)")
        }
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: URL(string: "mailto:support@glassgridyou.com")!,
                currentPageURL: nil,
                isUserLinkClick: false,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: false,
                routingMode: .companion
            ),
            .block
        )
        XCTAssertEqual(
            YouTubeURLRouter.routeNavigation(
                url: URL(string: "mailto:support@glassgridyou.com")!,
                currentPageURL: nil,
                isUserLinkClick: true,
                openExternalLinksInBrowser: true,
                redirectShortsToWatch: false,
                routingMode: .companion
            ),
            .openExternal(URL(string: "mailto:support@glassgridyou.com")!)
        )
    }

    func testStrictDRMStrategyAndFairPlayLayerMaskingMatrix() {
        let strictIDs = ["disneyplus", "netflix", "hulu", "max", "primevideo", "appletv", "crunchyroll"]
        for id in strictIDs {
            let service = StreamingServiceCatalog.service(id: id)
            XCTAssertNotNil(service, "Expected catalog entry for \(id)")
            XCTAssertEqual(service?.requiresStrictDRM, true, "Expected requiresStrictDRM == true for \(id)")
        }

        XCTAssertEqual(CleanBoxRules.profile(serviceID: "disneyplus")?.strategy, .companionPassthrough)
        XCTAssertEqual(CleanBoxRules.profile(serviceID: "netflix")?.strategy, .companionPassthrough)
        XCTAssertEqual(CleanBoxRules.profile(serviceID: "hulu")?.strategy, .companionPassthrough)
        XCTAssertEqual(CleanBoxRules.profile(serviceID: "primevideo")?.strategy, .companionOverlaySDK)
        XCTAssertEqual(CleanBoxRules.profile(serviceID: "appletv")?.strategy, .companionOverlaySDK)
        XCTAssertEqual(CleanBoxRules.profile(serviceID: "crunchyroll")?.strategy, .companionIframe)
        XCTAssertEqual(CleanBoxRules.profile(serviceID: "max")?.strategy, .companionSelector)

        let unmaskedURLs = [
            "https://www.disneyplus.com/play/abc123",
            "https://www.netflix.com/watch/80057281",
            "https://www.hulu.com/watch/123",
            "https://play.hbomax.com/video/watch/123",
            "https://www.amazon.com/gp/video/detail/B001",
            "https://www.primevideo.com/detail/B001",
            "https://tv.apple.com/us/show/severance/umc.cmc.1",
            "https://www.crunchyroll.com/watch/GX9U34054/raiders",
            "https://tv.youtube.com/watch/abc123"
        ]
        for raw in unmaskedURLs {
            XCTAssertFalse(
                MultiviewGridLayout.shouldMaskWebViewLayer(for: URL(string: raw)!),
                "Expected unmasked layer for FairPlay/strict-DRM host: \(raw)"
            )
        }

        let maskedURLs = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.twitch.tv/shroud"
        ]
        for raw in maskedURLs {
            XCTAssertTrue(
                MultiviewGridLayout.shouldMaskWebViewLayer(for: URL(string: raw)!),
                "Expected masked layer for \(raw)"
            )
        }
    }

    func testMultiviewAudioMixerAndMediaStatusVolumeAndSpeed() {
        XCTAssertEqual(MultiviewAudioMixer.clampVolume(-10), 0)
        XCTAssertEqual(MultiviewAudioMixer.clampVolume(140), 100)
        XCTAssertEqual(MultiviewAudioMixer.clampVolume(42), 42)

        XCTAssertEqual(
            MultiviewAudioMixer.levelForSliderChange(0),
            MultiviewAudioLevel(muted: true, volumePercent: 0)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.levelForSliderChange(35),
            MultiviewAudioLevel(muted: false, volumePercent: 35)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.levelForSliderChange(-5),
            MultiviewAudioLevel(muted: true, volumePercent: 0)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.levelForSliderChange(150),
            MultiviewAudioLevel(muted: false, volumePercent: 100)
        )

        let activeTab = UUID()
        let backgroundTab = UUID()
        let customTab = UUID()
        let closedTab = UUID()

        XCTAssertEqual(
            MultiviewAudioMixer.effectiveLevel(
                for: activeTab,
                activeAudioTabID: activeTab,
                duckBackground: false,
                customVolumes: [:]
            ),
            MultiviewAudioLevel(muted: false, volumePercent: 100)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.effectiveLevel(
                for: backgroundTab,
                activeAudioTabID: activeTab,
                duckBackground: true,
                customVolumes: [:]
            ),
            MultiviewAudioLevel(muted: false, volumePercent: 15)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.effectiveLevel(
                for: backgroundTab,
                activeAudioTabID: activeTab,
                duckBackground: false,
                customVolumes: [:]
            ),
            MultiviewAudioLevel(muted: true, volumePercent: 100)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.effectiveLevel(
                for: backgroundTab,
                activeAudioTabID: nil,
                duckBackground: false,
                customVolumes: [:],
                singleTabMode: true
            ),
            MultiviewAudioLevel(muted: false, volumePercent: 100)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.effectiveLevel(
                for: customTab,
                activeAudioTabID: activeTab,
                duckBackground: true,
                customVolumes: [customTab: 70]
            ),
            MultiviewAudioLevel(muted: false, volumePercent: 70)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.effectiveLevel(
                for: activeTab,
                activeAudioTabID: activeTab,
                duckBackground: false,
                customVolumes: [activeTab: 0]
            ),
            MultiviewAudioLevel(muted: true, volumePercent: 0)
        )
        XCTAssertEqual(
            MultiviewAudioMixer.effectiveLevel(
                for: customTab,
                activeAudioTabID: activeTab,
                duckBackground: false,
                customVolumes: [customTab: 135]
            ),
            MultiviewAudioLevel(muted: false, volumePercent: 100)
        )

        let sanitized = MultiviewAudioMixer.sanitizedCustomVolumes(
            [activeTab: 70, backgroundTab: 140, customTab: -10, closedTab: 50],
            keeping: [activeTab, backgroundTab, customTab]
        )
        XCTAssertEqual(sanitized, [activeTab: 70, backgroundTab: 100, customTab: 0])
        XCTAssertNil(sanitized[closedTab])

        XCTAssertEqual(MediaStatus.empty.volumePercent, 100)
        let defaultStatus = MediaStatus(
            hasVideo: true,
            isPlaying: true,
            title: "Sample",
            channel: "Channel",
            urlString: "https://www.youtube.com/watch?v=1",
            isMuted: false,
            isPiP: false,
            isTheater: false
        )
        XCTAssertEqual(defaultStatus.volumePercent, 100)

        let lowClampedStatus = MediaStatus(
            hasVideo: true,
            isPlaying: true,
            title: "Sample",
            channel: "Channel",
            urlString: "https://www.youtube.com/watch?v=1",
            isMuted: true,
            isPiP: false,
            isTheater: false,
            volumePercent: -25
        )
        XCTAssertEqual(lowClampedStatus.volumePercent, 0)

        let highClampedStatus = MediaStatus(
            hasVideo: true,
            isPlaying: true,
            title: "Sample",
            channel: "Channel",
            urlString: "https://www.youtube.com/watch?v=1",
            isMuted: false,
            isPiP: false,
            isTheater: false,
            volumePercent: 180
        )
        XCTAssertEqual(highClampedStatus.volumePercent, 100)

        XCTAssertEqual(MediaStatus.formatPlaybackRate(1.25), "1.25×")
        XCTAssertEqual(MediaStatus.formatPlaybackRate(1.75), "1.75×")
        XCTAssertEqual(MediaStatus.formatPlaybackRate(1.0), "1×")
        XCTAssertEqual(MediaStatus.formatPlaybackRate(1.5), "1.5×")
    }
}
