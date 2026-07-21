import Foundation

/// A paginated collection of App Store search keyword identifiers.
public struct ASCAppKeywordsResponse: Codable, Sendable {
    public let data: [ASCAppKeyword]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

/// An App Store search keyword resource identifier.
public struct ASCAppKeyword: Codable, Sendable {
    public let type: String
    public let id: String
    public let links: ASCResourceLinks?
}
