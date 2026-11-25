import Darwin
import Foundation
import YouTubeMacCore

public enum AgentUnixSocketStatus: Equatable, Sendable {
    case stopped
    case listening(path: String)
    case anotherInstanceActive(path: String)
    case failed(String)

    public var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .listening: return "Listening"
        case .anotherInstanceActive: return "Active in Another Window/Instance"
        case .failed(let reason): return "Error: \(reason)"
        }
    }
}

/// Hardened POSIX `AF_UNIX` `SOCK_STREAM` server confined to a dedicated serial `DispatchQueue`.
/// Uses `0700` parent directory, `0600` socket permissions, non-blocking stale-socket probe,
/// `SO_NOSIGPIPE`, `getpeereid` EUID check, 4-byte BE framing, and inode-verified `unlink()` on stop.
public final class AgentUnixSocketServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.glassgridyou.agent.unixsocket")
    private let executor: any AgentCommandExecutor
    private let protocolHandler = MCPProtocolHandler()
    private let onStatusChange: @MainActor @Sendable (AgentUnixSocketStatus) -> Void

    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var ownedSocketPath: String?
    private var ownedInode: ino_t?
    private var clients: [Int32: ClientConnection] = [:]
    private let maxConcurrentClients = 16

    private final class ClientConnection {
        let fd: Int32
        let peerPID: Int32?
        var source: DispatchSourceRead?
        var timeoutWorkItem: DispatchWorkItem?
        var buffer = Data()

        init(fd: Int32, peerPID: Int32?) {
            self.fd = fd
            self.peerPID = peerPID
        }
    }

    public init(
        executor: any AgentCommandExecutor,
        onStatusChange: @escaping @MainActor @Sendable (AgentUnixSocketStatus) -> Void
    ) {
        self.executor = executor
        self.onStatusChange = onStatusChange
    }

    public func start(overridePath: String? = ProcessInfo.processInfo.environment["GLASSGRID_SOCKET_PATH"]) {
        queue.async { [weak self] in
            self?.startOnQueue(overridePath: overridePath)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    /// Synchronous shutdown helper for `applicationWillTerminate()` so `v1.sock` is unlinked before process exit.
    public func stopSynchronously() {
        queue.sync {
            stopOnQueue()
        }
    }

    private func startOnQueue(overridePath: String?) {
        if listenerFD >= 0 {
            return
        }

        let location = AgentSocketPath.resolve(overridePath: overridePath)
        let dirURL = URL(fileURLWithPath: location.directoryPath, isDirectory: true)
        do {
            try AgentSecureFileIO.ensurePrivateDirectory(dirURL)
        } catch {
            publishStatus(.failed(error.localizedDescription))
            return
        }

        // Refuse non-socket files/symlinks and probe existing socket non-blockingly before unlinking.
        var existingStat = stat()
        if lstat(location.socketPath, &existingStat) == 0 {
            if (existingStat.st_mode & S_IFMT) != S_IFSOCK {
                publishStatus(.failed("Refused non-socket file at \(location.socketPath)"))
                return
            }
            if isSocketActivelyListening(path: location.socketPath) {
                publishStatus(.anotherInstanceActive(path: location.socketPath))
                return
            }
            _ = Darwin.unlink(location.socketPath)
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            publishStatus(.failed("socket() failed (\(errno))"))
            return
        }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let utf8 = Array(location.socketPath.utf8)
        guard utf8.count <= AgentSocketPath.maxSunPathUTF8Bytes else {
            Darwin.close(fd)
            publishStatus(.failed("Socket path too long"))
            return
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            rawPtr.initializeMemory(as: UInt8.self, repeating: 0)
            for (idx, byte) in utf8.enumerated() {
                rawPtr[idx] = byte
            }
        }

        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + 1 + utf8.count + 1)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            let err = errno
            Darwin.close(fd)
            publishStatus(.failed("bind() failed (\(err))"))
            return
        }

        // Enforce 0600 inside verified 0700 directory (never mutate process-wide umask).
        guard chmod(location.socketPath, 0o600) == 0 else {
            let err = errno
            Darwin.close(fd)
            _ = Darwin.unlink(location.socketPath)
            publishStatus(.failed("chmod(0600) failed (\(err))"))
            return
        }

        guard Darwin.listen(fd, 16) == 0 else {
            let err = errno
            Darwin.close(fd)
            _ = Darwin.unlink(location.socketPath)
            publishStatus(.failed("listen() failed (\(err))"))
            return
        }

        var boundStat = stat()
        if lstat(location.socketPath, &boundStat) == 0 {
            ownedInode = boundStat.st_ino
        } else {
            ownedInode = nil
        }
        ownedSocketPath = location.socketPath
        listenerFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        acceptSource = source
        source.resume()

        publishStatus(.listening(path: location.socketPath))
    }

    private func stopOnQueue() {
        for (_, client) in clients {
            client.timeoutWorkItem?.cancel()
            client.source?.cancel()
        }
        clients.removeAll()

        if let source = acceptSource {
            acceptSource = nil
            listenerFD = -1
            source.cancel()
        } else if listenerFD >= 0 {
            Darwin.close(listenerFD)
            listenerFD = -1
        }

        if let path = ownedSocketPath {
            var currentStat = stat()
            if lstat(path, &currentStat) == 0,
               (currentStat.st_mode & S_IFMT) == S_IFSOCK,
               (ownedInode == nil || currentStat.st_ino == ownedInode) {
                _ = Darwin.unlink(path)
            }
        }
        ownedSocketPath = nil
        ownedInode = nil
        publishStatus(.stopped)
    }

    private func acceptPendingConnections() {
        while listenerFD >= 0 {
            var addr = sockaddr_un()
            var len = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(listenerFD, sockPtr, &len)
                }
            }
            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }
                if errno == EINTR {
                    continue
                }
                break
            }

            guard clients.count < maxConcurrentClients else {
                Darwin.close(clientFD)
                continue
            }

            // Authenticate local peer EUID strictly.
            var peerUID: uid_t = 0
            var peerGID: gid_t = 0
            guard getpeereid(clientFD, &peerUID, &peerGID) == 0, peerUID == geteuid() else {
                Darwin.close(clientFD)
                continue
            }

            var noSigPipe: Int32 = 1
            _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let flags = fcntl(clientFD, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(clientFD, F_SETFL, flags | O_NONBLOCK)
            }

            var peerPIDValue: pid_t = 0
            var pidLen = socklen_t(MemoryLayout<pid_t>.size)
            let peerPID: Int32? = getsockopt(clientFD, SOL_LOCAL, LOCAL_PEERPID, &peerPIDValue, &pidLen) == 0
                ? Int32(peerPIDValue)
                : nil

            let client = ClientConnection(fd: clientFD, peerPID: peerPID)
            let timeout = DispatchWorkItem { [weak self] in
                self?.closeClient(fd: clientFD)
            }
            client.timeoutWorkItem = timeout
            queue.asyncAfter(deadline: .now() + .seconds(20), execute: timeout)

            let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
            source.setEventHandler { [weak self] in
                self?.readFromClient(fd: clientFD)
            }
            source.setCancelHandler {
                Darwin.close(clientFD)
            }
            client.source = source
            clients[clientFD] = client
            source.resume()
        }
    }

    private func readFromClient(fd: Int32) {
        guard let client = clients[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }
                if errno == EINTR {
                    continue
                }
                closeClient(fd: fd)
                return
            }
            if n == 0 {
                closeClient(fd: fd)
                return
            }
            if client.buffer.count + n > AgentIPCFrameCodec.maxFrameBytes + 4 {
                closeClient(fd: fd)
                return
            }
            client.buffer.append(chunk, count: n)
        }

        do {
            let frames = try AgentIPCFrameCodec.extractFrames(from: &client.buffer)
            for frame in frames {
                handleFrame(frame, clientFD: fd, peerPID: client.peerPID)
            }
        } catch {
            closeClient(fd: fd)
        }
    }

    private func handleFrame(_ data: Data, clientFD: Int32, peerPID: Int32?) {
        let request: AgentIPCRequest
        do {
            request = try JSONDecoder().decode(AgentIPCRequest.self, from: data)
        } catch {
            let errResp = AgentIPCResponse(id: UUID(), kind: .error(code: "bad_request", message: "Invalid IPC request JSON."))
            sendResponse(errResp, to: clientFD)
            return
        }

        let executor = self.executor
        let protocolHandler = self.protocolHandler
        Task { [weak self] in
            let response: AgentIPCResponse
            switch request.kind {
            case .mcpJSONRPC(let payloadUTF8, let clientName):
                let ctx = AgentRequestContext(source: .mcpStdio, clientName: clientName, peerPID: peerPID)
                let result = await protocolHandler.handleMessageData(
                    Data(payloadUTF8.utf8),
                    httpProtocolVersion: nil,
                    context: ctx,
                    executor: executor
                )
                switch result {
                case .noResponse:
                    response = AgentIPCResponse(id: request.id, kind: .mcpNoResponse)
                case .reply(let replyData):
                    let str = String(data: replyData, encoding: .utf8) ?? "{}"
                    response = AgentIPCResponse(id: request.id, kind: .mcpReply(payloadUTF8: str))
                case .batchRejected:
                    response = AgentIPCResponse(id: request.id, kind: .error(code: "batch_rejected", message: "Batch requests unsupported."))
                }

            case .toolCall(let toolName, let arguments, let source, let clientName):
                let ctx = AgentRequestContext(source: source, clientName: clientName, peerPID: peerPID)
                let outcome = await executor.execute(toolName: toolName, arguments: arguments, context: ctx)
                response = AgentIPCResponse(id: request.id, kind: .commandOutcome(outcome))

            case .readResource(let uri, let source, let clientName):
                let ctx = AgentRequestContext(source: source, clientName: clientName, peerPID: peerPID)
                let outcome = await executor.readResource(uri: uri, context: ctx)
                response = AgentIPCResponse(id: request.id, kind: .resourceOutcome(outcome))
            }

            self?.queue.async { [weak self] in
                self?.sendResponse(response, to: clientFD)
            }
        }
    }

    private func sendResponse(_ response: AgentIPCResponse, to clientFD: Int32) {
        guard clients[clientFD] != nil else { return }
        guard let jsonData = try? JSONEncoder().encode(response),
              let framed = try? AgentIPCFrameCodec.encode(jsonData) else {
            closeClient(fd: clientFD)
            return
        }

        let deadline = Date().addingTimeInterval(2.0)
        let ok = framed.withUnsafeBytes { rawBuf -> Bool in
            guard let base = rawBuf.baseAddress else { return true }
            var offset = 0
            while offset < rawBuf.count {
                let n = Darwin.write(clientFD, base.advanced(by: offset), rawBuf.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        if Date() >= deadline { return false }
                        var pfd = pollfd(fd: clientFD, events: Int16(POLLOUT), revents: 0)
                        let polled = Darwin.poll(&pfd, 1, 250)
                        guard polled > 0,
                              (pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) == 0,
                              Date() < deadline else {
                            return false
                        }
                        continue
                    }
                    return false
                }
                if n == 0 { return false }
                offset += n
            }
            return true
        }
        if !ok {
            closeClient(fd: clientFD)
        }
    }

    private func closeClient(fd: Int32) {
        guard let client = clients.removeValue(forKey: fd) else { return }
        client.timeoutWorkItem?.cancel()
        client.source?.cancel()
    }

    private func isSocketActivelyListening(path: String) -> Bool {
        let probeFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard probeFD >= 0 else { return false }
        defer { Darwin.close(probeFD) }

        let flags = fcntl(probeFD, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(probeFD, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let utf8 = Array(path.utf8)
        guard utf8.count <= AgentSocketPath.maxSunPathUTF8Bytes else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            rawPtr.initializeMemory(as: UInt8.self, repeating: 0)
            for (idx, byte) in utf8.enumerated() {
                rawPtr[idx] = byte
            }
        }
        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + 1 + utf8.count + 1)
        let res = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(probeFD, sockPtr, addrLen)
            }
        }
        if res == 0 {
            return true
        }
        if errno == EINPROGRESS {
            var pfd = pollfd(fd: probeFD, events: Int16(POLLOUT), revents: 0)
            let polled = Darwin.poll(&pfd, 1, 200)
            if polled > 0 {
                var soErr: Int32 = 0
                var soLen = socklen_t(MemoryLayout<Int32>.size)
                if getsockopt(probeFD, SOL_SOCKET, SO_ERROR, &soErr, &soLen) == 0 && soErr == 0 {
                    return true
                }
            }
        }
        return false
    }

    private func publishStatus(_ status: AgentUnixSocketStatus) {
        let callback = onStatusChange
        Task { @MainActor in
            callback(status)
        }
    }
}
