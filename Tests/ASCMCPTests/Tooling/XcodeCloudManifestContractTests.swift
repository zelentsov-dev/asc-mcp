import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Manifest Contract Tests")
struct XcodeCloudManifestContractTests {
    @Test("42 tools cover exactly 42 unique non-linkage operations")
    func exactMappingsAndOperationContracts() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let worker = try #require(
            manifest.workers.first { $0.workerKey == "xcode_cloud" }
        )
        let expected: [String: (operation: String, method: String, path: String, status: String)] = [
            "xcode_cloud_action_artifacts_list": ("ciBuildActions_artifacts_getToManyRelated", "get", "/v1/ciBuildActions/{id}/artifacts", "200"),
            "xcode_cloud_action_issues_list": ("ciBuildActions_issues_getToManyRelated", "get", "/v1/ciBuildActions/{id}/issues", "200"),
            "xcode_cloud_action_test_results_list": ("ciBuildActions_testResults_getToManyRelated", "get", "/v1/ciBuildActions/{id}/testResults", "200"),
            "xcode_cloud_actions_get": ("ciBuildActions_getInstance", "get", "/v1/ciBuildActions/{id}", "200"),
            "xcode_cloud_artifacts_get": ("ciArtifacts_getInstance", "get", "/v1/ciArtifacts/{id}", "200"),
            "xcode_cloud_build_run_actions_list": ("ciBuildRuns_actions_getToManyRelated", "get", "/v1/ciBuildRuns/{id}/actions", "200"),
            "xcode_cloud_build_run_builds_list": ("ciBuildRuns_builds_getToManyRelated", "get", "/v1/ciBuildRuns/{id}/builds", "200"),
            "xcode_cloud_build_runs_get": ("ciBuildRuns_getInstance", "get", "/v1/ciBuildRuns/{id}", "200"),
            "xcode_cloud_build_runs_start": ("ciBuildRuns_createInstance", "post", "/v1/ciBuildRuns", "201"),
            "xcode_cloud_issues_get": ("ciIssues_getInstance", "get", "/v1/ciIssues/{id}", "200"),
            "xcode_cloud_macos_versions_get": ("ciMacOsVersions_getInstance", "get", "/v1/ciMacOsVersions/{id}", "200"),
            "xcode_cloud_macos_versions_list": ("ciMacOsVersions_getCollection", "get", "/v1/ciMacOsVersions", "200"),
            "xcode_cloud_product_build_runs_list": ("ciProducts_buildRuns_getToManyRelated", "get", "/v1/ciProducts/{id}/buildRuns", "200"),
            "xcode_cloud_product_workflows_list": ("ciProducts_workflows_getToManyRelated", "get", "/v1/ciProducts/{id}/workflows", "200"),
            "xcode_cloud_products_get": ("ciProducts_getInstance", "get", "/v1/ciProducts/{id}", "200"),
            "xcode_cloud_products_list": ("ciProducts_getCollection", "get", "/v1/ciProducts", "200"),
            "xcode_cloud_scm_git_references_get": ("scmGitReferences_getInstance", "get", "/v1/scmGitReferences/{id}", "200"),
            "xcode_cloud_scm_provider_repositories_list": ("scmProviders_repositories_getToManyRelated", "get", "/v1/scmProviders/{id}/repositories", "200"),
            "xcode_cloud_scm_providers_get": ("scmProviders_getInstance", "get", "/v1/scmProviders/{id}", "200"),
            "xcode_cloud_scm_providers_list": ("scmProviders_getCollection", "get", "/v1/scmProviders", "200"),
            "xcode_cloud_scm_pull_requests_get": ("scmPullRequests_getInstance", "get", "/v1/scmPullRequests/{id}", "200"),
            "xcode_cloud_scm_repositories_get": ("scmRepositories_getInstance", "get", "/v1/scmRepositories/{id}", "200"),
            "xcode_cloud_scm_repositories_list": ("scmRepositories_getCollection", "get", "/v1/scmRepositories", "200"),
            "xcode_cloud_scm_repository_git_references_list": ("scmRepositories_gitReferences_getToManyRelated", "get", "/v1/scmRepositories/{id}/gitReferences", "200"),
            "xcode_cloud_scm_repository_pull_requests_list": ("scmRepositories_pullRequests_getToManyRelated", "get", "/v1/scmRepositories/{id}/pullRequests", "200"),
            "xcode_cloud_test_results_get": ("ciTestResults_getInstance", "get", "/v1/ciTestResults/{id}", "200"),
            "xcode_cloud_workflow_build_runs_list": ("ciWorkflows_buildRuns_getToManyRelated", "get", "/v1/ciWorkflows/{id}/buildRuns", "200"),
            "xcode_cloud_workflows_get": ("ciWorkflows_getInstance", "get", "/v1/ciWorkflows/{id}", "200"),
            "xcode_cloud_xcode_versions_get": ("ciXcodeVersions_getInstance", "get", "/v1/ciXcodeVersions/{id}", "200"),
            "xcode_cloud_xcode_versions_list": ("ciXcodeVersions_getCollection", "get", "/v1/ciXcodeVersions", "200"),
            "xcode_cloud_app_product_get": ("apps_ciProduct_getToOneRelated", "get", "/v1/apps/{id}/ciProduct", "200"),
            "xcode_cloud_action_build_run_get": ("ciBuildActions_buildRun_getToOneRelated", "get", "/v1/ciBuildActions/{id}/buildRun", "200"),
            "xcode_cloud_macos_version_xcode_versions_list": ("ciMacOsVersions_xcodeVersions_getToManyRelated", "get", "/v1/ciMacOsVersions/{id}/xcodeVersions", "200"),
            "xcode_cloud_product_additional_repositories_list": ("ciProducts_additionalRepositories_getToManyRelated", "get", "/v1/ciProducts/{id}/additionalRepositories", "200"),
            "xcode_cloud_product_app_get": ("ciProducts_app_getToOneRelated", "get", "/v1/ciProducts/{id}/app", "200"),
            "xcode_cloud_product_primary_repositories_list": ("ciProducts_primaryRepositories_getToManyRelated", "get", "/v1/ciProducts/{id}/primaryRepositories", "200"),
            "xcode_cloud_workflow_repository_get": ("ciWorkflows_repository_getToOneRelated", "get", "/v1/ciWorkflows/{id}/repository", "200"),
            "xcode_cloud_xcode_version_macos_versions_list": ("ciXcodeVersions_macOsVersions_getToManyRelated", "get", "/v1/ciXcodeVersions/{id}/macOsVersions", "200"),
            "xcode_cloud_products_delete": ("ciProducts_deleteInstance", "delete", "/v1/ciProducts/{id}", "204"),
            "xcode_cloud_workflows_create": ("ciWorkflows_createInstance", "post", "/v1/ciWorkflows", "201"),
            "xcode_cloud_workflows_update": ("ciWorkflows_updateInstance", "patch", "/v1/ciWorkflows/{id}", "200"),
            "xcode_cloud_workflows_delete": ("ciWorkflows_deleteInstance", "delete", "/v1/ciWorkflows/{id}", "204")
        ]
        let supporting: [String: [(operation: String, method: String, path: String, status: String)]] = [
            "xcode_cloud_products_delete": [
                ("ciProducts_getInstance", "get", "/v1/ciProducts/{id}", "200"),
                ("ciProducts_workflows_getToManyRelated", "get", "/v1/ciProducts/{id}/workflows", "200"),
                ("ciProducts_buildRuns_getToManyRelated", "get", "/v1/ciProducts/{id}/buildRuns", "200")
            ],
            "xcode_cloud_workflows_delete": [
                ("ciWorkflows_getInstance", "get", "/v1/ciWorkflows/{id}", "200"),
                ("ciWorkflows_buildRuns_getToManyRelated", "get", "/v1/ciWorkflows/{id}/buildRuns", "200")
            ]
        ]

        #expect(worker.tools.count == 42)
        #expect(Set(worker.tools.map(\.tool)) == Set(expected.keys))
        let workerOperations = Set(worker.tools.flatMap(\.operations).map(\.operationID))
        #expect(workerOperations.count == 42)
        #expect(workerOperations.allSatisfy { !$0.hasSuffix("Relationship") })

        for mapping in worker.tools {
            #expect(mapping.implementationState == .asBuilt)
            let contract = try #require(expected[mapping.tool])
            let operation = try #require(
                mapping.operations.first { $0.role == .primary }
            )
            let expectedSupporting = supporting[mapping.tool] ?? []
            let expectedOperations = [contract] + expectedSupporting
            #expect(mapping.operations.count == expectedOperations.count)
            #expect(Set(mapping.operations.map(\.operationID)) == Set(expectedOperations.map { $0.operation }))

            #expect(operation.operationID == contract.operation)
            #expect(operation.method == contract.method)
            #expect(operation.path == contract.path)
            #expect(mapping.response.sources.contains {
                $0.operationID == contract.operation && $0.statusCode == contract.status
            })

            for expectedOperation in expectedSupporting {
                let supportingOperation = try #require(
                    mapping.operations.first { $0.operationID == expectedOperation.operation }
                )
                #expect(supportingOperation.role == .supporting)
                #expect(supportingOperation.method == expectedOperation.method)
                #expect(supportingOperation.path == expectedOperation.path)
                #expect(mapping.response.sources.contains {
                    $0.operationID == expectedOperation.operation &&
                        $0.statusCode == expectedOperation.status
                })
            }

            switch operation.method {
            case "get":
                #expect(mapping.effect == .read)
            case "delete":
                #expect(mapping.effect == .destructive)
            default:
                #expect(mapping.effect == .write)
            }
        }

        #expect(Set(manifest.tools.flatMap(\.operations).map(\.operationID)).count == 476)
        #expect(manifest.index.waivers.count == 424)
        #expect(476 + 424 + 363 == manifest.index.specPin.operationCount)
    }

    @Test("19 linkage-only waivers name their typed functional supersets")
    func exactLinkageWaivers() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let replacements: [String: String] = [
            "apps_ciProduct_getToOneRelationship": "xcode_cloud_app_product_get",
            "ciBuildActions_artifacts_getToManyRelationship": "xcode_cloud_action_artifacts_list",
            "ciBuildActions_buildRun_getToOneRelationship": "xcode_cloud_action_build_run_get",
            "ciBuildActions_issues_getToManyRelationship": "xcode_cloud_action_issues_list",
            "ciBuildActions_testResults_getToManyRelationship": "xcode_cloud_action_test_results_list",
            "ciBuildRuns_actions_getToManyRelationship": "xcode_cloud_build_run_actions_list",
            "ciBuildRuns_builds_getToManyRelationship": "xcode_cloud_build_run_builds_list",
            "ciMacOsVersions_xcodeVersions_getToManyRelationship": "xcode_cloud_macos_version_xcode_versions_list",
            "ciProducts_additionalRepositories_getToManyRelationship": "xcode_cloud_product_additional_repositories_list",
            "ciProducts_app_getToOneRelationship": "xcode_cloud_product_app_get",
            "ciProducts_buildRuns_getToManyRelationship": "xcode_cloud_product_build_runs_list",
            "ciProducts_primaryRepositories_getToManyRelationship": "xcode_cloud_product_primary_repositories_list",
            "ciProducts_workflows_getToManyRelationship": "xcode_cloud_product_workflows_list",
            "ciWorkflows_buildRuns_getToManyRelationship": "xcode_cloud_workflow_build_runs_list",
            "ciWorkflows_repository_getToOneRelationship": "xcode_cloud_workflow_repository_get",
            "ciXcodeVersions_macOsVersions_getToManyRelationship": "xcode_cloud_xcode_version_macos_versions_list",
            "scmProviders_repositories_getToManyRelationship": "xcode_cloud_scm_provider_repositories_list",
            "scmRepositories_gitReferences_getToManyRelationship": "xcode_cloud_scm_repository_git_references_list",
            "scmRepositories_pullRequests_getToManyRelationship": "xcode_cloud_scm_repository_pull_requests_list"
        ]
        let linkagePrefixes = [
            "ciBuildActions_", "ciBuildRuns_", "ciMacOsVersions_", "ciProducts_",
            "ciWorkflows_", "ciXcodeVersions_", "scmProviders_", "scmRepositories_"
        ]
        let linkageWaivers = manifest.index.waivers.filter { waiver in
            guard let operation = waiver.operationID, operation.hasSuffix("Relationship") else {
                return false
            }
            return operation == "apps_ciProduct_getToOneRelationship" ||
                linkagePrefixes.contains { operation.hasPrefix($0) }
        }
        let worker = try #require(
            manifest.workers.first { $0.workerKey == "xcode_cloud" }
        )
        let mapped = Set(worker.tools.flatMap(\.operations).map(\.operationID))
        let waived = Set(linkageWaivers.compactMap(\.operationID))

        #expect(linkageWaivers.count == 19)
        #expect(waived == Set(replacements.keys))
        #expect(mapped.isDisjoint(with: waived))
        #expect(mapped.union(waived).count == 61)

        for waiver in linkageWaivers {
            let operation = try #require(waiver.operationID)
            let replacement = try #require(replacements[operation])
            #expect(waiver.disposition == .deferred)
            #expect(waiver.reason.contains("ID-only linkage endpoint"))
            #expect(waiver.reason.contains("functional superset"))
            #expect(waiver.reason.contains(replacement))
            #expect(!waiver.reason.contains("not yet exposed"))
        }

        #expect(manifest.index.waivers.allSatisfy { waiver in
            waiver.operationID.map { !mapped.contains($0) } ?? true
        })
    }

    @Test("optional inputs and recovery lineage remain explicit")
    func optionalInputsAndRecoveryLineage() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let buildRunBuilds = try #require(
            manifest.mapping(for: "xcode_cloud_build_run_builds_list")
        )
        let buildRunFields = Dictionary(
            uniqueKeysWithValues: buildRunBuilds.fields.compactMap { field in
                field.appleName.map { (field.toolField, $0) }
            }
        )
        #expect(buildRunFields["include"] == "include")
        #expect(buildRunFields["individual_testers_limit"] == "limit[individualTesters]")
        #expect(buildRunFields["beta_groups_limit"] == "limit[betaGroups]")
        #expect(buildRunFields["beta_build_localizations_limit"] == "limit[betaBuildLocalizations]")
        #expect(buildRunFields["icons_limit"] == "limit[icons]")
        #expect(buildRunFields["build_bundles_limit"] == "limit[buildBundles]")
        #expect(buildRunBuilds.operations.first?.optionalParameterClassifications?.isEmpty != false)

        let relationshipLimits: [String: (field: String, appleName: String)] = [
            "xcode_cloud_products_list": ("primary_repositories_limit", "limit[primaryRepositories]"),
            "xcode_cloud_products_get": ("primary_repositories_limit", "limit[primaryRepositories]"),
            "xcode_cloud_product_build_runs_list": ("builds_limit", "limit[builds]"),
            "xcode_cloud_workflow_build_runs_list": ("builds_limit", "limit[builds]"),
            "xcode_cloud_build_runs_get": ("builds_limit", "limit[builds]"),
            "xcode_cloud_xcode_versions_list": ("macos_versions_limit", "limit[macOsVersions]"),
            "xcode_cloud_xcode_versions_get": ("macos_versions_limit", "limit[macOsVersions]"),
            "xcode_cloud_macos_versions_list": ("xcode_versions_limit", "limit[xcodeVersions]"),
            "xcode_cloud_macos_versions_get": ("xcode_versions_limit", "limit[xcodeVersions]")
        ]
        for (tool, expected) in relationshipLimits {
            let mapping = try #require(manifest.mapping(for: tool))
            let binding = try #require(
                mapping.fields.first { $0.toolField == expected.field }
            )
            #expect(binding.appleName == expected.appleName)
            #expect(mapping.operations.first?.optionalParameterClassifications?.contains {
                $0.appleName == expected.appleName
            } != true)
        }

        let productApp = try #require(
            manifest.mapping(for: "xcode_cloud_product_app_get")
        )
        let productAppOmissions = Set(
            productApp.operations.flatMap { $0.optionalParameterClassifications ?? [] }
                .map(\.appleName)
        )
        #expect(productAppOmissions.count == 19)
        #expect(productAppOmissions.contains("include"))
        #expect(productAppOmissions.contains("limit[androidToIosAppMappingDetails]"))
        #expect(productAppOmissions.allSatisfy { !$0.hasPrefix("fields[") })
        #expect(productApp.note?.contains("existing typed app/domain tools") == true)

        let buildRunStart = try #require(
            manifest.mapping(for: "xcode_cloud_build_runs_start")
        )
        #expect(buildRunStart.fields.first { $0.toolField == "clean" }?.localRole?.contains(
            "intentionally omitted"
        ) == true)

        let update = try #require(
            manifest.mapping(for: "xcode_cloud_workflows_update")
        )
        let nullableUpdateFields: Set<String> = [
            "name", "description", "branch_start_condition", "tag_start_condition",
            "pull_request_start_condition", "scheduled_start_condition",
            "manual_branch_start_condition", "manual_tag_start_condition",
            "manual_pull_request_start_condition", "actions", "is_enabled",
            "is_locked_for_editing", "clean", "container_file_path"
        ]
        for field in update.fields where nullableUpdateFields.contains(field.toolField) {
            #expect(field.localRole?.contains("explicit JSON null") == true)
            #expect(field.localRole?.contains("omission") == true)
        }
        #expect(Set(update.fields.map(\.toolField)).isSuperset(of: nullableUpdateFields))

        for tool in ["xcode_cloud_products_delete", "xcode_cloud_workflows_delete"] {
            let deletion = try #require(manifest.mapping(for: tool))
            #expect(deletion.effect == .destructive)
            #expect(deletion.note?.contains("two-step safety contract") == true)
            #expect(deletion.note?.contains("exact sorted length-delimited") == true)
            #expect(deletion.note?.contains("never replayed automatically") == true)
            #expect(Set(deletion.response.fields.map(\.outputField)).isSuperset(of: [
                "previewOnly", "confirmation", "operationCommitState",
                "inspectionRequired", "inspection", "retrySafe", "statusCode"
            ]))
        }

        let productDelete = try #require(
            manifest.mapping(for: "xcode_cloud_products_delete")
        )
        #expect(productDelete.kind == .compound)
        #expect(productDelete.operations.count == 4)
        #expect(Set(productDelete.operations.map(\.operationID)) == Set([
            "ciProducts_getInstance", "ciProducts_workflows_getToManyRelated",
            "ciProducts_buildRuns_getToManyRelated", "ciProducts_deleteInstance"
        ]))
        #expect(Set(productDelete.fields.filter { $0.toolField == "product_id" }
            .compactMap(\.operationID)) == Set(productDelete.operations.map(\.operationID)))

        let workflowDelete = try #require(
            manifest.mapping(for: "xcode_cloud_workflows_delete")
        )
        #expect(workflowDelete.kind == .compound)
        #expect(workflowDelete.operations.count == 3)
        #expect(Set(workflowDelete.operations.map(\.operationID)) == Set([
            "ciWorkflows_getInstance", "ciWorkflows_buildRuns_getToManyRelated",
            "ciWorkflows_deleteInstance"
        ]))
        #expect(Set(workflowDelete.fields.filter { $0.toolField == "workflow_id" }
            .compactMap(\.operationID)) == Set(workflowDelete.operations.map(\.operationID)))

        for (mapping, operationID, sparseName, sparseValue) in [
            (productDelete, "ciProducts_workflows_getToManyRelated", "fields[ciWorkflows]", "name"),
            (productDelete, "ciProducts_buildRuns_getToManyRelated", "fields[ciBuildRuns]", "number"),
            (workflowDelete, "ciWorkflows_buildRuns_getToManyRelated", "fields[ciBuildRuns]", "number")
        ] {
            let operation = try #require(
                mapping.operations.first { $0.operationID == operationID }
            )
            let inputs = operation.inputs ?? []
            #expect(inputs.first { $0.appleName == "limit" }?.fixedValue == .integer(200))
            #expect(inputs.first { $0.appleName == sparseName }?.fixedValue == .array([.string(sparseValue)]))
        }

        for tool in ["xcode_cloud_workflows_create", "xcode_cloud_workflows_update"] {
            let mutation = try #require(manifest.mapping(for: tool))
            let responseFields = Dictionary(
                uniqueKeysWithValues: mutation.response.fields.map { ($0.outputField, $0) }
            )
            #expect(responseFields["self_url"]?.jsonPointer == "/links/self")
            #expect(responseFields["included"]?.jsonPointer == "/included")
            #expect(responseFields["included"]?.localRole?.contains("including an empty array") == true)
        }

        let pin = try #require(manifest.index.optionalInputCoveragePin)
        #expect(pin.total == 2_905)
        #expect(pin.bound == 1_122)
        #expect(pin.internalControl == 40)
        #expect(pin.intentionallyOmitted == 1_743)
        #expect(pin.unclassified == 0)
        #expect(pin.identitySHA256 == "c975f4e4eebb62ec87864a73fbf72bb8841f644108e54e6ffb25168bcf2a2766")
    }

    @Test("selected projections distinguish relationship self from related URLs")
    func relationshipURLProjectionContracts() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expected: [String: Set<String>] = [
            "xcode_cloud_actions_get": [
                "action.buildRunRelationshipUrl", "action.artifactsRelationshipUrl",
                "action.issuesRelationshipUrl", "action.testResultsRelationshipUrl"
            ],
            "xcode_cloud_build_run_actions_list": [
                "actions.*.buildRunRelationshipUrl", "actions.*.artifactsRelationshipUrl",
                "actions.*.issuesRelationshipUrl", "actions.*.testResultsRelationshipUrl"
            ],
            "xcode_cloud_build_run_builds_list": [
                "builds.*.preReleaseVersionRelationshipUrl",
                "builds.*.individualTestersRelationshipUrl",
                "builds.*.betaGroupsRelationshipUrl",
                "builds.*.betaBuildLocalizationsRelationshipUrl",
                "builds.*.appEncryptionDeclarationRelationshipUrl",
                "builds.*.betaAppReviewSubmissionRelationshipUrl",
                "builds.*.appRelationshipUrl",
                "builds.*.buildBetaDetailRelationshipUrl",
                "builds.*.appStoreVersionRelationshipUrl",
                "builds.*.iconsRelationshipUrl",
                "builds.*.diagnosticSignaturesRelationshipUrl"
            ],
            "xcode_cloud_build_runs_get": [
                "buildRun.buildsRelationshipUrl", "buildRun.actionsRelationshipUrl"
            ],
            "xcode_cloud_build_runs_start": [
                "buildRun.buildsRelationshipUrl", "buildRun.actionsRelationshipUrl"
            ],
            "xcode_cloud_macos_versions_get": [
                "macOSVersion.xcodeVersionsRelationshipUrl"
            ],
            "xcode_cloud_macos_versions_list": [
                "macOSVersions.*.xcodeVersionsRelationshipUrl"
            ],
            "xcode_cloud_product_build_runs_list": [
                "buildRuns.*.buildsRelationshipUrl", "buildRuns.*.actionsRelationshipUrl"
            ],
            "xcode_cloud_product_workflows_list": [
                "workflows.*.repositoryRelationshipUrl", "workflows.*.buildRunsRelationshipUrl"
            ],
            "xcode_cloud_products_get": [
                "product.appRelationshipUrl", "product.workflowsRelationshipUrl",
                "product.primaryRepositoriesRelationshipUrl",
                "product.additionalRepositoriesRelationshipUrl",
                "product.buildRunsRelationshipUrl"
            ],
            "xcode_cloud_products_list": [
                "products.*.appRelationshipUrl", "products.*.workflowsRelationshipUrl",
                "products.*.primaryRepositoriesRelationshipUrl",
                "products.*.additionalRepositoriesRelationshipUrl",
                "products.*.buildRunsRelationshipUrl"
            ],
            "xcode_cloud_scm_provider_repositories_list": [
                "repositories.*.gitReferencesRelationshipUrl",
                "repositories.*.pullRequestsRelationshipUrl"
            ],
            "xcode_cloud_scm_providers_get": [
                "provider.repositoriesRelationshipUrl"
            ],
            "xcode_cloud_scm_providers_list": [
                "providers.*.repositoriesRelationshipUrl"
            ],
            "xcode_cloud_scm_repositories_get": [
                "repository.gitReferencesRelationshipUrl",
                "repository.pullRequestsRelationshipUrl"
            ],
            "xcode_cloud_scm_repositories_list": [
                "repositories.*.gitReferencesRelationshipUrl",
                "repositories.*.pullRequestsRelationshipUrl"
            ],
            "xcode_cloud_workflow_build_runs_list": [
                "buildRuns.*.buildsRelationshipUrl", "buildRuns.*.actionsRelationshipUrl"
            ],
            "xcode_cloud_workflows_get": [
                "workflow.repositoryRelationshipUrl", "workflow.buildRunsRelationshipUrl"
            ],
            "xcode_cloud_xcode_versions_get": [
                "xcodeVersion.macOSVersionsRelationshipUrl"
            ],
            "xcode_cloud_xcode_versions_list": [
                "xcodeVersions.*.macOSVersionsRelationshipUrl"
            ],
            "xcode_cloud_app_product_get": [
                "product.appRelationshipUrl", "product.workflowsRelationshipUrl",
                "product.primaryRepositoriesRelationshipUrl",
                "product.additionalRepositoriesRelationshipUrl",
                "product.buildRunsRelationshipUrl"
            ],
            "xcode_cloud_action_build_run_get": [
                "buildRun.buildsRelationshipUrl", "buildRun.actionsRelationshipUrl"
            ],
            "xcode_cloud_macos_version_xcode_versions_list": [
                "xcodeVersions.*.macOSVersionsRelationshipUrl"
            ],
            "xcode_cloud_product_additional_repositories_list": [
                "repositories.*.gitReferencesRelationshipUrl",
                "repositories.*.pullRequestsRelationshipUrl"
            ],
            "xcode_cloud_product_primary_repositories_list": [
                "repositories.*.gitReferencesRelationshipUrl",
                "repositories.*.pullRequestsRelationshipUrl"
            ],
            "xcode_cloud_workflow_repository_get": [
                "repository.gitReferencesRelationshipUrl",
                "repository.pullRequestsRelationshipUrl"
            ],
            "xcode_cloud_xcode_version_macos_versions_list": [
                "macOSVersions.*.xcodeVersionsRelationshipUrl"
            ]
        ]

        for (tool, expectedFields) in expected {
            let mapping = try #require(manifest.mapping(for: tool))
            let actualFields = Set(mapping.response.fields.map(\.outputField))
            #expect(actualFields.isSuperset(of: expectedFields), "Missing relationship URL projection for \(tool)")
            #expect(mapping.note?.contains("no MCP output schema") == true)

            for field in mapping.response.fields where expectedFields.contains(field.outputField) {
                #expect(field.jsonPointer?.hasSuffix("/links/self") == true)
                #expect(field.localRole?.contains("related-resource URL") == true)
            }
        }

        let start = try #require(manifest.mapping(for: "xcode_cloud_build_runs_start"))
        let included = try #require(
            start.response.fields.first { $0.outputField == "included" }
        )
        #expect(included.jsonPointer == "/included")
        #expect(included.localRole?.contains("validated non-empty") == true)

        let buildList = try #require(
            manifest.mapping(for: "xcode_cloud_build_run_builds_list")
        )
        let buildFields = Dictionary(
            uniqueKeysWithValues: buildList.response.fields.map { ($0.outputField, $0) }
        )
        #expect(buildFields["builds.*.perfPowerMetricsRelationshipUrl"]?.jsonPointer == nil)
        #expect(buildFields["builds.*.perfPowerMetricsRelationshipUrl"]?.localRole?.contains(
            "no links.self"
        ) == true)
        for compatibilityKey in ["builds.*.buildBundlesUrl", "builds.*.buildUploadUrl"] {
            #expect(buildFields[compatibilityKey]?.jsonPointer == nil)
            #expect(buildFields[compatibilityKey]?.localRole?.contains("no links object") == true)
        }
    }
}
