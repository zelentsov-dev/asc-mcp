import Foundation
import MCP

extension XcodeCloudWorker {
    /// Gets the Xcode Cloud product associated with an app.
    /// - Parameter params: Tool parameters containing `app_id` and optional include controls.
    /// - Returns: A validated Xcode Cloud product and any explicitly requested included resources.
    /// - Throws: Never; validation, networking, and API failures are returned as MCP errors.
    func getAppProduct(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await relatedResourceResult(failureContext: "get the app Xcode Cloud product") {
            let arguments = try relatedArguments(
                params,
                allowed: ["app_id", "include", "primary_repositories_limit"]
            )
            let appID = try relatedIdentifier("app_id", from: arguments)
            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appID, field: "app_id"))/ciProduct"
            var query: [String: String] = [:]
            let includes = try relatedApplyInclude(
                arguments,
                allowed: ["app", "bundleId", "primaryRepositories"],
                to: &query
            )
            try relatedRequireInclude(
                for: arguments["primary_repositories_limit"],
                field: "primary_repositories_limit",
                include: "primaryRepositories",
                selectedIncludes: includes
            )
            try relatedApplyInteger(
                arguments["primary_repositories_limit"],
                field: "primary_repositories_limit",
                appleName: "limit[primaryRepositories]",
                range: 1...50,
                to: &query
            )

            let response = try await httpClient.get(
                endpoint,
                parameters: query,
                as: ASCXcodeCloudSingleResponse<ASCCIProduct>.self
            )
            try validateXcodeCloudSingleDocument(selfURL: response.links.`self`, endpoint: endpoint, query: query)
            try relatedValidateResource(
                response.data,
                expectedType: "ciProducts",
                context: "app product"
            )
            try validateXcodeCloudRequestedRelationshipLimit(
                [response.data.relationships?.primaryRepositories],
                query: query,
                appleName: "limit[primaryRepositories]",
                relationshipName: "primaryRepositories"
            )
            try relatedValidateIncluded(
                response.included,
                requestedIncludes: includes,
                resourceTypes: [
                    "app": ["apps"],
                    "bundleId": ["bundleIds"],
                    "primaryRepositories": ["scmRepositories"]
                ],
                linkedResources: [response.data],
                context: "app product"
            )

            var result: [String: Any] = [
                "success": true,
                "product": relatedFormatProduct(response.data),
                "self_url": response.links.`self`
            ]
            relatedAppendIncluded(response.included, to: &result)
            return result
        }
    }

    /// Gets the build run that owns an Xcode Cloud build action.
    /// - Parameter params: Tool parameters containing `action_id` and optional include controls.
    /// - Returns: A validated build run and any explicitly requested included resources.
    /// - Throws: Never; validation, networking, and API failures are returned as MCP errors.
    func getActionBuildRun(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await relatedResourceResult(failureContext: "get the action build run") {
            let arguments = try relatedArguments(
                params,
                allowed: ["action_id", "include", "builds_limit"]
            )
            let actionID = try relatedIdentifier("action_id", from: arguments)
            let endpoint = "/v1/ciBuildActions/\(try ASCPathSegment.encode(actionID, field: "action_id"))/buildRun"
            var query: [String: String] = [:]
            let includes = try relatedApplyInclude(
                arguments,
                allowed: [
                    "builds", "workflow", "product", "sourceBranchOrTag",
                    "destinationBranch", "pullRequest"
                ],
                to: &query
            )
            try relatedRequireInclude(
                for: arguments["builds_limit"],
                field: "builds_limit",
                include: "builds",
                selectedIncludes: includes
            )
            try relatedApplyInteger(
                arguments["builds_limit"],
                field: "builds_limit",
                appleName: "limit[builds]",
                range: 1...50,
                to: &query
            )

            let response = try await httpClient.get(
                endpoint,
                parameters: query,
                as: ASCXcodeCloudSingleResponse<ASCCIBuildRun>.self
            )
            try validateXcodeCloudSingleDocument(selfURL: response.links.`self`, endpoint: endpoint, query: query)
            try relatedValidateResource(
                response.data,
                expectedType: "ciBuildRuns",
                context: "action build run"
            )
            try validateXcodeCloudRequestedRelationshipLimit(
                [response.data.relationships?.builds],
                query: query,
                appleName: "limit[builds]",
                relationshipName: "builds"
            )
            try relatedValidateIncluded(
                response.included,
                requestedIncludes: includes,
                resourceTypes: [
                    "builds": ["builds"],
                    "workflow": ["ciWorkflows"],
                    "product": ["ciProducts"],
                    "sourceBranchOrTag": ["scmGitReferences"],
                    "destinationBranch": ["scmGitReferences"],
                    "pullRequest": ["scmPullRequests"]
                ],
                linkedResources: [response.data],
                context: "action build run"
            )

            var result: [String: Any] = [
                "success": true,
                "buildRun": relatedFormatBuildRun(response.data),
                "self_url": response.links.`self`
            ]
            relatedAppendIncluded(response.included, to: &result)
            return result
        }
    }

    /// Lists Xcode versions compatible with a macOS version.
    /// - Parameter params: Tool parameters containing `macos_version_id`, filters, and pagination controls.
    /// - Returns: Validated Xcode versions, included resources, and pagination fields.
    /// - Throws: Never; validation, networking, and API failures are returned as MCP errors.
    func listMacOSVersionXcodeVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await relatedResourceResult(failureContext: "list compatible Xcode versions") {
            let arguments = try relatedArguments(
                params,
                allowed: ["macos_version_id", "limit", "next_url", "include", "macos_versions_limit"]
            )
            let macOSVersionID = try relatedIdentifier("macos_version_id", from: arguments)
            let endpoint = "/v1/ciMacOsVersions/\(try ASCPathSegment.encode(macOSVersionID, field: "macos_version_id"))/xcodeVersions"
            var query = try relatedListQuery(arguments)
            let includes = try relatedApplyInclude(arguments, allowed: ["macOsVersions"], to: &query)
            try relatedRequireInclude(
                for: arguments["macos_versions_limit"],
                field: "macos_versions_limit",
                include: "macOsVersions",
                selectedIncludes: includes
            )
            try relatedApplyInteger(
                arguments["macos_versions_limit"],
                field: "macos_versions_limit",
                appleName: "limit[macOsVersions]",
                range: 1...50,
                to: &query
            )

            let page: XcodeCloudRelatedPage<ASCCIXcodeVersion> = try await relatedCollectionPage(
                endpoint: endpoint,
                query: query,
                nextURLValue: arguments["next_url"]
            )
            let response = page.response
            try relatedValidateResources(
                response.data,
                expectedType: "ciXcodeVersions",
                context: "compatible Xcode versions"
            )
            try validateXcodeCloudRequestedRelationshipLimit(
                response.data.map { $0.relationships?.macOsVersions },
                query: query,
                appleName: "limit[macOsVersions]",
                relationshipName: "macOsVersions"
            )
            try relatedValidateIncluded(
                response.included,
                requestedIncludes: includes,
                resourceTypes: ["macOsVersions": ["ciMacOsVersions"]],
                linkedResources: response.data,
                context: "compatible Xcode versions"
            )
            return try relatedCollectionResult(
                key: "xcodeVersions",
                values: response.data.map(relatedFormatXcodeVersion),
                page: page
            )
        }
    }

    /// Lists additional repositories attached to an Xcode Cloud product.
    /// - Parameter params: Tool parameters containing `product_id`, filters, and pagination controls.
    /// - Returns: Validated repositories, included resources, and pagination fields.
    /// - Throws: Never; validation, networking, and API failures are returned as MCP errors.
    func listProductAdditionalRepositories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await listProductRepositories(params, relationship: "additionalRepositories", failureContext: "list additional product repositories")
    }

    /// Gets the app associated with an Xcode Cloud product.
    /// - Parameter params: Tool parameters containing `product_id`.
    /// - Returns: A compact validated App Store Connect app projection.
    /// - Throws: Never; validation, networking, and API failures are returned as MCP errors.
    func getProductApp(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await relatedResourceResult(failureContext: "get the product app") {
            let arguments = try relatedArguments(params, allowed: ["product_id"])
            let productID = try relatedIdentifier("product_id", from: arguments)
            let endpoint = "/v1/ciProducts/\(try ASCPathSegment.encode(productID, field: "product_id"))/app"
            let response = try await httpClient.get(
                endpoint,
                as: ASCXcodeCloudSingleResponse<XcodeCloudRelatedApp>.self
            )
            try validateXcodeCloudSingleDocument(selfURL: response.links.`self`, endpoint: endpoint)
            try relatedValidateResource(
                type: response.data.type,
                id: response.data.id,
                links: response.data.links,
                expectedType: "apps",
                context: "product app"
            )
            return [
                "success": true,
                "app": relatedFormatApp(response.data),
                "self_url": response.links.`self`
            ]
        }
    }

    /// Lists primary repositories attached to an Xcode Cloud product.
    /// - Parameter params: Tool parameters containing `product_id`, filters, and pagination controls.
    /// - Returns: Validated repositories, included resources, and pagination fields.
    /// - Throws: Never; validation, networking, and API failures are returned as MCP errors.
    func listProductPrimaryRepositories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await listProductRepositories(params, relationship: "primaryRepositories", failureContext: "list primary product repositories")
    }

    /// Gets the SCM repository used by an Xcode Cloud workflow.
    /// - Parameter params: Tool parameters containing `workflow_id` and optional include controls.
    /// - Returns: A validated SCM repository and any explicitly requested included resources.
    /// - Throws: Never; validation, networking, and API failures are returned as MCP errors.
    func getWorkflowRepository(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await relatedResourceResult(failureContext: "get the workflow repository") {
            let arguments = try relatedArguments(params, allowed: ["workflow_id", "include"])
            let workflowID = try relatedIdentifier("workflow_id", from: arguments)
            let endpoint = "/v1/ciWorkflows/\(try ASCPathSegment.encode(workflowID, field: "workflow_id"))/repository"
            var query: [String: String] = [:]
            let includes = try relatedApplyInclude(
                arguments,
                allowed: ["scmProvider", "defaultBranch"],
                to: &query
            )
            let response = try await httpClient.get(
                endpoint,
                parameters: query,
                as: ASCXcodeCloudSingleResponse<ASCScmRepository>.self
            )
            try validateXcodeCloudSingleDocument(selfURL: response.links.`self`, endpoint: endpoint, query: query)
            try relatedValidateResource(
                response.data,
                expectedType: "scmRepositories",
                context: "workflow repository"
            )
            try relatedValidateIncluded(
                response.included,
                requestedIncludes: includes,
                resourceTypes: [
                    "scmProvider": ["scmProviders"],
                    "defaultBranch": ["scmGitReferences"]
                ],
                linkedResources: [response.data],
                context: "workflow repository"
            )
            var result: [String: Any] = [
                "success": true,
                "repository": relatedFormatRepository(response.data),
                "self_url": response.links.`self`
            ]
            relatedAppendIncluded(response.included, to: &result)
            return result
        }
    }

    /// Lists macOS versions compatible with an Xcode version.
    /// - Parameter params: Tool parameters containing `xcode_version_id`, filters, and pagination controls.
    /// - Returns: Validated macOS versions, included resources, and pagination fields.
    /// - Throws: Never; validation, networking, and API failures are returned as MCP errors.
    func listXcodeVersionMacOSVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await relatedResourceResult(failureContext: "list compatible macOS versions") {
            let arguments = try relatedArguments(
                params,
                allowed: ["xcode_version_id", "limit", "next_url", "include", "xcode_versions_limit"]
            )
            let xcodeVersionID = try relatedIdentifier("xcode_version_id", from: arguments)
            let endpoint = "/v1/ciXcodeVersions/\(try ASCPathSegment.encode(xcodeVersionID, field: "xcode_version_id"))/macOsVersions"
            var query = try relatedListQuery(arguments)
            let includes = try relatedApplyInclude(arguments, allowed: ["xcodeVersions"], to: &query)
            try relatedRequireInclude(
                for: arguments["xcode_versions_limit"],
                field: "xcode_versions_limit",
                include: "xcodeVersions",
                selectedIncludes: includes
            )
            try relatedApplyInteger(
                arguments["xcode_versions_limit"],
                field: "xcode_versions_limit",
                appleName: "limit[xcodeVersions]",
                range: 1...50,
                to: &query
            )

            let page: XcodeCloudRelatedPage<ASCCIMacOSVersion> = try await relatedCollectionPage(
                endpoint: endpoint,
                query: query,
                nextURLValue: arguments["next_url"]
            )
            let response = page.response
            try relatedValidateResources(
                response.data,
                expectedType: "ciMacOsVersions",
                context: "compatible macOS versions"
            )
            try validateXcodeCloudRequestedRelationshipLimit(
                response.data.map { $0.relationships?.xcodeVersions },
                query: query,
                appleName: "limit[xcodeVersions]",
                relationshipName: "xcodeVersions"
            )
            try relatedValidateIncluded(
                response.included,
                requestedIncludes: includes,
                resourceTypes: ["xcodeVersions": ["ciXcodeVersions"]],
                linkedResources: response.data,
                context: "compatible macOS versions"
            )
            return try relatedCollectionResult(
                key: "macOSVersions",
                values: response.data.map(relatedFormatMacOSVersion),
                page: page
            )
        }
    }

    private func listProductRepositories(
        _ params: CallTool.Parameters,
        relationship: String,
        failureContext: String
    ) async -> CallTool.Result {
        await relatedResourceResult(failureContext: failureContext) {
            let arguments = try relatedArguments(
                params,
                allowed: ["product_id", "repository_id", "limit", "next_url", "include"]
            )
            let productID = try relatedIdentifier("product_id", from: arguments)
            let productEndpoint = "/v1/ciProducts/\(try ASCPathSegment.encode(productID, field: "product_id"))"
            let endpoint = productEndpoint + "/" + relationship
            var query = try relatedListQuery(arguments)
            let repositoryIDs = try relatedIdentifierList("repository_id", from: arguments)
            if !repositoryIDs.isEmpty {
                query["filter[id]"] = repositoryIDs.joined(separator: ",")
            }
            let includes = try relatedApplyInclude(
                arguments,
                allowed: ["scmProvider", "defaultBranch"],
                to: &query
            )
            let page: XcodeCloudRelatedPage<ASCScmRepository> = try await relatedCollectionPage(
                endpoint: endpoint,
                query: query,
                nextURLValue: arguments["next_url"]
            )
            let response = page.response
            try relatedValidateResources(
                response.data,
                expectedType: "scmRepositories",
                context: failureContext
            )
            if !repositoryIDs.isEmpty {
                let requestedRepositoryIDs = Set(repositoryIDs)
                guard response.data.allSatisfy({ requestedRepositoryIDs.contains($0.id) }) else {
                    throw ASCError.parsing(
                        "Apple returned a repository outside the requested filter[id] scope"
                    )
                }
            }
            try relatedValidateIncluded(
                response.included,
                requestedIncludes: includes,
                resourceTypes: [
                    "scmProvider": ["scmProviders"],
                    "defaultBranch": ["scmGitReferences"]
                ],
                linkedResources: response.data,
                context: failureContext
            )
            return try relatedCollectionResult(
                key: "repositories",
                values: response.data.map(relatedFormatRepository),
                page: page
            )
        }
    }
}

private extension XcodeCloudWorker {
    func relatedResourceResult(
        failureContext: String,
        operation: () async throws -> [String: Any]
    ) async -> CallTool.Result {
        do {
            return MCPResult.jsonObject(try await operation())
        } catch {
            return MCPResult.error("Failed to \(failureContext): \(error.localizedDescription)")
        }
    }

    func relatedArguments(
        _ params: CallTool.Parameters,
        allowed: Set<String>
    ) throws -> [String: Value] {
        let arguments = params.arguments ?? [:]
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw XcodeCloudRelatedResourceArgumentError(
                "Unsupported parameter(s): \(unsupported.joined(separator: ", "))"
            )
        }
        return arguments
    }

    func relatedIdentifier(_ field: String, from arguments: [String: Value]) throws -> String {
        guard let value = arguments[field] else {
            throw XcodeCloudRelatedResourceArgumentError("Required parameter '\(field)' is missing")
        }
        guard let identifier = value.stringValue,
              !identifier.isEmpty,
              identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw XcodeCloudRelatedResourceArgumentError(
                "'\(field)' must be a non-empty canonical App Store Connect resource ID"
            )
        }
        let encoded = try ASCPathSegment.encode(identifier, field: field)
        guard encoded == identifier else {
            throw XcodeCloudRelatedResourceArgumentError(
                "'\(field)' must be a canonical App Store Connect resource ID"
            )
        }
        return identifier
    }

    func relatedIdentifierList(_ field: String, from arguments: [String: Value]) throws -> [String] {
        guard let value = arguments[field] else { return [] }
        let values: [Value]
        if value.stringValue != nil {
            values = [value]
        } else if let array = value.arrayValue, !array.isEmpty {
            values = array
        } else {
            throw XcodeCloudRelatedResourceArgumentError(
                "'\(field)' must be a canonical ID or non-empty array of canonical IDs"
            )
        }

        var seen: Set<String> = []
        return try values.enumerated().map { index, item in
            guard let identifier = item.stringValue,
                  !identifier.isEmpty,
                  identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw XcodeCloudRelatedResourceArgumentError(
                    "'\(field)[\(index)]' must be a non-empty canonical resource ID"
                )
            }
            let encoded = try ASCPathSegment.encode(identifier, field: "\(field)[\(index)]")
            guard encoded == identifier else {
                throw XcodeCloudRelatedResourceArgumentError(
                    "'\(field)[\(index)]' must be a canonical resource ID"
                )
            }
            guard seen.insert(identifier).inserted else {
                throw XcodeCloudRelatedResourceArgumentError("'\(field)' must not contain duplicate IDs")
            }
            return identifier
        }
    }

    func relatedStringList(
        _ value: Value?,
        field: String,
        allowed: Set<String>
    ) throws -> [String] {
        guard let value else { return [] }
        let values: [String]
        if let string = value.stringValue {
            values = [string]
        } else if let array = value.arrayValue,
                  !array.isEmpty,
                  array.allSatisfy({ $0.stringValue != nil }) {
            values = array.compactMap(\.stringValue)
        } else {
            throw XcodeCloudRelatedResourceArgumentError(
                "'\(field)' must be a string or non-empty array of strings"
            )
        }
        guard values.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
            throw XcodeCloudRelatedResourceArgumentError("'\(field)' must contain non-empty values")
        }
        guard Set(values).count == values.count else {
            throw XcodeCloudRelatedResourceArgumentError("'\(field)' must not contain duplicate values")
        }
        if let invalid = values.first(where: { !allowed.contains($0) }) {
            throw XcodeCloudRelatedResourceArgumentError("'\(field)' contains unsupported value '\(invalid)'")
        }
        return values
    }

    func relatedApplyInclude(
        _ arguments: [String: Value],
        allowed: Set<String>,
        to query: inout [String: String]
    ) throws -> [String] {
        let includes = try relatedStringList(arguments["include"], field: "include", allowed: allowed)
        if !includes.isEmpty {
            query["include"] = includes.joined(separator: ",")
        }
        return includes
    }

    func relatedApplyInteger(
        _ value: Value?,
        field: String,
        appleName: String,
        range: ClosedRange<Int>,
        to query: inout [String: String]
    ) throws {
        guard let value else { return }
        guard let integer = value.intValue, range.contains(integer) else {
            throw XcodeCloudRelatedResourceArgumentError(
                "'\(field)' must be an integer from \(range.lowerBound) through \(range.upperBound)"
            )
        }
        query[appleName] = String(integer)
    }

    func relatedRequireInclude(
        for value: Value?,
        field: String,
        include: String,
        selectedIncludes: [String]
    ) throws {
        guard value == nil || selectedIncludes.contains(include) else {
            throw XcodeCloudRelatedResourceArgumentError(
                "'\(field)' requires include to contain '\(include)'"
            )
        }
    }

    func relatedListQuery(_ arguments: [String: Value]) throws -> [String: String] {
        var query: [String: String] = [:]
        if let value = arguments["limit"] {
            try relatedApplyInteger(value, field: "limit", appleName: "limit", range: 1...200, to: &query)
        } else {
            query["limit"] = "25"
        }
        return query
    }

    func relatedCollectionPage<Resource: ASCXcodeCloudResourceContract>(
        endpoint: String,
        query: [String: String],
        nextURLValue: Value?
    ) async throws -> XcodeCloudRelatedPage<Resource> {
        let continuationScope = PaginationScope.strict(path: endpoint, query: query)
        let nextURL = try paginationURL(from: nextURLValue)
        let response: ASCXcodeCloudCollectionResponse<Resource>
        if let nextURL {
            response = try await httpClient.getPage(
                nextURL,
                scope: continuationScope,
                as: ASCXcodeCloudCollectionResponse<Resource>.self
            )
        } else {
            response = try await httpClient.get(
                endpoint,
                parameters: query,
                as: ASCXcodeCloudCollectionResponse<Resource>.self
            )
        }
        let contract = try validateXcodeCloudPage(
            links: response.links,
            meta: response.meta,
            endpoint: endpoint,
            query: query,
            requestedNextURL: nextURL,
            count: response.data.count
        )
        return XcodeCloudRelatedPage(response: response, contract: contract)
    }

    func relatedValidateResource<Resource: ASCXcodeCloudResourceContract>(
        _ resource: Resource,
        expectedType: String,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: resource.type,
            id: resource.id,
            expectedType: expectedType,
            context: context
        )
        try resource.validateXcodeCloudRelationships()
        try validateXcodeCloudRelationshipLinks(for: resource)
        if let link = resource.links?.`self` {
            try relatedValidateResourceSelf(link, type: resource.type, id: resource.id, context: context)
        }
    }

    func relatedValidateResource(
        type: String,
        id: String,
        links: ASCResourceLinks?,
        expectedType: String,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: type,
            id: id,
            expectedType: expectedType,
            context: context
        )
        if let link = links?.`self` {
            try relatedValidateResourceSelf(link, type: type, id: id, context: context)
        }
    }

    func relatedValidateResources<Resource: ASCXcodeCloudResourceContract>(
        _ resources: [Resource],
        expectedType: String,
        context: String
    ) throws {
        var identities: Set<String> = []
        for resource in resources {
            try relatedValidateResource(
                resource,
                expectedType: expectedType,
                context: context
            )
            guard identities.insert("\(resource.type):\(resource.id)").inserted else {
                throw ASCError.parsing("Apple returned a duplicate resource identity in \(context)")
            }
        }
    }

    func relatedValidateResourceSelf(
        _ link: String,
        type: String,
        id: String,
        context: String
    ) throws {
        guard let resourceBase = XcodeCloudRelatedResourcePath.basePathByType[type] else {
            throw ASCError.parsing("Apple returned an unsupported resource type in \(context)")
        }
        _ = try httpClient.validatedScopedLink(
            link,
            scope: PaginationScope(
                path: "\(resourceBase)/\(try ASCPathSegment.encode(id, field: "\(context) resource ID"))",
                allowedParameters: []
            )
        )
    }

    func relatedValidateIncluded<Resource: ASCXcodeCloudResourceContract>(
        _ included: [JSONValue]?,
        requestedIncludes: [String],
        resourceTypes: [String: Set<String>],
        linkedResources: [Resource],
        context: String
    ) throws {
        let requestedValue: Value? = requestedIncludes.isEmpty
            ? nil
            : .array(requestedIncludes.map { .string($0) })
        try validateXcodeCloudIncluded(
            included,
            requestedValue: requestedValue,
            resourceTypesByInclude: resourceTypes,
            linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: linkedResources),
            context: context
        )
    }

    func relatedCollectionResult<Resource: ASCXcodeCloudResourceContract>(
        key: String,
        values: [[String: Any]],
        page: XcodeCloudRelatedPage<Resource>
    ) throws -> [String: Any] {
        let response = page.response
        var result: [String: Any] = [
            "success": true,
            key: values,
            "count": values.count,
            "self_url": page.contract.selfURL
        ]
        if let first = page.contract.firstURL {
            result["first_url"] = first
        }
        if let next = page.contract.nextURL {
            result["next_url"] = next
        }
        if let total = page.contract.total {
            result["total"] = total
        }
        relatedAppendIncluded(response.included, to: &result)
        return result
    }

    func relatedAppendIncluded(_ included: [JSONValue]?, to result: inout [String: Any]) {
        if let included, !included.isEmpty {
            result["included"] = included.map(\.asAny)
        }
    }

    func relatedFormatProduct(_ product: ASCCIProduct) -> [String: Any] {
        [
            "id": product.id,
            "type": product.type,
            "selfUrl": (product.links?.`self`).jsonSafe,
            "name": (product.attributes?.name).jsonSafe,
            "createdDate": (product.attributes?.createdDate).jsonSafe,
            "productType": (product.attributes?.productType).jsonSafe,
            "appId": relatedRelationshipID(product.relationships?.app),
            "appUrl": relatedRelationshipURL(product.relationships?.app?.links),
            "appRelationshipUrl": relatedRelationshipSelfURL(product.relationships?.app?.links),
            "bundleIdResourceId": relatedRelationshipID(product.relationships?.bundleId),
            "workflowIds": NSNull(),
            "workflowsUrl": relatedRelationshipURL(product.relationships?.workflows?.links),
            "workflowsRelationshipUrl": relatedRelationshipSelfURL(product.relationships?.workflows?.links),
            "primaryRepositoryIds": relatedRelationshipIDs(product.relationships?.primaryRepositories),
            "primaryRepositoryIdsMeta": relatedRelationshipIDsMetadata(product.relationships?.primaryRepositories),
            "primaryRepositoriesUrl": relatedRelationshipURL(product.relationships?.primaryRepositories?.links),
            "primaryRepositoriesRelationshipUrl": relatedRelationshipSelfURL(product.relationships?.primaryRepositories?.links),
            "additionalRepositoryIds": NSNull(),
            "additionalRepositoriesUrl": relatedRelationshipURL(product.relationships?.additionalRepositories?.links),
            "additionalRepositoriesRelationshipUrl": relatedRelationshipSelfURL(product.relationships?.additionalRepositories?.links),
            "buildRunIds": NSNull(),
            "buildRunsUrl": relatedRelationshipURL(product.relationships?.buildRuns?.links),
            "buildRunsRelationshipUrl": relatedRelationshipSelfURL(product.relationships?.buildRuns?.links)
        ]
    }

    func relatedFormatBuildRun(_ buildRun: ASCCIBuildRun) -> [String: Any] {
        let attributes = buildRun.attributes
        return [
            "id": buildRun.id,
            "type": buildRun.type,
            "selfUrl": (buildRun.links?.`self`).jsonSafe,
            "number": (attributes?.number).jsonSafe,
            "createdDate": (attributes?.createdDate).jsonSafe,
            "startedDate": (attributes?.startedDate).jsonSafe,
            "finishedDate": (attributes?.finishedDate).jsonSafe,
            "sourceCommit": relatedFormatCommit(attributes?.sourceCommit),
            "destinationCommit": relatedFormatCommit(attributes?.destinationCommit),
            "isPullRequestBuild": (attributes?.isPullRequestBuild).jsonSafe,
            "issueCounts": relatedFormatIssueCounts(attributes?.issueCounts),
            "executionProgress": (attributes?.executionProgress).jsonSafe,
            "completionStatus": (attributes?.completionStatus).jsonSafe,
            "startReason": (attributes?.startReason).jsonSafe,
            "cancelReason": (attributes?.cancelReason).jsonSafe,
            "buildIds": relatedRelationshipIDs(buildRun.relationships?.builds),
            "buildIdsMeta": relatedRelationshipIDsMetadata(buildRun.relationships?.builds),
            "buildsUrl": relatedRelationshipURL(buildRun.relationships?.builds?.links),
            "buildsRelationshipUrl": relatedRelationshipSelfURL(buildRun.relationships?.builds?.links),
            "workflowId": relatedRelationshipID(buildRun.relationships?.workflow),
            "productId": relatedRelationshipID(buildRun.relationships?.product),
            "sourceBranchOrTagId": relatedRelationshipID(buildRun.relationships?.sourceBranchOrTag),
            "destinationBranchId": relatedRelationshipID(buildRun.relationships?.destinationBranch),
            "actionIds": NSNull(),
            "actionsUrl": relatedRelationshipURL(buildRun.relationships?.actions?.links),
            "actionsRelationshipUrl": relatedRelationshipSelfURL(buildRun.relationships?.actions?.links),
            "pullRequestId": relatedRelationshipID(buildRun.relationships?.pullRequest)
        ]
    }

    func relatedFormatXcodeVersion(_ version: ASCCIXcodeVersion) -> [String: Any] {
        [
            "id": version.id,
            "type": version.type,
            "selfUrl": (version.links?.`self`).jsonSafe,
            "version": (version.attributes?.version).jsonSafe,
            "name": (version.attributes?.name).jsonSafe,
            "testDestinations": version.attributes?.testDestinations?.map { destination in
                [
                    "deviceTypeName": (destination.deviceTypeName).jsonSafe,
                    "deviceTypeIdentifier": (destination.deviceTypeIdentifier).jsonSafe,
                    "kind": (destination.kind).jsonSafe,
                    "availableRuntimes": destination.availableRuntimes?.map { runtime in
                        [
                            "runtimeName": (runtime.runtimeName).jsonSafe,
                            "runtimeIdentifier": (runtime.runtimeIdentifier).jsonSafe
                        ]
                    } ?? [],
                    "availableRuntimesPresent": destination.availableRuntimes != nil
                ] as [String: Any]
            } ?? [],
            "testDestinationsPresent": version.attributes?.testDestinations != nil,
            "macOSVersionIds": relatedRelationshipIDs(version.relationships?.macOsVersions),
            "macOSVersionIdsMeta": relatedRelationshipIDsMetadata(version.relationships?.macOsVersions),
            "macOSVersionsUrl": relatedRelationshipURL(version.relationships?.macOsVersions?.links),
            "macOSVersionsRelationshipUrl": relatedRelationshipSelfURL(version.relationships?.macOsVersions?.links)
        ]
    }

    func relatedFormatMacOSVersion(_ version: ASCCIMacOSVersion) -> [String: Any] {
        [
            "id": version.id,
            "type": version.type,
            "selfUrl": (version.links?.`self`).jsonSafe,
            "version": (version.attributes?.version).jsonSafe,
            "name": (version.attributes?.name).jsonSafe,
            "xcodeVersionIds": relatedRelationshipIDs(version.relationships?.xcodeVersions),
            "xcodeVersionIdsMeta": relatedRelationshipIDsMetadata(version.relationships?.xcodeVersions),
            "xcodeVersionsUrl": relatedRelationshipURL(version.relationships?.xcodeVersions?.links),
            "xcodeVersionsRelationshipUrl": relatedRelationshipSelfURL(version.relationships?.xcodeVersions?.links)
        ]
    }

    func relatedFormatRepository(_ repository: ASCScmRepository) -> [String: Any] {
        [
            "id": repository.id,
            "type": repository.type,
            "selfUrl": (repository.links?.`self`).jsonSafe,
            "lastAccessedDate": (repository.attributes?.lastAccessedDate).jsonSafe,
            "httpCloneUrl": (repository.attributes?.httpCloneUrl).jsonSafe,
            "sshCloneUrl": (repository.attributes?.sshCloneUrl).jsonSafe,
            "ownerName": (repository.attributes?.ownerName).jsonSafe,
            "repositoryName": (repository.attributes?.repositoryName).jsonSafe,
            "providerId": relatedRelationshipID(repository.relationships?.scmProvider),
            "defaultBranchId": relatedRelationshipID(repository.relationships?.defaultBranch),
            "gitReferenceIds": NSNull(),
            "gitReferencesUrl": relatedRelationshipURL(repository.relationships?.gitReferences?.links),
            "gitReferencesRelationshipUrl": relatedRelationshipSelfURL(repository.relationships?.gitReferences?.links),
            "pullRequestIds": NSNull(),
            "pullRequestsUrl": relatedRelationshipURL(repository.relationships?.pullRequests?.links),
            "pullRequestsRelationshipUrl": relatedRelationshipSelfURL(repository.relationships?.pullRequests?.links)
        ]
    }

    func relatedFormatApp(_ app: XcodeCloudRelatedApp) -> [String: Any] {
        [
            "id": app.id,
            "type": app.type,
            "name": (app.attributes?.name).jsonSafe,
            "bundleId": (app.attributes?.bundleId).jsonSafe,
            "sku": (app.attributes?.sku).jsonSafe,
            "primaryLocale": (app.attributes?.primaryLocale).jsonSafe,
            "isOrEverWasMadeForKids": (app.attributes?.isOrEverWasMadeForKids).jsonSafe,
            "resourceUrl": (app.links?.`self`).jsonSafe
        ]
    }

    func relatedRelationshipID(_ relationship: ASCRelationship?) -> Any {
        relationship?.data?.id ?? NSNull()
    }

    func relatedRelationshipIDs(_ relationship: ASCRelationshipMultiple?) -> Any {
        relationship?.data?.map(\.id) ?? NSNull()
    }

    func relatedRelationshipIDsMetadata(_ relationship: ASCRelationshipMultiple?) -> Any {
        guard let relationship else { return NSNull() }
        let paging = relationship.meta?.paging
        let returnedCount = relationship.data?.count
        let isComplete: Any
        if let returnedCount, let total = paging?.total {
            isComplete = returnedCount == total && paging?.nextCursor == nil
        } else if paging?.nextCursor != nil {
            isComplete = false
        } else {
            isComplete = NSNull()
        }
        return [
            "returnedCount": (returnedCount).jsonSafe,
            "total": (paging?.total).jsonSafe,
            "limit": (paging?.limit).jsonSafe,
            "nextCursor": (paging?.nextCursor).jsonSafe,
            "isComplete": isComplete
        ]
    }

    func relatedRelationshipURL(_ links: ASCRelationshipLinks?) -> Any {
        links?.related ?? NSNull()
    }

    func relatedRelationshipSelfURL(_ links: ASCRelationshipLinks?) -> Any {
        links?.`self` ?? NSNull()
    }

    func relatedFormatCommit(_ commit: ASCCIBuildRun.Commit?) -> Any {
        guard let commit else { return NSNull() }
        return [
            "commitSha": (commit.commitSha).jsonSafe,
            "message": (commit.message).jsonSafe,
            "author": relatedFormatGitUser(commit.author),
            "committer": relatedFormatGitUser(commit.committer),
            "webUrl": (commit.webUrl).jsonSafe
        ]
    }

    func relatedFormatGitUser(_ user: ASCCIBuildRun.GitUser?) -> Any {
        guard let user else { return NSNull() }
        return [
            "displayName": (user.displayName).jsonSafe,
            "avatarUrl": (user.avatarUrl).jsonSafe
        ]
    }

    func relatedFormatIssueCounts(_ counts: ASCCIBuildRun.IssueCounts?) -> Any {
        guard let counts else { return NSNull() }
        return [
            "analyzerWarnings": (counts.analyzerWarnings).jsonSafe,
            "errors": (counts.errors).jsonSafe,
            "testFailures": (counts.testFailures).jsonSafe,
            "warnings": (counts.warnings).jsonSafe
        ]
    }
}

private struct XcodeCloudRelatedPage<Resource: ASCXcodeCloudResourceContract>: Sendable {
    let response: ASCXcodeCloudCollectionResponse<Resource>
    let contract: XcodeCloudPageContract
}

private struct XcodeCloudRelatedApp: ASCXcodeCloudResourceContract {
    static let expectedResourceType = "apps"
    static let permitsIncludedResources = false

    let type: String
    let id: String
    let attributes: Attributes?
    let links: ASCResourceLinks?

    struct Attributes: Codable, Sendable {
        let name: String?
        let bundleId: String?
        let sku: String?
        let primaryLocale: String?
        let isOrEverWasMadeForKids: Bool?
    }

    func validateXcodeCloudRelationships() throws {}
}

private enum XcodeCloudRelatedResourcePath {
    static let basePathByType: [String: String] = [
        "apps": "/v1/apps",
        "builds": "/v1/builds",
        "bundleIds": "/v1/bundleIds",
        "ciBuildRuns": "/v1/ciBuildRuns",
        "ciMacOsVersions": "/v1/ciMacOsVersions",
        "ciProducts": "/v1/ciProducts",
        "ciWorkflows": "/v1/ciWorkflows",
        "ciXcodeVersions": "/v1/ciXcodeVersions",
        "scmGitReferences": "/v1/scmGitReferences",
        "scmProviders": "/v1/scmProviders",
        "scmPullRequests": "/v1/scmPullRequests",
        "scmRepositories": "/v1/scmRepositories"
    ]
}

private struct XcodeCloudRelatedResourceArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
