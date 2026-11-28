import CoreGraphics
import Foundation
import XCTest
@testable import YouTubeMacCore

// MARK: - Deterministic Offline URLProtocol Stub for RYD Tests

private final class RYDMockRouter: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (statusCode: Int, data: Data)

    static let shared = RYDMockRouter()

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    func register(id: String, handler: @escaping Handler) {
        lock.lock()
        handlers[id] = handler
        lock.unlock()
    }

    func unregister(id: String) {
        lock.lock()
        handlers.removeValue(forKey: id)
        lock.unlock()
    }

    func handler(for id: String) -> Handler? {
        lock.lock()
        let result = handlers[id]
        lock.unlock()
        return result
    }
}

private final class RYDMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let headerName = "X-RYD-Mock-ID"

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: headerName) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let mockID = request.value(forHTTPHeaderField: Self.headerName),
              let handler = RYDMockRouter.shared.handler(for: mockID),
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockRYDSession(id: String, handler: @escaping RYDMockRouter.Handler) -> URLSession {
    RYDMockRouter.shared.register(id: id, handler: handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RYDMockURLProtocol.self]
    config.httpAdditionalHeaders = [RYDMockURLProtocol.headerName: id]
    config.httpCookieAcceptPolicy = .never
    config.httpShouldSetCookies = false
    return URLSession(configuration: config)
}

final class V150FeaturesTests: XCTestCase {
    // MARK: - 1. A-B Loop Range

    func testABLoopRangeClampingSpanInvalidationCooldownAndFreeScrubBeforeA() throws {
        // Negative / non-finite / exceeding duration clamping
        let dirty = ABLoopRange(startSeconds: -5.0, endSeconds: 180.0, isEnabled: true)
        let clamped = dirty.clamped(duration: 120.0)
        XCTAssertEqual(clamped.startSeconds, 0.0)
        XCTAssertEqual(clamped.endSeconds, 120.0)
        XCTAssertTrue(clamped.isComplete)
        XCTAssertTrue(clamped.isEnabled)

        let nonFinite = ABLoopRange(startSeconds: .nan, endSeconds: .infinity, isEnabled: true).clamped(duration: 120.0)
        XCTAssertNil(nonFinite.startSeconds)
        XCTAssertNil(nonFinite.endSeconds)
        XCTAssertFalse(nonFinite.isComplete)
        XCTAssertFalse(nonFinite.isEnabled)

        // < 0.5s span invalidation (both <= 0.5s and clamped-to-duration collapse)
        let tooShort = ABLoopRange(startSeconds: 10.0, endSeconds: 10.5, isEnabled: true)
        XCTAssertFalse(tooShort.isComplete)
        let clampedShort = tooShort.clamped(duration: 100.0)
        XCTAssertEqual(clampedShort.startSeconds, 10.0)
        XCTAssertNil(clampedShort.endSeconds)
        XCTAssertFalse(clampedShort.isEnabled)

        let collapsedByDuration = ABLoopRange(startSeconds: 29.7, endSeconds: 40.0, isEnabled: true).clamped(duration: 30.0)
        XCTAssertEqual(collapsedByDuration.startSeconds, 29.7)
        XCTAssertNil(collapsedByDuration.endSeconds)
        XCTAssertFalse(collapsedByDuration.isEnabled)

        // Valid loop + >= 0.4s re-seek cooldown + free scrubbing before A
        let activeLoop = ABLoopRange(startSeconds: 15.0, endSeconds: 30.0, isEnabled: true)
        XCTAssertTrue(activeLoop.isComplete)

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Scrubbing before A returns nil (free scrubbing allowed)
        XCTAssertNil(activeLoop.shouldTriggerLoopJump(currentTime: 3.0, duration: 120.0, lastSeekAt: nil, now: t0))
        XCTAssertNil(activeLoop.shouldTriggerLoopJump(currentTime: 14.9, duration: 120.0, lastSeekAt: nil, now: t0))
        // Inside A...B before threshold (end - 0.12) returns nil
        XCTAssertNil(activeLoop.shouldTriggerLoopJump(currentTime: 29.8, duration: 120.0, lastSeekAt: nil, now: t0))

        // At threshold (end - 0.12 = 29.88) triggers jump back to A
        XCTAssertEqual(activeLoop.shouldTriggerLoopJump(currentTime: 29.9, duration: 120.0, lastSeekAt: nil, now: t0), 15.0)

        // Within < 0.4s cooldown returns nil
        XCTAssertNil(
            activeLoop.shouldTriggerLoopJump(
                currentTime: 30.0,
                duration: 120.0,
                lastSeekAt: t0,
                now: t0.addingTimeInterval(0.39)
            )
        )

        // Past >= 0.4s cooldown (accounting for Double epoch precision) triggers again
        XCTAssertEqual(
            activeLoop.shouldTriggerLoopJump(
                currentTime: 30.0,
                duration: 120.0,
                lastSeekAt: t0,
                now: t0.addingTimeInterval(0.41)
            ),
            15.0
        )

        // Backward-compatible Codable decoding defaults isEnabled to false
        let legacyData = Data(#"{"startSeconds":12.0,"endSeconds":24.0}"#.utf8)
        let decoded = try JSONDecoder().decode(ABLoopRange.self, from: legacyData)
        XCTAssertEqual(decoded.startSeconds, 12.0)
        XCTAssertEqual(decoded.endSeconds, 24.0)
        XCTAssertFalse(decoded.isEnabled)
    }

    // MARK: - 2. Video Aspect Mode & FairPlay DRM Layer Guard

    func testVideoAspectModeAndShouldMaskWebViewLayerRespectsStrictDRM() throws {
        let drmBlockedURLs = [
            "https://tv.youtube.com/watch/abc",
            "https://www.disneyplus.com/video/123",
            "https://www.netflix.com/watch/8000",
            "https://www.hulu.com/watch/123",
            "https://tv.apple.com/us/show/severance"
        ]
        for raw in drmBlockedURLs {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertFalse(VideoAspectMode.canApplyAspectFill(for: url), "Expected Aspect Fill blocked for \(raw)")
            XCTAssertFalse(MultiviewGridLayout.shouldMaskWebViewLayer(for: url), "Expected layer mask disabled for \(raw)")
        }

        let allowedURLs = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.twitch.tv/shroud"
        ]
        for raw in allowedURLs {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertTrue(VideoAspectMode.canApplyAspectFill(for: url), "Expected Aspect Fill allowed for \(raw)")
            XCTAssertTrue(MultiviewGridLayout.shouldMaskWebViewLayer(for: url), "Expected layer mask allowed for \(raw)")
        }

        XCTAssertEqual(VideoAspectMode.allCases, [.fit, .fill])
        XCTAssertFalse(VideoAspectMode.fit.title.isEmpty)
        XCTAssertFalse(VideoAspectMode.fill.systemImage.isEmpty)
    }

    // MARK: - 3. SponsorBlock Categories, Point Highlights & Normalized Ranges

    func testSponsorSegmentCategorySevenCasesPoiHighlightParsingAndNormalizedRange() {
        XCTAssertEqual(SponsorSegmentCategory.allCases.count, 7)
        XCTAssertTrue(SponsorSegmentCategory.allCases.contains(.musicOfftopic))
        XCTAssertTrue(SponsorSegmentCategory.allCases.contains(.poiHighlight))
        XCTAssertEqual(SponsorSegmentCategory.musicOfftopic.rawValue, "music_offtopic")
        XCTAssertEqual(SponsorSegmentCategory.poiHighlight.rawValue, "poi_highlight")

        XCTAssertTrue(SponsorSegmentCategory.poiHighlight.isPointHighlight)
        XCTAssertFalse(SponsorSegmentCategory.poiHighlight.isAutoSkipped)

        for category in SponsorSegmentCategory.allCases where category != .poiHighlight {
            XCTAssertFalse(category.isPointHighlight, "\(category.rawValue) must not be a point highlight")
            XCTAssertTrue(category.isAutoSkipped, "\(category.rawValue) should be auto-skipped")
        }

        let videoID = "dQw4w9WgXcQ"
        let payload = Data("""
        [
          {
            "videoID": "\(videoID)",
            "segments": [
              { "category": "poi_highlight", "segment": [42.5, 42.5] },
              { "category": "sponsor", "segment": [10.0, 10.4] },
              { "category": "sponsor", "segment": [20.0, 35.0] },
              { "category": "music_offtopic", "segment": [60.0, 75.0] }
            ]
          }
        ]
        """.utf8)

        let parsed = SponsorBlockClient.parseSegments(
            from: payload,
            videoID: videoID,
            allowedCategories: ["sponsor", "music_offtopic", "poi_highlight"]
        )
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0], SponsorSegment(start: 20.0, end: 35.0, category: "sponsor"))
        XCTAssertEqual(parsed[1], SponsorSegment(start: 42.5, end: 42.5, category: "poi_highlight"))
        XCTAssertEqual(parsed[2], SponsorSegment(start: 60.0, end: 75.0, category: "music_offtopic"))

        // normalizedRange(duration:)
        let sponsorRange = parsed[0].normalizedRange(duration: 100.0)
        XCTAssertNotNil(sponsorRange)
        XCTAssertEqual(sponsorRange?.lowerBound ?? -1, 0.20, accuracy: 0.0001)
        XCTAssertEqual(sponsorRange?.upperBound ?? -1, 0.35, accuracy: 0.0001)

        let poiRange = parsed[1].normalizedRange(duration: 100.0)
        XCTAssertNotNil(poiRange)
        XCTAssertEqual(poiRange?.lowerBound ?? -1, 0.425, accuracy: 0.0001)
        XCTAssertEqual(poiRange?.upperBound ?? -1, 0.425, accuracy: 0.0001)

        XCTAssertNil(parsed[0].normalizedRange(duration: 0))
        XCTAssertNil(parsed[0].normalizedRange(duration: .nan))
        XCTAssertNil(parsed[0].normalizedRange(duration: 90_000))
        XCTAssertNil(SponsorSegment(start: 150.0, end: 160.0, category: "sponsor").normalizedRange(duration: 100.0))
    }

    // MARK: - 4. EnhancementScript Static Checks & Zero Forbidden Tokens

    func testEnhancementScriptStepFrameSponsorHighlightExclusionAndZeroForbiddenTokens() {
        let forwardStep = EnhancementScript.stepVideoFrameScript(forward: true, fps: 60.0)
        let backwardStep = EnhancementScript.stepVideoFrameScript(forward: false, fps: 30.0)

        for script in [forwardStep, backwardStep] {
            XCTAssertTrue(script.contains("tv.youtube.com"))
            XCTAssertTrue(script.contains("v.mediaKeys"))
            XCTAssertTrue(script.contains("v.webkitKeys"))
            XCTAssertTrue(script.contains("Number.isFinite(v.duration)"))
        }
        XCTAssertTrue(backwardStep.contains("-"))

        let bootstrap = EnhancementScript.bootstrapScript(config: DistractionFreeConfig(aspectFill: true))
        XCTAssertTrue(bootstrap.contains("poi_highlight"))
        XCTAssertTrue(bootstrap.contains("ytmacAspectFill"))

        let forbiddenTokens = [":has(", "MutationObserver", "AudioContext", "ytInitialPlayerResponse"]
        for token in forbiddenTokens {
            XCTAssertFalse(bootstrap.contains(token), "bootstrapScript must not contain \(token)")
            XCTAssertFalse(forwardStep.contains(token), "stepVideoFrameScript(forward) must not contain \(token)")
            XCTAssertFalse(backwardStep.contains(token), "stepVideoFrameScript(backward) must not contain \(token)")
        }
    }

    // MARK: - 5. ReturnYouTubeDislikeClient

    func testReturnYouTubeDislikeQueryParsingCooldownLRUAndAttribution() async throws {
        XCTAssertEqual(ReturnYouTubeDislikeClient.attributionURL.absoluteString, "https://returnyoutubedislike.com")
        XCTAssertEqual(ReturnYouTubeDislikeClient.cooldownSeconds, 60.0)

        let validURL = try XCTUnwrap(ReturnYouTubeDislikeClient.queryURL(for: "dQw4w9WgXcQ"))
        XCTAssertEqual(validURL.absoluteString, "https://returnyoutubedislikeapi.com/votes?videoId=dQw4w9WgXcQ")

        for badID in ["", "abc", "bad/id", "has space12", String(repeating: "x", count: 33)] {
            XCTAssertNil(ReturnYouTubeDislikeClient.queryURL(for: badID), "Expected nil URL for invalid ID \(badID)")
        }

        // Valid payload + rating clamping to 0...5
        let clampedHighData = Data("""
        { "id": "dQw4w9WgXcQ", "likes": 1500, "dislikes": 250, "rating": 9.5, "viewCount": 100000, "deleted": false }
        """.utf8)
        let parsedHigh = try XCTUnwrap(ReturnYouTubeDislikeClient.parseStats(from: clampedHighData, videoID: "dQw4w9WgXcQ"))
        XCTAssertEqual(parsedHigh.likes, 1500)
        XCTAssertEqual(parsedHigh.dislikes, 250)
        XCTAssertEqual(parsedHigh.rating, 5.0, accuracy: 0.0001)
        XCTAssertEqual(parsedHigh.viewCount, 100_000)

        let clampedLowData = Data("""
        { "id": "dQw4w9WgXcQ", "likes": 10, "dislikes": 0, "rating": -2.5, "viewCount": -50 }
        """.utf8)
        let parsedLow = try XCTUnwrap(ReturnYouTubeDislikeClient.parseStats(from: clampedLowData, videoID: "dQw4w9WgXcQ"))
        XCTAssertEqual(parsedLow.rating, 0.0, accuracy: 0.0001)
        XCTAssertNil(parsedLow.viewCount)

        // Reject negative likes/dislikes & mismatched IDs
        let negativeLikes = Data(#"{"id":"dQw4w9WgXcQ","likes":-1,"dislikes":5,"rating":4.0}"#.utf8)
        XCTAssertNil(ReturnYouTubeDislikeClient.parseStats(from: negativeLikes, videoID: "dQw4w9WgXcQ"))
        let negativeDislikes = Data(#"{"id":"dQw4w9WgXcQ","likes":5,"dislikes":-2,"rating":4.0}"#.utf8)
        XCTAssertNil(ReturnYouTubeDislikeClient.parseStats(from: negativeDislikes, videoID: "dQw4w9WgXcQ"))
        let mismatchedID = Data(#"{"id":"otherVideoID","likes":5,"dislikes":2,"rating":4.0}"#.utf8)
        XCTAssertNil(ReturnYouTubeDislikeClient.parseStats(from: mismatchedID, videoID: "dQw4w9WgXcQ"))

        // 429 cooldown activation (true inside 60s, false after 61s)
        let cooldownID = "ryd-429-\(UUID().uuidString)"
        defer { RYDMockRouter.shared.unregister(id: cooldownID) }
        let cooldownSession = makeMockRYDSession(id: cooldownID) { _ in
            (429, Data())
        }
        let cooldownClient = ReturnYouTubeDislikeClient(session: cooldownSession)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let coolingAtT0 = await cooldownClient.isCoolingDown(at: t0)
        XCTAssertFalse(coolingAtT0)
        let rateLimitedResult = await cooldownClient.fetchStats(for: "dQw4w9WgXcQ", now: t0)
        XCTAssertNil(rateLimitedResult)
        let coolingAt30 = await cooldownClient.isCoolingDown(at: t0.addingTimeInterval(30))
        XCTAssertTrue(coolingAt30)
        let coolingAt61 = await cooldownClient.isCoolingDown(at: t0.addingTimeInterval(61))
        XCTAssertFalse(coolingAt61)

        // 120-entry LRU cache & clearCache()
        let lruID = "ryd-lru-\(UUID().uuidString)"
        defer { RYDMockRouter.shared.unregister(id: lruID) }
        final class CounterBox: @unchecked Sendable {
            private let lock = NSLock()
            var count = 0
            func increment() {
                lock.lock()
                count += 1
                lock.unlock()
            }
            func value() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return count
            }
        }
        let counter = CounterBox()
        let lruSession = makeMockRYDSession(id: lruID) { request in
            counter.increment()
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let vid = comps?.queryItems?.first(where: { $0.name == "videoId" })?.value ?? ""
            let body = Data("""
            { "id": "\(vid)", "likes": 100, "dislikes": 10, "rating": 4.5 }
            """.utf8)
            return (200, body)
        }
        let lruClient = ReturnYouTubeDislikeClient(session: lruSession)
        let id0 = "vid_000000"
        let id1 = "vid_000001"
        _ = await lruClient.fetchStats(for: id0, now: t0)
        _ = await lruClient.fetchStats(for: id1, now: t0)
        // Touch id0 so id1 becomes LRU
        _ = await lruClient.fetchStats(for: id0, now: t0)
        XCTAssertEqual(counter.value(), 2)

        // Fill remaining 118 entries + 1 extra (total 121 distinct keys) -> evicts id1, keeps id0
        for idx in 2...120 {
            let vid = String(format: "vid_%06d", idx)
            _ = await lruClient.fetchStats(for: vid, now: t0)
        }
        let callsBeforeCheck = counter.value()
        XCTAssertEqual(callsBeforeCheck, 121)

        // id0 should still be cached (no network increment)
        _ = await lruClient.fetchStats(for: id0, now: t0)
        XCTAssertEqual(counter.value(), callsBeforeCheck)

        // id1 was evicted so fetching it hits network again
        _ = await lruClient.fetchStats(for: id1, now: t0)
        XCTAssertEqual(counter.value(), callsBeforeCheck + 1)

        // clearCache forces subsequent fetch to hit network
        await lruClient.clearCache()
        _ = await lruClient.fetchStats(for: id0, now: t0)
        XCTAssertEqual(counter.value(), callsBeforeCheck + 2)
    }

    // MARK: - 6. VideoNoteEntry & TranscriptMarkdownExporter

    func testVideoNoteEntryAndTranscriptMarkdownExporterFormattingAndCaps() throws {
        let dirtyNote = VideoNoteEntry(
            videoID: " dQw4w9WgXcQ ",
            title: "Study\u{0007} \u{202E}Title",
            markdown: String(repeating: "A", count: VideoNoteEntry.maxMarkdownLength + 200)
        )
        XCTAssertEqual(dirtyNote.id, "dQw4w9WgXcQ")
        XCTAssertEqual(dirtyNote.title, "Study Title")
        XCTAssertEqual(dirtyNote.markdown.count, VideoNoteEntry.maxMarkdownLength)

        let transcript = YouTubeTranscript.fromRawSegments(
            [
                (startSeconds: 0, durationSeconds: 5, text: "Hello\u{0007} \u{202E}world"),
                (startSeconds: 65, durationSeconds: 4, text: "Second cue")
            ],
            videoID: "dQw4w9WgXcQ",
            title: "Test Video"
        )
        let bookmarks = [
            VideoBookmark(
                videoID: "dQw4w9WgXcQ",
                urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                title: "Key Moment",
                note: "Review this derivation",
                timestampSeconds: 75
            )
        ]
        let chapters = [
            VideoChapter(title: "Intro", startSeconds: 0),
            VideoChapter(title: "Core Idea", startSeconds: 60)
        ]

        let exported = TranscriptMarkdownExporter.exportMarkdown(
            title: "My \"Quoted\" Video\nLine2",
            videoID: "dQw4w9WgXcQ",
            urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            transcript: transcript,
            bookmarks: bookmarks,
            chapters: chapters,
            noteMarkdown: "Personal takeaway",
            includeTimestamps: true,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(exported.hasPrefix("---\n"))
        XCTAssertTrue(exported.contains("title: \"My \\\"Quoted\\\" Video Line2\""))
        XCTAssertTrue(exported.contains("video_id: \"dQw4w9WgXcQ\""))
        XCTAssertTrue(exported.contains("content_trust: \"untrusted_web_page\""))
        XCTAssertTrue(exported.contains("## Notes\n\nPersonal takeaway"))
        XCTAssertTrue(exported.contains("> [!NOTE] [1:15](https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=75s) — Key Moment"))
        XCTAssertTrue(exported.contains("> Review this derivation"))
        XCTAssertTrue(exported.contains("## Chapters"))
        XCTAssertTrue(exported.contains("- [1:00](https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=60s) Core Idea"))
        XCTAssertTrue(exported.contains("## Transcript"))
        XCTAssertTrue(exported.contains("Hello world"))
        XCTAssertFalse(exported.contains("\u{202E}"))
        XCTAssertFalse(exported.contains("\u{0007}"))

        // 128 KB byte cap enforced on massive exports
        let hugeCues = (0..<1_000).map { idx in
            TranscriptCue(
                id: idx,
                startSeconds: Double(idx * 5),
                durationSeconds: 4,
                text: String(repeating: "B", count: 380)
            )
        }
        let hugeTranscript = YouTubeTranscript(videoID: "dQw4w9WgXcQ", title: "Huge", cues: hugeCues)
        let cappedExport = TranscriptMarkdownExporter.exportMarkdown(
            title: "Huge",
            videoID: "dQw4w9WgXcQ",
            urlString: nil,
            transcript: hugeTranscript
        )
        XCTAssertLessThanOrEqual(cappedExport.utf8.count, TranscriptMarkdownExporter.maxExportBytes)

        // formatAIStudyPacket includes [untrusted_web_content] marker
        let packet = TranscriptMarkdownExporter.formatAIStudyPacket(
            title: "Study",
            videoID: "dQw4w9WgXcQ",
            urlString: nil,
            transcript: transcript,
            bookmarks: bookmarks,
            chapters: chapters
        )
        XCTAssertTrue(packet.contains("[untrusted_web_content]"))
        XCTAssertTrue(packet.contains("[untrusted_web_page]"))
        XCTAssertTrue(packet.contains("[/untrusted_web_page]"))
        XCTAssertLessThanOrEqual(packet.utf8.count, TranscriptMarkdownExporter.maxExportBytes)
    }

    // MARK: - 7. Watch Queue & Channel Inbox Filtering

    func testWatchQueuePolicyAndChannelInboxFilterHelper() throws {
        // Unsafe URLs rejected
        XCTAssertNil(WatchQueueItem(urlString: "javascript:alert(1)", title: "Bad"))
        XCTAssertNil(WatchQueueItem(urlString: "http://127.0.0.1:41773/mcp", title: "Local"))
        XCTAssertNil(WatchQueueItem(urlString: "http://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "HTTP"))
        XCTAssertNil(WatchQueueItem(urlString: "file:///etc/passwd", title: "File"))

        let first = try XCTUnwrap(
            WatchQueueItem(
                urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                title: "First Video"
            )
        )
        XCTAssertEqual(first.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(first.deduplicationKey, "vid:dQw4w9WgXcQ")

        let second = try XCTUnwrap(
            WatchQueueItem(
                urlString: "https://www.youtube.com/watch?v=M7lc1UVf-VE",
                title: "Second Video"
            )
        )

        var queue = WatchQueuePolicy.enqueue(first, into: [])
        queue = WatchQueuePolicy.enqueue(second, into: queue)
        XCTAssertEqual(queue.map(\.videoID), ["dQw4w9WgXcQ", "M7lc1UVf-VE"])

        // Deduplicates same videoID and moves to front when playNext = true
        let firstPlayNext = try XCTUnwrap(
            WatchQueueItem(
                urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s",
                title: "First Again"
            )
        )
        queue = WatchQueuePolicy.enqueue(firstPlayNext, into: queue, playNext: true)
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.map(\.videoID), ["dQw4w9WgXcQ", "M7lc1UVf-VE"])

        // 100-item cap
        var bigQueue: [WatchQueueItem] = []
        for idx in 0..<115 {
            let vid = String(format: "qvid_%05d", idx)
            let item = try XCTUnwrap(
                WatchQueueItem(
                    urlString: "https://www.youtube.com/watch?v=\(vid)",
                    title: "Video \(idx)"
                )
            )
            bigQueue = WatchQueuePolicy.enqueue(item, into: bigQueue)
        }
        XCTAssertEqual(bigQueue.count, WatchQueuePolicy.maxItems)
        XCTAssertEqual(WatchQueuePolicy.maxItems, 100)

        // shouldAutoAdvance policy
        XCTAssertFalse(
            WatchQueuePolicy.shouldAutoAdvance(
                isQueueNonEmpty: true,
                sleepTimerOption: .endOfVideo,
                isMultiviewActive: false
            )
        )
        XCTAssertFalse(
            WatchQueuePolicy.shouldAutoAdvance(
                isQueueNonEmpty: true,
                sleepTimerOption: nil,
                isMultiviewActive: true
            )
        )
        XCTAssertFalse(
            WatchQueuePolicy.shouldAutoAdvance(
                isQueueNonEmpty: false,
                sleepTimerOption: nil,
                isMultiviewActive: false
            )
        )
        XCTAssertTrue(
            WatchQueuePolicy.shouldAutoAdvance(
                isQueueNonEmpty: true,
                sleepTimerOption: .minutes30,
                isMultiviewActive: false
            )
        )

        // ChannelInboxFilterHelper
        let folderA = PinnedFolder(name: "Tech")
        let cid1 = "UC1111111111111111111111"
        let cid2 = "UC2222222222222222222222"
        let cid3 = "UC3333333333333333333333"

        let pins = [
            PinnedItem(title: "Chan 1", urlString: "https://www.youtube.com/channel/\(cid1)", folderID: folderA.id),
            PinnedItem(title: "Chan 2", urlString: "https://www.youtube.com/channel/\(cid2)", folderID: nil),
            PinnedItem(title: "Chan 1 Dup", urlString: "https://www.youtube.com/channel/\(cid1)", folderID: folderA.id)
        ]
        let watched = [
            WatchedChannelStat(name: "Chan 3", channelURLString: "https://www.youtube.com/channel/\(cid3)"),
            WatchedChannelStat(name: "Chan 1", channelURLString: "https://www.youtube.com/channel/\(cid1)")
        ]

        XCTAssertEqual(
            ChannelInboxFilterHelper.channelIDs(for: .all, folders: [folderA], pins: pins, watchedChannels: watched),
            [cid1, cid2, cid3]
        )
        XCTAssertEqual(
            ChannelInboxFilterHelper.channelIDs(for: .folder(folderA.id), folders: [folderA], pins: pins, watchedChannels: watched),
            [cid1]
        )
        XCTAssertEqual(
            ChannelInboxFilterHelper.channelIDs(for: .ungrouped, folders: [folderA], pins: pins, watchedChannels: watched),
            [cid2, cid3]
        )

        let entries = [
            ChannelInboxEntry(videoID: "v1", title: "One", channelName: "C1", channelID: cid1),
            ChannelInboxEntry(videoID: "v2", title: "Two", channelName: "C2", channelID: cid2)
        ]
        XCTAssertEqual(
            ChannelInboxFilterHelper.filterEntries(entries, watchedVideoIDs: ["v1"], hideWatched: false).map(\.videoID),
            ["v1", "v2"]
        )
        XCTAssertEqual(
            ChannelInboxFilterHelper.filterEntries(entries, watchedVideoIDs: ["v1"], hideWatched: true).map(\.videoID),
            ["v2"]
        )
    }

    // MARK: - 8. NotchMediaHUDGeometry.expandedFrame

    func testNotchMediaHUDGeometryExpandedFrameNotchAndExternalBounds() {
        // 1. Notched MacBook Pro display
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 60, width: 1512, height: 890)
        let baseNotch = NotchMediaHUDGeometry.targetFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryTopRight: CGRect(x: 856, y: 950, width: 656, height: 32)
        )
        let expandedNotch = NotchMediaHUDGeometry.expandedFrame(
            from: baseNotch,
            in: screenFrame,
            visibleFrame: visibleFrame
        )
        XCTAssertTrue(expandedNotch.hasNotch)
        XCTAssertEqual(expandedNotch.notchWidth, baseNotch.notchWidth)
        XCTAssertEqual(expandedNotch.frame.maxY, baseNotch.frame.maxY)
        XCTAssertEqual(expandedNotch.frame.width, baseNotch.frame.width + 68)
        XCTAssertEqual(expandedNotch.frame.height, baseNotch.frame.height + 86)
        XCTAssertGreaterThanOrEqual(expandedNotch.frame.minX, screenFrame.minX + 8)
        XCTAssertLessThanOrEqual(expandedNotch.frame.maxX, screenFrame.maxX - 8)
        XCTAssertGreaterThanOrEqual(expandedNotch.frame.minY, visibleFrame.minY + 8)

        // 2. External non-notched display
        let extScreen = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let extVisible = CGRect(x: 1512, y: 70, width: 2560, height: 1345)
        let baseExt = NotchMediaHUDGeometry.targetFrame(
            screenFrame: extScreen,
            visibleFrame: extVisible,
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        )
        let expandedExt = NotchMediaHUDGeometry.expandedFrame(
            from: baseExt,
            in: extScreen,
            visibleFrame: extVisible
        )
        XCTAssertFalse(expandedExt.hasNotch)
        XCTAssertEqual(expandedExt.notchWidth, 0)
        XCTAssertEqual(expandedExt.frame.maxY, baseExt.frame.maxY)
        XCTAssertGreaterThanOrEqual(expandedExt.frame.minX, extVisible.minX + 8)
        XCTAssertLessThanOrEqual(expandedExt.frame.maxX, extVisible.maxX - 8)
        XCTAssertGreaterThanOrEqual(expandedExt.frame.minY, extVisible.minY + 8)
    }

    // MARK: - 9. MultiviewWatchAlongSync

    func testMultiviewWatchAlongSyncOffsetClampingTargetTimeAndRateAdjustments() {
        XCTAssertEqual(MultiviewWatchAlongSync.clampOffset(-500), -300)
        XCTAssertEqual(MultiviewWatchAlongSync.clampOffset(450), 300)
        XCTAssertEqual(MultiviewWatchAlongSync.clampOffset(.nan), 0)
        XCTAssertEqual(MultiviewSyncOffsetEntry(tabID: UUID(), offsetSeconds: 999).offsetSeconds, 300)

        // VOD clamping
        XCTAssertNil(
            MultiviewWatchAlongSync.computeTargetTime(
                masterTime: -5,
                tileOffsetSeconds: 10,
                tileDuration: 100,
                isLive: false
            )
        )
        XCTAssertEqual(
            MultiviewWatchAlongSync.computeTargetTime(
                masterTime: 90,
                tileOffsetSeconds: 25,
                tileDuration: 100,
                isLive: false
            ),
            100
        )
        XCTAssertEqual(
            MultiviewWatchAlongSync.computeTargetTime(
                masterTime: 10,
                tileOffsetSeconds: -25,
                tileDuration: 100,
                isLive: false
            ),
            0
        )

        // Live DVR clamping
        XCTAssertEqual(
            MultiviewWatchAlongSync.computeTargetTime(
                masterTime: 1000,
                tileOffsetSeconds: -40,
                tileDuration: nil,
                isLive: true,
                minSeekable: 970,
                maxSeekable: 1050
            ),
            970
        )
        XCTAssertEqual(
            MultiviewWatchAlongSync.computeTargetTime(
                masterTime: 1000,
                tileOffsetSeconds: 80,
                tileDuration: nil,
                isLive: true,
                minSeekable: 970,
                maxSeekable: 1050
            ),
            1050
        )

        // Offset-aware rate adjustments
        let masterID = UUID()
        let aheadID = UUID()
        let behindID = UUID()
        let syncedID = UUID()

        // Master at 100s (offset 0).
        // aheadID offset +10s -> expected 110s, actual 111.5s -> drift +1.5s -> 0.92x
        // behindID offset -5s -> expected 95s, actual 93.0s -> drift -2.0s -> 1.08x
        // syncedID offset +2s -> expected 102s, actual 102.05s -> drift +0.05s -> 1.0x
        let samples = [
            MultiviewSyncSample(tabID: masterID, currentTime: 100.0, duration: 500, isPlaying: true, isLive: false),
            MultiviewSyncSample(tabID: aheadID, currentTime: 111.5, duration: 500, isPlaying: true, isLive: false),
            MultiviewSyncSample(tabID: behindID, currentTime: 93.0, duration: 500, isPlaying: true, isLive: false),
            MultiviewSyncSample(tabID: syncedID, currentTime: 102.05, duration: 500, isPlaying: true, isLive: false)
        ]
        let offsets: [UUID: Double] = [
            masterID: 0,
            aheadID: 10,
            behindID: -5,
            syncedID: 2
        ]

        let adjustments = MultiviewWatchAlongSync.computeRateAdjustments(
            samples: samples,
            masterTabID: masterID,
            isAutoSyncEnabled: true,
            offsetsByTabID: offsets
        )
        XCTAssertEqual(adjustments.count, 3)

        let aheadAdj = adjustments.first(where: { $0.tabID == aheadID })
        XCTAssertEqual(aheadAdj?.targetRate, MultiviewSyncPlanner.slowCatchupRate)
        XCTAssertEqual(aheadAdj?.driftSeconds ?? 0, 1.5, accuracy: 0.0001)

        let behindAdj = adjustments.first(where: { $0.tabID == behindID })
        XCTAssertEqual(behindAdj?.targetRate, MultiviewSyncPlanner.fastCatchupRate)
        XCTAssertEqual(behindAdj?.driftSeconds ?? 0, -2.0, accuracy: 0.0001)

        let syncedAdj = adjustments.first(where: { $0.tabID == syncedID })
        XCTAssertEqual(syncedAdj?.targetRate, 1.0)
    }
}
