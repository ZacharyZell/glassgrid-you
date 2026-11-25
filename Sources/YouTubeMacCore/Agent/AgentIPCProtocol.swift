import Darwin
import Foundation

/// Resolved Unix Domain Socket location honoring Darwin `sockaddr_un.sun_path` (`<= 103` UTF-8 bytes).
public struct AgentSocketLocation: Equatable, Sendable {
    public let directoryPath: String
    public let socketPath: String
    public let usedTempFallback: Bool

    public init(directoryPath: String, socketPath: String, usedTempFallback: Bool) {
        self.directoryPath = directoryPath
        self.socketPath = socketPath
        self.usedTempFallback = usedTempFallback
    }
}

public enum AgentSocketPath {
    public static let maxSunPathUTF8Bytes = 103

    /// Resolves the deterministic Unix socket path shared by GlassGrid You and `glassgrid` CLI.
    /// Uses `confstr(_CS_DARWIN_USER_TEMP_DIR)` fallback only if the primary Application Support path exceeds 103 UTF-8 bytes.
    public static func resolve(
        homeDirectory: String? = nil,
        overridePath: String? = nil,
        darwinUserTempDir: String? = nil
    ) -> AgentSocketLocation {
        if let overridePath, !overridePath.isEmpty {
            let trimmed = overridePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.utf8.count <= maxSunPathUTF8Bytes {
                let dir = (trimmed as NSString).deletingLastPathComponent
                return AgentSocketLocation(directoryPath: dir, socketPath: trimmed, usedTempFallback: false)
            }
        }

        let home = homeDirectory ?? NSHomeDirectory()
        let primaryDir = ((home as NSString)
            .appendingPathComponent("Library/Application Support"))
            .appending("/GlassGridYou")
        let primarySocket = primaryDir + "/v1.sock"
        if primarySocket.utf8.count <= maxSunPathUTF8Bytes {
            return AgentSocketLocation(directoryPath: primaryDir, socketPath: primarySocket, usedTempFallback: false)
        }

        let userTempBase = darwinUserTempDir ?? resolveDarwinUserTempDir()
        let cleanedTemp = userTempBase.hasSuffix("/") ? String(userTempBase.dropLast()) : userTempBase
        let fallbackDir = cleanedTemp + "/gg"
        let fallbackSocket = fallbackDir + "/v1.sock"
        return AgentSocketLocation(directoryPath: fallbackDir, socketPath: fallbackSocket, usedTempFallback: true)
    }

    public static func resolveDarwinUserTempDir() -> String {
        let len = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        if len > 0 {
            var buf = [CChar](repeating: 0, count: len)
            if confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, len) > 0 {
                let raw = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if !raw.isEmpty {
                    return raw
                }
            }
        }
        return NSTemporaryDirectory()
    }
}

/// Wire envelope carried over the `0600` Unix Domain Socket between `glassgrid` and GlassGrid You.
public enum AgentIPCRequestKind: Codable, Equatable, Sendable {
    case mcpJSONRPC(payloadUTF8: String, clientName: String)
    case toolCall(toolName: String, arguments: [String: JSONValue], source: AgentCommandSource, clientName: String)
    case readResource(uri: String, source: AgentCommandSource, clientName: String)
}

public struct AgentIPCRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: AgentIPCRequestKind

    public init(id: UUID = UUID(), kind: AgentIPCRequestKind) {
        self.id = id
        self.kind = kind
    }
}

public enum AgentIPCResponseKind: Codable, Equatable, Sendable {
    case mcpNoResponse
    case mcpReply(payloadUTF8: String)
    case commandOutcome(AgentCommandOutcome)
    case resourceOutcome(AgentResourceOutcome)
    case error(code: String, message: String)
}

public struct AgentIPCResponse: Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: AgentIPCResponseKind

    public init(id: UUID, kind: AgentIPCResponseKind) {
        self.id = id
        self.kind = kind
    }
}

public enum AgentIPCFrameError: Error, Equatable, Sendable {
    case emptyFrame
    case frameTooLarge(Int)
}

/// Length-prefixed (`4-byte big-endian UInt32` + JSON payload) framing codec capped at 256 KiB.
public enum AgentIPCFrameCodec {
    public static let maxFrameBytes = 262_144

    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else {
            throw AgentIPCFrameError.emptyFrame
        }
        guard payload.count <= maxFrameBytes else {
            throw AgentIPCFrameError.frameTooLarge(payload.count)
        }
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        return framed
    }

    /// Consumes as many complete frames as available from `buffer`.
    public static func extractFrames(from buffer: inout Data) throws -> [Data] {
        var frames: [Data] = []
        while buffer.count >= 4 {
            let b0 = UInt32(buffer[buffer.startIndex]) << 24
            let b1 = UInt32(buffer[buffer.startIndex + 1]) << 16
            let b2 = UInt32(buffer[buffer.startIndex + 2]) << 8
            let b3 = UInt32(buffer[buffer.startIndex + 3])
            let length = Int(b0 | b1 | b2 | b3)

            guard length > 0 else {
                throw AgentIPCFrameError.emptyFrame
            }
            guard length <= maxFrameBytes else {
                throw AgentIPCFrameError.frameTooLarge(length)
            }
            guard buffer.count >= 4 + length else {
                break
            }
            let payloadStart = buffer.index(buffer.startIndex, offsetBy: 4)
            let payloadEnd = buffer.index(payloadStart, offsetBy: length)
            frames.append(Data(buffer[payloadStart..<payloadEnd]))
            buffer.removeSubrange(buffer.startIndex..<payloadEnd)
        }
        return frames
    }
}
