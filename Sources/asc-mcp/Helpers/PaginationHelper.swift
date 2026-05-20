import Foundation

enum PaginationURLPolicy {
    static let defaultAllowedHost = "api.appstoreconnect.apple.com"
}

/// Parses a full pagination URL into path and query parameters
/// - Parameter fullUrl: The full URL from API pagination links
/// - Returns: Tuple of (path, parameters) or nil if URL is invalid or host is not allowed
func parsePaginationUrl(
    _ fullUrl: String,
    allowedHost: String = PaginationURLPolicy.defaultAllowedHost
) -> (path: String, parameters: [String: String])? {
    guard let components = URLComponents(string: fullUrl) else { return nil }

    // Validate URL belongs to the configured API host (SSRF protection).
    guard let host = components.host, host.caseInsensitiveCompare(allowedHost) == .orderedSame else {
        return nil
    }

    let path = components.path
    var params: [String: String] = [:]
    components.queryItems?.forEach { params[$0.name] = $0.value ?? "" }
    return (path, params)
}
