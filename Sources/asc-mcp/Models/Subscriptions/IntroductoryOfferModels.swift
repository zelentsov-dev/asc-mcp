import Foundation

// MARK: - Introductory Offer Models

/// Introductory offers list response
public struct ASCIntroductoryOffersResponse: Codable, Sendable {
    public let data: [ASCIntroductoryOffer]
    public let links: ASCPagedDocumentLinks?
}

/// Introductory offer single response
public struct ASCIntroductoryOfferResponse: Codable, Sendable {
    public let data: ASCIntroductoryOffer
}

/// Introductory offer resource
public struct ASCIntroductoryOffer: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: IntroductoryOfferAttributes
}

/// Introductory offer attributes
public struct IntroductoryOfferAttributes: Codable, Sendable {
    public let duration: String?
    public let offerMode: String?
    public let numberOfPeriods: Int?
    public let startDate: String?
    public let endDate: String?
}

// MARK: - Introductory Offer Request Models

/// Create introductory offer request
public struct CreateIntroductoryOfferRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionIntroductoryOffers"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let duration: String
        public let offerMode: String
        public let numberOfPeriods: Int
        public let startDate: String?
        public let endDate: String?
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
        public let subscriptionPricePoint: PricePointRelationship?
        public let territory: TerritoryRelationship?
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct PricePointRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct TerritoryRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - Set All Territories Introductory Offer (PATCH /v1/subscriptions/{id})

/// Request to set FREE_TRIAL intro offer for all territories in one PATCH.
/// Uses relationships.introductoryOffers + included array with ${N} local IDs.
public struct SetAllIntroductoryOffersRequest: Encodable, Sendable {
    public let data: UpdateData
    public let included: [InlineOffer]

    public struct UpdateData: Encodable, Sendable {
        public let type: String = "subscriptions"
        public let id: String
        public let relationships: Relationships
    }

    public struct Relationships: Encodable, Sendable {
        public let introductoryOffers: OffersData
    }

    public struct OffersData: Encodable, Sendable {
        public let data: [OfferRef]
    }

    public struct OfferRef: Encodable, Sendable {
        public let id: String
        public let type: String = "subscriptionIntroductoryOffers"
    }

    public struct InlineOffer: Encodable, Sendable {
        public let id: String
        public let type: String = "subscriptionIntroductoryOffers"
        public let attributes: OfferAttrs
        public let relationships: InlineOfferRels
    }

    public struct OfferAttrs: Encodable, Sendable {
        public let duration: String
        public let offerMode: String
        public let numberOfPeriods: Int
    }

    public struct InlineOfferRels: Encodable, Sendable {
        public let territory: TerritoryRef
    }

    public struct TerritoryRef: Encodable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update introductory offer request
public struct UpdateIntroductoryOfferRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "subscriptionIntroductoryOffers"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let endDate: String?
    }
}
