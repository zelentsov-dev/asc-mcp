import Foundation

// MARK: - In-App Purchase V2 Models

/// In-app purchases list response
public struct ASCInAppPurchasesV2Response: Codable, Sendable {
    public let data: [ASCInAppPurchaseV2]
    public let links: ASCPagedDocumentLinks?
}

/// In-app purchase single response
public struct ASCInAppPurchaseV2Response: Codable, Sendable {
    public let data: ASCInAppPurchaseV2
}

/// In-app purchase V2 resource
public struct ASCInAppPurchaseV2: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: InAppPurchaseV2Attributes
}

/// In-app purchase V2 attributes
public struct InAppPurchaseV2Attributes: Codable, Sendable {
    public let name: String?
    public let productId: String?
    public let inAppPurchaseType: String?
    public let state: String?
    public let reviewNote: String?
    public let familySharable: Bool?
    public let contentHosting: Bool?
}

// MARK: - IAP Request Models

/// Create in-app purchase V2 request
public struct CreateInAppPurchaseV2Request: Codable, Sendable {
    public let data: CreateIAPData

    public struct CreateIAPData: Codable, Sendable {
        public let type: String = "inAppPurchases"
        public let attributes: CreateIAPAttributes
        public let relationships: CreateIAPRelationships
    }

    public struct CreateIAPAttributes: Codable, Sendable {
        public let name: String
        public let productId: String
        public let inAppPurchaseType: String
        public let reviewNote: String?
        public let familySharable: Bool?
    }

    public struct CreateIAPRelationships: Codable, Sendable {
        public let app: AppRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update in-app purchase V2 request
public struct UpdateInAppPurchaseV2Request: Codable, Sendable {
    public let data: UpdateIAPData

    public struct UpdateIAPData: Codable, Sendable {
        public let type: String = "inAppPurchases"
        public let id: String
        public let attributes: UpdateIAPAttributes
    }

    public struct UpdateIAPAttributes: Codable, Sendable {
        public let name: String?
        public let reviewNote: String?
        public let familySharable: Bool?
    }
}

// MARK: - IAP Localization Models

/// IAP localizations response
public struct ASCInAppPurchaseLocalizationsResponse: Codable, Sendable {
    public let data: [ASCInAppPurchaseLocalization]
    public let links: ASCPagedDocumentLinks?
}

/// IAP localization resource
public struct ASCInAppPurchaseLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: InAppPurchaseLocalizationAttributes
}

/// IAP localization attributes
public struct InAppPurchaseLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let name: String?
    public let description: String?
}

// MARK: - Subscription Group Models

/// Subscription groups response
public struct ASCSubscriptionGroupsResponse: Codable, Sendable {
    public let data: [ASCSubscriptionGroup]
    public let links: ASCPagedDocumentLinks?
}

/// Subscription group single response
public struct ASCSubscriptionGroupResponse: Codable, Sendable {
    public let data: ASCSubscriptionGroup
}

/// Subscription group resource
public struct ASCSubscriptionGroup: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubscriptionGroupAttributes
}

/// Subscription group attributes
public struct SubscriptionGroupAttributes: Codable, Sendable {
    public let referenceName: String?
}

// MARK: - IAP Localization Single Response

/// Single IAP localization response
public struct ASCInAppPurchaseLocalizationResponse: Codable, Sendable {
    public let data: ASCInAppPurchaseLocalization
}

// MARK: - IAP Localization Request Models

/// Create IAP localization request
public struct CreateInAppPurchaseLocalizationRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "inAppPurchaseLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let locale: String
        public let name: String
        public let description: String?
    }

    public struct Relationships: Codable, Sendable {
        public let inAppPurchaseV2: InAppPurchaseRelationship
    }

    public struct InAppPurchaseRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update IAP localization request
public struct UpdateInAppPurchaseLocalizationRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "inAppPurchaseLocalizations"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let description: String?
    }
}

// MARK: - IAP Submission Request Models

/// Create IAP submission request
public struct CreateInAppPurchaseSubmissionRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "inAppPurchaseSubmissions"
        public let relationships: Relationships
    }

    public struct Relationships: Codable, Sendable {
        public let inAppPurchaseV2: InAppPurchaseRelationship
    }

    public struct InAppPurchaseRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - IAP Price Points

/// IAP price points list response
public struct ASCIAPPricePointsResponse: Codable, Sendable {
    public let data: [ASCIAPPricePoint]
    public let links: ASCPagedDocumentLinks?
}

/// IAP price point resource
public struct ASCIAPPricePoint: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: IAPPricePointAttributes?
}

/// IAP price point attributes
public struct IAPPricePointAttributes: Codable, Sendable {
    public let customerPrice: String?
    public let proceeds: String?
    public let priceTier: String?
}

// MARK: - IAP Price Schedule

/// IAP price schedule response
public struct ASCIAPPriceScheduleResponse: Codable, Sendable {
    public let data: ASCIAPPriceSchedule
}

/// IAP price schedule resource
public struct ASCIAPPriceSchedule: Codable, Sendable {
    public let type: String
    public let id: String
}

// MARK: - Create IAP Price Schedule

/// Create IAP price schedule request
public struct CreateIAPPriceScheduleRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "inAppPurchasePriceSchedules"
        public let relationships: Relationships
    }

    public struct Relationships: Codable, Sendable {
        public let inAppPurchase: InAppPurchaseRelationship
        public let manualPrices: ManualPricesRelationship
        public let baseTerritory: BaseTerritoryRelationship
    }

    public struct InAppPurchaseRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct ManualPricesRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }

    public struct BaseTerritoryRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - IAP Review Screenshot

/// IAP review screenshot response
public struct ASCIAPReviewScreenshotResponse: Codable, Sendable {
    public let data: ASCIAPReviewScreenshot
}

/// IAP review screenshot resource
public struct ASCIAPReviewScreenshot: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: IAPReviewScreenshotAttributes?
}

/// IAP review screenshot attributes
public struct IAPReviewScreenshotAttributes: Codable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let imageAsset: ASCImageAssetSimple?
    public let assetToken: String?
    public let sourceFileChecksum: String?
    public let assetDeliveryState: ASCAssetDeliveryStateSimple?
}

/// Simple image asset model
public struct ASCImageAssetSimple: Codable, Sendable {
    public let templateUrl: String?
    public let width: Int?
    public let height: Int?
}

/// Simple asset delivery state model
public struct ASCAssetDeliveryStateSimple: Codable, Sendable {
    public let state: String?
    public let errors: [ASCAssetDeliveryErrorSimple]?
}

/// Simple asset delivery error model
public struct ASCAssetDeliveryErrorSimple: Codable, Sendable {
    public let code: String?
    public let description: String?
}

// MARK: - Create IAP Review Screenshot Request

/// Create IAP review screenshot request
public struct CreateIAPReviewScreenshotRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "inAppPurchaseAppStoreReviewScreenshots"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let fileName: String
        public let fileSize: Int
    }

    public struct Relationships: Codable, Sendable {
        public let inAppPurchaseV2: InAppPurchaseRelationship
    }

    public struct InAppPurchaseRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
