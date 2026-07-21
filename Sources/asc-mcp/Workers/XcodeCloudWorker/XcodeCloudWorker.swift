import Foundation
import MCP

/// Manages Xcode Cloud products and workflows, starts builds, and reads CI, artifact, and SCM resources.
public final class XcodeCloudWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available Xcode Cloud tools.
    /// - Returns: Tool definitions for Xcode Cloud inspection, workflow management, guarded deletion, and build execution.
    public func getTools() async -> [Tool] {
        [
            productsListTool(),
            productsGetTool(),
            productsDeleteTool(),
            appProductGetTool(),
            productAppGetTool(),
            productPrimaryRepositoriesListTool(),
            productAdditionalRepositoriesListTool(),
            productWorkflowsListTool(),
            productBuildRunsListTool(),
            workflowsGetTool(),
            workflowsCreateTool(),
            workflowsUpdateTool(),
            workflowsDeleteTool(),
            workflowRepositoryGetTool(),
            workflowBuildRunsListTool(),
            buildRunsGetTool(),
            buildRunsStartTool(),
            buildRunActionsListTool(),
            buildRunBuildsListTool(),
            actionsGetTool(),
            actionBuildRunGetTool(),
            actionArtifactsListTool(),
            actionIssuesListTool(),
            actionTestResultsListTool(),
            artifactsGetTool(),
            issuesGetTool(),
            testResultsGetTool(),
            xcodeVersionsListTool(),
            xcodeVersionsGetTool(),
            xcodeVersionMacOSVersionsListTool(),
            macOSVersionsListTool(),
            macOSVersionsGetTool(),
            macOSVersionXcodeVersionsListTool(),
            scmProvidersListTool(),
            scmProvidersGetTool(),
            scmProviderRepositoriesListTool(),
            scmRepositoriesListTool(),
            scmRepositoriesGetTool(),
            scmRepositoryGitReferencesListTool(),
            scmRepositoryPullRequestsListTool(),
            scmGitReferencesGetTool(),
            scmPullRequestsGetTool()
        ]
    }

    /// Handle Xcode Cloud tool calls.
    /// - Parameter params: MCP tool call parameters.
    /// - Returns: MCP tool result with JSON text and structured content.
    /// - Throws: `MCPError.methodNotFound` for unknown tool names.
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        if let inputError = existingToolInputError(params) {
            return inputError
        }

        switch params.name {
        case "xcode_cloud_products_list":
            return try await listProducts(params)
        case "xcode_cloud_products_get":
            return try await getProduct(params)
        case "xcode_cloud_products_delete":
            return try await deleteProduct(params)
        case "xcode_cloud_app_product_get":
            return try await getAppProduct(params)
        case "xcode_cloud_product_app_get":
            return try await getProductApp(params)
        case "xcode_cloud_product_primary_repositories_list":
            return try await listProductPrimaryRepositories(params)
        case "xcode_cloud_product_additional_repositories_list":
            return try await listProductAdditionalRepositories(params)
        case "xcode_cloud_product_workflows_list":
            return try await listProductWorkflows(params)
        case "xcode_cloud_product_build_runs_list":
            return try await listProductBuildRuns(params)
        case "xcode_cloud_workflows_get":
            return try await getWorkflow(params)
        case "xcode_cloud_workflows_create":
            return try await createWorkflow(params)
        case "xcode_cloud_workflows_update":
            return try await updateWorkflow(params)
        case "xcode_cloud_workflows_delete":
            return try await deleteWorkflow(params)
        case "xcode_cloud_workflow_repository_get":
            return try await getWorkflowRepository(params)
        case "xcode_cloud_workflow_build_runs_list":
            return try await listWorkflowBuildRuns(params)
        case "xcode_cloud_build_runs_get":
            return try await getBuildRun(params)
        case "xcode_cloud_build_runs_start":
            return try await startBuildRun(params)
        case "xcode_cloud_build_run_actions_list":
            return try await listBuildRunActions(params)
        case "xcode_cloud_build_run_builds_list":
            return try await listBuildRunBuilds(params)
        case "xcode_cloud_actions_get":
            return try await getAction(params)
        case "xcode_cloud_action_build_run_get":
            return try await getActionBuildRun(params)
        case "xcode_cloud_action_artifacts_list":
            return try await listActionArtifacts(params)
        case "xcode_cloud_action_issues_list":
            return try await listActionIssues(params)
        case "xcode_cloud_action_test_results_list":
            return try await listActionTestResults(params)
        case "xcode_cloud_artifacts_get":
            return try await getArtifact(params)
        case "xcode_cloud_issues_get":
            return try await getIssue(params)
        case "xcode_cloud_test_results_get":
            return try await getTestResult(params)
        case "xcode_cloud_xcode_versions_list":
            return try await listXcodeVersions(params)
        case "xcode_cloud_xcode_versions_get":
            return try await getXcodeVersion(params)
        case "xcode_cloud_xcode_version_macos_versions_list":
            return try await listXcodeVersionMacOSVersions(params)
        case "xcode_cloud_macos_versions_list":
            return try await listMacOSVersions(params)
        case "xcode_cloud_macos_versions_get":
            return try await getMacOSVersion(params)
        case "xcode_cloud_macos_version_xcode_versions_list":
            return try await listMacOSVersionXcodeVersions(params)
        case "xcode_cloud_scm_providers_list":
            return try await listScmProviders(params)
        case "xcode_cloud_scm_providers_get":
            return try await getScmProvider(params)
        case "xcode_cloud_scm_provider_repositories_list":
            return try await listScmProviderRepositories(params)
        case "xcode_cloud_scm_repositories_list":
            return try await listScmRepositories(params)
        case "xcode_cloud_scm_repositories_get":
            return try await getScmRepository(params)
        case "xcode_cloud_scm_repository_git_references_list":
            return try await listScmRepositoryGitReferences(params)
        case "xcode_cloud_scm_repository_pull_requests_list":
            return try await listScmRepositoryPullRequests(params)
        case "xcode_cloud_scm_git_references_get":
            return try await getScmGitReference(params)
        case "xcode_cloud_scm_pull_requests_get":
            return try await getScmPullRequest(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
