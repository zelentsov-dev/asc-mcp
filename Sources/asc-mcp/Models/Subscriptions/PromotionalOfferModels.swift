import Foundation

// MARK: - Promotional Offer Models

/// Promotional offers list response
public struct ASCPromotionalOffersResponse: Codable, Sendable {
    public let data: [ASCPromotionalOffer]
    public let links: ASCPagedDocumentLinks?
}

/// Promotional offer single response
public struct ASCPromotionalOfferResponse: Codable, Sendable {
    public let data: ASCPromotionalOffer
}

/// Promotional offer resource
public struct ASCPromotionalOffer: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PromotionalOfferAttributes
}

/// Promotional offer attributes
public struct PromotionalOfferAttributes: Codable, Sendable {
    public let name: String?
    public let offerCode: String?
    public let duration: String?
    public let offerMode: String?
    public let numberOfPeriods: Int?
}

// MARK: - Promotional Offer Price Models

/// Promotional offer prices list response
public struct ASCPromotionalOfferPricesResponse: Codable, Sendable {
    public let data: [ASCPromotionalOfferPrice]
    public let links: ASCPagedDocumentLinks?
}

/// Promotional offer price resource
public struct ASCPromotionalOfferPrice: Codable, Sendable {
    public let type: String
    public let id: String
}

/// Inline create for promotional offer price
public struct PromotionalOfferPriceInlineCreate: Codable, Sendable {
    public let type: String = "subscriptionPromotionalOfferPrices"
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

// MARK: - Promotional Offer Request Models

/// Create promotional offer request
public struct CreatePromotionalOfferRequest: Codable, Sendable {
    public let data: CreateData
    public let included: [PromotionalOfferPriceInlineCreate]?

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionPromotionalOffers"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
        public let offerCode: String
        public let duration: String
        public let offerMode: String
        public let numberOfPeriods: Int
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

/// Update promotional offer request (prices only, no attributes)
public struct UpdatePromotionalOfferRequest: Codable, Sendable {
    public let data: UpdateData
    public let included: [PromotionalOfferPriceInlineCreate]?

    public struct UpdateData: Codable, Sendable {
        public let type: String = "subscriptionPromotionalOffers"
        public let id: String
        public let relationships: Relationships?
    }

    public struct Relationships: Codable, Sendable {
        public let prices: PricesRelationship?
    }

    public struct PricesRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}
