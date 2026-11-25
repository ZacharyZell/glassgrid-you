import Foundation

/// Supported AI desktop & CLI MCP clients with verified config file paths and formats.
public enum MCPClientKind: String, CaseIterable, Identifiable, Sendable {
    case claudeDesktop
    case claudeCode
    case geminiCLI
    case antigravity
    case grokCLI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeDesktop: return "Claude Desktop"
        case .claudeCode: return "Claude Code"
        case .geminiCLI: return "Gemini CLI"
        case .antigravity: return "Antigravity"
        case .grokCLI: return "Grok CLI"
        }
    }

    public var configFormatTitle: String {
        switch self {
        case .grokCLI: return "TOML"
        default: return "JSON"
        }
    }

    public var defaultRelativeConfigPath: String {
        switch self {
        case .claudeDesktop: return "Library/Application Support/Claude/claude_desktop_config.json"
        case .claudeCode: return ".claude.json"
        case .geminiCLI: return ".gemini/settings.json"
        case .antigravity: return ".gemini/config/mcp_config.json"
        case .grokCLI: return ".grok/config.toml"
        }
    }

    public var legacyRelativeConfigPath: String? {
        switch self {
        case .antigravity: return ".gemini/antigravity/mcp_config.json"
        default: return nil
        }
    }

    public var supportsCLIInstallCommand: Bool {
        self == .claudeCode || self == .grokCLI
    }

    public func resolvedConfigPath(homeDirectory: String = NSHomeDirectory()) -> String {
        (homeDirectory as NSString).appendingPathComponent(defaultRelativeConfigPath)
    }

    public func resolvedLegacyConfigPath(homeDirectory: String = NSHomeDirectory()) -> String? {
        guard let rel = legacyRelativeConfigPath else { return nil }
        return (homeDirectory as NSString).appendingPathComponent(rel)
    }
}

public enum MCPTransportSnippetMode: String, CaseIterable, Identifiable, Sendable {
    case stdio
    case streamableHTTP

    public var id: String { rawValue }
}

public enum MCPConfigMergeError: Error, Equatable, Sendable {
    case invalidJSON(String)
    case nonObjectJSONRoot
    case nonObjectMCPServers
    case invalidTOML(String)
    case duplicateTOMLSection

    public var message: String {
        switch self {
        case .invalidJSON(let detail):
            return "Existing config is not valid JSON (\(detail)). Refused to overwrite."
        case .nonObjectJSONRoot:
            return "Existing JSON root must be an object. Refused to overwrite."
        case .nonObjectMCPServers:
            return "Existing 'mcpServers' field is not a JSON object. Refused to overwrite."
        case .invalidTOML(let detail):
            return "Existing TOML config could not be safely parsed (\(detail)). Refused to overwrite."
        case .duplicateTOMLSection:
            return "Existing TOML config already has duplicate GlassGrid You server sections. Resolve manually first."
        }
    }
}

/// Pure, fail-closed JSON & surgical line-preserving TOML configuration mergers and snippet generators.
public enum MCPClientConfigMerger {
    public static let serverKey = "glassgrid-you"
    public static let defaultBinaryPath = "/Applications/GlassGrid You.app/Contents/MacOS/glassgrid"

    public static func shellQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\""
    }

    public static func stdioServerObject(binaryPath: String) -> [String: Any] {
        [
            "command": binaryPath,
            "args": ["mcp"]
        ]
    }

    public static func httpServerObject(for client: MCPClientKind, port: Int, bearerToken: String) -> [String: Any] {
        let url = "http://127.0.0.1:\(port)/mcp"
        let headers = ["Authorization": "Bearer \(bearerToken)"]
        switch client {
        case .geminiCLI:
            return ["httpUrl": url, "headers": headers]
        case .claudeCode:
            return ["type": "http", "url": url, "headers": headers]
        default:
            return ["url": url, "headers": headers]
        }
    }

    public static func generateSnippet(
        for client: MCPClientKind,
        mode: MCPTransportSnippetMode,
        binaryPath: String,
        httpPort: Int,
        bearerToken: String
    ) -> String {
        switch client {
        case .grokCLI:
            let table = buildTOMLServerBlock(
                serverKey: serverKey,
                mode: mode,
                binaryPath: binaryPath,
                httpPort: httpPort,
                bearerToken: bearerToken
            )
            return table
        default:
            let serverObj: [String: Any] = (mode == .stdio)
                ? stdioServerObject(binaryPath: binaryPath)
                : httpServerObject(for: client, port: httpPort, bearerToken: bearerToken)
            let root: [String: Any] = ["mcpServers": [serverKey: serverObj]]
            if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "{}"
        }
    }

    public static func generateCLISnippet(
        for client: MCPClientKind,
        mode: MCPTransportSnippetMode,
        binaryPath: String,
        httpPort: Int,
        bearerToken: String
    ) -> String? {
        switch client {
        case .claudeCode:
            switch mode {
            case .stdio:
                return "claude mcp add --transport stdio --scope user \(serverKey) -- \(shellQuoted(binaryPath)) mcp"
            case .streamableHTTP:
                return "claude mcp add --transport http --scope user \(serverKey) \"http://127.0.0.1:\(httpPort)/mcp\" --header \"Authorization: Bearer \(bearerToken)\""
            }
        case .grokCLI:
            switch mode {
            case .stdio:
                return "grok mcp add \(serverKey) -- \(shellQuoted(binaryPath)) mcp"
            case .streamableHTTP:
                return "grok mcp add --transport http \(serverKey) \"http://127.0.0.1:\(httpPort)/mcp\" --header \"Authorization: Bearer \(bearerToken)\""
            }
        default:
            return nil
        }
    }

    // MARK: - JSON Merge / Inspect / Remove

    public static func mergeJSONConfig(
        existing: Data?,
        serverKey: String = MCPClientConfigMerger.serverKey,
        serverObject: [String: Any]
    ) throws -> Data {
        var root: [String: Any]
        if let existing, !existing.isEmpty {
            let trimmed = String(data: existing, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                root = [:]
            } else {
                let rawObj: Any
                do {
                    rawObj = try JSONSerialization.jsonObject(with: existing, options: [])
                } catch {
                    throw MCPConfigMergeError.invalidJSON(error.localizedDescription)
                }
                guard let dict = rawObj as? [String: Any] else {
                    throw MCPConfigMergeError.nonObjectJSONRoot
                }
                root = dict
            }
        } else {
            root = [:]
        }

        var servers: [String: Any]
        if let existingServers = root["mcpServers"] {
            guard let dict = existingServers as? [String: Any] else {
                throw MCPConfigMergeError.nonObjectMCPServers
            }
            servers = dict
        } else {
            servers = [:]
        }

        servers[serverKey] = serverObject
        root["mcpServers"] = servers

        var out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        out.append(0x0A)
        return out
    }

    public static func removeJSONConfig(
        existing: Data,
        serverKey: String = MCPClientConfigMerger.serverKey
    ) throws -> Data {
        let rawObj: Any
        do {
            rawObj = try JSONSerialization.jsonObject(with: existing, options: [])
        } catch {
            throw MCPConfigMergeError.invalidJSON(error.localizedDescription)
        }
        guard var root = rawObj as? [String: Any] else {
            throw MCPConfigMergeError.nonObjectJSONRoot
        }
        if let existingServers = root["mcpServers"] {
            guard var dict = existingServers as? [String: Any] else {
                throw MCPConfigMergeError.nonObjectMCPServers
            }
            dict.removeValue(forKey: serverKey)
            root["mcpServers"] = dict
        }
        var out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        out.append(0x0A)
        return out
    }

    public static func inspectJSONServer(
        existing: Data,
        serverKey: String = MCPClientConfigMerger.serverKey
    ) -> [String: Any]? {
        guard let rawObj = try? JSONSerialization.jsonObject(with: existing, options: []),
              let root = rawObj as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let entry = servers[serverKey] as? [String: Any] else {
            return nil
        }
        return entry
    }

    // MARK: - Surgical Line-Preserving TOML Merge / Remove (Grok CLI)

    public static func mergeTOMLConfig(
        existing: String?,
        serverKey: String = MCPClientConfigMerger.serverKey,
        mode: MCPTransportSnippetMode = .stdio,
        binaryPath: String,
        httpPort: Int = 41773,
        bearerToken: String = ""
    ) throws -> String {
        let newBlock = buildTOMLServerBlock(
            serverKey: serverKey,
            mode: mode,
            binaryPath: binaryPath,
            httpPort: httpPort,
            bearerToken: bearerToken
        )

        guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return newBlock + "\n"
        }

        let stripped = try removeTOMLSectionRanges(from: existing, serverKey: serverKey, failOnDuplicatePrimary: true)
        var base = stripped.result
        if !base.isEmpty && !base.hasSuffix("\n") {
            base += "\n"
        }
        if !base.isEmpty && !base.hasSuffix("\n\n") {
            base += "\n"
        }
        return base + newBlock + "\n"
    }

    public static func removeTOMLConfig(
        existing: String,
        serverKey: String = MCPClientConfigMerger.serverKey
    ) throws -> String {
        let stripped = try removeTOMLSectionRanges(from: existing, serverKey: serverKey, failOnDuplicatePrimary: false)
        var result = stripped.result
        while result.hasSuffix("\n\n\n") {
            result.removeLast()
        }
        if !result.isEmpty && !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    public static func inspectTOMLServerConfigured(
        existing: String,
        serverKey: String = MCPClientConfigMerger.serverKey,
        expectedBinaryPath: String
    ) -> (present: Bool, matchesBinary: Bool) {
        guard let sections = try? parseTOMLSections(existing) else {
            return (false, false)
        }
        guard let primary = sections.first(where: { isTargetSection($0.headerPath, serverKey: serverKey) == .primary }) else {
            return (false, false)
        }
        let escapedExpected = escapeTOMLBasicString(expectedBinaryPath)
        let matchesCommand = primary.bodyLines.contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("command") && (t.contains("\"\(escapedExpected)\"") || t.contains("'\(expectedBinaryPath)'"))
        }
        let matchesArgs = primary.bodyLines.contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("args") && (t.contains("\"mcp\"") || t.contains("'mcp'"))
        }
        return (true, matchesCommand && matchesArgs)
    }

    private enum TargetSectionMatch {
        case none
        case primary
        case subtable
    }

    private struct TOMLSection {
        let startLine: Int
        let endLine: Int
        let headerPath: [String]
        let bodyLines: [String]
    }

    private static func buildTOMLServerBlock(
        serverKey: String,
        mode: MCPTransportSnippetMode,
        binaryPath: String,
        httpPort: Int,
        bearerToken: String
    ) -> String {
        let header = "[mcp_servers.\(serverKey)]"
        switch mode {
        case .stdio:
            return """
            \(header)
            command = "\(escapeTOMLBasicString(binaryPath))"
            args = ["mcp"]
            """
        case .streamableHTTP:
            return """
            \(header)
            url = "http://127.0.0.1:\(httpPort)/mcp"

            [mcp_servers.\(serverKey).headers]
            Authorization = "Bearer \(escapeTOMLBasicString(bearerToken))"
            """
        }
    }

    private static func escapeTOMLBasicString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func removeTOMLSectionRanges(
        from source: String,
        serverKey: String,
        failOnDuplicatePrimary: Bool
    ) throws -> (result: String, removedCount: Int) {
        let lines = source.components(separatedBy: "\n")
        let sections = try parseTOMLSections(source)
        let primaryMatches = sections.filter { isTargetSection($0.headerPath, serverKey: serverKey) == .primary }
        if failOnDuplicatePrimary && primaryMatches.count > 1 {
            throw MCPConfigMergeError.duplicateTOMLSection
        }

        var linesToDrop = IndexSet()
        var removedCount = 0
        for section in sections where isTargetSection(section.headerPath, serverKey: serverKey) != .none {
            removedCount += 1
            for idx in section.startLine...section.endLine {
                linesToDrop.insert(idx)
            }
        }

        var kept: [String] = []
        kept.reserveCapacity(lines.count)
        for (idx, line) in lines.enumerated() where !linesToDrop.contains(idx) {
            kept.append(line)
        }
        // Trim trailing empty lines left behind
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.removeLast()
        }
        return (kept.joined(separator: "\n"), removedCount)
    }

    private static func isTargetSection(_ path: [String], serverKey: String) -> TargetSectionMatch {
        guard path.count >= 2, path[0] == "mcp_servers", path[1] == serverKey else {
            return .none
        }
        return path.count == 2 ? .primary : .subtable
    }

    /// Scans TOML line-by-line while tracking multiline `"""` / `'''` strings and `[...]` brackets so
    /// bracketed strings inside multiline values are never mistaken for table headers.
    private static func parseTOMLSections(_ source: String) throws -> [TOMLSection] {
        let lines = source.components(separatedBy: "\n")
        var inTripleDouble = false
        var inTripleSingle = false
        var bracketDepth = 0

        var sections: [(startLine: Int, path: [String])] = []

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inTripleDouble && !inTripleSingle && bracketDepth == 0 {
                if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") {
                    if let path = parseTableHeader(trimmed) {
                        sections.append((lineIndex, path))
                    }
                }
            }
            scanTOMLState(
                line: line,
                inTripleDouble: &inTripleDouble,
                inTripleSingle: &inTripleSingle,
                bracketDepth: &bracketDepth
            )
        }

        if inTripleDouble || inTripleSingle {
            throw MCPConfigMergeError.invalidTOML("unterminated multiline string literal")
        }

        var result: [TOMLSection] = []
        for i in sections.indices {
            let start = sections[i].startLine
            let end = (i + 1 < sections.count) ? (sections[i + 1].startLine - 1) : (lines.count - 1)
            let body = (start + 1 <= end) ? Array(lines[(start + 1)...end]) : []
            result.append(TOMLSection(startLine: start, endLine: end, headerPath: sections[i].path, bodyLines: body))
        }
        return result
    }

    private static func parseTableHeader(_ trimmedLine: String) -> [String]? {
        guard trimmedLine.hasPrefix("[") else { return nil }
        var inner = ""
        var quote: Character? = nil
        var escaped = false
        var foundClose = false
        var restAfterClose = ""

        var idx = trimmedLine.index(after: trimmedLine.startIndex)
        while idx < trimmedLine.endIndex {
            let ch = trimmedLine[idx]
            if let q = quote {
                inner.append(ch)
                if q == "\"" && !escaped && ch == "\\" {
                    escaped = true
                } else {
                    if !escaped && ch == q {
                        quote = nil
                    }
                    escaped = false
                }
            } else {
                if ch == "\"" || ch == "'" {
                    quote = ch
                    inner.append(ch)
                } else if ch == "]" {
                    foundClose = true
                    let after = trimmedLine.index(after: idx)
                    restAfterClose = String(trimmedLine[after...]).trimmingCharacters(in: .whitespaces)
                    break
                } else {
                    inner.append(ch)
                }
            }
            idx = trimmedLine.index(after: idx)
        }

        guard foundClose else { return nil }
        if !restAfterClose.isEmpty && !restAfterClose.hasPrefix("#") {
            return nil
        }
        return parseDottedKeyPath(inner)
    }

    private static func parseDottedKeyPath(_ raw: String) -> [String]? {
        var segments: [String] = []
        var current = ""
        var quote: Character? = nil
        var escaped = false

        for ch in raw {
            if let q = quote {
                if q == "\"" && !escaped && ch == "\\" {
                    escaped = true
                } else if !escaped && ch == q {
                    quote = nil
                } else {
                    current.append(ch)
                    escaped = false
                }
            } else {
                if ch == "\"" || ch == "'" {
                    quote = ch
                } else if ch == "." {
                    let seg = current.trimmingCharacters(in: .whitespaces)
                    guard !seg.isEmpty else { return nil }
                    segments.append(seg)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
        }
        guard quote == nil else { return nil }
        let last = current.trimmingCharacters(in: .whitespaces)
        guard !last.isEmpty else { return nil }
        segments.append(last)
        return segments
    }

    private static func scanTOMLState(
        line: String,
        inTripleDouble: inout Bool,
        inTripleSingle: inout Bool,
        bracketDepth: inout Int
    ) {
        let chars = Array(line)
        var i = 0
        var inSingleLineDouble = false
        var inSingleLineSingle = false

        while i < chars.count {
            if inTripleDouble {
                if chars[i] == "\\" {
                    i += 2
                    continue
                }
                if i + 2 < chars.count && chars[i] == "\"" && chars[i + 1] == "\"" && chars[i + 2] == "\"" {
                    inTripleDouble = false
                    i += 3
                    continue
                }
                i += 1
                continue
            }
            if inTripleSingle {
                if i + 2 < chars.count && chars[i] == "'" && chars[i + 1] == "'" && chars[i + 2] == "'" {
                    inTripleSingle = false
                    i += 3
                    continue
                }
                i += 1
                continue
            }
            if inSingleLineDouble {
                if chars[i] == "\\" {
                    i += 2
                    continue
                }
                if chars[i] == "\"" {
                    inSingleLineDouble = false
                }
                i += 1
                continue
            }
            if inSingleLineSingle {
                if chars[i] == "'" {
                    inSingleLineSingle = false
                }
                i += 1
                continue
            }

            let ch = chars[i]
            if ch == "#" {
                break
            }
            if i + 2 < chars.count && ch == "\"" && chars[i + 1] == "\"" && chars[i + 2] == "\"" {
                inTripleDouble = true
                i += 3
                continue
            }
            if i + 2 < chars.count && ch == "'" && chars[i + 1] == "'" && chars[i + 2] == "'" {
                inTripleSingle = true
                i += 3
                continue
            }
            if ch == "\"" {
                inSingleLineDouble = true
                i += 1
                continue
            }
            if ch == "'" {
                inSingleLineSingle = true
                i += 1
                continue
            }
            if ch == "[" {
                bracketDepth += 1
            } else if ch == "]" && bracketDepth > 0 {
                bracketDepth -= 1
            }
            i += 1
        }
    }
}
