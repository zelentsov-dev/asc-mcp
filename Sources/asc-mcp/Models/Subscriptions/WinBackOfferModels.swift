import Foundation

// MARK: - Win-Back Offer Models

/// Win-back offers list response
public struct ASCWinBackOffersResponse: Codable, Sendable {
    public let data: [ASCWinBackOffer]
    public let links: ASCPagedDocumentLinks?
}

/// Win-back offer single response
public struct ASCWinBackOfferResponse: Codable, Sendable {
    public let data: ASCWinBackOffer
}

/// Win-back offer resource
public struct ASCWinBackOffer: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: WinBackOfferAttributes
}

/// Eligibility time range with minimum and maximum months
public struct EligibilityRange: Codable, Sendable {
    public let minimum: Int
    public let maximum: Int
}

/// Win-back offer attributes
public struct WinBackOfferAttributes: Codable, Sendable {
    public let referenceName: String?
    public let offerId: String?
    public let duration: String?
    public let offerMode: String?
    public let periodCount: Int?
    public let priority: String?
    public let promotionIntent: String?
    public let customerEligibilityPaidSubscriptionDurationInMonths: Int?
    public let customerEligibilityTimeSinceLastSubscribedInMonths: EligibilityRange?
    public let customerEligibilityWaitBetweenOffersInMonths: Int?
    public let startDate: String?
    public let endDate: String?
}

// MARK: - Win-Back Offer Price Models

/// Win-back offer prices list response
public struct ASCWinBackOfferPricesResponse: Codable, Sendable {
    public let data: [ASCWinBackOfferPrice]
    public let links: ASCPagedDocumentLinks?
}

/// Win-back offer price resource
public struct ASCWinBackOfferPrice: Codable, Sendable {
    public let type: String
    public let id: String
}

/// Inline create for win-back offer price
public struct WinBackOfferPriceInlineCreate: Codable, Sendable {
    public let type: String = "winBackOfferPrices"
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

// MARK: - Win-Back Offer Request Models

/// Create win-back offer request
public struct CreateWinBackOfferRequest: Codable, Sendable {
    public let data: CreateData
    public let included: [WinBackOfferPriceInlineCreate]?

    public struct CreateData: Codable, Sendable {
        public let type: String = "winBackOffers"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let referenceName: String
        public let offerId: String
        public let duration: String
        public let offerMode: String
        public let periodCount: Int
        public let priority: String
        public let promotionIntent: String
        public let customerEligibilityPaidSubscriptionDurationInMonths: Int
        public let customerEligibilityTimeSinceLastSubscribedInMonths: EligibilityRange
        public let customerEligibilityWaitBetweenOffersInMonths: Int
        public let startDate: String
        public let endDate: String?
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

/// Update win-back offer request
public struct UpdateWinBackOfferRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "winBackOffers"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let priority: String?
        public let startDate: String?
        public let endDate: String?
    }
}
