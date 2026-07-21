import Foundation
import MCP

struct XcodeCloudPageContract: Sendable {
    let selfURL: String
    let firstURL: String?
    let nextURL: String?
    let total: Int?
}

extension XcodeCloudWorker {
    func validateXcodeCloudRequestedRelationshipLimit(
        _ relationships: [ASCRelationshipMultiple?],
        query: [String: String],
        appleName: String,
        relationshipName: String
    ) throws {
        guard let rawLimit = query[appleName], let requestedLimit = Int(rawLimit) else { return }

        for relationship in relationships {
            guard let relationship else { continue }
            let count = relationship.data?.count ?? 0
            guard count <= requestedLimit else {
                throw ASCError.parsing(
                    "Xcode Cloud relationship \(relationshipName) returned \(count) resources for requested limit \(requestedLimit)"
                )
            }
            if let responseLimit = relationship.meta?.paging?.limit,
               responseLimit != requestedLimit {
                throw ASCError.parsing(
                    "Xcode Cloud relationship \(relationshipName) meta.paging.limit does not match the requested limit"
                )
            }
        }
    }

    func validateXcodeCloudRelationshipLinks(
        _ links: ASCRelationshipLinks?,
        parentType: String,
        parentID: String,
        relationship: String
    ) throws {
        guard let links else { return }
        let supportedParents: Set<String> = [
            "ciProducts", "ciWorkflows", "ciBuildRuns", "ciBuildActions",
            "ciXcodeVersions", "ciMacOsVersions", "scmProviders", "scmRepositories"
        ]
        guard supportedParents.contains(parentType) else {
            throw ASCError.parsing("Xcode Cloud relationship links use an unsupported parent type")
        }
        let parentPath = "/v1/\(parentType)/\(try ASCPathSegment.encode(parentID))"
        if let selfURL = links.`self` {
            do {
                try validateXcodeCloudSingleDocument(
                    selfURL: selfURL,
                    endpoint: "\(parentPath)/relationships/\(relationship)"
                )
            } catch {
                throw ASCError.parsing(
                    "Xcode Cloud \(parentType).\(relationship) links.self is outside its parent scope: \(error.localizedDescription)"
                )
            }
        }
        if let relatedURL = links.related {
            do {
                try validateXcodeCloudSingleDocument(
                    selfURL: relatedURL,
                    endpoint: "\(parentPath)/\(relationship)"
                )
            } catch {
                throw ASCError.parsing(
                    "Xcode Cloud \(parentType).\(relationship) links.related is outside its parent scope: \(error.localizedDescription)"
                )
            }
        }
    }

    func validateXcodeCloudRelationshipLinks<Resource: ASCXcodeCloudResourceContract>(
        for resource: Resource
    ) throws {
        switch resource {
        case let product as ASCCIProduct:
            try validateXcodeCloudRelationshipLinks(product.relationships?.app?.links, parentType: product.type, parentID: product.id, relationship: "app")
            try rejectUnexpectedXcodeCloudRelationshipLinks(product.relationships?.bundleId?.links, parentType: product.type, relationship: "bundleId")
            try validateXcodeCloudRelationshipLinks(product.relationships?.workflows?.links, parentType: product.type, parentID: product.id, relationship: "workflows")
            try validateXcodeCloudRelationshipLinks(product.relationships?.primaryRepositories?.links, parentType: product.type, parentID: product.id, relationship: "primaryRepositories")
            try validateXcodeCloudRelationshipLinks(product.relationships?.additionalRepositories?.links, parentType: product.type, parentID: product.id, relationship: "additionalRepositories")
            try validateXcodeCloudRelationshipLinks(product.relationships?.buildRuns?.links, parentType: product.type, parentID: product.id, relationship: "buildRuns")
        case let workflow as ASCCIWorkflow:
            try rejectUnexpectedXcodeCloudRelationshipLinks(workflow.relationships?.product?.links, parentType: workflow.type, relationship: "product")
            try validateXcodeCloudRelationshipLinks(workflow.relationships?.repository?.links, parentType: workflow.type, parentID: workflow.id, relationship: "repository")
            try rejectUnexpectedXcodeCloudRelationshipLinks(workflow.relationships?.xcodeVersion?.links, parentType: workflow.type, relationship: "xcodeVersion")
            try rejectUnexpectedXcodeCloudRelationshipLinks(workflow.relationships?.macOsVersion?.links, parentType: workflow.type, relationship: "macOsVersion")
            try validateXcodeCloudRelationshipLinks(workflow.relationships?.buildRuns?.links, parentType: workflow.type, parentID: workflow.id, relationship: "buildRuns")
        case let buildRun as ASCCIBuildRun:
            try validateXcodeCloudRelationshipLinks(buildRun.relationships?.builds?.links, parentType: buildRun.type, parentID: buildRun.id, relationship: "builds")
            try rejectUnexpectedXcodeCloudRelationshipLinks(buildRun.relationships?.workflow?.links, parentType: buildRun.type, relationship: "workflow")
            try rejectUnexpectedXcodeCloudRelationshipLinks(buildRun.relationships?.product?.links, parentType: buildRun.type, relationship: "product")
            try rejectUnexpectedXcodeCloudRelationshipLinks(buildRun.relationships?.sourceBranchOrTag?.links, parentType: buildRun.type, relationship: "sourceBranchOrTag")
            try rejectUnexpectedXcodeCloudRelationshipLinks(buildRun.relationships?.destinationBranch?.links, parentType: buildRun.type, relationship: "destinationBranch")
            try validateXcodeCloudRelationshipLinks(buildRun.relationships?.actions?.links, parentType: buildRun.type, parentID: buildRun.id, relationship: "actions")
            try rejectUnexpectedXcodeCloudRelationshipLinks(buildRun.relationships?.pullRequest?.links, parentType: buildRun.type, relationship: "pullRequest")
        case let action as ASCCIBuildAction:
            try validateXcodeCloudRelationshipLinks(action.relationships?.buildRun?.links, parentType: action.type, parentID: action.id, relationship: "buildRun")
            try validateXcodeCloudRelationshipLinks(action.relationships?.artifacts?.links, parentType: action.type, parentID: action.id, relationship: "artifacts")
            try validateXcodeCloudRelationshipLinks(action.relationships?.issues?.links, parentType: action.type, parentID: action.id, relationship: "issues")
            try validateXcodeCloudRelationshipLinks(action.relationships?.testResults?.links, parentType: action.type, parentID: action.id, relationship: "testResults")
        case let version as ASCCIXcodeVersion:
            try validateXcodeCloudRelationshipLinks(version.relationships?.macOsVersions?.links, parentType: version.type, parentID: version.id, relationship: "macOsVersions")
        case let version as ASCCIMacOSVersion:
            try validateXcodeCloudRelationshipLinks(version.relationships?.xcodeVersions?.links, parentType: version.type, parentID: version.id, relationship: "xcodeVersions")
        case let provider as ASCScmProvider:
            try validateXcodeCloudRelationshipLinks(provider.relationships?.repositories?.links, parentType: provider.type, parentID: provider.id, relationship: "repositories")
        case let repository as ASCScmRepository:
            try rejectUnexpectedXcodeCloudRelationshipLinks(repository.relationships?.scmProvider?.links, parentType: repository.type, relationship: "scmProvider")
            try rejectUnexpectedXcodeCloudRelationshipLinks(repository.relationships?.defaultBranch?.links, parentType: repository.type, relationship: "defaultBranch")
            try validateXcodeCloudRelationshipLinks(repository.relationships?.gitReferences?.links, parentType: repository.type, parentID: repository.id, relationship: "gitReferences")
            try validateXcodeCloudRelationshipLinks(repository.relationships?.pullRequests?.links, parentType: repository.type, parentID: repository.id, relationship: "pullRequests")
        case let reference as ASCScmGitReference:
            try rejectUnexpectedXcodeCloudRelationshipLinks(reference.relationships?.repository?.links, parentType: reference.type, relationship: "repository")
        case let pullRequest as ASCScmPullRequest:
            try rejectUnexpectedXcodeCloudRelationshipLinks(pullRequest.relationships?.repository?.links, parentType: pullRequest.type, relationship: "repository")
        default:
            break
        }
    }

    func validateXcodeCloudIncluded(
        _ included: [JSONValue]?,
        requestedValue: Value?,
        resourceTypesByInclude: [String: Set<String>],
        linkedIdentitiesByInclude: [String: Set<String>]? = nil,
        context: String
    ) throws {
        guard let included, !included.isEmpty else { return }
        let requested: [String]
        if let scalar = requestedValue?.stringValue {
            requested = [scalar]
        } else {
            requested = requestedValue?.arrayValue?.compactMap(\.stringValue) ?? []
        }
        let allowedTypes = requested.reduce(into: Set<String>()) { result, include in
            result.formUnion(resourceTypesByInclude[include] ?? [])
        }
        guard !allowedTypes.isEmpty else {
            throw ASCError.parsing("Xcode Cloud response returned unrequested included resources in \(context)")
        }

        var identities: Set<String> = []
        for value in included {
            guard case .object(let object) = value,
                  let type = object["type"]?.stringValue,
                  let id = object["id"]?.stringValue,
                  allowedTypes.contains(type) else {
                throw ASCError.parsing("Xcode Cloud response returned an invalid included resource in \(context)")
            }
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: type,
                id: id,
                expectedType: type,
                context: "Xcode Cloud \(context) included resource"
            )
            guard identities.insert("\(type):\(id)").inserted else {
                throw ASCError.parsing("Xcode Cloud response returned duplicate included resources in \(context)")
            }
            if let linkedIdentitiesByInclude {
                let identity = "\(type):\(id)"
                let linkedIdentities = requested.reduce(into: Set<String>()) { result, include in
                    guard resourceTypesByInclude[include]?.contains(type) == true else { return }
                    result.formUnion(linkedIdentitiesByInclude[include] ?? [])
                }
                guard linkedIdentities.contains(identity) else {
                    throw ASCError.parsing(
                        "Xcode Cloud response returned an included resource outside requested relationship lineage in \(context)"
                    )
                }
            }
            if let links = object["links"] {
                guard case .object(let linksObject) = links else {
                    throw ASCError.parsing("Xcode Cloud included resource links are malformed in \(context)")
                }
                if let selfValue = linksObject["self"] {
                    guard let selfURL = selfValue.stringValue else {
                        throw ASCError.parsing("Xcode Cloud included resource links.self is malformed in \(context)")
                    }
                    if type == "buildIcons" || type == "buildBundles" {
                        try validateXcodeCloudOpaqueResourceSelf(selfURL, id: id)
                    } else {
                        try validateXcodeCloudResourceSelf(selfURL, type: type, id: id)
                    }
                }
            }
            try validateXcodeCloudIncludedRelationshipLinks(value, type: type)
        }
    }

    func xcodeCloudIncludedLineage<Resource: ASCXcodeCloudResourceContract>(
        for resources: [Resource]
    ) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for resource in resources {
            switch resource {
            case let product as ASCCIProduct:
                addXcodeCloudLineage(product.relationships?.app, include: "app", to: &result)
                addXcodeCloudLineage(product.relationships?.bundleId, include: "bundleId", to: &result)
                addXcodeCloudLineage(product.relationships?.primaryRepositories, include: "primaryRepositories", to: &result)
            case let workflow as ASCCIWorkflow:
                addXcodeCloudLineage(workflow.relationships?.product, include: "product", to: &result)
                addXcodeCloudLineage(workflow.relationships?.repository, include: "repository", to: &result)
                addXcodeCloudLineage(workflow.relationships?.xcodeVersion, include: "xcodeVersion", to: &result)
                addXcodeCloudLineage(workflow.relationships?.macOsVersion, include: "macOsVersion", to: &result)
            case let buildRun as ASCCIBuildRun:
                addXcodeCloudLineage(buildRun.relationships?.builds, include: "builds", to: &result)
                addXcodeCloudLineage(buildRun.relationships?.workflow, include: "workflow", to: &result)
                addXcodeCloudLineage(buildRun.relationships?.product, include: "product", to: &result)
                addXcodeCloudLineage(buildRun.relationships?.sourceBranchOrTag, include: "sourceBranchOrTag", to: &result)
                addXcodeCloudLineage(buildRun.relationships?.destinationBranch, include: "destinationBranch", to: &result)
                addXcodeCloudLineage(buildRun.relationships?.pullRequest, include: "pullRequest", to: &result)
            case let action as ASCCIBuildAction:
                addXcodeCloudLineage(action.relationships?.buildRun, include: "buildRun", to: &result)
            case let version as ASCCIXcodeVersion:
                addXcodeCloudLineage(version.relationships?.macOsVersions, include: "macOsVersions", to: &result)
            case let version as ASCCIMacOSVersion:
                addXcodeCloudLineage(version.relationships?.xcodeVersions, include: "xcodeVersions", to: &result)
            case let repository as ASCScmRepository:
                addXcodeCloudLineage(repository.relationships?.scmProvider, include: "scmProvider", to: &result)
                addXcodeCloudLineage(repository.relationships?.defaultBranch, include: "defaultBranch", to: &result)
            case let reference as ASCScmGitReference:
                addXcodeCloudLineage(reference.relationships?.repository, include: "repository", to: &result)
            case let pullRequest as ASCScmPullRequest:
                addXcodeCloudLineage(pullRequest.relationships?.repository, include: "repository", to: &result)
            default:
                break
            }
        }
        return result
    }

    func xcodeCloudBuildIncludedLineage(
        for builds: [ASCXcodeCloudBuild]
    ) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for build in builds {
            let relationships = build.relationships
            addXcodeCloudLineage(relationships?.preReleaseVersion, include: "preReleaseVersion", to: &result)
            addXcodeCloudLineage(relationships?.individualTesters, include: "individualTesters", to: &result)
            addXcodeCloudLineage(relationships?.betaGroups, include: "betaGroups", to: &result)
            addXcodeCloudLineage(relationships?.betaBuildLocalizations, include: "betaBuildLocalizations", to: &result)
            addXcodeCloudLineage(relationships?.appEncryptionDeclaration, include: "appEncryptionDeclaration", to: &result)
            addXcodeCloudLineage(relationships?.betaAppReviewSubmission, include: "betaAppReviewSubmission", to: &result)
            addXcodeCloudLineage(relationships?.app, include: "app", to: &result)
            addXcodeCloudLineage(relationships?.buildBetaDetail, include: "buildBetaDetail", to: &result)
            addXcodeCloudLineage(relationships?.appStoreVersion, include: "appStoreVersion", to: &result)
            addXcodeCloudLineage(relationships?.icons, include: "icons", to: &result)
            addXcodeCloudLineage(relationships?.buildBundles, include: "buildBundles", to: &result)
            addXcodeCloudLineage(relationships?.buildUpload, include: "buildUpload", to: &result)
        }
        return result
    }

    func validateXcodeCloudIncludedRelationshipLinks(
        _ value: JSONValue,
        type: String
    ) throws {
        let data = try JSONEncoder().encode(value)
        switch type {
        case "builds":
            try validateXcodeCloudBuild(try JSONDecoder().decode(ASCXcodeCloudBuild.self, from: data))
        case "ciProducts":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCIProduct.self, from: data))
        case "ciWorkflows":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCIWorkflow.self, from: data))
        case "ciBuildRuns":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCIBuildRun.self, from: data))
        case "ciBuildActions":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCIBuildAction.self, from: data))
        case "ciArtifacts":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCIArtifact.self, from: data))
        case "ciIssues":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCIIssue.self, from: data))
        case "ciTestResults":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCITestResult.self, from: data))
        case "ciXcodeVersions":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCIXcodeVersion.self, from: data))
        case "ciMacOsVersions":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCCIMacOSVersion.self, from: data))
        case "scmProviders":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCScmProvider.self, from: data))
        case "scmRepositories":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCScmRepository.self, from: data))
        case "scmGitReferences":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCScmGitReference.self, from: data))
        case "scmPullRequests":
            try validateXcodeCloudIncludedResource(try JSONDecoder().decode(ASCScmPullRequest.self, from: data))
        default:
            break
        }
    }

    func validateXcodeCloudPage(
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        endpoint: String,
        query: [String: String],
        requestedNextURL: String?,
        count: Int
    ) throws -> XcodeCloudPageContract {
        let effectiveLimit = Int(query["limit"] ?? "") ?? 25
        guard count <= effectiveLimit else {
            throw ASCError.parsing(
                "Xcode Cloud response returned \(count) resources for requested limit \(effectiveLimit)"
            )
        }

        let currentRequest: PaginationRequest
        if let requestedNextURL {
            currentRequest = try httpClient.validatedScopedLink(
                requestedNextURL,
                scope: PaginationScope(
                    path: endpoint,
                    requiredParameters: query,
                    allowedParameters: Set(query.keys).union(["cursor"]),
                    requiredNonEmptyParameters: ["cursor"]
                )
            )
        } else {
            currentRequest = PaginationRequest(path: endpoint, parameters: query)
        }

        let currentCursor = currentRequest.parameters["cursor"]
        var requiredSelfParameters = query
        if let currentCursor {
            requiredSelfParameters["cursor"] = currentCursor
        }
        let selfRequest = try httpClient.validatedScopedLink(
            links.`self`,
            scope: PaginationScope(
                path: endpoint,
                requiredParameters: requiredSelfParameters,
                allowedParameters: Set(requiredSelfParameters.keys),
                requiredNonEmptyParameters: currentCursor == nil ? [] : ["cursor"]
            )
        )
        guard selfRequest.parameters == requiredSelfParameters else {
            throw ASCError.parsing("Xcode Cloud response links.self does not identify the requested page")
        }

        if let first = links.first {
            let firstRequest = try httpClient.validatedScopedLink(
                first,
                scope: PaginationScope(
                    path: endpoint,
                    requiredParameters: query,
                    allowedParameters: Set(query.keys),
                    requiredNonEmptyParameters: []
                )
            )
            guard firstRequest.parameters == query else {
                throw ASCError.parsing("Xcode Cloud response links.first does not identify the first scoped page")
            }
        }

        var nextCursor: String?
        if let next = links.next {
            let nextRequest = try httpClient.validatedScopedLink(
                next,
                scope: PaginationScope(
                    path: endpoint,
                    requiredParameters: query,
                    allowedParameters: Set(query.keys).union(["cursor"]),
                    requiredNonEmptyParameters: ["cursor"]
                )
            )
            nextCursor = nextRequest.parameters["cursor"]
            guard nextCursor != currentCursor else {
                throw ASCError.parsing("Xcode Cloud response links.next does not advance the pagination cursor")
            }
        }

        let paging = meta?.paging
        if let paging {
            guard paging.limit == effectiveLimit else {
                throw ASCError.parsing("Xcode Cloud response meta.paging.limit does not match the requested limit")
            }
            if let total = paging.total, total < count {
                throw ASCError.parsing("Xcode Cloud response meta.paging.total is smaller than the page count")
            }
            if let metaCursor = paging.nextCursor {
                guard !metaCursor.isEmpty, metaCursor == nextCursor else {
                    throw ASCError.parsing("Xcode Cloud response meta.paging.nextCursor disagrees with links.next")
                }
            }
        }

        return XcodeCloudPageContract(
            selfURL: links.`self`,
            firstURL: links.first,
            nextURL: links.next,
            total: paging?.total
        )
    }

    func validateXcodeCloudSingleDocument(
        selfURL: String,
        endpoint: String,
        query: [String: String] = [:]
    ) throws {
        let request = try httpClient.validatedScopedLink(
            selfURL,
            scope: PaginationScope(
                path: endpoint,
                requiredParameters: query,
                allowedParameters: Set(query.keys),
                requiredNonEmptyParameters: []
            )
        )
        guard request.parameters == query else {
            throw ASCError.parsing("Xcode Cloud response links.self does not identify the requested resource")
        }
    }

    func validateXcodeCloudResourceSelf(
        _ selfURL: String?,
        type: String,
        id: String
    ) throws {
        guard let selfURL else { return }
        let collectionByType: [String: String] = [
            "apps": "apps",
            "appEncryptionDeclarations": "appEncryptionDeclarations",
            "appStoreVersions": "appStoreVersions",
            "betaAppReviewSubmissions": "betaAppReviewSubmissions",
            "betaBuildLocalizations": "betaBuildLocalizations",
            "betaGroups": "betaGroups",
            "betaTesters": "betaTesters",
            "bundleIds": "bundleIds",
            "buildBetaDetails": "buildBetaDetails",
            "buildUploads": "buildUploads",
            "ciProducts": "ciProducts",
            "ciWorkflows": "ciWorkflows",
            "ciBuildRuns": "ciBuildRuns",
            "ciBuildActions": "ciBuildActions",
            "ciArtifacts": "ciArtifacts",
            "ciIssues": "ciIssues",
            "ciTestResults": "ciTestResults",
            "ciXcodeVersions": "ciXcodeVersions",
            "ciMacOsVersions": "ciMacOsVersions",
            "scmProviders": "scmProviders",
            "scmRepositories": "scmRepositories",
            "scmGitReferences": "scmGitReferences",
            "scmPullRequests": "scmPullRequests",
            "builds": "builds",
            "preReleaseVersions": "preReleaseVersions"
        ]
        guard let collection = collectionByType[type] else {
            throw ASCError.parsing("Xcode Cloud response contains an unsupported resource type")
        }
        try validateXcodeCloudSingleDocument(
            selfURL: selfURL,
            endpoint: "/v1/\(collection)/\(try ASCPathSegment.encode(id))"
        )
    }

    func validateXcodeCloudOpaqueResourceSelf(
        _ selfURL: String?,
        id: String
    ) throws {
        guard let selfURL else { return }
        let trimmedURL = selfURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selfURL.isEmpty,
              trimmedURL == selfURL,
              let components = URLComponents(string: selfURL),
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.percentEncodedQuery == nil else {
            throw ASCError.parsing("Xcode Cloud response contains an invalid opaque resource links.self")
        }
        let path = components.percentEncodedPath
        let encodedID = try ASCPathSegment.encode(id)
        guard path.hasPrefix("/v1/"),
              path.split(separator: "/", omittingEmptySubsequences: false).last == Substring(encodedID) else {
            throw ASCError.parsing("Xcode Cloud response opaque resource links.self does not match its identity")
        }
        _ = try httpClient.validatedScopedLink(
            selfURL,
            scope: PaginationScope(path: path, allowedParameters: [])
        )
    }

    private func rejectUnexpectedXcodeCloudRelationshipLinks(
        _ links: ASCRelationshipLinks?,
        parentType: String,
        relationship: String
    ) throws {
        guard links == nil else {
            throw ASCError.parsing(
                "Xcode Cloud \(parentType).\(relationship) returned links that are absent from the pinned schema"
            )
        }
    }

    private func addXcodeCloudLineage(
        _ relationship: ASCRelationship?,
        include: String,
        to result: inout [String: Set<String>]
    ) {
        guard let identifier = relationship?.data else { return }
        result[include, default: []].insert("\(identifier.type):\(identifier.id)")
    }

    private func addXcodeCloudLineage(
        _ relationship: ASCRelationshipMultiple?,
        include: String,
        to result: inout [String: Set<String>]
    ) {
        for identifier in relationship?.data ?? [] {
            result[include, default: []].insert("\(identifier.type):\(identifier.id)")
        }
    }

    private func validateXcodeCloudIncludedResource<Resource: ASCXcodeCloudResourceContract>(
        _ resource: Resource
    ) throws {
        try resource.validateXcodeCloudRelationships()
        try validateXcodeCloudRelationshipLinks(for: resource)
    }
}
