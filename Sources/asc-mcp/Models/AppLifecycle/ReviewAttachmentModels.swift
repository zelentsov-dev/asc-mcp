import Foundation

// MARK: - Review Attachment Models

/// Review attachments list response
public struct ASCReviewAttachmentsResponse: Codable, Sendable {
    public let data: [ASCReviewAttachment]
    public let links: ASCPagedDocumentLinks?
}

/// Single review attachment response
public struct ASCReviewAttachmentResponse: Codable, Sendable {
    public let data: ASCReviewAttachment
}

/// Review attachment resource
public struct ASCReviewAttachment: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: ReviewAttachmentAttributes?
}

/// Review attachment attributes
public struct ReviewAttachmentAttributes: Codable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let sourceFileChecksum: String?
    public let uploadOperations: [ASCUploadOperation]?
    public let assetDeliveryState: ASCAssetDeliveryState?
}

// MARK: - Review Attachment Request Models

/// Create review attachment reservation request
public struct CreateReviewAttachmentRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "appStoreReviewAttachments"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let fileSize: Int
        public let fileName: String
    }

    public struct Relationships: Codable, Sendable {
        public let appStoreReviewDetail: ReviewDetailRelationship
    }

    public struct ReviewDetailRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Commit review attachment request
public struct CommitReviewAttachmentRequest: Codable, Sendable {
    public let data: CommitData

    public struct CommitData: Codable, Sendable {
        public let type: String = "appStoreReviewAttachments"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let sourceFileChecksum: String?
        public let uploaded: Bool?
    }
}
