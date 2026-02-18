import Foundation

// MARK: - App Store Connect API Models

/// App resource from App Store Connect API
public struct ASCApp: Codable, Sendable {
    public let id: String
    public let type: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    
    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let bundleId: String?
        public let sku: String?
        public let primaryLocale: String?
        public let isOrEverWasMadeForKids: Bool?
        public let subscriptionStatusUrl: String?
        public let subscriptionStatusUrlVersion: String?
        public let subscriptionStatusUrlForSandbox: String?
        public let subscriptionStatusUrlVersionForSandbox: String?
        public let availableInNewTerritories: Bool?
        public let contentRightsDeclaration: String?
    }
    
    public struct Relationships: Codable, Sendable {
        public let ciProduct: Relationship?
        public let betaGroups: Relationship?
        public let appStoreVersions: Relationship?
        public let preReleaseVersions: Relationship?
        public let betaAppLocalizations: Relationship?
        public let builds: Relationship?
        public let betaLicenseAgreement: Relationship?
        public let betaAppReviewDetail: Relationship?
        public let appInfos: Relationship?
        public let appClips: Relationship?
        public let endUserLicenseAgreement: Relationship?
        public let preOrder: Relationship?
        public let prices: Relationship?
        public let availableTerritories: Relationship?
        public let inAppPurchases: Relationship?
        public let subscriptionGroups: Relationship?
        public let gameCenterEnabledVersions: Relationship?
        public let appCustomProductPages: Relationship?
        public let inAppPurchasesV2: Relationship?
        public let promotedPurchases: Relationship?
        public let appEvents: Relationship?
        public let reviewSubmissions: Relationship?
        public let subscriptionGracePeriod: Relationship?
        public let customerReviews: Relationship?
        public let perfPowerMetrics: Relationship?
        public let appEncryptionDeclarations: Relationship?
    }
    
    public struct Relationship: Codable, Sendable {
        public let links: Links?
        public let meta: Meta?
        public let data: [ResourceIdentifier]?
        
        public struct Links: Codable, Sendable {
            public let related: String?
            public let `self`: String?
        }
        
        public struct Meta: Codable, Sendable {
            public let paging: Paging?
            
            public struct Paging: Codable, Sendable {
                public let total: Int?
                public let limit: Int?
            }
        }
    }
    
    public struct ResourceIdentifier: Codable, Sendable {
        public let id: String
        public let type: String
    }
}

/// Apps list response
public struct ASCAppsResponse: Codable, Sendable {
    public let data: [ASCApp]
    public let links: Links
    public let meta: Meta?
    
    public struct Links: Codable, Sendable {
        public let first: String?
        public let next: String?
        public let `self`: String
    }
    
    public struct Meta: Codable, Sendable {
        public let paging: Paging
        
        public struct Paging: Codable, Sendable {
            public let total: Int
            public let limit: Int
        }
    }
}

/// Single app response
public struct ASCAppResponse: Codable, Sendable {
    public let data: ASCApp
    public let links: Links
    
    public struct Links: Codable, Sendable {
        public let `self`: String
    }
}

// MARK: - Convenience Extensions

extension ASCApp {
    /// Human-readable app display name
    public var displayName: String {
        return attributes?.name ?? "Unknown App"
    }
    
    /// App bundle identifier
    public var bundleIdentifier: String {
        return attributes?.bundleId ?? "Unknown Bundle ID"
    }
    
    /// App SKU
    public var appSKU: String {
        return attributes?.sku ?? "Unknown SKU"
    }
    
    /// App primary locale
    public var locale: String {
        return attributes?.primaryLocale ?? "en-US"
    }
}

extension ASCAppsResponse {
    /// Total number of apps
    public var totalCount: Int {
        return meta?.paging.total ?? data.count
    }
    
    /// Whether there is a next page
    public var hasNextPage: Bool {
        return links.next != nil
    }
}

// MARK: - Hashable for Set operations
extension ASCApp: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ASCApp, rhs: ASCApp) -> Bool {
        return lhs.id == rhs.id
    }
}