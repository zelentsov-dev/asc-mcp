import Foundation

// MARK: - Subscription Image Models

/// Subscription image single response
public struct ASCSubscriptionImageResponse: Codable, Sendable {
    public let data: ASCSubscriptionImage
}

/// Subscription image resource
public struct ASCSubscriptionImage: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubscriptionImageAttributes?
}

/// Subscription image attributes
public struct SubscriptionImageAttributes: Codable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let sourceFileChecksum: String?
    public let imageAsset: ASCImageAsset?
    public let uploadOperations: [ASCUploadOperation]?
    public let state: String?
}

/// Create subscription image reservation request
public struct CreateSubscriptionImageRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionImages"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let fileSize: Int
        public let fileName: String
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Commit subscription image request
public struct CommitSubscriptionImageRequest: Codable, Sendable {
    public let data: CommitData

    public struct CommitData: Codable, Sendable {
        public let type: String = "subscriptionImages"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let sourceFileChecksum: String?
        public let uploaded: Bool?
    }
}

// MARK: - Subscription Review Screenshot Models

/// Subscription review screenshot single response
public struct ASCSubReviewScreenshotResponse: Codable, Sendable {
    public let data: ASCSubReviewScreenshot
}

/// Subscription review screenshot resource
public struct ASCSubReviewScreenshot: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubReviewScreenshotAttributes?
}

/// Subscription review screenshot attributes
public struct SubReviewScreenshotAttributes: Codable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let sourceFileChecksum: String?
    public let imageAsset: ASCImageAsset?
    public let assetDeliveryState: ASCAssetDeliveryState?
    public let uploadOperations: [ASCUploadOperation]?
}

/// Create subscription review screenshot request
public struct CreateSubReviewScreenshotRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionAppStoreReviewScreenshots"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let fileSize: Int
        public let fileName: String
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Commit subscription review screenshot request
public struct CommitSubReviewScreenshotRequest: Codable, Sendable {
    public let data: CommitData

    public struct CommitData: Codable, Sendable {
        public let type: String = "subscriptionAppStoreReviewScreenshots"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let sourceFileChecksum: String?
        public let uploaded: Bool?
    }
}
