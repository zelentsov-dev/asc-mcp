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
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCIProductsResponse.self)
            } else {
                var query = listQuery(arguments)
                if let productType = arguments["product_type"]?.stringValue {
                    query["filter[productType]"] = productType
                }
                if let appID = arguments["app_id"]?.stringValue {
                    query["filter[app]"] = appID
                }
                applyInclude(arguments, to: &query)
                response = try await httpClient.get("/v1/ciProducts", parameters: query, as: ASCCIProductsResponse.self)
            }

            var result = listResult("products", response.data.map(formatProduct), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud products: \(error.localizedDescription)")
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
            let response = try await httpClient.get("/v1/ciProducts/\(productID)", parameters: query, as: ASCCIProductResponse.self)
            var result: [String: Any] = ["success": true, "product": formatProduct(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud product: \(error.localizedDescription)")
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
        return try await listWorkflows(endpoint: "/v1/ciProducts/\(productID)/workflows", arguments: arguments, failureContext: "product workflows")
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
        return try await listBuildRuns(endpoint: "/v1/ciProducts/\(productID)/buildRuns", arguments: arguments, failureContext: "product build runs")
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
            let response = try await httpClient.get("/v1/ciWorkflows/\(workflowID)", parameters: query, as: ASCCIWorkflowResponse.self)
            var result: [String: Any] = ["success": true, "workflow": formatWorkflow(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud workflow: \(error.localizedDescription)")
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
        return try await listBuildRuns(endpoint: "/v1/ciWorkflows/\(workflowID)/buildRuns", arguments: arguments, failureContext: "workflow build runs")
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
            let response = try await httpClient.get("/v1/ciBuildRuns/\(buildRunID)", parameters: query, as: ASCCIBuildRunResponse.self)
            var result: [String: Any] = ["success": true, "buildRun": formatBuildRun(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud build run: \(error.localizedDescription)")
        }
    }

    /// Starts an Xcode Cloud build run.
    /// - Parameter params: Tool parameters containing either `workflow_id` or `build_run_id`.
    /// - Returns: JSON object containing the created build run resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func startBuildRun(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters: workflow_id or build_run_id")
        }

        let workflowID = arguments["workflow_id"]?.stringValue
        let buildRunID = arguments["build_run_id"]?.stringValue
        let sourceBranchOrTagID = arguments["source_branch_or_tag_id"]?.stringValue
        let pullRequestID = arguments["pull_request_id"]?.stringValue

        guard workflowID != nil || buildRunID != nil else {
            return MCPResult.error("Provide 'workflow_id' to start a workflow build or 'build_run_id' to rebuild an existing run")
        }
        guard !(sourceBranchOrTagID != nil && pullRequestID != nil) else {
            return MCPResult.error("Use only one source selector: source_branch_or_tag_id or pull_request_id")
        }

        do {
            let request = ASCCIBuildRunCreateRequest(
                workflowID: workflowID,
                buildRunID: buildRunID,
                sourceBranchOrTagID: sourceBranchOrTagID,
                pullRequestID: pullRequestID,
                clean: arguments["clean"]?.boolValue
            )
            let response = try await httpClient.post("/v1/ciBuildRuns", body: request, as: ASCCIBuildRunResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "buildRun": formatBuildRun(response.data)
            ])
        } catch {
            return MCPResult.error("Failed to start Xcode Cloud build run: \(error.localizedDescription)")
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
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCIBuildActionsResponse.self)
            } else {
                var query = listQuery(arguments)
                applyInclude(arguments, to: &query)
                response = try await httpClient.get("/v1/ciBuildRuns/\(buildRunID)/actions", parameters: query, as: ASCCIBuildActionsResponse.self)
            }

            var result = listResult("actions", response.data.map(formatAction), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud build run actions: \(error.localizedDescription)")
        }
    }

    /// Lists App Store Connect builds created by one Xcode Cloud build run.
    /// - Parameter params: Tool parameters containing `build_run_id`.
    /// - Returns: JSON object containing build summaries and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listBuildRunBuilds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildRunID = arguments["build_run_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'build_run_id' is missing")
        }

        do {
            let response: ASCBuildsResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBuildsResponse.self)
            } else {
                response = try await httpClient.get("/v1/ciBuildRuns/\(buildRunID)/builds", parameters: listQuery(arguments), as: ASCBuildsResponse.self)
            }

            var result: [String: Any] = [
                "success": true,
                "builds": response.data.map(formatASCBuild),
                "count": response.data.count
            ]
            appendPaging(response.links, nil, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list App Store Connect builds for Xcode Cloud run: \(error.localizedDescription)")
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
            let response = try await httpClient.get("/v1/ciBuildActions/\(actionID)", parameters: query, as: ASCCIBuildActionResponse.self)
            var result: [String: Any] = ["success": true, "action": formatAction(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud build action: \(error.localizedDescription)")
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
        return try await listArtifacts(endpoint: "/v1/ciBuildActions/\(actionID)/artifacts", arguments: arguments)
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
        return try await listIssues(endpoint: "/v1/ciBuildActions/\(actionID)/issues", arguments: arguments)
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
        return try await listTestResults(endpoint: "/v1/ciBuildActions/\(actionID)/testResults", arguments: arguments)
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
            let response = try await httpClient.get("/v1/ciArtifacts/\(artifactID)", as: ASCCIArtifactResponse.self)
            return MCPResult.jsonObject(["success": true, "artifact": formatArtifact(response.data)])
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud artifact: \(error.localizedDescription)")
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
            let response = try await httpClient.get("/v1/ciIssues/\(issueID)", as: ASCCIIssueResponse.self)
            return MCPResult.jsonObject(["success": true, "issue": formatIssue(response.data)])
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud issue: \(error.localizedDescription)")
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
            let response = try await httpClient.get("/v1/ciTestResults/\(testResultID)", as: ASCCITestResultResponse.self)
            return MCPResult.jsonObject(["success": true, "testResult": formatTestResult(response.data)])
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud test result: \(error.localizedDescription)")
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
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCIXcodeVersionsResponse.self)
            } else {
                var query = listQuery(arguments)
                applyInclude(arguments, to: &query)
                response = try await httpClient.get("/v1/ciXcodeVersions", parameters: query, as: ASCCIXcodeVersionsResponse.self)
            }

            var result = listResult("xcodeVersions", response.data.map(formatXcodeVersion), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud Xcode versions: \(error.localizedDescription)")
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
            let response = try await httpClient.get("/v1/ciXcodeVersions/\(xcodeVersionID)", parameters: query, as: ASCCIXcodeVersionResponse.self)
            var result: [String: Any] = ["success": true, "xcodeVersion": formatXcodeVersion(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud Xcode version: \(error.localizedDescription)")
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
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCIMacOSVersionsResponse.self)
            } else {
                var query = listQuery(arguments)
                applyInclude(arguments, to: &query)
                response = try await httpClient.get("/v1/ciMacOsVersions", parameters: query, as: ASCCIMacOSVersionsResponse.self)
            }

            var result = listResult("macOSVersions", response.data.map(formatMacOSVersion), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud macOS versions: \(error.localizedDescription)")
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
            let response = try await httpClient.get("/v1/ciMacOsVersions/\(macOSVersionID)", parameters: query, as: ASCCIMacOSVersionResponse.self)
            var result: [String: Any] = ["success": true, "macOSVersion": formatMacOSVersion(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud macOS version: \(error.localizedDescription)")
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
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCScmProvidersResponse.self)
            } else {
                response = try await httpClient.get("/v1/scmProviders", parameters: listQuery(arguments), as: ASCScmProvidersResponse.self)
            }

            var result = listResult("providers", response.data.map(formatScmProvider), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud SCM providers: \(error.localizedDescription)")
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
            let response = try await httpClient.get("/v1/scmProviders/\(providerID)", as: ASCScmProviderResponse.self)
            return MCPResult.jsonObject(["success": true, "provider": formatScmProvider(response.data)])
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud SCM provider: \(error.localizedDescription)")
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
        return try await listScmRepositories(endpoint: "/v1/scmProviders/\(providerID)/repositories", arguments: arguments)
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
            let response = try await httpClient.get("/v1/scmRepositories/\(repositoryID)", parameters: query, as: ASCScmRepositoryResponse.self)
            var result: [String: Any] = ["success": true, "repository": formatScmRepository(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud SCM repository: \(error.localizedDescription)")
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
        return try await listScmGitReferences(endpoint: "/v1/scmRepositories/\(repositoryID)/gitReferences", arguments: arguments)
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
        return try await listScmPullRequests(endpoint: "/v1/scmRepositories/\(repositoryID)/pullRequests", arguments: arguments)
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
            let response = try await httpClient.get("/v1/scmGitReferences/\(gitReferenceID)", parameters: query, as: ASCScmGitReferenceResponse.self)
            var result: [String: Any] = ["success": true, "gitReference": formatScmGitReference(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud SCM git reference: \(error.localizedDescription)")
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
            let response = try await httpClient.get("/v1/scmPullRequests/\(pullRequestID)", parameters: query, as: ASCScmPullRequestResponse.self)
            var result: [String: Any] = ["success": true, "pullRequest": formatScmPullRequest(response.data)]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get Xcode Cloud SCM pull request: \(error.localizedDescription)")
        }
    }

    private func listWorkflows(endpoint: String, arguments: [String: Value], failureContext: String) async throws -> CallTool.Result {
        do {
            let response: ASCCIWorkflowsResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCIWorkflowsResponse.self)
            } else {
                var query = listQuery(arguments)
                applyInclude(arguments, to: &query)
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIWorkflowsResponse.self)
            }

            var result = listResult("workflows", response.data.map(formatWorkflow), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud \(failureContext): \(error.localizedDescription)")
        }
    }

    private func listBuildRuns(endpoint: String, arguments: [String: Value], failureContext: String) async throws -> CallTool.Result {
        do {
            let response: ASCCIBuildRunsResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCIBuildRunsResponse.self)
            } else {
                var query = listQuery(arguments)
                if let buildID = arguments["build_id"]?.stringValue {
                    query["filter[builds]"] = buildID
                }
                if let sort = arguments["sort"]?.stringValue {
                    query["sort"] = sort
                }
                applyInclude(arguments, to: &query)
                response = try await httpClient.get(endpoint, parameters: query, as: ASCCIBuildRunsResponse.self)
            }

            var result = listResult("buildRuns", response.data.map(formatBuildRun), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud \(failureContext): \(error.localizedDescription)")
        }
    }

    private func listArtifacts(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCCIArtifactsResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCIArtifactsResponse.self)
            } else {
                response = try await httpClient.get(endpoint, parameters: listQuery(arguments), as: ASCCIArtifactsResponse.self)
            }
            var result = listResult("artifacts", response.data.map(formatArtifact), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud artifacts: \(error.localizedDescription)")
        }
    }

    private func listIssues(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCCIIssuesResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCIIssuesResponse.self)
            } else {
                response = try await httpClient.get(endpoint, parameters: listQuery(arguments), as: ASCCIIssuesResponse.self)
            }
            var result = listResult("issues", response.data.map(formatIssue), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud issues: \(error.localizedDescription)")
        }
    }

    private func listTestResults(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCCITestResultsResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCITestResultsResponse.self)
            } else {
                response = try await httpClient.get(endpoint, parameters: listQuery(arguments), as: ASCCITestResultsResponse.self)
            }
            var result = listResult("testResults", response.data.map(formatTestResult), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud test results: \(error.localizedDescription)")
        }
    }

    private func listScmRepositories(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCScmRepositoriesResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCScmRepositoriesResponse.self)
            } else {
                var query = listQuery(arguments)
                if let repositoryID = arguments["repository_id"]?.stringValue {
                    query["filter[id]"] = repositoryID
                }
                applyInclude(arguments, to: &query)
                response = try await httpClient.get(endpoint, parameters: query, as: ASCScmRepositoriesResponse.self)
            }

            var result = listResult("repositories", response.data.map(formatScmRepository), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud SCM repositories: \(error.localizedDescription)")
        }
    }

    private func listScmGitReferences(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCScmGitReferencesResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCScmGitReferencesResponse.self)
            } else {
                var query = listQuery(arguments)
                applyInclude(arguments, to: &query)
                response = try await httpClient.get(endpoint, parameters: query, as: ASCScmGitReferencesResponse.self)
            }

            var result = listResult("gitReferences", response.data.map(formatScmGitReference), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud SCM git references: \(error.localizedDescription)")
        }
    }

    private func listScmPullRequests(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response: ASCScmPullRequestsResponse
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCScmPullRequestsResponse.self)
            } else {
                var query = listQuery(arguments)
                applyInclude(arguments, to: &query)
                response = try await httpClient.get(endpoint, parameters: query, as: ASCScmPullRequestsResponse.self)
            }

            var result = listResult("pullRequests", response.data.map(formatScmPullRequest), links: response.links, meta: response.meta)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list Xcode Cloud SCM pull requests: \(error.localizedDescription)")
        }
    }

    private func listQuery(_ arguments: [String: Value]) -> [String: String] {
        let limit = arguments["limit"]?.intValue ?? 25
        return ["limit": String(min(max(limit, 1), 200))]
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

    private func listResult(_ key: String, _ values: [[String: Any]], links: ASCPagedDocumentLinks?, meta: ASCPagingInformation?) -> [String: Any] {
        var result: [String: Any] = [
            "success": true,
            key: values,
            "count": values.count
        ]
        appendPaging(links, meta, to: &result)
        return result
    }

    private func appendPaging(_ links: ASCPagedDocumentLinks?, _ meta: ASCPagingInformation?, to result: inout [String: Any]) {
        if let next = links?.next {
            result["next_url"] = next
        }
        if let total = meta?.paging?.total {
            result["total"] = total
        }
    }

    private func appendIncluded(_ included: [JSONValue]?, to result: inout [String: Any]) {
        if let included, !included.isEmpty {
            result["included"] = included.map(\.asAny)
        }
    }

    private func relationshipID(_ relationship: ASCRelationship?) -> Any {
        relationship?.data?.id ?? NSNull()
    }

    private func relationshipIDs(_ relationship: ASCRelationshipMultiple?) -> [String] {
        relationship?.data?.map(\.id) ?? []
    }

    private func formatProduct(_ product: ASCCIProduct) -> [String: Any] {
        [
            "id": product.id,
            "type": product.type,
            "name": (product.attributes?.name).jsonSafe,
            "createdDate": (product.attributes?.createdDate).jsonSafe,
            "productType": (product.attributes?.productType).jsonSafe,
            "appId": relationshipID(product.relationships?.app),
            "bundleIdResourceId": relationshipID(product.relationships?.bundleId),
            "workflowIds": relationshipIDs(product.relationships?.workflows),
            "primaryRepositoryIds": relationshipIDs(product.relationships?.primaryRepositories),
            "additionalRepositoryIds": relationshipIDs(product.relationships?.additionalRepositories),
            "buildRunIds": relationshipIDs(product.relationships?.buildRuns)
        ]
    }

    private func formatWorkflow(_ workflow: ASCCIWorkflow) -> [String: Any] {
        let attrs = workflow.attributes
        return [
            "id": workflow.id,
            "type": workflow.type,
            "name": (attrs?.name).jsonSafe,
            "description": (attrs?.description).jsonSafe,
            "isEnabled": (attrs?.isEnabled).jsonSafe,
            "isLockedForEditing": (attrs?.isLockedForEditing).jsonSafe,
            "clean": (attrs?.clean).jsonSafe,
            "containerFilePath": (attrs?.containerFilePath).jsonSafe,
            "lastModifiedDate": (attrs?.lastModifiedDate).jsonSafe,
            "actions": attrs?.actions?.map(\.asAny) ?? [],
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
            "xcodeVersionId": relationshipID(workflow.relationships?.xcodeVersion),
            "macOSVersionId": relationshipID(workflow.relationships?.macOsVersion),
            "buildRunIds": relationshipIDs(workflow.relationships?.buildRuns)
        ]
    }

    private func formatBuildRun(_ buildRun: ASCCIBuildRun) -> [String: Any] {
        let attrs = buildRun.attributes
        return [
            "id": buildRun.id,
            "type": buildRun.type,
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
            "workflowId": relationshipID(buildRun.relationships?.workflow),
            "productId": relationshipID(buildRun.relationships?.product),
            "sourceBranchOrTagId": relationshipID(buildRun.relationships?.sourceBranchOrTag),
            "destinationBranchId": relationshipID(buildRun.relationships?.destinationBranch),
            "actionIds": relationshipIDs(buildRun.relationships?.actions),
            "pullRequestId": relationshipID(buildRun.relationships?.pullRequest)
        ]
    }

    private func formatAction(_ action: ASCCIBuildAction) -> [String: Any] {
        let attrs = action.attributes
        return [
            "id": action.id,
            "type": action.type,
            "name": (attrs?.name).jsonSafe,
            "actionType": (attrs?.actionType).jsonSafe,
            "startedDate": (attrs?.startedDate).jsonSafe,
            "finishedDate": (attrs?.finishedDate).jsonSafe,
            "issueCounts": formatIssueCounts(attrs?.issueCounts),
            "executionProgress": (attrs?.executionProgress).jsonSafe,
            "completionStatus": (attrs?.completionStatus).jsonSafe,
            "isRequiredToPass": (attrs?.isRequiredToPass).jsonSafe,
            "buildRunId": relationshipID(action.relationships?.buildRun),
            "artifactIds": relationshipIDs(action.relationships?.artifacts),
            "issueIds": relationshipIDs(action.relationships?.issues),
            "testResultIds": relationshipIDs(action.relationships?.testResults)
        ]
    }

    private func formatArtifact(_ artifact: ASCCIArtifact) -> [String: Any] {
        [
            "id": artifact.id,
            "type": artifact.type,
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
            "name": (result.attributes?.name).jsonSafe,
            "className": (result.attributes?.className).jsonSafe,
            "status": (result.attributes?.status).jsonSafe,
            "message": (result.attributes?.message).jsonSafe,
            "fileSource": formatFileSource(result.attributes?.fileSource),
            "destinationTestResults": result.attributes?.destinationTestResults?.map(formatDestinationTestResult) ?? []
        ]
    }

    private func formatXcodeVersion(_ version: ASCCIXcodeVersion) -> [String: Any] {
        [
            "id": version.id,
            "type": version.type,
            "version": (version.attributes?.version).jsonSafe,
            "name": (version.attributes?.name).jsonSafe,
            "testDestinations": version.attributes?.testDestinations?.map(formatTestDestination) ?? [],
            "macOSVersionIds": relationshipIDs(version.relationships?.macOsVersions)
        ]
    }

    private func formatMacOSVersion(_ version: ASCCIMacOSVersion) -> [String: Any] {
        [
            "id": version.id,
            "type": version.type,
            "version": (version.attributes?.version).jsonSafe,
            "name": (version.attributes?.name).jsonSafe,
            "xcodeVersionIds": relationshipIDs(version.relationships?.xcodeVersions)
        ]
    }

    private func formatScmProvider(_ provider: ASCScmProvider) -> [String: Any] {
        [
            "id": provider.id,
            "type": provider.type,
            "scmProviderType": (provider.attributes?.scmProviderType).jsonSafe,
            "url": (provider.attributes?.url).jsonSafe,
            "repositoryIds": relationshipIDs(provider.relationships?.repositories)
        ]
    }

    private func formatScmRepository(_ repository: ASCScmRepository) -> [String: Any] {
        [
            "id": repository.id,
            "type": repository.type,
            "lastAccessedDate": (repository.attributes?.lastAccessedDate).jsonSafe,
            "httpCloneUrl": (repository.attributes?.httpCloneUrl).jsonSafe,
            "sshCloneUrl": (repository.attributes?.sshCloneUrl).jsonSafe,
            "ownerName": (repository.attributes?.ownerName).jsonSafe,
            "repositoryName": (repository.attributes?.repositoryName).jsonSafe,
            "providerId": relationshipID(repository.relationships?.scmProvider),
            "defaultBranchId": relationshipID(repository.relationships?.defaultBranch),
            "gitReferenceIds": relationshipIDs(repository.relationships?.gitReferences),
            "pullRequestIds": relationshipIDs(repository.relationships?.pullRequests)
        ]
    }

    private func formatScmGitReference(_ reference: ASCScmGitReference) -> [String: Any] {
        [
            "id": reference.id,
            "type": reference.type,
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

    private func formatCommit(_ commit: ASCCIBuildRun.Commit?) -> [String: Any] {
        [
            "commitSha": (commit?.commitSha).jsonSafe,
            "message": (commit?.message).jsonSafe,
            "author": formatGitUser(commit?.author),
            "committer": formatGitUser(commit?.committer),
            "webUrl": (commit?.webUrl).jsonSafe
        ]
    }

    private func formatGitUser(_ user: ASCCIBuildRun.GitUser?) -> [String: Any] {
        [
            "displayName": (user?.displayName).jsonSafe,
            "email": (user?.email).jsonSafe
        ]
    }

    private func formatIssueCounts(_ counts: ASCCIBuildRun.IssueCounts?) -> [String: Any] {
        [
            "analyzerWarnings": (counts?.analyzerWarnings).jsonSafe,
            "errors": (counts?.errors).jsonSafe,
            "testFailures": (counts?.testFailures).jsonSafe,
            "warnings": (counts?.warnings).jsonSafe
        ]
    }

    private func formatFileSource(_ source: ASCCIIssue.FileSource?) -> [String: Any] {
        [
            "fileName": (source?.fileName).jsonSafe,
            "lineNumber": (source?.lineNumber).jsonSafe
        ]
    }

    private func formatDestinationTestResult(_ result: ASCCITestResult.DestinationTestResult) -> [String: Any] {
        [
            "deviceName": (result.deviceName).jsonSafe,
            "osVersion": (result.osVersion).jsonSafe,
            "status": (result.status).jsonSafe,
            "message": (result.message).jsonSafe,
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
            } ?? []
        ]
    }

    private func formatASCBuild(_ build: ASCBuild) -> [String: Any] {
        [
            "id": build.id,
            "type": build.type,
            "version": build.attributes.version.jsonSafe,
            "uploadedDate": build.attributes.uploadedDate.jsonSafe,
            "expirationDate": build.attributes.expirationDate.jsonSafe,
            "expired": build.attributes.expired.jsonSafe,
            "processingState": build.attributes.processingState.jsonSafe,
            "buildAudienceType": build.attributes.buildAudienceType.jsonSafe,
            "usesNonExemptEncryption": build.attributes.usesNonExemptEncryption.jsonSafe,
            "appId": relationshipID(build.relationships?.app),
            "preReleaseVersionId": relationshipID(build.relationships?.preReleaseVersion),
            "appStoreVersionId": relationshipID(build.relationships?.appStoreVersion)
        ]
    }
}
