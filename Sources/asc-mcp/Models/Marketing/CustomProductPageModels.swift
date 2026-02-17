import Foundation

// MARK: - Custom Product Page Models

/// Custom product pages list response
public struct ASCCustomProductPagesResponse: Codable, Sendable {
    public let data: [ASCCustomProductPage]
    public let links: ASCPagedDocumentLinks?
}

/// Single custom product page response
public struct ASCCustomProductPageResponse: Codable, Sendable {
    public let data: ASCCustomProductPage
}

/// Custom product page resource
public struct ASCCustomProductPage: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: CustomProductPageAttributes?
}

/// Custom product page attributes
public struct CustomProductPageAttributes: Codable, Sendable {
    public let name: String?
    public let url: String?
    public let visible: Bool?
    public let state: String?
}

// MARK: - Custom Product Page Version Models

/// Custom product page versions list response
public struct ASCCustomProductPageVersionsResponse: Codable, Sendable {
    public let data: [ASCCustomProductPageVersion]
    public let links: ASCPagedDocumentLinks?
}

/// Single custom product page version response
public struct ASCCustomProductPageVersionResponse: Codable, Sendable {
    public let data: ASCCustomProductPageVersion
}

/// Custom product page version resource
public struct ASCCustomProductPageVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: CustomProductPageVersionAttributes?
}

/// Custom product page version attributes
public struct CustomProductPageVersionAttributes: Codable, Sendable {
    public let version: String?
    public let state: String?
    public let deepLink: String?
}

// MARK: - Custom Product Page Localization Models

/// Custom product page localizations list response
public struct ASCCustomProductPageLocalizationsResponse: Codable, Sendable {
    public let data: [ASCCustomProductPageLocalization]
    public let links: ASCPagedDocumentLinks?
}

/// Single custom product page localization response
public struct ASCCustomProductPageLocalizationResponse: Codable, Sendable {
    public let data: ASCCustomProductPageLocalization
}

/// Custom product page localization resource
public struct ASCCustomProductPageLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: CustomProductPageLocalizationAttributes?
}

/// Custom product page localization attributes
public struct CustomProductPageLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let promotionalText: String?
}

// MARK: - Custom Product Page Request Models

/// Create custom product page request
public struct CreateCustomProductPageRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "appCustomProductPages"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update custom product page request
public struct UpdateCustomProductPageRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "appCustomProductPages"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let visible: Bool?
    }
}

/// Create custom product page version request
public struct CreateCustomProductPageVersionRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "appCustomProductPageVersions"
        public let relationships: Relationships
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
        public let type: String = "appCustomProductPageLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let locale: String
        public let promotionalText: String?
    }

    public struct Relationships: Codable, Sendable {
        public let appCustomProductPageVersion: VersionRelationship
    }

    public struct VersionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update custom product page localization request
public struct UpdateCustomProductPageLocalizationRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "appCustomProductPageLocalizations"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let promotionalText: String?
    }
}
