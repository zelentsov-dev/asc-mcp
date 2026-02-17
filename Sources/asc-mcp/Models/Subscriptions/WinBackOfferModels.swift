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

/// Win-back offer attributes
public struct WinBackOfferAttributes: Codable, Sendable {
    public let referenceName: String?
    public let offerId: String?
    public let duration: String?
    public let offerMode: String?
    public let periodCount: Int?
    public let priority: String?
    public let customerEligibilityPaidSubscriptionDurationInMonths: Int?
    public let customerEligibilityTimeSinceLastSubscribedInMonths: Int?
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

// MARK: - Win-Back Offer Request Models

/// Create win-back offer request
public struct CreateWinBackOfferRequest: Codable, Sendable {
    public let data: CreateData

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
        public let periodCount: Int?
        public let priority: String
        public let customerEligibilityPaidSubscriptionDurationInMonths: Int?
        public let customerEligibilityTimeSinceLastSubscribedInMonths: Int?
        public let customerEligibilityWaitBetweenOffersInMonths: Int?
        public let startDate: String
        public let endDate: String?
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
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
