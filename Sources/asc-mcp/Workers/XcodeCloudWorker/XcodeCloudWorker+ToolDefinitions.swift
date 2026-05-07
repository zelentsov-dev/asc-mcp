import Foundation
import MCP

extension XcodeCloudWorker {
    func productsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_products_list",
            description: "List Xcode Cloud products. Returns product IDs, names, product type, app relationship, repository relationships, and pagination info.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "product_type": enumSchema("Filter by product type", values: ["APP", "FRAMEWORK"]),
                    "app_id": stringSchema("Filter by related App Store Connect app ID"),
                    "include": includeSchema("Related resources to include", values: ["app", "bundleId", "primaryRepositories"])
                ])
            )
        )
    }

    func productsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_products_get",
            description: "Get one Xcode Cloud product by ID.",
            inputSchema: baseSchema(
                properties: [
                    "product_id": stringSchema("Xcode Cloud product ID"),
                    "include": includeSchema("Related resources to include", values: ["app", "bundleId", "primaryRepositories"])
                ],
                required: ["product_id"]
            )
        )
    }

    func productWorkflowsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_product_workflows_list",
            description: "List workflows for an Xcode Cloud product.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "product_id": stringSchema("Xcode Cloud product ID"),
                    "include": includeSchema("Related resources to include", values: ["product", "repository", "xcodeVersion", "macOsVersion"])
                ]),
                required: ["product_id"]
            )
        )
    }

    func productBuildRunsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_product_build_runs_list",
            description: "List Xcode Cloud build runs for a product.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "product_id": stringSchema("Xcode Cloud product ID"),
                    "sort": enumSchema("Sort by build number", values: ["number", "-number"]),
                    "include": includeSchema("Related resources to include", values: ["builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"])
                ]),
                required: ["product_id"]
            )
        )
    }

    func workflowsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_workflows_get",
            description: "Get one Xcode Cloud workflow by ID, including actions and start-condition summaries.",
            inputSchema: baseSchema(
                properties: [
                    "workflow_id": stringSchema("Xcode Cloud workflow ID"),
                    "include": includeSchema("Related resources to include", values: ["product", "repository", "xcodeVersion", "macOsVersion"])
                ],
                required: ["workflow_id"]
            )
        )
    }

    func workflowBuildRunsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_workflow_build_runs_list",
            description: "List Xcode Cloud build runs for a workflow.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "workflow_id": stringSchema("Xcode Cloud workflow ID"),
                    "build_id": stringSchema("Filter by related App Store Connect build ID"),
                    "sort": enumSchema("Sort by build number", values: ["number", "-number"]),
                    "include": includeSchema("Related resources to include", values: ["builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"])
                ]),
                required: ["workflow_id"]
            )
        )
    }

    func buildRunsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_build_runs_get",
            description: "Get one Xcode Cloud build run by ID.",
            inputSchema: baseSchema(
                properties: [
                    "build_run_id": stringSchema("Xcode Cloud build run ID"),
                    "include": includeSchema("Related resources to include", values: ["builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"])
                ],
                required: ["build_run_id"]
            )
        )
    }

    func buildRunsStartTool() -> Tool {
        Tool(
            name: "xcode_cloud_build_runs_start",
            description: "Start an Xcode Cloud build. Provide workflow_id for a new run or build_run_id for a rebuild; optional source_branch_or_tag_id and pull_request_id choose the source.",
            inputSchema: baseSchema(
                properties: [
                    "workflow_id": stringSchema("Workflow ID to start"),
                    "build_run_id": stringSchema("Existing build run ID to rebuild"),
                    "source_branch_or_tag_id": stringSchema("SCM git reference ID to build"),
                    "pull_request_id": stringSchema("SCM pull request ID to build"),
                    "clean": boolSchema("Whether Xcode Cloud should perform a clean build")
                ]
            )
        )
    }

    func buildRunActionsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_build_run_actions_list",
            description: "List actions performed during an Xcode Cloud build run.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "build_run_id": stringSchema("Xcode Cloud build run ID"),
                    "include": includeSchema("Related resources to include", values: ["buildRun"])
                ]),
                required: ["build_run_id"]
            )
        )
    }

    func buildRunBuildsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_build_run_builds_list",
            description: "List App Store Connect/TestFlight builds created by an Xcode Cloud build run.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "build_run_id": stringSchema("Xcode Cloud build run ID")
                ]),
                required: ["build_run_id"]
            )
        )
    }

    func actionsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_actions_get",
            description: "Get one Xcode Cloud build action by ID.",
            inputSchema: baseSchema(
                properties: [
                    "action_id": stringSchema("Xcode Cloud build action ID"),
                    "include": includeSchema("Related resources to include", values: ["buildRun"])
                ],
                required: ["action_id"]
            )
        )
    }

    func actionArtifactsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_action_artifacts_list",
            description: "List artifacts for an Xcode Cloud build action, including file names, sizes, types, and download URLs.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "action_id": stringSchema("Xcode Cloud build action ID")
                ]),
                required: ["action_id"]
            )
        )
    }

    func actionIssuesListTool() -> Tool {
        Tool(
            name: "xcode_cloud_action_issues_list",
            description: "List issues for an Xcode Cloud build action.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "action_id": stringSchema("Xcode Cloud build action ID")
                ]),
                required: ["action_id"]
            )
        )
    }

    func actionTestResultsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_action_test_results_list",
            description: "List test results for an Xcode Cloud build action.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "action_id": stringSchema("Xcode Cloud build action ID")
                ]),
                required: ["action_id"]
            )
        )
    }

    func artifactsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_artifacts_get",
            description: "Get one Xcode Cloud artifact by ID.",
            inputSchema: baseSchema(
                properties: [
                    "artifact_id": stringSchema("Xcode Cloud artifact ID")
                ],
                required: ["artifact_id"]
            )
        )
    }

    func issuesGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_issues_get",
            description: "Get one Xcode Cloud issue by ID.",
            inputSchema: baseSchema(
                properties: [
                    "issue_id": stringSchema("Xcode Cloud issue ID")
                ],
                required: ["issue_id"]
            )
        )
    }

    func testResultsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_test_results_get",
            description: "Get one Xcode Cloud test result by ID.",
            inputSchema: baseSchema(
                properties: [
                    "test_result_id": stringSchema("Xcode Cloud test result ID")
                ],
                required: ["test_result_id"]
            )
        )
    }

    func xcodeVersionsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_xcode_versions_list",
            description: "List Xcode versions available for Xcode Cloud workflows.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "include": includeSchema("Related resources to include", values: ["macOsVersions"])
                ])
            )
        )
    }

    func xcodeVersionsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_xcode_versions_get",
            description: "Get one Xcode Cloud Xcode version by ID.",
            inputSchema: baseSchema(
                properties: [
                    "xcode_version_id": stringSchema("Xcode version ID"),
                    "include": includeSchema("Related resources to include", values: ["macOsVersions"])
                ],
                required: ["xcode_version_id"]
            )
        )
    }

    func macOSVersionsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_macos_versions_list",
            description: "List macOS versions available for Xcode Cloud workflows.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "include": includeSchema("Related resources to include", values: ["xcodeVersions"])
                ])
            )
        )
    }

    func macOSVersionsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_macos_versions_get",
            description: "Get one Xcode Cloud macOS version by ID.",
            inputSchema: baseSchema(
                properties: [
                    "macos_version_id": stringSchema("macOS version ID"),
                    "include": includeSchema("Related resources to include", values: ["xcodeVersions"])
                ],
                required: ["macos_version_id"]
            )
        )
    }

    func scmProvidersListTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_providers_list",
            description: "List source code management providers connected to Xcode Cloud.",
            inputSchema: baseSchema(properties: listProperties([:]))
        )
    }

    func scmProvidersGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_providers_get",
            description: "Get one Xcode Cloud SCM provider by ID.",
            inputSchema: baseSchema(
                properties: [
                    "provider_id": stringSchema("SCM provider ID")
                ],
                required: ["provider_id"]
            )
        )
    }

    func scmProviderRepositoriesListTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_provider_repositories_list",
            description: "List repositories for an Xcode Cloud SCM provider.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "provider_id": stringSchema("SCM provider ID"),
                    "repository_id": stringSchema("Optional repository ID filter"),
                    "include": includeSchema("Related resources to include", values: ["scmProvider", "defaultBranch"])
                ]),
                required: ["provider_id"]
            )
        )
    }

    func scmRepositoriesListTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_repositories_list",
            description: "List repositories available to Xcode Cloud.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "repository_id": stringSchema("Optional repository ID filter"),
                    "include": includeSchema("Related resources to include", values: ["scmProvider", "defaultBranch"])
                ])
            )
        )
    }

    func scmRepositoriesGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_repositories_get",
            description: "Get one Xcode Cloud SCM repository by ID.",
            inputSchema: baseSchema(
                properties: [
                    "repository_id": stringSchema("SCM repository ID"),
                    "include": includeSchema("Related resources to include", values: ["scmProvider", "defaultBranch"])
                ],
                required: ["repository_id"]
            )
        )
    }

    func scmRepositoryGitReferencesListTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_repository_git_references_list",
            description: "List git branch/tag references for an Xcode Cloud SCM repository.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "repository_id": stringSchema("SCM repository ID"),
                    "include": includeSchema("Related resources to include", values: ["repository"])
                ]),
                required: ["repository_id"]
            )
        )
    }

    func scmRepositoryPullRequestsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_repository_pull_requests_list",
            description: "List pull requests for an Xcode Cloud SCM repository.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "repository_id": stringSchema("SCM repository ID"),
                    "include": includeSchema("Related resources to include", values: ["repository"])
                ]),
                required: ["repository_id"]
            )
        )
    }

    func scmGitReferencesGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_git_references_get",
            description: "Get one Xcode Cloud SCM git reference by ID.",
            inputSchema: baseSchema(
                properties: [
                    "git_reference_id": stringSchema("SCM git reference ID"),
                    "include": includeSchema("Related resources to include", values: ["repository"])
                ],
                required: ["git_reference_id"]
            )
        )
    }

    func scmPullRequestsGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_scm_pull_requests_get",
            description: "Get one Xcode Cloud SCM pull request by ID.",
            inputSchema: baseSchema(
                properties: [
                    "pull_request_id": stringSchema("SCM pull request ID"),
                    "include": includeSchema("Related resources to include", values: ["repository"])
                ],
                required: ["pull_request_id"]
            )
        )
    }

    private func listProperties(_ extra: [String: Value]) -> [String: Value] {
        var properties = extra
        properties["limit"] = integerSchema("Max results (default: 25, max: 200)")
        properties["next_url"] = stringSchema("Pagination URL from a previous response")
        return properties
    }

    private func baseSchema(properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    private func stringSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private func integerSchema(_ description: String) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description)
        ])
    }

    private func boolSchema(_ description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }

    private func enumSchema(_ description: String, values: [String]) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "enum": .array(values.map(Value.string))
        ])
    }

    private func includeSchema(_ description: String, values: [String]) -> Value {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": .object([
                "type": .string("string"),
                "enum": .array(values.map(Value.string))
            ])
        ])
    }
}
