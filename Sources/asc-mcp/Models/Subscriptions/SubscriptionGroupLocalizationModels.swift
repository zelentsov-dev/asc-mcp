import Foundation

// MARK: - Subscription Group Localization Models

/// Subscription group localizations list response
public struct ASCSubscriptionGroupLocalizationsResponse: Codable, Sendable {
    public let data: [ASCSubscriptionGroupLocalization]
    public let links: ASCPagedDocumentLinks?
}

/// Subscription group localization single response
public struct ASCSubscriptionGroupLocalizationResponse: Codable, Sendable {
    public let data: ASCSubscriptionGroupLocalization
}

/// Subscription group localization resource
public struct ASCSubscriptionGroupLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubscriptionGroupLocalizationAttributes
}

/// Subscription group localization attributes
public struct SubscriptionGroupLocalizationAttributes: Codable, Sendable {
    public let name: String?
    public let customAppName: String?
    public let locale: String?
    public let state: String?
}

// MARK: - Subscription Group Localization Request Models

/// Create subscription group localization request
public struct CreateSubscriptionGroupLocalizationRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "subscriptionGroupLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
        public let locale: String
        public let customAppName: String?
    }

    public struct Relationships: Codable, Sendable {
        public let subscriptionGroup: SubscriptionGroupRelationship
    }

    public struct SubscriptionGroupRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update subscription group localization request
public struct UpdateSubscriptionGroupLocalizationRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "subscriptionGroupLocalizations"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let customAppName: String?
    }
}
