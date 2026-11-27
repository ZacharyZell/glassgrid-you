import XCTest
@testable import YouTubeMacCore

final class AgentControlTests: XCTestCase {
    // MARK: - 1. URL Routing Self-Reentry Block & EnhancementScript Invariants

    func testWebKitNavigationBlocksCustomAppSchemes() {
        let youtubePage = URL(string: "https://www.youtube.com/watch?v=abc")!
        let companionPage = URL(string: "https://www.twitch.tv/live")!

        for schemeURL in [
            URL(string: "glassgridyou://action/pause")!,
            URL(string: "glassgridyou://watch?v=dQw4w9WgXcQ")!,
            URL(string: "youtubemac://action/play")!
        ] {
            XCTAssertEqual(
                YouTubeURLRouter.routeNavigation(
                    url: schemeURL,
                    currentPageURL: youtubePage,
                    isUserLinkClick: true,
                    openExternalLinksInBrowser: true,
                    redirectShortsToWatch: true,
                    routingMode: .youtube
                ),
                .block
            )
            XCTAssertEqual(
                YouTubeURLRouter.routeNavigation(
                    url: schemeURL,
                    currentPageURL: companionPage,
                    isUserLinkClick: false,
                    openExternalLinksInBrowser: true,
                    redirectShortsToWatch: true,
                    routingMode: .companion
                ),
                .block
            )
        }
    }

    func testEnhancementScriptPlayAndChapters() {
        XCTAssertTrue(EnhancementScript.playScript.contains("playVideo"))
        XCTAssertTrue(EnhancementScript.playScript.contains("v.play()"))
        let bootstrap = EnhancementScript.bootstrapScript(config: DistractionFreeConfig())
        XCTAssertTrue(bootstrap.contains("description: cappedDescription"))
        XCTAssertFalse(bootstrap.contains(":has("))
        XCTAssertFalse(bootstrap.contains("MutationObserver"))
        XCTAssertFalse(bootstrap.contains("AudioContext"))
        XCTAssertFalse(bootstrap.contains("ytInitialPlayerResponse"))
    }

    // MARK: - 2. Security, Constant-Time Compare, Sanitization & SSRF/URL Validation

    func testConstantTimeEqual() {
        XCTAssertTrue(AgentSecurity.constantTimeEqual("secret-token-123", "secret-token-123"))
        XCTAssertFalse(AgentSecurity.constantTimeEqual("secret-token-123", "secret-token-124"))
        XCTAssertFalse(AgentSecurity.constantTimeEqual("short", "much-longer-token"))
        XCTAssertTrue(AgentSecurity.constantTimeEqual("", ""))
    }

    func testSanitizeWebTextStripsControlAndBidiAndCapsLength() {
        let dirty = "Hello\u{0000}\u{0007} \u{202E}evil\u{2066}\n\n\n\nWorld"
        let (cleaned, truncated) = AgentSecurity.sanitizeWebText(dirty, maxLength: 100)
        XCTAssertFalse(truncated)
        XCTAssertEqual(cleaned, "Hello evil\n\nWorld")

        let long = String(repeating: "a", count: 4500)
        let (capped, wasTruncated) = AgentSecurity.sanitizeWebText(long, maxLength: AgentSecurity.maxVideoDescriptionLength)
        XCTAssertTrue(wasTruncated)
        XCTAssertEqual(capped.count, 4000)
    }

    func testValidateURLHardening() {
        // Blocked under all tiers
        let alwaysBlocked = [
            "",
            "http://www.youtube.com/watch?v=123",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "data:text/html,hi",
            "https://user:pass@www.youtube.com/",
            "https://localhost/watch",
            "https://foo.localhost/",
            "https://mybox.local/",
            "https://metadata.internal/",
            "https://127.0.0.1/mcp",
            "https://169.254.169.254/latest/meta-data",
            "https://[::1]/",
            "https://2130706433/",
            "https://0x7f000001/",
            "https://www.youtube.com./watch?v=123",
            "https://foo..bar.com/",
            "https://accounts.google.com/ServiceLogin",
            "https://myaccount.google.com/",
            "https://www.youtube.com/redirect?q=https://evil.com",
            "https://www.youtube.com/logout",
            "https://www.twitch.tv/signout",
            "https://auth.hulu.com/web/login"
        ]
        for raw in alwaysBlocked {
            if case .success = AgentSecurity.validateURL(raw, tier: .fullControl) {
                XCTFail("Expected URL to be blocked even in fullControl: \(raw)")
            }
        }

        // YouTube & catalog streaming services allowed in playbackAndNavigation
        XCTAssertTrue((try? AgentSecurity.validateURL("https://www.youtube.com/watch?v=dQw4w9WgXcQ", tier: .playbackAndNavigation).get()) != nil)
        XCTAssertTrue((try? AgentSecurity.validateURL("https://tv.youtube.com/live", tier: .playbackAndNavigation).get()) != nil)
        XCTAssertTrue((try? AgentSecurity.validateURL("https://www.twitch.tv/esl", tier: .playbackAndNavigation).get()) != nil)

        // Arbitrary public HTTPS Companion domain blocked in playbackAndNavigation, allowed in fullControl
        if case .failure(let err) = AgentSecurity.validateURL("https://www.nasa.gov/", tier: .playbackAndNavigation) {
            XCTAssertEqual(err, .tierRestrictedCompanionDomain)
        } else {
            XCTFail("Expected arbitrary Companion domain to require fullControl")
        }
        XCTAssertTrue((try? AgentSecurity.validateURL("https://www.nasa.gov/", tier: .fullControl).get()) != nil)

        // Read-only rejects all URL navigation
        if case .success = AgentSecurity.validateURL("https://www.youtube.com/", tier: .readOnly) {
            XCTFail("readOnly must reject URLs")
        }
    }

    // MARK: - 3. MCP Protocol & Permission Matrix

    func testMCPProtocolDiscoveryAndToolsCall() async throws {
        let handler = MCPProtocolHandler()
        let executor = MockAgentExecutor(enabled: true, tier: .playbackAndNavigation)
        let ctx = AgentRequestContext(source: .mcpStdio, clientName: "test")

        // Initialize
        let initReq = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#.utf8)
        if case .reply(let replyData) = await handler.handleMessageData(initReq, context: ctx, executor: executor),
           let decoded = try? JSONValue.decode(from: replyData) {
            XCTAssertEqual(decoded.objectValue?["result"]?.objectValue?["protocolVersion"]?.stringValue, "2025-06-18")
        } else {
            XCTFail("Expected initialize reply")
        }

        // Notification returns noResponse
        let notifReq = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        let notifRes = await handler.handleMessageData(notifReq, context: ctx, executor: executor)
        XCTAssertEqual(notifRes, .noResponse)

        // tools/list returns all 28 tools with annotations
        let listReq = Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
        if case .reply(let listData) = await handler.handleMessageData(listReq, context: ctx, executor: executor),
           let decoded = try? JSONValue.decode(from: listData),
           let tools = decoded.objectValue?["result"]?.objectValue?["tools"]?.arrayValue {
            XCTAssertEqual(tools.count, 28)
        } else {
            XCTFail("Expected 28 tools from tools/list")
        }

        // resources/list returns all 5 resources
        let resListReq = Data(#"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#.utf8)
        if case .reply(let resData) = await handler.handleMessageData(resListReq, context: ctx, executor: executor),
           let decoded = try? JSONValue.decode(from: resData),
           let resources = decoded.objectValue?["result"]?.objectValue?["resources"]?.arrayValue {
            XCTAssertEqual(resources.count, 5)
        } else {
            XCTFail("Expected 5 resources from resources/list")
        }

        // Tier 2 succeeds under playbackAndNavigation
        let playReq = Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"playback_control","arguments":{"action":"pause"}}}"#.utf8)
        if case .reply(let playData) = await handler.handleMessageData(playReq, context: ctx, executor: executor),
           let decoded = try? JSONValue.decode(from: playData),
           let result = decoded.objectValue?["result"]?.objectValue {
            XCTAssertEqual(result["isError"]?.boolValue, false)
            XCTAssertEqual(result["structuredContent"]?.objectValue?["ok"]?.boolValue, true)
        } else {
            XCTFail("Expected tools/call reply")
        }

        // Tier 3 denied under playbackAndNavigation -> isError: true
        let closeReq = Data(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"manage_tabs","arguments":{"action":"close"}}}"#.utf8)
        if case .reply(let closeData) = await handler.handleMessageData(closeReq, context: ctx, executor: executor),
           let decoded = try? JSONValue.decode(from: closeData),
           let result = decoded.objectValue?["result"]?.objectValue {
            XCTAssertEqual(result["isError"]?.boolValue, true)
            XCTAssertEqual(result["structuredContent"]?.objectValue?["errorCode"]?.stringValue, "permission_denied")
        } else {
            XCTFail("Expected permission_denied tool error")
        }

        // Batch rejected on 2025-06-18
        let batchReq = Data(#"[{"jsonrpc":"2.0","id":6,"method":"ping"}]"#.utf8)
        let batchRes = await handler.handleMessageData(batchReq, httpProtocolVersion: "2025-06-18", context: ctx, executor: executor)
        XCTAssertEqual(batchRes, .batchRejected)

        // Unknown resource returns -32002
        let readUnknown = Data(#"{"jsonrpc":"2.0","id":7,"method":"resources/read","params":{"uri":"glassgrid://nope"}}"#.utf8)
        if case .reply(let errData) = await handler.handleMessageData(readUnknown, context: ctx, executor: executor),
           let decoded = try? JSONValue.decode(from: errData) {
            XCTAssertEqual(decoded.objectValue?["error"]?.objectValue?["code"]?.intValue, -32002)
        } else {
            XCTFail("Expected -32002 JSON-RPC error")
        }
    }

    // MARK: - 4. IPC Framing & Socket Path Resolution

    func testIPCFrameCodecAndSocketPath() throws {
        let p1 = Data(#"{"hello":"world"}"#.utf8)
        let p2 = Data(#"{"second":2}"#.utf8)
        let f1 = try AgentIPCFrameCodec.encode(p1)
        let f2 = try AgentIPCFrameCodec.encode(p2)

        let combined = f1 + f2
        // Split across arbitrary chunk boundary
        var streamBuf = Data(combined.prefix(6))
        XCTAssertEqual(try AgentIPCFrameCodec.extractFrames(from: &streamBuf), [])
        streamBuf.append(combined.dropFirst(6))
        let extracted = try AgentIPCFrameCodec.extractFrames(from: &streamBuf)
        XCTAssertEqual(extracted, [p1, p2])
        XCTAssertTrue(streamBuf.isEmpty)

        // Reject 0-length frame
        var zeroBuf = Data([0, 0, 0, 0])
        XCTAssertThrowsError(try AgentIPCFrameCodec.extractFrames(from: &zeroBuf))

        // Reject > maxFrameBytes
        let oversized = Data(repeating: 0x41, count: AgentIPCFrameCodec.maxFrameBytes + 1)
        XCTAssertThrowsError(try AgentIPCFrameCodec.encode(oversized))

        // Normal path & long-HOME fallback
        let normal = AgentSocketPath.resolve(homeDirectory: "/Users/alice", darwinUserTempDir: "/var/folders/xx/T")
        XCTAssertFalse(normal.usedTempFallback)
        XCTAssertEqual(normal.socketPath, "/Users/alice/Library/Application Support/GlassGridYou/v1.sock")

        let longHome = "/Users/" + String(repeating: "longuser", count: 12)
        let fallback = AgentSocketPath.resolve(homeDirectory: longHome, darwinUserTempDir: "/var/folders/xx/T")
        XCTAssertTrue(fallback.usedTempFallback)
        XCTAssertEqual(fallback.socketPath, "/var/folders/xx/T/gg/v1.sock")
        XCTAssertLessThanOrEqual(fallback.socketPath.utf8.count, AgentSocketPath.maxSunPathUTF8Bytes)
    }

    // MARK: - 5. Streamable HTTP Parser, Security Validator, Session LRU & Rate Limiter

    func testHTTPParserAndSecurityValidator() {
        let token = "0123456789abcdef0123456789abcdef"
        let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let validRaw = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:41773\r\nAuthorization: Bearer \(token)\r\nContent-Type: application/json\r\nMCP-Protocol-Version: 2025-06-18\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"

        guard case .parsed(let parsed) = AgentHTTPParser.parse(buffer: Data(validRaw.utf8)) else {
            return XCTFail("Expected valid HTTP parse")
        }
        XCTAssertEqual(
            AgentHTTPRequestValidator.validate(parsed, expectedPort: 41773, expectedBearerToken: token),
            .valid(protocolVersion: "2025-06-18")
        )

        // Reject Origin header (CSRF)
        let originRaw = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:41773\r\nOrigin: https://evil.com\r\nAuthorization: Bearer \(token)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        if case .parsed(let req) = AgentHTTPParser.parse(buffer: Data(originRaw.utf8)),
           case .rejected(let code, _, _) = AgentHTTPRequestValidator.validate(req, expectedPort: 41773, expectedBearerToken: token) {
            XCTAssertEqual(code, 403)
        } else {
            XCTFail("Expected 403 for Origin header")
        }

        // Reject DNS rebinding Host
        let badHostRaw = "POST /mcp HTTP/1.1\r\nHost: evil.com:41773\r\nAuthorization: Bearer \(token)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        if case .parsed(let req) = AgentHTTPParser.parse(buffer: Data(badHostRaw.utf8)),
           case .rejected(let code, _, _) = AgentHTTPRequestValidator.validate(req, expectedPort: 41773, expectedBearerToken: token) {
            XCTAssertEqual(code, 403)
        } else {
            XCTFail("Expected 403 for non-loopback Host")
        }

        // Reject bad Bearer token
        let badAuthRaw = "POST /mcp HTTP/1.1\r\nHost: localhost:41773\r\nAuthorization: Bearer wrong\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        if case .parsed(let req) = AgentHTTPParser.parse(buffer: Data(badAuthRaw.utf8)),
           case .rejected(let code, _, _) = AgentHTTPRequestValidator.validate(req, expectedPort: 41773, expectedBearerToken: token) {
            XCTAssertEqual(code, 401)
        } else {
            XCTFail("Expected 401 for wrong Bearer")
        }

        // GET /mcp -> 405
        let getRaw = "GET /mcp HTTP/1.1\r\nHost: 127.0.0.1:41773\r\n\r\n"
        if case .parsed(let req) = AgentHTTPParser.parse(buffer: Data(getRaw.utf8)),
           case .rejected(let code, _, let extra) = AgentHTTPRequestValidator.validate(req, expectedPort: 41773, expectedBearerToken: token) {
            XCTAssertEqual(code, 405)
            XCTAssertEqual(extra["Allow"], "POST, DELETE")
        } else {
            XCTFail("Expected 405 on GET /mcp")
        }

        // Transfer-Encoding rejected (anti-smuggling)
        let teRaw = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:41773\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
        if case .error(let code, _) = AgentHTTPParser.parse(buffer: Data(teRaw.utf8)) {
            XCTAssertEqual(code, 501)
        } else {
            XCTFail("Expected 501 for Transfer-Encoding")
        }

        // Duplicate protected header rejected
        let dupRaw = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:41773\r\nHost: evil.com\r\n\r\n"
        if case .error(let code, _) = AgentHTTPParser.parse(buffer: Data(dupRaw.utf8)) {
            XCTAssertEqual(code, 400)
        } else {
            XCTFail("Expected 400 for duplicate Host")
        }
    }

    func testHTTPSessionStoreLRUAndRateLimiter() {
        var store = AgentHTTPSessionStore(capacity: 2, ttlSeconds: 3600)
        let s1 = store.createSession(idOverride: "s1")
        let s2 = store.createSession(idOverride: "s2")
        XCTAssertTrue(store.validateAndTouch(s1)) // s2 is now LRU
        let s3 = store.createSession(idOverride: "s3")
        XCTAssertFalse(store.validateAndTouch(s2))
        XCTAssertTrue(store.validateAndTouch(s1))
        XCTAssertTrue(store.validateAndTouch(s3))
        XCTAssertTrue(store.delete(s1))
        XCTAssertFalse(store.validateAndTouch(s1))

        var limiter = AgentRateLimiter(capacity: 2, requestsPerMinute: 60, now: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(limiter.tryConsume(now: Date(timeIntervalSince1970: 1000)))
        XCTAssertTrue(limiter.tryConsume(now: Date(timeIntervalSince1970: 1000)))
        XCTAssertFalse(limiter.tryConsume(now: Date(timeIntervalSince1970: 1000)))
        XCTAssertTrue(limiter.tryConsume(now: Date(timeIntervalSince1970: 1001.5)))
    }

    // MARK: - 6. URL Action Parser

    func testURLActionParserSafety() {
        XCTAssertTrue(AgentURLActionParser.isActionURL(URL(string: "glassgridyou://action/pause")!))
        XCTAssertFalse(AgentURLActionParser.isActionURL(URL(string: "glassgridyou://watch?v=abc")!))

        if case .success(let parsed) = AgentURLActionParser.parse(URL(string: "glassgridyou://action/seek?delta=-15")!) {
            XCTAssertEqual(parsed.toolName, "seek_playback")
            XCTAssertEqual(parsed.arguments["delta_seconds"]?.doubleValue, -15)
        } else {
            XCTFail("Expected valid seek action")
        }

        // Arbitrary open URL or Tier 3 verbs are blocked
        if case .success = AgentURLActionParser.parse(URL(string: "glassgridyou://action/open?url=https://evil.com")!) {
            XCTFail("open verb must not be exposed via URL action")
        }
        if case .success = AgentURLActionParser.parse(URL(string: "glassgridyou://action/manage_tabs?action=close")!) {
            XCTFail("Tier 3 verb must not be exposed via URL action")
        }
    }

    // MARK: - 7. MCP Client Config Mergers (JSON & TOML)

    func testJSONMergerPreservesSiblingsAndFailsClosed() throws {
        let initial = Data(#"{"theme":"dark","mcpServers":{"other":{"command":"uvx"}}}"#.utf8)
        let mergedData = try MCPClientConfigMerger.mergeJSONConfig(
            existing: initial,
            serverObject: MCPClientConfigMerger.stdioServerObject(binaryPath: "/Applications/GlassGrid You.app/Contents/MacOS/glassgrid")
        )
        let mergedText = String(data: mergedData, encoding: .utf8)!
        XCTAssertTrue(mergedText.contains("/Applications/GlassGrid You.app/Contents/MacOS/glassgrid"))
        XCTAssertFalse(mergedText.contains("\\/"))
        XCTAssertTrue(mergedText.contains("\"other\""))
        XCTAssertTrue(mergedText.contains("\"theme\""))

        let removedData = try MCPClientConfigMerger.removeJSONConfig(existing: mergedData)
        XCTAssertNil(MCPClientConfigMerger.inspectJSONServer(existing: removedData))
        XCTAssertNotNil(MCPClientConfigMerger.inspectJSONServer(existing: removedData, serverKey: "other"))

        XCTAssertThrowsError(try MCPClientConfigMerger.mergeJSONConfig(existing: Data("{not json".utf8), serverObject: [:]))
    }

    func testTOMLMergerHandlesMultilineCommentsAndSubtables() throws {
        let existing = """
        # Grok CLI user config
        model = "grok-code-fast-1"

        [prompts]
        banner = \"\"\"
        [mcp_servers.glassgrid-you]
        this is inside a multiline string and must NOT be stripped!
        \"\"\"

        [mcp_servers.filesystem]
        command = "npx"
        args = ["-y", "fs"]

        [mcp_servers."glassgrid-you"]
        command = "/old/path"
        args = ["mcp"]

        [mcp_servers."glassgrid-you".headers]
        Authorization = "Bearer old"
        """

        let merged = try MCPClientConfigMerger.mergeTOMLConfig(
            existing: existing,
            mode: .stdio,
            binaryPath: "/Applications/GlassGrid You.app/Contents/MacOS/glassgrid"
        )
        XCTAssertTrue(merged.contains("# Grok CLI user config"))
        XCTAssertTrue(merged.contains("this is inside a multiline string and must NOT be stripped!"))
        XCTAssertTrue(merged.contains("[mcp_servers.filesystem]"))
        XCTAssertFalse(merged.contains("/old/path"))
        XCTAssertFalse(merged.contains("Bearer old"))
        XCTAssertTrue(merged.contains("command = \"/Applications/GlassGrid You.app/Contents/MacOS/glassgrid\""))

        let removed = try MCPClientConfigMerger.removeTOMLConfig(existing: merged)
        XCTAssertFalse(removed.contains("/Applications/GlassGrid You.app/Contents/MacOS/glassgrid"))
        XCTAssertTrue(removed.contains("[mcp_servers.filesystem]"))

        // Gemini HTTP uses httpUrl vs Antigravity url
        let geminiHTTP = MCPClientConfigMerger.generateSnippet(
            for: .geminiCLI,
            mode: .streamableHTTP,
            binaryPath: "/Applications/GlassGrid You.app/Contents/MacOS/glassgrid",
            httpPort: 41773,
            bearerToken: "tok"
        )
        XCTAssertTrue(geminiHTTP.contains("\"httpUrl\""))
    }

    // MARK: - 10. All-18-Services Security Matrix & Crunchyroll URL Actions

    func testAll18ServicesURLSecurityMatrixAndCrunchyrollURLAction() {
        for service in StreamingServiceCatalog.all {
            if case .failure(let err) = AgentSecurity.validateURL(service.homeURLString, tier: .playbackAndNavigation) {
                XCTFail("Expected homeURL to be allowed for \(service.id) (\(service.homeURLString)): \(err)")
            }
            if service.signInURL != service.homeURL {
                if case .failure(let err) = AgentSecurity.validateURL(service.signInURLString, tier: .fullControl) {
                    XCTAssertEqual(err, .blockedAuthOrLogoutRoute, "Unexpected error kind for \(service.id) signInURL")
                } else {
                    XCTFail("Expected signInURL to be blocked for \(service.id): \(service.signInURLString)")
                }
            }
        }

        let explicitAllowed = [
            "https://www.amazon.com/gp/video/storefront",
            "https://www.primevideo.com/storefront",
            "https://www.amazon.co.uk/gp/video/storefront",
            "https://www.netflix.com/browse",
            "https://www.crunchyroll.com/discover",
            "https://www.crunchyroll.com/watch/G12345/ep-1"
        ]
        for raw in explicitAllowed {
            if case .failure(let err) = AgentSecurity.validateURL(raw, tier: .playbackAndNavigation) {
                XCTFail("Expected URL to be allowed in playbackAndNavigation (\(raw)): \(err)")
            }
        }

        let explicitBlocked = [
            "https://www.amazon.com/ap/signin",
            "https://www.amazon.com/ap/signin?openid.mode=checkid_setup",
            "https://www.amazon.com/ax/claim?arb=test",
            "https://www.amazon.com/ap/mfa",
            "https://www.amazon.com/gp/cart/view.html",
            "https://www.amazon.com/gp/aws/cart/add.html?ASIN.1=B000",
            "https://www.amazon.com/gp/checkoutportal/enter-checkout.html",
            "https://www.amazon.com/cpe/managepaymentmethods",
            "https://www.amazon.com/gp/flex/sign-out.html",
            "https://www.amazon.com/gp/sign-in.html",
            "https://www.primevideo.com/region/na/ap/signin",
            "https://na.account.amazon.com/",
            "https://www.netflix.com/login",
            "https://www.crunchyroll.com/login",
            "https://www.crunchyroll.com/es-es/login",
            "https://www.crunchyroll.com/pt-br/login",
            "https://sso.crunchyroll.com/login",
            "https://www.twitch.tv/login",
            "https://www.peacocktv.com/signin"
        ]
        for raw in explicitBlocked {
            if case .failure(let err) = AgentSecurity.validateURL(raw, tier: .fullControl) {
                XCTAssertEqual(err, .blockedAuthOrLogoutRoute, "Expected blockedAuthOrLogoutRoute for \(raw)")
            } else {
                XCTFail("Expected URL to be blocked in fullControl: \(raw)")
            }
        }

        let parsedAction = AgentURLActionParser.parse(URL(string: "glassgridyou://action/service?id=crunchyroll")!)
        if case .success(let req) = parsedAction {
            XCTAssertEqual(req.toolName, "open_service")
            XCTAssertEqual(req.arguments["service_id"]?.stringValue, "crunchyroll")
        } else {
            XCTFail("Expected crunchyroll URL action to parse cleanly")
        }
    }

    func testMCPCatalogPreservesSurfaceAndExposesCleanBoxAndGridControls() {
        XCTAssertEqual(AgentToolCatalog.tools.count, 28)
        XCTAssertEqual(AgentToolCatalog.resources.count, 5)

        let miniTool = AgentToolCatalog.tool(named: "mini_player_control")
        XCTAssertNotNil(miniTool)
        let sizePresetSchema = miniTool?.inputSchema.objectValue?["properties"]?.objectValue?["size_preset"]?.objectValue
        let enumValues = sizePresetSchema?["enum"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        XCTAssertEqual(enumValues, ["compact", "standard", "large", "extraLarge"])

        let prefsTool = AgentToolCatalog.tool(named: "set_distraction_free_preferences")
        XCTAssertNotNil(prefsTool)
        let cleanBoxProp = prefsTool?.inputSchema.objectValue?["properties"]?.objectValue?["clean_box_streaming_players"]?.objectValue
        XCTAssertEqual(cleanBoxProp?["type"]?.stringValue, "boolean")
    }

    func testConnectedServiceSecurityAliasResolutionAndMCPDiscovery() async throws {
        // 1. Alias resolution across CLI, URL actions, Siri & MCP tools
        XCTAssertEqual(StreamingServiceCatalog.resolveService(identifierOrAlias: "hbomax")?.id, "max")
        XCTAssertEqual(StreamingServiceCatalog.resolveService(identifierOrAlias: "HBO Max")?.id, "max")
        XCTAssertEqual(StreamingServiceCatalog.resolveService(identifierOrAlias: "disney+")?.id, "disneyplus")
        XCTAssertEqual(StreamingServiceCatalog.resolveService(identifierOrAlias: "Apple TV+")?.id, "appletv")
        XCTAssertEqual(StreamingServiceCatalog.resolveService(identifierOrAlias: "prime")?.id, "primevideo")

        let urlAction = AgentURLActionParser.parse(URL(string: "glassgridyou://action/service?id=hbomax&multiview=true")!)
        if case .success(let parsed) = urlAction {
            XCTAssertEqual(parsed.toolName, "open_service")
            XCTAssertEqual(parsed.arguments["service_id"]?.stringValue, "max")
            XCTAssertEqual(parsed.arguments["in_multiview"]?.boolValue, true)
        } else {
            XCTFail("Expected hbomax URL alias to resolve to max")
        }

        // 2. AgentSecurity URL hardening against newly discovered auth & corporate domains
        if case .failure(let err) = AgentSecurity.validateURL("https://www.disneyplus.com/identity/login/enter-password", tier: .fullControl) {
            XCTAssertEqual(err, .blockedAuthOrLogoutRoute)
        } else {
            XCTFail("Expected Disney+ /identity/login/enter-password to be blocked")
        }
        if case .failure(let err) = AgentSecurity.validateURL("https://www.hbomax.com/auth/password", tier: .fullControl) {
            XCTAssertEqual(err, .blockedAuthOrLogoutRoute)
        } else {
            XCTFail("Expected HBO Max /auth/password to be blocked")
        }
        if case .failure(let err) = AgentSecurity.validateURL("https://www.icloud.com/", tier: .playbackAndNavigation) {
            XCTAssertEqual(err, .tierRestrictedCompanionDomain)
        } else {
            XCTFail("Expected icloud.com to be blocked in playbackAndNavigation tier")
        }
        if case .success(let hboURL) = AgentSecurity.validateURL("https://play.hbomax.com/video/watch/123", tier: .playbackAndNavigation) {
            XCTAssertEqual(hboURL.host, "play.hbomax.com")
        } else {
            XCTFail("Expected play.hbomax.com watch URL in playbackAndNavigation tier")
        }

        // 3. MCP discovery-only handling avoids launching GUI app
        let handler = MCPProtocolHandler()
        let tplReq = Data(#"{"jsonrpc":"2.0","id":10,"method":"resources/templates/list"}"#.utf8)
        guard let tplRes = handler.handleDiscoveryOnly(tplReq), case .reply(let tplData) = tplRes else {
            return XCTFail("Expected resources/templates/list local reply")
        }
        let tplJSON = try JSONValue.decode(from: tplData)
        XCTAssertEqual(tplJSON.objectValue?["result"]?.objectValue?["resourceTemplates"]?.arrayValue, [])

        let promptsReq = Data(#"{"jsonrpc":"2.0","id":11,"method":"prompts/list"}"#.utf8)
        guard let promptsRes = handler.handleDiscoveryOnly(promptsReq), case .reply(let promptsData) = promptsRes else {
            return XCTFail("Expected prompts/list local error reply")
        }
        let promptsJSON = try JSONValue.decode(from: promptsData)
        XCTAssertEqual(promptsJSON.objectValue?["error"]?.objectValue?["code"]?.intValue, -32601)

        let notifReq = Data(#"{"jsonrpc":"2.0","method":"notifications/roots/list_changed"}"#.utf8)
        XCTAssertEqual(handler.handleDiscoveryOnly(notifReq), .noResponse)

        let notifIDReq = Data(#"{"jsonrpc":"2.0","method":"resources/templates/list"}"#.utf8)
        XCTAssertEqual(handler.handleDiscoveryOnly(notifIDReq), .noResponse)
    }
}

private struct MockAgentExecutor: AgentCommandExecutor {
    let enabled: Bool
    let tier: AgentPermissionLevel

    func isAutomationEnabled() async -> Bool { enabled }
    func currentPermissionLevel() async -> AgentPermissionLevel { tier }

    func execute(toolName: String, arguments: [String: JSONValue], context: AgentRequestContext) async -> AgentCommandOutcome {
        guard enabled else {
            return .failure(code: "automation_disabled", message: "Disabled")
        }
        guard let tool = AgentToolCatalog.tool(named: toolName) else {
            return .failure(code: "unknown_tool", message: "Unknown")
        }
        guard tier >= tool.requiredTier else {
            return .failure(code: "permission_denied", message: "Denied")
        }
        return .success("Executed \(toolName)")
    }

    func readResource(uri: String, context: AgentRequestContext) async -> AgentResourceOutcome {
        guard enabled else {
            return .failure(uri: uri, code: "automation_disabled", message: "Disabled")
        }
        if AgentToolCatalog.resource(forURI: uri) != nil {
            return .success(uri: uri, text: "{}")
        }
        return .failure(uri: uri, code: "resource_not_found", message: "Not found")
    }
}
