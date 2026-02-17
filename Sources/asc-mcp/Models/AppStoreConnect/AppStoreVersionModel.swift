import Foundation

// MARK: - App Store Version Models

/// Модель версии приложения в App Store
public struct ASCAppStoreVersion: Codable, Sendable {
    public let id: String
    public let type: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    
    public struct Attributes: Codable, Sendable {
        public let platform: String?
        public let versionString: String?
        public let appStoreState: String?
        public let copyright: String?
        public let releaseType: String?
        public let earliestReleaseDate: String?
        public let downloadable: Bool?
        public let createdDate: String?
    }
    
    public struct Relationships: Codable, Sendable {
        public let app: Relationship?
        public let appStoreVersionLocalizations: Relationship?
        public let build: Relationship?
        public let appStoreVersionPhasedRelease: Relationship?
        public let appStoreVersionSubmission: Relationship?
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

/// Ответ со списком версий приложения
public struct ASCAppStoreVersionsResponse: Codable, Sendable {
    public let data: [ASCAppStoreVersion]
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

/// Включенные ресурсы (для include параметра)
public enum IncludedResource: Codable, Sendable {
    case appStoreVersionLocalization(ASCAppStoreVersionLocalization)
    case appScreenshotSet(ASCAppScreenshotSet)
    case appScreenshot(ASCAppScreenshot)
    case appPreviewSet(ASCAppPreviewSet)
    case appPreview(ASCAppPreview)
    case unknown
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "appStoreVersionLocalizations":
            let localization = try ASCAppStoreVersionLocalization(from: decoder)
            self = .appStoreVersionLocalization(localization)
        case "appScreenshotSets":
            let screenshotSet = try ASCAppScreenshotSet(from: decoder)
            self = .appScreenshotSet(screenshotSet)
        case "appScreenshots":
            let screenshot = try ASCAppScreenshot(from: decoder)
            self = .appScreenshot(screenshot)
        case "appPreviewSets":
            let previewSet = try ASCAppPreviewSet(from: decoder)
            self = .appPreviewSet(previewSet)
        case "appPreviews":
            let preview = try ASCAppPreview(from: decoder)
            self = .appPreview(preview)
        default:
            self = .unknown
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .appStoreVersionLocalization(let value):
            try value.encode(to: encoder)
        case .appScreenshotSet(let value):
            try value.encode(to: encoder)
        case .appScreenshot(let value):
            try value.encode(to: encoder)
        case .appPreviewSet(let value):
            try value.encode(to: encoder)
        case .appPreview(let value):
            try value.encode(to: encoder)
        case .unknown:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("unknown", forKey: .type)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
}

/// Ответ с одной версией приложения
public struct ASCAppStoreVersionResponse: Codable, Sendable {
    public let data: ASCAppStoreVersion
    public let included: [IncludedResource]?
    public let links: Links?
    
    public struct Links: Codable, Sendable {
        public let `self`: String?
    }
}

// MARK: - Convenience Extensions

extension ASCAppStoreVersion {
    /// Версия приложения
    public var version: String {
        return attributes?.versionString ?? "Unknown"
    }
    
    /// Состояние версии
    public var state: String {
        return attributes?.appStoreState ?? "Unknown"
    }
    
    /// Платформа
    public var platform: String {
        return attributes?.platform ?? "IOS"
    }
    
    /// Доступна ли для скачивания
    public var isDownloadable: Bool {
        return attributes?.downloadable ?? false
    }
}