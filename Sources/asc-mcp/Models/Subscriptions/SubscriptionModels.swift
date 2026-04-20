import Foundation

// MARK: - Subscription Models

/// Subscriptions list response
public struct ASCSubscriptionsResponse: Codable, Sendable {
    public let data: [ASCSubscription]
    public let links: ASCPagedDocumentLinks?
}

/// Subscription single response
public struct ASCSubscriptionResponse: Codable, Sendable {
    public let data: ASCSubscription
}

/// Subscription resource
public struct ASCSubscription: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubscriptionAttributes
}

/// Subscription attributes
public struct SubscriptionAttributes: Codable, Sendable {
    public let name: String?
    public let productId: String?
    public let familySharable: Bool?
    public let state: String?
    public let subscriptionPeriod: String?
    public let groupLevel: Int?
    public let reviewNote: String?
}

// MARK: - Subscription Localization Models

/// Subscription localizations list response
public struct ASCSubscriptionLocalizationsResponse: Codable, Sendable {
    public let data: [ASCSubscriptionLocalization]
    public let links: ASCPagedDocumentLinks?
}

/// Subscription localization single response
public struct ASCSubscriptionLocalizationResponse: Codable, Sendable {
    public let data: ASCSubscriptionLocalization
}

/// Subscription localization resource
public struct ASCSubscriptionLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubscriptionLocalizationAttributes
}

/// Subscription localization attributes
public struct SubscriptionLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let name: String?
    public let description: String?
}

// MARK: - Set All Subscription Prices (PATCH /v1/subscriptions/{id})

/// Request to set prices for all territories via PATCH subscription.
/// Uses GET /v1/subscriptionPricePoints/{id}/equalizations to get all territory price points,
/// then PATCHes the subscription with all of them in a single request.
public struct SetAllSubscriptionPricesRequest: Encodable, Sendable {
    public let data: UpdateData
    public let included: [InlinePrice]

    public struct UpdateData: Encodable, Sendable {
        public let type: String = "subscriptions"
        public let id: String
        public let relationships: Relationships
    }

    public struct Relationships: Encodable, Sendable {
        public let prices: PricesData
    }

    public struct PricesData: Encodable, Sendable {
        public let data: [PriceRef]
    }

    public struct PriceRef: Encodable, Sendable {
        public let id: String
        public let type: String = "subscriptionPrices"
    }

    public struct InlinePrice: Encodable, Sendable {
        public let id: String
        public let type: String = "subscriptionPrices"
        public let attributes: PriceAttrs
        public let relationships: InlinePriceRels
    }

    public struct PriceAttrs: Encodable, Sendable {
        public let preserveCurrentPrice: Bool
    }

    public struct InlinePriceRels: Encodable, Sendable {
        public let subscriptionPricePoint: PointRef
    }

    public struct PointRef: Encodable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - Subscription Price Models

/// Subscription prices list response
public struct ASCSubscriptionPricesResponse: Codable, Sendable {
    public let data: [ASCSubscriptionPrice]
    public let included: [ASCSubscriptionPricePoint]?
    public let links: ASCPagedDocumentLinks?
}

/// Single subscription price response
public struct ASCSubscriptionPriceResponse: Codable, Sendable {
    public let data: ASCSubscriptionPrice
}

/// Create subscription price request
public struct CreateSubscriptionPriceRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionPrices"
        public let relationships: Relationships
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
        public let subscriptionPricePoint: SubscriptionPricePointRelationship
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct SubscriptionPricePointRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Subscription price resource
public struct ASCSubscriptionPrice: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubscriptionPriceAttributes?
    public let relationships: SubscriptionPriceRelationships?
}

/// Subscription price relationships
public struct SubscriptionPriceRelationships: Codable, Sendable {
    public let subscriptionPricePoint: RelationshipData?

    public struct RelationshipData: Codable, Sendable {
        public let data: ASCResourceIdentifier?
    }
}

/// Subscription price attributes
public struct SubscriptionPriceAttributes: Codable, Sendable {
    public let startDate: String?
    public let preserved: Bool?
}

// MARK: - Subscription Price Point Models

/// Subscription price points list response
public struct ASCSubscriptionPricePointsResponse: Codable, Sendable {
    public let data: [ASCSubscriptionPricePoint]
    public let links: ASCPagedDocumentLinks?
}

/// Subscription price point resource
public struct ASCSubscriptionPricePoint: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubscriptionPricePointAttributes?
}

/// Subscription price point attributes
public struct SubscriptionPricePointAttributes: Codable, Sendable {
    public let customerPrice: String?
    public let proceeds: String?
    public let proceedsYear2: String?
}

// MARK: - Subscription Request Models

/// Create subscription request
public struct CreateSubscriptionRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptions"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
        public let productId: String
        public let subscriptionPeriod: String
        public let familySharable: Bool?
        public let groupLevel: Int?
        public let reviewNote: String?
    }

    public struct Relationships: Codable, Sendable {
        public let group: GroupRelationship
    }

    public struct GroupRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update subscription request
public struct UpdateSubscriptionRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "subscriptions"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let familySharable: Bool?
        public let groupLevel: Int?
        public let reviewNote: String?
    }
}

/// Create subscription localization request
public struct CreateSubscriptionLocalizationRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let locale: String
        public let name: String
        public let description: String?
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update subscription localization request
public struct UpdateSubscriptionLocalizationRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "subscriptionLocalizations"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let description: String?
    }
}

/// Create subscription group request
public struct CreateSubscriptionGroupRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionGroups"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let referenceName: String
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update subscription group request
public struct UpdateSubscriptionGroupRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "subscriptionGroups"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let referenceName: String?
    }
}

/// Create subscription submission request
public struct CreateSubscriptionSubmissionRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionSubmissions"
        public let relationships: Relationships
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - Subscription Availability Models

/// Create subscription availability request (enables subscription in all territories)
public struct CreateSubscriptionAvailabilityRequest: Codable, Sendable {
    public let data: CreateData
    public let included: [TerritoryResource]?

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionAvailabilities"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let availableInNewTerritories: Bool
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship2
        public let availableTerritories: TerritoriesRelationship
    }

    public struct SubscriptionRelationship2: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct TerritoriesRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }

    public struct TerritoryResource: Codable, Sendable {
        public let type: String
        public let id: String
    }
}

/// Subscription availability response
public struct ASCSubscriptionAvailabilityResponse: Codable, Sendable {
    public let data: ASCSubscriptionAvailability
}

public struct ASCSubscriptionAvailability: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AvailabilityAttributes?

    public struct AvailabilityAttributes: Codable, Sendable {
        public let availableInNewTerritories: Bool?
    }
}
