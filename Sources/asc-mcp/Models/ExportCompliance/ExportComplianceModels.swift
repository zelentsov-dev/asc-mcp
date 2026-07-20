import Foundation

// MARK: - Responses

struct ASCExportComplianceDeclarationsResponse: Codable, Sendable {
    let data: [ASCExportComplianceDeclaration]
    let links: ASCPagedDocumentLinks?
    let meta: ASCPagingInformation?
}

struct ASCExportComplianceDeclarationResponse: Codable, Sendable {
    let data: ASCExportComplianceDeclaration
}

struct ASCExportComplianceDeclaration: Codable, Sendable {
    let type: String
    let id: String
    let attributes: Attributes?
    let relationships: Relationships?

    struct Attributes: Codable, Sendable {
        let appDescription: String?
        let createdDate: String?
        let exempt: Bool?
        let containsProprietaryCryptography: Bool?
        let containsThirdPartyCryptography: Bool?
        let availableOnFrenchStore: Bool?
        let appEncryptionDeclarationState: String?
        let codeValue: String?
    }

    struct Relationships: Codable, Sendable {
        let appEncryptionDeclarationDocument: ASCRelationship?
    }
}

struct ASCExportComplianceDocumentResponse: Codable, Sendable {
    let data: ASCExportComplianceDocument
}

struct ASCExportComplianceDocument: Codable, Sendable {
    let type: String
    let id: String
    let attributes: Attributes?

    struct Attributes: Codable, Sendable {
        let fileSize: Int?
        let fileName: String?
        let assetToken: String?
        let downloadUrl: String?
        let sourceFileChecksum: String?
        let uploadOperations: [ASCUploadOperation]?
        let assetDeliveryState: ASCAssetDeliveryState?
    }
}

// MARK: - Requests

struct ExportComplianceCreateDeclarationRequest: Codable, Sendable {
    let data: Data

    struct Data: Codable, Sendable {
        var type = "appEncryptionDeclarations"
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let appDescription: String
        let containsProprietaryCryptography: Bool
        let containsThirdPartyCryptography: Bool
        let availableOnFrenchStore: Bool
    }

    struct Relationships: Codable, Sendable {
        let app: Relationship
    }

    struct Relationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

struct ExportComplianceCreateDocumentRequest: Codable, Sendable {
    let data: Data

    struct Data: Codable, Sendable {
        var type = "appEncryptionDeclarationDocuments"
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let fileSize: Int
        let fileName: String
    }

    struct Relationships: Codable, Sendable {
        let appEncryptionDeclaration: Relationship
    }

    struct Relationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

struct ExportComplianceUpdateDocumentRequest: Codable, Sendable {
    let data: Data

    struct Data: Codable, Sendable {
        var type = "appEncryptionDeclarationDocuments"
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Codable, Sendable {
        let sourceFileChecksum: JSONValue?
        let uploaded: JSONValue?
    }
}

struct ExportComplianceAttachDeclarationRequest: Codable, Sendable {
    let data: Data

    struct Data: Codable, Sendable {
        var type = "builds"
        let id: String
        let relationships: Relationships
    }

    struct Relationships: Codable, Sendable {
        let appEncryptionDeclaration: Relationship
    }

    struct Relationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

extension ASCExportComplianceDocument: RecoverableUploadResource {
    var recoveryUploadOperations: [ASCUploadOperation]? {
        attributes?.uploadOperations
    }

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
