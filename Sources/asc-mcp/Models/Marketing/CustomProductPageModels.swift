import Foundation

// MARK: - Custom Product Page Models

/// Custom product pages list response
public struct ASCCustomProductPagesResponse: Codable, Sendable {
    public let data: [ASCCustomProductPage]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

/// Single custom product page response
public struct ASCCustomProductPageResponse: Codable, Sendable {
    public let data: ASCCustomProductPage
    public let links: ASCCustomProductPageDocumentLinks
}

/// Required top-level JSON:API document links returned by App Store Connect.
public struct ASCCustomProductPageDocumentLinks: Codable, Sendable {
    public let `self`: String
}

/// Optional to-one relationship data returned with a custom-product-page resource.
public struct ASCCustomProductPageToOneRelationship: Codable, Sendable {
    public let data: ASCResourceIdentifier?
}

/// Optional to-many relationship data returned with a custom-product-page resource.
public struct ASCCustomProductPageToManyRelationship: Codable, Sendable {
    public let data: [ASCResourceIdentifier]?
}

/// Custom product page resource
public struct ASCCustomProductPage: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: CustomProductPageAttributes?
    public let relationships: CustomProductPageRelationships?
    public let links: ASCResourceLinks?
}

/// Relationships returned for a custom product page.
public struct CustomProductPageRelationships: Codable, Sendable {
    public let app: ASCCustomProductPageToOneRelationship?
    public let appCustomProductPageVersions: ASCCustomProductPageToManyRelationship?
}

/// Custom product page attributes
public struct CustomProductPageAttributes: Codable, Sendable {
    public let name: String?
    public let url: String?
    public let visible: Bool?
    public let hasName: Bool
    public let hasURL: Bool
    public let hasVisible: Bool

    private enum CodingKeys: String, CodingKey {
        case name, url, visible
    }

    /// Decodes attributes while preserving whether each field was present.
    /// - Returns: Decoded custom product page attributes with field-presence flags.
    /// - Throws: A decoding error when a present field has an invalid type.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasName = container.contains(.name)
        hasURL = container.contains(.url)
        hasVisible = container.contains(.visible)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        visible = try container.decodeIfPresent(Bool.self, forKey: .visible)
    }

    /// Encodes only fields that were present in the decoded attributes.
    /// - Returns: Nothing; writes the preserved custom product page attributes to the encoder.
    /// - Throws: An encoding error when a present field cannot be encoded.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if hasName { try container.encode(name, forKey: .name) }
        if hasURL { try container.encode(url, forKey: .url) }
        if hasVisible { try container.encode(visible, forKey: .visible) }
    }
}

// MARK: - Custom Product Page Version Models

/// Custom product page versions list response
public struct ASCCustomProductPageVersionsResponse: Codable, Sendable {
    public let data: [ASCCustomProductPageVersion]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

/// Single custom product page version response
public struct ASCCustomProductPageVersionResponse: Codable, Sendable {
    public let data: ASCCustomProductPageVersion
    public let links: ASCCustomProductPageDocumentLinks
}

/// Custom product page version resource
public struct ASCCustomProductPageVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: CustomProductPageVersionAttributes?
    public let relationships: CustomProductPageVersionRelationships?
    public let links: ASCResourceLinks?
}

/// Relationships returned for a custom product page version.
public struct CustomProductPageVersionRelationships: Codable, Sendable {
    public let appCustomProductPage: ASCCustomProductPageToOneRelationship?
    public let appCustomProductPageLocalizations: ASCCustomProductPageToManyRelationship?
}

/// Custom product page version attributes
public struct CustomProductPageVersionAttributes: Codable, Sendable {
    public let version: String?
    public let state: String?
    public let deepLink: String?
    public let hasVersion: Bool
    public let hasState: Bool
    public let hasDeepLink: Bool

    private enum CodingKeys: String, CodingKey {
        case version, state, deepLink
    }

    /// Decodes attributes while preserving whether each field was present.
    /// - Returns: Decoded custom product page version attributes with field-presence flags.
    /// - Throws: A decoding error when a present field has an invalid type.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasVersion = container.contains(.version)
        hasState = container.contains(.state)
        hasDeepLink = container.contains(.deepLink)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        deepLink = try container.decodeIfPresent(String.self, forKey: .deepLink)
    }

    /// Encodes only fields that were present in the decoded attributes.
    /// - Returns: Nothing; writes the preserved custom product page version attributes to the encoder.
    /// - Throws: An encoding error when a present field cannot be encoded.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if hasVersion { try container.encode(version, forKey: .version) }
        if hasState { try container.encode(state, forKey: .state) }
        if hasDeepLink { try container.encode(deepLink, forKey: .deepLink) }
    }
}

// MARK: - Custom Product Page Localization Models

/// Custom product page localizations list response
public struct ASCCustomProductPageLocalizationsResponse: Codable, Sendable {
    public let data: [ASCCustomProductPageLocalization]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

/// Single custom product page localization response
public struct ASCCustomProductPageLocalizationResponse: Codable, Sendable {
    public let data: ASCCustomProductPageLocalization
    public let links: ASCCustomProductPageDocumentLinks
}

/// Custom product page localization resource
public struct ASCCustomProductPageLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: CustomProductPageLocalizationAttributes?
    public let relationships: CustomProductPageLocalizationRelationships?
    public let links: ASCResourceLinks?
}

/// Relationships returned for a custom product page localization.
public struct CustomProductPageLocalizationRelationships: Codable, Sendable {
    public let appCustomProductPageVersion: ASCCustomProductPageToOneRelationship?
    public let appScreenshotSets: ASCCustomProductPageToManyRelationship?
    public let appPreviewSets: ASCCustomProductPageToManyRelationship?
    public let searchKeywords: ASCCustomProductPageToManyRelationship?
}

/// Custom product page localization attributes
public struct CustomProductPageLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let promotionalText: String?
    public let hasLocale: Bool
    public let hasPromotionalText: Bool

    private enum CodingKeys: String, CodingKey {
        case locale, promotionalText
    }

    /// Decodes attributes while preserving whether each field was present.
    /// - Returns: Decoded custom product page localization attributes with field-presence flags.
    /// - Throws: A decoding error when a present field has an invalid type.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasLocale = container.contains(.locale)
        hasPromotionalText = container.contains(.promotionalText)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        promotionalText = try container.decodeIfPresent(String.self, forKey: .promotionalText)
    }

    /// Encodes only fields that were present in the decoded attributes.
    /// - Returns: Nothing; writes the preserved custom product page localization attributes to the encoder.
    /// - Throws: An encoding error when a present field cannot be encoded.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if hasLocale { try container.encode(locale, forKey: .locale) }
        if hasPromotionalText { try container.encode(promotionalText, forKey: .promotionalText) }
    }
}

// MARK: - Custom Product Page Request Models

/// Encodes either a concrete custom-product-page value or an explicit JSON null.
public enum ASCCustomProductPageNullable<Value: Codable & Sendable>: Codable, Sendable {
    case value(Value)
    case null

    /// Decodes a concrete value or JSON null.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .null : .value(try container.decode(Value.self))
    }

    /// Encodes the concrete value or JSON null.
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

/// Create custom product page request
public struct CreateCustomProductPageRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "appCustomProductPages"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship
        public let appStoreVersionTemplate: AppRelationship?
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update custom product page request
public struct UpdateCustomProductPageRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public var type: String = "appCustomProductPages"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: ASCCustomProductPageNullable<String>?
        public let visible: ASCCustomProductPageNullable<Bool>?
    }
}

/// Create custom product page version request
public struct CreateCustomProductPageVersionRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "appCustomProductPageVersions"
        public let attributes: Attributes?
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let deepLink: ASCCustomProductPageNullable<String>?
    }

    public struct Relationships: Codable, Sendable {
        public let appCustomProductPage: PageRelationship
    }

    public struct PageRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Create custom product page localization request
public struct CreateCustomProductPageLocalizationRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "appCustomProductPageLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let locale: String
        public let promotionalText: ASCCustomProductPageNullable<String>?
    }

    public struct Relationships: Codable, Sendable {
        public let appCustomProductPageVersion: VersionRelationship
    }

    public struct VersionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update custom product page version request
public struct UpdateCustomProductPageVersionRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public var type: String = "appCustomProductPageVersions"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let deepLink: ASCCustomProductPageNullable<String>?
    }
}

/// Update custom product page localization request
public struct UpdateCustomProductPageLocalizationRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public var type: String = "appCustomProductPageLocalizations"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let promotionalText: ASCCustomProductPageNullable<String>?
    }
}

/// Request body for adding or removing custom-page search keyword relationships.
public struct ASCCustomProductPageSearchKeywordLinkagesRequest: Codable, Sendable {
    public let data: [ASCResourceIdentifier]
}
