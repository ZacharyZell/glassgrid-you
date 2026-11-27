import CoreGraphics
import Foundation
import XCTest
@testable import YouTubeMacCore

final class V140FeaturesTests: XCTestCase {
    // MARK: - 1. SponsorBlock Multi-Category

    func testSponsorBlockMultiCategoryQueryURLParsingAndEmptyFallback() throws {
        let categories: Set<String> = ["sponsor", "selfpromo", "intro", "outro", "interaction"]
        let prefix = SponsorBlockClient.hashPrefix(for: "dQw4w9WgXcQ")
        XCTAssertEqual(prefix.count, 4)

        let url = try XCTUnwrap(SponsorBlockClient.queryURL(forPrefix: prefix, categories: categories))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "sponsor.ajay.app")
        XCTAssertEqual(url.path, "/api/skipSegments/\(prefix)")

        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let catValue = comps.queryItems?.first(where: { $0.name == "categories" })?.value
        let catData = try XCTUnwrap(catValue?.data(using: .utf8))
        let decodedCats = try JSONDecoder().decode([String].self, from: catData)
        XCTAssertEqual(decodedCats, ["interaction", "intro", "outro", "selfpromo", "sponsor"])

        // Empty categories fall back safely to ["sponsor"]
        let fallbackURL = try XCTUnwrap(SponsorBlockClient.queryURL(forPrefix: prefix, categories: []))
        let fallbackComps = try XCTUnwrap(URLComponents(url: fallbackURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(fallbackComps.queryItems?.first(where: { $0.name == "categories" })?.value, #"["sponsor"]"#)

        let payload = Data("""
        [
          {
            "videoID": "dQw4w9WgXcQ",
            "segments": [
              { "category": "outro", "segment": [190.0, 212.0] },
              { "category": "intro", "segment": [0.0, 11.5] },
              { "category": "selfpromo", "segment": [45.0, 58.0] },
              { "category": "interaction", "segment": [90.0, 96.5] },
              { "category": "sponsor", "segment": [120.0, 155.0] },
              { "category": "music_offtopic", "segment": [15.0, 30.0] },
              { "category": "sponsor", "segment": [12.0, 12.2] }
            ]
          }
        ]
        """.utf8)

        let parsedAll = SponsorBlockClient.parseSegments(
            from: payload,
            videoID: "dQw4w9WgXcQ",
            allowedCategories: categories
        )
        XCTAssertEqual(parsedAll, [
            SponsorSegment(start: 0.0, end: 11.5, category: "intro"),
            SponsorSegment(start: 45.0, end: 58.0, category: "selfpromo"),
            SponsorSegment(start: 90.0, end: 96.5, category: "interaction"),
            SponsorSegment(start: 120.0, end: 155.0, category: "sponsor"),
            SponsorSegment(start: 190.0, end: 212.0, category: "outro")
        ])
        XCTAssertEqual(parsedAll[0].categoryEnum, .intro)
        XCTAssertEqual(parsedAll[1].categoryDisplayName, "Self-Promotion")

        // Empty allowedCategories falls back safely to sponsor-only
        let parsedFallback = SponsorBlockClient.parseSegments(
            from: payload,
            videoID: "dQw4w9WgXcQ",
            allowedCategories: []
        )
        XCTAssertEqual(parsedFallback, [
            SponsorSegment(start: 120.0, end: 155.0, category: "sponsor")
        ])
    }

    // MARK: - 2. DeArrowClient

    func testDeArrowParseCleanTitleRankingSanitizationAndHashPrefixParity() {
        let videoID = "LXb3EKWsInQ"
        let prefix = SponsorBlockClient.hashPrefix(for: videoID)
        XCTAssertEqual(prefix.count, 4)
        XCTAssertEqual(prefix, SponsorBlockClient.hashPrefix(for: videoID))
        XCTAssertTrue(prefix.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) })

        // Ignores original: true, prefers locked: true even with lower votes, ranks votes otherwise, sanitizes control/bidi chars
        let lockedPayload = Data("""
        {
          "\(videoID)": {
            "titles": [
              { "title": "YOU WON'T BELIEVE THIS!!!", "original": true, "votes": 999, "locked": true },
              { "title": "High Vote Unlocked Title", "original": false, "votes": 42, "locked": false },
              { "title": "  Locked\\u0007 Clean\\u202E Title  ", "original": false, "votes": 1, "locked": true }
            ]
          }
        }
        """.utf8)
        XCTAssertEqual(
            DeArrowClient.parseCleanTitle(from: lockedPayload, videoID: videoID),
            "Locked Clean Title"
        )

        let votesPayload = Data("""
        {
          "\(videoID)": {
            "titles": [
              { "title": "Clickbait Original", "original": true, "votes": 500 },
              { "title": "Downvoted Spam", "original": false, "votes": -3, "locked": false },
              { "title": "Decent Summary", "original": false, "votes": 4 },
              { "title": "Best Community Title", "original": false, "votes": 19 }
            ]
          }
        }
        """.utf8)
        XCTAssertEqual(
            DeArrowClient.parseCleanTitle(from: votesPayload, videoID: videoID),
            "Best Community Title"
        )

        let onlyOriginalPayload = Data("""
        {
          "\(videoID)": {
            "titles": [
              { "title": "Original Only", "original": true, "votes": 10 },
              { "title": "Negative Only", "original": false, "votes": -1 }
            ]
          }
        }
        """.utf8)
        XCTAssertNil(DeArrowClient.parseCleanTitle(from: onlyOriginalPayload, videoID: videoID))
    }

    // MARK: - 3. ChannelInboxClient

    func testChannelInboxFeedURLChannelIDExtractionAndAtomFeedParsing() throws {
        let validID = "UC_x5XG1OV2P6uZZ5FSM9Ttw"
        let feedURL = try XCTUnwrap(ChannelInboxClient.feedURL(forChannelID: validID))
        XCTAssertEqual(feedURL.absoluteString, "https://www.youtube.com/feeds/videos.xml?channel_id=\(validID)")

        XCTAssertNil(ChannelInboxClient.feedURL(forChannelID: "abc"))
        XCTAssertNil(ChannelInboxClient.feedURL(forChannelID: "UCbad/id?x=1"))

        XCTAssertEqual(ChannelInboxClient.extractChannelID(from: validID), validID)
        XCTAssertEqual(
            ChannelInboxClient.extractChannelID(from: "https://www.youtube.com/channel/\(validID)/videos"),
            validID
        )
        XCTAssertNil(ChannelInboxClient.extractChannelID(from: "https://evil.example.com/channel/\(validID)"))
        XCTAssertNil(ChannelInboxClient.extractChannelID(from: "https://www.youtube.com/@GoogleDevelopers"))

        let atomXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns="http://www.w3.org/2005/Atom">
          <title>Feed Level Title Should Be Ignored</title>
          <author><name>Feed Level Author Should Be Ignored</name></author>
          <entry>
            <yt:videoId>vid001</yt:videoId>
            <yt:channelId>\(validID)</yt:channelId>
            <title>Swift 6\u{202E} Concurrency Deep Dive</title>
            <author>
              <name>Google\u{0000} Developers</name>
            </author>
            <published>2026-11-26T18:30:00+00:00</published>
          </entry>
          <entry>
            <yt:videoId>vid002</yt:videoId>
            <title>Second Upload</title>
            <author>
              <name>Google Developers</name>
            </author>
            <published>2026-11-25T10:00:00Z</published>
          </entry>
          <entry>
            <yt:videoId>vid003</yt:videoId>
            <title>Third Upload Beyond Limit</title>
            <author><name>Google Developers</name></author>
          </entry>
        </feed>
        """.data(using: .utf8)!

        let entries = ChannelInboxClient.parseAtomFeed(from: atomXML, channelID: validID, limit: 2)
        XCTAssertEqual(entries.count, 2)

        XCTAssertEqual(entries[0].videoID, "vid001")
        XCTAssertEqual(entries[0].title, "Swift 6 Concurrency Deep Dive")
        XCTAssertEqual(entries[0].channelName, "Google Developers")
        XCTAssertEqual(entries[0].channelID, validID)
        XCTAssertNotNil(entries[0].publishedAt)
        XCTAssertEqual(entries[0].watchURL?.absoluteString, "https://www.youtube.com/watch?v=vid001")
        XCTAssertEqual(entries[0].thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/vid001/mqdefault.jpg")

        XCTAssertEqual(entries[1].videoID, "vid002")
        XCTAssertEqual(entries[1].title, "Second Upload")
        XCTAssertEqual(entries[1].channelID, validID)
    }

    // MARK: - 4. YouTubeTranscript

    func testYouTubeTranscriptParsersBoundsSearchAndTrustTag() throws {
        let json3Data = Data(#"""
        {
          "events": [
            { "tStartMs": 1200, "dDurationMs": 2500, "segs": [{ "utf8": "Hello " }, { "utf8": "Swift\u202E" }] },
            { "tStartMs": 4000, "dDurationMs": 1800, "segs": [{ "utf8": "   " }] },
            { "tStartMs": 65000, "dDurationMs": 3000, "segs": [{ "utf8": "Liquid Glass windowing" }] }
          ]
        }
        """#.utf8)

        let jsonTranscript = try XCTUnwrap(
            YouTubeTranscript.parseJSON3(from: json3Data, videoID: "abc12345678", title: "WWDC\u{0007} Talk", languageCode: "en")
        )
        XCTAssertEqual(jsonTranscript.contentTrust, AgentSecurity.untrustedWebContentTag)
        XCTAssertEqual(jsonTranscript.source, "json3")
        XCTAssertEqual(jsonTranscript.title, "WWDC Talk")
        XCTAssertEqual(jsonTranscript.cues.count, 2)
        XCTAssertEqual(jsonTranscript.cues[0].text, "Hello Swift")
        XCTAssertEqual(jsonTranscript.cues[0].formattedTimestamp, "0:01")
        XCTAssertEqual(jsonTranscript.cues[1].formattedTimestamp, "1:05")
        XCTAssertEqual(jsonTranscript.matching(query: "liquid").map(\.id), [1])
        XCTAssertEqual(jsonTranscript.matching(query: "   ").count, 2)

        let xmlData = Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <transcript>
          <text start="2.4" dur="3.1">First &amp; foremost</text>
          <text start="10.0" dur="2.0">Second line\nwrapped</text>
        </transcript>
        """.utf8)
        let xmlTranscript = try XCTUnwrap(
            YouTubeTranscript.parseTimedTextXML(from: xmlData, videoID: "abc12345678", title: "XML Talk", languageCode: "en")
        )
        XCTAssertEqual(xmlTranscript.contentTrust, AgentSecurity.untrustedWebContentTag)
        XCTAssertEqual(xmlTranscript.source, "timedtext_xml")
        XCTAssertEqual(xmlTranscript.cues.map(\.text), ["First & foremost", "Second line wrapped"])

        // Cue count cap (<= 1000) & per-cue character cap (<= 400)
        let oversizedText = String(repeating: "x", count: 600)
        let manySegments = (0..<1200).map { idx in
            (startSeconds: Double(idx), durationSeconds: 1.0, text: idx == 0 ? oversizedText : "Cue \(idx)")
        }
        let cappedCountTranscript = YouTubeTranscript.fromRawSegments(manySegments, videoID: "v1")
        XCTAssertEqual(cappedCountTranscript.cues.count, YouTubeTranscript.maxCues)
        XCTAssertEqual(cappedCountTranscript.cues[0].text.count, YouTubeTranscript.maxCueTextLength)
        XCTAssertEqual(cappedCountTranscript.contentTrust, AgentSecurity.untrustedWebContentTag)

        // Total byte budget cap (<= 64 KB)
        let chunk300 = String(repeating: "b", count: 300)
        let byteHeavySegments = (0..<300).map { idx in
            (startSeconds: Double(idx), durationSeconds: 1.0, text: chunk300)
        }
        let byteCapped = YouTubeTranscript.fromRawSegments(byteHeavySegments, videoID: "v2")
        let totalCueBytes = byteCapped.cues.reduce(0) { $0 + $1.text.utf8.count }
        XCTAssertLessThanOrEqual(totalCueBytes, YouTubeTranscript.maxTotalBytes)
        XCTAssertLessThan(byteCapped.cues.count, 300)
        XCTAssertLessThanOrEqual(byteCapped.formattedPlainText().utf8.count, YouTubeTranscript.maxTotalBytes)
    }

    // MARK: - 5. VideoBookmark & ContentFilterConfig

    func testVideoBookmarkSerializationAndContentFilterMatching() throws {
        let bookmark = VideoBookmark(
            videoID: "dQw4w9WgXcQ",
            urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            title: "Demo Keynote",
            channel: "Apple",
            note: "Great GPU slide",
            timestampSeconds: 125.4
        )
        XCTAssertEqual(bookmark.formattedTimestamp, "2:05")
        XCTAssertEqual(bookmark.url?.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=125s")

        let data = try JSONEncoder().encode(bookmark)
        let decoded = try JSONDecoder().decode(VideoBookmark.self, from: data)
        XCTAssertEqual(decoded, bookmark)

        let zeroBookmark = VideoBookmark(
            urlString: "https://www.twitch.tv/shroud",
            title: "Live Stream",
            timestampSeconds: -10
        )
        XCTAssertEqual(zeroBookmark.timestampSeconds, 0)
        XCTAssertEqual(zeroBookmark.url?.absoluteString, "https://www.twitch.tv/shroud")

        // ContentFilterConfig: disabled vs enabled
        var filter = ContentFilterConfig(
            isEnabled: false,
            blockedChannels: ["  SpoilerChannel  "],
            blockedKeywords: ["  leaked ending ", ""]
        )
        XCTAssertEqual(filter.blockedChannels, ["SpoilerChannel"])
        XCTAssertEqual(filter.blockedKeywords, ["leaked ending"])
        XCTAssertEqual(filter.effectiveBlockedChannels, [])
        XCTAssertEqual(filter.effectiveBlockedKeywords, [])
        XCTAssertFalse(filter.matches(title: "Leaked Ending Breakdown", channel: "SpoilerChannel"))

        filter.isEnabled = true
        XCTAssertEqual(filter.effectiveBlockedChannels, ["SpoilerChannel"])
        XCTAssertEqual(filter.effectiveBlockedKeywords, ["leaked ending"])
        XCTAssertTrue(filter.matches(title: "Normal Title", channel: "Official SpoilerChannel Clips"))
        XCTAssertTrue(filter.matches(title: "Full LEAKED ENDING Reaction", channel: "Other"))
        XCTAssertFalse(filter.matches(title: "Clean Documentary", channel: "PBS"))

        let filterData = try JSONEncoder().encode(filter)
        let decodedFilter = try JSONDecoder().decode(ContentFilterConfig.self, from: filterData)
        XCTAssertEqual(decodedFilter, filter)
    }

    // MARK: - 6. NotchMediaHUDGeometry

    func testNotchMediaHUDGeometryNotchedAndNonNotchedFallback() {
        // Notched MacBook Pro 14"/16" screen in AppKit coordinates (y=0 bottom)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 60, width: 1512, height: 890)
        let leftWing = CGRect(x: 0, y: 950, width: 656, height: 32)
        let rightWing = CGRect(x: 856, y: 950, width: 656, height: 32)

        let notched = NotchMediaHUDGeometry.targetFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            safeAreaTop: 32,
            auxiliaryTopLeft: leftWing,
            auxiliaryTopRight: rightWing
        )
        XCTAssertTrue(notched.hasNotch)
        XCTAssertEqual(notched.notchWidth, 200)
        XCTAssertEqual(notched.frame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(notched.frame.width, 396) // 200 + 98 * 2
        XCTAssertEqual(notched.frame.height, 32)
        XCTAssertEqual(notched.frame.maxY, screenFrame.maxY)
        // Fits cleanly around the notch without pushing past either wing's outer edge
        XCTAssertGreaterThan(notched.frame.minX, leftWing.minX + 8)
        XCTAssertLessThan(notched.frame.maxX, rightWing.maxX - 8)
        XCTAssertLessThan(notched.frame.minX, leftWing.maxX)
        XCTAssertGreaterThan(notched.frame.maxX, rightWing.minX)

        // External / non-notched display fallback
        let extScreen = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let extVisible = CGRect(x: 1512, y: 70, width: 2560, height: 1345)
        let fallback = NotchMediaHUDGeometry.targetFrame(
            screenFrame: extScreen,
            visibleFrame: extVisible,
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        )
        XCTAssertFalse(fallback.hasNotch)
        XCTAssertEqual(fallback.notchWidth, 0)
        XCTAssertEqual(fallback.frame.width, NotchMediaHUDGeometry.fallbackWidth)
        XCTAssertEqual(fallback.frame.height, NotchMediaHUDGeometry.fallbackHeight)
        XCTAssertEqual(fallback.frame.midX, extVisible.midX, accuracy: 0.5)
        XCTAssertEqual(
            fallback.frame.maxY,
            extVisible.maxY - NotchMediaHUDGeometry.fallbackTopInset
        )

        // Degenerate screen safe fallback
        let empty = NotchMediaHUDGeometry.targetFrame(
            screenFrame: .zero,
            visibleFrame: .zero,
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        )
        XCTAssertEqual(empty, NotchMediaHUDPlacement(frame: .zero, hasNotch: false, notchWidth: 0))
    }

    // MARK: - 7. MultiviewSyncPlanner & MultiviewStallDetector

    func testMultiviewSyncPlannerSoftRatesDeadbandAndGuards() {
        let masterID = UUID()
        let aheadID = UUID()
        let behindID = UUID()
        let syncedID = UUID()
        let pausedID = UUID()
        let farVODID = UUID()
        let liveID = UUID()

        let samples = [
            MultiviewSyncSample(tabID: masterID, currentTime: 100.0, duration: 300, isPlaying: true, isLive: false),
            MultiviewSyncSample(tabID: aheadID, currentTime: 101.2, duration: 300, isPlaying: true, isLive: false),
            MultiviewSyncSample(tabID: behindID, currentTime: 98.9, duration: 300, isPlaying: true, isLive: false),
            MultiviewSyncSample(tabID: syncedID, currentTime: 100.1, duration: 300, isPlaying: true, isLive: false),
            MultiviewSyncSample(tabID: pausedID, currentTime: 102.0, duration: 300, isPlaying: false, isLive: false),
            MultiviewSyncSample(tabID: farVODID, currentTime: 130.0, duration: 300, isPlaying: true, isLive: false),
            MultiviewSyncSample(tabID: liveID, currentTime: 130.0, duration: 0, isPlaying: true, isLive: true)
        ]

        // Disabled returns empty
        XCTAssertEqual(
            MultiviewSyncPlanner.computeRateAdjustments(samples: samples, masterTabID: masterID, isAutoSyncEnabled: false),
            []
        )

        let adjustments = MultiviewSyncPlanner.computeRateAdjustments(
            samples: samples,
            masterTabID: masterID,
            isAutoSyncEnabled: true
        )
        let byID = Dictionary(uniqueKeysWithValues: adjustments.map { ($0.tabID, $0) })

        XCTAssertEqual(byID[aheadID]?.targetRate, MultiviewSyncPlanner.slowCatchupRate)
        XCTAssertEqual(byID[behindID]?.targetRate, MultiviewSyncPlanner.fastCatchupRate)
        XCTAssertEqual(byID[syncedID]?.targetRate, 1.0)
        XCTAssertNil(byID[pausedID])
        XCTAssertNil(byID[farVODID])
        XCTAssertEqual(byID[liveID]?.targetRate, MultiviewSyncPlanner.slowCatchupRate)

        // Deadband hysteresis keeps existing catch-up rate between 0.15s and 0.6s until inside 0.15s
        let hysteresisSamples = [
            MultiviewSyncSample(tabID: masterID, currentTime: 100.0, duration: 300, isPlaying: true),
            MultiviewSyncSample(tabID: aheadID, currentTime: 100.35, duration: 300, isPlaying: true)
        ]
        let kept = MultiviewSyncPlanner.computeRateAdjustments(
            samples: hysteresisSamples,
            masterTabID: masterID,
            isAutoSyncEnabled: true,
            currentRates: [aheadID: 0.92]
        )
        XCTAssertEqual(kept.first?.targetRate, 0.92)
    }

    func testMultiviewStallDetectorThresholdCooldownMaxRecoveriesAndReset() {
        var detector = MultiviewStallDetector(
            stallThresholdSeconds: 15.0,
            cooldownSeconds: 20.0,
            maxAutoRecoveries: 2
        )
        let tabA = UUID()
        let tabPaused = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let playingAt40 = MultiviewSyncSample(tabID: tabA, currentTime: 40.0, duration: 500, isPlaying: true, isLive: true)
        let pausedAt40 = MultiviewSyncSample(tabID: tabPaused, currentTime: 40.0, duration: 500, isPlaying: false, isLive: true)

        XCTAssertEqual(detector.evaluate(samples: [playingAt40, pausedAt40], at: t0), [])
        XCTAssertEqual(detector.evaluate(samples: [playingAt40, pausedAt40], at: t0.addingTimeInterval(15.0)), [])

        // > 15s triggers first recovery
        XCTAssertEqual(detector.evaluate(samples: [playingAt40, pausedAt40], at: t0.addingTimeInterval(15.5)), [tabA])

        // Cooldown (20s) prevents immediate re-trigger
        XCTAssertEqual(detector.evaluate(samples: [playingAt40], at: t0.addingTimeInterval(35.0)), [])

        // After cooldown (>= 20s since 15.5s -> 35.5s+), triggers second recovery
        XCTAssertEqual(detector.evaluate(samples: [playingAt40], at: t0.addingTimeInterval(36.0)), [tabA])

        // Reached maxAutoRecoveries (2): no 3rd trigger even after another cooldown
        XCTAssertEqual(detector.evaluate(samples: [playingAt40], at: t0.addingTimeInterval(60.0)), [])

        // Advancing time resets recovery counter; reset(tabA) / resetAll() also clear cleanly
        let advanced = MultiviewSyncSample(tabID: tabA, currentTime: 42.0, duration: 500, isPlaying: true, isLive: true)
        XCTAssertEqual(detector.evaluate(samples: [advanced], at: t0.addingTimeInterval(61.0)), [])
        XCTAssertEqual(detector.evaluate(samples: [advanced], at: t0.addingTimeInterval(77.0)), [tabA])

        detector.reset(tabA)
        XCTAssertEqual(detector.evaluate(samples: [advanced], at: t0.addingTimeInterval(78.0)), [])
        detector.resetAll()
        XCTAssertEqual(detector.evaluate(samples: [advanced], at: t0.addingTimeInterval(95.0)), [])
    }

    // MARK: - 8. MultiviewShareLinkCodec

    func testMultiviewShareLinkCodecRoundTripAndSecurityRejection() throws {
        let urls = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.twitch.tv/shroud",
            "https://tv.youtube.com/watch/abcDEF12345"
        ]
        let shareURL = try XCTUnwrap(MultiviewShareLinkCodec.encode(urlStrings: urls, layoutMode: .spotlight))
        XCTAssertTrue(MultiviewShareLinkCodec.isMultiviewShareURL(shareURL))
        XCTAssertEqual(shareURL.scheme, "glassgridyou")
        XCTAssertEqual(shareURL.host, "multiview")

        let decoded = try XCTUnwrap(MultiviewShareLinkCodec.decode(shareURL))
        XCTAssertEqual(decoded.layoutMode, .spotlight)
        XCTAssertEqual(decoded.urls.map(\.absoluteString), urls)

        // Reject invalid/non-HTTPS/SSRF/custom-app schemes
        let rejectedLinks = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ", // not glassgridyou://multiview
            "glassgridyou://multiview?layout=auto&url=https://www.youtube.com/watch?v=dQw4w9WgXcQ", // < 2 URLs
            "glassgridyou://multiview?url=http://www.youtube.com/watch?v=1&url=https://www.twitch.tv/shroud", // non-HTTPS
            "glassgridyou://multiview?url=https://127.0.0.1/admin&url=https://www.twitch.tv/shroud", // SSRF
            "glassgridyou://multiview?url=glassgridyou://action/pause&url=https://www.twitch.tv/shroud", // custom-app scheme
            "glassgridyou://multiview?url=youtubemac://action/play&url=https://www.twitch.tv/shroud", // legacy custom scheme
            "glassgridyou://multiview?url=javascript:alert(1)&url=https://www.twitch.tv/shroud",
            "glassgridyou://multiview?url=file:///etc/passwd&url=https://www.twitch.tv/shroud"
        ]
        for raw in rejectedLinks {
            let candidate = try XCTUnwrap(URL(string: raw))
            XCTAssertNil(MultiviewShareLinkCodec.decode(candidate), "Expected share link rejection for \(raw)")
        }

        // Encode also rejects fewer than 2 valid HTTPS streams
        XCTAssertNil(MultiviewShareLinkCodec.encode(urlStrings: ["http://www.youtube.com/watch?v=1", "glassgridyou://action/play"]))
    }

    // MARK: - 9. YouTubeURLRouter Shorthands & CompanionChatURLValidator

    func testURLRouterShorthandsSearchHelpersAndCompanionChatValidator() throws {
        XCTAssertEqual(YouTubeURLRouter.resolveShorthandURL("twitch:shroud")?.absoluteString, "https://www.twitch.tv/shroud")
        XCTAssertEqual(YouTubeURLRouter.resolveShorthandURL("twitch:")?.absoluteString, "https://www.twitch.tv/")
        XCTAssertNil(YouTubeURLRouter.resolveShorthandURL("twitch:bad channel!"))

        XCTAssertEqual(
            YouTubeURLRouter.resolveShorthandURL("yt:lofi")?.absoluteString,
            "https://www.youtube.com/results?search_query=lofi"
        )
        XCTAssertEqual(
            YouTubeURLRouter.resolveShorthandURL("yt:dQw4w9WgXcQ")?.absoluteString,
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            YouTubeURLRouter.resolveShorthandURL("yt:@mkbhd")?.absoluteString,
            "https://www.youtube.com/@mkbhd"
        )
        XCTAssertEqual(YouTubeURLRouter.resolveShorthandURL("yttv:")?.absoluteString, "https://tv.youtube.com/")
        XCTAssertEqual(
            YouTubeURLRouter.resolveShorthandURL("yttv:nba")?.absoluteString,
            "https://tv.youtube.com/search?q=nba"
        )
        XCTAssertEqual(
            YouTubeURLRouter.resolveShorthandURL("yttv:watch/abcDEF12345")?.absoluteString,
            "https://tv.youtube.com/watch/abcDEF12345"
        )

        XCTAssertEqual(
            YouTubeURLRouter.resolveOmniboxInput("twitch:shroud", redirectShortsToWatch: true)?.absoluteString,
            "https://www.twitch.tv/shroud"
        )
        XCTAssertEqual(
            YouTubeURLRouter.resolveCompanionURL("twitch:esl_csgo")?.absoluteString,
            "https://www.twitch.tv/esl_csgo"
        )
        XCTAssertEqual(
            YouTubeURLRouter.youtubeSearchURL(for: "4k hdr")?.absoluteString,
            "https://www.youtube.com/results?search_query=4k%20hdr"
        )
        XCTAssertEqual(
            YouTubeURLRouter.twitchSearchURL(for: "valorant")?.absoluteString,
            "https://www.twitch.tv/search?term=valorant"
        )
        XCTAssertEqual(
            YouTubeURLRouter.youtubeTVSearchURL(for: "redzone")?.absoluteString,
            "https://tv.youtube.com/search?q=redzone"
        )

        // CompanionChatURLValidator
        let twitchChat = try XCTUnwrap(CompanionChatURLValidator.twitchPopoutChatURL(channel: "shroud", darkMode: true))
        XCTAssertTrue(CompanionChatURLValidator.isAllowedChatURL(twitchChat))
        XCTAssertEqual(
            CompanionChatURLValidator.chatURL(forStreamURL: URL(string: "https://www.twitch.tv/shroud")!, darkMode: true),
            twitchChat
        )

        let ytChat = try XCTUnwrap(CompanionChatURLValidator.youtubeLiveChatURL(videoID: "dQw4w9WgXcQ", darkMode: true))
        XCTAssertTrue(CompanionChatURLValidator.isAllowedChatURL(ytChat))
        XCTAssertEqual(
            CompanionChatURLValidator.chatURL(forStreamURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!, darkMode: true),
            ytChat
        )

        let rejectedChatURLs = [
            "http://www.twitch.tv/popout/shroud/chat",
            "https://www.twitch.tv/shroud",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/live_chat",
            "https://evil.com/popout/shroud/chat",
            "glassgridyou://action/pause"
        ]
        for raw in rejectedChatURLs {
            let candidate = try XCTUnwrap(URL(string: raw))
            XCTAssertFalse(CompanionChatURLValidator.isAllowedChatURL(candidate), "Expected chat URL rejection for \(raw)")
        }
    }

    // MARK: - 10. GlobalHotKeyAction & HUDToast

    func testGlobalHotKeyActionUniquenessAndHUDToastEquatable() {
        let actions = GlobalHotKeyAction.allCases
        XCTAssertEqual(actions.count, 5)
        XCTAssertEqual(Set(actions.map(\.carbonHotKeyID)).count, actions.count)

        for action in actions {
            XCTAssertFalse(action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(action.shortcutDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThan(action.defaultCarbonModifiers, 0)
        }

        let id = UUID()
        let toastA = HUDToast(id: id, icon: "forward.fill", message: "Skipped Sponsor", actionTitle: "Undo")
        let toastB = HUDToast(id: id, icon: "forward.fill", message: "Skipped Sponsor", actionTitle: "Undo")
        let toastNoAction = HUDToast(id: id, icon: "forward.fill", message: "Skipped Sponsor")
        XCTAssertEqual(toastA, toastB)
        XCTAssertNotEqual(toastA, toastNoAction)
        XCTAssertNil(toastNoAction.actionTitle)
    }
}
