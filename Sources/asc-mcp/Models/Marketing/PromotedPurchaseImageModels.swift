import Foundation

// MARK: - Promoted Purchase Image Models

/// Single promoted purchase image response
public struct ASCPromotedPurchaseImageResponse: Codable, Sendable {
    public let data: ASCPromotedPurchaseImage
}

/// Promoted purchase image resource
public struct ASCPromotedPurchaseImage: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PromotedPurchaseImageAttributes?
}

/// Promoted purchase image attributes
public struct PromotedPurchaseImageAttributes: Codable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let sourceFileChecksum: String?
    public let imageAsset: ASCImageAsset?
    public let uploadOperations: [ASCUploadOperation]?
    public let state: String?
}

// MARK: - Request Models

/// Create promoted purchase image request (reserve step)
public struct CreatePromotedPurchaseImageRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "promotedPurchaseImages"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let fileSize: Int
        public let fileName: String
    }

    public struct Relationships: Codable, Sendable {
        public let promotedPurchase: PromotedPurchaseRelationship
    }

    public struct PromotedPurchaseRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Commit promoted purchase image request
public struct CommitPromotedPurchaseImageRequest: Codable, Sendable {
    public let data: CommitData

    public struct CommitData: Codable, Sendable {
        public let type: String = "promotedPurchaseImages"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let sourceFileChecksum: String?
        public let uploaded: Bool?
    }
}
