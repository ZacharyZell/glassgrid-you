import CoreGraphics
import Foundation
import XCTest
@testable import YouTubeMacCore

final class V141FeaturesTests: XCTestCase {
    // MARK: - 1. DeArrow Branding (Title + Thumbnail)

    func testDeArrowParseBrandingSelectionRankingValidationAndBackwardCompatibility() throws {
        let videoID = "dQw4w9WgXcQ"

        // Combined title + thumbnail selection:
        // - Ignores original: true even when locked or high-voted
        // - Ranks locked: true above higher unlocked votes
        // - Ignores negative votes when unlocked
        // - Ignores negative timestamps
        // - Formats tiny timestamps cleanly without scientific notation
        let combinedPayload = Data("""
        {
          "\(videoID)": {
            "titles": [
              { "title": "CLICKBAIT ORIGINAL!!!", "original": true, "votes": 999, "locked": true },
              { "title": "Downvoted Unlocked Title", "original": false, "votes": -5, "locked": false },
              { "title": "High Vote Unlocked Title", "original": false, "votes": 80, "locked": false },
              { "title": "  Locked\\u0007 Clean\\u202E Title  ", "original": false, "votes": 2, "locked": true }
            ],
            "thumbnails": [
              { "timestamp": 45.0, "original": true, "votes": 999, "locked": true },
              { "timestamp": -12.5, "original": false, "votes": 500, "locked": true },
              { "timestamp": 18.2, "original": false, "votes": -3, "locked": false },
              { "timestamp": 12.75, "original": false, "votes": 60, "locked": false },
              { "timestamp": 0.05, "original": false, "votes": 1, "locked": true }
            ]
          }
        }
        """.utf8)

        let branding = try XCTUnwrap(DeArrowClient.parseBranding(from: combinedPayload, videoID: videoID))
        XCTAssertEqual(branding.title, "Locked Clean Title")
        XCTAssertEqual(
            branding.thumbnailURL?.absoluteString,
            "https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=\(videoID)&time=0.05"
        )
        XCTAssertEqual(
            DeArrowClient.parseCleanTitle(from: combinedPayload, videoID: videoID),
            branding.title
        )

        // Verify tiny timestamp formatting never emits scientific notation (e.g., e-)
        let tinyTimestampPayload = Data("""
        {
          "\(videoID)": {
            "thumbnails": [
              { "timestamp": 0.00001, "original": false, "votes": 5 }
            ]
          }
        }
        """.utf8)
        let tinyBranding = try XCTUnwrap(DeArrowClient.parseBranding(from: tinyTimestampPayload, videoID: videoID))
        XCTAssertNil(tinyBranding.title)
        let tinyURL = try XCTUnwrap(tinyBranding.thumbnailURL)
        XCTAssertEqual(tinyURL.scheme, "https")
        XCTAssertEqual(tinyURL.host, "dearrow-thumb.ajay.app")
        XCTAssertEqual(tinyURL.path, "/api/v1/getThumbnail")
        XCTAssertFalse(tinyURL.absoluteString.lowercased().contains("e-"))
        let tinyComps = try XCTUnwrap(URLComponents(url: tinyURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(tinyComps.queryItems?.first(where: { $0.name == "videoID" })?.value, videoID)
        XCTAssertEqual(tinyComps.queryItems?.first(where: { $0.name == "time" })?.value, "0.00")
        XCTAssertNil(DeArrowClient.parseCleanTitle(from: tinyTimestampPayload, videoID: videoID))

        // Rejects invalid/negative/missing timestamps & negative/original titles
        let rejectedEntriesPayload = Data("""
        {
          "\(videoID)": {
            "titles": [
              { "title": "Original Title", "original": true, "votes": 50 },
              { "title": "Negative Vote Title", "original": false, "votes": -1 }
            ],
            "thumbnails": [
              { "timestamp": 5.0, "original": true, "votes": 50 },
              { "timestamp": -0.01, "original": false, "votes": 20 },
              { "timestamp": null, "original": false, "votes": 20 },
              { "timestamp": 9.5, "original": false, "votes": -2 }
            ]
          }
        }
        """.utf8)
        XCTAssertNil(DeArrowClient.parseBranding(from: rejectedEntriesPayload, videoID: videoID))

        // Rejects invalid video IDs
        let invalidIDs = ["", "short", "bad/id?x=1", "has space12", String(repeating: "a", count: 33)]
        for badID in invalidIDs {
            let payload = Data("""
            { "\(badID)": { "titles": [{ "title": "Valid", "votes": 1 }] } }
            """.utf8)
            XCTAssertNil(DeArrowClient.parseBranding(from: payload, videoID: badID), "Expected invalid videoID \(badID) to be rejected")
            XCTAssertNil(DeArrowClient.parseCleanTitle(from: payload, videoID: badID))
        }
    }

    // MARK: - 2. Customizable Global Hotkeys

    func testGlobalHotKeyBindingValidationFormattingAndDefaults() {
        // Default Play/Pause is ⌃⌥P (zero ⌘⌥P Always-on-Top collision)
        let playPause = GlobalHotKeyAction.playPause
        XCTAssertEqual(playPause.shortcutDisplay, "⌃⌥P")
        XCTAssertEqual(playPause.defaultKeyCode, 0x23)
        XCTAssertEqual(playPause.defaultCarbonModifiers, 0x1800)
        XCTAssertEqual(playPause.defaultBinding.displayString, "⌃⌥P")
        XCTAssertTrue(playPause.defaultBinding.isValid)

        let alwaysOnTopCollisionMask = GlobalHotKeyBinding.cmdKeyMask | GlobalHotKeyBinding.optionKeyMask
        for action in GlobalHotKeyAction.allCases {
            let isCmdOptP = action.defaultKeyCode == 0x23 && action.defaultCarbonModifiers == alwaysOnTopCollisionMask
            XCTAssertFalse(isCmdOptP, "\(action.rawValue) must not collide with ⌘⌥P Always-on-Top")
            XCTAssertTrue(action.defaultBinding.isValid)
        }

        // Multiview Audio 1-4 defaults (⌃⌥1..4)
        let audioActions: [(GlobalHotKeyAction, String, UInt32)] = [
            (.multiviewAudio1, "⌃⌥1", 0x12),
            (.multiviewAudio2, "⌃⌥2", 0x13),
            (.multiviewAudio3, "⌃⌥3", 0x14),
            (.multiviewAudio4, "⌃⌥4", 0x15)
        ]
        for (action, expectedDisplay, expectedKeyCode) in audioActions {
            XCTAssertEqual(action.shortcutDisplay, expectedDisplay)
            XCTAssertEqual(action.defaultKeyCode, expectedKeyCode)
            XCTAssertEqual(action.defaultCarbonModifiers, 0x1800)
            XCTAssertEqual(action.defaultBinding.displayString, expectedDisplay)
            XCTAssertTrue(action.defaultBinding.isValid)
        }

        // AppKit raw modifier flags -> Carbon modifier masks
        let controlFlag: UInt = 1 << 18
        let optionFlag: UInt = 1 << 19
        let shiftFlag: UInt = 1 << 17
        let commandFlag: UInt = 1 << 20
        let unrelatedFlag: UInt = (1 << 16) | (1 << 21)

        XCTAssertEqual(GlobalHotKeyBinding.carbonModifiers(fromAppKitFlags: controlFlag), GlobalHotKeyBinding.controlKeyMask)
        XCTAssertEqual(GlobalHotKeyBinding.carbonModifiers(fromAppKitFlags: optionFlag), GlobalHotKeyBinding.optionKeyMask)
        XCTAssertEqual(GlobalHotKeyBinding.carbonModifiers(fromAppKitFlags: shiftFlag), GlobalHotKeyBinding.shiftKeyMask)
        XCTAssertEqual(GlobalHotKeyBinding.carbonModifiers(fromAppKitFlags: commandFlag), GlobalHotKeyBinding.cmdKeyMask)
        XCTAssertEqual(
            GlobalHotKeyBinding.carbonModifiers(fromAppKitFlags: controlFlag | optionFlag | shiftFlag | commandFlag | unrelatedFlag),
            GlobalHotKeyBinding.supportedCarbonModifierMask
        )
        XCTAssertEqual(GlobalHotKeyBinding.carbonModifiers(fromAppKitFlags: unrelatedFlag), 0)

        // isValid rejects bare keys, Shift-only combos, unknown keyCodes, and unsupported modifier bits
        XCTAssertFalse(GlobalHotKeyBinding(keyCode: 0x28, carbonModifiers: 0x0000).isValid)
        XCTAssertFalse(GlobalHotKeyBinding(keyCode: 0x28, carbonModifiers: 0x0200).isValid)
        XCTAssertFalse(GlobalHotKeyBinding(keyCode: 0xFFFF, carbonModifiers: GlobalHotKeyBinding.cmdKeyMask).isValid)
        XCTAssertFalse(GlobalHotKeyBinding(keyCode: 0x28, carbonModifiers: GlobalHotKeyBinding.cmdKeyMask | 0x0400).isValid)

        // isValid accepts ⌃ / ⌥ / ⌘ combos (including with Shift)
        XCTAssertTrue(GlobalHotKeyBinding(keyCode: 0x28, carbonModifiers: GlobalHotKeyBinding.controlKeyMask).isValid)
        XCTAssertTrue(GlobalHotKeyBinding(keyCode: 0x28, carbonModifiers: GlobalHotKeyBinding.optionKeyMask).isValid)
        XCTAssertTrue(GlobalHotKeyBinding(keyCode: 0x28, carbonModifiers: GlobalHotKeyBinding.cmdKeyMask).isValid)
        XCTAssertTrue(GlobalHotKeyBinding(keyCode: 0x28, carbonModifiers: GlobalHotKeyBinding.cmdKeyMask | GlobalHotKeyBinding.shiftKeyMask).isValid)

        // displayString ordering (⌃⌥⇧⌘) and deterministic keyLabel(for:)
        let allModsK = GlobalHotKeyBinding(
            keyCode: 0x28,
            carbonModifiers: GlobalHotKeyBinding.supportedCarbonModifierMask
        )
        XCTAssertEqual(allModsK.displayString, "⌃⌥⇧⌘K")
        XCTAssertEqual(GlobalHotKeyBinding(keyCode: 0xFFFF, carbonModifiers: GlobalHotKeyBinding.cmdKeyMask).displayString, "⌘?")

        XCTAssertEqual(GlobalHotKeyBinding.keyLabel(for: 0x23), "P")
        XCTAssertEqual(GlobalHotKeyBinding.keyLabel(for: 0x12), "1")
        XCTAssertEqual(GlobalHotKeyBinding.keyLabel(for: 0x31), "Space")
        XCTAssertEqual(GlobalHotKeyBinding.keyLabel(for: 0x7A), "F1")
        XCTAssertEqual(GlobalHotKeyBinding.keyLabel(for: 0x6F), "F12")
        XCTAssertEqual(GlobalHotKeyBinding.keyLabel(for: 0x7E), "↑")
        XCTAssertNil(GlobalHotKeyBinding.keyLabel(for: 0xFFFF))
    }

    // MARK: - 3. FairPlay Night Dimmer Guard

    func testShouldBypassNightDimmerForStrictDRMAndAllowNonDRM() throws {
        let drmURLStrings = [
            "https://tv.youtube.com/watch/abc",
            "https://www.disneyplus.com/video/123",
            "https://www.netflix.com/watch/8000",
            "https://www.hulu.com/watch/123",
            "https://www.amazon.com/gp/video/detail/B001",
            "https://play.hbomax.com/video/watch/123",
            "https://tv.apple.com/us/show/severance",
            "https://www.crunchyroll.com/watch/G123"
        ]
        for raw in drmURLStrings {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertTrue(
                MultiviewGridLayout.shouldBypassNightDimmer(for: [url]),
                "Expected Night Dimmer bypass for FairPlay DRM URL: \(raw)"
            )
        }

        let nonDRMURLStrings = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.twitch.tv/shroud",
            "https://www.espn.com/watch/"
        ]
        let nonDRMURLs = try nonDRMURLStrings.map { try XCTUnwrap(URL(string: $0)) }
        for url in nonDRMURLs {
            XCTAssertFalse(
                MultiviewGridLayout.shouldBypassNightDimmer(for: [url]),
                "Expected Night Dimmer allowed for non-strict-DRM URL: \(url.absoluteString)"
            )
        }
        XCTAssertFalse(MultiviewGridLayout.shouldBypassNightDimmer(for: nonDRMURLs))
        XCTAssertFalse(MultiviewGridLayout.shouldBypassNightDimmer(for: []))

        // Mixed array containing at least one strict-DRM URL still bypasses Night Dimmer
        let netflixURL = try XCTUnwrap(URL(string: "https://www.netflix.com/watch/8000"))
        XCTAssertTrue(MultiviewGridLayout.shouldBypassNightDimmer(for: nonDRMURLs + [netflixURL]))
    }

    // MARK: - 4. Multiview Preset Transfer Codec

    func testMultiviewPresetTransferCodecRoundTripAndValidation() throws {
        let presetID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let customRatios = MultiviewSplitRatios(
            columnRatio: 0.65,
            rowRatio: 0.35,
            spotlightRatio: 0.70,
            stackedWeights: [0.50, 0.25, 0.25]
        )
        let original = MultiviewPreset(
            id: presetID,
            name: "Sunday RedZone Quad",
            urlStrings: [
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "https://tv.youtube.com/live",
                "https://www.twitch.tv/esl"
            ],
            layoutMode: .spotlight,
            splitRatios: customRatios
        )

        let encoded = try MultiviewPresetTransferCodec.encode([original], exportedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try MultiviewPresetTransferCodec.decode(from: encoded)
        XCTAssertEqual(decoded, [original])

        // Clamps out-of-range ratios and truncates/sanitizes control/bidi preset names
        let longSuffix = String(repeating: "X", count: 120)
        let dirtyPayload = Data("""
        {
          "schemaVersion": 1,
          "exportedAt": "2026-11-27T12:00:00Z",
          "presets": [
            {
              "id": "\(presetID.uuidString)",
              "name": "Quad\\u0000\\u0007\\u202EGrid \(longSuffix)",
              "urlStrings": [
                "http://www.youtube.com/watch?v=insecure",
                "https://127.0.0.1/ssrf",
                "https://user:pass@www.youtube.com/watch?v=auth",
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "https://www.twitch.tv/shroud"
              ],
              "layoutMode": "stacked",
              "splitRatios": {
                "columnRatio": 0.05,
                "rowRatio": 0.99,
                "spotlightRatio": 5.0,
                "stackedWeights": [0.01, 0.99, 0.0]
              }
            }
          ]
        }
        """.utf8)

        let sanitized = try MultiviewPresetTransferCodec.decode(from: dirtyPayload)
        XCTAssertEqual(sanitized.count, 1)
        let imported = sanitized[0]
        XCTAssertTrue(imported.name.hasPrefix("QuadGrid "))
        XCTAssertEqual(imported.name.count, MultiviewPresetTransferCodec.maxPresetNameLength)
        XCTAssertFalse(imported.name.contains("\u{0000}"))
        XCTAssertFalse(imported.name.contains("\u{202E}"))
        XCTAssertEqual(imported.urlStrings, [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.twitch.tv/shroud"
        ])
        let clamped = try XCTUnwrap(imported.splitRatios)
        XCTAssertEqual(clamped.columnRatio, MultiviewSplitRatios.minRatio, accuracy: 0.0001)
        XCTAssertEqual(clamped.rowRatio, MultiviewSplitRatios.maxRatio, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(clamped.spotlightRatio), MultiviewSplitRatios.maxRatio, accuracy: 0.0001)
        let weights = try XCTUnwrap(clamped.stackedWeights)
        XCTAssertEqual(weights.count, 3)
        XCTAssertEqual(weights.reduce(0, +), 1.0, accuracy: 0.0001)
        for w in weights {
            XCTAssertGreaterThanOrEqual(w, MultiviewSplitRatios.minStackedWeight - 0.0001)
        }

        // Rejects <2 valid tiles and SSRF/loopback/private-IP/http/auth URLs
        let blockedOrTooFewPayload = Data("""
        {
          "schemaVersion": 1,
          "exportedAt": "2026-11-27T12:00:00Z",
          "presets": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Single Tile",
              "urlStrings": ["https://www.youtube.com/watch?v=dQw4w9WgXcQ"],
              "layoutMode": "auto"
            },
            {
              "id": "\(UUID().uuidString)",
              "name": "SSRF Mix",
              "urlStrings": [
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "http://www.youtube.com/watch?v=plainhttp",
                "https://localhost/watch",
                "https://127.0.0.1/watch",
                "https://169.254.169.254/latest/meta-data",
                "https://10.0.0.1/admin",
                "https://[::1]/",
                "https://user:pass@www.youtube.com/"
              ],
              "layoutMode": "auto"
            }
          ]
        }
        """.utf8)
        XCTAssertThrowsError(try MultiviewPresetTransferCodec.decode(from: blockedOrTooFewPayload)) { error in
            XCTAssertEqual(error as? MultiviewPresetTransferError, .noValidPresets)
        }

        // Rejects empty payload
        XCTAssertThrowsError(try MultiviewPresetTransferCodec.decode(from: Data())) { error in
            XCTAssertEqual(error as? MultiviewPresetTransferError, .emptyPayload)
        }

        // Rejects invalid JSON payload
        XCTAssertThrowsError(try MultiviewPresetTransferCodec.decode(from: Data("{not valid json".utf8))) { error in
            XCTAssertEqual(error as? MultiviewPresetTransferError, .invalidJSON)
        }

        // Rejects >512KB payload
        let oversized = Data(repeating: 0x20, count: MultiviewPresetTransferCodec.maxPayloadBytes + 1)
        XCTAssertThrowsError(try MultiviewPresetTransferCodec.decode(from: oversized)) { error in
            XCTAssertEqual(
                error as? MultiviewPresetTransferError,
                .payloadTooLarge(bytes: oversized.count, limit: MultiviewPresetTransferCodec.maxPayloadBytes)
            )
        }

        // Rejects unsupported schemaVersion != 1
        let badSchemaPayload = Data("""
        {
          "schemaVersion": 2,
          "exportedAt": "2026-11-27T12:00:00Z",
          "presets": []
        }
        """.utf8)
        XCTAssertThrowsError(try MultiviewPresetTransferCodec.decode(from: badSchemaPayload)) { error in
            XCTAssertEqual(error as? MultiviewPresetTransferError, .unsupportedSchemaVersion(2))
        }

        // Rejects >32 presets on both encode and decode
        let thirtyThreePresets = (0..<33).map { idx in
            MultiviewPreset(
                name: "Preset \(idx)",
                urlStrings: [
                    "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                    "https://www.twitch.tv/esl"
                ]
            )
        }
        XCTAssertThrowsError(try MultiviewPresetTransferCodec.encode(thirtyThreePresets)) { error in
            XCTAssertEqual(
                error as? MultiviewPresetTransferError,
                .tooManyPresets(count: 33, limit: MultiviewPresetTransferCodec.maxImportedPresets)
            )
        }

        let thirtyThreeJSONEntries = (0..<33).map { idx in
            """
            {
              "id": "\(UUID().uuidString)",
              "name": "Preset \(idx)",
              "urlStrings": [
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "https://www.twitch.tv/esl"
              ],
              "layoutMode": "auto"
            }
            """
        }.joined(separator: ",")
        let tooManyPayload = Data("""
        {
          "schemaVersion": 1,
          "exportedAt": "2026-11-27T12:00:00Z",
          "presets": [\(thirtyThreeJSONEntries)]
        }
        """.utf8)
        XCTAssertThrowsError(try MultiviewPresetTransferCodec.decode(from: tooManyPayload)) { error in
            XCTAssertEqual(
                error as? MultiviewPresetTransferError,
                .tooManyPresets(count: 33, limit: MultiviewPresetTransferCodec.maxImportedPresets)
            )
        }
    }
}
