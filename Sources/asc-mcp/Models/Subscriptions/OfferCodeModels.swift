import Foundation

// MARK: - Offer Code Models

/// Offer codes list response
public struct ASCOfferCodesResponse: Codable, Sendable {
    public let data: [ASCOfferCode]
    public let links: ASCPagedDocumentLinks?
}

/// Offer code single response
public struct ASCOfferCodeResponse: Codable, Sendable {
    public let data: ASCOfferCode
}

/// Offer code resource
public struct ASCOfferCode: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: OfferCodeAttributes
}

/// Offer code attributes
public struct OfferCodeAttributes: Codable, Sendable {
    public let name: String?
    public let active: Bool?
    public let offerEligibility: String?
    public let offerMode: String?
    public let duration: String?
    public let numberOfPeriods: Int?
    public let totalNumberOfCodes: Int?
    public let customerEligibilities: [String]?
}

// MARK: - Offer Code Price Models

/// Offer code prices list response
public struct ASCOfferCodePricesResponse: Codable, Sendable {
    public let data: [ASCOfferCodePrice]
    public let links: ASCPagedDocumentLinks?
}

/// Offer code price resource
public struct ASCOfferCodePrice: Codable, Sendable {
    public let type: String
    public let id: String
}

// MARK: - One-Time Use Code Models

/// One-time use codes list response
public struct ASCOneTimeUseCodesResponse: Codable, Sendable {
    public let data: [ASCOneTimeUseCode]
    public let links: ASCPagedDocumentLinks?
}

/// One-time use code single response
public struct ASCOneTimeUseCodeResponse: Codable, Sendable {
    public let data: ASCOneTimeUseCode
}

/// One-time use code resource
public struct ASCOneTimeUseCode: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: OneTimeUseCodeAttributes?
}

/// One-time use code attributes
public struct OneTimeUseCodeAttributes: Codable, Sendable {
    public let numberOfCodes: Int?
    public let createdDate: String?
    public let expirationDate: String?
    public let active: Bool?
}

// MARK: - Offer Code Custom Code Models

/// Custom code single response
public struct ASCOfferCodeCustomCodeResponse: Codable, Sendable {
    public let data: ASCOfferCodeCustomCode
}

/// Custom code resource
public struct ASCOfferCodeCustomCode: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: OfferCodeCustomCodeAttributes?
}

/// Custom code attributes
public struct OfferCodeCustomCodeAttributes: Codable, Sendable {
    public let customCode: String?
    public let numberOfCodes: Int?
    public let totalNumberOfCodes: Int?
    public let active: Bool?
    public let expirationDate: String?
    public let createdDate: String?
}

/// Create custom code request
public struct CreateOfferCodeCustomCodeRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionOfferCodeCustomCodes"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let customCode: String
        public let numberOfCodes: Int
        public let expirationDate: String?
    }

    public struct Relationships: Codable, Sendable {
        public let offerCode: OfferCodeRelationship
    }

    public struct OfferCodeRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update custom code request
public struct UpdateOfferCodeCustomCodeRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "subscriptionOfferCodeCustomCodes"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let active: Bool?
    }
}

// MARK: - Offer Code Price Inline Create

/// Inline create for offer code price (used in included[] when creating offer codes)
public struct OfferCodePriceInlineCreate: Codable, Sendable {
    public let type: String = "subscriptionOfferCodePrices"
    public let id: String
    public let relationships: Relationships?

    public struct Relationships: Codable, Sendable {
        public let subscriptionPricePoint: PricePointRelationship?
        public let territory: TerritoryRelationship?
    }

    public struct PricePointRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct TerritoryRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - Offer Code Request Models

/// Create offer code request
public struct CreateOfferCodeRequest: Codable, Sendable {
    public let data: CreateData
    public let included: [OfferCodePriceInlineCreate]?

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionOfferCodes"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
        public let offerEligibility: String
        public let offerMode: String
        public let duration: String
        public let numberOfPeriods: Int
        public let customerEligibilities: [String]
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
        public let prices: PricesRelationship?
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct PricesRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}

/// Update offer code request
public struct UpdateOfferCodeRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "subscriptionOfferCodes"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let active: Bool?
    }
}

/// Generate one-time use codes request
public struct GenerateOneTimeCodesRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionOfferCodeOneTimeUseCodes"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let numberOfCodes: Int
        public let expirationDate: String
    }

    public struct Relationships: Codable, Sendable {
        public let offerCode: OfferCodeRelationship
    }

    public struct OfferCodeRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
