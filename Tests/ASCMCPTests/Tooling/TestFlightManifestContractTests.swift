import MCP
import Testing
@testable import asc_mcp

@Suite("TestFlight Manifest Contract Tests")
struct TestFlightManifestContractTests {
    @Test("eleven tools map exactly twelve TestFlight operations")
    func exactMappingsAndCoverage() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expected: [String: Set<String>] = [
            "beta_groups_get_recruitment_criteria": [
                "betaGroups_getInstance",
                "betaGroups_betaRecruitmentCriteria_getToOneRelated"
            ],
            "beta_groups_create_recruitment_criteria": [
                "betaGroups_getInstance",
                "betaGroups_betaRecruitmentCriteria_getToOneRelated",
                "betaRecruitmentCriteria_createInstance"
            ],
            "beta_groups_update_recruitment_criteria": [
                "betaGroups_getInstance",
                "betaGroups_betaRecruitmentCriteria_getToOneRelated",
                "betaRecruitmentCriteria_updateInstance"
            ],
            "beta_groups_delete_recruitment_criteria": [
                "betaGroups_getInstance",
                "betaGroups_betaRecruitmentCriteria_getToOneRelated",
                "betaRecruitmentCriteria_deleteInstance"
            ],
            "beta_groups_list_recruitment_options": [
                "betaRecruitmentCriterionOptions_getCollection"
            ],
            "beta_groups_check_recruitment_compatibility": [
                "betaGroups_getInstance",
                "betaGroups_betaRecruitmentCriterionCompatibleBuildCheck_getToOneRelated"
            ],
            "metrics_app_beta_tester_usage": ["apps_betaTesterUsages_getMetrics"],
            "metrics_group_beta_tester_usage": ["betaGroups_betaTesterUsages_getMetrics"],
            "metrics_group_public_link_usage": ["betaGroups_publicLinkUsages_getMetrics"],
            "metrics_tester_usage": ["betaTesters_betaTesterUsages_getMetrics"],
            "metrics_build_beta_usage": ["builds_betaBuildUsages_getMetrics"]
        ]

        for (tool, operations) in expected {
            let mapping = try #require(manifest.mapping(for: tool))
            #expect(mapping.implementationState == .asBuilt)
            #expect(Set(mapping.operations.map(\.operationID)) == operations)
        }

        let mapped = Set(manifest.tools.flatMap(\.operations).map(\.operationID))
        let testFlightOperations = Set(expected.values.flatMap { $0 })
        #expect(testFlightOperations.count == 12)
        #expect(testFlightOperations.isSubset(of: mapped))
        #expect(mapped.count == 476)
        #expect(manifest.index.waivers.count == 424)
        #expect(476 + 424 + 363 == manifest.index.specPin.operationCount)

        let recruitmentWaivers = Set(
            manifest.index.waivers.compactMap(\.operationID).filter {
                $0.contains("betaRecruitment")
            }
        )
        #expect(recruitmentWaivers == [
            "betaGroups_betaRecruitmentCriteria_getToOneRelationship",
            "betaGroups_betaRecruitmentCriterionCompatibleBuildCheck_getToOneRelationship"
        ])
        #expect(manifest.index.waivers.allSatisfy { waiver in
            waiver.operationID.map { !testFlightOperations.contains($0) } ?? true
        })

        let pin = try #require(manifest.index.optionalInputCoveragePin)
        #expect(pin.total == 2_905)
        #expect(pin.bound == 1_122)
        #expect(pin.internalControl == 40)
        #expect(pin.intentionallyOmitted == 1_743)
        #expect(pin.unclassified == 0)
        #expect(pin.identitySHA256 == "c975f4e4eebb62ec87864a73fbf72bb8841f644108e54e6ffb25168bcf2a2766")
    }

    @Test("TestFlight operation methods paths and success statuses are exact")
    func exactOperationContracts() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let toolNames: Set<String> = [
            "beta_groups_get_recruitment_criteria",
            "beta_groups_create_recruitment_criteria",
            "beta_groups_update_recruitment_criteria",
            "beta_groups_delete_recruitment_criteria",
            "beta_groups_list_recruitment_options",
            "beta_groups_check_recruitment_compatibility",
            "metrics_app_beta_tester_usage",
            "metrics_group_beta_tester_usage",
            "metrics_group_public_link_usage",
            "metrics_tester_usage",
            "metrics_build_beta_usage"
        ]
        let expected: [String: (method: String, path: String, status: String)] = [
            "betaGroups_getInstance": ("get", "/v1/betaGroups/{id}", "200"),
            "betaGroups_betaRecruitmentCriteria_getToOneRelated": ("get", "/v1/betaGroups/{id}/betaRecruitmentCriteria", "200"),
            "betaRecruitmentCriteria_createInstance": ("post", "/v1/betaRecruitmentCriteria", "201"),
            "betaRecruitmentCriteria_updateInstance": ("patch", "/v1/betaRecruitmentCriteria/{id}", "200"),
            "betaRecruitmentCriteria_deleteInstance": ("delete", "/v1/betaRecruitmentCriteria/{id}", "204"),
            "betaRecruitmentCriterionOptions_getCollection": ("get", "/v1/betaRecruitmentCriterionOptions", "200"),
            "betaGroups_betaRecruitmentCriterionCompatibleBuildCheck_getToOneRelated": ("get", "/v1/betaGroups/{id}/betaRecruitmentCriterionCompatibleBuildCheck", "200"),
            "apps_betaTesterUsages_getMetrics": ("get", "/v1/apps/{id}/metrics/betaTesterUsages", "200"),
            "betaGroups_betaTesterUsages_getMetrics": ("get", "/v1/betaGroups/{id}/metrics/betaTesterUsages", "200"),
            "betaGroups_publicLinkUsages_getMetrics": ("get", "/v1/betaGroups/{id}/metrics/publicLinkUsages", "200"),
            "betaTesters_betaTesterUsages_getMetrics": ("get", "/v1/betaTesters/{id}/metrics/betaTesterUsages", "200"),
            "builds_betaBuildUsages_getMetrics": ("get", "/v1/builds/{id}/metrics/betaBuildUsages", "200")
        ]

        for mapping in manifest.tools where toolNames.contains(mapping.tool) {
            for operation in mapping.operations {
                let contract = try #require(expected[operation.operationID])
                #expect(operation.method == contract.method)
                #expect(operation.path == contract.path)
                #expect(mapping.response.sources.contains {
                    $0.operationID == operation.operationID && $0.statusCode == contract.status
                })
            }
        }
    }

    @Test("recruitment mutations preserve confirmation and fresh related-resource lineage")
    func recruitmentMutationLineage() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let deletion = try #require(manifest.mapping(for: "beta_groups_delete_recruitment_criteria"))
        let confirmation = try #require(
            deletion.fields.first { $0.toolField == "confirm_criterion_id" }
        )

        #expect(deletion.effect == .destructive)
        #expect(confirmation.sourceKind == .local)
        #expect(confirmation.operationID == nil)
        #expect(confirmation.location == nil)
        #expect(confirmation.localRole ==
            "Mandatory exact match with criterion_id before the irreversible DELETE request.")

        for (toolName, expectedStatus) in [
            ("beta_groups_create_recruitment_criteria", "201"),
            ("beta_groups_update_recruitment_criteria", "200")
        ] {
            let mapping = try #require(manifest.mapping(for: toolName))
            let projection = try #require(
                mapping.response.fields.first { $0.outputField == "recruitmentCriteria" }
            )
            let status = try #require(
                mapping.response.fields.first { $0.outputField == "statusCode" }
            )

            #expect(mapping.effect == .write)
            #expect(projection.operationID == "betaGroups_betaRecruitmentCriteria_getToOneRelated")
            #expect(projection.jsonPointer == "/data")
            #expect(projection.localRole?.contains("Fresh group-scoped postflight projection") == true)
            #expect(status.localRole?.contains("Exact verified \(expectedStatus) status") == true)
        }
    }

    @Test("metric manifests publish exact echoes and included tester projections")
    func metricResponseFields() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expected: [String: Set<String>] = [
            "metrics_app_beta_tester_usage": [
                "success", "metric", "groups", "count", "limit", "app_id", "period",
                "group_by", "beta_tester_id", "includedBetaTesters", "next_url", "total"
            ],
            "metrics_group_beta_tester_usage": [
                "success", "metric", "groups", "count", "limit", "group_id", "period",
                "group_by", "beta_tester_id", "includedBetaTesters", "next_url", "total"
            ],
            "metrics_group_public_link_usage": [
                "success", "metric", "groups", "count", "limit", "group_id", "next_url", "total"
            ],
            "metrics_tester_usage": [
                "success", "metric", "groups", "count", "limit", "tester_id", "app_id",
                "period", "next_url", "total"
            ],
            "metrics_build_beta_usage": [
                "success", "metric", "groups", "count", "limit", "build_id", "next_url", "total"
            ]
        ]

        for (toolName, fields) in expected {
            let mapping = try #require(manifest.mapping(for: toolName))
            #expect(Set(mapping.response.fields.map(\.outputField)) == fields)
        }

        for (toolName, operationID) in [
            ("metrics_app_beta_tester_usage", "apps_betaTesterUsages_getMetrics"),
            ("metrics_group_beta_tester_usage", "betaGroups_betaTesterUsages_getMetrics")
        ] {
            let mapping = try #require(manifest.mapping(for: toolName))
            let included = try #require(
                mapping.response.fields.first { $0.outputField == "includedBetaTesters" }
            )
            #expect(included.operationID == operationID)
            #expect(included.jsonPointer == "/included")
            #expect(included.localRole?.contains("appDevices") == true)
        }
    }

    @Test("every public tester projection preserves appDevices")
    func testerProjectionAppDevices() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expectedOutputFields = [
            "beta_testers_create": "beta_tester",
            "beta_testers_get": "beta_tester",
            "beta_testers_list": "beta_testers",
            "beta_testers_search": "beta_testers",
            "beta_groups_list_testers": "beta_testers",
            "builds_get_beta_testers": "betaTesters",
            "builds_list_individual_testers": "individualTesters",
            "metrics_app_beta_tester_usage": "includedBetaTesters",
            "metrics_group_beta_tester_usage": "includedBetaTesters"
        ]

        for (toolName, outputField) in expectedOutputFields {
            let mapping = try #require(manifest.mapping(for: toolName))
            let projection = try #require(
                mapping.response.fields.first { $0.outputField == outputField }
            )
            #expect(
                projection.localRole?.contains("appDevices") == true,
                "Expected appDevices projection contract for \(toolName)"
            )
        }
    }

    @Test("worker filters route new tools and read-only mode blocks only recruitment mutations")
    func routingFilteringAndReadOnlyMode() async throws {
        let betaOnly = try await TestFactory.makeWorkerManager(enabledWorkers: ["beta_groups"])
        let betaRead = try await betaOnly.routeTool(.init(
            name: "beta_groups_get_recruitment_criteria",
            arguments: nil
        ))
        #expect(Self.text(betaRead).contains("group_id"))
        #expect(!Self.text(betaRead).contains("is disabled"))
        let metricDisabled = try await betaOnly.routeTool(.init(
            name: "metrics_build_beta_usage",
            arguments: nil
        ))
        #expect(Self.text(metricDisabled).contains("Worker 'metrics' is disabled"))

        let metricsOnly = try await TestFactory.makeWorkerManager(enabledWorkers: ["metrics"])
        let metricRead = try await metricsOnly.routeTool(.init(
            name: "metrics_build_beta_usage",
            arguments: nil
        ))
        #expect(Self.text(metricRead).contains("build_id"))
        #expect(!Self.text(metricRead).contains("is disabled"))
        let betaDisabled = try await metricsOnly.routeTool(.init(
            name: "beta_groups_get_recruitment_criteria",
            arguments: nil
        ))
        #expect(Self.text(betaDisabled).contains("Worker 'beta_groups' is disabled"))

        let readOnly = try await TestFactory.makeWorkerManager(readOnlyMode: true)
        for toolName in [
            "beta_groups_create_recruitment_criteria",
            "beta_groups_update_recruitment_criteria",
            "beta_groups_delete_recruitment_criteria"
        ] {
            let blocked = try await readOnly.routeTool(.init(name: toolName, arguments: nil))
            #expect(blocked._meta?.fields["asc/readOnlyMode"] == .bool(true))
            #expect(blocked._meta?.fields["asc/blockedTool"] == .string(toolName))
        }
        let allowedBetaRead = try await readOnly.routeTool(.init(
            name: "beta_groups_get_recruitment_criteria",
            arguments: nil
        ))
        let allowedMetricRead = try await readOnly.routeTool(.init(
            name: "metrics_build_beta_usage",
            arguments: nil
        ))
        #expect(Self.text(allowedBetaRead).contains("group_id"))
        #expect(Self.text(allowedMetricRead).contains("build_id"))
        #expect(allowedBetaRead._meta?.fields["asc/readOnlyMode"] == nil)
        #expect(allowedMetricRead._meta?.fields["asc/readOnlyMode"] == nil)
    }

    private static func text(_ result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let text, _, _) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
}
