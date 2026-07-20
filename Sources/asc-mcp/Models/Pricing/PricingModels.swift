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
    public let included: [ASCTerritoryAvailability]?
    public let links: ASCPagedDocumentLinks?
}

/// App availability data
public struct ASCAppAvailabilityV2: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppAvailabilityV2Attributes?
    public let relationships: AppAvailabilityV2Relationships?
    public let links: ASCResourceLinks?
}

/// App availability attributes
public struct AppAvailabilityV2Attributes: Codable, Sendable {
    public let availableInNewTerritories: Bool?
}

/// App availability relationships
public struct AppAvailabilityV2Relationships: Codable, Sendable {
    public let territoryAvailabilities: ASCPricingPagedRelationship?
}

/// To-many pricing relationship with paging information
public struct ASCPricingPagedRelationship: Codable, Sendable {
    public let links: ASCRelationshipLinks?
    public let meta: ASCPagingInformation?
    public let data: [ASCResourceIdentifier]?
}

// MARK: - Territory Availability Models

/// Territory availability response
public struct ASCTerritoryAvailabilitiesResponse: Codable, Sendable {
    public let data: [ASCTerritoryAvailability]
    public let included: [ASCTerritory]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
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
    public let preOrderPublishDate: String?
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
    public let links: ASCPagedDocumentLinks?
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
    public let manualPricesMeta: ASCPagingInformation?
    public let automaticPricesMeta: ASCPagingInformation?

    private enum CodingKeys: String, CodingKey {
        case manualPrices
        case automaticPrices
        case baseTerritory
    }

    private struct PagedRelationship: Codable {
        let links: ASCRelationshipLinks?
        let meta: ASCPagingInformation?
        let data: [ASCResourceIdentifier]?
    }

    /// Decodes schedule relationships while preserving nested paging metadata.
    /// - Returns: A decoded price schedule relationships value.
    /// - Throws: A decoding error when relationship data is malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let manual = try container.decodeIfPresent(PagedRelationship.self, forKey: .manualPrices)
        let automatic = try container.decodeIfPresent(PagedRelationship.self, forKey: .automaticPrices)

        manualPrices = manual.map { ASCRelationshipMultiple(links: $0.links, data: $0.data) }
        automaticPrices = automatic.map { ASCRelationshipMultiple(links: $0.links, data: $0.data) }
        baseTerritory = try container.decodeIfPresent(ASCRelationship.self, forKey: .baseTerritory)
        manualPricesMeta = manual?.meta
        automaticPricesMeta = automatic?.meta
    }

    /// Encodes schedule relationships and their nested paging metadata.
    /// - Returns: No value; the relationships are written to the encoder.
    /// - Throws: An encoding error when the encoder cannot write a relationship.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let manualPrices {
            try container.encode(
                PagedRelationship(
                    links: manualPrices.links,
                    meta: manualPricesMeta,
                    data: manualPrices.data
                ),
                forKey: .manualPrices
            )
        }
        if let automaticPrices {
            try container.encode(
                PagedRelationship(
                    links: automaticPrices.links,
                    meta: automaticPricesMeta,
                    data: automaticPrices.data
                ),
                forKey: .automaticPrices
            )
        }
        try container.encodeIfPresent(baseTerritory, forKey: .baseTerritory)
    }
}

// MARK: - Pricing Included Resources

/// Polymorphic included resources in pricing responses
public enum ASCPricingIncludedResource: Codable, Sendable {
    case app(ASCApp)
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
        case "apps":
            let app = try ASCApp(from: decoder)
            self = .app(app)
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
        case .app(let app): try app.encode(to: encoder)
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
        public var type: String = "appPriceSchedules"
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
    public var type: String = "appPrices"
    public let id: String
    public let attributes: Attributes
    public let relationships: CreateAppPriceInlineRelationships

    public struct Attributes: Codable, Sendable {
        public let startDate: String?
        public let endDate: String?

        private enum CodingKeys: String, CodingKey {
            case startDate
            case endDate
        }

        /// Creates nullable start and end boundaries for an inline app price.
        /// - Returns: An inline app price attributes value.
        /// - Throws: Never.
        public init(startDate: String?, endDate: String?) {
            self.startDate = startDate
            self.endDate = endDate
        }

        /// Decodes nullable app price date boundaries.
        /// - Returns: A decoded inline app price attributes value.
        /// - Throws: A decoding error when a date boundary has an invalid type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
            endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        }

        /// Encodes both app price date boundaries, preserving explicit nulls.
        /// - Returns: No value; the boundaries are written to the encoder.
        /// - Throws: An encoding error when the encoder cannot write a boundary.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(startDate, forKey: .startDate)
            try container.encode(endDate, forKey: .endDate)
        }
    }

    public struct CreateAppPriceInlineRelationships: Codable, Sendable {
        public let appPricePoint: AppPricePointRelationship
    }

    public struct AppPricePointRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
