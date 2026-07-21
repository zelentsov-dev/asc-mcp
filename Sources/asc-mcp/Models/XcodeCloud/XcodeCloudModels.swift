import Foundation

// MARK: - Xcode Cloud Response Wrappers

public struct ASCDocumentLinks: Codable, Sendable {
    public let `self`: String
}

public struct ASCXcodeCloudRelationshipLinksOnly: Codable, Sendable {
    public let links: ASCRelationshipLinks?

    /// Creates a links-only Xcode Cloud relationship.
    /// - Parameter links: Apple relationship links, when present.
    public init(links: ASCRelationshipLinks?) {
        self.links = links
    }

    private enum CodingKeys: String, CodingKey {
        case links
    }

    /// Decodes a relationship that permits only the `links` member.
    /// - Parameter decoder: Decoder containing the Apple relationship object.
    /// - Throws: `DecodingError` when unsupported linkage or metadata members are present.
    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: DynamicCodingKey.self).allKeys
        guard keys.allSatisfy({ $0.stringValue == CodingKeys.links.rawValue }) else {
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

    /// Encodes the links-only relationship.
    /// - Parameter encoder: Encoder receiving the relationship object.
    /// - Throws: Encoding errors produced by the supplied encoder.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(links, forKey: .links)
    }

    private struct DynamicCodingKey: CodingKey {
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
}

public protocol ASCXcodeCloudResourceContract: Codable, Sendable {
    static var expectedResourceType: String { get }
    static var permitsIncludedResources: Bool { get }
    var type: String { get }
    var id: String { get }
    var links: ASCResourceLinks? { get }
    /// Validates resource relationship linkage against the pinned Xcode Cloud schema.
    /// - Throws: `ASCError.parsing` when a relationship contains invalid linkage.
    func validateXcodeCloudRelationships() throws
}

public struct ASCXcodeCloudCollectionResponse<Resource: ASCXcodeCloudResourceContract>: Codable, Sendable {
    public let data: [Resource]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks
    public let meta: ASCPagingInformation?

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
        case meta
    }

    /// Decodes and validates a paged Xcode Cloud resource document.
    /// - Parameter decoder: Decoder containing the Apple response document.
    /// - Throws: Decoding or contract-validation errors for malformed response data.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([Resource].self, forKey: .data)
        links = try container.decode(ASCPagedDocumentLinks.self, forKey: .links)
        meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
        if Resource.permitsIncludedResources {
            included = try container.decodeIfPresent([JSONValue].self, forKey: .included)
        } else {
            if container.contains(.included) {
                throw DecodingError.dataCorruptedError(
                    forKey: .included,
                    in: container,
                    debugDescription: "Apple does not define included resources for \(Resource.expectedResourceType) responses"
                )
            }
            included = nil
        }
        try Self.validateDocumentLinks(links)
        try Self.validatePaging(meta, count: data.count)
        for resource in data {
            try Self.validate(resource)
        }
    }

    /// Encodes the validated paged resource document.
    /// - Parameter encoder: Encoder receiving the response document.
    /// - Throws: Encoding errors produced by the supplied encoder.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(included, forKey: .included)
        try container.encode(links, forKey: .links)
        try container.encodeIfPresent(meta, forKey: .meta)
    }

    private static func validate(_ resource: Resource) throws {
        try ASCXcodeCloudResourceValidation.validate(resource)
    }

    private static func validateDocumentLinks(_ links: ASCPagedDocumentLinks) throws {
        try ASCXcodeCloudResourceValidation.validateDocumentLink(links.`self`, name: "links.self")
        if let first = links.first {
            try ASCXcodeCloudResourceValidation.validateDocumentLink(first, name: "links.first")
        }
        if let next = links.next {
            try ASCXcodeCloudResourceValidation.validateDocumentLink(next, name: "links.next")
        }
    }

    private static func validatePaging(_ meta: ASCPagingInformation?, count: Int) throws {
        guard let meta else { return }
        guard let paging = meta.paging, let limit = paging.limit, limit > 0 else {
            throw ASCError.parsing("Xcode Cloud collection meta must contain a positive paging.limit")
        }
        if let total = paging.total, total < count {
            throw ASCError.parsing("Xcode Cloud collection meta.paging.total is smaller than the returned data count")
        }
    }
}

public struct ASCXcodeCloudSingleResponse<Resource: ASCXcodeCloudResourceContract>: Codable, Sendable {
    public let data: Resource
    public let included: [JSONValue]?
    public let links: ASCDocumentLinks

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
    }

    /// Decodes and validates a single-resource Xcode Cloud document.
    /// - Parameter decoder: Decoder containing the Apple response document.
    /// - Throws: Decoding or contract-validation errors for malformed response data.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(Resource.self, forKey: .data)
        links = try container.decode(ASCDocumentLinks.self, forKey: .links)
        if Resource.permitsIncludedResources {
            included = try container.decodeIfPresent([JSONValue].self, forKey: .included)
        } else {
            if container.contains(.included) {
                throw DecodingError.dataCorruptedError(
                    forKey: .included,
                    in: container,
                    debugDescription: "Apple does not define included resources for \(Resource.expectedResourceType) responses"
                )
            }
            included = nil
        }
        try ASCXcodeCloudResourceValidation.validateDocumentLink(links.`self`, name: "links.self")
        try ASCXcodeCloudResourceValidation.validate(data)
    }

    /// Encodes the validated single-resource document.
    /// - Parameter encoder: Encoder receiving the response document.
    /// - Throws: Encoding errors produced by the supplied encoder.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(included, forKey: .included)
        try container.encode(links, forKey: .links)
    }
}

public typealias ASCCIProductsResponse = ASCXcodeCloudCollectionResponse<ASCCIProduct>
public typealias ASCCIProductResponse = ASCXcodeCloudSingleResponse<ASCCIProduct>
public typealias ASCCIWorkflowsResponse = ASCXcodeCloudCollectionResponse<ASCCIWorkflow>
public typealias ASCCIWorkflowResponse = ASCXcodeCloudSingleResponse<ASCCIWorkflow>
public typealias ASCCIBuildRunsResponse = ASCXcodeCloudCollectionResponse<ASCCIBuildRun>
public typealias ASCCIBuildRunResponse = ASCXcodeCloudSingleResponse<ASCCIBuildRun>
public typealias ASCCIBuildActionsResponse = ASCXcodeCloudCollectionResponse<ASCCIBuildAction>
public typealias ASCCIBuildActionResponse = ASCXcodeCloudSingleResponse<ASCCIBuildAction>
public typealias ASCCIArtifactsResponse = ASCXcodeCloudCollectionResponse<ASCCIArtifact>
public typealias ASCCIArtifactResponse = ASCXcodeCloudSingleResponse<ASCCIArtifact>
public typealias ASCCIIssuesResponse = ASCXcodeCloudCollectionResponse<ASCCIIssue>
public typealias ASCCIIssueResponse = ASCXcodeCloudSingleResponse<ASCCIIssue>
public typealias ASCCITestResultsResponse = ASCXcodeCloudCollectionResponse<ASCCITestResult>
public typealias ASCCITestResultResponse = ASCXcodeCloudSingleResponse<ASCCITestResult>
public typealias ASCCIXcodeVersionsResponse = ASCXcodeCloudCollectionResponse<ASCCIXcodeVersion>
public typealias ASCCIXcodeVersionResponse = ASCXcodeCloudSingleResponse<ASCCIXcodeVersion>
public typealias ASCCIMacOSVersionsResponse = ASCXcodeCloudCollectionResponse<ASCCIMacOSVersion>
public typealias ASCCIMacOSVersionResponse = ASCXcodeCloudSingleResponse<ASCCIMacOSVersion>
public typealias ASCScmProvidersResponse = ASCXcodeCloudCollectionResponse<ASCScmProvider>
public typealias ASCScmProviderResponse = ASCXcodeCloudSingleResponse<ASCScmProvider>
public typealias ASCScmRepositoriesResponse = ASCXcodeCloudCollectionResponse<ASCScmRepository>
public typealias ASCScmRepositoryResponse = ASCXcodeCloudSingleResponse<ASCScmRepository>
public typealias ASCScmGitReferencesResponse = ASCXcodeCloudCollectionResponse<ASCScmGitReference>
public typealias ASCScmGitReferenceResponse = ASCXcodeCloudSingleResponse<ASCScmGitReference>
public typealias ASCScmPullRequestsResponse = ASCXcodeCloudCollectionResponse<ASCScmPullRequest>
public typealias ASCScmPullRequestResponse = ASCXcodeCloudSingleResponse<ASCScmPullRequest>

// MARK: - Xcode Cloud Resources

public struct ASCCIProduct: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let createdDate: String?
        public let productType: String?
    }

    public struct Relationships: Codable, Sendable {
        public let app: ASCRelationship?
        public let bundleId: ASCRelationship?
        public let workflows: ASCXcodeCloudRelationshipLinksOnly?
        public let primaryRepositories: ASCRelationshipMultiple?
        public let additionalRepositories: ASCXcodeCloudRelationshipLinksOnly?
        public let buildRuns: ASCXcodeCloudRelationshipLinksOnly?
    }
}

public struct ASCCIWorkflow: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let description: String?
        public let branchStartCondition: JSONValue?
        public let tagStartCondition: JSONValue?
        public let pullRequestStartCondition: JSONValue?
        public let scheduledStartCondition: JSONValue?
        public let manualBranchStartCondition: JSONValue?
        public let manualTagStartCondition: JSONValue?
        public let manualPullRequestStartCondition: JSONValue?
        public let actions: [JSONValue]?
        public let isEnabled: Bool?
        public let isLockedForEditing: Bool?
        public let clean: Bool?
        public let containerFilePath: String?
        public let lastModifiedDate: String?
    }

    public struct Relationships: Codable, Sendable {
        public let product: ASCRelationship?
        public let repository: ASCRelationship?
        public let xcodeVersion: ASCRelationship?
        public let macOsVersion: ASCRelationship?
        public let buildRuns: ASCXcodeCloudRelationshipLinksOnly?
    }
}

public struct ASCCIBuildRun: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let number: Int?
        public let createdDate: String?
        public let startedDate: String?
        public let finishedDate: String?
        public let sourceCommit: Commit?
        public let destinationCommit: Commit?
        public let isPullRequestBuild: Bool?
        public let issueCounts: IssueCounts?
        public let executionProgress: String?
        public let completionStatus: String?
        public let startReason: String?
        public let cancelReason: String?
    }

    public struct Commit: Codable, Sendable {
        public let commitSha: String?
        public let message: String?
        public let author: GitUser?
        public let committer: GitUser?
        public let webUrl: String?
    }

    public struct GitUser: Codable, Sendable {
        public let displayName: String?
        public let avatarUrl: String?
    }

    public struct IssueCounts: Codable, Sendable {
        public let analyzerWarnings: Int?
        public let errors: Int?
        public let testFailures: Int?
        public let warnings: Int?
    }

    public struct Relationships: Codable, Sendable {
        public let builds: ASCRelationshipMultiple?
        public let workflow: ASCRelationship?
        public let product: ASCRelationship?
        public let sourceBranchOrTag: ASCRelationship?
        public let destinationBranch: ASCRelationship?
        public let actions: ASCXcodeCloudRelationshipLinksOnly?
        public let pullRequest: ASCRelationship?
    }
}

public struct ASCCIBuildAction: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let actionType: String?
        public let startedDate: String?
        public let finishedDate: String?
        public let issueCounts: ASCCIBuildRun.IssueCounts?
        public let executionProgress: String?
        public let completionStatus: String?
        public let isRequiredToPass: Bool?
    }

    public struct Relationships: Codable, Sendable {
        public let buildRun: ASCRelationship?
        public let artifacts: ASCXcodeCloudRelationshipLinksOnly?
        public let issues: ASCXcodeCloudRelationshipLinksOnly?
        public let testResults: ASCXcodeCloudRelationshipLinksOnly?
    }
}

public struct ASCCIArtifact: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let fileType: String?
        public let fileName: String?
        public let fileSize: Int?
        public let downloadUrl: String?
    }
}

public struct ASCCIIssue: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let category: String?
        public let issueType: String?
        public let message: String?
        public let fileSource: FileSource?
    }
}

public struct ASCCITestResult: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let className: String?
        public let status: String?
        public let message: String?
        public let fileSource: ASCCIIssue.FileSource?
        public let destinationTestResults: [DestinationTestResult]?
    }

    public struct DestinationTestResult: Codable, Sendable {
        public let uuid: String?
        public let deviceName: String?
        public let osVersion: String?
        public let status: String?
        public let duration: Double?
    }
}

extension ASCCIIssue {
    public struct FileSource: Codable, Sendable {
        public let path: String?
        public let lineNumber: Int?
    }
}

public struct ASCCIXcodeVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let version: String?
        public let name: String?
        public let testDestinations: [TestDestination]?
    }

    public struct TestDestination: Codable, Sendable {
        public let deviceTypeName: String?
        public let deviceTypeIdentifier: String?
        public let availableRuntimes: [Runtime]?
        public let kind: String?

        public struct Runtime: Codable, Sendable {
            public let runtimeName: String?
            public let runtimeIdentifier: String?
        }
    }

    public struct Relationships: Codable, Sendable {
        public let macOsVersions: ASCRelationshipMultiple?
    }
}

public struct ASCCIMacOSVersion: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let version: String?
        public let name: String?
    }

    public struct Relationships: Codable, Sendable {
        public let xcodeVersions: ASCRelationshipMultiple?
    }
}

// MARK: - SCM Resources

public struct ASCScmProvider: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let scmProviderType: ScmProviderType?
        public let url: String?
    }

    public struct ScmProviderType: Codable, Sendable {
        public let kind: String?
        public let displayName: String?
        public let isOnPremise: Bool?
    }

    public struct Relationships: Codable, Sendable {
        public let repositories: ASCXcodeCloudRelationshipLinksOnly?
    }
}

public struct ASCScmRepository: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let lastAccessedDate: String?
        public let httpCloneUrl: String?
        public let sshCloneUrl: String?
        public let ownerName: String?
        public let repositoryName: String?
    }

    public struct Relationships: Codable, Sendable {
        public let scmProvider: ASCRelationship?
        public let defaultBranch: ASCRelationship?
        public let gitReferences: ASCXcodeCloudRelationshipLinksOnly?
        public let pullRequests: ASCXcodeCloudRelationshipLinksOnly?
    }
}

public struct ASCScmGitReference: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let canonicalName: String?
        public let isDeleted: Bool?
        public let kind: String?
    }

    public struct Relationships: Codable, Sendable {
        public let repository: ASCRelationship?
    }
}

public struct ASCScmPullRequest: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let title: String?
        public let number: Int?
        public let webUrl: String?
        public let sourceRepositoryOwner: String?
        public let sourceRepositoryName: String?
        public let sourceBranchName: String?
        public let destinationRepositoryOwner: String?
        public let destinationRepositoryName: String?
        public let destinationBranchName: String?
        public let isClosed: Bool?
        public let isCrossRepository: Bool?
    }

    public struct Relationships: Codable, Sendable {
        public let repository: ASCRelationship?
    }
}

private enum ASCXcodeCloudResourceValidation {
    static func validate<Resource: ASCXcodeCloudResourceContract>(_ resource: Resource) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: resource.type,
            id: resource.id,
            expectedType: Resource.expectedResourceType,
            context: "Xcode Cloud response"
        )
        if let selfLink = resource.links?.`self` {
            try validateDocumentLink(selfLink, name: "resource links.self")
        }
        try resource.validateXcodeCloudRelationships()
    }

    static func validateDocumentLink(_ value: String, name: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ASCError.parsing("Xcode Cloud response \(name) must be a non-empty URI reference")
        }
    }

    static func validate(_ relationship: ASCRelationship?, expectedType: String, name: String) throws {
        guard let identifier = relationship?.data else { return }
        try validate(identifier, expectedType: expectedType, name: name)
    }

    static func validate(_ relationship: ASCRelationshipMultiple?, expectedType: String, name: String) throws {
        guard let relationship else { return }
        var identities: Set<String> = []
        if let identifiers = relationship.data {
            for identifier in identifiers {
                try validate(identifier, expectedType: expectedType, name: name)
                guard identities.insert("\(identifier.type):\(identifier.id)").inserted else {
                    throw ASCError.parsing(
                        "Xcode Cloud relationship \(name) contains a duplicate resource identity"
                    )
                }
            }
        }
        if let meta = relationship.meta {
            guard let paging = meta.paging, let limit = paging.limit, limit > 0 else {
                throw ASCError.parsing("Xcode Cloud relationship \(name) meta must contain a positive paging.limit")
            }
            let count = relationship.data?.count ?? 0
            guard count <= limit else {
                throw ASCError.parsing("Xcode Cloud relationship \(name) data count exceeds meta.paging.limit")
            }
            if let total = paging.total, total < count {
                throw ASCError.parsing("Xcode Cloud relationship \(name) total is smaller than its data count")
            }
            if let nextCursor = paging.nextCursor,
               nextCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ASCError.parsing("Xcode Cloud relationship \(name) meta.paging.nextCursor must not be empty")
            }
        }
    }

    private static func validate(_ identifier: ASCResourceIdentifier, expectedType: String, name: String) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: identifier.type,
            id: identifier.id,
            expectedType: expectedType,
            context: "Xcode Cloud \(name) relationship"
        )
    }
}

public extension ASCXcodeCloudResourceContract {
    static var permitsIncludedResources: Bool { true }

    /// Accepts resources that do not declare typed relationship linkage.
    /// - Throws: This default implementation does not throw.
    func validateXcodeCloudRelationships() throws {}
}

extension ASCCIProduct: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciProducts" }

    /// Validates product relationship linkage types and paging metadata.
    /// - Throws: `ASCError.parsing` for malformed product relationships.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.app, expectedType: "apps", name: "app")
        try ASCXcodeCloudResourceValidation.validate(relationships?.bundleId, expectedType: "bundleIds", name: "bundleId")
        try ASCXcodeCloudResourceValidation.validate(relationships?.primaryRepositories, expectedType: "scmRepositories", name: "primaryRepositories")
    }
}

extension ASCCIWorkflow: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciWorkflows" }

    /// Validates workflow relationship linkage types.
    /// - Throws: `ASCError.parsing` for malformed workflow relationships.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.product, expectedType: "ciProducts", name: "product")
        try ASCXcodeCloudResourceValidation.validate(relationships?.repository, expectedType: "scmRepositories", name: "repository")
        try ASCXcodeCloudResourceValidation.validate(relationships?.xcodeVersion, expectedType: "ciXcodeVersions", name: "xcodeVersion")
        try ASCXcodeCloudResourceValidation.validate(relationships?.macOsVersion, expectedType: "ciMacOsVersions", name: "macOsVersion")
    }
}

extension ASCCIBuildRun: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciBuildRuns" }

    /// Validates build-run relationship linkage types and paging metadata.
    /// - Throws: `ASCError.parsing` for malformed build-run relationships.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.builds, expectedType: "builds", name: "builds")
        try ASCXcodeCloudResourceValidation.validate(relationships?.workflow, expectedType: "ciWorkflows", name: "workflow")
        try ASCXcodeCloudResourceValidation.validate(relationships?.product, expectedType: "ciProducts", name: "product")
        try ASCXcodeCloudResourceValidation.validate(relationships?.sourceBranchOrTag, expectedType: "scmGitReferences", name: "sourceBranchOrTag")
        try ASCXcodeCloudResourceValidation.validate(relationships?.destinationBranch, expectedType: "scmGitReferences", name: "destinationBranch")
        try ASCXcodeCloudResourceValidation.validate(relationships?.pullRequest, expectedType: "scmPullRequests", name: "pullRequest")
    }
}

extension ASCCIBuildAction: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciBuildActions" }

    /// Validates build-action relationship linkage types.
    /// - Throws: `ASCError.parsing` for malformed build-action relationships.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.buildRun, expectedType: "ciBuildRuns", name: "buildRun")
    }
}

extension ASCCIArtifact: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciArtifacts" }
    public static var permitsIncludedResources: Bool { false }
}

extension ASCCIIssue: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciIssues" }
    public static var permitsIncludedResources: Bool { false }
}

extension ASCCITestResult: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciTestResults" }
    public static var permitsIncludedResources: Bool { false }
}

extension ASCCIXcodeVersion: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciXcodeVersions" }

    /// Validates Xcode-version relationship linkage and paging metadata.
    /// - Throws: `ASCError.parsing` for malformed Xcode-version relationships.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.macOsVersions, expectedType: "ciMacOsVersions", name: "macOsVersions")
    }
}

extension ASCCIMacOSVersion: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "ciMacOsVersions" }

    /// Validates macOS-version relationship linkage and paging metadata.
    /// - Throws: `ASCError.parsing` for malformed macOS-version relationships.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.xcodeVersions, expectedType: "ciXcodeVersions", name: "xcodeVersions")
    }
}

extension ASCScmProvider: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "scmProviders" }
    public static var permitsIncludedResources: Bool { false }
}

extension ASCScmRepository: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "scmRepositories" }

    /// Validates SCM repository relationship linkage types.
    /// - Throws: `ASCError.parsing` for malformed repository relationships.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.scmProvider, expectedType: "scmProviders", name: "scmProvider")
        try ASCXcodeCloudResourceValidation.validate(relationships?.defaultBranch, expectedType: "scmGitReferences", name: "defaultBranch")
    }
}

extension ASCScmGitReference: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "scmGitReferences" }

    /// Validates SCM git-reference repository linkage.
    /// - Throws: `ASCError.parsing` for malformed repository linkage.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.repository, expectedType: "scmRepositories", name: "repository")
    }
}

extension ASCScmPullRequest: ASCXcodeCloudResourceContract {
    public static var expectedResourceType: String { "scmPullRequests" }

    /// Validates SCM pull-request repository linkage.
    /// - Throws: `ASCError.parsing` for malformed repository linkage.
    public func validateXcodeCloudRelationships() throws {
        try ASCXcodeCloudResourceValidation.validate(relationships?.repository, expectedType: "scmRepositories", name: "repository")
    }
}

// MARK: - Requests

public struct ASCCIBuildRunCreateRequest: Codable, Sendable {
    public let data: ResourceData

    public init(
        workflowID: String?,
        buildRunID: String?,
        sourceBranchOrTagID: String?,
        pullRequestID: String?,
        clean: Bool?
    ) {
        self.data = ResourceData(
            attributes: Attributes(clean: clean),
            relationships: Relationships(
                buildRun: buildRunID.map { Relationship(data: ASCResourceIdentifier(type: "ciBuildRuns", id: $0)) },
                workflow: workflowID.map { Relationship(data: ASCResourceIdentifier(type: "ciWorkflows", id: $0)) },
                sourceBranchOrTag: sourceBranchOrTagID.map { Relationship(data: ASCResourceIdentifier(type: "scmGitReferences", id: $0)) },
                pullRequest: pullRequestID.map { Relationship(data: ASCResourceIdentifier(type: "scmPullRequests", id: $0)) }
            )
        )
    }

    public struct ResourceData: Codable, Sendable {
        public let type: String
        public let attributes: Attributes?
        public let relationships: Relationships

        public init(attributes: Attributes?, relationships: Relationships) {
            self.type = "ciBuildRuns"
            self.attributes = attributes
            self.relationships = relationships
        }
    }

    public struct Attributes: Codable, Sendable {
        public let clean: Bool?
    }

    public struct Relationships: Codable, Sendable {
        public let buildRun: Relationship?
        public let workflow: Relationship?
        public let sourceBranchOrTag: Relationship?
        public let pullRequest: Relationship?
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
