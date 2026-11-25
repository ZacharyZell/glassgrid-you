import CryptoKit
import Foundation

/// Parsed HTTP/1.1 request validated for local Streamable HTTP MCP.
public struct ParsedHTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let rawTarget: String
    public let headers: [String: String]
    public let duplicateProtectedHeaders: Set<String>
    public let body: Data

    public init(
        method: String,
        path: String,
        rawTarget: String,
        headers: [String: String],
        duplicateProtectedHeaders: Set<String> = [],
        body: Data
    ) {
        self.method = method
        self.path = path
        self.rawTarget = rawTarget
        self.headers = headers
        self.duplicateProtectedHeaders = duplicateProtectedHeaders
        self.body = body
    }

    public func header(_ lowercasedName: String) -> String? {
        headers[lowercasedName.lowercased()]
    }
}

public enum AgentHTTPParseStatus: Equatable, Sendable {
    case incomplete
    case parsed(ParsedHTTPRequest)
    case error(statusCode: Int, message: String)
}

/// Incremental HTTP/1.1 request parser enforcing header/body bounds and rejecting Transfer-Encoding smuggling.
public enum AgentHTTPParser {
    public static let maxHeaderBytes = 8_192
    public static let maxBodyBytes = 262_144

    private static let singletonProtectedHeaders: Set<String> = [
        "host",
        "content-length",
        "origin",
        "authorization",
        "mcp-protocol-version",
        "mcp-session-id",
        "content-type"
    ]

    public static func parse(buffer: Data) -> AgentHTTPParseStatus {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else {
            if buffer.count > maxHeaderBytes {
                return .error(statusCode: 431, message: "Request Header Fields Too Large")
            }
            return .incomplete
        }

        let headerData = buffer[buffer.startIndex..<headerRange.lowerBound]
        if headerData.count > maxHeaderBytes {
            return .error(statusCode: 431, message: "Request Header Fields Too Large")
        }

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return .error(statusCode: 400, message: "Invalid HTTP header encoding")
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .error(statusCode: 400, message: "Missing request line")
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard requestParts.count == 3 else {
            return .error(statusCode: 400, message: "Malformed HTTP request line")
        }

        let method = String(requestParts[0]).uppercased()
        let rawTarget = String(requestParts[1])
        let httpVersion = String(requestParts[2]).uppercased()
        guard httpVersion == "HTTP/1.1" || httpVersion == "HTTP/1.0" else {
            return .error(statusCode: 505, message: "HTTP Version Not Supported")
        }

        let path: String
        if let qIdx = rawTarget.firstIndex(of: "?") {
            path = String(rawTarget[..<qIdx])
        } else {
            path = rawTarget
        }

        var headers: [String: String] = [:]
        var duplicates: Set<String> = []
        for rawLine in lines.dropFirst() where !rawLine.isEmpty {
            guard let colon = rawLine.firstIndex(of: ":") else {
                return .error(statusCode: 400, message: "Malformed header line")
            }
            let name = rawLine[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = rawLine[rawLine.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                return .error(statusCode: 400, message: "Empty header name")
            }
            if name == "transfer-encoding" {
                return .error(statusCode: 501, message: "Transfer-Encoding is not supported")
            }
            if headers[name] != nil {
                if singletonProtectedHeaders.contains(name) {
                    duplicates.insert(name)
                }
            }
            headers[name] = value
        }

        if !duplicates.isEmpty {
            return .error(statusCode: 400, message: "Duplicate protected HTTP headers are rejected")
        }

        var contentLength = 0
        if let rawCL = headers["content-length"] {
            guard !rawCL.isEmpty,
                  rawCL.allSatisfy(\.isNumber),
                  let parsedCL = Int(rawCL),
                  parsedCL >= 0 else {
                return .error(statusCode: 400, message: "Invalid Content-Length")
            }
            guard parsedCL <= maxBodyBytes else {
                return .error(statusCode: 413, message: "Payload Too Large")
            }
            contentLength = parsedCL
        }

        let bodyStart = headerRange.upperBound
        let availableBody = buffer.distance(from: bodyStart, to: buffer.endIndex)
        if availableBody < contentLength {
            return .incomplete
        }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = Data(buffer[bodyStart..<bodyEnd])
        return .parsed(ParsedHTTPRequest(
            method: method,
            path: path,
            rawTarget: rawTarget,
            headers: headers,
            duplicateProtectedHeaders: duplicates,
            body: body
        ))
    }
}

/// Validation result for an HTTP request targeting `/mcp`.
public enum AgentHTTPValidationResult: Equatable, Sendable {
    case valid(protocolVersion: String)
    case rejected(statusCode: Int, message: String, extraHeaders: [String: String])
}

/// Strict security & MCP transport validator for local `127.0.0.1` Streamable HTTP.
public enum AgentHTTPRequestValidator {
    public static func validate(
        _ request: ParsedHTTPRequest,
        expectedPort: Int,
        expectedBearerToken: String
    ) -> AgentHTTPValidationResult {
        guard request.path == "/mcp" else {
            return .rejected(statusCode: 404, message: "Not Found", extraHeaders: [:])
        }

        // Reject ANY Origin header (browser CSRF protection per MCP Streamable HTTP specification)
        if request.header("origin") != nil {
            return .rejected(statusCode: 403, message: "Forbidden: cross-origin requests are rejected", extraHeaders: [:])
        }

        if request.method == "OPTIONS" {
            return .rejected(statusCode: 403, message: "Forbidden", extraHeaders: [:])
        }

        if request.method == "GET" {
            return .rejected(
                statusCode: 405,
                message: "Method Not Allowed: use POST /mcp or DELETE /mcp",
                extraHeaders: ["Allow": "POST, DELETE"]
            )
        }

        guard request.method == "POST" || request.method == "DELETE" else {
            return .rejected(
                statusCode: 405,
                message: "Method Not Allowed",
                extraHeaders: ["Allow": "POST, DELETE"]
            )
        }

        // Anti-DNS-Rebinding: strict Host check for 127.0.0.1:<port>, localhost:<port>, or [::1]:<port>
        guard let host = request.header("host")?.lowercased(),
              isAllowedLoopbackHost(host, expectedPort: expectedPort) else {
            return .rejected(statusCode: 403, message: "Forbidden: invalid Host header", extraHeaders: [:])
        }

        // Constant-time Bearer token check
        guard let auth = request.header("authorization"),
              let token = extractBearerToken(auth),
              !expectedBearerToken.isEmpty,
              AgentSecurity.constantTimeEqual(token, expectedBearerToken) else {
            return .rejected(
                statusCode: 401,
                message: "Unauthorized",
                extraHeaders: ["WWW-Authenticate": "Bearer realm=\"GlassGrid You MCP\""]
            )
        }

        // Validate MCP-Protocol-Version header (2025-06-18 or 2025-03-26; absent defaults to 2025-03-26)
        let protocolVersion: String
        if let rawVersion = request.header("mcp-protocol-version"), !rawVersion.isEmpty {
            guard MCPProtocolHandler.isSupportedHTTPProtocolVersion(rawVersion) else {
                return .rejected(statusCode: 400, message: "Unsupported MCP-Protocol-Version", extraHeaders: [:])
            }
            protocolVersion = rawVersion
        } else {
            protocolVersion = MCPProtocolHandler.defaultHTTPFallbackVersion
        }

        if request.method == "POST" {
            guard let contentType = request.header("content-type")?.lowercased(),
                  contentType.hasPrefix("application/json") else {
                return .rejected(statusCode: 415, message: "Unsupported Media Type: expected application/json", extraHeaders: [:])
            }
        }

        return .valid(protocolVersion: protocolVersion)
    }

    public static func isAllowedLoopbackHost(_ hostHeader: String, expectedPort: Int) -> Bool {
        let lower = hostHeader.trimmingCharacters(in: .whitespaces).lowercased()
        let allowed = [
            "127.0.0.1:\(expectedPort)",
            "localhost:\(expectedPort)",
            "[::1]:\(expectedPort)"
        ]
        if expectedPort == 80 {
            return allowed.contains(lower) || lower == "127.0.0.1" || lower == "localhost" || lower == "[::1]"
        }
        return allowed.contains(lower)
    }

    private static func extractBearerToken(_ header: String) -> String? {
        let parts = header.split(maxSplits: 1, whereSeparator: { $0 == " " })
        guard parts.count == 2, parts[0].lowercased() == "bearer" else {
            return nil
        }
        let token = String(parts[1]).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }
}

/// Bounded 64-entry LRU + 24h TTL store for `Mcp-Session-Id` lifecycle.
public struct AgentHTTPSessionStore: Sendable {
    public struct Entry: Equatable, Sendable {
        public let id: String
        public var lastUsedAt: Date
    }

    private var entries: [Entry] = []
    public let capacity: Int
    public let ttlSeconds: TimeInterval

    public init(capacity: Int = 64, ttlSeconds: TimeInterval = 24 * 60 * 60) {
        self.capacity = max(1, capacity)
        self.ttlSeconds = max(60, ttlSeconds)
    }

    public mutating func createSession(now: Date = Date(), idOverride: String? = nil) -> String {
        pruneExpired(now: now)
        let id = idOverride ?? Self.generateSessionID()
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, lastUsedAt: now))
        while entries.count > capacity {
            entries.removeFirst()
        }
        return id
    }

    public mutating func validateAndTouch(_ sessionID: String, now: Date = Date()) -> Bool {
        pruneExpired(now: now)
        guard let idx = entries.firstIndex(where: { $0.id == sessionID }) else {
            return false
        }
        var item = entries.remove(at: idx)
        item.lastUsedAt = now
        entries.append(item)
        return true
    }

    @discardableResult
    public mutating func delete(_ sessionID: String) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == sessionID }
        return entries.count < before
    }

    public var count: Int {
        entries.count
    }

    private mutating func pruneExpired(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.lastUsedAt) > ttlSeconds }
    }

    public static func generateSessionID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Simple token-bucket rate limiter protecting MainActor/WebKit from runaway agent loops (60 req/min, burst 20).
public struct AgentRateLimiter: Sendable {
    private var tokens: Double
    private var lastRefill: Date
    public let capacity: Double
    public let refillPerSecond: Double

    public init(capacity: Double = 20, requestsPerMinute: Double = 60, now: Date = Date()) {
        self.capacity = max(1, capacity)
        self.tokens = self.capacity
        self.refillPerSecond = max(0.1, requestsPerMinute / 60.0)
        self.lastRefill = now
    }

    public mutating func tryConsume(now: Date = Date()) -> Bool {
        let elapsed = max(0, now.timeIntervalSince(lastRefill))
        tokens = min(capacity, tokens + elapsed * refillPerSecond)
        lastRefill = now
        guard tokens >= 1.0 else {
            return false
        }
        tokens -= 1.0
        return true
    }
}

/// Serializes HTTP/1.1 responses with explicit `Content-Length`, `Connection: close`, and `Cache-Control: no-store`.
public enum AgentHTTPResponseSerializer {
    public static func serialize(
        statusCode: Int,
        reasonPhrase: String? = nil,
        headers: [String: String] = [:],
        body: Data = Data()
    ) -> Data {
        let phrase = reasonPhrase ?? defaultReasonPhrase(for: statusCode)
        var allHeaders: [String: String] = [
            "Connection": "close",
            "Cache-Control": "no-store",
            "Content-Length": "\(body.count)"
        ]
        for (k, v) in headers {
            allHeaders[k] = v
        }

        var head = "HTTP/1.1 \(statusCode) \(phrase)\r\n"
        for key in allHeaders.keys.sorted() {
            if let val = allHeaders[key] {
                head += "\(key): \(val)\r\n"
            }
        }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    public static func jsonError(
        statusCode: Int,
        code: Int = -32600,
        message: String,
        headers: [String: String] = [:]
    ) -> Data {
        let payload = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .null,
            "error": .object([
                "code": .int(code),
                "message": .string(message)
            ])
        ])
        let body = (try? payload.encodedData(prettyPrinted: false)) ?? Data()
        var merged = headers
        merged["Content-Type"] = "application/json; charset=utf-8"
        return serialize(statusCode: statusCode, headers: merged, body: body)
    }

    private static func defaultReasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 505: return "HTTP Version Not Supported"
        default: return "Error"
        }
    }
}
