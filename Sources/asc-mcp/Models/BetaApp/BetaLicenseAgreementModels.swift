import Foundation

// MARK: - Beta License Agreement Models

/// Beta license agreements list response
public struct ASCBetaLicenseAgreementsResponse: Codable, Sendable {
    public let data: [ASCBetaLicenseAgreement]
    public let links: ASCPagedDocumentLinks?
}

/// Beta license agreement single response
public struct ASCBetaLicenseAgreementResponse: Codable, Sendable {
    public let data: ASCBetaLicenseAgreement
}

/// Beta license agreement resource
public struct ASCBetaLicenseAgreement: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BetaLicenseAgreementAttributes?
}

/// Beta license agreement attributes
public struct BetaLicenseAgreementAttributes: Codable, Sendable {
    public let agreementText: String?
}

// MARK: - Beta License Agreement Request Models

/// Update beta license agreement request
public struct UpdateBetaLicenseAgreementRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "betaLicenseAgreements"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let agreementText: String?
    }
}
