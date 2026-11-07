import Foundation

// MARK: - Shared Retention Helpers & Included Resources

/// Integer range for retention offer subscriber eligibility duration in months
public struct RetentionIntegerRange: Codable, Sendable, Equatable {
    public let minimum: Int?
    public let maximum: Int?

    public init(minimum: Int? = nil, maximum: Int? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

extension WinBackOfferAttributes {
    /// Alias for integer range used across commerce offer models
    public typealias IntegerRange = RetentionIntegerRange
}

/// Included resource in retention messaging responses
public struct ASCRetentionMessageIncludedResource: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: [String: JSONValue]?
    public let relationships: [String: JSONValue]?

    public init(
        type: String,
        id: String,
        attributes: [String: JSONValue]? = nil,
        relationships: [String: JSONValue]? = nil
    ) {
        self.type = type
        self.id = id
        self.attributes = attributes
        self.relationships = relationships
    }
}

/// Included resource in win-back and retention offer price responses
public struct ASCWinBackOfferPriceIncludedResource: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: [String: JSONValue]?
    public let relationships: [String: JSONValue]?

    public init(
        type: String,
        id: String,
        attributes: [String: JSONValue]? = nil,
        relationships: [String: JSONValue]? = nil
    ) {
        self.type = type
        self.id = id
        self.attributes = attributes
        self.relationships = relationships
    }
}

/// Helper for decoding `ASCPagedDocumentLinks` even when test fixtures omit `links` or `links.self`
private struct LenientPagedDocumentLinks: Codable, Sendable {
    let first: String?
    let next: String?
    let selfLink: String?

    private enum CodingKeys: String, CodingKey {
        case first
        case next
        case selfLink = "self"
    }

    var asPagedDocumentLinks: ASCPagedDocumentLinks {
        ASCPagedDocumentLinks(first: first, next: next, self: selfLink ?? "")
    }
}

// MARK: - Retention Messages

/// Response wrapper for multiple retention messages
public struct ASCRetentionMessagesResponse: Codable, Sendable {
    public let data: [ASCRetentionMessage]
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?

    public init(
        data: [ASCRetentionMessage],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
        self.meta = meta
    }

    public init(
        data: [ASCRetentionMessage],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
        case meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([ASCRetentionMessage].self, forKey: .data)
        self.included = try container.decodeIfPresent([ASCRetentionMessageIncludedResource].self, forKey: .included)
        let lenientLinks = try container.decodeIfPresent(LenientPagedDocumentLinks.self, forKey: .links)
        self.links = lenientLinks?.asPagedDocumentLinks ?? ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

/// Response wrapper for a single retention message
public struct ASCRetentionMessageResponse: Codable, Sendable {
    public let data: ASCRetentionMessage
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCDocumentLinks?

    public init(
        data: ASCRetentionMessage,
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCDocumentLinks? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
    }
}

/// Response wrapper for an optional retention message (`GET /v1/subscriptions/{id}/retentionMessage` can return `{"data": null}`)
public struct ASCRetentionMessageOptionalResponse: Codable, Sendable {
    public let data: ASCRetentionMessage?
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCDocumentLinks?

    public init(
        data: ASCRetentionMessage?,
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCDocumentLinks? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
    }
}

/// Retention message resource
public struct ASCRetentionMessage: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: RetentionMessageAttributes?
    public let relationships: RetentionMessageRelationships?

    public init(
        type: String = "retentionMessages",
        id: String,
        attributes: RetentionMessageAttributes? = nil,
        relationships: RetentionMessageRelationships? = nil
    ) {
        self.type = type
        self.id = id
        self.attributes = attributes
        self.relationships = relationships
    }
}

/// Retention message attributes
public struct RetentionMessageAttributes: Codable, Sendable {
    public let referenceName: String?

    public init(referenceName: String? = nil) {
        self.referenceName = referenceName
    }
}

/// Retention message relationships
public struct RetentionMessageRelationships: Codable, Sendable {
    public let app: ASCRelationship?
    public let versions: ASCRelationshipMultiple?
    public let retentionMessageVersions: ASCRelationshipMultiple?
    public let subscriptions: ASCRelationshipMultiple?

    public init(
        app: ASCRelationship? = nil,
        versions: ASCRelationshipMultiple? = nil,
        retentionMessageVersions: ASCRelationshipMultiple? = nil,
        subscriptions: ASCRelationshipMultiple? = nil
    ) {
        self.app = app
        self.versions = versions
        self.retentionMessageVersions = retentionMessageVersions
        self.subscriptions = subscriptions
    }
}

// MARK: - Retention Message Versions

/// Response wrapper for multiple retention message versions
public struct ASCRetentionMessageVersionsResponse: Codable, Sendable {
    public let data: [ASCRetentionMessageVersion]
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?

    public init(
        data: [ASCRetentionMessageVersion],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
        self.meta = meta
    }

    public init(
        data: [ASCRetentionMessageVersion],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
        case meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([ASCRetentionMessageVersion].self, forKey: .data)
        self.included = try container.decodeIfPresent([ASCRetentionMessageIncludedResource].self, forKey: .included)
        let lenientLinks = try container.decodeIfPresent(LenientPagedDocumentLinks.self, forKey: .links)
        self.links = lenientLinks?.asPagedDocumentLinks ?? ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

/// Response wrapper for a single retention message version
public struct ASCRetentionMessageVersionResponse: Codable, Sendable {
    public let data: ASCRetentionMessageVersion
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCDocumentLinks?

    public init(
        data: ASCRetentionMessageVersion,
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCDocumentLinks? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
    }
}

/// Retention message version resource
public struct ASCRetentionMessageVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: RetentionMessageVersionAttributes?
    public let relationships: RetentionMessageVersionRelationships?

    public init(
        type: String = "retentionMessageVersions",
        id: String,
        attributes: RetentionMessageVersionAttributes? = nil,
        relationships: RetentionMessageVersionRelationships? = nil
    ) {
        self.type = type
        self.id = id
        self.attributes = attributes
        self.relationships = relationships
    }
}

/// Retention message version attributes
public struct RetentionMessageVersionAttributes: Codable, Sendable {
    public let state: String?
    public let version: Int?

    public init(state: String? = nil, version: Int? = nil) {
        self.state = state
        self.version = version
    }
}

/// Retention message version relationships
public struct RetentionMessageVersionRelationships: Codable, Sendable {
    public let retentionMessage: ASCRelationship?
    public let placement: ASCRelationship?
    public let localizations: ASCRelationshipMultiple?
    public let retentionMessageLocalizations: ASCRelationshipMultiple?

    public init(
        retentionMessage: ASCRelationship? = nil,
        placement: ASCRelationship? = nil,
        localizations: ASCRelationshipMultiple? = nil,
        retentionMessageLocalizations: ASCRelationshipMultiple? = nil
    ) {
        self.retentionMessage = retentionMessage
        self.placement = placement
        self.localizations = localizations
        self.retentionMessageLocalizations = retentionMessageLocalizations
    }
}

// MARK: - Retention Message Localizations

/// Response wrapper for multiple retention message localizations
public struct ASCRetentionMessageLocalizationsResponse: Codable, Sendable {
    public let data: [ASCRetentionMessageLocalization]
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?

    public init(
        data: [ASCRetentionMessageLocalization],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
        self.meta = meta
    }

    public init(
        data: [ASCRetentionMessageLocalization],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
        case meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([ASCRetentionMessageLocalization].self, forKey: .data)
        self.included = try container.decodeIfPresent([ASCRetentionMessageIncludedResource].self, forKey: .included)
        let lenientLinks = try container.decodeIfPresent(LenientPagedDocumentLinks.self, forKey: .links)
        self.links = lenientLinks?.asPagedDocumentLinks ?? ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

/// Response wrapper for a single retention message localization
public struct ASCRetentionMessageLocalizationResponse: Codable, Sendable {
    public let data: ASCRetentionMessageLocalization
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCDocumentLinks?

    public init(
        data: ASCRetentionMessageLocalization,
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCDocumentLinks? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
    }
}

/// Retention message localization resource
public struct ASCRetentionMessageLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: RetentionMessageLocalizationAttributes?
    public let relationships: RetentionMessageLocalizationRelationships?

    public init(
        type: String = "retentionMessageLocalizations",
        id: String,
        attributes: RetentionMessageLocalizationAttributes? = nil,
        relationships: RetentionMessageLocalizationRelationships? = nil
    ) {
        self.type = type
        self.id = id
        self.attributes = attributes
        self.relationships = relationships
    }
}

/// Retention message localization attributes
public struct RetentionMessageLocalizationAttributes: Codable, Sendable {
    public let locale: String?
    public let header: String?
    public let body: String?

    public init(locale: String? = nil, header: String? = nil, body: String? = nil) {
        self.locale = locale
        self.header = header
        self.body = body
    }
}

/// Retention message localization relationships
public struct RetentionMessageLocalizationRelationships: Codable, Sendable {
    public let retentionMessageVersion: ASCRelationship?
    public let version: ASCRelationship?

    public init(retentionMessageVersion: ASCRelationship? = nil, version: ASCRelationship? = nil) {
        self.retentionMessageVersion = retentionMessageVersion
        self.version = version
    }
}

// MARK: - Retention Offers

/// Response wrapper for multiple retention offers
public struct ASCRetentionOffersResponse: Codable, Sendable {
    public let data: [ASCRetentionOffer]
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?

    public init(
        data: [ASCRetentionOffer],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
        self.meta = meta
    }

    public init(
        data: [ASCRetentionOffer],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
        case meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([ASCRetentionOffer].self, forKey: .data)
        self.included = try container.decodeIfPresent([ASCRetentionMessageIncludedResource].self, forKey: .included)
        let lenientLinks = try container.decodeIfPresent(LenientPagedDocumentLinks.self, forKey: .links)
        self.links = lenientLinks?.asPagedDocumentLinks ?? ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

/// Response wrapper for a single retention offer
public struct ASCRetentionOfferResponse: Codable, Sendable {
    public let data: ASCRetentionOffer
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCDocumentLinks?

    public init(
        data: ASCRetentionOffer,
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCDocumentLinks? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
    }
}

/// Retention offer resource
public struct ASCRetentionOffer: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: RetentionOfferAttributes?
    public let relationships: RetentionOfferRelationships?

    public init(
        type: String = "retentionOffers",
        id: String,
        attributes: RetentionOfferAttributes? = nil,
        relationships: RetentionOfferRelationships? = nil
    ) {
        self.type = type
        self.id = id
        self.attributes = attributes
        self.relationships = relationships
    }
}

/// Retention offer attributes
public struct RetentionOfferAttributes: Codable, Sendable {
    public typealias IntegerRange = RetentionIntegerRange

    public let referenceName: String?
    public let offerId: String?
    public let duration: String?
    public let offerMode: String?
    public let periodCount: Int?
    public let customerEligibilityPaidSubscriptionDurationInMonths: Int?
    public let customerEligibilityWaitBetweenOffersInMonths: Int?
    public let targetSubscriptionPlanType: String?

    public init(
        referenceName: String? = nil,
        offerId: String? = nil,
        duration: String? = nil,
        offerMode: String? = nil,
        periodCount: Int? = nil,
        customerEligibilityPaidSubscriptionDurationInMonths: Int? = nil,
        customerEligibilityWaitBetweenOffersInMonths: Int? = nil,
        targetSubscriptionPlanType: String? = nil
    ) {
        self.referenceName = referenceName
        self.offerId = offerId
        self.duration = duration
        self.offerMode = offerMode
        self.periodCount = periodCount
        self.customerEligibilityPaidSubscriptionDurationInMonths = customerEligibilityPaidSubscriptionDurationInMonths
        self.customerEligibilityWaitBetweenOffersInMonths = customerEligibilityWaitBetweenOffersInMonths
        self.targetSubscriptionPlanType = targetSubscriptionPlanType
    }
}

/// Retention offer relationships
public struct RetentionOfferRelationships: Codable, Sendable {
    public let subscription: ASCRelationship?
    public let prices: ASCRelationshipMultiple?

    public init(subscription: ASCRelationship? = nil, prices: ASCRelationshipMultiple? = nil) {
        self.subscription = subscription
        self.prices = prices
    }
}

// MARK: - Retention Offer Prices

/// Response wrapper for retention offer prices
public struct ASCRetentionOfferPricesResponse: Codable, Sendable {
    public let data: [ASCRetentionOfferPrice]
    public let included: [ASCWinBackOfferPriceIncludedResource]?
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?

    public init(
        data: [ASCRetentionOfferPrice],
        included: [ASCWinBackOfferPriceIncludedResource]? = nil,
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
        self.meta = meta
    }

    public init(
        data: [ASCRetentionOfferPrice],
        included: [ASCWinBackOfferPriceIncludedResource]? = nil,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
        case meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([ASCRetentionOfferPrice].self, forKey: .data)
        self.included = try container.decodeIfPresent([ASCWinBackOfferPriceIncludedResource].self, forKey: .included)
        let lenientLinks = try container.decodeIfPresent(LenientPagedDocumentLinks.self, forKey: .links)
        self.links = lenientLinks?.asPagedDocumentLinks ?? ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

/// Retention offer price resource
public struct ASCRetentionOfferPrice: Codable, Sendable {
    public let type: String
    public let id: String
    public let relationships: RetentionOfferPriceRelationships?

    public init(
        type: String = "retentionOfferPrices",
        id: String,
        relationships: RetentionOfferPriceRelationships? = nil
    ) {
        self.type = type
        self.id = id
        self.relationships = relationships
    }
}

/// Retention offer price relationships
public struct RetentionOfferPriceRelationships: Codable, Sendable {
    public let territory: ASCRelationship?
    public let subscriptionPricePoint: ASCRelationship?

    public init(territory: ASCRelationship? = nil, subscriptionPricePoint: ASCRelationship? = nil) {
        self.territory = territory
        self.subscriptionPricePoint = subscriptionPricePoint
    }
}

// MARK: - Retention Message Subscriptions Response

/// Subscription item returned by `GET /v1/retentionMessages/{id}/subscriptions`
public struct ASCRetentionMessageSubscription: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SubscriptionAttributes?
    public let relationships: [String: JSONValue]?

    public init(
        type: String = "subscriptions",
        id: String,
        attributes: SubscriptionAttributes? = nil,
        relationships: [String: JSONValue]? = nil
    ) {
        self.type = type
        self.id = id
        self.attributes = attributes
        self.relationships = relationships
    }
}

/// Response wrapper for subscriptions associated with a retention message
public struct ASCRetentionMessageSubscriptionsResponse: Codable, Sendable {
    public let data: [ASCRetentionMessageSubscription]
    public let included: [ASCRetentionMessageIncludedResource]?
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?

    public init(
        data: [ASCRetentionMessageSubscription],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = links
        self.meta = meta
    }

    public init(
        data: [ASCRetentionMessageSubscription],
        included: [ASCRetentionMessageIncludedResource]? = nil,
        meta: ASCPagingInformation? = nil
    ) {
        self.data = data
        self.included = included
        self.links = ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
        case meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode([ASCRetentionMessageSubscription].self, forKey: .data)
        self.included = try container.decodeIfPresent([ASCRetentionMessageIncludedResource].self, forKey: .included)
        let lenientLinks = try container.decodeIfPresent(LenientPagedDocumentLinks.self, forKey: .links)
        self.links = lenientLinks?.asPagedDocumentLinks ?? ASCPagedDocumentLinks(first: nil, next: nil, self: "")
        self.meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

// MARK: - Request Models

/// Request to create a retention message
public struct RetentionMessageCreateRequest: Codable, Sendable {
    public let data: CreateData

    public init(data: CreateData) {
        self.data = data
    }

    public init(appId: String, referenceName: String) {
        self.data = CreateData(
            attributes: Attributes(referenceName: referenceName),
            relationships: Relationships(
                app: AppRelationship(
                    data: ASCResourceIdentifier(type: "apps", id: appId)
                )
            )
        )
    }

    public struct CreateData: Codable, Sendable {
        public let type: String
        public let attributes: Attributes
        public let relationships: Relationships

        public init(
            type: String = "retentionMessages",
            attributes: Attributes,
            relationships: Relationships
        ) {
            self.type = type
            self.attributes = attributes
            self.relationships = relationships
        }
    }

    public struct Attributes: Codable, Sendable {
        public let referenceName: String

        public init(referenceName: String) {
            self.referenceName = referenceName
        }
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship

        public init(app: AppRelationship) {
            self.app = app
        }
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier

        public init(data: ASCResourceIdentifier) {
            self.data = data
        }
    }
}

/// Request to create a retention message version
public struct RetentionMessageVersionCreateRequest: Codable, Sendable {
    public let data: CreateData

    public init(data: CreateData) {
        self.data = data
    }

    public init(retentionMessageId: String) {
        self.data = CreateData(
            relationships: Relationships(
                retentionMessage: RetentionMessageRelationship(
                    data: ASCResourceIdentifier(type: "retentionMessages", id: retentionMessageId)
                )
            )
        )
    }

    public struct CreateData: Codable, Sendable {
        public let type: String
        public let relationships: Relationships

        public init(
            type: String = "retentionMessageVersions",
            relationships: Relationships
        ) {
            self.type = type
            self.relationships = relationships
        }
    }

    public struct Relationships: Codable, Sendable {
        public let retentionMessage: RetentionMessageRelationship

        public init(retentionMessage: RetentionMessageRelationship) {
            self.retentionMessage = retentionMessage
        }
    }

    public struct RetentionMessageRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier

        public init(data: ASCResourceIdentifier) {
            self.data = data
        }
    }
}

/// Request to create a retention message localization
public struct RetentionMessageLocalizationCreateRequest: Codable, Sendable {
    public let data: CreateData

    public init(data: CreateData) {
        self.data = data
    }

    public init(versionId: String, locale: String, header: String, body: String) {
        self.data = CreateData(
            attributes: Attributes(locale: locale, header: header, body: body),
            relationships: Relationships(
                retentionMessageVersion: VersionRelationship(
                    data: ASCResourceIdentifier(type: "retentionMessageVersions", id: versionId)
                )
            )
        )
    }

    public struct CreateData: Codable, Sendable {
        public let type: String
        public let attributes: Attributes
        public let relationships: Relationships

        public init(
            type: String = "retentionMessageLocalizations",
            attributes: Attributes,
            relationships: Relationships
        ) {
            self.type = type
            self.attributes = attributes
            self.relationships = relationships
        }
    }

    public struct Attributes: Codable, Sendable {
        public let locale: String
        public let header: String
        public let body: String

        public init(locale: String, header: String, body: String) {
            self.locale = locale
            self.header = header
            self.body = body
        }
    }

    public struct Relationships: Codable, Sendable {
        public let retentionMessageVersion: VersionRelationship

        public init(retentionMessageVersion: VersionRelationship) {
            self.retentionMessageVersion = retentionMessageVersion
        }
    }

    public struct VersionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier

        public init(data: ASCResourceIdentifier) {
            self.data = data
        }
    }
}

/// Request to update a retention message localization
public struct RetentionMessageLocalizationUpdateRequest: Codable, Sendable {
    public let data: UpdateData

    public init(data: UpdateData) {
        self.data = data
    }

    public init(
        localizationId: String,
        header: ASCNullable<String>? = nil,
        body: ASCNullable<String>? = nil
    ) {
        self.data = UpdateData(
            id: localizationId,
            attributes: Attributes(header: header, body: body)
        )
    }

    public struct UpdateData: Codable, Sendable {
        public let type: String
        public let id: String
        public let attributes: Attributes

        public init(
            type: String = "retentionMessageLocalizations",
            id: String,
            attributes: Attributes
        ) {
            self.type = type
            self.id = id
            self.attributes = attributes
        }
    }

    public struct Attributes: Codable, Sendable {
        public let header: ASCNullable<String>?
        public let body: ASCNullable<String>?

        public init(
            header: ASCNullable<String>? = nil,
            body: ASCNullable<String>? = nil
        ) {
            self.header = header
            self.body = body
        }
    }
}

/// Request to create a retention offer with inline prices
public struct RetentionOfferCreateRequest: Codable, Sendable {
    public let data: CreateData
    public let included: [RetentionOfferPriceInlineCreate]?

    public init(data: CreateData, included: [RetentionOfferPriceInlineCreate]? = nil) {
        self.data = data
        self.included = included
    }

    public struct CreateData: Codable, Sendable {
        public let type: String
        public let attributes: Attributes
        public let relationships: Relationships

        public init(
            type: String = "retentionOffers",
            attributes: Attributes,
            relationships: Relationships
        ) {
            self.type = type
            self.attributes = attributes
            self.relationships = relationships
        }
    }

    public struct Attributes: Codable, Sendable {
        public let referenceName: String
        public let offerId: String
        public let duration: String
        public let offerMode: String
        public let periodCount: Int
        public let customerEligibilityPaidSubscriptionDurationInMonths: Int
        public let customerEligibilityWaitBetweenOffersInMonths: Int?
        public let targetSubscriptionPlanType: String?

        public init(
            referenceName: String,
            offerId: String,
            duration: String,
            offerMode: String,
            periodCount: Int,
            customerEligibilityPaidSubscriptionDurationInMonths: Int,
            customerEligibilityWaitBetweenOffersInMonths: Int? = nil,
            targetSubscriptionPlanType: String? = nil
        ) {
            self.referenceName = referenceName
            self.offerId = offerId
            self.duration = duration
            self.offerMode = offerMode
            self.periodCount = periodCount
            self.customerEligibilityPaidSubscriptionDurationInMonths = customerEligibilityPaidSubscriptionDurationInMonths
            self.customerEligibilityWaitBetweenOffersInMonths = customerEligibilityWaitBetweenOffersInMonths
            self.targetSubscriptionPlanType = targetSubscriptionPlanType
        }
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: SubscriptionRelationship
        public let prices: PricesRelationship

        public init(subscription: SubscriptionRelationship, prices: PricesRelationship) {
            self.subscription = subscription
            self.prices = prices
        }
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier

        public init(data: ASCResourceIdentifier) {
            self.data = data
        }
    }

    public struct PricesRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]

        public init(data: [ASCResourceIdentifier]) {
            self.data = data
        }
    }
}

/// Inline price creation resource for `RetentionOfferCreateRequest.included`
/// Note: Apple's OpenAPI 4.6 schema omits `subscriptionPricePoint` from `RetentionOfferPriceInlineCreate`,
/// but the runtime API requires `relationships.subscriptionPricePoint.data` on each inline price item.
public struct RetentionOfferPriceInlineCreate: Codable, Sendable {
    public let type: String
    public let id: String?
    public let relationships: Relationships

    public init(
        type: String = "retentionOfferPrices",
        id: String?,
        relationships: Relationships
    ) {
        self.type = type
        self.id = id
        self.relationships = relationships
    }

    public struct Relationships: Codable, Sendable {
        public let subscriptionPricePoint: PricePointRelationship
        public let territory: TerritoryRelationship?

        public init(
            subscriptionPricePoint: PricePointRelationship,
            territory: TerritoryRelationship? = nil
        ) {
            self.subscriptionPricePoint = subscriptionPricePoint
            self.territory = territory
        }
    }

    public struct PricePointRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier

        public init(data: ASCResourceIdentifier) {
            self.data = data
        }
    }

    public struct TerritoryRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier

        public init(data: ASCResourceIdentifier) {
            self.data = data
        }
    }
}

/// Request to update a retention offer with tri-state patch fields
public struct RetentionOfferUpdateRequest: Codable, Sendable {
    public let data: UpdateData

    public init(data: UpdateData) {
        self.data = data
    }

    public init(
        offerId: String,
        customerEligibilityPaidSubscriptionDurationInMonths: ASCNullable<Int>? = nil,
        customerEligibilityWaitBetweenOffersInMonths: ASCNullable<Int>? = nil
    ) {
        self.data = UpdateData(
            id: offerId,
            attributes: Attributes(
                customerEligibilityPaidSubscriptionDurationInMonths: customerEligibilityPaidSubscriptionDurationInMonths,
                customerEligibilityWaitBetweenOffersInMonths: customerEligibilityWaitBetweenOffersInMonths
            )
        )
    }

    public struct UpdateData: Codable, Sendable {
        public let type: String
        public let id: String
        public let attributes: Attributes

        public init(
            type: String = "retentionOffers",
            id: String,
            attributes: Attributes
        ) {
            self.type = type
            self.id = id
            self.attributes = attributes
        }
    }

    public struct Attributes: Codable, Sendable {
        public let customerEligibilityPaidSubscriptionDurationInMonths: ASCNullable<Int>?
        public let customerEligibilityWaitBetweenOffersInMonths: ASCNullable<Int>?

        public init(
            customerEligibilityPaidSubscriptionDurationInMonths: ASCNullable<Int>? = nil,
            customerEligibilityWaitBetweenOffersInMonths: ASCNullable<Int>? = nil
        ) {
            self.customerEligibilityPaidSubscriptionDurationInMonths = customerEligibilityPaidSubscriptionDurationInMonths
            self.customerEligibilityWaitBetweenOffersInMonths = customerEligibilityWaitBetweenOffersInMonths
        }
    }
}

public typealias RetentionOfferCreateAttributes = RetentionOfferCreateRequest.Attributes
public typealias RetentionOfferUpdateAttributes = RetentionOfferUpdateRequest.Attributes

/// Request to set or clear a subscription's retention message (`PATCH /v1/subscriptions/{id}/relationships/retentionMessage`)
/// Encodes `{"data": {"type": "retentionMessages", "id": id}}` when setting, and `{"data": null}` when clearing.
public struct SubscriptionRetentionMessageLinkageRequest: Codable, Sendable {
    public let data: ASCResourceIdentifier?

    public init(retentionMessageId: String?) {
        if let retentionMessageId {
            self.data = ASCResourceIdentifier(type: "retentionMessages", id: retentionMessageId)
        } else {
            self.data = nil
        }
    }

    public init(data: ASCResourceIdentifier?) {
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let data {
            try container.encode(data, forKey: .data)
        } else {
            try container.encodeNil(forKey: .data)
        }
    }
}

/// Request to add or remove retention message offers for a subscription
/// (`POST` or `DELETE /v1/subscriptions/{id}/relationships/retentionMessageOffers`)
public struct SubscriptionRetentionMessageOffersLinkagesRequest: Codable, Sendable {
    public let data: [ASCResourceIdentifier]

    public init(offerIds: [String]) {
        self.data = offerIds.map { ASCResourceIdentifier(type: "retentionOffers", id: $0) }
    }

    public init(data: [ASCResourceIdentifier]) {
        self.data = data
    }
}
