import Foundation

public struct ASCIAPVersionResponse: Codable, Sendable {
    public let data: ASCIAPVersion
    public let links: ASCPagedDocumentLinks
}

public struct ASCIAPVersionsResponse: Codable, Sendable {
    public let data: [ASCIAPVersion]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCIAPVersionPagingInformation?
}

public struct ASCIAPVersionPagingInformation: Codable, Sendable {
    public let paging: Paging

    public struct Paging: Codable, Sendable {
        public let total: Int?
        public let limit: Int
        public let nextCursor: String?
    }
}

public struct ASCIAPVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?

    public struct Attributes: Codable, Sendable {
        public let version: Int?
        public let state: String?
    }

    public struct Relationships: Codable, Sendable {
        public let inAppPurchase: ASCRelationship?
        public let image: ASCRelationship?
        public let images: ASCIAPVersionPagedRelationship?
        public let localizations: ASCIAPVersionPagedRelationship?
    }
}

public struct ASCIAPVersionPagedRelationship: Codable, Sendable {
    public let links: ASCRelationshipLinks?
    public let meta: ASCIAPVersionPagingInformation?
    public let data: [ASCResourceIdentifier]?
}

public struct CreateIAPVersionRequest: Codable, Sendable {
    public let data: Data

    public struct Data: Codable, Sendable {
        public let type: String
        public let relationships: Relationships

        public init(iapID: String) {
            self.type = "inAppPurchaseVersions"
            self.relationships = Relationships(
                inAppPurchase: Relationship(
                    data: ASCResourceIdentifier(type: "inAppPurchases", id: iapID)
                )
            )
        }
    }

    public struct Relationships: Codable, Sendable {
        public let inAppPurchase: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }

    public init(iapID: String) {
        self.data = Data(iapID: iapID)
    }
}

public struct ASCIAPVersionLocalizationResponse: Codable, Sendable {
    public let data: ASCIAPVersionLocalization
    public let links: ASCPagedDocumentLinks
}

public struct ASCIAPVersionLocalizationsResponse: Codable, Sendable {
    public let data: [ASCIAPVersionLocalization]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCIAPVersionPagingInformation?
}

public struct ASCIAPVersionLocalization: Codable, Sendable {
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

public struct CreateIAPVersionLocalizationRequest: Codable, Sendable {
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
            type: "inAppPurchaseLocalizations",
            attributes: Attributes(name: name, locale: locale, description: description),
            relationships: Relationships(
                version: Relationship(
                    data: ASCResourceIdentifier(type: "inAppPurchaseVersions", id: versionID)
                )
            )
        )
    }
}

public struct UpdateIAPVersionLocalizationRequest: Codable, Sendable {
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
            type: "inAppPurchaseLocalizations",
            id: localizationID,
            attributes: Attributes(name: name, description: description)
        )
    }
}

public struct ASCIAPVersionImageResponse: Codable, Sendable {
    public let data: ASCIAPVersionImage
    public let links: ASCPagedDocumentLinks
}

public struct ASCIAPVersionImagesResponse: Codable, Sendable {
    public let data: [ASCIAPVersionImage]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCIAPVersionPagingInformation?
}

public struct ASCIAPVersionImage: Codable, Sendable {
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

public struct CreateIAPVersionImageRequest: Codable, Sendable {
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
            type: "inAppPurchaseImages",
            attributes: Attributes(fileSize: fileSize, fileName: fileName),
            relationships: Relationships(
                version: Relationship(
                    data: ASCResourceIdentifier(type: "inAppPurchaseVersions", id: versionID)
                )
            )
        )
    }
}

public struct CommitIAPVersionImageRequest: Codable, Sendable {
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
            type: "inAppPurchaseImages",
            id: imageID,
            attributes: Attributes(uploaded: true)
        )
    }
}

extension ASCIAPVersionImage: RecoverableUploadResource {
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
