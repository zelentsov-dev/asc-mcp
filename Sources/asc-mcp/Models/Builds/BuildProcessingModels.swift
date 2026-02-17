import Foundation

// MARK: - Build Processing Models

/// Update build request for processing state
public struct UpdateBuildProcessingRequest: Codable, Sendable {
    public let data: UpdateBuildProcessingData
    
    public struct UpdateBuildProcessingData: Codable, Sendable {
        public let type: String = "builds"
        public let id: String
        public let attributes: BuildProcessingAttributes
    }
    
    public struct BuildProcessingAttributes: Codable, Sendable {
        public let expired: Bool?
        public let usesNonExemptEncryption: Bool?
    }
}

/// App encryption declaration response
public struct ASCAppEncryptionDeclarationResponse: Codable, Sendable {
    public let data: ASCAppEncryptionDeclaration
}

/// App encryption declarations response
public struct ASCAppEncryptionDeclarationsResponse: Codable, Sendable {
    public let data: [ASCAppEncryptionDeclaration]
    public let links: ASCPagedDocumentLinks?
}

/// App encryption declaration data
public struct ASCAppEncryptionDeclaration: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AppEncryptionDeclarationAttributes?
    public let relationships: AppEncryptionDeclarationRelationships?
}

/// App encryption declaration attributes
public struct AppEncryptionDeclarationAttributes: Codable, Sendable {
    public let platform: String?
    public let appEncryptionDeclarationState: String?
    public let availableOnFrenchStore: Bool?
    public let containsProprietaryCryptography: Bool?
    public let containsThirdPartyCryptography: Bool?
    public let isExportCompliant: Bool?
    public let usesEncryption: Bool?
    public let exempt: Bool?
    public let complianceCode: String?
    public let uploadedDate: String?
    public let appDescription: String?
    public let codeValue: String?
    public let documentName: String?
    public let documentType: String?
    public let documentUrl: String?
}

/// App encryption declaration relationships
public struct AppEncryptionDeclarationRelationships: Codable, Sendable {
    public let app: ASCRelationship?
    public let builds: ASCRelationshipMultiple?
    public let appEncryptionDeclarationDocument: ASCRelationship?
}

/// Create app encryption declaration request
public struct CreateAppEncryptionDeclarationRequest: Codable, Sendable {
    public let data: CreateAppEncryptionDeclarationData
    
    public struct CreateAppEncryptionDeclarationData: Codable, Sendable {
        public let type: String = "appEncryptionDeclarations"
        public let attributes: CreateAppEncryptionDeclarationAttributes
        public let relationships: CreateAppEncryptionDeclarationRelationships
    }
    
    public struct CreateAppEncryptionDeclarationAttributes: Codable, Sendable {
        public let platform: String
        public let usesEncryption: Bool
        public let exempt: Bool?
        public let containsProprietaryCryptography: Bool?
        public let containsThirdPartyCryptography: Bool?
        public let isExportCompliant: Bool?
        public let availableOnFrenchStore: Bool?
        public let complianceCode: String?
        public let appDescription: String?
        public let codeValue: String?
    }
    
    public struct CreateAppEncryptionDeclarationRelationships: Codable, Sendable {
        public let app: AppRelationship
        public let builds: BuildsRelationship?
    }
    
    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
    
    public struct BuildsRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}

/// Attach encryption declaration to build request
public struct AttachEncryptionDeclarationRequest: Codable, Sendable {
    public let data: AttachEncryptionDeclarationData
    
    public struct AttachEncryptionDeclarationData: Codable, Sendable {
        public let type: String = "builds"
        public let id: String
        public let relationships: AttachEncryptionDeclarationRelationships
    }
    
    public struct AttachEncryptionDeclarationRelationships: Codable, Sendable {
        public let appEncryptionDeclaration: AppEncryptionDeclarationRelationship
    }
    
    public struct AppEncryptionDeclarationRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - App Encryption Declaration Update

/// Update app encryption declaration request
public struct UpdateAppEncryptionDeclarationRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "appEncryptionDeclarations"
        public let id: String
        public let attributes: UpdateAttributes
    }

    public struct UpdateAttributes: Codable, Sendable {
        public let usesNonExemptEncryption: Bool?
    }
}