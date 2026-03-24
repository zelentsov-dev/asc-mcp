import Foundation

// MARK: - Pre-Release Version Models (for /v1/preReleaseVersions endpoint)

/// Pre-release versions list response
public struct ASCPreReleaseVersionsResponse: Codable, Sendable {
    public let data: [ASCPreReleaseVersionResource]
    public let links: ASCPagedDocumentLinks?
}

/// Pre-release version single response
public struct ASCPreReleaseVersionResponse: Codable, Sendable {
    public let data: ASCPreReleaseVersionResource
}

/// Pre-release version resource (distinct from ASCPreReleaseVersion in BuildModels)
public struct ASCPreReleaseVersionResource: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PreReleaseVersionResourceAttributes?
}

/// Pre-release version resource attributes
public struct PreReleaseVersionResourceAttributes: Codable, Sendable {
    public let version: String?
    public let platform: String?
}
