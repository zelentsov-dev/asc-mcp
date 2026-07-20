import Foundation

enum ASCSubscriptionPlanType: String, Codable, CaseIterable, Sendable {
    case monthly = "MONTHLY"
    case upfront = "UPFRONT"
}

struct ASCSubscriptionPlanAvailabilityResponse: Codable, Sendable {
    let data: ASCSubscriptionPlanAvailability
    let included: [ASCTerritory]?
    let links: ASCPagedDocumentLinks
}

struct ASCSubscriptionPlanAvailabilitiesResponse: Codable, Sendable {
    let data: [ASCSubscriptionPlanAvailability]
    let included: [ASCTerritory]?
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCSubscriptionPlanAvailability: Codable, Sendable {
    let type: String
    let id: String
    let attributes: Attributes?
    let relationships: Relationships?

    struct Attributes: Codable, Sendable {
        let availableInNewTerritories: Bool?
        let planType: ASCSubscriptionPlanType?
    }

    struct Relationships: Codable, Sendable {
        let availableTerritories: ASCPricingPagedRelationship?
    }
}

struct ASCSubscriptionPlanAvailabilityCreateRequest: Codable, Sendable {
    let data: Resource

    init(
        subscriptionID: String,
        planType: ASCSubscriptionPlanType,
        territoryIDs: [String],
        availableInNewTerritories: NullableAttributeValue?
    ) {
        data = Resource(
            type: "subscriptionPlanAvailabilities",
            attributes: Attributes(
                availableInNewTerritories: availableInNewTerritories,
                planType: planType
            ),
            relationships: Relationships(
                availableTerritories: ToManyRelationship(
                    data: territoryIDs.map { ASCResourceIdentifier(type: "territories", id: $0) }
                ),
                subscription: ToOneRelationship(
                    data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionID)
                )
            )
        )
    }

    struct Resource: Codable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let availableInNewTerritories: NullableAttributeValue?
        let planType: ASCSubscriptionPlanType
    }

    struct Relationships: Codable, Sendable {
        let availableTerritories: ToManyRelationship
        let subscription: ToOneRelationship
    }

    struct ToManyRelationship: Codable, Sendable {
        let data: [ASCResourceIdentifier]
    }

    struct ToOneRelationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

struct ASCSubscriptionPlanAvailabilityUpdateRequest: Codable, Sendable {
    let data: Resource

    init(
        id: String,
        availableInNewTerritories: NullableAttributeValue?,
        territoryIDs: [String]?
    ) {
        data = Resource(
            type: "subscriptionPlanAvailabilities",
            id: id,
            attributes: availableInNewTerritories.map {
                Attributes(availableInNewTerritories: $0)
            },
            relationships: territoryIDs.map {
                Relationships(
                    availableTerritories: ToManyRelationship(
                        data: $0.map { ASCResourceIdentifier(type: "territories", id: $0) }
                    )
                )
            }
        )
    }

    struct Resource: Codable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes?
        let relationships: Relationships?
    }

    struct Attributes: Codable, Sendable {
        let availableInNewTerritories: NullableAttributeValue
    }

    struct Relationships: Codable, Sendable {
        let availableTerritories: ToManyRelationship
    }

    struct ToManyRelationship: Codable, Sendable {
        let data: [ASCResourceIdentifier]
    }
}

struct ASCSubscriptionAdjustedPricePointsResponse: Codable, Sendable {
    let data: [ASCSubscriptionAdjustedPricePoint]
    let included: [ASCTerritory]?
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCSubscriptionPlanTerritoriesResponse: Codable, Sendable {
    let data: [ASCTerritory]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCSubscriptionAdjustedPricePoint: Codable, Sendable {
    let type: String
    let id: String
    let attributes: SubscriptionPricePointAttributes?
    let relationships: Relationships?

    struct Relationships: Codable, Sendable {
        let territory: ASCRelationship?
    }
}
