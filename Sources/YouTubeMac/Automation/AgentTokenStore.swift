import Foundation
import Security

/// Manages the local Streamable HTTP Bearer secret inside a `0700` directory with strict `0600` file permissions.
/// Never stores tokens in `UserDefaults` (world-readable) or macOS Keychain (ad-hoc CDHash prompt traps).
public struct AgentTokenStore: Sendable {
    public let directoryURL: URL
    public let tokenURL: URL

    public init(baseDirectoryURL: URL? = nil) {
        let dir: URL
        if let baseDirectoryURL {
            dir = baseDirectoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            dir = appSupport.appendingPathComponent("GlassGridYou", isDirectory: true)
        }
        self.directoryURL = dir
        self.tokenURL = dir.appendingPathComponent("http-token", isDirectory: false)
    }

    public func loadOrCreateToken() -> String {
        do {
            try AgentSecureFileIO.ensurePrivateDirectory(directoryURL)
            if let existing = try AgentSecureFileIO.readFileNoFollow(at: tokenURL, maxBytes: 512),
               let raw = String(data: existing.data, encoding: .utf8)?
                   .trimmingCharacters(in: .whitespacesAndNewlines),
               raw.count >= 32 {
                if existing.mode != 0o600 {
                    _ = chmod(tokenURL.path, 0o600)
                }
                return raw
            }
        } catch {
            // Fall through to generate fresh token if directory is valid
        }
        return rotateToken()
    }

    @discardableResult
    public func rotateToken() -> String {
        let token = Self.generateRandomHexToken(byteCount: 32)
        do {
            try AgentSecureFileIO.ensurePrivateDirectory(directoryURL)
            try AgentSecureFileIO.writeAtomicSecureFile(
                data: Data((token + "\n").utf8),
                to: tokenURL,
                mode: 0o600
            )
        } catch {
            // Even if disk write fails, keep rotating in-memory token so callers never fall back to a static secret.
        }
        return token
    }

    public static func generateRandomHexToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
