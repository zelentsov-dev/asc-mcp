import Foundation

// MARK: - Create App Availability v2 Request

/// Request body for creating app availability via v2 endpoint
public struct CreateAppAvailabilityV2Request: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "appAvailabilities"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let availableInNewTerritories: Bool
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship
        public let territoryAvailabilities: TerritoryAvailabilitiesRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct TerritoryAvailabilitiesRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}
