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

        // Clamping on tiny screen
        let tinyScreen = CGRect(x: 0, y: 0, width: 500, height: 320)
        let clamped = MiniPlayerGeometry.resizedFrame(from: CGRect(x: 20, y: 20, width: 360, height: 203), to: .large, in: tinyScreen)
        XCTAssertLessThanOrEqual(clamped.maxX, tinyScreen.maxX)
        XCTAssertLessThanOrEqual(clamped.maxY, tinyScreen.maxY)
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
}
