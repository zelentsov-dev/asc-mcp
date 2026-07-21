import Foundation

// MARK: - Promoted Purchase Models

/// Promoted purchases list response
public struct ASCPromotedPurchasesResponse: Codable, Sendable {
    public let data: [ASCPromotedPurchase]
    public let included: [PromotedPurchaseIncludedResource]?
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

public struct ASCPromotedPurchaseLinkagesResponse: Codable, Sendable {
    public let data: [ASCResourceIdentifier]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

/// Single promoted purchase response
public struct ASCPromotedPurchaseResponse: Codable, Sendable {
    public let data: ASCPromotedPurchase
    public let included: [PromotedPurchaseIncludedResource]?
    public let links: ASCPromotedPurchaseDocumentLinks
}

public struct ASCPromotedPurchaseDocumentLinks: Codable, Sendable {
    public let `self`: String
}

/// Included resource in promoted purchase response (IAP or subscription)
public struct PromotedPurchaseIncludedResource: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PromotedPurchaseIncludedAttributes?
}

/// Attributes for included IAP/subscription resources
public struct PromotedPurchaseIncludedAttributes: Codable, Sendable {
    public let name: String?
    public let productId: String?
    public let inAppPurchaseType: String?
    public let state: String?
}

/// Promoted purchase resource
public struct ASCPromotedPurchase: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PromotedPurchaseAttributes?
    public let relationships: PromotedPurchaseRelationships?
}

public struct PromotedPurchaseRelationships: Codable, Sendable {
    public let inAppPurchaseV2: PromotedPurchaseProductRelationship?
    public let subscription: PromotedPurchaseProductRelationship?
}

public struct PromotedPurchaseProductRelationship: Codable, Sendable {
    public let data: ASCResourceIdentifier?
}

/// Promoted purchase attributes
public struct PromotedPurchaseAttributes: Codable, Sendable {
    public let visibleForAllUsers: Bool?
    public let enabled: Bool?
    public let state: String?

    private enum CodingKeys: String, CodingKey {
        case visibleForAllUsers
        case enabled
        case state
    }

    /// Decodes response attributes while rejecting present JSON null Boolean values.
    /// - Throws: `DecodingError` when a present Boolean attribute is null or has the wrong type.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visibleForAllUsers = try Self.decodeOptionalBoolean(
            .visibleForAllUsers,
            from: container
        )
        enabled = try Self.decodeOptionalBoolean(.enabled, from: container)
        state = try container.decodeIfPresent(String.self, forKey: .state)
    }

    private static func decodeOptionalBoolean(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Bool? {
        guard container.contains(key) else { return nil }
        guard try !container.decodeNil(forKey: key) else {
            throw DecodingError.valueNotFound(
                Bool.self,
                DecodingError.Context(
                    codingPath: container.codingPath + [key],
                    debugDescription: "Promoted purchase response Boolean must not be null"
                )
            )
        }
        return try container.decode(Bool.self, forKey: key)
    }
}

/// Optional Boolean that preserves an explicit JSON null in write requests.
public enum PromotedPurchaseNullableBool: Codable, Sendable {
    case value(Bool)
    case null

    /// Decodes either a Boolean value or JSON null.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .null : .value(try container.decode(Bool.self))
    }

    /// Encodes the selected Boolean value or JSON null.
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

// MARK: - Request Models

/// Create promoted purchase request
public struct CreatePromotedPurchaseRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "promotedPurchases"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let visibleForAllUsers: Bool
        public let enabled: PromotedPurchaseNullableBool?
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship
        public let inAppPurchaseV2: IAPRelationship?
        public let subscription: SubscriptionRelationship?
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct IAPRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public struct SubscriptionRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update promoted purchase request
public struct UpdatePromotedPurchaseRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public var type: String = "promotedPurchases"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let visibleForAllUsers: PromotedPurchaseNullableBool?
        public let enabled: PromotedPurchaseNullableBool?
    }
}

public struct ReorderPromotedPurchasesRequest: Codable, Sendable {
    public let data: [ASCResourceIdentifier]
}
