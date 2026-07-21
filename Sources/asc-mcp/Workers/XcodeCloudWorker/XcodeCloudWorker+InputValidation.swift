import Foundation
import MCP

extension XcodeCloudWorker {
    func existingToolInputError(_ params: CallTool.Parameters) -> CallTool.Result? {
        guard Self.existingToolAllowedArguments[params.name] != nil else {
            return nil
        }

        do {
            try validateExistingToolInput(params)
            return nil
        } catch {
            return MCPResult.error("Invalid Xcode Cloud arguments: \(error.localizedDescription)")
        }
    }

    private func validateExistingToolInput(_ params: CallTool.Parameters) throws {
        let arguments = params.arguments ?? [:]
        let allowed = Self.existingToolAllowedArguments[params.name] ?? []
        let unknown = Set(arguments.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw XcodeCloudInputValidationError(
                "Unsupported parameter\(unknown.count == 1 ? "" : "s"): \(unknown.joined(separator: ", "))"
            )
        }

        for name in Self.requiredCanonicalIDs[params.name] ?? [] {
            try validateCanonicalID(arguments[name], name: name, required: true)
        }
        for name in Self.optionalCanonicalIDs[params.name] ?? [] where arguments[name] != nil {
            try validateCanonicalID(arguments[name], name: name, required: false)
        }

        if let value = arguments["limit"] {
            try validateInteger(value, name: "limit", range: 1...200)
        }
        for name in [
            "primary_repositories_limit",
            "builds_limit",
            "macos_versions_limit",
            "xcode_versions_limit",
            "individual_testers_limit",
            "beta_groups_limit",
            "beta_build_localizations_limit",
            "icons_limit",
            "build_bundles_limit"
        ] where arguments[name] != nil {
            try validateInteger(arguments[name], name: name, range: 1...50)
        }
        if let value = arguments["next_url"] {
            guard let string = value.stringValue,
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcodeCloudInputValidationError("next_url must be a non-empty URI reference")
            }
        }

        if let values = Self.includeValues[params.name] {
            try validateStringList(arguments["include"], name: "include", allowedValues: values)
        }
        if arguments["include"] != nil, Self.includeValues[params.name] == nil {
            throw XcodeCloudInputValidationError("include is not supported by \(params.name)")
        }
        try validateRelationshipLimits(arguments)

        switch params.name {
        case "xcode_cloud_products_list":
            try validateStringList(arguments["product_type"], name: "product_type", allowedValues: ["APP", "FRAMEWORK"])
            try validateStringList(arguments["app_id"], name: "app_id", canonicalIDs: true)
        case "xcode_cloud_product_build_runs_list", "xcode_cloud_workflow_build_runs_list":
            try validateStringList(arguments["build_id"], name: "build_id", canonicalIDs: true)
            try validateStringList(arguments["sort"], name: "sort", allowedValues: ["number", "-number"])
        case "xcode_cloud_build_runs_start":
            try validateStartBuildArguments(arguments)
        case "xcode_cloud_build_run_builds_list":
            try validateBuildCollectionArguments(arguments)
        case "xcode_cloud_scm_provider_repositories_list", "xcode_cloud_scm_repositories_list":
            try validateStringList(arguments["repository_id"], name: "repository_id", canonicalIDs: true)
        default:
            break
        }
    }

    private func validateStartBuildArguments(_ arguments: [String: Value]) throws {
        let workflowPresent = arguments["workflow_id"] != nil
        let buildRunPresent = arguments["build_run_id"] != nil
        guard workflowPresent != buildRunPresent else {
            throw XcodeCloudInputValidationError("Provide exactly one of workflow_id or build_run_id")
        }
        guard !(arguments["source_branch_or_tag_id"] != nil && arguments["pull_request_id"] != nil) else {
            throw XcodeCloudInputValidationError(
                "Use only one source selector: source_branch_or_tag_id or pull_request_id"
            )
        }
        if let clean = arguments["clean"], clean.boolValue == nil {
            throw XcodeCloudInputValidationError("clean must be a boolean")
        }
    }

    private func validateBuildCollectionArguments(_ arguments: [String: Value]) throws {
        try validateStringList(arguments["version"], name: "version")
        try validateBooleanList(arguments["expired"], name: "expired")
        try validateStringList(
            arguments["processing_state"],
            name: "processing_state",
            allowedValues: ["PROCESSING", "FAILED", "INVALID", "VALID"]
        )
        try validateStringList(
            arguments["beta_review_states"],
            name: "beta_review_states",
            allowedValues: ["WAITING_FOR_REVIEW", "IN_REVIEW", "REJECTED", "APPROVED"]
        )
        try validateBooleanList(arguments["uses_non_exempt_encryption"], name: "uses_non_exempt_encryption")
        try validateStringList(arguments["pre_release_versions"], name: "pre_release_versions")
        try validateStringList(
            arguments["pre_release_platforms"],
            name: "pre_release_platforms",
            allowedValues: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
        )
        try validateStringList(
            arguments["build_audience_types"],
            name: "build_audience_types",
            allowedValues: ["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"]
        )
        for name in [
            "pre_release_version_ids",
            "app_ids",
            "beta_group_ids",
            "app_store_version_ids",
            "build_ids"
        ] {
            try validateStringList(arguments[name], name: name, canonicalIDs: true)
        }
        if let value = arguments["uses_non_exempt_encryption_set"], value.boolValue == nil {
            throw XcodeCloudInputValidationError("uses_non_exempt_encryption_set must be a boolean")
        }
        try validateStringList(
            arguments["sort"],
            name: "sort",
            allowedValues: [
                "version", "-version", "uploadedDate", "-uploadedDate",
                "preReleaseVersion", "-preReleaseVersion"
            ]
        )
    }

    private func validateCanonicalID(_ value: Value?, name: String, required: Bool) throws {
        guard let value else {
            if required {
                throw XcodeCloudInputValidationError("Required parameter '\(name)' is missing")
            }
            return
        }
        guard let id = value.stringValue else {
            throw XcodeCloudInputValidationError("\(name) must be a string")
        }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == id else {
            throw XcodeCloudInputValidationError("\(name) must be a non-empty canonical identifier")
        }
        guard try ASCPathSegment.encode(id, field: name) == id else {
            throw XcodeCloudInputValidationError("\(name) must be a canonical identifier")
        }
    }

    private func validateInteger(_ value: Value?, name: String, range: ClosedRange<Int>) throws {
        guard let value, let integer = value.intValue, range.contains(integer) else {
            throw XcodeCloudInputValidationError("\(name) must be an integer in \(range.lowerBound)...\(range.upperBound)")
        }
    }

    private func validateStringList(
        _ value: Value?,
        name: String,
        allowedValues: Set<String>? = nil,
        canonicalIDs: Bool = false
    ) throws {
        guard let value else { return }
        let strings: [String]
        if let string = value.stringValue {
            strings = [string]
        } else if let array = value.arrayValue,
                  !array.isEmpty,
                  array.allSatisfy({ $0.stringValue != nil }) {
            strings = array.compactMap(\.stringValue)
        } else {
            throw XcodeCloudInputValidationError("\(name) must be a non-empty string or array of strings")
        }
        guard strings.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.contains(",")
        }), Set(strings).count == strings.count else {
            throw XcodeCloudInputValidationError("\(name) must contain unique non-empty values without commas")
        }
        if let allowedValues, let unsupported = strings.first(where: { !allowedValues.contains($0) }) {
            throw XcodeCloudInputValidationError("\(name) contains unsupported value '\(unsupported)'")
        }
        if canonicalIDs {
            for string in strings {
                guard try ASCPathSegment.encode(string, field: name) == string else {
                    throw XcodeCloudInputValidationError("\(name) must contain canonical identifiers")
                }
            }
        }
    }

    private func validateBooleanList(_ value: Value?, name: String) throws {
        guard let value else { return }
        let booleans: [Bool]
        if let boolean = value.boolValue {
            booleans = [boolean]
        } else if let array = value.arrayValue,
                  !array.isEmpty,
                  array.allSatisfy({ $0.boolValue != nil }) {
            booleans = array.compactMap(\.boolValue)
        } else {
            throw XcodeCloudInputValidationError("\(name) must be a boolean or non-empty array of booleans")
        }
        guard Set(booleans).count == booleans.count else {
            throw XcodeCloudInputValidationError("\(name) must contain unique values")
        }
    }

    private func validateRelationshipLimits(_ arguments: [String: Value]) throws {
        let requirements = [
            "primary_repositories_limit": "primaryRepositories",
            "builds_limit": "builds",
            "macos_versions_limit": "macOsVersions",
            "xcode_versions_limit": "xcodeVersions",
            "individual_testers_limit": "individualTesters",
            "beta_groups_limit": "betaGroups",
            "beta_build_localizations_limit": "betaBuildLocalizations",
            "icons_limit": "icons",
            "build_bundles_limit": "buildBundles"
        ]
        let includes: Set<String>
        if let include = arguments["include"] {
            if let string = include.stringValue {
                includes = [string]
            } else {
                includes = Set(include.arrayValue?.compactMap(\.stringValue) ?? [])
            }
        } else {
            includes = []
        }

        for (limit, relationship) in requirements where arguments[limit] != nil {
            guard includes.contains(relationship) else {
                throw XcodeCloudInputValidationError(
                    "\(limit) requires include to contain '\(relationship)'"
                )
            }
        }
    }

    private static let commonListArguments: Set<String> = ["limit", "next_url"]

    private static let existingToolAllowedArguments: [String: Set<String>] = [
        "xcode_cloud_products_list": commonListArguments.union([
            "product_type", "app_id", "include", "primary_repositories_limit"
        ]),
        "xcode_cloud_products_get": ["product_id", "include", "primary_repositories_limit"],
        "xcode_cloud_product_workflows_list": commonListArguments.union(["product_id", "include"]),
        "xcode_cloud_product_build_runs_list": commonListArguments.union([
            "product_id", "build_id", "sort", "include", "builds_limit"
        ]),
        "xcode_cloud_workflows_get": ["workflow_id", "include"],
        "xcode_cloud_workflow_build_runs_list": commonListArguments.union([
            "workflow_id", "build_id", "sort", "include", "builds_limit"
        ]),
        "xcode_cloud_build_runs_get": ["build_run_id", "include", "builds_limit"],
        "xcode_cloud_build_runs_start": [
            "workflow_id", "build_run_id", "source_branch_or_tag_id", "pull_request_id", "clean"
        ],
        "xcode_cloud_build_run_actions_list": commonListArguments.union(["build_run_id", "include"]),
        "xcode_cloud_build_run_builds_list": commonListArguments.union([
            "build_run_id", "version", "expired", "processing_state", "beta_review_states",
            "uses_non_exempt_encryption", "pre_release_versions", "pre_release_platforms",
            "build_audience_types", "pre_release_version_ids", "app_ids", "beta_group_ids",
            "app_store_version_ids", "build_ids", "uses_non_exempt_encryption_set", "sort", "include",
            "individual_testers_limit", "beta_groups_limit", "beta_build_localizations_limit",
            "icons_limit", "build_bundles_limit"
        ]),
        "xcode_cloud_actions_get": ["action_id", "include"],
        "xcode_cloud_action_artifacts_list": commonListArguments.union(["action_id"]),
        "xcode_cloud_action_issues_list": commonListArguments.union(["action_id"]),
        "xcode_cloud_action_test_results_list": commonListArguments.union(["action_id"]),
        "xcode_cloud_artifacts_get": ["artifact_id"],
        "xcode_cloud_issues_get": ["issue_id"],
        "xcode_cloud_test_results_get": ["test_result_id"],
        "xcode_cloud_xcode_versions_list": commonListArguments.union(["include", "macos_versions_limit"]),
        "xcode_cloud_xcode_versions_get": ["xcode_version_id", "include", "macos_versions_limit"],
        "xcode_cloud_macos_versions_list": commonListArguments.union(["include", "xcode_versions_limit"]),
        "xcode_cloud_macos_versions_get": ["macos_version_id", "include", "xcode_versions_limit"],
        "xcode_cloud_scm_providers_list": commonListArguments,
        "xcode_cloud_scm_providers_get": ["provider_id"],
        "xcode_cloud_scm_provider_repositories_list": commonListArguments.union(["provider_id", "repository_id", "include"]),
        "xcode_cloud_scm_repositories_list": commonListArguments.union(["repository_id", "include"]),
        "xcode_cloud_scm_repositories_get": ["repository_id", "include"],
        "xcode_cloud_scm_repository_git_references_list": commonListArguments.union(["repository_id", "include"]),
        "xcode_cloud_scm_repository_pull_requests_list": commonListArguments.union(["repository_id", "include"]),
        "xcode_cloud_scm_git_references_get": ["git_reference_id", "include"],
        "xcode_cloud_scm_pull_requests_get": ["pull_request_id", "include"]
    ]

    private static let requiredCanonicalIDs: [String: Set<String>] = [
        "xcode_cloud_products_get": ["product_id"],
        "xcode_cloud_product_workflows_list": ["product_id"],
        "xcode_cloud_product_build_runs_list": ["product_id"],
        "xcode_cloud_workflows_get": ["workflow_id"],
        "xcode_cloud_workflow_build_runs_list": ["workflow_id"],
        "xcode_cloud_build_runs_get": ["build_run_id"],
        "xcode_cloud_build_run_actions_list": ["build_run_id"],
        "xcode_cloud_build_run_builds_list": ["build_run_id"],
        "xcode_cloud_actions_get": ["action_id"],
        "xcode_cloud_action_artifacts_list": ["action_id"],
        "xcode_cloud_action_issues_list": ["action_id"],
        "xcode_cloud_action_test_results_list": ["action_id"],
        "xcode_cloud_artifacts_get": ["artifact_id"],
        "xcode_cloud_issues_get": ["issue_id"],
        "xcode_cloud_test_results_get": ["test_result_id"],
        "xcode_cloud_xcode_versions_get": ["xcode_version_id"],
        "xcode_cloud_macos_versions_get": ["macos_version_id"],
        "xcode_cloud_scm_providers_get": ["provider_id"],
        "xcode_cloud_scm_provider_repositories_list": ["provider_id"],
        "xcode_cloud_scm_repositories_get": ["repository_id"],
        "xcode_cloud_scm_repository_git_references_list": ["repository_id"],
        "xcode_cloud_scm_repository_pull_requests_list": ["repository_id"],
        "xcode_cloud_scm_git_references_get": ["git_reference_id"],
        "xcode_cloud_scm_pull_requests_get": ["pull_request_id"]
    ]

    private static let optionalCanonicalIDs: [String: Set<String>] = [
        "xcode_cloud_build_runs_start": [
            "workflow_id", "build_run_id", "source_branch_or_tag_id", "pull_request_id"
        ]
    ]

    private static let includeValues: [String: Set<String>] = [
        "xcode_cloud_products_list": ["app", "bundleId", "primaryRepositories"],
        "xcode_cloud_products_get": ["app", "bundleId", "primaryRepositories"],
        "xcode_cloud_product_workflows_list": ["product", "repository", "xcodeVersion", "macOsVersion"],
        "xcode_cloud_product_build_runs_list": [
            "builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"
        ],
        "xcode_cloud_workflows_get": ["product", "repository", "xcodeVersion", "macOsVersion"],
        "xcode_cloud_workflow_build_runs_list": [
            "builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"
        ],
        "xcode_cloud_build_runs_get": [
            "builds", "workflow", "product", "sourceBranchOrTag", "destinationBranch", "pullRequest"
        ],
        "xcode_cloud_build_run_actions_list": ["buildRun"],
        "xcode_cloud_build_run_builds_list": [
            "preReleaseVersion", "individualTesters", "betaGroups", "betaBuildLocalizations",
            "appEncryptionDeclaration", "betaAppReviewSubmission", "app", "buildBetaDetail",
            "appStoreVersion", "icons", "buildBundles", "buildUpload"
        ],
        "xcode_cloud_actions_get": ["buildRun"],
        "xcode_cloud_xcode_versions_list": ["macOsVersions"],
        "xcode_cloud_xcode_versions_get": ["macOsVersions"],
        "xcode_cloud_macos_versions_list": ["xcodeVersions"],
        "xcode_cloud_macos_versions_get": ["xcodeVersions"],
        "xcode_cloud_scm_provider_repositories_list": ["scmProvider", "defaultBranch"],
        "xcode_cloud_scm_repositories_list": ["scmProvider", "defaultBranch"],
        "xcode_cloud_scm_repositories_get": ["scmProvider", "defaultBranch"],
        "xcode_cloud_scm_repository_git_references_list": ["repository"],
        "xcode_cloud_scm_repository_pull_requests_list": ["repository"],
        "xcode_cloud_scm_git_references_get": ["repository"],
        "xcode_cloud_scm_pull_requests_get": ["repository"]
    ]
}

private struct XcodeCloudInputValidationError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
