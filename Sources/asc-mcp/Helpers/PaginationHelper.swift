import Foundation

/// Parses a full pagination URL into path and query parameters
/// - Parameter fullUrl: The full URL from API pagination links
/// - Returns: Tuple of (path, parameters) or nil if URL is invalid or host is not allowed
func parsePaginationUrl(_ fullUrl: String) -> (path: String, parameters: [String: String])? {
    guard let components = URLComponents(string: fullUrl) else { return nil }

    // Validate URL belongs to App Store Connect API (SSRF protection)
    let allowedHosts = ["api.appstoreconnect.apple.com"]
    guard let host = components.host, allowedHosts.contains(host) else {
        return nil
    }

    let path = components.path
    var params: [String: String] = [:]
    components.queryItems?.forEach { params[$0.name] = $0.value ?? "" }
    return (path, params)
}
