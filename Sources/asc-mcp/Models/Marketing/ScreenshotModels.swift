import Foundation

// MARK: - Screenshot Set Models

/// Screenshot sets list response
public struct ASCScreenshotSetsResponse: Codable, Sendable {
    public let data: [ASCScreenshotSet]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

/// Screenshot set resource
public struct ASCScreenshotSet: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: ScreenshotSetAttributes?
    public let relationships: ASCScreenshotSetRelationships?
    public let links: ASCMediaResourceLinks?
}

/// Single screenshot set response
public struct ASCScreenshotSetResponse: Codable, Sendable {
    public let data: ASCScreenshotSet
    public let links: ASCMediaDocumentLinks
}

/// Screenshot set attributes
public struct ScreenshotSetAttributes: Codable, Sendable {
    public let screenshotDisplayType: String?
}

public struct ASCScreenshotSetRelationships: Codable, Sendable {
    public let appStoreVersionLocalization: ASCRelationship?
    public let appCustomProductPageLocalization: ASCRelationship?
    public let appStoreVersionExperimentTreatmentLocalization: ASCRelationship?
}

// MARK: - Screenshot Models

/// Screenshots list response
public struct ASCScreenshotsResponse: Codable, Sendable {
    public let data: [ASCScreenshot]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

/// Single screenshot response
public struct ASCScreenshotResponse: Codable, Sendable {
    public let data: ASCScreenshot
    public let links: ASCMediaDocumentLinks
}

/// Screenshot resource
public struct ASCScreenshot: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: ScreenshotAttributes?
    public let relationships: ASCScreenshotRelationships?
    public let links: ASCMediaResourceLinks?
}

public struct ASCScreenshotRelationships: Codable, Sendable {
    public let appScreenshotSet: ASCRelationship?
}

/// Screenshot attributes
public struct ScreenshotAttributes: Codable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let sourceFileChecksum: String?
    public let imageAsset: ASCImageAsset?
    public let assetToken: String?
    public let assetType: String?
    public let uploadOperations: [ASCUploadOperation]?
    public let assetDeliveryState: ASCAssetDeliveryState?
}

// MARK: - Screenshot Request Models

/// Create screenshot set request
public struct CreateScreenshotSetRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "appScreenshotSets"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let screenshotDisplayType: String
    }

    public struct Relationships: Codable, Sendable {
        public let appStoreVersionLocalization: LocalizationRelationship?
        public let appCustomProductPageLocalization: LocalizationRelationship?
        public let appStoreVersionExperimentTreatmentLocalization: LocalizationRelationship?
    }

    public struct LocalizationRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Create screenshot reservation request
public struct CreateScreenshotRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "appScreenshots"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let fileName: String
        public let fileSize: Int
    }

    public struct Relationships: Codable, Sendable {
        public let appScreenshotSet: ScreenshotSetRelationship
    }

    public struct ScreenshotSetRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Reorder screenshots request
public struct ReorderScreenshotsRequest: Codable, Sendable {
    public let data: [ASCResourceIdentifier]
}

/// Reorder app previews request
public struct ReorderPreviewsRequest: Codable, Sendable {
    public let data: [ASCResourceIdentifier]
}

// MARK: - Preview Set Models

/// Preview sets list response
public struct ASCPreviewSetsResponse: Codable, Sendable {
    public let data: [ASCPreviewSet]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

/// Preview set resource
public struct ASCPreviewSet: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PreviewSetAttributes?
    public let relationships: ASCPreviewSetRelationships?
    public let links: ASCMediaResourceLinks?
}

/// Single preview set response
public struct ASCPreviewSetResponse: Codable, Sendable {
    public let data: ASCPreviewSet
    public let links: ASCMediaDocumentLinks
}

/// Preview set attributes
public struct PreviewSetAttributes: Codable, Sendable {
    public let previewType: String?
}

public struct ASCPreviewSetRelationships: Codable, Sendable {
    public let appStoreVersionLocalization: ASCRelationship?
    public let appCustomProductPageLocalization: ASCRelationship?
    public let appStoreVersionExperimentTreatmentLocalization: ASCRelationship?
}

// MARK: - Preview Models

/// Single preview response
public struct ASCPreviewResponse: Codable, Sendable {
    public let data: ASCPreview
    public let links: ASCMediaDocumentLinks
}

/// Preview resource
public struct ASCPreview: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: PreviewAttributes?
    public let relationships: ASCPreviewRelationships?
    public let links: ASCMediaResourceLinks?
}

public struct ASCPreviewRelationships: Codable, Sendable {
    public let appPreviewSet: ASCRelationship?
}

/// Preview attributes
public struct PreviewAttributes: Codable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let sourceFileChecksum: String?
    public let previewFrameTimeCode: String?
    public let mimeType: String?
    public let videoUrl: String?
    public let previewImage: ASCImageAsset?
    public let previewFrameImage: ASCPreviewFrameImage?
    public let uploadOperations: [ASCUploadOperation]?
    public let assetDeliveryState: ASCAssetDeliveryState?
    public let videoDeliveryState: ASCAssetDeliveryState?
}

public struct ASCPreviewFrameImage: Codable, Sendable {
    public let image: ASCImageAsset?
    public let state: ASCAssetDeliveryState?
}

// MARK: - Preview Request Models

/// Create preview set request
public struct CreatePreviewSetRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "appPreviewSets"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let previewType: String
    }

    public struct Relationships: Codable, Sendable {
        public let appStoreVersionLocalization: LocalizationRelationship?
        public let appCustomProductPageLocalization: LocalizationRelationship?
        public let appStoreVersionExperimentTreatmentLocalization: LocalizationRelationship?
    }

    public struct LocalizationRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Previews list response
public struct ASCPreviewsResponse: Codable, Sendable {
    public let data: [ASCPreview]
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?
}

public struct ASCMediaDocumentLinks: Codable, Sendable {
    public let `self`: String
}

public struct ASCMediaResourceLinks: Codable, Sendable {
    public let `self`: String?
}

/// Commit screenshot upload request
public struct CommitScreenshotRequest: Codable, Sendable {
    public let data: CommitData
    public struct CommitData: Codable, Sendable {
        public var type: String = "appScreenshots"
        public let id: String
        public let attributes: Attributes
    }
    public struct Attributes: Codable, Sendable {
        public let sourceFileChecksum: String?
        public let uploaded: Bool?
    }
}

/// Commit preview upload request
public struct CommitPreviewRequest: Codable, Sendable {
    public let data: CommitData
    public struct CommitData: Codable, Sendable {
        public var type: String = "appPreviews"
        public let id: String
        public let attributes: Attributes
    }
    public struct Attributes: Codable, Sendable {
        public let sourceFileChecksum: String?
        public let previewFrameTimeCode: NullableAttributeValue?
        public let uploaded: Bool?
    }
}

/// Create preview reservation request
public struct CreatePreviewRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public var type: String = "appPreviews"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let fileName: String
        public let fileSize: Int
        public let previewFrameTimeCode: NullableAttributeValue?
        public let mimeType: NullableAttributeValue?
    }

    public struct Relationships: Codable, Sendable {
        public let appPreviewSet: PreviewSetRelationship
    }

    public struct PreviewSetRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
