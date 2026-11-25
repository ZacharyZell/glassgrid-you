import Darwin
import Foundation

/// Structured validation failures for agent-supplied URLs.
public enum AgentURLValidationError: Error, Equatable, Sendable {
    case emptyOrMalformed
    case nonHTTPS
    case containsCredentials
    case invalidHost
    case localOrPrivateHost
    case rawIPAddressRejected
    case blockedAuthOrLogoutRoute
    case tierRestrictedCompanionDomain

    public var message: String {
        switch self {
        case .emptyOrMalformed:
            return "URL is empty or malformed."
        case .nonHTTPS:
            return "Only https:// URLs are allowed for AI automation."
        case .containsCredentials:
            return "URLs containing embedded username or password credentials are blocked."
        case .invalidHost:
            return "URL host is missing or invalid."
        case .localOrPrivateHost:
            return "Localhost and internal network hostnames are blocked."
        case .rawIPAddressRejected:
            return "Raw IP address URLs are blocked."
        case .blockedAuthOrLogoutRoute:
            return "Authentication, OAuth, redirect, and sign-out URLs are blocked."
        case .tierRestrictedCompanionDomain:
            return "Arbitrary third-party Companion URLs require Full Control permission."
        }
    }
}

/// Security primitives shared across MCP, HTTP, IPC, URL actions, and web-context sanitization.
public enum AgentSecurity {
    public static let maxVideoDescriptionLength = 4000
    public static let maxWebTitleLength = 300
    public static let maxChannelNameLength = 120
    public static let maxChapterTitleLength = 200
    public static let maxChaptersCount = 100
    public static let untrustedWebContentTag = "untrusted_web_page"

    private static let blockedAuthHostFragments: [String] = [
        "accounts.google.com",
        "accounts.youtube.com",
        "myaccount.google.com",
        "consent.youtube.com",
        "consent.google.com",
        "passwords.google.com",
        "idmsa.apple.com",
        "appleid.apple.com",
        "sp.auth.adobe.com",
        "registerdisney.go.com",
        "cdn.registerdisney.go.com",
        "passport.twitch.tv",
        "id.twitch.tv",
        "identity.sling.com",
        "identity.nba.com",
        "ids.mlb.com",
        "id.nfl.com",
        "id.peacocktv.com",
        "auth.hulu.com",
        "auth.max.com",
        "sso.crunchyroll.com",
        "na.account.amazon.com",
        "eu.account.amazon.com",
        "fe.account.amazon.com"
    ]

    private static let blockedAuthHostPrefixes: [String] = [
        "auth.",
        "sso.",
        "login.",
        "signin.",
        "sign-in.",
        "id.",
        "ids.",
        "identity.",
        "passport.",
        "accounts."
    ]

    private static let blockedLogoutSegments: Set<String> = [
        "logout",
        "signout",
        "log-out",
        "sign-out"
    ]

    /// Constant-time UTF-8 string comparison for Bearer tokens.
    public static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return a.isEmpty && b.isEmpty }
        var diff: UInt8 = a.count == b.count ? 0 : 1
        for i in 0..<maxLen {
            let ca = i < a.count ? a[i] : 0
            let cb = i < b.count ? b[i] : 0
            diff |= (ca ^ cb)
        }
        return diff == 0
    }

    /// Strips ASCII control characters (preserving `\n` and `\t`) and Unicode bidi override/isolate controls,
    /// then caps output length cleanly for untrusted web metadata.
    public static func sanitizeWebText(_ raw: String, maxLength: Int) -> (text: String, truncated: Bool) {
        guard maxLength > 0 else { return ("", !raw.isEmpty) }
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(min(raw.unicodeScalars.count, maxLength))

        var previousWasNewline = false
        var consecutiveNewlines = 0

        for scalar in raw.unicodeScalars {
            let v = scalar.value
            // Strip ASCII controls except \t (0x09) and \n (0x0A), plus DEL (0x7F)
            if (v < 0x20 && v != 0x09 && v != 0x0A) || v == 0x7F {
                continue
            }
            // Strip Unicode bidirectional control characters & isolates (Trojan Source / prompt-injection spoofing)
            if (v >= 0x202A && v <= 0x202E)
                || (v >= 0x2066 && v <= 0x2069)
                || v == 0x200E || v == 0x200F || v == 0x061C {
                continue
            }

            if v == 0x0A {
                consecutiveNewlines = previousWasNewline ? (consecutiveNewlines + 1) : 1
                previousWasNewline = true
                if consecutiveNewlines > 2 {
                    continue
                }
            } else {
                previousWasNewline = false
                consecutiveNewlines = 0
            }
            scalars.append(scalar)
        }

        let cleaned = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count <= maxLength {
            return (cleaned, false)
        }
        let endIdx = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
        return (String(cleaned[..<endIdx]), true)
    }

    /// Validates an agent-provided URL strictly against HTTPS-only, SSRF/IP, Auth/SSO, redirect, logout, and tier policies.
    public static func validateURL(_ raw: String, tier: AgentPermissionLevel) -> Result<URL, AgentURLValidationError> {
        guard tier >= .playbackAndNavigation else {
            return .failure(.tierRestrictedCompanionDomain)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(" "),
              !trimmed.contains("\n"),
              !trimmed.contains("\r"),
              !trimmed.contains("\t") else {
            return .failure(.emptyOrMalformed)
        }

        guard let parsed = URL(string: trimmed),
              let components = URLComponents(url: parsed, resolvingAgainstBaseURL: false) else {
            return .failure(.emptyOrMalformed)
        }

        guard components.scheme?.lowercased() == "https" else {
            return .failure(.nonHTTPS)
        }

        if components.user != nil || components.password != nil || parsed.user != nil || parsed.password != nil {
            return .failure(.containsCredentials)
        }

        guard let rawHost = components.host?.lowercased(), !rawHost.isEmpty else {
            return .failure(.invalidHost)
        }

        // Reject trailing dot variants or empty domain labels (e.g. `foo..bar.com`, `localhost.`)
        if rawHost.hasSuffix(".") || rawHost.hasPrefix(".") {
            return .failure(.invalidHost)
        }

        let unbracketedHost = (rawHost.hasPrefix("[") && rawHost.hasSuffix("]"))
            ? String(rawHost.dropFirst().dropLast())
            : rawHost

        if unbracketedHost.isEmpty {
            return .failure(.invalidHost)
        }

        // Reject raw IPv4 or IPv6 literals via inet_pton
        var ipv4Addr = in_addr()
        var ipv6Addr = in6_addr()
        if inet_pton(AF_INET, unbracketedHost, &ipv4Addr) == 1
            || inet_pton(AF_INET6, unbracketedHost, &ipv6Addr) == 1 {
            return .failure(.rawIPAddressRejected)
        }

        // Require well-formed DNS labels and strictly alphabetic TLD (blocks integer/hex/octal IPs like 0x7f000001 or 2130706433)
        let labels = unbracketedHost.split(separator: ".", omittingEmptySubsequences: false)
        if unbracketedHost == "localhost"
            || unbracketedHost.hasSuffix(".localhost")
            || unbracketedHost.hasSuffix(".local")
            || unbracketedHost.hasSuffix(".internal") {
            return .failure(.localOrPrivateHost)
        }

        guard labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty
                      && !label.hasPrefix("-")
                      && !label.hasSuffix("-")
                      && label.unicodeScalars.allSatisfy { s in
                          (s.value >= 97 && s.value <= 122)
                              || (s.value >= 48 && s.value <= 57)
                              || s == "-"
                      }
              }),
              let tld = labels.last,
              tld.count >= 2,
              tld.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else {
            return .failure(.invalidHost)
        }

        // Reject Google/YouTube auth hosts and all known SSO/OAuth domains
        if YouTubeURLRouter.isGoogleAuthHost(unbracketedHost) {
            return .failure(.blockedAuthOrLogoutRoute)
        }
        let allAuthHints = StreamingServiceCatalog.all.flatMap(\.authHostHints)
        if blockedAuthHostFragments.contains(where: { unbracketedHost == $0 || unbracketedHost.hasSuffix("." + $0) })
            || allAuthHints.contains(where: { unbracketedHost == $0.lowercased() || unbracketedHost.hasSuffix("." + $0.lowercased()) })
            || blockedAuthHostPrefixes.contains(where: { unbracketedHost.hasPrefix($0) }) {
            return .failure(.blockedAuthOrLogoutRoute)
        }

        // Inspect standardized lowercased path for /redirect, auth/account/checkout, and logout routes
        let standardizedPath = parsed.standardized.path.lowercased()
        let rawSegments = standardizedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let normSegments = rawSegments.map(StreamingServiceCatalog.stripOptionalWebExtension)

        if YouTubeURLRouter.isYouTubeHost(unbracketedHost), normSegments.first == "redirect" {
            return .failure(.blockedAuthOrLogoutRoute)
        }
        if normSegments.contains(where: { blockedLogoutSegments.contains($0) }) {
            return .failure(.blockedAuthOrLogoutRoute)
        }

        // Amazon / Prime Video auth, retail account, payment, and 1-click checkout routes (checked BEFORE any locale stripping)
        if StreamingServiceCatalog.isAmazonOrPrimeVideoHost(unbracketedHost) {
            let amzSegs: [String]
            if normSegments.count >= 2 && normSegments[0] == "region",
               (2...3).contains(normSegments[1].count),
               normSegments[1].unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) {
                amzSegs = Array(normSegments.dropFirst(2))
            } else {
                amzSegs = normSegments
            }

            if let first = amzSegs.first,
               ["ap", "ax", "your-account", "checkout", "cpe"].contains(first) {
                return .failure(.blockedAuthOrLogoutRoute)
            }
            if amzSegs.count >= 2 {
                let s0 = amzSegs[0]
                let s1 = amzSegs[1]
                if (s0 == "gp" && (["buy", "cart", "css", "your-account", "checkoutportal", "sign-in"].contains(s1) || s1.hasPrefix("payment")))
                    || (s0 == "a" && (s1 == "addresses" || s1 == "settings")) {
                    return .failure(.blockedAuthOrLogoutRoute)
                }
            }
            if amzSegs.count >= 3 && amzSegs[0] == "gp" {
                if amzSegs[1] == "aws" && amzSegs[2] == "cart" {
                    return .failure(.blockedAuthOrLogoutRoute)
                }
                if amzSegs[1] == "flex" && (amzSegs[2] == "sign-out" || amzSegs[2] == "sign-in") {
                    return .failure(.blockedAuthOrLogoutRoute)
                }
            }
            if amzSegs.contains("auth-redirect") {
                return .failure(.blockedAuthOrLogoutRoute)
            }
        }

        let blockedAuthSegments: Set<String> = [
            "signin", "sign-in", "sign_in",
            "oauth", "oauth2", "authorize",
            "auth-redirect", "servicelogin"
        ]
        if normSegments.contains(where: { blockedAuthSegments.contains($0) }) {
            return .failure(.blockedAuthOrLogoutRoute)
        }

        let afterLocale = Array(StreamingServiceCatalog.stripLeadingLocaleSegment(normSegments))
        if afterLocale.first == "login" {
            return .failure(.blockedAuthOrLogoutRoute)
        }
        if afterLocale.count >= 2,
           ["web", "account", "accounts", "auth", "sso", "user"].contains(afterLocale[0]),
           afterLocale[1] == "login" {
            return .failure(.blockedAuthOrLogoutRoute)
        }

        if let query = components.query?.lowercased(),
           query.contains("servicelogin")
            || query.contains("openid.mode=checkid_setup")
            || query.contains("openid.mode=checkid_immediate")
            || (query.contains("oauth") && query.contains("client_id=")) {
            return .failure(.blockedAuthOrLogoutRoute)
        }

        if tier == .playbackAndNavigation {
            let isYouTube = YouTubeURLRouter.isYouTubeHost(unbracketedHost)
            let isKnownService = StreamingServiceCatalog.service(matchingURL: parsed) != nil
            guard isYouTube || isKnownService else {
                return .failure(.tierRestrictedCompanionDomain)
            }
        }

        return .success(parsed)
    }
}
