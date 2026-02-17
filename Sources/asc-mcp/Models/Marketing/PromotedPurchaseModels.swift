import Foundation

// MARK: - Promoted Purchase Models

/// Promoted purchases list response
public struct ASCPromotedPurchasesResponse: Codable, Sendable {
    public let data: [ASCPromotedPurchase]
    public let links: ASCPagedDocumentLinks?
}

/// Single promoted purchase response
public struct ASCPromotedPurchaseResponse: Codable, Sendable {
    public let data: ASCPromotedPurchase
}

/// Promoted purchase resource
public struct ASCPromotedPurchase: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PromotedPurchaseAttributes?
}

/// Promoted purchase attributes
public struct PromotedPurchaseAttributes: Codable, Sendable {
    public let visibleForAllUsers: Bool?
    public let enabled: Bool?
    public let state: String?
}

// MARK: - Promotion Image Models

/// Promotion images list response
public struct ASCPromotionImagesResponse: Codable, Sendable {
    public let data: [ASCPromotionImage]
    public let links: ASCPagedDocumentLinks?
}

/// Promotion image resource
public struct ASCPromotionImage: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PromotionImageAttributes?
}

/// Promotion image attributes
public struct PromotionImageAttributes: Codable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let imageAsset: ASCImageAsset?
    public let assetToken: String?
    public let sourceFileChecksum: String?
    public let assetDeliveryState: ASCAssetDeliveryState?
}

// MARK: - Request Models

/// Create promoted purchase request
public struct CreatePromotedPurchaseRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "promotedPurchases"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let visibleForAllUsers: Bool
        public let enabled: Bool
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship
        public let inAppPurchaseV2: IAPRelationship?
        public let subscription: SubscriptionRelationship?
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct IAPRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update promoted purchase request
public struct UpdatePromotedPurchaseRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "promotedPurchases"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let visibleForAllUsers: Bool?
        public let enabled: Bool?
    }
}
