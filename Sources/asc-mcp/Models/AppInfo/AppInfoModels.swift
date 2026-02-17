import Foundation

// MARK: - App Info Models

/// App infos response
public struct ASCAppInfosResponse: Codable, Sendable {
    public let data: [ASCAppInfo]
    public let links: ASCPagedDocumentLinks?
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
    public let brazilAgeRating: String?
    public let brazilAgeRatingV2: String?
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
}

// MARK: - App Info Localization Models

/// App info localizations response
public struct ASCAppInfoLocalizationsResponse: Codable, Sendable {
    public let data: [ASCAppInfoLocalization]
    public let links: ASCPagedDocumentLinks?
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

// MARK: - App Info Update Request

/// Update app info request (for categories)
public struct UpdateAppInfoRequest: Codable, Sendable {
    public let data: UpdateAppInfoData

    public struct UpdateAppInfoData: Codable, Sendable {
        public let type: String = "appInfos"
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
        public let type: String = "appInfoLocalizations"
        public let id: String
        public let attributes: UpdateAppInfoLocalizationAttributes
    }

    public struct UpdateAppInfoLocalizationAttributes: Codable, Sendable {
        public let name: String?
        public let subtitle: String?
        public let privacyPolicyUrl: String?
        public let privacyChoicesUrl: String?
        public let privacyPolicyText: String?
    }
}

/// Create app info localization request
public struct CreateAppInfoLocalizationRequest: Codable, Sendable {
    public let data: CreateAppInfoLocalizationData

    public struct CreateAppInfoLocalizationData: Codable, Sendable {
        public let type: String = "appInfoLocalizations"
        public let attributes: CreateAppInfoLocalizationAttributes
        public let relationships: CreateAppInfoLocalizationRelationships
    }

    public struct CreateAppInfoLocalizationAttributes: Codable, Sendable {
        public let locale: String
        public let name: String?
        public let subtitle: String?
        public let privacyPolicyUrl: String?
        public let privacyChoicesUrl: String?
        public let privacyPolicyText: String?
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
    case appCategory(ASCAppCategory)
    case appInfoLocalization(ASCAppInfoLocalization)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "appCategories":
            let category = try ASCAppCategory(from: decoder)
            self = .appCategory(category)
        case "appInfoLocalizations":
            let localization = try ASCAppInfoLocalization(from: decoder)
            self = .appInfoLocalization(localization)
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
        case .appCategory(let category):
            try category.encode(to: encoder)
        case .appInfoLocalization(let localization):
            try localization.encode(to: encoder)
        }
    }
}

/// App category
public struct ASCAppCategory: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppCategoryAttributes?
}

/// App category attributes
public struct AppCategoryAttributes: Codable, Sendable {
    public let platforms: [String]?
}
