import Foundation

// MARK: - Build Models

/// Build response from App Store Connect
public struct ASCBuildResponse: Codable, Sendable {
    public let data: ASCBuild
    public let included: [ASCBuildIncludedResource]?
}

/// Multiple builds response
public struct ASCBuildsResponse: Codable, Sendable {
    public let data: [ASCBuild]
    public let included: [ASCBuildIncludedResource]?
    public let links: ASCPagedDocumentLinks?
}

/// Build data structure
public struct ASCBuild: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BuildAttributes
    public let relationships: BuildRelationships?
}

/// Build attributes - based on official Apple documentation
public struct BuildAttributes: Codable, Sendable {
    public let version: String?
    public let uploadedDate: String?
    public let expirationDate: String?
    public let expired: Bool?
    public let minOsVersion: String?
    public let lsMinimumSystemVersion: String?
    public let computedMinMacOsVersion: String?
    public let iconAssetToken: ImageAsset?
    public let processingState: String? // PROCESSING, FAILED, INVALID, VALID
    public let buildAudienceType: String? // INTERNAL_ONLY, APP_STORE_ELIGIBLE
    public let usesNonExemptEncryption: Bool?
}

/// Image asset for icon
public struct ImageAsset: Codable, Sendable {
    public let templateUrl: String?
    public let width: Int?
    public let height: Int?
}

/// Build relationships
public struct BuildRelationships: Codable, Sendable {
    public let app: ASCRelationship?
    public let appEncryptionDeclaration: ASCRelationship?
    public let betaGroups: ASCRelationshipMultiple?
    public let buildBetaDetail: ASCRelationship?
    public let betaAppReviewSubmission: ASCRelationship?
    public let appStoreVersion: ASCRelationship?
    public let icons: ASCRelationshipMultiple?
    public let individualTesters: ASCRelationshipMultiple?
    public let preReleaseVersion: ASCRelationship?
    public let buildBundles: ASCRelationshipMultiple?
}

/// Relationship structure
public struct ASCRelationship: Codable, Sendable {
    public let links: ASCRelationshipLinks?
    public let data: ASCResourceIdentifier?
}

/// Multiple resource identifiers in relationship
public struct ASCRelationshipMultiple: Codable, Sendable {
    public let links: ASCRelationshipLinks?
    public let data: [ASCResourceIdentifier]?
}

/// Resource identifier
public struct ASCResourceIdentifier: Codable, Sendable {
    public let type: String
    public let id: String
}

/// Relationship links
public struct ASCRelationshipLinks: Codable, Sendable {
    public let related: String?
    public let `self`: String?
}

/// Paged document links
public struct ASCPagedDocumentLinks: Codable, Sendable {
    public let first: String?
    public let next: String?
    public let `self`: String
}

/// Enum for included resource types
public enum ASCBuildIncludedResource: Codable, Sendable {
    case app(BuildIncludedApp)
    case buildBetaDetail(ASCBuildBetaDetail)
    case preReleaseVersion(ASCPreReleaseVersion)
    case buildBundle(ASCBuildBundle)
    case betaGroup(ASCBetaGroup)
    case betaTester(ASCBetaTester)
    
    private enum CodingKeys: String, CodingKey {
        case type, id, attributes, relationships
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "apps":
            let app = try BuildIncludedApp(from: decoder)
            self = .app(app)
        case "buildBetaDetails":
            let detail = try ASCBuildBetaDetail(from: decoder)
            self = .buildBetaDetail(detail)
        case "preReleaseVersions":
            let version = try ASCPreReleaseVersion(from: decoder)
            self = .preReleaseVersion(version)
        case "buildBundles":
            let bundle = try ASCBuildBundle(from: decoder)
            self = .buildBundle(bundle)
        case "betaGroups":
            let group = try ASCBetaGroup(from: decoder)
            self = .betaGroup(group)
        case "betaTesters":
            let tester = try ASCBetaTester(from: decoder)
            self = .betaTester(tester)
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
        case .buildBetaDetail(let detail):
            try detail.encode(to: encoder)
        case .preReleaseVersion(let version):
            try version.encode(to: encoder)
        case .buildBundle(let bundle):
            try bundle.encode(to: encoder)
        case .betaGroup(let group):
            try group.encode(to: encoder)
        case .betaTester(let tester):
            try tester.encode(to: encoder)
        }
    }
}

/// App included in build response
public struct BuildIncludedApp: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BuildIncludedAppAttributes?
}

public struct BuildIncludedAppAttributes: Codable, Sendable {
    public let name: String?
    public let bundleId: String?
    public let sku: String?
    public let primaryLocale: String?
}

// MARK: - Pre-Release Version Models

/// Pre-release version for build
public struct ASCPreReleaseVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PreReleaseVersionAttributes
}

/// Pre-release version attributes
public struct PreReleaseVersionAttributes: Codable, Sendable {
    public let version: String?
    public let platform: String?
}

// MARK: - Build Bundle Models

/// Build bundle information
public struct ASCBuildBundle: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BuildBundleAttributes
}

/// Build bundle attributes
public struct BuildBundleAttributes: Codable, Sendable {
    public let bundleId: String?
    public let bundleType: String?
    public let sdkBuild: String?
    public let platformBuild: String?
    public let fileName: String?
    public let hasSirikit: Bool?
    public let hasOnDemandResources: Bool?
    public let hasPrerenderedIcon: Bool?
    public let usesLocationServices: Bool?
    public let isIosBuildMacAppStoreCompatible: Bool?
    public let includesSymbols: Bool?
    public let dSYMUrl: String?
    public let supportedArchitectures: [String]?
    public let requiredCapabilities: [String]?
    public let deviceProtocols: [String]?
    public let locales: [String]?
    public let entitlements: EntitlementsContainer?
}

/// Container for entitlements - stores as raw JSON
public struct EntitlementsContainer: Codable, Sendable {
    private let rawValue: String
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: Bool].self) {
            let data = try JSONSerialization.data(withJSONObject: dict)
            self.rawValue = String(data: data, encoding: .utf8) ?? "{}"
        } else if let str = try? container.decode(String.self) {
            self.rawValue = str
        } else {
            self.rawValue = "{}"
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let data = rawValue.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) {
            try container.encode(dict as? [String: Bool] ?? [:])
        } else {
            try container.encode([String: Bool]())
        }
    }
    
    public var dictionary: [String: Any]? {
        guard let data = rawValue.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}