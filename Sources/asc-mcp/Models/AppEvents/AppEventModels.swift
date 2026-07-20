import Foundation

// MARK: - App Event Models

/// App events list response
public struct ASCAppEventsResponse: Codable, Sendable {
    public let data: [ASCAppEvent]
    public let included: [ASCAppEventIncludedResource]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
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
    public let primaryLocale: String?
    public let priority: String?
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
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// App event localization resource
public struct ASCAppEventLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppEventLocalizationAttributes?
    public let relationships: AppEventLocalizationRelationships?
}

/// App event localization attributes
public struct AppEventLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let name: String?
    public let shortDescription: String?
    public let longDescription: String?
}

public struct AppEventLocalizationRelationships: Codable, Sendable {
    public let appEvent: ASCRelationship?
    public let appEventScreenshots: ASCRelationshipMultiple?
    public let appEventVideoClips: ASCRelationshipMultiple?
}

// MARK: - Included Resources

/// Polymorphic included resource for app event responses
public enum ASCAppEventIncludedResource: Codable, Sendable {
    case localization(ASCAppEventLocalization)
    case unknown(JSONValue)

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
            self = .unknown(try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .localization(let loc):
            try loc.encode(to: encoder)
        case .unknown(let value):
            try value.encode(to: encoder)
        }
    }
}

/// Encodes either a concrete app-event attribute value or an explicit JSON null.
public enum AppEventNullable<Value: Codable & Sendable>: Codable, Sendable {
    case value(Value)
    case null

    /// Decodes a concrete value or JSON null.
    /// - Parameter decoder: Decoder positioned at the attribute value.
    /// - Throws: A decoding error when the concrete value does not match `Value`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .value(try container.decode(Value.self))
        }
    }

    /// Encodes the concrete value or JSON null.
    /// - Parameter encoder: Encoder for the attribute value.
    /// - Throws: An encoding error from the concrete value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

// MARK: - Create/Update Requests

/// Create app event request body
public struct CreateAppEventRequest: Codable, Sendable {
    public let data: CreateAppEventData

    public struct CreateAppEventData: Codable, Sendable {
        public var type: String = "appEvents"
        public let attributes: CreateAppEventAttributes
        public let relationships: CreateAppEventRelationships
    }

    public struct CreateAppEventAttributes: Codable, Sendable {
        public let referenceName: String
        public let badge: AppEventNullable<String>?
        public let deepLink: AppEventNullable<String>?
        public let purchaseRequirement: AppEventNullable<String>?
        public let primaryLocale: AppEventNullable<String>?
        public let priority: AppEventNullable<String>?
        public let purpose: AppEventNullable<String>?
        public let territorySchedules: AppEventNullable<[TerritorySchedule]>?
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
        public var type: String = "appEvents"
        public let id: String
        public let attributes: UpdateAppEventAttributes
    }

    public struct UpdateAppEventAttributes: Codable, Sendable {
        public let referenceName: AppEventNullable<String>?
        public let badge: AppEventNullable<String>?
        public let deepLink: AppEventNullable<String>?
        public let purchaseRequirement: AppEventNullable<String>?
        public let primaryLocale: AppEventNullable<String>?
        public let priority: AppEventNullable<String>?
        public let purpose: AppEventNullable<String>?
        public let territorySchedules: AppEventNullable<[TerritorySchedule]>?

        var hasChanges: Bool {
            referenceName != nil ||
                badge != nil ||
                deepLink != nil ||
                purchaseRequirement != nil ||
                primaryLocale != nil ||
                priority != nil ||
                purpose != nil ||
                territorySchedules != nil
        }
    }
}

// MARK: - App Event Localization Request Models

/// Request body for creating an app event localization
public struct CreateAppEventLocalizationRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "appEventLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let locale: String
        public let name: AppEventNullable<String>?
        public let shortDescription: AppEventNullable<String>?
        public let longDescription: AppEventNullable<String>?
    }

    public struct Relationships: Codable, Sendable {
        public let appEvent: AppEventRelationship
    }

    public struct AppEventRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Request body for updating an app event localization
public struct UpdateAppEventLocalizationRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public var type: String = "appEventLocalizations"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: AppEventNullable<String>?
        public let shortDescription: AppEventNullable<String>?
        public let longDescription: AppEventNullable<String>?

        var hasChanges: Bool {
            name != nil || shortDescription != nil || longDescription != nil
        }
    }
}

/// Single app event localization response
public struct ASCAppEventLocalizationSingleResponse: Codable, Sendable {
    public let data: ASCAppEventLocalization
}
