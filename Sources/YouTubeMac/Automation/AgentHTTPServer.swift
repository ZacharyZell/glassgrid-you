import Foundation
import Network
import YouTubeMacCore

public enum AgentHTTPServerStatus: Equatable, Sendable {
    case disabled
    case starting(port: Int)
    case listening(port: Int)
    case failed(port: Int, reason: String)

    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

/// Queue-confined local `127.0.0.1` Streamable HTTP MCP server (`NWListener` + `NWConnection`).
/// All non-`Sendable` `Network.framework` objects live strictly on `queue` and communicate across Swift concurrency using integer connection IDs.
public final class AgentHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.glassgridyou.agent.http")
    private let executor: any AgentCommandExecutor
    private let protocolHandler = MCPProtocolHandler()
    private let onStatusChange: @MainActor @Sendable (AgentHTTPServerStatus) -> Void

    private var listener: NWListener?
    private var activePort: Int = 41773
    private var activeBearerToken: String = ""
    private var nextConnectionID: Int = 1
    private var connections: [Int: HTTPClientState] = [:]
    private var sessionStore = AgentHTTPSessionStore(capacity: 64, ttlSeconds: 24 * 60 * 60)
    private var rateLimiter = AgentRateLimiter(capacity: 20, requestsPerMinute: 60)
    private let maxConcurrentConnections = 16

    private final class HTTPClientState {
        let id: Int
        let connection: NWConnection
        var buffer = Data()
        var timeoutItem: DispatchWorkItem?
        var completed = false

        init(id: Int, connection: NWConnection) {
            self.id = id
            self.connection = connection
        }
    }

    public init(
        executor: any AgentCommandExecutor,
        onStatusChange: @escaping @MainActor @Sendable (AgentHTTPServerStatus) -> Void
    ) {
        self.executor = executor
        self.onStatusChange = onStatusChange
    }

    public func start(port: Int, bearerToken: String) {
        let clampedPort = min(max(port, 1024), 65535)
        queue.async { [weak self] in
            self?.startOnQueue(port: clampedPort, bearerToken: bearerToken)
        }
    }

    public func updateBearerToken(_ token: String) {
        queue.async { [weak self] in
            self?.activeBearerToken = token
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue(publishDisabled: true)
        }
    }

    public func stopSynchronously() {
        queue.sync {
            stopOnQueue(publishDisabled: true)
        }
    }

    private func startOnQueue(port: Int, bearerToken: String) {
        stopOnQueue(publishDisabled: false)
        activePort = port
        activeBearerToken = bearerToken

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            publishStatus(.failed(port: port, reason: "Invalid port \(port)."))
            return
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true

        let newListener: NWListener
        do {
            // Never pass duplicate `on: nwPort` when `requiredLocalEndpoint` already specifies the port (avoids macOS EINVAL).
            newListener = try NWListener(using: parameters)
        } catch {
            publishStatus(.failed(port: port, reason: error.localizedDescription))
            return
        }

        listener = newListener
        publishStatus(.starting(port: port))

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.publishStatus(.listening(port: port))
            case .failed(let error):
                self.publishStatus(.failed(port: port, reason: error.localizedDescription))
                self.stopOnQueue(publishDisabled: false)
            case .waiting(let error):
                self.publishStatus(.failed(port: port, reason: error.localizedDescription))
            case .cancelled:
                break
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.acceptConnection(connection)
        }

        newListener.start(queue: queue)
    }

    private func stopOnQueue(publishDisabled: Bool) {
        if let listener {
            self.listener = nil
            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            listener.cancel()
        }
        for (_, state) in connections {
            state.timeoutItem?.cancel()
            state.connection.cancel()
        }
        connections.removeAll()
        if publishDisabled {
            publishStatus(.disabled)
        }
    }

    private func acceptConnection(_ connection: NWConnection) {
        guard connections.count < maxConcurrentConnections else {
            connection.cancel()
            return
        }

        let connID = nextConnectionID
        nextConnectionID &+= 1
        let client = HTTPClientState(id: connID, connection: connection)
        connections[connID] = client

        let timeout = DispatchWorkItem { [weak self] in
            self?.closeConnection(id: connID)
        }
        client.timeoutItem = timeout
        queue.asyncAfter(deadline: .now() + .seconds(10), execute: timeout)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.closeConnection(id: connID)
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveNextChunk(for: connID)
    }

    private func receiveNextChunk(for connID: Int) {
        guard let client = connections[connID], !client.completed else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let client = self.connections[connID], !client.completed else { return }

            if let data, !data.isEmpty {
                if client.buffer.count + data.count > AgentHTTPParser.maxHeaderBytes + AgentHTTPParser.maxBodyBytes + 4 {
                    self.sendAndClose(
                        connID: connID,
                        payload: AgentHTTPResponseSerializer.jsonError(statusCode: 413, message: "Payload Too Large")
                    )
                    return
                }
                client.buffer.append(data)
            }

            switch AgentHTTPParser.parse(buffer: client.buffer) {
            case .parsed(let request):
                client.completed = true
                self.handleValidatedHTTPRequest(request, connID: connID)
            case .error(let statusCode, let message):
                client.completed = true
                self.sendAndClose(
                    connID: connID,
                    payload: AgentHTTPResponseSerializer.jsonError(statusCode: statusCode, message: message)
                )
            case .incomplete:
                if isComplete || error != nil {
                    self.closeConnection(id: connID)
                } else {
                    self.receiveNextChunk(for: connID)
                }
            }
        }
    }

    private func handleValidatedHTTPRequest(_ request: ParsedHTTPRequest, connID: Int) {
        guard rateLimiter.tryConsume() else {
            sendAndClose(
                connID: connID,
                payload: AgentHTTPResponseSerializer.jsonError(
                    statusCode: 429,
                    message: "Rate limit exceeded.",
                    headers: ["Retry-After": "1"]
                )
            )
            return
        }

        switch AgentHTTPRequestValidator.validate(request, expectedPort: activePort, expectedBearerToken: activeBearerToken) {
        case .rejected(let statusCode, let message, let extraHeaders):
            sendAndClose(
                connID: connID,
                payload: AgentHTTPResponseSerializer.jsonError(
                    statusCode: statusCode,
                    message: message,
                    headers: extraHeaders
                )
            )

        case .valid(let protocolVersion):
            if request.method == "DELETE" {
                guard let sid = request.header("mcp-session-id"), !sid.isEmpty else {
                    sendAndClose(
                        connID: connID,
                        payload: AgentHTTPResponseSerializer.jsonError(statusCode: 400, message: "Missing Mcp-Session-Id header")
                    )
                    return
                }
                if sessionStore.delete(sid) {
                    sendAndClose(
                        connID: connID,
                        payload: AgentHTTPResponseSerializer.serialize(
                            statusCode: 204,
                            headers: ["MCP-Protocol-Version": protocolVersion]
                        )
                    )
                } else {
                    sendAndClose(
                        connID: connID,
                        payload: AgentHTTPResponseSerializer.jsonError(statusCode: 404, message: "Session not found")
                    )
                }
                return
            }

            // POST /mcp
            let parsedObj = (try? JSONValue.decode(from: request.body))?.objectValue
            let method = parsedObj?["method"]?.stringValue
            let isInitialize = (method == "initialize")
            let incomingSessionID = request.header("mcp-session-id")

            var responseSessionID: String?
            if isInitialize {
                responseSessionID = sessionStore.createSession()
            } else if let incomingSessionID, !incomingSessionID.isEmpty {
                guard sessionStore.validateAndTouch(incomingSessionID) else {
                    sendAndClose(
                        connID: connID,
                        payload: AgentHTTPResponseSerializer.jsonError(statusCode: 404, message: "Unknown or expired Mcp-Session-Id")
                    )
                    return
                }
                responseSessionID = incomingSessionID
            }

            let executor = self.executor
            let protocolHandler = self.protocolHandler
            let bodyData = request.body

            Task { [weak self] in
                let ctx = AgentRequestContext(source: .mcpHTTP, clientName: "streamable-http", peerPID: nil)
                let result = await protocolHandler.handleMessageData(
                    bodyData,
                    httpProtocolVersion: protocolVersion,
                    context: ctx,
                    executor: executor
                )

                var headers: [String: String] = ["MCP-Protocol-Version": protocolVersion]
                if let responseSessionID {
                    headers["Mcp-Session-Id"] = responseSessionID
                }

                let responsePayload: Data
                switch result {
                case .noResponse:
                    responsePayload = AgentHTTPResponseSerializer.serialize(statusCode: 202, headers: headers, body: Data())
                case .batchRejected:
                    responsePayload = AgentHTTPResponseSerializer.jsonError(
                        statusCode: 400,
                        code: -32600,
                        message: "JSON-RPC batching is not allowed in MCP 2025-06-18.",
                        headers: headers
                    )
                case .reply(let jsonBody):
                    headers["Content-Type"] = "application/json; charset=utf-8"
                    responsePayload = AgentHTTPResponseSerializer.serialize(statusCode: 200, headers: headers, body: jsonBody)
                }

                self?.queue.async { [weak self] in
                    self?.sendAndClose(connID: connID, payload: responsePayload)
                }
            }
        }
    }

    private func sendAndClose(connID: Int, payload: Data) {
        guard let client = connections[connID] else { return }
        client.timeoutItem?.cancel()
        client.connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            self?.closeConnection(id: connID)
        })
    }

    private func closeConnection(id connID: Int) {
        guard let client = connections.removeValue(forKey: connID) else { return }
        client.timeoutItem?.cancel()
        client.connection.stateUpdateHandler = nil
        client.connection.cancel()
    }

    private func publishStatus(_ status: AgentHTTPServerStatus) {
        let callback = onStatusChange
        Task { @MainActor in
            callback(status)
        }
    }
}
