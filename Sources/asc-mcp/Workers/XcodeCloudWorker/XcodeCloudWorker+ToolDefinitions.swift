import Foundation
import MCP

extension XcodeCloudWorker {
    func productsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_products_list",
            description: "List Xcode Cloud products. Returns product IDs, names, product type, app relationship, repository relationships, and pagination info.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "product_type": enumListSchema("Filter by one or more product types", values: ["APP", "FRAMEWORK"]),
                    "app_id": identifierListSchema("Filter by one or more related App Store Connect app IDs"),
                    "include": includeSchema("Related resources to include", values: ["app", "bundleId", "primaryRepositories"]),
                    "primary_repositories_limit": integerSchema(
                        "Maximum included primary repositories; requires include=primaryRepositories",
                        minimum: 1,
                        maximum: 50
                    )
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
                    "product_id": nonEmptyStringSchema("Xcode Cloud product ID"),
                    "include": includeSchema("Related resources to include", values: ["app", "bundleId", "primaryRepositories"]),
                    "primary_repositories_limit": integerSchema(
                        "Maximum included primary repositories; requires include=primaryRepositories",
                        minimum: 1,
                        maximum: 50
                    )
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
                    "product_id": nonEmptyStringSchema("Xcode Cloud product ID"),
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
                    "product_id": nonEmptyStringSchema("Xcode Cloud product ID"),
                    "build_id": identifierListSchema("Filter by one or more related App Store Connect build IDs"),
                    "sort": enumListSchema("Sort by one or more build number expressions", values: ["number", "-number"]),
                    "include": includeSchema("Related resources to include", values: ["builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"]),
                    "builds_limit": integerSchema(
                        "Maximum included builds; requires include=builds",
                        minimum: 1,
                        maximum: 50
                    )
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
                    "workflow_id": nonEmptyStringSchema("Xcode Cloud workflow ID"),
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
                    "workflow_id": nonEmptyStringSchema("Xcode Cloud workflow ID"),
                    "build_id": identifierListSchema("Filter by one or more related App Store Connect build IDs"),
                    "sort": enumListSchema("Sort by one or more build number expressions", values: ["number", "-number"]),
                    "include": includeSchema("Related resources to include", values: ["builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"]),
                    "builds_limit": integerSchema(
                        "Maximum included builds; requires include=builds",
                        minimum: 1,
                        maximum: 50
                    )
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
                    "build_run_id": nonEmptyStringSchema("Xcode Cloud build run ID"),
                    "include": includeSchema("Related resources to include", values: ["builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"]),
                    "builds_limit": integerSchema(
                        "Maximum included builds; requires include=builds",
                        minimum: 1,
                        maximum: 50
                    )
                ],
                required: ["build_run_id"]
            )
        )
    }

    func buildRunsStartTool() -> Tool {
        Tool(
            name: "xcode_cloud_build_runs_start",
            description: "Start an Xcode Cloud build. Provide exactly one of workflow_id for a new run or build_run_id for a rebuild; optional source_branch_or_tag_id and pull_request_id choose the source.",
            inputSchema: buildRunStartSchema()
        )
    }

    func buildRunActionsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_build_run_actions_list",
            description: "List actions performed during an Xcode Cloud build run.",
            inputSchema: baseSchema(
                properties: listProperties([
                    "build_run_id": nonEmptyStringSchema("Xcode Cloud build run ID"),
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
                    "build_run_id": nonEmptyStringSchema("Xcode Cloud build run ID"),
                    "version": stringListSchema("Filter by one or more build numbers"),
                    "expired": booleanListSchema("Filter by one or more expiration values"),
                    "processing_state": enumListSchema(
                        "Filter by one or more processing states",
                        values: ["PROCESSING", "FAILED", "INVALID", "VALID"]
                    ),
                    "beta_review_states": enumListSchema(
                        "Filter by one or more TestFlight beta review states",
                        values: ["WAITING_FOR_REVIEW", "IN_REVIEW", "REJECTED", "APPROVED"]
                    ),
                    "uses_non_exempt_encryption": booleanListSchema("Filter by one or more non-exempt encryption values"),
                    "pre_release_versions": stringListSchema("Filter by one or more pre-release version strings"),
                    "pre_release_platforms": enumListSchema(
                        "Filter by one or more pre-release platforms",
                        values: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
                    ),
                    "build_audience_types": enumListSchema(
                        "Filter by one or more build audience types",
                        values: ["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"]
                    ),
                    "pre_release_version_ids": identifierListSchema("Filter by one or more pre-release version IDs"),
                    "app_ids": identifierListSchema("Filter by one or more App Store Connect app IDs"),
                    "beta_group_ids": identifierListSchema("Filter by one or more beta group IDs"),
                    "app_store_version_ids": identifierListSchema("Filter by one or more App Store version IDs"),
                    "build_ids": identifierListSchema("Filter by one or more build IDs"),
                    "uses_non_exempt_encryption_set": boolSchema("Filter by whether the usesNonExemptEncryption attribute is present"),
                    "include": includeSchema(
                        "Related resources to include",
                        values: [
                            "preReleaseVersion", "individualTesters", "betaGroups",
                            "betaBuildLocalizations", "appEncryptionDeclaration",
                            "betaAppReviewSubmission", "app", "buildBetaDetail",
                            "appStoreVersion", "icons", "buildBundles", "buildUpload"
                        ]
                    ),
                    "individual_testers_limit": integerSchema(
                        "Maximum included individual testers; requires include=individualTesters",
                        minimum: 1,
                        maximum: 50
                    ),
                    "beta_groups_limit": integerSchema(
                        "Maximum included beta groups; requires include=betaGroups",
                        minimum: 1,
                        maximum: 50
                    ),
                    "beta_build_localizations_limit": integerSchema(
                        "Maximum included beta build localizations; requires include=betaBuildLocalizations",
                        minimum: 1,
                        maximum: 50
                    ),
                    "icons_limit": integerSchema(
                        "Maximum included icons; requires include=icons",
                        minimum: 1,
                        maximum: 50
                    ),
                    "build_bundles_limit": integerSchema(
                        "Maximum included build bundles; requires include=buildBundles",
                        minimum: 1,
                        maximum: 50
                    ),
                    "sort": enumListSchema(
                        "Sort by one or more supported build fields",
                        values: ["version", "-version", "uploadedDate", "-uploadedDate", "preReleaseVersion", "-preReleaseVersion"]
                    )
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
                    "action_id": nonEmptyStringSchema("Xcode Cloud build action ID"),
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
                    "action_id": nonEmptyStringSchema("Xcode Cloud build action ID")
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
                    "action_id": nonEmptyStringSchema("Xcode Cloud build action ID")
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
                    "action_id": nonEmptyStringSchema("Xcode Cloud build action ID")
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
                    "artifact_id": nonEmptyStringSchema("Xcode Cloud artifact ID")
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
                    "issue_id": nonEmptyStringSchema("Xcode Cloud issue ID")
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
                    "test_result_id": nonEmptyStringSchema("Xcode Cloud test result ID")
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
                    "include": includeSchema("Related resources to include", values: ["macOsVersions"]),
                    "macos_versions_limit": integerSchema(
                        "Maximum included macOS versions; requires include=macOsVersions",
                        minimum: 1,
                        maximum: 50
                    )
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
                    "xcode_version_id": nonEmptyStringSchema("Xcode version ID"),
                    "include": includeSchema("Related resources to include", values: ["macOsVersions"]),
                    "macos_versions_limit": integerSchema(
                        "Maximum included macOS versions; requires include=macOsVersions",
                        minimum: 1,
                        maximum: 50
                    )
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
                    "include": includeSchema("Related resources to include", values: ["xcodeVersions"]),
                    "xcode_versions_limit": integerSchema(
                        "Maximum included Xcode versions; requires include=xcodeVersions",
                        minimum: 1,
                        maximum: 50
                    )
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
                    "macos_version_id": nonEmptyStringSchema("macOS version ID"),
                    "include": includeSchema("Related resources to include", values: ["xcodeVersions"]),
                    "xcode_versions_limit": integerSchema(
                        "Maximum included Xcode versions; requires include=xcodeVersions",
                        minimum: 1,
                        maximum: 50
                    )
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
                    "provider_id": nonEmptyStringSchema("SCM provider ID")
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
                    "provider_id": nonEmptyStringSchema("SCM provider ID"),
                    "repository_id": identifierListSchema("Filter by one or more repository IDs"),
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
                    "repository_id": identifierListSchema("Filter by one or more repository IDs"),
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
                    "repository_id": nonEmptyStringSchema("SCM repository ID"),
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
                    "repository_id": nonEmptyStringSchema("SCM repository ID"),
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
                    "repository_id": nonEmptyStringSchema("SCM repository ID"),
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
                    "git_reference_id": nonEmptyStringSchema("SCM git reference ID"),
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
                    "pull_request_id": nonEmptyStringSchema("SCM pull request ID"),
                    "include": includeSchema("Related resources to include", values: ["repository"])
                ],
                required: ["pull_request_id"]
            )
        )
    }

    private func listProperties(_ extra: [String: Value]) -> [String: Value] {
        var properties = extra
        properties["limit"] = integerSchema("Max results (default: 25, max: 200)", minimum: 1, maximum: 200)
        properties["next_url"] = paginationURLSchema()
        return properties
    }

    private func baseSchema(properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    private func buildRunStartSchema() -> Value {
        baseSchema(
            properties: [
                "workflow_id": nonEmptyStringSchema("Workflow ID to start"),
                "build_run_id": nonEmptyStringSchema("Existing build run ID to rebuild"),
                "source_branch_or_tag_id": nonEmptyStringSchema("SCM git reference ID to build"),
                "pull_request_id": nonEmptyStringSchema("SCM pull request ID to build"),
                "clean": boolSchema("Whether Xcode Cloud should perform a clean build")
            ]
        )
    }

    private func nonEmptyStringSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string("\(description); canonical App Store Connect resource ID"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
        ])
    }

    private func paginationURLSchema() -> Value {
        .object([
            "type": .string("string"),
            "description": .string(
                "Pagination URL from a previous response. Repeat the original parent IDs, filters, include values, sort, and limit unchanged."
            ),
            "minLength": .int(1),
            "format": .string("uri-reference")
        ])
    }

    private func integerSchema(_ description: String, minimum: Int, maximum: Int) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(minimum),
            "maximum": .int(maximum)
        ])
    }

    private func boolSchema(_ description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }

    private func stringListSchema(_ description: String) -> Value {
        listSchema(description: description, item: .object(["type": .string("string"), "minLength": .int(1)]))
    }

    private func identifierListSchema(_ description: String) -> Value {
        listSchema(
            description: description,
            item: .object([
                "type": .string("string"),
                "minLength": .int(1),
                "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
            ])
        )
    }

    private func enumListSchema(_ description: String, values: [String]) -> Value {
        listSchema(
            description: description,
            item: .object([
                "type": .string("string"),
                "enum": .array(values.map(Value.string))
            ])
        )
    }

    private func booleanListSchema(_ description: String) -> Value {
        listSchema(description: description, item: .object(["type": .string("boolean")]))
    }

    private func listSchema(description: String, item: Value) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                item,
                .object([
                    "type": .string("array"),
                    "items": item,
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func includeSchema(_ description: String, values: [String]) -> Value {
        enumListSchema(description, values: values)
    }
}
