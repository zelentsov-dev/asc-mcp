import Foundation

// MARK: - Create App Availability v2 Request

/// Request body for creating app availability via v2 endpoint
public struct CreateAppAvailabilityV2Request: Codable, Sendable {
    public let data: CreateData
    public let included: [TerritoryAvailabilityInlineCreate]?

    /// Creates an app availability request with optional inline territory resources.
    /// - Returns: A request containing the primary resource and any inline resources.
    /// - Throws: Never.
    public init(data: CreateData, included: [TerritoryAvailabilityInlineCreate]? = nil) {
        self.data = data
        self.included = included
    }

    public struct CreateData: Codable, Sendable {
        public var type: String = "appAvailabilities"
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

/// Inline territory availability for creating an app availability
public struct TerritoryAvailabilityInlineCreate: Codable, Sendable {
    public var type: String = "territoryAvailabilities"
    public let id: String
    public let attributes: Attributes
    public let relationships: Relationships

    public struct Attributes: Codable, Sendable {
        public let available: Bool?
        public let releaseDate: String?
        public let preOrderEnabled: Bool?

        private enum CodingKeys: String, CodingKey {
            case available
            case releaseDate
            case preOrderEnabled
        }

        /// Creates nullable attributes for an inline territory availability.
        /// Omitted MCP fields and explicit null inputs both become nil and are encoded as JSON null.
        /// - Returns: A territory availability attributes value.
        /// - Throws: Never.
        public init(available: Bool?, releaseDate: String?, preOrderEnabled: Bool?) {
            self.available = available
            self.releaseDate = releaseDate
            self.preOrderEnabled = preOrderEnabled
        }

        /// Decodes nullable territory availability attributes.
        /// - Returns: A decoded attributes value.
        /// - Throws: A decoding error when an attribute has an invalid type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            available = try container.decodeIfPresent(Bool.self, forKey: .available)
            releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
            preOrderEnabled = try container.decodeIfPresent(Bool.self, forKey: .preOrderEnabled)
        }

        /// Encodes every nullable territory availability attribute, including omitted values as JSON null.
        /// - Returns: No value; the attributes are written to the encoder.
        /// - Throws: An encoding error when the encoder cannot write an attribute.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(available, forKey: .available)
            try container.encode(releaseDate, forKey: .releaseDate)
            try container.encode(preOrderEnabled, forKey: .preOrderEnabled)
        }
    }

    public struct Relationships: Codable, Sendable {
        public let territory: TerritoryRelationship
    }

    public struct TerritoryRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
