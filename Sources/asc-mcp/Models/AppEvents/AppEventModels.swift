import Foundation

// MARK: - App Event Models

/// App events list response
public struct ASCAppEventsResponse: Codable, Sendable {
    public let data: [ASCAppEvent]
    public let links: ASCPagedDocumentLinks?
}

/// App event single response with optional included resources
public struct ASCAppEventResponse: Codable, Sendable {
    public let data: ASCAppEvent
    public let included: [ASCAppEventIncludedResource]?
}

/// App event resource
public struct ASCAppEvent: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppEventAttributes?
    public let relationships: AppEventRelationships?
}

/// App event attributes
public struct AppEventAttributes: Codable, Sendable {
    public let referenceName: String?
    public let badge: String?
    public let deepLink: String?
    public let purchaseRequirement: String?
    public let purpose: String?
    public let eventState: String?
    public let archivedTerritorySchedules: [TerritorySchedule]?
    public let territorySchedules: [TerritorySchedule]?
}

/// Territory schedule for app event
public struct TerritorySchedule: Codable, Sendable {
    public let territories: [String]?
    public let publishStart: String?
    public let eventStart: String?
    public let eventEnd: String?
}

/// App event relationships
public struct AppEventRelationships: Codable, Sendable {
    public let localizations: ASCRelationshipMultiple?
}

// MARK: - App Event Localization

/// App event localizations list response
public struct ASCAppEventLocalizationsResponse: Codable, Sendable {
    public let data: [ASCAppEventLocalization]
    public let links: ASCPagedDocumentLinks?
}

/// App event localization resource
public struct ASCAppEventLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppEventLocalizationAttributes?
}

/// App event localization attributes
public struct AppEventLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let name: String?
    public let shortDescription: String?
    public let longDescription: String?
}

// MARK: - Included Resources

/// Polymorphic included resource for app event responses
public enum ASCAppEventIncludedResource: Codable, Sendable {
    case localization(ASCAppEventLocalization)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "appEventLocalizations":
            let loc = try ASCAppEventLocalization(from: decoder)
            self = .localization(loc)
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
        case .localization(let loc):
            try loc.encode(to: encoder)
        }
    }
}

// MARK: - Create/Update Requests

/// Create app event request body
public struct CreateAppEventRequest: Codable, Sendable {
    public let data: CreateAppEventData

    public struct CreateAppEventData: Codable, Sendable {
        public let type: String = "appEvents"
        public let attributes: CreateAppEventAttributes
        public let relationships: CreateAppEventRelationships
    }

    public struct CreateAppEventAttributes: Codable, Sendable {
        public let referenceName: String
        public let badge: String?
        public let deepLink: String?
        public let purchaseRequirement: String?
        public let purpose: String?
        public let territorySchedules: [TerritorySchedule]?
    }

    public struct CreateAppEventRelationships: Codable, Sendable {
        public let app: AppRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update app event request body
public struct UpdateAppEventRequest: Codable, Sendable {
    public let data: UpdateAppEventData

    public struct UpdateAppEventData: Codable, Sendable {
        public let type: String = "appEvents"
        public let id: String
        public let attributes: UpdateAppEventAttributes
    }

    public struct UpdateAppEventAttributes: Codable, Sendable {
        public let referenceName: String?
        public let badge: String?
        public let deepLink: String?
        public let purchaseRequirement: String?
        public let purpose: String?
    }
}
