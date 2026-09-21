import Foundation

public enum EndpointPolicyError: Error, Equatable, Sendable {
    case empty
    case invalidURL
    case userinfoForbidden
    case fragmentForbidden
    case secretInQuery(String)
    case httpsRequired
    case insecurePrivateNetworkDisabled
    case unsupportedScheme(String)
}

public struct EndpointPolicy: Sendable {
    public static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    public static let secretQueryKeys: Set<String> = [
        "api_key", "apikey", "key", "token", "access_token", "secret", "password", "auth",
    ]

    public static func parse(
        _ raw: String,
        allowsInsecurePrivateNetworkHTTP: Bool
    ) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EndpointPolicyError.empty }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw EndpointPolicyError.invalidURL
        }
        if url.user != nil || url.password != nil {
            throw EndpointPolicyError.userinfoForbidden
        }
        if url.fragment != nil {
            throw EndpointPolicyError.fragmentForbidden
        }
        if let query = url.query {
            for pair in query.split(separator: "&") {
                let name = pair.split(separator: "=", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
                if secretQueryKeys.contains(name) {
                    throw EndpointPolicyError.secretInQuery(name)
                }
            }
        }
        switch scheme {
        case "https":
            return url
        case "http":
            if isLoopback(url.host) {
                return url
            }
            if isPrivateNetwork(url.host) {
                guard allowsInsecurePrivateNetworkHTTP else {
                    throw EndpointPolicyError.insecurePrivateNetworkDisabled
                }
                return url
            }
            throw EndpointPolicyError.httpsRequired
        default:
            throw EndpointPolicyError.unsupportedScheme(scheme)
        }
    }

    public static func isLoopback(_ host: String?) -> Bool {
        guard let host else { return false }
        return loopbackHosts.contains(host.lowercased())
    }

    public static func isPrivateNetwork(_ host: String?) -> Bool {
        guard let host else { return false }
        if isLoopback(host) { return true }
        if host.hasPrefix("10.") { return true }
        if host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        if host.lowercased().hasSuffix(".local") { return true }
        return false
    }

    public static func identityScope(for url: URL) -> String {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = url.path
        return components.string ?? url.absoluteString
    }
}

public enum SecretRedactor: Sendable {
    public static func redact(_ text: String) -> String {
        var result = text
        let patterns = [
            #"sk-[A-Za-z0-9_\-]{8,}"#,
            #"sk-ant-[A-Za-z0-9_\-]{8,}"#,
            #"(?i)(api[_-]?key|token|secret|authorization)\s*[:=]\s*\S+"#,
            #"(?i)bearer\s+[A-Za-z0-9\-._~+/]+=*"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[redacted]")
            }
        }
        return result
    }

    public static func containsSecretLikeValue(_ text: String) -> Bool {
        redact(text) != text
    }
}
