import Foundation
import MCP

extension XcodeCloudWorker {
    /// Lists Xcode Cloud products.
    /// - Parameter params: Tool parameters with optional product/app filters and pagination.
    /// - Returns: JSON object containing products, count, included resources, and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listProducts(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = params.arguments ?? [:]
            let response: ASCCIProductsResponse
            let endpoint = "/v1/ciProducts"
            var query = listQuery(arguments)
            try applyStringList(
                arguments["product_type"],
                field: "product_type",
                allowedValues: ["APP", "FRAMEWORK"],
                appleName: "filter[productType]",
                to: &query
            )
            try applyStringList(arguments["app_id"], field: "app_id", appleName: "filter[app]", to: &query)
            applyInclude(arguments, to: &query)
            try applyRelationshipLimit(
                arguments["primary_repositories_limit"],
                field: "primary_repositories_limit",
                appleName: "limit[primaryRepositories]",
                to: &query
            )
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCIProductsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIProductsResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudRequestedRelationshipLimit(
                response.data.map { $0.relationships?.primaryRepositories },
                query: query,
                appleName: "limit[primaryRepositories]",
                relationshipName: "primaryRepositories"
            )
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.productIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: "products"
            )
            var result = try validatedListResult(
                "products",
                response.data.map(formatProduct),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud products")
        }
    }

    /// Gets one Xcode Cloud product.
    /// - Parameter params: Tool parameters containing `product_id`.
    /// - Returns: JSON object containing the product resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getProduct(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let productID = arguments["product_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'product_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            try applyRelationshipLimit(
                arguments["primary_repositories_limit"],
                field: "primary_repositories_limit",
                appleName: "limit[primaryRepositories]",
                to: &query
            )
            let endpoint = "/v1/ciProducts/\(try ASCPathSegment.encode(productID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCCIProductResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.productIncludedTypes,
                context: "product"
            )
            try validateXcodeCloudRequestedRelationshipLimit(
                [response.data.relationships?.primaryRepositories],
                query: query,
                appleName: "limit[primaryRepositories]",
                relationshipName: "primaryRepositories"
            )
            var result: [String: Any] = [
                "success": true,
                "product": formatProduct(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud product")
        }
    }

    /// Lists workflows for one Xcode Cloud product.
    /// - Parameter params: Tool parameters containing `product_id`.
    /// - Returns: JSON object containing workflows and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listProductWorkflows(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let productID = arguments["product_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'product_id' is missing")
        }
        return try await listWorkflows(endpoint: "/v1/ciProducts/\(try ASCPathSegment.encode(productID))/workflows", arguments: arguments, failureContext: "product workflows")
    }

    /// Lists build runs for one Xcode Cloud product.
    /// - Parameter params: Tool parameters containing `product_id`.
    /// - Returns: JSON object containing build runs and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listProductBuildRuns(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let productID = arguments["product_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'product_id' is missing")
        }
        return try await listBuildRuns(endpoint: "/v1/ciProducts/\(try ASCPathSegment.encode(productID))/buildRuns", arguments: arguments, failureContext: "product build runs")
    }

    /// Gets one Xcode Cloud workflow.
    /// - Parameter params: Tool parameters containing `workflow_id`.
    /// - Returns: JSON object containing the workflow resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getWorkflow(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let workflowID = arguments["workflow_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'workflow_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            let endpoint = "/v1/ciWorkflows/\(try ASCPathSegment.encode(workflowID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCCIWorkflowResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.workflowIncludedTypes,
                context: "workflow"
            )
            var result: [String: Any] = [
                "success": true,
                "workflow": formatWorkflow(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud workflow")
        }
    }

    /// Lists build runs for one Xcode Cloud workflow.
    /// - Parameter params: Tool parameters containing `workflow_id`.
    /// - Returns: JSON object containing build runs and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listWorkflowBuildRuns(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let workflowID = arguments["workflow_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'workflow_id' is missing")
        }
        return try await listBuildRuns(endpoint: "/v1/ciWorkflows/\(try ASCPathSegment.encode(workflowID))/buildRuns", arguments: arguments, failureContext: "workflow build runs")
    }

    /// Gets one Xcode Cloud build run.
    /// - Parameter params: Tool parameters containing `build_run_id`.
    /// - Returns: JSON object containing the build run resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getBuildRun(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildRunID = arguments["build_run_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'build_run_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            try applyRelationshipLimit(
                arguments["builds_limit"],
                field: "builds_limit",
                appleName: "limit[builds]",
                to: &query
            )
            let endpoint = "/v1/ciBuildRuns/\(try ASCPathSegment.encode(buildRunID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCCIBuildRunResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.buildRunIncludedTypes,
                context: "build run"
            )
            try validateXcodeCloudRequestedRelationshipLimit(
                [response.data.relationships?.builds],
                query: query,
                appleName: "limit[builds]",
                relationshipName: "builds"
            )
            var result: [String: Any] = [
                "success": true,
                "buildRun": formatBuildRun(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud build run")
        }
    }

    /// Starts an Xcode Cloud build run.
    /// - Parameter params: Tool parameters containing exactly one of `workflow_id` or `build_run_id`.
    /// - Returns: JSON object containing the created build run resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func startBuildRun(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Provide exactly one of 'workflow_id' or 'build_run_id'")
        }

        let workflowID: String?
        let buildRunID: String?
        let sourceBranchOrTagID: String?
        let pullRequestID: String?
        let clean: Bool?
        do {
            try validateXcodeCloudArguments(
                arguments,
                allowed: [
                    "workflow_id", "build_run_id", "source_branch_or_tag_id",
                    "pull_request_id", "clean"
                ]
            )
            workflowID = try optionalXcodeCloudIdentifier("workflow_id", from: arguments)
            buildRunID = try optionalXcodeCloudIdentifier("build_run_id", from: arguments)
            sourceBranchOrTagID = try optionalXcodeCloudIdentifier("source_branch_or_tag_id", from: arguments)
            pullRequestID = try optionalXcodeCloudIdentifier("pull_request_id", from: arguments)
            if let cleanValue = arguments["clean"] {
                guard let value = cleanValue.boolValue else {
                    throw XcodeCloudArgumentError("clean must be a boolean")
                }
                clean = value
            } else {
                clean = nil
            }
            guard (workflowID == nil) != (buildRunID == nil) else {
                throw XcodeCloudArgumentError("Provide exactly one of 'workflow_id' or 'build_run_id'")
            }
            guard !(sourceBranchOrTagID != nil && pullRequestID != nil) else {
                throw XcodeCloudArgumentError("Use only one source selector: source_branch_or_tag_id or pull_request_id")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate Xcode Cloud build run start")
        }

        let request = ASCCIBuildRunCreateRequest(
            workflowID: workflowID,
            buildRunID: buildRunID,
            sourceBranchOrTagID: sourceBranchOrTagID,
            pullRequestID: pullRequestID,
            clean: clean
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode Xcode Cloud build run start")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/ciBuildRuns", body: body)
        } catch {
            return buildRunStartFailure(
                error,
                phase: .request,
                workflowID: workflowID,
                sourceBuildRunID: buildRunID,
                sourceBranchOrTagID: sourceBranchOrTagID,
                pullRequestID: pullRequestID,
                clean: clean
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Xcode Cloud build run start"
            )
            let response = try JSONDecoder().decode(ASCXcodeCloudBuildRunResponse.self, from: receipt.data)
            try ASCNonIdempotentWriteRecovery.validateCreatedResource(
                type: response.data.type,
                id: response.data.id,
                expectedType: "ciBuildRuns"
            )
            try response.data.validateXcodeCloudRelationships()
            try validateXcodeCloudRelationshipLinks(for: response.data)
            try validateBuildRunStartRequestedRelationships(
                response.data,
                workflowID: workflowID,
                sourceBranchOrTagID: sourceBranchOrTagID,
                pullRequestID: pullRequestID
            )
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: .array(Self.buildRunIncludedTypes.keys.sorted().map(Value.string)),
                resourceTypesByInclude: Self.buildRunIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: [response.data]),
                context: "build run start"
            )
            try validateBuildRunStartDocumentSelf(response.links.`self`)
            if let resourceSelf = response.data.links?.`self` {
                try validateXcodeCloudDocumentSelf(
                    resourceSelf,
                    expectedPath: "/v1/ciBuildRuns/\(try ASCPathSegment.encode(response.data.id))",
                    context: "Xcode Cloud build run resource"
                )
            }
            var result: [String: Any] = [
                "success": true,
                "operation": "start_build_run",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "changed": true,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "buildRun": formatBuildRun(response.data)
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return buildRunStartFailure(
                error,
                phase: .acceptedResponse,
                workflowID: workflowID,
                sourceBuildRunID: buildRunID,
                sourceBranchOrTagID: sourceBranchOrTagID,
                pullRequestID: pullRequestID,
                clean: clean
            )
        }
    }

    /// Lists actions for one Xcode Cloud build run.
    /// - Parameter params: Tool parameters containing `build_run_id`.
    /// - Returns: JSON object containing actions and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listBuildRunActions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildRunID = arguments["build_run_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'build_run_id' is missing")
        }

        do {
            let response: ASCCIBuildActionsResponse
            var query = listQuery(arguments)
            applyInclude(arguments, to: &query)
            let endpoint = "/v1/ciBuildRuns/\(try ASCPathSegment.encode(buildRunID))/actions"
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCIBuildActionsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIBuildActionsResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.actionIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: "build run actions"
            )
            var result = try validatedListResult(
                "actions",
                response.data.map(formatAction),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud build run actions")
        }
    }

    /// Lists App Store Connect builds created by one Xcode Cloud build run.
    /// - Parameter params: Tool parameters containing `build_run_id`.
    /// - Returns: JSON object containing build summaries and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listBuildRunBuilds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'build_run_id' is missing")
        }

        do {
            try validateXcodeCloudArguments(
                arguments,
                allowed: [
                    "build_run_id", "limit", "next_url", "version", "expired",
                    "processing_state", "beta_review_states", "uses_non_exempt_encryption",
                    "pre_release_versions", "pre_release_platforms", "build_audience_types",
                    "pre_release_version_ids", "app_ids", "beta_group_ids",
                    "app_store_version_ids", "build_ids", "uses_non_exempt_encryption_set",
                    "include", "individual_testers_limit", "beta_groups_limit",
                    "beta_build_localizations_limit", "icons_limit", "build_bundles_limit",
                    "sort"
                ]
            )
            let buildRunID = try requiredXcodeCloudIdentifier("build_run_id", from: arguments)
            let response: ASCXcodeCloudBuildsResponse
            var query = listQuery(arguments)
            try applyStringList(arguments["version"], field: "version", appleName: "filter[version]", to: &query)
            try applyBooleanList(arguments["expired"], field: "expired", appleName: "filter[expired]", to: &query)
            try applyStringList(
                arguments["processing_state"],
                field: "processing_state",
                allowedValues: Set(["PROCESSING", "FAILED", "INVALID", "VALID"]),
                appleName: "filter[processingState]",
                to: &query
            )
            try applyStringList(
                arguments["beta_review_states"],
                field: "beta_review_states",
                allowedValues: Set(["WAITING_FOR_REVIEW", "IN_REVIEW", "REJECTED", "APPROVED"]),
                appleName: "filter[betaAppReviewSubmission.betaReviewState]",
                to: &query
            )
            try applyBooleanList(
                arguments["uses_non_exempt_encryption"],
                field: "uses_non_exempt_encryption",
                appleName: "filter[usesNonExemptEncryption]",
                to: &query
            )
            try applyStringList(
                arguments["pre_release_versions"],
                field: "pre_release_versions",
                appleName: "filter[preReleaseVersion.version]",
                to: &query
            )
            try applyStringList(
                arguments["pre_release_platforms"],
                field: "pre_release_platforms",
                allowedValues: Set(["IOS", "MAC_OS", "TV_OS", "VISION_OS"]),
                appleName: "filter[preReleaseVersion.platform]",
                to: &query
            )
            try applyStringList(
                arguments["build_audience_types"],
                field: "build_audience_types",
                allowedValues: Set(["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"]),
                appleName: "filter[buildAudienceType]",
                to: &query
            )
            try applyStringList(
                arguments["pre_release_version_ids"],
                field: "pre_release_version_ids",
                appleName: "filter[preReleaseVersion]",
                to: &query
            )
            try applyStringList(arguments["app_ids"], field: "app_ids", appleName: "filter[app]", to: &query)
            try applyStringList(
                arguments["beta_group_ids"],
                field: "beta_group_ids",
                appleName: "filter[betaGroups]",
                to: &query
            )
            try applyStringList(
                arguments["app_store_version_ids"],
                field: "app_store_version_ids",
                appleName: "filter[appStoreVersion]",
                to: &query
            )
            try applyStringList(arguments["build_ids"], field: "build_ids", appleName: "filter[id]", to: &query)
            if let encryptionSet = arguments["uses_non_exempt_encryption_set"] {
                guard let value = encryptionSet.boolValue else {
                    throw XcodeCloudArgumentError("uses_non_exempt_encryption_set must be a boolean")
                }
                query["exists[usesNonExemptEncryption]"] = value ? "true" : "false"
            }
            try applyStringList(
                arguments["sort"],
                field: "sort",
                allowedValues: Set(["version", "-version", "uploadedDate", "-uploadedDate", "preReleaseVersion", "-preReleaseVersion"]),
                appleName: "sort",
                to: &query
            )
            let includes = try applyBuildIncludes(arguments["include"], to: &query)
            try applyBuildRelatedLimit(
                arguments["individual_testers_limit"],
                field: "individual_testers_limit",
                appleName: "limit[individualTesters]",
                relationship: "individualTesters",
                includes: includes,
                to: &query
            )
            try applyBuildRelatedLimit(
                arguments["beta_groups_limit"],
                field: "beta_groups_limit",
                appleName: "limit[betaGroups]",
                relationship: "betaGroups",
                includes: includes,
                to: &query
            )
            try applyBuildRelatedLimit(
                arguments["beta_build_localizations_limit"],
                field: "beta_build_localizations_limit",
                appleName: "limit[betaBuildLocalizations]",
                relationship: "betaBuildLocalizations",
                includes: includes,
                to: &query
            )
            try applyBuildRelatedLimit(
                arguments["icons_limit"],
                field: "icons_limit",
                appleName: "limit[icons]",
                relationship: "icons",
                includes: includes,
                to: &query
            )
            try applyBuildRelatedLimit(
                arguments["build_bundles_limit"],
                field: "build_bundles_limit",
                appleName: "limit[buildBundles]",
                relationship: "buildBundles",
                includes: includes,
                to: &query
            )
            let expectedRelationshipLimits = [
                "individualTesters": query["limit[individualTesters]"].flatMap(Int.init),
                "betaGroups": query["limit[betaGroups]"].flatMap(Int.init),
                "betaBuildLocalizations": query["limit[betaBuildLocalizations]"].flatMap(Int.init),
                "icons": query["limit[icons]"].flatMap(Int.init),
                "buildBundles": query["limit[buildBundles]"].flatMap(Int.init)
            ].compactMapValues { $0 }
            let endpoint = "/v1/ciBuildRuns/\(try ASCPathSegment.encode(buildRunID))/builds"
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCXcodeCloudBuildsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCXcodeCloudBuildsResponse.self)
            }
            if response.meta != nil, response.meta?.paging == nil {
                throw ASCError.parsing("Xcode Cloud build list meta must contain paging information")
            }
            let page = try validateXcodeCloudPage(
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL,
                count: response.data.count
            )
            var buildIdentities: Set<String> = []
            for build in response.data {
                try validateXcodeCloudBuild(
                    build,
                    expectedRelatedLimits: expectedRelationshipLimits
                )
                guard buildIdentities.insert("\(build.type):\(build.id)").inserted else {
                    throw ASCError.parsing("Xcode Cloud build list returned a duplicate build resource")
                }
            }
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.buildIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudBuildIncludedLineage(for: response.data),
                context: "build run builds list"
            )

            var result: [String: Any] = [
                "success": true,
                "builds": response.data.map(formatASCBuild),
                "count": response.data.count,
                "self_url": page.selfURL
            ]
            if let firstURL = page.firstURL {
                result["first_url"] = firstURL
            }
            if let nextURL = page.nextURL {
                result["next_url"] = nextURL
            }
            if let total = page.total {
                result["total"] = total
            }
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(
                result,
                explicitlyAllowedSensitivePaths: [
                    MCPSensitiveValuePath("builds", "*", "iconAssetToken")
                ]
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to list App Store Connect builds for Xcode Cloud run")
        }
    }

    /// Gets one Xcode Cloud build action.
    /// - Parameter params: Tool parameters containing `action_id`.
    /// - Returns: JSON object containing the action resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getAction(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let actionID = arguments["action_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'action_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            let endpoint = "/v1/ciBuildActions/\(try ASCPathSegment.encode(actionID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCCIBuildActionResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.actionIncludedTypes,
                context: "build action"
            )
            var result: [String: Any] = [
                "success": true,
                "action": formatAction(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud build action")
        }
    }

    /// Lists artifacts for one Xcode Cloud action.
    /// - Parameter params: Tool parameters containing `action_id`.
    /// - Returns: JSON object containing artifacts and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listActionArtifacts(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let actionID = arguments["action_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'action_id' is missing")
        }
        return try await listArtifacts(endpoint: "/v1/ciBuildActions/\(try ASCPathSegment.encode(actionID))/artifacts", arguments: arguments)
    }

    /// Lists issues for one Xcode Cloud action.
    /// - Parameter params: Tool parameters containing `action_id`.
    /// - Returns: JSON object containing issues and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listActionIssues(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let actionID = arguments["action_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'action_id' is missing")
        }
        return try await listIssues(endpoint: "/v1/ciBuildActions/\(try ASCPathSegment.encode(actionID))/issues", arguments: arguments)
    }

    /// Lists test results for one Xcode Cloud action.
    /// - Parameter params: Tool parameters containing `action_id`.
    /// - Returns: JSON object containing test results and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listActionTestResults(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let actionID = arguments["action_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'action_id' is missing")
        }
        return try await listTestResults(endpoint: "/v1/ciBuildActions/\(try ASCPathSegment.encode(actionID))/testResults", arguments: arguments)
    }

    /// Gets one Xcode Cloud artifact.
    /// - Parameter params: Tool parameters containing `artifact_id`.
    /// - Returns: JSON object containing the artifact resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getArtifact(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let artifactID = arguments["artifact_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'artifact_id' is missing")
        }

        do {
            let endpoint = "/v1/ciArtifacts/\(try ASCPathSegment.encode(artifactID))"
            let response = try await httpClient.get(endpoint, as: ASCCIArtifactResponse.self)
            try validateXcodeCloudSingle(response, endpoint: endpoint, context: "artifact")
            return MCPResult.jsonObject(
                [
                    "success": true,
                    "artifact": formatArtifact(response.data),
                    "self_url": response.links.`self`
                ],
                explicitlyAllowedSensitivePaths: [MCPSensitiveValuePath("artifact", "downloadUrl")]
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud artifact")
        }
    }

    /// Gets one Xcode Cloud issue.
    /// - Parameter params: Tool parameters containing `issue_id`.
    /// - Returns: JSON object containing the issue resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getIssue(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let issueID = arguments["issue_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'issue_id' is missing")
        }

        do {
            let endpoint = "/v1/ciIssues/\(try ASCPathSegment.encode(issueID))"
            let response = try await httpClient.get(endpoint, as: ASCCIIssueResponse.self)
            try validateXcodeCloudSingle(response, endpoint: endpoint, context: "issue")
            return MCPResult.jsonObject([
                "success": true,
                "issue": formatIssue(response.data),
                "self_url": response.links.`self`
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud issue")
        }
    }

    /// Gets one Xcode Cloud test result.
    /// - Parameter params: Tool parameters containing `test_result_id`.
    /// - Returns: JSON object containing the test result resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getTestResult(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let testResultID = arguments["test_result_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'test_result_id' is missing")
        }

        do {
            let endpoint = "/v1/ciTestResults/\(try ASCPathSegment.encode(testResultID))"
            let response = try await httpClient.get(endpoint, as: ASCCITestResultResponse.self)
            try validateXcodeCloudSingle(response, endpoint: endpoint, context: "test result")
            return MCPResult.jsonObject([
                "success": true,
                "testResult": formatTestResult(response.data),
                "self_url": response.links.`self`
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud test result")
        }
    }

    /// Lists Xcode versions for Xcode Cloud.
    /// - Parameter params: Tool parameters containing optional pagination and include values.
    /// - Returns: JSON object containing Xcode versions and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listXcodeVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            let response: ASCCIXcodeVersionsResponse
            let endpoint = "/v1/ciXcodeVersions"
            var query = listQuery(arguments)
            applyInclude(arguments, to: &query)
            try applyRelationshipLimit(
                arguments["macos_versions_limit"],
                field: "macos_versions_limit",
                appleName: "limit[macOsVersions]",
                to: &query
            )
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCIXcodeVersionsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIXcodeVersionsResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudRequestedRelationshipLimit(
                response.data.map { $0.relationships?.macOsVersions },
                query: query,
                appleName: "limit[macOsVersions]",
                relationshipName: "macOsVersions"
            )
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.xcodeVersionIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: "Xcode versions"
            )
            var result = try validatedListResult(
                "xcodeVersions",
                response.data.map(formatXcodeVersion),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud Xcode versions")
        }
    }

    /// Gets one Xcode Cloud Xcode version.
    /// - Parameter params: Tool parameters containing `xcode_version_id`.
    /// - Returns: JSON object containing the Xcode version resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getXcodeVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let xcodeVersionID = arguments["xcode_version_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'xcode_version_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            try applyRelationshipLimit(
                arguments["macos_versions_limit"],
                field: "macos_versions_limit",
                appleName: "limit[macOsVersions]",
                to: &query
            )
            let endpoint = "/v1/ciXcodeVersions/\(try ASCPathSegment.encode(xcodeVersionID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCCIXcodeVersionResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.xcodeVersionIncludedTypes,
                context: "Xcode version"
            )
            try validateXcodeCloudRequestedRelationshipLimit(
                [response.data.relationships?.macOsVersions],
                query: query,
                appleName: "limit[macOsVersions]",
                relationshipName: "macOsVersions"
            )
            var result: [String: Any] = [
                "success": true,
                "xcodeVersion": formatXcodeVersion(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud Xcode version")
        }
    }

    /// Lists macOS versions for Xcode Cloud.
    /// - Parameter params: Tool parameters containing optional pagination and include values.
    /// - Returns: JSON object containing macOS versions and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listMacOSVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            let response: ASCCIMacOSVersionsResponse
            let endpoint = "/v1/ciMacOsVersions"
            var query = listQuery(arguments)
            applyInclude(arguments, to: &query)
            try applyRelationshipLimit(
                arguments["xcode_versions_limit"],
                field: "xcode_versions_limit",
                appleName: "limit[xcodeVersions]",
                to: &query
            )
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCIMacOSVersionsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIMacOSVersionsResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudRequestedRelationshipLimit(
                response.data.map { $0.relationships?.xcodeVersions },
                query: query,
                appleName: "limit[xcodeVersions]",
                relationshipName: "xcodeVersions"
            )
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.macOSVersionIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: "macOS versions"
            )
            var result = try validatedListResult(
                "macOSVersions",
                response.data.map(formatMacOSVersion),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud macOS versions")
        }
    }

    /// Gets one Xcode Cloud macOS version.
    /// - Parameter params: Tool parameters containing `macos_version_id`.
    /// - Returns: JSON object containing the macOS version resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getMacOSVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let macOSVersionID = arguments["macos_version_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'macos_version_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            try applyRelationshipLimit(
                arguments["xcode_versions_limit"],
                field: "xcode_versions_limit",
                appleName: "limit[xcodeVersions]",
                to: &query
            )
            let endpoint = "/v1/ciMacOsVersions/\(try ASCPathSegment.encode(macOSVersionID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCCIMacOSVersionResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.macOSVersionIncludedTypes,
                context: "macOS version"
            )
            try validateXcodeCloudRequestedRelationshipLimit(
                [response.data.relationships?.xcodeVersions],
                query: query,
                appleName: "limit[xcodeVersions]",
                relationshipName: "xcodeVersions"
            )
            var result: [String: Any] = [
                "success": true,
                "macOSVersion": formatMacOSVersion(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud macOS version")
        }
    }

    /// Lists SCM providers.
    /// - Parameter params: Tool parameters containing optional pagination.
    /// - Returns: JSON object containing SCM providers and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listScmProviders(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            let response: ASCScmProvidersResponse
            let endpoint = "/v1/scmProviders"
            let query = listQuery(arguments)
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCScmProvidersResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCScmProvidersResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            let result = try validatedListResult(
                "providers",
                response.data.map(formatScmProvider),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud SCM providers")
        }
    }

    /// Gets one SCM provider.
    /// - Parameter params: Tool parameters containing `provider_id`.
    /// - Returns: JSON object containing the SCM provider resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getScmProvider(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let providerID = arguments["provider_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'provider_id' is missing")
        }

        do {
            let endpoint = "/v1/scmProviders/\(try ASCPathSegment.encode(providerID))"
            let response = try await httpClient.get(endpoint, as: ASCScmProviderResponse.self)
            try validateXcodeCloudSingle(response, endpoint: endpoint, context: "SCM provider")
            return MCPResult.jsonObject([
                "success": true,
                "provider": formatScmProvider(response.data),
                "self_url": response.links.`self`
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud SCM provider")
        }
    }

    /// Lists SCM repositories for one provider.
    /// - Parameter params: Tool parameters containing `provider_id`.
    /// - Returns: JSON object containing repositories and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listScmProviderRepositories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let providerID = arguments["provider_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'provider_id' is missing")
        }
        return try await listScmRepositories(endpoint: "/v1/scmProviders/\(try ASCPathSegment.encode(providerID))/repositories", arguments: arguments)
    }

    /// Lists SCM repositories available to Xcode Cloud.
    /// - Parameter params: Tool parameters containing optional filters and pagination.
    /// - Returns: JSON object containing repositories and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listScmRepositories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        try await listScmRepositories(endpoint: "/v1/scmRepositories", arguments: params.arguments ?? [:])
    }

    /// Gets one SCM repository.
    /// - Parameter params: Tool parameters containing `repository_id`.
    /// - Returns: JSON object containing the SCM repository resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getScmRepository(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let repositoryID = arguments["repository_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'repository_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            let endpoint = "/v1/scmRepositories/\(try ASCPathSegment.encode(repositoryID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCScmRepositoryResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.repositoryIncludedTypes,
                context: "SCM repository"
            )
            var result: [String: Any] = [
                "success": true,
                "repository": formatScmRepository(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud SCM repository")
        }
    }

    /// Lists SCM git references for one repository.
    /// - Parameter params: Tool parameters containing `repository_id`.
    /// - Returns: JSON object containing git references and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listScmRepositoryGitReferences(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let repositoryID = arguments["repository_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'repository_id' is missing")
        }
        return try await listScmGitReferences(endpoint: "/v1/scmRepositories/\(try ASCPathSegment.encode(repositoryID))/gitReferences", arguments: arguments)
    }

    /// Lists SCM pull requests for one repository.
    /// - Parameter params: Tool parameters containing `repository_id`.
    /// - Returns: JSON object containing pull requests and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listScmRepositoryPullRequests(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let repositoryID = arguments["repository_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'repository_id' is missing")
        }
        return try await listScmPullRequests(endpoint: "/v1/scmRepositories/\(try ASCPathSegment.encode(repositoryID))/pullRequests", arguments: arguments)
    }

    /// Gets one SCM git reference.
    /// - Parameter params: Tool parameters containing `git_reference_id`.
    /// - Returns: JSON object containing the git reference resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getScmGitReference(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let gitReferenceID = arguments["git_reference_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'git_reference_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            let endpoint = "/v1/scmGitReferences/\(try ASCPathSegment.encode(gitReferenceID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCScmGitReferenceResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.gitReferenceIncludedTypes,
                context: "SCM git reference"
            )
            var result: [String: Any] = [
                "success": true,
                "gitReference": formatScmGitReference(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud SCM git reference")
        }
    }

    /// Gets one SCM pull request.
    /// - Parameter params: Tool parameters containing `pull_request_id`.
    /// - Returns: JSON object containing the pull request resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getScmPullRequest(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let pullRequestID = arguments["pull_request_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'pull_request_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            applyInclude(arguments, to: &query)
            let endpoint = "/v1/scmPullRequests/\(try ASCPathSegment.encode(pullRequestID))"
            let response = try await httpClient.get(endpoint, parameters: query, as: ASCScmPullRequestResponse.self)
            try validateXcodeCloudSingle(
                response,
                endpoint: endpoint,
                query: query,
                requestedInclude: arguments["include"],
                includedTypes: Self.pullRequestIncludedTypes,
                context: "SCM pull request"
            )
            var result: [String: Any] = [
                "success": true,
                "pullRequest": formatScmPullRequest(response.data),
                "self_url": response.links.`self`
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get Xcode Cloud SCM pull request")
        }
    }

    private func listWorkflows(endpoint: String, arguments: [String: Value], failureContext: String) async throws -> CallTool.Result {
        do {
            let response: ASCCIWorkflowsResponse
            var query = listQuery(arguments)
            applyInclude(arguments, to: &query)
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCIWorkflowsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIWorkflowsResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.workflowIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: failureContext
            )
            var result = try validatedListResult(
                "workflows",
                response.data.map(formatWorkflow),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud \(failureContext)")
        }
    }

    private func listBuildRuns(endpoint: String, arguments: [String: Value], failureContext: String) async throws -> CallTool.Result {
        do {
            let response: ASCCIBuildRunsResponse
            var query = listQuery(arguments)
            try applyStringList(arguments["build_id"], field: "build_id", appleName: "filter[builds]", to: &query)
            try applyStringList(
                arguments["sort"],
                field: "sort",
                allowedValues: ["number", "-number"],
                appleName: "sort",
                to: &query
            )
            applyInclude(arguments, to: &query)
            try applyRelationshipLimit(
                arguments["builds_limit"],
                field: "builds_limit",
                appleName: "limit[builds]",
                to: &query
            )
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCIBuildRunsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIBuildRunsResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudRequestedRelationshipLimit(
                response.data.map { $0.relationships?.builds },
                query: query,
                appleName: "limit[builds]",
                relationshipName: "builds"
            )
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.buildRunIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: failureContext
            )
            var result = try validatedListResult(
                "buildRuns",
                response.data.map(formatBuildRun),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud \(failureContext)")
        }
    }

    private func listArtifacts(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCCIArtifactsResponse
            let query = listQuery(arguments)
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCIArtifactsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIArtifactsResponse.self)
            }
            try validateXcodeCloudResources(response.data)
            let result = try validatedListResult(
                "artifacts",
                response.data.map(formatArtifact),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            return MCPResult.jsonObject(
                result,
                explicitlyAllowedSensitivePaths: [MCPSensitiveValuePath("artifacts", "*", "downloadUrl")]
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud artifacts")
        }
    }

    private func listIssues(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCCIIssuesResponse
            let query = listQuery(arguments)
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCIIssuesResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIIssuesResponse.self)
            }
            try validateXcodeCloudResources(response.data)
            let result = try validatedListResult(
                "issues",
                response.data.map(formatIssue),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud issues")
        }
    }

    private func listTestResults(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCCITestResultsResponse
            let query = listQuery(arguments)
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCCITestResultsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCITestResultsResponse.self)
            }
            try validateXcodeCloudResources(response.data)
            let result = try validatedListResult(
                "testResults",
                response.data.map(formatTestResult),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud test results")
        }
    }

    private func listScmRepositories(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCScmRepositoriesResponse
            var query = listQuery(arguments)
            try applyStringList(arguments["repository_id"], field: "repository_id", appleName: "filter[id]", to: &query)
            applyInclude(arguments, to: &query)
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCScmRepositoriesResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCScmRepositoriesResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.repositoryIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: "SCM repositories"
            )
            var result = try validatedListResult(
                "repositories",
                response.data.map(formatScmRepository),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud SCM repositories")
        }
    }

    private func listScmGitReferences(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCScmGitReferencesResponse
            var query = listQuery(arguments)
            applyInclude(arguments, to: &query)
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCScmGitReferencesResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCScmGitReferencesResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.gitReferenceIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: "SCM git references"
            )
            var result = try validatedListResult(
                "gitReferences",
                response.data.map(formatScmGitReference),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud SCM git references")
        }
    }

    private func listScmPullRequests(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCScmPullRequestsResponse
            var query = listQuery(arguments)
            applyInclude(arguments, to: &query)
            let requestedNextURL = try paginationURL(from: arguments["next_url"])
            if let requestedNextURL {
                response = try await httpClient.getPage(
                    requestedNextURL,
                    scope: paginationScope(endpoint: endpoint, query: query),
                    as: ASCScmPullRequestsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCScmPullRequestsResponse.self)
            }

            try validateXcodeCloudResources(response.data)
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: arguments["include"],
                resourceTypesByInclude: Self.pullRequestIncludedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: response.data),
                context: "SCM pull requests"
            )
            var result = try validatedListResult(
                "pullRequests",
                response.data.map(formatScmPullRequest),
                links: response.links,
                meta: response.meta,
                endpoint: endpoint,
                query: query,
                requestedNextURL: requestedNextURL
            )
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list Xcode Cloud SCM pull requests")
        }
    }

    private func validateXcodeCloudArguments(_ arguments: [String: Value], allowed: Set<String>) throws {
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw XcodeCloudArgumentError("Unsupported parameter(s): \(unsupported.joined(separator: ", "))")
        }
    }

    private func requiredXcodeCloudIdentifier(_ field: String, from arguments: [String: Value]) throws -> String {
        guard let value = arguments[field]?.stringValue else {
            throw XcodeCloudArgumentError("Required parameter '\(field)' must be a string")
        }
        let encoded = try ASCPathSegment.encode(value, field: field)
        guard encoded == value else {
            throw XcodeCloudArgumentError("'\(field)' must be a canonical App Store Connect resource ID")
        }
        return value
    }

    private func optionalXcodeCloudIdentifier(_ field: String, from arguments: [String: Value]) throws -> String? {
        guard arguments[field] != nil else {
            return nil
        }
        return try requiredXcodeCloudIdentifier(field, from: arguments)
    }

    private func applyBuildIncludes(_ value: Value?, to query: inout [String: String]) throws -> Set<String> {
        guard let value else {
            return []
        }
        let values: [String]
        if let string = value.stringValue {
            values = [string]
        } else if let array = value.arrayValue,
                  !array.isEmpty,
                  array.allSatisfy({ $0.stringValue != nil }) {
            values = array.compactMap(\.stringValue)
        } else {
            throw XcodeCloudArgumentError("include must be a non-empty string or array of strings")
        }
        let allowed = Set([
            "preReleaseVersion", "individualTesters", "betaGroups", "betaBuildLocalizations",
            "appEncryptionDeclaration", "betaAppReviewSubmission", "app", "buildBetaDetail",
            "appStoreVersion", "icons", "buildBundles", "buildUpload"
        ])
        guard values.allSatisfy({ allowed.contains($0) }) else {
            throw XcodeCloudArgumentError("include contains an unsupported Xcode Cloud build relationship")
        }
        guard Set(values).count == values.count,
              values.allSatisfy({ !$0.contains(",") }) else {
            throw XcodeCloudArgumentError("include must contain unique values without commas")
        }
        query["include"] = values.joined(separator: ",")
        return Set(values)
    }

    private func applyBuildRelatedLimit(
        _ value: Value?,
        field: String,
        appleName: String,
        relationship: String,
        includes: Set<String>,
        to query: inout [String: String]
    ) throws {
        guard let value else {
            return
        }
        guard let limit = value.intValue, (1...50).contains(limit) else {
            throw XcodeCloudArgumentError("\(field) must be an integer from 1 through 50")
        }
        guard includes.contains(relationship) else {
            throw XcodeCloudArgumentError("\(field) requires include to contain '\(relationship)'")
        }
        query[appleName] = String(limit)
    }

    private func validateBuildRunStartDocumentSelf(_ value: String) throws {
        try validateXcodeCloudDocumentSelf(
            value,
            expectedPath: "/v1/ciBuildRuns",
            context: "Xcode Cloud build run start"
        )
    }

    private func validateBuildRunStartRequestedRelationships(
        _ buildRun: ASCCIBuildRun,
        workflowID: String?,
        sourceBranchOrTagID: String?,
        pullRequestID: String?
    ) throws {
        try validateBuildRunStartRequestedRelationship(
            buildRun.relationships?.workflow,
            requestedID: workflowID,
            name: "workflow"
        )
        try validateBuildRunStartRequestedRelationship(
            buildRun.relationships?.sourceBranchOrTag,
            requestedID: sourceBranchOrTagID,
            name: "sourceBranchOrTag"
        )
        try validateBuildRunStartRequestedRelationship(
            buildRun.relationships?.pullRequest,
            requestedID: pullRequestID,
            name: "pullRequest"
        )
    }

    private func validateBuildRunStartRequestedRelationship(
        _ relationship: ASCRelationship?,
        requestedID: String?,
        name: String
    ) throws {
        guard let requestedID, let returnedID = relationship?.data?.id else { return }
        guard returnedID == requestedID else {
            throw ASCError.parsing(
                "Xcode Cloud build run start returned \(name) outside the requested lineage"
            )
        }
    }

    func validateXcodeCloudBuild(
        _ build: ASCXcodeCloudBuild,
        expectedRelatedLimits: [String: Int] = [:]
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: build.type,
            id: build.id,
            expectedType: "builds",
            context: "Xcode Cloud build run builds response"
        )
        if let selfURL = build.links?.`self` {
            try validateXcodeCloudDocumentSelf(
                selfURL,
                expectedPath: "/v1/builds/\(try ASCPathSegment.encode(build.id))",
                context: "Xcode Cloud build resource"
            )
        }

        let relationships = build.relationships
        try validateXcodeCloudBuildRelationship(
            relationships?.preReleaseVersion,
            buildID: build.id,
            expectedType: "preReleaseVersions",
            name: "preReleaseVersion"
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.individualTesters,
            buildID: build.id,
            expectedType: "betaTesters",
            name: "individualTesters",
            expectedLimit: expectedRelatedLimits["individualTesters"]
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.betaGroups,
            buildID: build.id,
            expectedType: "betaGroups",
            name: "betaGroups",
            supportsRelated: false,
            expectedLimit: expectedRelatedLimits["betaGroups"]
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.betaBuildLocalizations,
            buildID: build.id,
            expectedType: "betaBuildLocalizations",
            name: "betaBuildLocalizations",
            expectedLimit: expectedRelatedLimits["betaBuildLocalizations"]
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.appEncryptionDeclaration,
            buildID: build.id,
            expectedType: "appEncryptionDeclarations",
            name: "appEncryptionDeclaration"
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.betaAppReviewSubmission,
            buildID: build.id,
            expectedType: "betaAppReviewSubmissions",
            name: "betaAppReviewSubmission"
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.app,
            buildID: build.id,
            expectedType: "apps",
            name: "app"
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.buildBetaDetail,
            buildID: build.id,
            expectedType: "buildBetaDetails",
            name: "buildBetaDetail"
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.appStoreVersion,
            buildID: build.id,
            expectedType: "appStoreVersions",
            name: "appStoreVersion"
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.icons,
            buildID: build.id,
            expectedType: "buildIcons",
            name: "icons",
            expectedLimit: expectedRelatedLimits["icons"]
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.buildBundles,
            buildID: build.id,
            expectedType: "buildBundles",
            name: "buildBundles",
            supportsRelationshipSelf: false,
            supportsRelated: false,
            expectedLimit: expectedRelatedLimits["buildBundles"]
        )
        try validateXcodeCloudBuildRelationship(
            relationships?.buildUpload,
            buildID: build.id,
            expectedType: "buildUploads",
            name: "buildUpload",
            supportsRelationshipSelf: false,
            supportsRelated: false
        )
        try validateXcodeCloudBuildLinksOnlyRelationship(
            relationships?.perfPowerMetrics,
            buildID: build.id,
            name: "perfPowerMetrics",
            supportsRelationshipSelf: false
        )
        try validateXcodeCloudBuildLinksOnlyRelationship(
            relationships?.diagnosticSignatures,
            buildID: build.id,
            name: "diagnosticSignatures",
            supportsRelationshipSelf: true
        )
    }

    private func validateXcodeCloudBuildRelationship(
        _ relationship: ASCRelationship?,
        buildID: String,
        expectedType: String,
        name: String,
        supportsRelationshipSelf: Bool = true,
        supportsRelated: Bool = true
    ) throws {
        if let identifier = relationship?.data {
            try validateXcodeCloudBuildRelationshipIdentifier(
                identifier,
                expectedType: expectedType,
                name: name
            )
        }
        try validateXcodeCloudBuildRelationshipLinks(
            relationship?.links,
            buildID: buildID,
            name: name,
            supportsRelationshipSelf: supportsRelationshipSelf,
            supportsRelated: supportsRelated
        )
    }

    private func validateXcodeCloudBuildRelationship(
        _ relationship: ASCRelationshipMultiple?,
        buildID: String,
        expectedType: String,
        name: String,
        supportsRelationshipSelf: Bool = true,
        supportsRelated: Bool = true,
        expectedLimit: Int? = nil
    ) throws {
        let dataCount = relationship?.data?.count ?? 0
        if let expectedLimit, dataCount > expectedLimit {
            throw ASCError.parsing(
                "Xcode Cloud build \(name) relationship returned more resources than the requested limit"
            )
        }
        if let meta = relationship?.meta {
            guard let paging = meta.paging, let limit = paging.limit, limit > 0 else {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) relationship meta must contain a positive paging.limit"
                )
            }
            if let expectedLimit, limit != expectedLimit {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) relationship meta.paging.limit does not match the requested limit"
                )
            }
            if dataCount > limit {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) relationship returned more resources than meta.paging.limit"
                )
            }
            if let total = paging.total, total < dataCount {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) relationship meta.paging.total is smaller than its data count"
                )
            }
            if let nextCursor = paging.nextCursor,
               nextCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) relationship meta.paging.nextCursor must not be empty"
                )
            }
        }
        var identities: Set<String> = []
        for identifier in relationship?.data ?? [] {
            try validateXcodeCloudBuildRelationshipIdentifier(
                identifier,
                expectedType: expectedType,
                name: name
            )
            guard identities.insert("\(identifier.type):\(identifier.id)").inserted else {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) relationship returned duplicate resource identifiers"
                )
            }
        }
        try validateXcodeCloudBuildRelationshipLinks(
            relationship?.links,
            buildID: buildID,
            name: name,
            supportsRelationshipSelf: supportsRelationshipSelf,
            supportsRelated: supportsRelated
        )
    }

    private func validateXcodeCloudBuildRelationshipIdentifier(
        _ identifier: ASCResourceIdentifier,
        expectedType: String,
        name: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: identifier.type,
            id: identifier.id,
            expectedType: expectedType,
            context: "Xcode Cloud build \(name) relationship"
        )
    }

    private func validateXcodeCloudBuildRelationshipLinks(
        _ links: ASCRelationshipLinks?,
        buildID: String,
        name: String,
        supportsRelationshipSelf: Bool,
        supportsRelated: Bool
    ) throws {
        guard let links else { return }
        if let selfURL = links.`self` {
            guard supportsRelationshipSelf else {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) returned links.self absent from the pinned schema"
                )
            }
            try validateXcodeCloudSingleDocument(
                selfURL: selfURL,
                endpoint: "/v1/builds/\(try ASCPathSegment.encode(buildID))/relationships/\(try ASCPathSegment.encode(name))"
            )
        }
        if let relatedURL = links.related {
            guard supportsRelated else {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) returned links.related absent from the pinned schema"
                )
            }
            try validateXcodeCloudSingleDocument(
                selfURL: relatedURL,
                endpoint: "/v1/builds/\(try ASCPathSegment.encode(buildID))/\(try ASCPathSegment.encode(name))"
            )
        }
    }

    private func validateXcodeCloudBuildLinksOnlyRelationship(
        _ relationship: ASCXcodeCloudLinksOnlyRelationship?,
        buildID: String,
        name: String,
        supportsRelationshipSelf: Bool
    ) throws {
        guard let links = relationship?.links else {
            return
        }
        if let selfURL = links.`self` {
            guard supportsRelationshipSelf else {
                throw ASCError.parsing(
                    "Xcode Cloud build \(name) returned an unverifiable relationship links.self"
                )
            }
            try validateXcodeCloudSingleDocument(
                selfURL: selfURL,
                endpoint: "/v1/builds/\(try ASCPathSegment.encode(buildID))/relationships/\(try ASCPathSegment.encode(name))"
            )
        }
        if let relatedURL = links.related {
            try validateXcodeCloudSingleDocument(
                selfURL: relatedURL,
                endpoint: "/v1/builds/\(try ASCPathSegment.encode(buildID))/\(try ASCPathSegment.encode(name))"
            )
        }
    }

    private func validateXcodeCloudDocumentSelf(
        _ value: String,
        expectedPath: String,
        context: String
    ) throws {
        do {
            _ = try httpClient.validatedScopedLink(
                value,
                scope: PaginationScope(path: expectedPath, allowedParameters: [])
            )
        } catch {
            throw ASCError.parsing("Apple returned an invalid required links.self for \(context)")
        }
    }

    private func buildRunStartFailure(
        _ error: Error,
        phase: ASCNonIdempotentWriteFailurePhase,
        workflowID: String?,
        sourceBuildRunID: String?,
        sourceBranchOrTagID: String?,
        pullRequestID: String?,
        clean: Bool?
    ) -> CallTool.Result {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: phase)
        var identifiers: [String: Value] = [:]
        if let workflowID {
            identifiers["workflow_id"] = .string(workflowID)
        }
        if let sourceBuildRunID {
            identifiers["build_run_id"] = .string(sourceBuildRunID)
        }
        if let sourceBranchOrTagID {
            identifiers["source_branch_or_tag_id"] = .string(sourceBranchOrTagID)
        }
        if let pullRequestID {
            identifiers["pull_request_id"] = .string(pullRequestID)
        }
        if let clean {
            identifiers["clean"] = .bool(clean)
        }

        var details = identifiers
        details["operation"] = .string("start_build_run")
        details["write_outcome"] = .string(disposition.rawValue)
        details["operationCommitState"] = .string(disposition.rawValue)
        details["retrySafe"] = .bool(false)
        details["recovered"] = .bool(false)
        details["cause"] = xcodeCloudFailureCause(error, phase: phase)

        if disposition != .rejected {
            details["inspectionRequired"] = .bool(true)
            if disposition == .outcomeUnknown {
                details["outcomeUnknown"] = .bool(true)
            } else {
                details["operationCommitted"] = .bool(true)
                details["outcomeUnknown"] = .bool(false)
            }
            details["recovery_tools"] = .array([
                .string("xcode_cloud_workflow_build_runs_list"),
                .string("xcode_cloud_build_runs_get")
            ])
            details["recovery"] = buildRunStartRecovery(
                workflowID: workflowID,
                sourceBuildRunID: sourceBuildRunID,
                identifiers: identifiers
            )
        }

        return MCPResult.error(
            "Failed to start Xcode Cloud build run: \(error.localizedDescription)",
            details: .object(details)
        )
    }

    private func buildRunStartRecovery(
        workflowID: String?,
        sourceBuildRunID: String?,
        identifiers: [String: Value]
    ) -> Value {
        let inspectCandidate: Value = .object([
            "tool": .string("xcode_cloud_build_runs_get"),
            "id_argument": .string("build_run_id"),
            "id_source": .string("/buildRuns/*/id"),
            "after": .string("list_candidates")
        ])
        if let workflowID {
            return .object([
                "list_candidates": .object([
                    "tool": .string("xcode_cloud_workflow_build_runs_list"),
                    "arguments": .object(["workflow_id": .string(workflowID)]),
                    "continue_with_next_url": .bool(true)
                ]),
                "match_requested": .object([
                    "identifiers": .object(identifiers),
                    "fields": .array([
                        .string("workflowId"), .string("sourceBranchOrTagId"),
                        .string("pullRequestId"), .string("createdDate"), .string("startReason")
                    ])
                ]),
                "inspect_candidate": inspectCandidate,
                "instruction": .string(
                    "List every build run for the exact workflow, inspect plausible candidates with xcode_cloud_build_runs_get, and do not retry until the existing-run outcome is resolved. This error does not prove that a new run was recovered."
                )
            ])
        }

        guard let sourceBuildRunID else {
            return .object([
                "instruction": .string(
                    "The original run selector is unavailable. Do not retry until the Xcode Cloud workflow and its recent build runs have been inspected manually; this error does not claim successful recovery."
                )
            ])
        }
        return .object([
            "inspect_source_run": .object([
                "tool": .string("xcode_cloud_build_runs_get"),
                "arguments": .object(["build_run_id": .string(sourceBuildRunID)]),
                "workflow_id_source": .string("/buildRun/workflowId")
            ]),
            "list_candidates": .object([
                "tool": .string("xcode_cloud_workflow_build_runs_list"),
                "arguments_from": .object(["workflow_id": .string("/buildRun/workflowId")]),
                "continue_with_next_url": .bool(true),
                "after": .string("inspect_source_run")
            ]),
            "match_requested": .object([
                "identifiers": .object(identifiers),
                "fields": .array([
                    .string("workflowId"), .string("startReason"), .string("createdDate"),
                    .string("sourceCommit"), .string("destinationCommit")
                ])
            ]),
            "inspect_candidate": inspectCandidate,
            "instruction": .string(
                "First inspect the source build run to obtain its workflowId. Then list every run for that workflow and inspect plausible MANUAL_REBUILD candidates. Do not treat the source run as the newly created run and do not retry until the outcome is resolved; this error does not claim successful recovery."
            )
        ])
    }

    private func xcodeCloudFailureCause(
        _ error: Error,
        phase: ASCNonIdempotentWriteFailurePhase
    ) -> Value {
        if let ascError = error as? ASCError {
            return ascError.structuredValue
        }
        if error is CancellationError {
            return .object([
                "type": .string("cancellation"),
                "message": .string("The request was cancelled before its write outcome was confirmed")
            ])
        }
        let type = phase == .request ? "request" : "response_validation"
        return .object([
            "type": .string(type),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
    }

    private func listQuery(_ arguments: [String: Value]) -> [String: String] {
        let limit = arguments["limit"]?.intValue ?? 25
        return ["limit": String(limit)]
    }

    private func paginationScope(endpoint: String, query: [String: String]) -> PaginationScope {
        PaginationScope(
            path: endpoint,
            requiredParameters: query,
            allowedParameters: Set(query.keys).union(["cursor"]),
            requiredNonEmptyParameters: ["cursor"]
        )
    }

    private func applyInclude(_ arguments: [String: Value], to query: inout [String: String]) {
        if let include = commaSeparated(argument: arguments["include"]), !include.isEmpty {
            query["include"] = include
        }
    }

    private func commaSeparated(argument: Value?) -> String? {
        if let value = argument?.stringValue {
            return value
        }
        return argument?.arrayValue?.compactMap(\.stringValue).joined(separator: ",")
    }

    private func applyStringList(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil,
        appleName: String,
        to query: inout [String: String]
    ) throws {
        guard let value else {
            return
        }
        let values: [String]
        if let string = value.stringValue {
            values = [string]
        } else if let array = value.arrayValue,
                  !array.isEmpty,
                  array.allSatisfy({ $0.stringValue != nil }) {
            values = array.compactMap(\.stringValue)
        } else {
            throw XcodeCloudArgumentError("\(field) must be a non-empty string or array of strings")
        }
        guard values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw XcodeCloudArgumentError("\(field) must contain only non-empty strings")
        }
        guard Set(values).count == values.count,
              values.allSatisfy({ !$0.contains(",") }) else {
            throw XcodeCloudArgumentError("\(field) must contain unique values without commas")
        }
        if let allowedValues,
           let invalid = values.first(where: { !allowedValues.contains($0) }) {
            throw XcodeCloudArgumentError("\(field) contains unsupported value '\(invalid)'")
        }
        query[appleName] = values.joined(separator: ",")
    }

    private func applyRelationshipLimit(
        _ value: Value?,
        field: String,
        appleName: String,
        to query: inout [String: String]
    ) throws {
        guard let value else { return }
        guard let limit = value.intValue, (1...50).contains(limit) else {
            throw XcodeCloudArgumentError("\(field) must be an integer in 1...50")
        }
        query[appleName] = String(limit)
    }

    private func applyBooleanList(
        _ value: Value?,
        field: String,
        appleName: String,
        to query: inout [String: String]
    ) throws {
        guard let value else {
            return
        }
        let values: [Bool]
        if let boolean = value.boolValue {
            values = [boolean]
        } else if let array = value.arrayValue,
                  !array.isEmpty,
                  array.allSatisfy({ $0.boolValue != nil }) {
            values = array.compactMap(\.boolValue)
        } else {
            throw XcodeCloudArgumentError("\(field) must be a boolean or non-empty array of booleans")
        }
        guard Set(values).count == values.count else {
            throw XcodeCloudArgumentError("\(field) must contain unique values")
        }
        query[appleName] = values.map { $0 ? "true" : "false" }.joined(separator: ",")
    }

    private func validatedListResult(
        _ key: String,
        _ values: [[String: Any]],
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        endpoint: String,
        query: [String: String],
        requestedNextURL: String?
    ) throws -> [String: Any] {
        let page = try validateXcodeCloudPage(
            links: links,
            meta: meta,
            endpoint: endpoint,
            query: query,
            requestedNextURL: requestedNextURL,
            count: values.count
        )
        var result: [String: Any] = [
            "success": true,
            key: values,
            "count": values.count,
            "self_url": page.selfURL
        ]
        if let firstURL = page.firstURL {
            result["first_url"] = firstURL
        }
        if let nextURL = page.nextURL {
            result["next_url"] = nextURL
        }
        if let total = page.total {
            result["total"] = total
        }
        return result
    }

    private func validateXcodeCloudResources<Resource: ASCXcodeCloudResourceContract>(
        _ resources: [Resource]
    ) throws {
        var identities: Set<String> = []
        for resource in resources {
            guard identities.insert("\(resource.type):\(resource.id)").inserted else {
                throw ASCError.parsing("Xcode Cloud response returned duplicate data resources")
            }
            try validateXcodeCloudResourceSelf(resource.links?.`self`, type: resource.type, id: resource.id)
            try resource.validateXcodeCloudRelationships()
            try validateXcodeCloudRelationshipLinks(for: resource)
        }
    }

    private func validateXcodeCloudSingle<Resource: ASCXcodeCloudResourceContract>(
        _ response: ASCXcodeCloudSingleResponse<Resource>,
        endpoint: String,
        query: [String: String] = [:],
        requestedInclude: Value? = nil,
        includedTypes: [String: Set<String>] = [:],
        context: String
    ) throws {
        try validateXcodeCloudSingleDocument(
            selfURL: response.links.`self`,
            endpoint: endpoint,
            query: query
        )
        try validateXcodeCloudResourceSelf(
            response.data.links?.`self`,
            type: response.data.type,
            id: response.data.id
        )
        try response.data.validateXcodeCloudRelationships()
        try validateXcodeCloudRelationshipLinks(for: response.data)
        if Resource.permitsIncludedResources {
            try validateXcodeCloudIncluded(
                response.included,
                requestedValue: requestedInclude,
                resourceTypesByInclude: includedTypes,
                linkedIdentitiesByInclude: xcodeCloudIncludedLineage(for: [response.data]),
                context: context
            )
        }
    }

    private static var productIncludedTypes: [String: Set<String>] {
        [
            "app": ["apps"],
            "bundleId": ["bundleIds"],
            "primaryRepositories": ["scmRepositories"]
        ]
    }

    private static var workflowIncludedTypes: [String: Set<String>] {
        [
            "product": ["ciProducts"],
            "repository": ["scmRepositories"],
            "xcodeVersion": ["ciXcodeVersions"],
            "macOsVersion": ["ciMacOsVersions"]
        ]
    }

    private static var buildRunIncludedTypes: [String: Set<String>] {
        [
            "builds": ["builds"],
            "workflow": ["ciWorkflows"],
            "product": ["ciProducts"],
            "sourceBranchOrTag": ["scmGitReferences"],
            "destinationBranch": ["scmGitReferences"],
            "pullRequest": ["scmPullRequests"]
        ]
    }

    private static var buildIncludedTypes: [String: Set<String>] {
        [
            "preReleaseVersion": ["preReleaseVersions"],
            "individualTesters": ["betaTesters"],
            "betaGroups": ["betaGroups"],
            "betaBuildLocalizations": ["betaBuildLocalizations"],
            "appEncryptionDeclaration": ["appEncryptionDeclarations"],
            "betaAppReviewSubmission": ["betaAppReviewSubmissions"],
            "app": ["apps"],
            "buildBetaDetail": ["buildBetaDetails"],
            "appStoreVersion": ["appStoreVersions"],
            "icons": ["buildIcons"],
            "buildBundles": ["buildBundles"],
            "buildUpload": ["buildUploads"]
        ]
    }

    private static var actionIncludedTypes: [String: Set<String>] {
        ["buildRun": ["ciBuildRuns"]]
    }

    private static var xcodeVersionIncludedTypes: [String: Set<String>] {
        ["macOsVersions": ["ciMacOsVersions"]]
    }

    private static var macOSVersionIncludedTypes: [String: Set<String>] {
        ["xcodeVersions": ["ciXcodeVersions"]]
    }

    private static var repositoryIncludedTypes: [String: Set<String>] {
        [
            "scmProvider": ["scmProviders"],
            "defaultBranch": ["scmGitReferences"]
        ]
    }

    private static var gitReferenceIncludedTypes: [String: Set<String>] {
        ["repository": ["scmRepositories"]]
    }

    private static var pullRequestIncludedTypes: [String: Set<String>] {
        ["repository": ["scmRepositories"]]
    }

    private func appendIncluded(_ included: [JSONValue]?, to result: inout [String: Any]) {
        if let included, !included.isEmpty {
            result["included"] = included.map(\.asAny)
        }
    }

    private func relationshipID(_ relationship: ASCRelationship?) -> Any {
        relationship?.data?.id ?? NSNull()
    }

    private func relationshipIDs(_ relationship: ASCRelationshipMultiple?) -> Any {
        relationship?.data?.map(\.id) ?? NSNull()
    }

    private func relationshipIDsMetadata(_ relationship: ASCRelationshipMultiple?) -> Any {
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

    private func relationshipURL(_ links: ASCRelationshipLinks?) -> Any {
        links?.related ?? NSNull()
    }

    private func relationshipSelfURL(_ links: ASCRelationshipLinks?) -> Any {
        links?.`self` ?? NSNull()
    }

    private func formatProduct(_ product: ASCCIProduct) -> [String: Any] {
        [
            "id": product.id,
            "type": product.type,
            "selfUrl": (product.links?.`self`).jsonSafe,
            "name": (product.attributes?.name).jsonSafe,
            "createdDate": (product.attributes?.createdDate).jsonSafe,
            "productType": (product.attributes?.productType).jsonSafe,
            "appId": relationshipID(product.relationships?.app),
            "appUrl": relationshipURL(product.relationships?.app?.links),
            "appRelationshipUrl": relationshipSelfURL(product.relationships?.app?.links),
            "bundleIdResourceId": relationshipID(product.relationships?.bundleId),
            "workflowIds": NSNull(),
            "workflowsUrl": relationshipURL(product.relationships?.workflows?.links),
            "workflowsRelationshipUrl": relationshipSelfURL(product.relationships?.workflows?.links),
            "primaryRepositoryIds": relationshipIDs(product.relationships?.primaryRepositories),
            "primaryRepositoryIdsMeta": relationshipIDsMetadata(product.relationships?.primaryRepositories),
            "primaryRepositoriesUrl": relationshipURL(product.relationships?.primaryRepositories?.links),
            "primaryRepositoriesRelationshipUrl": relationshipSelfURL(product.relationships?.primaryRepositories?.links),
            "additionalRepositoryIds": NSNull(),
            "additionalRepositoriesUrl": relationshipURL(product.relationships?.additionalRepositories?.links),
            "additionalRepositoriesRelationshipUrl": relationshipSelfURL(product.relationships?.additionalRepositories?.links),
            "buildRunIds": NSNull(),
            "buildRunsUrl": relationshipURL(product.relationships?.buildRuns?.links),
            "buildRunsRelationshipUrl": relationshipSelfURL(product.relationships?.buildRuns?.links)
        ]
    }

    private func formatWorkflow(_ workflow: ASCCIWorkflow) -> [String: Any] {
        let attrs = workflow.attributes
        return [
            "id": workflow.id,
            "type": workflow.type,
            "selfUrl": (workflow.links?.`self`).jsonSafe,
            "name": (attrs?.name).jsonSafe,
            "description": (attrs?.description).jsonSafe,
            "isEnabled": (attrs?.isEnabled).jsonSafe,
            "isLockedForEditing": (attrs?.isLockedForEditing).jsonSafe,
            "clean": (attrs?.clean).jsonSafe,
            "containerFilePath": (attrs?.containerFilePath).jsonSafe,
            "lastModifiedDate": (attrs?.lastModifiedDate).jsonSafe,
            "actions": attrs?.actions?.map(\.asAny) ?? [],
            "actionsPresent": attrs?.actions != nil,
            "startConditions": [
                "branch": attrs?.branchStartCondition?.asAny ?? NSNull(),
                "tag": attrs?.tagStartCondition?.asAny ?? NSNull(),
                "pullRequest": attrs?.pullRequestStartCondition?.asAny ?? NSNull(),
                "scheduled": attrs?.scheduledStartCondition?.asAny ?? NSNull(),
                "manualBranch": attrs?.manualBranchStartCondition?.asAny ?? NSNull(),
                "manualTag": attrs?.manualTagStartCondition?.asAny ?? NSNull(),
                "manualPullRequest": attrs?.manualPullRequestStartCondition?.asAny ?? NSNull()
            ],
            "productId": relationshipID(workflow.relationships?.product),
            "repositoryId": relationshipID(workflow.relationships?.repository),
            "repositoryUrl": relationshipURL(workflow.relationships?.repository?.links),
            "repositoryRelationshipUrl": relationshipSelfURL(workflow.relationships?.repository?.links),
            "xcodeVersionId": relationshipID(workflow.relationships?.xcodeVersion),
            "macOSVersionId": relationshipID(workflow.relationships?.macOsVersion),
            "buildRunIds": NSNull(),
            "buildRunsUrl": relationshipURL(workflow.relationships?.buildRuns?.links),
            "buildRunsRelationshipUrl": relationshipSelfURL(workflow.relationships?.buildRuns?.links)
        ]
    }

    private func formatBuildRun(_ buildRun: ASCCIBuildRun) -> [String: Any] {
        let attrs = buildRun.attributes
        return [
            "id": buildRun.id,
            "type": buildRun.type,
            "selfUrl": (buildRun.links?.`self`).jsonSafe,
            "number": (attrs?.number).jsonSafe,
            "createdDate": (attrs?.createdDate).jsonSafe,
            "startedDate": (attrs?.startedDate).jsonSafe,
            "finishedDate": (attrs?.finishedDate).jsonSafe,
            "sourceCommit": formatCommit(attrs?.sourceCommit),
            "destinationCommit": formatCommit(attrs?.destinationCommit),
            "isPullRequestBuild": (attrs?.isPullRequestBuild).jsonSafe,
            "issueCounts": formatIssueCounts(attrs?.issueCounts),
            "executionProgress": (attrs?.executionProgress).jsonSafe,
            "completionStatus": (attrs?.completionStatus).jsonSafe,
            "startReason": (attrs?.startReason).jsonSafe,
            "cancelReason": (attrs?.cancelReason).jsonSafe,
            "buildIds": relationshipIDs(buildRun.relationships?.builds),
            "buildIdsMeta": relationshipIDsMetadata(buildRun.relationships?.builds),
            "buildsUrl": relationshipURL(buildRun.relationships?.builds?.links),
            "buildsRelationshipUrl": relationshipSelfURL(buildRun.relationships?.builds?.links),
            "workflowId": relationshipID(buildRun.relationships?.workflow),
            "productId": relationshipID(buildRun.relationships?.product),
            "sourceBranchOrTagId": relationshipID(buildRun.relationships?.sourceBranchOrTag),
            "destinationBranchId": relationshipID(buildRun.relationships?.destinationBranch),
            "actionIds": NSNull(),
            "actionsUrl": relationshipURL(buildRun.relationships?.actions?.links),
            "actionsRelationshipUrl": relationshipSelfURL(buildRun.relationships?.actions?.links),
            "pullRequestId": relationshipID(buildRun.relationships?.pullRequest)
        ]
    }

    private func formatAction(_ action: ASCCIBuildAction) -> [String: Any] {
        let attrs = action.attributes
        return [
            "id": action.id,
            "type": action.type,
            "selfUrl": (action.links?.`self`).jsonSafe,
            "name": (attrs?.name).jsonSafe,
            "actionType": (attrs?.actionType).jsonSafe,
            "startedDate": (attrs?.startedDate).jsonSafe,
            "finishedDate": (attrs?.finishedDate).jsonSafe,
            "issueCounts": formatIssueCounts(attrs?.issueCounts),
            "executionProgress": (attrs?.executionProgress).jsonSafe,
            "completionStatus": (attrs?.completionStatus).jsonSafe,
            "isRequiredToPass": (attrs?.isRequiredToPass).jsonSafe,
            "buildRunId": relationshipID(action.relationships?.buildRun),
            "buildRunUrl": relationshipURL(action.relationships?.buildRun?.links),
            "buildRunRelationshipUrl": relationshipSelfURL(action.relationships?.buildRun?.links),
            "artifactIds": NSNull(),
            "artifactsUrl": relationshipURL(action.relationships?.artifacts?.links),
            "artifactsRelationshipUrl": relationshipSelfURL(action.relationships?.artifacts?.links),
            "issueIds": NSNull(),
            "issuesUrl": relationshipURL(action.relationships?.issues?.links),
            "issuesRelationshipUrl": relationshipSelfURL(action.relationships?.issues?.links),
            "testResultIds": NSNull(),
            "testResultsUrl": relationshipURL(action.relationships?.testResults?.links),
            "testResultsRelationshipUrl": relationshipSelfURL(action.relationships?.testResults?.links)
        ]
    }

    private func formatArtifact(_ artifact: ASCCIArtifact) -> [String: Any] {
        [
            "id": artifact.id,
            "type": artifact.type,
            "selfUrl": (artifact.links?.`self`).jsonSafe,
            "fileType": (artifact.attributes?.fileType).jsonSafe,
            "fileName": (artifact.attributes?.fileName).jsonSafe,
            "fileSize": (artifact.attributes?.fileSize).jsonSafe,
            "downloadUrl": (artifact.attributes?.downloadUrl).jsonSafe
        ]
    }

    private func formatIssue(_ issue: ASCCIIssue) -> [String: Any] {
        [
            "id": issue.id,
            "type": issue.type,
            "selfUrl": (issue.links?.`self`).jsonSafe,
            "category": (issue.attributes?.category).jsonSafe,
            "issueType": (issue.attributes?.issueType).jsonSafe,
            "message": (issue.attributes?.message).jsonSafe,
            "fileSource": formatFileSource(issue.attributes?.fileSource)
        ]
    }

    private func formatTestResult(_ result: ASCCITestResult) -> [String: Any] {
        [
            "id": result.id,
            "type": result.type,
            "selfUrl": (result.links?.`self`).jsonSafe,
            "name": (result.attributes?.name).jsonSafe,
            "className": (result.attributes?.className).jsonSafe,
            "status": (result.attributes?.status).jsonSafe,
            "message": (result.attributes?.message).jsonSafe,
            "fileSource": formatFileSource(result.attributes?.fileSource),
            "destinationTestResults": result.attributes?.destinationTestResults?.map(formatDestinationTestResult) ?? [],
            "destinationTestResultsPresent": result.attributes?.destinationTestResults != nil
        ]
    }

    private func formatXcodeVersion(_ version: ASCCIXcodeVersion) -> [String: Any] {
        [
            "id": version.id,
            "type": version.type,
            "selfUrl": (version.links?.`self`).jsonSafe,
            "version": (version.attributes?.version).jsonSafe,
            "name": (version.attributes?.name).jsonSafe,
            "testDestinations": version.attributes?.testDestinations?.map(formatTestDestination) ?? [],
            "testDestinationsPresent": version.attributes?.testDestinations != nil,
            "macOSVersionIds": relationshipIDs(version.relationships?.macOsVersions),
            "macOSVersionIdsMeta": relationshipIDsMetadata(version.relationships?.macOsVersions),
            "macOSVersionsUrl": relationshipURL(version.relationships?.macOsVersions?.links),
            "macOSVersionsRelationshipUrl": relationshipSelfURL(version.relationships?.macOsVersions?.links)
        ]
    }

    private func formatMacOSVersion(_ version: ASCCIMacOSVersion) -> [String: Any] {
        [
            "id": version.id,
            "type": version.type,
            "selfUrl": (version.links?.`self`).jsonSafe,
            "version": (version.attributes?.version).jsonSafe,
            "name": (version.attributes?.name).jsonSafe,
            "xcodeVersionIds": relationshipIDs(version.relationships?.xcodeVersions),
            "xcodeVersionIdsMeta": relationshipIDsMetadata(version.relationships?.xcodeVersions),
            "xcodeVersionsUrl": relationshipURL(version.relationships?.xcodeVersions?.links),
            "xcodeVersionsRelationshipUrl": relationshipSelfURL(version.relationships?.xcodeVersions?.links)
        ]
    }

    private func formatScmProvider(_ provider: ASCScmProvider) -> [String: Any] {
        let providerType = provider.attributes?.scmProviderType
        return [
            "id": provider.id,
            "type": provider.type,
            "selfUrl": (provider.links?.`self`).jsonSafe,
            "scmProviderType": (providerType?.kind).jsonSafe,
            "scmProviderDisplayName": (providerType?.displayName).jsonSafe,
            "isOnPremise": (providerType?.isOnPremise).jsonSafe,
            "url": (provider.attributes?.url).jsonSafe,
            "repositoryIds": NSNull(),
            "repositoriesUrl": relationshipURL(provider.relationships?.repositories?.links),
            "repositoriesRelationshipUrl": relationshipSelfURL(provider.relationships?.repositories?.links)
        ]
    }

    private func formatScmRepository(_ repository: ASCScmRepository) -> [String: Any] {
        [
            "id": repository.id,
            "type": repository.type,
            "selfUrl": (repository.links?.`self`).jsonSafe,
            "lastAccessedDate": (repository.attributes?.lastAccessedDate).jsonSafe,
            "httpCloneUrl": (repository.attributes?.httpCloneUrl).jsonSafe,
            "sshCloneUrl": (repository.attributes?.sshCloneUrl).jsonSafe,
            "ownerName": (repository.attributes?.ownerName).jsonSafe,
            "repositoryName": (repository.attributes?.repositoryName).jsonSafe,
            "providerId": relationshipID(repository.relationships?.scmProvider),
            "defaultBranchId": relationshipID(repository.relationships?.defaultBranch),
            "gitReferenceIds": NSNull(),
            "gitReferencesUrl": relationshipURL(repository.relationships?.gitReferences?.links),
            "gitReferencesRelationshipUrl": relationshipSelfURL(repository.relationships?.gitReferences?.links),
            "pullRequestIds": NSNull(),
            "pullRequestsUrl": relationshipURL(repository.relationships?.pullRequests?.links),
            "pullRequestsRelationshipUrl": relationshipSelfURL(repository.relationships?.pullRequests?.links)
        ]
    }

    private func formatScmGitReference(_ reference: ASCScmGitReference) -> [String: Any] {
        [
            "id": reference.id,
            "type": reference.type,
            "selfUrl": (reference.links?.`self`).jsonSafe,
            "name": (reference.attributes?.name).jsonSafe,
            "canonicalName": (reference.attributes?.canonicalName).jsonSafe,
            "isDeleted": (reference.attributes?.isDeleted).jsonSafe,
            "kind": (reference.attributes?.kind).jsonSafe,
            "repositoryId": relationshipID(reference.relationships?.repository)
        ]
    }

    private func formatScmPullRequest(_ pullRequest: ASCScmPullRequest) -> [String: Any] {
        [
            "id": pullRequest.id,
            "type": pullRequest.type,
            "selfUrl": (pullRequest.links?.`self`).jsonSafe,
            "title": (pullRequest.attributes?.title).jsonSafe,
            "number": (pullRequest.attributes?.number).jsonSafe,
            "webUrl": (pullRequest.attributes?.webUrl).jsonSafe,
            "sourceRepositoryOwner": (pullRequest.attributes?.sourceRepositoryOwner).jsonSafe,
            "sourceRepositoryName": (pullRequest.attributes?.sourceRepositoryName).jsonSafe,
            "sourceBranchName": (pullRequest.attributes?.sourceBranchName).jsonSafe,
            "destinationRepositoryOwner": (pullRequest.attributes?.destinationRepositoryOwner).jsonSafe,
            "destinationRepositoryName": (pullRequest.attributes?.destinationRepositoryName).jsonSafe,
            "destinationBranchName": (pullRequest.attributes?.destinationBranchName).jsonSafe,
            "isClosed": (pullRequest.attributes?.isClosed).jsonSafe,
            "isCrossRepository": (pullRequest.attributes?.isCrossRepository).jsonSafe,
            "repositoryId": relationshipID(pullRequest.relationships?.repository)
        ]
    }

    private func formatCommit(_ commit: ASCCIBuildRun.Commit?) -> Any {
        guard let commit else {
            return NSNull()
        }
        return [
            "commitSha": (commit.commitSha).jsonSafe,
            "message": (commit.message).jsonSafe,
            "author": formatGitUser(commit.author),
            "committer": formatGitUser(commit.committer),
            "webUrl": (commit.webUrl).jsonSafe
        ]
    }

    private func formatGitUser(_ user: ASCCIBuildRun.GitUser?) -> Any {
        guard let user else {
            return NSNull()
        }
        return [
            "displayName": (user.displayName).jsonSafe,
            "avatarUrl": (user.avatarUrl).jsonSafe
        ]
    }

    private func formatIssueCounts(_ counts: ASCCIBuildRun.IssueCounts?) -> Any {
        guard let counts else {
            return NSNull()
        }
        return [
            "analyzerWarnings": (counts.analyzerWarnings).jsonSafe,
            "errors": (counts.errors).jsonSafe,
            "testFailures": (counts.testFailures).jsonSafe,
            "warnings": (counts.warnings).jsonSafe
        ]
    }

    private func formatFileSource(_ source: ASCCIIssue.FileSource?) -> Any {
        guard let source else {
            return NSNull()
        }
        return [
            "path": (source.path).jsonSafe,
            "lineNumber": (source.lineNumber).jsonSafe
        ]
    }

    private func formatDestinationTestResult(_ result: ASCCITestResult.DestinationTestResult) -> [String: Any] {
        [
            "uuid": (result.uuid).jsonSafe,
            "deviceName": (result.deviceName).jsonSafe,
            "osVersion": (result.osVersion).jsonSafe,
            "status": (result.status).jsonSafe,
            "duration": (result.duration).jsonSafe
        ]
    }

    private func formatTestDestination(_ destination: ASCCIXcodeVersion.TestDestination) -> [String: Any] {
        [
            "deviceTypeName": (destination.deviceTypeName).jsonSafe,
            "deviceTypeIdentifier": (destination.deviceTypeIdentifier).jsonSafe,
            "kind": (destination.kind).jsonSafe,
            "availableRuntimes": destination.availableRuntimes?.map {
                [
                    "runtimeName": ($0.runtimeName).jsonSafe,
                    "runtimeIdentifier": ($0.runtimeIdentifier).jsonSafe
                ]
            } ?? [],
            "availableRuntimesPresent": destination.availableRuntimes != nil
        ]
    }

    private func formatASCBuild(_ build: ASCXcodeCloudBuild) -> [String: Any] {
        let attributes = build.attributes
        let relationships = build.relationships
        return [
            "id": build.id,
            "type": build.type,
            "selfUrl": (build.links?.`self`).jsonSafe,
            "version": (attributes?.version).jsonSafe,
            "uploadedDate": (attributes?.uploadedDate).jsonSafe,
            "expirationDate": (attributes?.expirationDate).jsonSafe,
            "expired": (attributes?.expired).jsonSafe,
            "minOsVersion": (attributes?.minOsVersion).jsonSafe,
            "lsMinimumSystemVersion": (attributes?.lsMinimumSystemVersion).jsonSafe,
            "computedMinMacOsVersion": (attributes?.computedMinMacOsVersion).jsonSafe,
            "computedMinVisionOsVersion": (attributes?.computedMinVisionOsVersion).jsonSafe,
            "iconAssetToken": formatBuildIconAsset(attributes?.iconAssetToken),
            "processingState": (attributes?.processingState).jsonSafe,
            "buildAudienceType": (attributes?.buildAudienceType).jsonSafe,
            "usesNonExemptEncryption": (attributes?.usesNonExemptEncryption).jsonSafe,
            "preReleaseVersionId": relationshipID(relationships?.preReleaseVersion),
            "preReleaseVersionUrl": relationshipURL(relationships?.preReleaseVersion?.links),
            "preReleaseVersionRelationshipUrl": relationshipSelfURL(relationships?.preReleaseVersion?.links),
            "individualTesterIds": relationshipIDs(relationships?.individualTesters),
            "individualTesterIdsMeta": relationshipIDsMetadata(relationships?.individualTesters),
            "individualTestersUrl": relationshipURL(relationships?.individualTesters?.links),
            "individualTestersRelationshipUrl": relationshipSelfURL(relationships?.individualTesters?.links),
            "betaGroupIds": relationshipIDs(relationships?.betaGroups),
            "betaGroupIdsMeta": relationshipIDsMetadata(relationships?.betaGroups),
            "betaGroupsUrl": relationshipURL(relationships?.betaGroups?.links),
            "betaGroupsRelationshipUrl": relationshipSelfURL(relationships?.betaGroups?.links),
            "betaBuildLocalizationIds": relationshipIDs(relationships?.betaBuildLocalizations),
            "betaBuildLocalizationIdsMeta": relationshipIDsMetadata(relationships?.betaBuildLocalizations),
            "betaBuildLocalizationsUrl": relationshipURL(relationships?.betaBuildLocalizations?.links),
            "betaBuildLocalizationsRelationshipUrl": relationshipSelfURL(relationships?.betaBuildLocalizations?.links),
            "appEncryptionDeclarationId": relationshipID(relationships?.appEncryptionDeclaration),
            "appEncryptionDeclarationUrl": relationshipURL(relationships?.appEncryptionDeclaration?.links),
            "appEncryptionDeclarationRelationshipUrl": relationshipSelfURL(relationships?.appEncryptionDeclaration?.links),
            "betaAppReviewSubmissionId": relationshipID(relationships?.betaAppReviewSubmission),
            "betaAppReviewSubmissionUrl": relationshipURL(relationships?.betaAppReviewSubmission?.links),
            "betaAppReviewSubmissionRelationshipUrl": relationshipSelfURL(relationships?.betaAppReviewSubmission?.links),
            "appId": relationshipID(relationships?.app),
            "appUrl": relationshipURL(relationships?.app?.links),
            "appRelationshipUrl": relationshipSelfURL(relationships?.app?.links),
            "buildBetaDetailId": relationshipID(relationships?.buildBetaDetail),
            "buildBetaDetailUrl": relationshipURL(relationships?.buildBetaDetail?.links),
            "buildBetaDetailRelationshipUrl": relationshipSelfURL(relationships?.buildBetaDetail?.links),
            "appStoreVersionId": relationshipID(relationships?.appStoreVersion),
            "appStoreVersionUrl": relationshipURL(relationships?.appStoreVersion?.links),
            "appStoreVersionRelationshipUrl": relationshipSelfURL(relationships?.appStoreVersion?.links),
            "iconIds": relationshipIDs(relationships?.icons),
            "iconIdsMeta": relationshipIDsMetadata(relationships?.icons),
            "iconsUrl": relationshipURL(relationships?.icons?.links),
            "iconsRelationshipUrl": relationshipSelfURL(relationships?.icons?.links),
            "buildBundleIds": relationshipIDs(relationships?.buildBundles),
            "buildBundleIdsMeta": relationshipIDsMetadata(relationships?.buildBundles),
            "buildBundlesUrl": relationshipURL(relationships?.buildBundles?.links),
            "buildUploadId": relationshipID(relationships?.buildUpload),
            "buildUploadUrl": relationshipURL(relationships?.buildUpload?.links),
            "perfPowerMetricsUrl": relationshipURL(relationships?.perfPowerMetrics?.links),
            "perfPowerMetricsRelationshipUrl": (relationships?.perfPowerMetrics?.links?.`self`).jsonSafe,
            "diagnosticSignaturesUrl": relationshipURL(relationships?.diagnosticSignatures?.links),
            "diagnosticSignaturesRelationshipUrl": (relationships?.diagnosticSignatures?.links?.`self`).jsonSafe
        ]
    }

    private func formatBuildIconAsset(_ asset: ImageAsset?) -> Any {
        guard let asset else {
            return NSNull()
        }
        return [
            "templateUrl": (asset.templateUrl).jsonSafe,
            "width": (asset.width).jsonSafe,
            "height": (asset.height).jsonSafe
        ]
    }
}

private struct XcodeCloudArgumentError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
