import Foundation

// MARK: - Territory Models

/// Territories response
public struct ASCTerritoriesResponse: Codable, Sendable {
    public let data: [ASCTerritory]
    public let links: ASCPagedDocumentLinks?
}

/// Territory data
public struct ASCTerritory: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: TerritoryAttributes?
}

/// Territory attributes
public struct TerritoryAttributes: Codable, Sendable {
    public let currency: String?
}

// MARK: - App Availability Models (v2)

/// App availability response
public struct ASCAppAvailabilityV2Response: Codable, Sendable {
    public let data: ASCAppAvailabilityV2
}

/// App availability data
public struct ASCAppAvailabilityV2: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppAvailabilityV2Attributes?
}

/// App availability attributes
public struct AppAvailabilityV2Attributes: Codable, Sendable {
    public let availableInNewTerritories: Bool?
}

// MARK: - Territory Availability Models

/// Territory availability response
public struct ASCTerritoryAvailabilitiesResponse: Codable, Sendable {
    public let data: [ASCTerritoryAvailability]
    public let links: ASCPagedDocumentLinks?
}

/// Territory availability data
public struct ASCTerritoryAvailability: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: TerritoryAvailabilityAttributes?
    public let relationships: TerritoryAvailabilityRelationships?
}

/// Territory availability attributes
public struct TerritoryAvailabilityAttributes: Codable, Sendable {
    public let available: Bool?
    public let releaseDate: String?
    public let preOrderEnabled: Bool?
    public let contentStatuses: [String]?
}

/// Territory availability relationships
public struct TerritoryAvailabilityRelationships: Codable, Sendable {
    public let territory: ASCRelationship?
}

// MARK: - App Price Points

/// App price points response (v3)
public struct ASCAppPricePointsV3Response: Codable, Sendable {
    public let data: [ASCAppPricePointV3]
    public let included: [ASCPricingIncludedResource]?
    public let links: ASCPagedDocumentLinks?
}

/// App price point data
public struct ASCAppPricePointV3: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppPricePointV3Attributes?
    public let relationships: AppPricePointV3Relationships?
}

/// App price point attributes
public struct AppPricePointV3Attributes: Codable, Sendable {
    public let customerPrice: String?
    public let proceeds: String?
}

/// App price point relationships
public struct AppPricePointV3Relationships: Codable, Sendable {
    public let territory: ASCRelationship?
}

// MARK: - App Price Schedule

/// App price schedule response
public struct ASCAppPriceScheduleResponse: Codable, Sendable {
    public let data: ASCAppPriceSchedule
    public let included: [ASCPricingIncludedResource]?
}

/// App price schedule data
public struct ASCAppPriceSchedule: Codable, Sendable {
    public let type: String
    public let id: String
    public let relationships: AppPriceScheduleRelationships?
}

/// App price schedule relationships
public struct AppPriceScheduleRelationships: Codable, Sendable {
    public let manualPrices: ASCRelationshipMultiple?
    public let automaticPrices: ASCRelationshipMultiple?
    public let baseTerritory: ASCRelationship?
}

// MARK: - Pricing Included Resources

/// Polymorphic included resources in pricing responses
public enum ASCPricingIncludedResource: Codable, Sendable {
    case territory(ASCTerritory)
    case appPrice(ASCAppPrice)
    case appPricePoint(ASCAppPricePointV3)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "territories":
            let territory = try ASCTerritory(from: decoder)
            self = .territory(territory)
        case "appPrices":
            let price = try ASCAppPrice(from: decoder)
            self = .appPrice(price)
        case "appPricePoints":
            let point = try ASCAppPricePointV3(from: decoder)
            self = .appPricePoint(point)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown included resource type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .territory(let t): try t.encode(to: encoder)
        case .appPrice(let p): try p.encode(to: encoder)
        case .appPricePoint(let pp): try pp.encode(to: encoder)
        }
    }
}

/// App price resource
public struct ASCAppPrice: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppPriceAttributes?
    public let relationships: AppPriceRelationships?
}

/// App price attributes
public struct AppPriceAttributes: Codable, Sendable {
    public let startDate: String?
    public let endDate: String?
    public let manual: Bool?
}

/// App price relationships
public struct AppPriceRelationships: Codable, Sendable {
    public let appPricePoint: ASCRelationship?
    public let territory: ASCRelationship?
}

// MARK: - Create Price Schedule Request

/// Request body for creating an app price schedule
public struct CreateAppPriceScheduleRequest: Codable, Sendable {
    public let data: CreateAppPriceScheduleData
    public let included: [CreateAppPriceInlineRequest]

    public struct CreateAppPriceScheduleData: Codable, Sendable {
        public let type: String = "appPriceSchedules"
        public let relationships: CreateAppPriceScheduleRelationships
    }

    public struct CreateAppPriceScheduleRelationships: Codable, Sendable {
        public let app: AppRelationship
        public let baseTerritory: BaseTerritoryRelationship
        public let manualPrices: ManualPricesRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct BaseTerritoryRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct ManualPricesRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}

/// Inline app price for creating price schedule
public struct CreateAppPriceInlineRequest: Codable, Sendable {
    public let type: String = "appPrices"
    public let id: String
    public let relationships: CreateAppPriceInlineRelationships

    public struct CreateAppPriceInlineRelationships: Codable, Sendable {
        public let appPricePoint: AppPricePointRelationship
    }

    public struct AppPricePointRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
