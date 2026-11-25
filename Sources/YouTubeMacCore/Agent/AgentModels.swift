import Foundation

/// Privilege tier governing what external AI agents and assistants are permitted to execute.
public enum AgentPermissionLevel: String, CaseIterable, Identifiable, Codable, Comparable, Sendable {
    case readOnly
    case playbackAndNavigation
    case fullControl

    public var id: String { rawValue }

    public var rank: Int {
        switch self {
        case .readOnly: return 1
        case .playbackAndNavigation: return 2
        case .fullControl: return 3
        }
    }

    public static func < (lhs: AgentPermissionLevel, rhs: AgentPermissionLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    public var title: String {
        switch self {
        case .readOnly:
            return "Read-Only"
        case .playbackAndNavigation:
            return "Playback & Navigation"
        case .fullControl:
            return "Full Control"
        }
    }

    public var subtitle: String {
        switch self {
        case .readOnly:
            return "Inspect now-playing info, chapters, video description, tabs, Multiview, and services."
        case .playbackAndNavigation:
            return "Play, pause, seek, search YouTube, open services, Multiview audio/layout, Mini-Player, and appearance."
        case .fullControl:
            return "Also close/sleep tabs, save/delete Multiview presets, manage pins/folders, windows, and distraction-free settings."
        }
    }
}

/// Originating client surface for auditing and activity logging.
public enum AgentCommandSource: String, Codable, Sendable {
    case mcpStdio = "mcp_stdio"
    case mcpHTTP = "mcp_http"
    case cli = "cli"
    case appIntents = "siri_shortcuts"
    case urlAction = "url_action"

    public var badgeTitle: String {
        switch self {
        case .mcpStdio: return "MCP"
        case .mcpHTTP: return "HTTP"
        case .cli: return "CLI"
        case .appIntents: return "Siri"
        case .urlAction: return "URL"
        }
    }
}

/// Request metadata passed into `AgentCommandExecutor`.
public struct AgentRequestContext: Codable, Equatable, Sendable {
    public let source: AgentCommandSource
    public let clientName: String
    public let peerPID: Int32?

    public init(source: AgentCommandSource, clientName: String = "", peerPID: Int32? = nil) {
        self.source = source
        self.clientName = clientName
        self.peerPID = peerPID
    }
}

/// Single entry in the bounded Settings → AI & Automation live activity log.
public struct AgentActivityEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let source: AgentCommandSource
    public let action: String
    public let summary: String
    public let succeeded: Bool
    public let errorCode: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: AgentCommandSource,
        action: String,
        summary: String,
        succeeded: Bool,
        errorCode: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.action = action
        self.summary = summary
        self.succeeded = succeeded
        self.errorCode = errorCode
    }
}

/// Canonical result returned by `AgentCommandExecutor.execute`.
public struct AgentCommandOutcome: Codable, Equatable, Sendable {
    public let ok: Bool
    public let message: String
    public let errorCode: String?
    public let data: JSONValue?

    public init(ok: Bool, message: String, errorCode: String? = nil, data: JSONValue? = nil) {
        self.ok = ok
        self.message = message
        self.errorCode = errorCode
        self.data = data
    }

    public static func success(_ message: String, data: JSONValue? = nil) -> AgentCommandOutcome {
        AgentCommandOutcome(ok: true, message: message, errorCode: nil, data: data)
    }

    public static func failure(code: String, message: String, data: JSONValue? = nil) -> AgentCommandOutcome {
        AgentCommandOutcome(ok: false, message: message, errorCode: code, data: data)
    }

    public func toJSONValue() -> JSONValue {
        var obj: [String: JSONValue] = [
            "ok": .bool(ok),
            "message": .string(message)
        ]
        if let errorCode {
            obj["errorCode"] = .string(errorCode)
        }
        if let data {
            obj["data"] = data
        }
        return .object(obj)
    }
}

/// Canonical result returned by `AgentCommandExecutor.readResource`.
public struct AgentResourceOutcome: Codable, Equatable, Sendable {
    public let uri: String
    public let mimeType: String
    public let text: String?
    public let errorCode: String?
    public let errorMessage: String?

    public init(
        uri: String,
        mimeType: String = "application/json",
        text: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    public static func success(uri: String, mimeType: String = "application/json", text: String) -> AgentResourceOutcome {
        AgentResourceOutcome(uri: uri, mimeType: mimeType, text: text, errorCode: nil, errorMessage: nil)
    }

    public static func failure(uri: String, code: String, message: String) -> AgentResourceOutcome {
        AgentResourceOutcome(uri: uri, mimeType: "application/json", text: nil, errorCode: code, errorMessage: message)
    }
}

/// Runtime-agnostic command executor implemented by `AgentBridgeController` in the GUI app and mocked in unit tests.
public protocol AgentCommandExecutor: Sendable {
    func isAutomationEnabled() async -> Bool
    func currentPermissionLevel() async -> AgentPermissionLevel
    func execute(toolName: String, arguments: [String: JSONValue], context: AgentRequestContext) async -> AgentCommandOutcome
    func readResource(uri: String, context: AgentRequestContext) async -> AgentResourceOutcome
}
