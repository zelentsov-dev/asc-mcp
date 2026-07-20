import Foundation

public struct ASCSubscriptionVersionResponse: Codable, Sendable {
    public let data: ASCSubscriptionVersion
    public let links: ASCPagedDocumentLinks
}

public struct ASCSubscriptionVersionsResponse: Codable, Sendable {
    public let data: [ASCSubscriptionVersion]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

public struct ASCSubscriptionVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?

    public struct Attributes: Codable, Sendable {
        public let version: Int?
        public let state: String?
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: ASCRelationship?
        public let image: ASCRelationship?
        public let images: ASCPricingPagedRelationship?
        public let localizations: ASCPricingPagedRelationship?
    }
}

public struct CreateSubscriptionVersionRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let relationships: Relationships
    }

    public struct Relationships: Codable, Sendable {
        public let subscription: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public init(subscriptionID: String) {
        self.data = Data(
            type: "subscriptionVersions",
            relationships: Relationships(
                subscription: Relationship(
                    data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionID)
                )
            )
        )
    }
}

public struct ASCSubscriptionVersionLocalizationResponse: Codable, Sendable {
    public let data: ASCSubscriptionVersionLocalization
    public let links: ASCPagedDocumentLinks
}

public struct ASCSubscriptionVersionLocalizationsResponse: Codable, Sendable {
    public let data: [ASCSubscriptionVersionLocalization]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

public struct ASCSubscriptionVersionLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let locale: String?
        public let description: String?
    }

    public struct Relationships: Codable, Sendable {
        public let version: ASCRelationship?
    }
}

public struct CreateSubscriptionVersionLocalizationRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
        public let locale: String
        public let description: NullableAttributeValue?
    }

    public struct Relationships: Codable, Sendable {
        public let version: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public init(
        versionID: String,
        locale: String,
        name: String,
        description: NullableAttributeValue?
    ) {
        self.data = Data(
            type: "subscriptionLocalizations",
            attributes: Attributes(name: name, locale: locale, description: description),
            relationships: Relationships(
                version: Relationship(
                    data: ASCResourceIdentifier(type: "subscriptionVersions", id: versionID)
                )
            )
        )
    }
}

public struct UpdateSubscriptionVersionLocalizationRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: NullableAttributeValue?
        public let description: NullableAttributeValue?
    }

    public init(
        localizationID: String,
        name: NullableAttributeValue?,
        description: NullableAttributeValue?
    ) {
        self.data = Data(
            type: "subscriptionLocalizations",
            id: localizationID,
            attributes: Attributes(name: name, description: description)
        )
    }
}

public struct ASCSubscriptionVersionImageResponse: Codable, Sendable {
    public let data: ASCSubscriptionVersionImage
    public let links: ASCPagedDocumentLinks
}

public struct ASCSubscriptionVersionImagesResponse: Codable, Sendable {
    public let data: [ASCSubscriptionVersionImage]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

public struct ASCSubscriptionVersionImage: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?

    public struct Attributes: Codable, Sendable {
        public let fileSize: Int?
        public let fileName: String?
        public let assetToken: String?
        public let imageAsset: ASCImageAsset?
        public let uploadOperations: [ASCUploadOperation]?
        public let assetDeliveryState: ASCAssetDeliveryState?
    }
}

public struct CreateSubscriptionVersionImageRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let fileSize: Int
        public let fileName: String
    }

    public struct Relationships: Codable, Sendable {
        public let version: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public init(versionID: String, fileSize: Int, fileName: String) {
        self.data = Data(
            type: "subscriptionImages",
            attributes: Attributes(fileSize: fileSize, fileName: fileName),
            relationships: Relationships(
                version: Relationship(
                    data: ASCResourceIdentifier(type: "subscriptionVersions", id: versionID)
                )
            )
        )
    }
}

public struct CommitSubscriptionVersionImageRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let uploaded: Bool
    }

    public init(imageID: String) {
        self.data = Data(
            type: "subscriptionImages",
            id: imageID,
            attributes: Attributes(uploaded: true)
        )
    }
}

extension ASCSubscriptionVersionImage: RecoverableUploadResource {
    var recoveryUploadOperations: [ASCUploadOperation]? { attributes?.uploadOperations }

    var recoveryDeliveryStatus: UploadDeliveryStatus {
        switch attributes?.assetDeliveryState?.state {
        case "COMPLETE":
            return .complete("COMPLETE")
        case "FAILED":
            return .failed("FAILED")
        case let state:
            return .pending(state)
        }
    }
}

public struct ASCSubscriptionGroupVersionResponse: Codable, Sendable {
    public let data: ASCSubscriptionGroupVersion
    public let links: ASCPagedDocumentLinks
}

public struct ASCSubscriptionGroupVersionsResponse: Codable, Sendable {
    public let data: [ASCSubscriptionGroupVersion]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

public struct ASCSubscriptionGroupVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?

    public struct Attributes: Codable, Sendable {
        public let version: Int?
        public let state: String?
    }

    public struct Relationships: Codable, Sendable {
        public let subscriptionGroup: ASCRelationship?
        public let localizations: ASCPricingPagedRelationship?
    }
}

public struct CreateSubscriptionGroupVersionRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let relationships: Relationships
    }

    public struct Relationships: Codable, Sendable {
        public let subscriptionGroup: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public init(groupID: String) {
        self.data = Data(
            type: "subscriptionGroupVersions",
            relationships: Relationships(
                subscriptionGroup: Relationship(
                    data: ASCResourceIdentifier(type: "subscriptionGroups", id: groupID)
                )
            )
        )
    }
}

public struct ASCSubscriptionGroupVersionLocalizationResponse: Codable, Sendable {
    public let data: ASCSubscriptionGroupVersionLocalization
    public let links: ASCPagedDocumentLinks
}

public struct ASCSubscriptionGroupVersionLocalizationsResponse: Codable, Sendable {
    public let data: [ASCSubscriptionGroupVersionLocalization]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

public struct ASCSubscriptionGroupVersionLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let customAppName: String?
        public let locale: String?
    }

    public struct Relationships: Codable, Sendable {
        public let version: ASCRelationship?
    }
}

public struct CreateSubscriptionGroupVersionLocalizationRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
        public let customAppName: NullableAttributeValue?
        public let locale: String
    }

    public struct Relationships: Codable, Sendable {
        public let version: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public init(
        versionID: String,
        locale: String,
        name: String,
        customAppName: NullableAttributeValue?
    ) {
        self.data = Data(
            type: "subscriptionGroupLocalizations",
            attributes: Attributes(name: name, customAppName: customAppName, locale: locale),
            relationships: Relationships(
                version: Relationship(
                    data: ASCResourceIdentifier(type: "subscriptionGroupVersions", id: versionID)
                )
            )
        )
    }
}

public struct UpdateSubscriptionGroupVersionLocalizationRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: NullableAttributeValue?
        public let customAppName: NullableAttributeValue?
    }

    public init(
        localizationID: String,
        name: NullableAttributeValue?,
        customAppName: NullableAttributeValue?
    ) {
        self.data = Data(
            type: "subscriptionGroupLocalizations",
            id: localizationID,
            attributes: Attributes(name: name, customAppName: customAppName)
        )
    }
}
