import Foundation

// MARK: - Xcode Cloud Response Wrappers

public struct ASCCIProductsResponse: Codable, Sendable {
    public let data: [ASCCIProduct]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCIProductResponse: Codable, Sendable {
    public let data: ASCCIProduct
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCCIWorkflowsResponse: Codable, Sendable {
    public let data: [ASCCIWorkflow]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCIWorkflowResponse: Codable, Sendable {
    public let data: ASCCIWorkflow
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCCIBuildRunsResponse: Codable, Sendable {
    public let data: [ASCCIBuildRun]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCIBuildRunResponse: Codable, Sendable {
    public let data: ASCCIBuildRun
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCCIBuildActionsResponse: Codable, Sendable {
    public let data: [ASCCIBuildAction]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCIBuildActionResponse: Codable, Sendable {
    public let data: ASCCIBuildAction
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCCIArtifactsResponse: Codable, Sendable {
    public let data: [ASCCIArtifact]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCIArtifactResponse: Codable, Sendable {
    public let data: ASCCIArtifact
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCCIIssuesResponse: Codable, Sendable {
    public let data: [ASCCIIssue]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCIIssueResponse: Codable, Sendable {
    public let data: ASCCIIssue
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCCITestResultsResponse: Codable, Sendable {
    public let data: [ASCCITestResult]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCITestResultResponse: Codable, Sendable {
    public let data: ASCCITestResult
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCCIXcodeVersionsResponse: Codable, Sendable {
    public let data: [ASCCIXcodeVersion]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCIXcodeVersionResponse: Codable, Sendable {
    public let data: ASCCIXcodeVersion
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCCIMacOSVersionsResponse: Codable, Sendable {
    public let data: [ASCCIMacOSVersion]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCCIMacOSVersionResponse: Codable, Sendable {
    public let data: ASCCIMacOSVersion
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCScmProvidersResponse: Codable, Sendable {
    public let data: [ASCScmProvider]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCScmProviderResponse: Codable, Sendable {
    public let data: ASCScmProvider
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCScmRepositoriesResponse: Codable, Sendable {
    public let data: [ASCScmRepository]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCScmRepositoryResponse: Codable, Sendable {
    public let data: ASCScmRepository
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCScmGitReferencesResponse: Codable, Sendable {
    public let data: [ASCScmGitReference]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCScmGitReferenceResponse: Codable, Sendable {
    public let data: ASCScmGitReference
    public let included: [JSONValue]?
    public let links: JSONValue?
}

public struct ASCScmPullRequestsResponse: Codable, Sendable {
    public let data: [ASCScmPullRequest]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCScmPullRequestResponse: Codable, Sendable {
    public let data: ASCScmPullRequest
    public let included: [JSONValue]?
    public let links: JSONValue?
}

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
        public let workflows: ASCRelationshipMultiple?
        public let primaryRepositories: ASCRelationshipMultiple?
        public let additionalRepositories: ASCRelationshipMultiple?
        public let buildRuns: ASCRelationshipMultiple?
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
        public let buildRuns: ASCRelationshipMultiple?
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
        public let email: String?
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
        public let actions: ASCRelationshipMultiple?
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
        public let artifacts: ASCRelationshipMultiple?
        public let issues: ASCRelationshipMultiple?
        public let testResults: ASCRelationshipMultiple?
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
        public let deviceName: String?
        public let osVersion: String?
        public let status: String?
        public let message: String?
        public let duration: Double?
    }
}

extension ASCCIIssue {
    public struct FileSource: Codable, Sendable {
        public let fileName: String?
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
        public let scmProviderType: String?
        public let url: String?
    }

    public struct Relationships: Codable, Sendable {
        public let repositories: ASCRelationshipMultiple?
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
        public let gitReferences: ASCRelationshipMultiple?
        public let pullRequests: ASCRelationshipMultiple?
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
