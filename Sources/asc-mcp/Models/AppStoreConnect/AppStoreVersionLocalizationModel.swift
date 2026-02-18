import Foundation

// MARK: - App Store Version Localization Models

/// App store version localization resource
public struct ASCAppStoreVersionLocalization: Codable, Sendable {
    public let id: String
    public let type: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    
    public struct Attributes: Codable, Sendable {
        public let locale: String?
        public let description: String?
        public let keywords: String?
        public let marketingUrl: String?
        public let promotionalText: String?
        public let supportUrl: String?
        public let whatsNew: String?
    }
    
    public struct Relationships: Codable, Sendable {
        public let appStoreVersion: Relationship?
        public let appScreenshotSets: Relationship?
        public let appPreviewSets: Relationship?
    }
    
    public struct Relationship: Codable, Sendable {
        public let links: Links?
        public let data: DataType?
        
        public enum DataType: Codable, Sendable {
            case single(ResourceIdentifier)
            case multiple([ResourceIdentifier])
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let single = try? container.decode(ResourceIdentifier.self) {
                    self = .single(single)
                } else if let multiple = try? container.decode([ResourceIdentifier].self) {
                    self = .multiple(multiple)
                } else {
                    throw DecodingError.typeMismatch(DataType.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected single or array"))
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .single(let value):
                    try container.encode(value)
                case .multiple(let values):
                    try container.encode(values)
                }
            }
        }
        
        public struct Links: Codable, Sendable {
            public let related: String?
            public let `self`: String?
        }
    }
    
    public struct ResourceIdentifier: Codable, Sendable {
        public let id: String
        public let type: String
    }
}

/// Localizations list response
public struct ASCAppStoreVersionLocalizationsResponse: Codable, Sendable {
    public let data: [ASCAppStoreVersionLocalization]
    public let included: [IncludedResource]?
    public let links: Links?
    public let meta: Meta?
    
    public struct Links: Codable, Sendable {
        public let first: String?
        public let next: String?
        public let `self`: String
    }
    
    public struct Meta: Codable, Sendable {
        public let paging: Paging?
        
        public struct Paging: Codable, Sendable {
            public let total: Int
            public let limit: Int
        }
    }
}

// MARK: - Screenshot Models

/// Screenshot set resource
public struct ASCAppScreenshotSet: Codable, Sendable {
    public let id: String
    public let type: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    
    public struct Attributes: Codable, Sendable {
        public let screenshotDisplayType: String?
    }
    
    public struct Relationships: Codable, Sendable {
        public let appStoreVersionLocalization: Relationship?
        public let appScreenshots: Relationship?
    }
    
    public struct Relationship: Codable, Sendable {
        public let links: Links?
        public let data: DataType?
        
        public enum DataType: Codable, Sendable {
            case single(ResourceIdentifier)
            case multiple([ResourceIdentifier])
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let single = try? container.decode(ResourceIdentifier.self) {
                    self = .single(single)
                } else if let multiple = try? container.decode([ResourceIdentifier].self) {
                    self = .multiple(multiple)
                } else {
                    throw DecodingError.typeMismatch(DataType.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected single or array"))
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .single(let value):
                    try container.encode(value)
                case .multiple(let values):
                    try container.encode(values)
                }
            }
        }
        
        public struct Links: Codable, Sendable {
            public let related: String?
            public let `self`: String?
        }
    }
    
    public struct ResourceIdentifier: Codable, Sendable {
        public let id: String
        public let type: String
    }
}

/// Screenshot resource
public struct ASCAppScreenshot: Codable, Sendable {
    public let id: String
    public let type: String
    public let attributes: Attributes?
    
    public struct Attributes: Codable, Sendable {
        public let fileSize: Int?
        public let fileName: String?
        public let sourceFileChecksum: String?
        public let imageAsset: ImageAsset?
        public let assetToken: String?
        public let assetType: String?
        public let uploadOperations: [UploadOperation]?
        public let assetDeliveryState: AssetDeliveryState?
    }
    
    public struct ImageAsset: Codable, Sendable {
        public let templateUrl: String?
        public let width: Int?
        public let height: Int?
    }
    
    public struct UploadOperation: Codable, Sendable {
        public let method: String?
        public let url: String?
        public let length: Int?
        public let offset: Int?
        public let requestHeaders: [Header]?
        
        public struct Header: Codable, Sendable {
            public let name: String?
            public let value: String?
        }
    }
    
    public struct AssetDeliveryState: Codable, Sendable {
        public let errors: [Error]?
        public let warnings: [Warning]?
        public let state: String?
        
        public struct Error: Codable, Sendable {
            public let code: String?
            public let description: String?
        }
        
        public struct Warning: Codable, Sendable {
            public let code: String?
            public let description: String?
        }
    }
}

/// Screenshot sets list response
public struct ASCAppScreenshotSetsResponse: Codable, Sendable {
    public let data: [ASCAppScreenshotSet]
    public let included: [ASCAppScreenshot]?
    public let links: Links?
    
    public struct Links: Codable, Sendable {
        public let first: String?
        public let next: String?
        public let `self`: String
    }
}

// MARK: - Update Models

/// Version localization update request
public struct ASCAppStoreVersionLocalizationUpdateRequest: Codable, Sendable {
    public let data: Data
    
    public struct Data: Codable, Sendable {
        public let type: String = "appStoreVersionLocalizations"
        public let id: String
        public let attributes: Attributes
        
        public struct Attributes: Codable, Sendable {
            public let description: String?
            public let whatsNew: String?
            public let keywords: String?
            public let promotionalText: String?
            public let supportUrl: String?
            public let marketingUrl: String?
        }
    }
    
    public init(id: String, attributes: Data.Attributes) {
        self.data = Data(id: id, attributes: attributes)
    }
}

/// Localization update response
public struct ASCAppStoreVersionLocalizationUpdateResponse: Codable, Sendable {
    public let data: ASCAppStoreVersionLocalization
}

/// Screenshots list response
public struct ASCAppScreenshotsResponse: Codable, Sendable {
    public let data: [ASCAppScreenshot]
    public let links: Links?
    
    public struct Links: Codable, Sendable {
        public let first: String?
        public let next: String?
        public let `self`: String
    }
}

// MARK: - App Preview Models (Video)

/// App preview set resource
public struct ASCAppPreviewSet: Codable, Sendable {
    public let id: String
    public let type: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    
    public struct Attributes: Codable, Sendable {
        public let previewType: String?
    }
    
    public struct Relationships: Codable, Sendable {
        public let appStoreVersionLocalization: Relationship?
        public let appPreviews: Relationship?
    }
    
    public struct Relationship: Codable, Sendable {
        public let links: Links?
        public let data: DataType?
        
        public enum DataType: Codable, Sendable {
            case single(ResourceIdentifier)
            case multiple([ResourceIdentifier])
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let single = try? container.decode(ResourceIdentifier.self) {
                    self = .single(single)
                } else if let multiple = try? container.decode([ResourceIdentifier].self) {
                    self = .multiple(multiple)
                } else {
                    throw DecodingError.typeMismatch(DataType.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected single or array"))
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .single(let value):
                    try container.encode(value)
                case .multiple(let values):
                    try container.encode(values)
                }
            }
        }
        
        public struct Links: Codable, Sendable {
            public let related: String?
            public let `self`: String?
        }
    }
    
    public struct ResourceIdentifier: Codable, Sendable {
        public let id: String
        public let type: String
    }
}

/// App preview resource
public struct ASCAppPreview: Codable, Sendable {
    public let id: String
    public let type: String
    public let attributes: Attributes?
    
    public struct Attributes: Codable, Sendable {
        public let fileSize: Int?
        public let fileName: String?
        public let sourceFileChecksum: String?
        public let videoUrl: String?
        public let mimeType: String?
        public let previewFrameTimeCode: String?
        public let previewImage: PreviewImage?
        public let assetDeliveryState: AssetDeliveryState?
    }
    
    public struct PreviewImage: Codable, Sendable {
        public let templateUrl: String?
        public let width: Int?
        public let height: Int?
    }
    
    public struct AssetDeliveryState: Codable, Sendable {
        public let errors: [Error]?
        public let warnings: [Warning]?
        public let state: String?
        
        public struct Error: Codable, Sendable {
            public let code: String?
            public let description: String?
        }
        
        public struct Warning: Codable, Sendable {
            public let code: String?
            public let description: String?
        }
    }
}

/// App preview sets list response
public struct ASCAppPreviewSetsResponse: Codable, Sendable {
    public let data: [ASCAppPreviewSet]
    public let included: [ASCAppPreview]?
    public let links: Links?
    
    public struct Links: Codable, Sendable {
        public let first: String?
        public let next: String?
        public let `self`: String
    }
}

// MARK: - Convenience Extensions

extension ASCAppStoreVersionLocalization {
    /// Locale
    public var locale: String {
        return attributes?.locale ?? "Unknown"
    }
    
    /// Whether What's New is set
    public var hasWhatsNew: Bool {
        return !(attributes?.whatsNew?.isEmpty ?? true)
    }
    
    /// Whether description is set
    public var hasDescription: Bool {
        return !(attributes?.description?.isEmpty ?? true)
    }
}

extension ASCAppScreenshot {
    /// Image URL
    public var imageUrl: String? {
        guard let templateUrl = attributes?.imageAsset?.templateUrl,
              let width = attributes?.imageAsset?.width,
              let height = attributes?.imageAsset?.height else {
            return nil
        }
        
        // Replace placeholders with actual values
        return templateUrl
            .replacingOccurrences(of: "{w}", with: String(width))
            .replacingOccurrences(of: "{h}", with: String(height))
            .replacingOccurrences(of: "{f}", with: "png")
    }
    
    /// Image dimensions
    public var dimensions: (width: Int, height: Int)? {
        guard let width = attributes?.imageAsset?.width,
              let height = attributes?.imageAsset?.height else {
            return nil
        }
        return (width, height)
    }
}

// MARK: - Create/Response Models

/// Response for a single localization
public struct ASCAppStoreVersionLocalizationResponse: Codable, Sendable {
    public let data: ASCAppStoreVersionLocalization
}

/// Request to create a new localization for an app store version
public struct CreateAppStoreVersionLocalizationRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String = "appStoreVersionLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships

        public struct Attributes: Codable, Sendable {
            public let locale: String
            public let description: String?
            public let whatsNew: String?
            public let keywords: String?
            public let promotionalText: String?
            public let supportUrl: String?
            public let marketingUrl: String?
        }

        public struct Relationships: Codable, Sendable {
            public let appStoreVersion: AppStoreVersionRelationship

            public struct AppStoreVersionRelationship: Codable, Sendable {
                public let data: ResourceRef

                public struct ResourceRef: Codable, Sendable {
                    public let type: String = "appStoreVersions"
                    public let id: String
                }
            }
        }
    }

    public init(versionId: String, attributes: Data.Attributes) {
        self.data = Data(
            attributes: attributes,
            relationships: Data.Relationships(
                appStoreVersion: Data.Relationships.AppStoreVersionRelationship(
                    data: Data.Relationships.AppStoreVersionRelationship.ResourceRef(id: versionId)
                )
            )
        )
    }
}

extension ASCAppPreview {
    /// Preview image URL
    public var previewImageUrl: String? {
        guard let templateUrl = attributes?.previewImage?.templateUrl else {
            return nil
        }
        
        // Replace placeholders with actual values for maximum size
        return templateUrl
            .replacingOccurrences(of: "{w}", with: "1290")
            .replacingOccurrences(of: "{h}", with: "2796")
            .replacingOccurrences(of: "{f}", with: "png")
    }
    
    /// Video URL
    public var videoUrl: String? {
        return attributes?.videoUrl
    }
}