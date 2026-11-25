import Darwin
import Foundation
import YouTubeMacCore

enum AgentClientError: Error, Sendable {
    case automationDisabled
    case appLaunchFailed(String)
    case connectionFailed(String)
    case timeout
    case protocolError(String)

    var message: String {
        switch self {
        case .automationDisabled:
            return "AI & Automation is disabled in GlassGrid You. Enable it in Settings → AI & Automation."
        case .appLaunchFailed(let detail):
            return "Failed to launch GlassGrid You: \(detail)"
        case .connectionFailed(let detail):
            return "Unable to connect to GlassGrid You: \(detail)"
        case .timeout:
            return "Timed out waiting for GlassGrid You to respond."
        case .protocolError(let detail):
            return detail
        }
    }
}

/// Framed POSIX Unix Domain Socket client for `glassgrid` CLI and MCP stdio bridge.
/// Never auto-launches the GUI app if `ytmac.agentControlEnabled` is false.
final class AgentUnixSocketClient: @unchecked Sendable {
    private let socketLocation: AgentSocketLocation
    private let noLaunch: Bool

    init(noLaunch: Bool = false) {
        signal(SIGPIPE, SIG_IGN)
        let override = ProcessInfo.processInfo.environment["GLASSGRID_SOCKET_PATH"]
        self.socketLocation = AgentSocketPath.resolve(overridePath: override)
        self.noLaunch = noLaunch
    }

    func send(_ request: AgentIPCRequest, timeoutSeconds: TimeInterval = 15.0) -> Result<AgentIPCResponse, AgentClientError> {
        let payload: Data
        let framed: Data
        do {
            payload = try JSONEncoder().encode(request)
            framed = try AgentIPCFrameCodec.encode(payload)
        } catch {
            return .failure(.protocolError("Failed to encode IPC request: \(error.localizedDescription)"))
        }

        switch connectWithOptionalLaunch() {
        case .failure(let err):
            return .failure(err)
        case .success(let fd):
            let firstAttempt = performRoundTrip(fd: fd, framedRequest: framed, timeoutSeconds: timeoutSeconds)
            Darwin.close(fd)
            switch firstAttempt {
            case .success(let response):
                return .success(response)
            case .failure(.connectionFailed):
                // Single clean retry if app restarted mid-flight
                switch connectOnce() {
                case .success(let retryFD):
                    let secondAttempt = performRoundTrip(fd: retryFD, framedRequest: framed, timeoutSeconds: timeoutSeconds)
                    Darwin.close(retryFD)
                    return secondAttempt
                case .failure(let err):
                    return .failure(err)
                }
            case .failure(let err):
                return .failure(err)
            }
        }
    }

    private func connectWithOptionalLaunch() -> Result<Int32, AgentClientError> {
        if case .success(let fd) = connectOnce() {
            return .success(fd)
        }

        if noLaunch {
            return .failure(.connectionFailed("GlassGrid You is not running (or AI & Automation is disabled)."))
        }

        // Respect Master Kill Switch BEFORE ever spawning the GUI app (skip check only for explicit test socket overrides).
        let hasOverride = !(ProcessInfo.processInfo.environment["GLASSGRID_SOCKET_PATH"] ?? "").isEmpty
        if !hasOverride {
            let appID = "com.glassgridyou.mac" as CFString
            CFPreferencesAppSynchronize(appID)
            let rawValue = CFPreferencesCopyAppValue("ytmac.agentControlEnabled" as CFString, appID)
            let enabled = (rawValue as? Bool) ?? ((rawValue as? NSNumber)?.boolValue ?? false)
            if !enabled {
                return .failure(.automationDisabled)
            }
        }

        if let launchError = launchOwningApp() {
            return .failure(.appLaunchFailed(launchError))
        }

        let delaysMs: [useconds_t] = [50, 100, 150, 250, 350, 500, 600, 750, 750, 750, 750, 750]
        for delay in delaysMs {
            usleep(delay * 1_000)
            if case .success(let fd) = connectOnce() {
                return .success(fd)
            }
        }

        return .failure(.connectionFailed("GlassGrid You started, but AI & Automation socket is unavailable."))
    }

    private func connectOnce() -> Result<Int32, AgentClientError> {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return .failure(.connectionFailed("socket() failed (\(errno))"))
        }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let utf8 = Array(socketLocation.socketPath.utf8)
        guard utf8.count <= AgentSocketPath.maxSunPathUTF8Bytes else {
            Darwin.close(fd)
            return .failure(.connectionFailed("Socket path exceeds sun_path limit."))
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            rawPtr.initializeMemory(as: UInt8.self, repeating: 0)
            for (idx, byte) in utf8.enumerated() {
                rawPtr[idx] = byte
            }
        }

        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + 1 + utf8.count + 1)
        let res = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        guard res == 0 else {
            let err = errno
            Darwin.close(fd)
            return .failure(.connectionFailed("connect(\(socketLocation.socketPath)) failed (\(err))"))
        }

        return .success(fd)
    }

    private func performRoundTrip(
        fd: Int32,
        framedRequest: Data,
        timeoutSeconds: TimeInterval
    ) -> Result<AgentIPCResponse, AgentClientError> {
        guard writeAll(fd: fd, data: framedRequest) else {
            return .failure(.connectionFailed("Failed writing request to socket (\(errno))"))
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while true {
            let remainingMs = Int32(max(100, min(15_000, deadline.timeIntervalSinceNow * 1000)))
            if deadline.timeIntervalSinceNow <= 0 {
                return .failure(.timeout)
            }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let polled = Darwin.poll(&pfd, 1, remainingMs)
            if polled < 0 {
                if errno == EINTR { continue }
                return .failure(.connectionFailed("poll() failed (\(errno))"))
            }
            if polled == 0 {
                return .failure(.timeout)
            }

            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0 {
                if errno == EINTR { continue }
                return .failure(.connectionFailed("read() failed (\(errno))"))
            }
            if n == 0 {
                return .failure(.connectionFailed("Server closed connection before responding."))
            }

            buffer.append(chunk, count: n)
            do {
                let frames = try AgentIPCFrameCodec.extractFrames(from: &buffer)
                if let first = frames.first {
                    let response = try JSONDecoder().decode(AgentIPCResponse.self, from: first)
                    return .success(response)
                }
            } catch {
                return .failure(.protocolError("Invalid IPC response frame: \(error.localizedDescription)"))
            }
        }
    }

    private func writeAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return true }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(fd, base.advanced(by: offset), rawBuffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if written == 0 {
                    return false
                }
                offset += written
            }
            return true
        }
    }

    private func launchOwningApp() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if let appURL = resolveOwningAppBundleURL() {
            task.arguments = ["-g", "-a", appURL.path]
        } else {
            task.arguments = ["-g", "-b", "com.glassgridyou.mac"]
        }
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                return "open exited with status \(task.terminationStatus)"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func resolveOwningAppBundleURL() -> URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        let rawPath = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let resolvedURL = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath()
        // <App>.app/Contents/MacOS/glassgrid -> 3 levels up
        let appURL = resolvedURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL),
              let bundleID = plist["CFBundleIdentifier"] as? String,
              bundleID == "com.glassgridyou.mac" else {
            return nil
        }
        return appURL
    }
}
