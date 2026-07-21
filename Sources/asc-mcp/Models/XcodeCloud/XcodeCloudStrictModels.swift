import Foundation

struct ASCXcodeCloudDocumentLinks: Decodable, Sendable {
    let `self`: String
}

struct ASCXcodeCloudBuildRunResponse: Decodable, Sendable {
    let data: ASCCIBuildRun
    let included: [JSONValue]?
    let links: ASCXcodeCloudDocumentLinks
}

struct ASCXcodeCloudBuildsResponse: Decodable, Sendable {
    let data: [ASCXcodeCloudBuild]
    let included: [JSONValue]?
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCXcodeCloudBuild: Decodable, Sendable {
    let type: String
    let id: String
    let attributes: BuildAttributes?
    let relationships: ASCXcodeCloudBuildRelationships?
    let links: ASCResourceLinks?
}

struct ASCXcodeCloudBuildRelationships: Decodable, Sendable {
    let preReleaseVersion: ASCRelationship?
    let individualTesters: ASCRelationshipMultiple?
    let betaGroups: ASCRelationshipMultiple?
    let betaBuildLocalizations: ASCRelationshipMultiple?
    let appEncryptionDeclaration: ASCRelationship?
    let betaAppReviewSubmission: ASCRelationship?
    let app: ASCRelationship?
    let buildBetaDetail: ASCRelationship?
    let appStoreVersion: ASCRelationship?
    let icons: ASCRelationshipMultiple?
    let buildBundles: ASCRelationshipMultiple?
    let buildUpload: ASCRelationship?
    let perfPowerMetrics: ASCXcodeCloudLinksOnlyRelationship?
    let diagnosticSignatures: ASCXcodeCloudLinksOnlyRelationship?
}

struct ASCXcodeCloudLinksOnlyRelationship: Decodable, Sendable {
    let links: ASCRelationshipLinks?

    private enum CodingKeys: String, CodingKey {
        case links
    }

    init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: ASCXcodeCloudDynamicCodingKey.self).allKeys
        guard allKeys.allSatisfy({ $0.stringValue == CodingKeys.links.rawValue }) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Xcode Cloud links-only relationship contains unsupported members"
                )
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        links = try container.decodeIfPresent(ASCRelationshipLinks.self, forKey: .links)
    }
}

private struct ASCXcodeCloudDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
