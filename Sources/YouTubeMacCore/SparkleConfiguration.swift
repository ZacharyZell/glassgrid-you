import Foundation

/// Pure validator for Sparkle 2 `Info.plist` configuration so unconfigured open-source forks,
/// local dev builds, and CI never initialize Sparkle or trigger startup error alerts.
public enum SparkleConfiguration {
    public static let feedURLKey = "SUFeedURL"
    public static let publicEDKey = "SUPublicEDKey"
    public static let defaultFeedURLString = "https://raw.githubusercontent.com/ZacharyZell/glassgrid-you/main/appcast.xml"

    /// Extracts a validated `https://` Sparkle appcast feed URL from an `Info.plist` dictionary.
    public static func feedURL(infoDictionary: [String: Any]?) -> URL? {
        guard let raw = infoDictionary?[feedURLKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }

    /// Extracts a validated Ed25519 base64 public key (`>= 32` decoded bytes) from an `Info.plist` dictionary.
    public static func publicEDKey(infoDictionary: [String: Any]?) -> String? {
        guard let raw = infoDictionary?[publicEDKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let decoded = Data(base64Encoded: trimmed),
              decoded.count >= 32 else {
            return nil
        }
        return trimmed
    }

    /// Returns `true` strictly when BOTH `SUFeedURL` (valid `https://`) and `SUPublicEDKey` (`>= 32`-byte base64) are configured.
    public static func isConfigured(infoDictionary: [String: Any]?) -> Bool {
        feedURL(infoDictionary: infoDictionary) != nil
            && publicEDKey(infoDictionary: infoDictionary) != nil
    }
}
