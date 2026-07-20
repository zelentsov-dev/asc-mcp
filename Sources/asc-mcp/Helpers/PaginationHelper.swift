import Foundation
import MCP

public struct PaginationScope: Sendable, Equatable {
    public let path: String
    public let requiredParameters: [String: String]
    public let allowedParameters: Set<String>?
    public let requiredNonEmptyParameters: Set<String>

    /// Defines the exact collection and query invariants a pagination link must preserve.
    /// - Parameters:
    ///   - path: Absolute API collection path, including concrete parent identifiers.
    ///   - requiredParameters: Query parameters whose values must remain unchanged across pages.
    ///   - allowedParameters: Optional strict query-name allowlist. Nil preserves forward-compatible Apple parameters.
    ///   - requiredNonEmptyParameters: Query parameters that must be present with a non-empty value.
    public init(
        path: String,
        requiredParameters: [String: String] = [:],
        allowedParameters: Set<String>? = nil,
        requiredNonEmptyParameters: Set<String> = []
    ) {
        self.path = path
        self.requiredParameters = requiredParameters
        self.allowedParameters = allowedParameters
        self.requiredNonEmptyParameters = requiredNonEmptyParameters
    }

    /// Creates a continuation scope bound to the complete originating query.
    /// - Parameters:
    ///   - path: Absolute API collection path, including concrete parent identifiers.
    ///   - query: Complete effective query used for the originating collection request.
    /// - Returns: A scope that permits only the originating query keys and a non-empty cursor.
    /// - Throws: Never.
    public static func strict(path: String, query: [String: String]) -> PaginationScope {
        PaginationScope(
            path: path,
            requiredParameters: query,
            allowedParameters: Set(query.keys).union(["cursor"]),
            requiredNonEmptyParameters: ["cursor"]
        )
    }
}

struct PaginationRequest: Sendable, Equatable {
    let path: String
    let parameters: [String: String]
}

func paginationURL(from value: Value?) throws -> String? {
    guard let value else { return nil }
    guard let nextURL = value.stringValue,
          !nextURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalidPaginationURL("must be a non-empty string")
    }
    return nextURL
}

func validatedPaginationRequest(
    _ fullURL: String,
    baseURL: String,
    scope: PaginationScope
) throws -> PaginationRequest {
    let trimmedURL = fullURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fullURL.isEmpty,
          trimmedURL == fullURL,
          let baseComponents = URLComponents(string: baseURL),
          let baseScheme = baseComponents.scheme,
          let baseHost = baseComponents.host,
          baseComponents.user == nil,
          baseComponents.password == nil,
          baseComponents.fragment == nil,
          let parsedComponents = URLComponents(string: fullURL),
          parsedComponents.user == nil,
          parsedComponents.password == nil,
          parsedComponents.fragment == nil else {
        throw invalidPaginationURL("must be an absolute configured-origin URL or a root-relative API URL without credentials or a fragment")
    }

    let components: URLComponents
    if parsedComponents.scheme == nil, parsedComponents.host == nil {
        guard fullURL.hasPrefix("/"), !fullURL.hasPrefix("//") else {
            throw invalidPaginationURL("relative links must be root-relative API URLs")
        }
        var resolvedComponents = parsedComponents
        resolvedComponents.scheme = baseScheme
        resolvedComponents.host = baseHost
        resolvedComponents.port = baseComponents.port
        components = resolvedComponents
    } else {
        components = parsedComponents
    }

    guard let scheme = components.scheme,
          let host = components.host,
          components.user == nil,
          components.password == nil,
          components.fragment == nil else {
        throw invalidPaginationURL("must resolve to the configured App Store Connect origin")
    }

    guard ["http", "https"].contains(baseScheme.lowercased()),
          scheme.caseInsensitiveCompare(baseScheme) == .orderedSame,
          host.caseInsensitiveCompare(baseHost) == .orderedSame,
          effectivePort(for: components) == effectivePort(for: baseComponents) else {
        throw invalidPaginationURL("origin does not match the configured App Store Connect origin")
    }

    guard isCanonicalAPIPath(scope.path),
          components.percentEncodedPath == scope.path else {
        throw invalidPaginationURL("path does not match the expected collection")
    }

    var parameters: [String: String] = [:]
    for item in components.queryItems ?? [] {
        guard !item.name.isEmpty, let value = item.value else {
            throw invalidPaginationURL("contains a query parameter without a value")
        }
        guard parameters[item.name] == nil else {
            throw invalidPaginationURL("contains duplicate query parameter '\(item.name)'")
        }
        parameters[item.name] = value
    }

    for (name, value) in scope.requiredParameters {
        guard parameters[name] == value else {
            throw invalidPaginationURL("does not preserve required query parameter '\(name)'")
        }
    }

    for name in scope.requiredNonEmptyParameters {
        guard let value = parameters[name],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalidPaginationURL("does not contain a non-empty query parameter '\(name)'")
        }
    }

    if let allowedParameters = scope.allowedParameters {
        guard Set(parameters.keys).isSubset(of: allowedParameters) else {
            throw invalidPaginationURL("contains a query parameter outside the allowed set")
        }
    }

    return PaginationRequest(path: scope.path, parameters: parameters)
}

private func isCanonicalAPIPath(_ path: String) -> Bool {
    guard path.hasPrefix("/"),
          !path.contains("//"),
          !path.contains("\\"),
          !path.contains("?"),
          !path.contains("#") else {
        return false
    }

    let lowered = path.lowercased()
    guard !lowered.contains("%2f"),
          !lowered.contains("%5c"),
          !lowered.contains("%2e") else {
        return false
    }

    return !path.split(separator: "/", omittingEmptySubsequences: false).contains { segment in
        segment == "." || segment == ".."
    }
}

private func effectivePort(for components: URLComponents) -> Int? {
    if let port = components.port {
        return port
    }

    switch components.scheme?.lowercased() {
    case "https":
        return 443
    case "http":
        return 80
    default:
        return nil
    }
}

private func invalidPaginationURL(_ reason: String) -> ASCError {
    ASCError.parsing("Invalid next_url: \(reason)")
}
