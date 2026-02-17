import Foundation

// MARK: - Build Beta Detail Models

/// Build beta detail response
public struct ASCBuildBetaDetailResponse: Codable, Sendable {
    public let data: ASCBuildBetaDetail
    public let included: [ASCBetaIncludedResource]?
}

/// Build beta detail data
public struct ASCBuildBetaDetail: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BuildBetaDetailAttributes
    public let relationships: BuildBetaDetailRelationships?
}

/// Build beta detail attributes
public struct BuildBetaDetailAttributes: Codable, Sendable {
    public let autoNotifyEnabled: Bool?
    public let internalBuildState: String?
    public let externalBuildState: String?
}

/// Build beta detail relationships
public struct BuildBetaDetailRelationships: Codable, Sendable {
    public let build: ASCRelationship?
    public let betaBuildLocalizations: ASCRelationshipMultiple?
}

// MARK: - Beta Build Localization Models

/// Beta build localizations response
public struct ASCBetaBuildLocalizationsResponse: Codable, Sendable {
    public let data: [ASCBetaBuildLocalization]
    public let links: ASCPagedDocumentLinks?
}

/// Beta build localization response
public struct ASCBetaBuildLocalizationResponse: Codable, Sendable {
    public let data: ASCBetaBuildLocalization
}

/// Beta build localization data
public struct ASCBetaBuildLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BetaBuildLocalizationAttributes
    public let relationships: BetaBuildLocalizationRelationships?
}

/// Beta build localization attributes
public struct BetaBuildLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let whatsNew: String?
    public let feedbackEmail: String?
    public let marketingUrl: String?
    public let privacyPolicyUrl: String?
    public let tvOsPrivacyPolicy: String?
}

/// Beta build localization relationships
public struct BetaBuildLocalizationRelationships: Codable, Sendable {
    public let buildBetaDetail: ASCRelationship?
}

// MARK: - Beta Group Models

/// Beta groups response
public struct ASCBetaGroupsResponse: Codable, Sendable {
    public let data: [ASCBetaGroup]
    public let links: ASCPagedDocumentLinks?
}

/// Beta group data
public struct ASCBetaGroup: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BetaGroupAttributes
    public let relationships: BetaGroupRelationships?
}

/// Beta group attributes
public struct BetaGroupAttributes: Codable, Sendable {
    public let name: String?
    public let createdDate: String?
    public let isInternalGroup: Bool?
    public let hasAccessToAllBuilds: Bool?
    public let publicLinkEnabled: Bool?
    public let publicLinkLimit: Int?
    public let publicLinkLimitEnabled: Bool?
    public let publicLink: String?
    public let publicLinkId: String?
    public let feedbackEnabled: Bool?
}

/// Beta group relationships
public struct BetaGroupRelationships: Codable, Sendable {
    public let app: ASCRelationship?
    public let builds: ASCRelationshipMultiple?
    public let betaTesters: ASCRelationshipMultiple?
}

// MARK: - Beta Tester Models

/// Beta testers response
public struct ASCBetaTestersResponse: Codable, Sendable {
    public let data: [ASCBetaTester]
    public let links: ASCPagedDocumentLinks?
}

/// Beta tester data
public struct ASCBetaTester: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BetaTesterAttributes
    public let relationships: BetaTesterRelationships?
}

/// Beta tester attributes
public struct BetaTesterAttributes: Codable, Sendable {
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let inviteType: String?
    public let state: String?
}

/// Beta tester relationships
public struct BetaTesterRelationships: Codable, Sendable {
    public let apps: ASCRelationshipMultiple?
    public let betaGroups: ASCRelationshipMultiple?
    public let builds: ASCRelationshipMultiple?
}

/// Enum for beta included resource types  
public enum ASCBetaIncludedResource: Codable, Sendable {
    case build(ASCBuild)
    case betaBuildLocalization(ASCBetaBuildLocalization)
    case app(BuildIncludedApp)
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "builds":
            let build = try ASCBuild(from: decoder)
            self = .build(build)
        case "betaBuildLocalizations":
            let localization = try ASCBetaBuildLocalization(from: decoder)
            self = .betaBuildLocalization(localization)
        case "apps":
            let app = try BuildIncludedApp(from: decoder)
            self = .app(app)
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
        case .build(let build):
            try build.encode(to: encoder)
        case .betaBuildLocalization(let localization):
            try localization.encode(to: encoder)
        case .app(let app):
            try app.encode(to: encoder)
        }
    }
}

// MARK: - Create/Update Request Models

/// Create beta build localization request
public struct CreateBetaBuildLocalizationRequest: Codable, Sendable {
    public let data: CreateBetaBuildLocalizationData
    
    public struct CreateBetaBuildLocalizationData: Codable, Sendable {
        public let type: String = "betaBuildLocalizations"
        public let attributes: BetaBuildLocalizationAttributes
        public let relationships: CreateBetaBuildLocalizationRelationships
    }
    
    public struct CreateBetaBuildLocalizationRelationships: Codable, Sendable {
        public let build: BuildRelationship
    }
    
    public struct BuildRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update beta build localization request
public struct UpdateBetaBuildLocalizationRequest: Codable, Sendable {
    public let data: UpdateBetaBuildLocalizationData
    
    public struct UpdateBetaBuildLocalizationData: Codable, Sendable {
        public let type: String = "betaBuildLocalizations"
        public let id: String
        public let attributes: BetaBuildLocalizationUpdateAttributes
    }
    
    public struct BetaBuildLocalizationUpdateAttributes: Codable, Sendable {
        public let whatsNew: String?
        public let feedbackEmail: String?
        public let marketingUrl: String?
        public let privacyPolicyUrl: String?
        public let tvOsPrivacyPolicy: String?
    }
}

// MARK: - Beta Group Request Models

/// Beta group single response
public struct ASCBetaGroupResponse: Codable, Sendable {
    public let data: ASCBetaGroup
}

/// Create beta group request
public struct CreateBetaGroupRequest: Codable, Sendable {
    public let data: CreateBetaGroupData

    public struct CreateBetaGroupData: Codable, Sendable {
        public let type: String = "betaGroups"
        public let attributes: CreateBetaGroupAttributes
        public let relationships: CreateBetaGroupRelationships
    }

    public struct CreateBetaGroupAttributes: Codable, Sendable {
        public let name: String
        public let isInternalGroup: Bool?
        public let hasAccessToAllBuilds: Bool?
        public let publicLinkEnabled: Bool?
        public let feedbackEnabled: Bool?
    }

    public struct CreateBetaGroupRelationships: Codable, Sendable {
        public let app: AppRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update beta group request
public struct UpdateBetaGroupRequest: Codable, Sendable {
    public let data: UpdateBetaGroupData

    public struct UpdateBetaGroupData: Codable, Sendable {
        public let type: String = "betaGroups"
        public let id: String
        public let attributes: UpdateBetaGroupAttributes
    }

    public struct UpdateBetaGroupAttributes: Codable, Sendable {
        public let name: String?
        public let publicLinkEnabled: Bool?
        public let publicLinkLimit: Int?
        public let feedbackEnabled: Bool?
    }
}

/// Beta group relationship bulk request (for add/remove testers)
public struct BetaGroupRelationshipRequest: Codable, Sendable {
    public let data: [ASCResourceIdentifier]
}

/// Update build beta detail request
public struct UpdateBuildBetaDetailRequest: Codable, Sendable {
    public let data: UpdateBuildBetaDetailData
    
    public struct UpdateBuildBetaDetailData: Codable, Sendable {
        public let type: String = "buildBetaDetails"
        public let id: String
        public let attributes: BuildBetaDetailUpdateAttributes
    }
    
    public struct BuildBetaDetailUpdateAttributes: Codable, Sendable {
        public let autoNotifyEnabled: Bool?
        public let internalBuildState: String?
        public let externalBuildState: String?
    }
}

// MARK: - Beta Tester Single Response

/// Single beta tester response
public struct ASCBetaTesterResponse: Codable, Sendable {
    public let data: ASCBetaTester
    public let included: [ASCBetaTesterIncludedResource]?
}

/// Enum for beta tester included resource types
public enum ASCBetaTesterIncludedResource: Codable, Sendable {
    case app(BuildIncludedApp)
    case betaGroup(ASCBetaGroup)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "apps":
            let app = try BuildIncludedApp(from: decoder)
            self = .app(app)
        case "betaGroups":
            let group = try ASCBetaGroup(from: decoder)
            self = .betaGroup(group)
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
        case .app(let app):
            try app.encode(to: encoder)
        case .betaGroup(let group):
            try group.encode(to: encoder)
        }
    }
}

// MARK: - Create Beta Tester Request

/// Create beta tester request
public struct CreateBetaTesterRequest: Codable, Sendable {
    public let data: CreateBetaTesterData

    public struct CreateBetaTesterData: Codable, Sendable {
        public let type: String = "betaTesters"
        public let attributes: CreateBetaTesterAttributes
        public let relationships: CreateBetaTesterRelationships?
    }

    public struct CreateBetaTesterAttributes: Codable, Sendable {
        public let email: String
        public let firstName: String?
        public let lastName: String?
    }

    public struct CreateBetaTesterRelationships: Codable, Sendable {
        public let betaGroups: BetaGroupsRelationship?
        public let builds: BuildsRelationship?
    }

    public struct BetaGroupsRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }

    public struct BuildsRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}