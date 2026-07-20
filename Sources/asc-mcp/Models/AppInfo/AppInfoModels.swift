import Foundation

// MARK: - App Info Models

/// App infos response
public struct ASCAppInfosResponse: Codable, Sendable {
    public let data: [ASCAppInfo]
    public let included: [ASCAppInfoIncludedResource]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// App info single response
public struct ASCAppInfoResponse: Codable, Sendable {
    public let data: ASCAppInfo
    public let included: [ASCAppInfoIncludedResource]?
}

/// App info data
public struct ASCAppInfo: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppInfoAttributes?
    public let relationships: AppInfoRelationships?
}

/// App info attributes
public struct AppInfoAttributes: Codable, Sendable {
    public let appStoreState: String?
    public let appStoreAgeRating: String?
    public let australiaAgeRating: String?
    public let brazilAgeRating: String?
    public let brazilAgeRatingV2: String?
    public let franceAgeRating: String?
    public let koreaAgeRating: String?
    public let kidsAgeBand: String?
    public let state: String?
}

/// App info relationships
public struct AppInfoRelationships: Codable, Sendable {
    public let app: ASCRelationship?
    public let ageRatingDeclaration: ASCRelationship?
    public let primaryCategory: ASCRelationship?
    public let primarySubcategoryOne: ASCRelationship?
    public let primarySubcategoryTwo: ASCRelationship?
    public let secondaryCategory: ASCRelationship?
    public let secondarySubcategoryOne: ASCRelationship?
    public let secondarySubcategoryTwo: ASCRelationship?
    public let appInfoLocalizations: ASCRelationshipMultiple?
    public let territoryAgeRatings: ASCRelationshipMultiple?
}

// MARK: - App Info Localization Models

/// App info localizations response
public struct ASCAppInfoLocalizationsResponse: Codable, Sendable {
    public let data: [ASCAppInfoLocalization]
    public let included: [ASCAppInfo]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// App info localization single response
public struct ASCAppInfoLocalizationResponse: Codable, Sendable {
    public let data: ASCAppInfoLocalization
}

/// App info localization data
public struct ASCAppInfoLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppInfoLocalizationAttributes?
    public let relationships: AppInfoLocalizationRelationships?
}

/// App info localization attributes
public struct AppInfoLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let name: String?
    public let subtitle: String?
    public let privacyPolicyUrl: String?
    public let privacyChoicesUrl: String?
    public let privacyPolicyText: String?
}

public struct AppInfoLocalizationRelationships: Codable, Sendable {
    public let appInfo: ASCRelationship?
}

// MARK: - App Info Update Request

/// Update app info request (for categories)
public struct UpdateAppInfoRequest: Codable, Sendable {
    public let data: UpdateAppInfoData

    public struct UpdateAppInfoData: Codable, Sendable {
        public var type: String = "appInfos"
        public let id: String
        public let relationships: UpdateAppInfoRelationships?
    }

    public struct UpdateAppInfoRelationships: Codable, Sendable {
        public let primaryCategory: CategoryRelationship?
        public let primarySubcategoryOne: CategoryRelationship?
        public let primarySubcategoryTwo: CategoryRelationship?
        public let secondaryCategory: CategoryRelationship?
        public let secondarySubcategoryOne: CategoryRelationship?
        public let secondarySubcategoryTwo: CategoryRelationship?

        var hasChanges: Bool {
            primaryCategory != nil ||
                primarySubcategoryOne != nil ||
                primarySubcategoryTwo != nil ||
                secondaryCategory != nil ||
                secondarySubcategoryOne != nil ||
                secondarySubcategoryTwo != nil
        }
    }

    public struct CategoryRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier?
    }
}

// MARK: - App Info Localization Requests

/// Update app info localization request
public struct UpdateAppInfoLocalizationRequest: Codable, Sendable {
    public let data: UpdateAppInfoLocalizationData

    public struct UpdateAppInfoLocalizationData: Codable, Sendable {
        public var type: String = "appInfoLocalizations"
        public let id: String
        public let attributes: UpdateAppInfoLocalizationAttributes
    }

    public struct UpdateAppInfoLocalizationAttributes: Codable, Sendable {
        public let name: JSONValue?
        public let subtitle: JSONValue?
        public let privacyPolicyUrl: JSONValue?
        public let privacyChoicesUrl: JSONValue?
        public let privacyPolicyText: JSONValue?
    }
}

/// Create app info localization request
public struct CreateAppInfoLocalizationRequest: Codable, Sendable {
    public let data: CreateAppInfoLocalizationData

    public struct CreateAppInfoLocalizationData: Codable, Sendable {
        public var type: String = "appInfoLocalizations"
        public let attributes: CreateAppInfoLocalizationAttributes
        public let relationships: CreateAppInfoLocalizationRelationships
    }

    public struct CreateAppInfoLocalizationAttributes: Codable, Sendable {
        public let locale: String
        public let name: String
        public let subtitle: JSONValue?
        public let privacyPolicyUrl: JSONValue?
        public let privacyChoicesUrl: JSONValue?
        public let privacyPolicyText: JSONValue?
    }

    public struct CreateAppInfoLocalizationRelationships: Codable, Sendable {
        public let appInfo: AppInfoRelationshipData
    }

    public struct AppInfoRelationshipData: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - App Info Included Resource

/// Included resources for app info response
public enum ASCAppInfoIncludedResource: Codable, Sendable {
    case app(ASCAppInfoIncludedApp)
    case ageRatingDeclaration(ASCAgeRatingDeclaration)
    case appCategory(ASCAppCategory)
    case appInfoLocalization(ASCAppInfoLocalization)
    case unknown(JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "apps":
            self = .app(try ASCAppInfoIncludedApp(from: decoder))
        case "ageRatingDeclarations":
            self = .ageRatingDeclaration(try ASCAgeRatingDeclaration(from: decoder))
        case "appCategories":
            let category = try ASCAppCategory(from: decoder)
            self = .appCategory(category)
        case "appInfoLocalizations":
            let localization = try ASCAppInfoLocalization(from: decoder)
            self = .appInfoLocalization(localization)
        default:
            self = .unknown(try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .app(let app):
            try app.encode(to: encoder)
        case .ageRatingDeclaration(let declaration):
            try declaration.encode(to: encoder)
        case .appCategory(let category):
            try category.encode(to: encoder)
        case .appInfoLocalization(let localization):
            try localization.encode(to: encoder)
        case .unknown(let value):
            try value.encode(to: encoder)
        }
    }
}

public struct ASCAppInfoIncludedApp: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: [String: JSONValue]?
    public let relationships: [String: JSONValue]?
    public let links: [String: JSONValue]?
}

public struct ASCAgeRatingDeclaration: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: [String: JSONValue]?
    public let links: [String: JSONValue]?
}

/// App category
public struct ASCAppCategory: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppCategoryAttributes?
    public let relationships: [String: JSONValue]?
    public let links: [String: JSONValue]?
}

/// App category attributes
public struct AppCategoryAttributes: Codable, Sendable {
    public let platforms: [String]?
}

// MARK: - EULA Models

/// EULA response
public struct ASCEULAResponse: Codable, Sendable {
    public let data: ASCEULA
}

/// EULA data
public struct ASCEULA: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: EULAAttributes?
    public let relationships: EULARelationships?
}

/// EULA attributes
public struct EULAAttributes: Codable, Sendable {
    public let agreementText: String?
}

public struct EULARelationships: Codable, Sendable {
    public let app: ASCRelationship?
    public let territories: ASCRelationshipMultiple?
}

/// Create EULA request
public struct CreateEULARequest: Encodable, Sendable {
    public let data: CreateEULAData

    public struct CreateEULAData: Encodable, Sendable {
        public let type = "endUserLicenseAgreements"
        public let attributes: CreateEULAAttributes
        public let relationships: CreateEULARelationships
    }

    public struct CreateEULAAttributes: Encodable, Sendable {
        public let agreementText: String
    }

    public struct CreateEULARelationships: Encodable, Sendable {
        public let app: AppRelationship
        public let territories: TerritoriesRelationship
    }

    public struct AppRelationship: Encodable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct TerritoriesRelationship: Encodable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}

/// Update EULA request
public struct UpdateEULARequest: Encodable, Sendable {
    public let data: UpdateEULAData

    public struct UpdateEULAData: Encodable, Sendable {
        public let type = "endUserLicenseAgreements"
        public let id: String
        public let attributes: UpdateEULAAttributes?
        public let relationships: UpdateEULARelationships?
    }

    public struct UpdateEULAAttributes: Encodable, Sendable {
        public let agreementText: JSONValue?
    }

    public struct UpdateEULARelationships: Encodable, Sendable {
        public let territories: TerritoriesRelationship
    }

    public struct TerritoriesRelationship: Encodable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}
