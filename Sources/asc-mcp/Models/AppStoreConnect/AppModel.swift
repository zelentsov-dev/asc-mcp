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
        public let accessibilityUrl: String?
        public let contentRightsDeclaration: String?
        public let streamlinedPurchasingEnabled: Bool?
    }
    
    public struct Relationships: Codable, Sendable {
        public let values: [String: Relationship]

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RelationshipKey.self)
            var values: [String: Relationship] = [:]
            for key in container.allKeys {
                values[key.stringValue] = try container.decode(Relationship.self, forKey: key)
            }
            self.values = values
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: RelationshipKey.self)
            for (name, relationship) in values {
                try container.encode(relationship, forKey: RelationshipKey(name))
            }
        }

        public var ciProduct: Relationship? { values["ciProduct"] }
        public var betaGroups: Relationship? { values["betaGroups"] }
        public var appStoreVersions: Relationship? { values["appStoreVersions"] }
        public var preReleaseVersions: Relationship? { values["preReleaseVersions"] }
        public var betaAppLocalizations: Relationship? { values["betaAppLocalizations"] }
        public var builds: Relationship? { values["builds"] }
        public var betaLicenseAgreement: Relationship? { values["betaLicenseAgreement"] }
        public var betaAppReviewDetail: Relationship? { values["betaAppReviewDetail"] }
        public var appInfos: Relationship? { values["appInfos"] }
        public var appClips: Relationship? { values["appClips"] }
        public var endUserLicenseAgreement: Relationship? { values["endUserLicenseAgreement"] }
        public var preOrder: Relationship? { values["preOrder"] }
        public var prices: Relationship? { values["prices"] }
        public var availableTerritories: Relationship? { values["availableTerritories"] }
        public var inAppPurchases: Relationship? { values["inAppPurchases"] }
        public var subscriptionGroups: Relationship? { values["subscriptionGroups"] }
        public var gameCenterEnabledVersions: Relationship? { values["gameCenterEnabledVersions"] }
        public var appCustomProductPages: Relationship? { values["appCustomProductPages"] }
        public var inAppPurchasesV2: Relationship? { values["inAppPurchasesV2"] }
        public var promotedPurchases: Relationship? { values["promotedPurchases"] }
        public var appEvents: Relationship? { values["appEvents"] }
        public var reviewSubmissions: Relationship? { values["reviewSubmissions"] }
        public var subscriptionGracePeriod: Relationship? { values["subscriptionGracePeriod"] }
        public var customerReviews: Relationship? { values["customerReviews"] }
        public var perfPowerMetrics: Relationship? { values["perfPowerMetrics"] }
        public var appEncryptionDeclarations: Relationship? { values["appEncryptionDeclarations"] }

        private struct RelationshipKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil

            init(_ stringValue: String) {
                self.stringValue = stringValue
            }

            init?(stringValue: String) {
                self.init(stringValue)
            }

            init?(intValue: Int) {
                return nil
            }
        }
    }
    
    public struct Relationship: Codable, Sendable {
        public let links: Links?
        public let meta: Meta?
        public let data: DataType?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            links = try container.decodeIfPresent(Links.self, forKey: .links)
            meta = try container.decodeIfPresent(Meta.self, forKey: .meta)
            if container.contains(.data) {
                if try container.decodeNil(forKey: .data) {
                    data = .null
                } else {
                    data = try container.decode(DataType.self, forKey: .data)
                }
            } else {
                data = nil
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(links, forKey: .links)
            try container.encodeIfPresent(meta, forKey: .meta)
            try container.encodeIfPresent(data, forKey: .data)
        }

        public enum DataType: Codable, Sendable {
            case single(ResourceIdentifier)
            case multiple([ResourceIdentifier])
            case null

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let single = try? container.decode(ResourceIdentifier.self) {
                    self = .single(single)
                } else if let multiple = try? container.decode([ResourceIdentifier].self) {
                    self = .multiple(multiple)
                } else {
                    throw DecodingError.typeMismatch(
                        DataType.self,
                        .init(codingPath: decoder.codingPath, debugDescription: "Expected relationship object or array")
                    )
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .single(let value):
                    try container.encode(value)
                case .multiple(let values):
                    try container.encode(values)
                case .null:
                    try container.encodeNil()
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case links
            case meta
            case data
        }
        
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
            public let total: Int?
            public let limit: Int
        }
    }
}

/// Single app response
public struct ASCAppResponse: Codable, Sendable {
    public let data: ASCApp
    public let included: [JSONValue]?
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
    /// Apple-reported total, or the current page count only when the page is terminal
    public var totalCount: Int? {
        if let total = meta?.paging.total {
            return total
        }
        return links.next == nil ? data.count : nil
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
