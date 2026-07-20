import Foundation

enum ASCBuildUploadResourceType: String, Codable, Sendable {
    case buildUpload = "buildUploads"
}

enum ASCBuildUploadFileResourceType: String, Codable, Sendable {
    case buildUploadFile = "buildUploadFiles"
}

struct ASCBuildUploadDocumentLinks: Codable, Sendable {
    let `self`: String
}

struct ASCBuildUploadResponse: Codable, Sendable {
    let data: ASCBuildUpload
    let included: [JSONValue]?
    let links: ASCBuildUploadDocumentLinks
}

struct ASCBuildUploadsResponse: Codable, Sendable {
    let data: [ASCBuildUpload]
    let included: [JSONValue]?
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCBuildUploadFileResponse: Codable, Sendable {
    let data: ASCBuildUploadFile
    let links: ASCBuildUploadDocumentLinks
}

struct ASCBuildUploadFilesResponse: Codable, Sendable {
    let data: [ASCBuildUploadFile]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

public struct ASCBuildUpload: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let cfBundleShortVersionString: String?
        public let cfBundleVersion: String?
        public let createdDate: String?
        public let state: ASCBuildUploadState?
        public let platform: String?
        public let uploadedDate: String?
    }

    public struct Relationships: Codable, Sendable {
        public let build: ASCRelationship?
        public let assetFile: ASCRelationship?
        public let assetDescriptionFile: ASCRelationship?
        public let assetSpiFile: ASCRelationship?
        public let buildUploadFiles: FilesRelationship?
    }

    public struct FilesRelationship: Codable, Sendable {
        public let links: ASCRelationshipLinks?
    }
}

public struct ASCBuildUploadState: Codable, Sendable {
    public let errors: [ASCBuildUploadStateDetail]?
    public let warnings: [ASCBuildUploadStateDetail]?
    public let infos: [ASCBuildUploadStateDetail]?
    public let state: String?
}

public struct ASCBuildUploadStateDetail: Codable, Sendable {
    public let code: String?
    public let description: String?
}

struct ASCBuildUploadFile: Codable, Sendable {
    let type: String
    let id: String
    let attributes: Attributes?
    let links: ASCResourceLinks?

    struct Attributes: Codable, Sendable {
        let assetDeliveryState: ASCAssetDeliveryState?
        let assetToken: String?
        let assetType: String?
        let fileName: String?
        let fileSize: Int?
        let sourceFileChecksums: ASCBuildUploadChecksums?
        let uploadOperations: [ASCUploadOperation]?
        let uti: String?
    }
}

struct ASCBuildUploadChecksums: Codable, Sendable {
    let file: Checksum?
    let composite: Checksum?

    struct Checksum: Codable, Sendable {
        let hash: String?
        let algorithm: String?
    }
}

struct ASCBuildUploadCreateRequest: Codable, Sendable {
    let data: Resource

    init(
        appID: String,
        shortVersion: String,
        buildVersion: String,
        platform: String
    ) {
        data = Resource(
            type: .buildUpload,
            attributes: Attributes(
                cfBundleShortVersionString: shortVersion,
                cfBundleVersion: buildVersion,
                platform: platform
            ),
            relationships: Relationships(
                app: Relationship(
                    data: ASCResourceIdentifier(type: "apps", id: appID)
                )
            )
        )
    }

    struct Resource: Codable, Sendable {
        let type: ASCBuildUploadResourceType
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let cfBundleShortVersionString: String
        let cfBundleVersion: String
        let platform: String
    }

    struct Relationships: Codable, Sendable {
        let app: Relationship
    }

    struct Relationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

struct ASCBuildUploadFileCreateRequest: Codable, Sendable {
    let data: Resource

    init(
        buildUploadID: String,
        assetType: String,
        fileName: String,
        fileSize: Int,
        uti: String
    ) {
        data = Resource(
            type: .buildUploadFile,
            attributes: Attributes(
                assetType: assetType,
                fileName: fileName,
                fileSize: fileSize,
                uti: uti
            ),
            relationships: Relationships(
                buildUpload: Relationship(
                    data: ASCResourceIdentifier(type: "buildUploads", id: buildUploadID)
                )
            )
        )
    }

    struct Resource: Codable, Sendable {
        let type: ASCBuildUploadFileResourceType
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let assetType: String
        let fileName: String
        let fileSize: Int
        let uti: String
    }

    struct Relationships: Codable, Sendable {
        let buildUpload: Relationship
    }

    struct Relationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

struct ASCBuildUploadFileUpdateRequest: Codable, Sendable {
    let data: Resource

    init(fileID: String, attributes: [String: JSONValue]?) {
        data = Resource(
            type: .buildUploadFile,
            id: fileID,
            attributes: attributes
        )
    }

    struct Resource: Codable, Sendable {
        let type: ASCBuildUploadFileResourceType
        let id: String
        let attributes: [String: JSONValue]?
    }
}
