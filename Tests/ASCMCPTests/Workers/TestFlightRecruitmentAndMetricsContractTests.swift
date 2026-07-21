import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("TestFlight Recruitment and Metrics Contract Tests")
struct TestFlightRecruitmentAndMetricsContractTests {
    @Test("schemas expose recruitment and TestFlight metric controls")
    func schemasExposeCurrentControls() async throws {
        let betaGroups = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(TestHTTPTransport(responses: []))
        )
        let betaGroupTools = await betaGroups.getTools()
        #expect(betaGroupTools.count == 15)
        let betaGroupToolNames: Set<String> = [
            "beta_groups_get_recruitment_criteria",
            "beta_groups_create_recruitment_criteria",
            "beta_groups_update_recruitment_criteria",
            "beta_groups_delete_recruitment_criteria",
            "beta_groups_list_recruitment_options",
            "beta_groups_check_recruitment_compatibility"
        ]
        #expect(Set(betaGroupTools.map(\.name)).isSuperset(of: betaGroupToolNames))
        for tool in betaGroupTools where betaGroupToolNames.contains(tool.name) {
            #expect(try testFlightContractSchema(tool)["additionalProperties"] == .bool(false))
        }

        let update = try testFlightContractProperties(
            try #require(betaGroupTools.first { $0.name == "beta_groups_update_recruitment_criteria" })
        )
        #expect(update["group_id"] != nil)
        #expect(update["criterion_id"] != nil)
        #expect(update["device_filters"]?.objectValue?["type"] == .array([.string("array"), .string("null")]))
        #expect(update["device_filters"]?.objectValue?["default"] == nil)

        let delete = try testFlightContractSchema(
            try #require(betaGroupTools.first { $0.name == "beta_groups_delete_recruitment_criteria" })
        )
        #expect(try testFlightContractStringSet(delete["required"]) == [
            "group_id", "criterion_id", "confirm_criterion_id"
        ])

        let metrics = MetricsWorker(
            httpClient: try await testFlightContractClient(TestHTTPTransport(responses: []))
        )
        let metricTools = await metrics.getTools()
        #expect(metricTools.count == 9)
        let metricToolNames: Set<String> = [
            "metrics_app_beta_tester_usage",
            "metrics_group_beta_tester_usage",
            "metrics_group_public_link_usage",
            "metrics_tester_usage",
            "metrics_build_beta_usage"
        ]
        #expect(Set(metricTools.map(\.name)).isSuperset(of: metricToolNames))
        for tool in metricTools where metricToolNames.contains(tool.name) {
            #expect(try testFlightContractSchema(tool)["additionalProperties"] == .bool(false))
        }

        let appUsage = try testFlightContractProperties(
            try #require(metricTools.first { $0.name == "metrics_app_beta_tester_usage" })
        )
        #expect(appUsage["period"] != nil)
        #expect(appUsage["group_by"] != nil)
        #expect(appUsage["beta_tester_id"] != nil)
        #expect(appUsage["limit"] != nil)
        #expect(appUsage["next_url"] != nil)
        #expect(appUsage["next_url"]?.objectValue?["minLength"] == .int(1))
    }

    @Test("beta tester appDevices decode and reach the public projection")
    func betaTesterAppDevicesProjection() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightTesterResponse())
        ])
        let worker = BetaTestersWorker(httpClient: try await testFlightContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_testers_get",
            arguments: ["tester_id": .string("tester-1")]
        ))

        #expect(result.isError != true)
        let root = try testFlightContractObject(result.structuredContent)
        let tester = try testFlightContractObject(root["beta_tester"])
        let devices = try testFlightContractArray(tester["appDevices"])
        let device = try testFlightContractObject(try #require(devices.first))
        #expect(device["model"] == .string("iPhone17,1"))
        #expect(device["platform"] == .string("IOS"))
        #expect(device["osVersion"] == .string("19.0"))
        #expect(device["appBuildVersion"] == .string("441"))
    }

    @Test("beta tester appDevices preserve null and empty array")
    func betaTesterAppDevicesNullAndEmpty() async throws {
        let nullTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightTesterResponse(appDevicesJSON: "null"))
        ])
        let nullWorker = BetaTestersWorker(httpClient: try await testFlightContractClient(nullTransport))
        let nullResult = try await nullWorker.handleTool(CallTool.Parameters(
            name: "beta_testers_get",
            arguments: ["tester_id": .string("tester-1")]
        ))
        let nullTester = try testFlightContractObject(
            try testFlightContractObject(nullResult.structuredContent)["beta_tester"]
        )
        #expect(nullTester["appDevices"] == .null)

        let emptyTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightTesterResponse(appDevicesJSON: "[]"))
        ])
        let emptyWorker = BetaTestersWorker(httpClient: try await testFlightContractClient(emptyTransport))
        let emptyResult = try await emptyWorker.handleTool(CallTool.Parameters(
            name: "beta_testers_get",
            arguments: ["tester_id": .string("tester-1")]
        ))
        let emptyTester = try testFlightContractObject(
            try testFlightContractObject(emptyResult.structuredContent)["beta_tester"]
        )
        #expect(emptyTester["appDevices"] == .array([]))
    }

    @Test("beta tester appDevices reject unknown platform values")
    func betaTesterAppDevicesRejectUnknownPlatform() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: testFlightTesterResponse(
                    appDevicesJSON: #"[{"model":"FutureDevice","platform":"IOS_FUTURE","osVersion":"99.0","appBuildVersion":"1"}]"#
                )
            )
        ])
        let worker = BetaTestersWorker(httpClient: try await testFlightContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_testers_get",
            arguments: ["tester_id": .string("tester-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("appDevices use the same camelCase projection across every public TestFlight surface")
    func appDevicesProjectionMatrix() async throws {
        let groupTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: testFlightTesterCollectionResponse(
                    selfPath: "/v1/betaGroups/group-1/betaTesters"
                )
            )
        ])
        let groupWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(groupTransport)
        )
        let groupResult = try await groupWorker.handleTool(.init(
            name: "beta_groups_list_testers",
            arguments: ["group_id": .string("group-1")]
        ))
        #expect(groupResult.isError != true)
        let groupTester = try #require(
            testFlightContractArray(
                try testFlightContractObject(groupResult.structuredContent)["beta_testers"]
            ).first
        )

        let betaDetailTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: testFlightTesterCollectionResponse(
                    selfPath: "/v1/builds/build-1/individualTesters"
                )
            ),
            .init(
                statusCode: 200,
                body: testFlightTesterCollectionResponse(
                    selfPath: "/v1/builds/build-1/individualTesters"
                )
            )
        ])
        let betaDetailWorker = BuildBetaDetailsWorker(
            httpClient: try await testFlightContractClient(betaDetailTransport)
        )
        let getResult = try await betaDetailWorker.handleTool(.init(
            name: "builds_get_beta_testers",
            arguments: ["build_id": .string("build-1")]
        ))
        let listResult = try await betaDetailWorker.handleTool(.init(
            name: "builds_list_individual_testers",
            arguments: ["build_id": .string("build-1")]
        ))
        #expect(getResult.isError != true)
        #expect(listResult.isError != true)
        let getTester = try #require(
            testFlightContractArray(
                try testFlightContractObject(getResult.structuredContent)["betaTesters"]
            ).first
        )
        let listTester = try #require(
            testFlightContractArray(
                try testFlightContractObject(listResult.structuredContent)["individualTesters"]
            ).first
        )

        let buildsTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightBuildsIncludedTesterResponse())
        ])
        let buildsWorker = BuildsWorker(httpClient: try await testFlightContractClient(buildsTransport))
        let buildsResult = try await buildsWorker.handleTool(.init(
            name: "builds_list",
            arguments: ["app_id": .string("app-1")]
        ))
        #expect(buildsResult.isError != true)
        let includedTester = try #require(
            testFlightContractArray(
                try testFlightContractObject(buildsResult.structuredContent)["included"]
            ).first
        )

        for testerValue in [groupTester, getTester, listTester, includedTester] {
            let tester = try testFlightContractObject(testerValue)
            let devices = try testFlightContractArray(tester["appDevices"])
            let device = try testFlightContractObject(try #require(devices.first))
            #expect(Set(device.keys) == ["model", "platform", "osVersion", "appBuildVersion"])
            #expect(device["model"] == .string("iPhone17,1"))
            #expect(device["platform"] == .string("IOS"))
            #expect(device["osVersion"] == .string("19.0"))
            #expect(device["appBuildVersion"] == .string("441"))
            #expect(tester["app_devices"] == nil)
        }
    }

    @Test("criteria read and compatibility check confirm the parent and project full resources")
    func criteriaReadAndCompatibility() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 200, body: testFlightCriterionResponse()),
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 200, body: testFlightCompatibilityResponse())
        ])
        let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))

        let criteria = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_get_recruitment_criteria",
            arguments: ["group_id": .string("group-1")]
        ))
        let compatibility = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_check_recruitment_compatibility",
            arguments: ["group_id": .string("group-1")]
        ))

        #expect(criteria.isError != true)
        let criteriaRoot = try testFlightContractObject(criteria.structuredContent)
        #expect(criteriaRoot["criteriaPresent"] == .bool(true))
        let criterion = try testFlightContractObject(criteriaRoot["recruitmentCriteria"])
        #expect(criterion["id"] == .string("criterion-1"))

        #expect(compatibility.isError != true)
        let compatibilityRoot = try testFlightContractObject(compatibility.structuredContent)
        #expect(compatibilityRoot["compatibilityCheckId"] == .string("check-1"))
        #expect(compatibilityRoot["hasCompatibleBuild"] == .bool(true))

        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.url?.path } == [
            "/v1/betaGroups/group-1",
            "/v1/betaGroups/group-1/betaRecruitmentCriteria",
            "/v1/betaGroups/group-1",
            "/v1/betaGroups/group-1/betaRecruitmentCriterionCompatibleBuildCheck"
        ])
    }

    @Test("canonical TestFlight identifiers fail before transport")
    func canonicalIdentifiersFailBeforeTransport() async throws {
        let invalidIDs: [Value] = [
            .string(""),
            .string(" group-1"),
            .string("group-1 "),
            .string("."),
            .string(".."),
            .string("group/1"),
            .string("group%2F1"),
            .string("group\n1"),
            .int(1)
        ]

        for invalidID in invalidIDs {
            let recruitmentTransport = TestHTTPTransport(responses: [])
            let recruitment = BetaGroupsWorker(
                httpClient: try await testFlightContractClient(recruitmentTransport)
            )
            let recruitmentCases: [(String, [String: Value])] = [
                ("beta_groups_get_recruitment_criteria", ["group_id": invalidID]),
                ("beta_groups_create_recruitment_criteria", [
                    "group_id": invalidID,
                    "device_filters": .array([])
                ]),
                ("beta_groups_update_recruitment_criteria", [
                    "group_id": .string("group-1"),
                    "criterion_id": invalidID,
                    "device_filters": .array([])
                ]),
                ("beta_groups_delete_recruitment_criteria", [
                    "group_id": .string("group-1"),
                    "criterion_id": invalidID,
                    "confirm_criterion_id": invalidID
                ]),
                ("beta_groups_check_recruitment_compatibility", ["group_id": invalidID])
            ]
            for (tool, arguments) in recruitmentCases {
                let result = try await recruitment.handleTool(.init(name: tool, arguments: arguments))
                #expect(result.isError == true)
            }
            #expect(await recruitmentTransport.requestCount() == 0)

            let metricTransport = TestHTTPTransport(responses: [])
            let metrics = MetricsWorker(httpClient: try await testFlightContractClient(metricTransport))
            let metricCases: [(String, [String: Value])] = [
                ("metrics_app_beta_tester_usage", ["app_id": invalidID]),
                ("metrics_app_beta_tester_usage", [
                    "app_id": .string("app-1"),
                    "beta_tester_id": invalidID
                ]),
                ("metrics_group_beta_tester_usage", ["group_id": invalidID]),
                ("metrics_group_beta_tester_usage", [
                    "group_id": .string("group-1"),
                    "beta_tester_id": invalidID
                ]),
                ("metrics_group_public_link_usage", ["group_id": invalidID]),
                ("metrics_tester_usage", [
                    "tester_id": invalidID,
                    "app_id": .string("app-1")
                ]),
                ("metrics_tester_usage", [
                    "tester_id": .string("tester-1"),
                    "app_id": invalidID
                ]),
                ("metrics_build_beta_usage", ["build_id": invalidID])
            ]
            for (tool, arguments) in metricCases {
                let result = try await metrics.handleTool(.init(name: tool, arguments: arguments))
                #expect(result.isError == true)
            }
            #expect(await metricTransport.requestCount() == 0)
        }
    }

    @Test("criteria absence is accepted only after a strict parent receipt")
    func criteriaAbsenceRequiresConfirmedParent() async throws {
        let absentTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 404, body: testFlightAPIError(status: 404))
        ])
        let absentWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(absentTransport)
        )
        let absent = try await absentWorker.handleTool(.init(
            name: "beta_groups_get_recruitment_criteria",
            arguments: ["group_id": .string("group-1")]
        ))
        #expect(absent.isError != true)
        let absentRoot = try testFlightContractObject(absent.structuredContent)
        #expect(absentRoot["criteriaPresent"] == .bool(false))
        #expect(await absentTransport.requestCount() == 2)

        let invalidParents = [
            #"{"data":{"type":"betaGroups","id":"group-1","attributes":{"name":"Public Beta"}}}"#,
            testFlightGroupResponse(type: "apps"),
            testFlightGroupResponse(id: "group-2"),
            testFlightGroupResponse(selfPath: "/v1/betaGroups/group-2")
        ]
        for invalidParent in invalidParents {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: invalidParent),
                .init(statusCode: 404, body: testFlightAPIError(status: 404))
            ])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "beta_groups_get_recruitment_criteria",
                arguments: ["group_id": .string("group-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("criteria reads reject links identity and enum drift")
    func criteriaReadsRejectResponseDrift() async throws {
        let invalidCriteria = [
            testFlightCriterionResponse(type: "apps"),
            testFlightCriterionResponse(id: "criterion/1"),
            testFlightCriterionResponse(selfPath: "/v1/betaGroups/group-2/betaRecruitmentCriteria"),
            testFlightCriterionResponse(filtersJSON: #"[{"deviceFamily":"FUTURE_DEVICE"}]"#),
            #"{"data":{"type":"betaRecruitmentCriteria","id":"criterion-1","attributes":{"deviceFamilyOsVersionFilters":[]}}}"#
        ]
        for invalidCriterion in invalidCriteria {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: testFlightGroupResponse()),
                .init(statusCode: 200, body: invalidCriterion)
            ])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "beta_groups_get_recruitment_criteria",
                arguments: ["group_id": .string("group-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 2)
        }
    }

    @Test("create criteria requires absence exact 201 and fresh group lineage")
    func createCriteriaExactReceiptAndFreshLineage() async throws {
        let existingTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 200, body: testFlightCriterionResponse())
        ])
        let existingWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(existingTransport)
        )
        let duplicate = try await existingWorker.handleTool(CallTool.Parameters(
            name: "beta_groups_create_recruitment_criteria",
            arguments: testFlightCreateCriteriaArguments()
        ))
        #expect(duplicate.isError == true)
        #expect(await existingTransport.recordedRequests().map(\.httpMethod) == ["GET", "GET"])

        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 404, body: testFlightAPIError(status: 404)),
            .init(
                statusCode: 201,
                body: testFlightCriterionResponse(
                    lastModifiedDate: "2026-07-20T00:00:00Z",
                    selfPath: "/v1/betaRecruitmentCriteria/criterion-1"
                )
            ),
            .init(
                statusCode: 200,
                body: testFlightCriterionResponse(lastModifiedDate: "2026-07-21T00:00:00Z")
            )
        ])
        let worker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(transport)
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_create_recruitment_criteria",
            arguments: testFlightCreateCriteriaArguments()
        ))

        #expect(result.isError != true)
        let root = try testFlightContractObject(result.structuredContent)
        #expect(root["operationCommitted"] == .bool(true))
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["createdByInvocation"] == .bool(true))
        #expect(root["candidateAttributionConfirmed"] == .bool(true))
        #expect(root["retrySafe"] == .bool(false))
        #expect(root["statusCode"] == .int(201))
        let returnedCriterion = try testFlightContractObject(root["recruitmentCriteria"])
        #expect(returnedCriterion["lastModifiedDate"] == .string("2026-07-21T00:00:00Z"))

        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "GET"])
        #expect(requests.map { $0.url?.path } == [
            "/v1/betaGroups/group-1",
            "/v1/betaGroups/group-1/betaRecruitmentCriteria",
            "/v1/betaRecruitmentCriteria",
            "/v1/betaGroups/group-1/betaRecruitmentCriteria"
        ])
        let body = try testFlightContractJSONBody(try #require(requests[2].httpBody))
        let data = try #require(body["data"] as? [String: Any])
        #expect(data["type"] as? String == "betaRecruitmentCriteria")
        let relationships = try #require(data["relationships"] as? [String: Any])
        let betaGroup = try #require(relationships["betaGroup"] as? [String: Any])
        let identifier = try #require(betaGroup["data"] as? [String: Any])
        #expect(identifier["id"] as? String == "group-1")
        #expect(identifier["type"] as? String == "betaGroups")
    }

    @Test("create criteria keeps ambiguous and rejected outcomes fail closed")
    func createCriteriaFailuresRemainFailClosed() async throws {
        let ambiguousTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 404, body: testFlightAPIError(status: 404)),
            .init(statusCode: 500, body: testFlightAPIError(status: 500)),
            .init(statusCode: 200, body: testFlightCriterionResponse())
        ])
        let ambiguousWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(ambiguousTransport)
        )
        let ambiguous = try await ambiguousWorker.handleTool(.init(
            name: "beta_groups_create_recruitment_criteria",
            arguments: testFlightCreateCriteriaArguments()
        ))
        #expect(ambiguous.isError == true)
        let ambiguousRoot = try testFlightContractObject(ambiguous.structuredContent)
        #expect(ambiguousRoot["operationCommitState"] == .string("unknown"))
        #expect(ambiguousRoot["operationCommitted"] == .null)
        #expect(ambiguousRoot["outcomeUnknown"] == .bool(true))
        #expect(ambiguousRoot["retrySafe"] == .bool(false))
        #expect(ambiguousRoot["createdByInvocation"] == .bool(false))
        #expect(ambiguousRoot["candidateAttributionConfirmed"] == .bool(false))
        #expect(ambiguousRoot["observedCandidate"] != nil)
        let inspection = try testFlightContractObject(ambiguousRoot["inspection"])
        #expect(inspection["tool"] == .string("beta_groups_get_recruitment_criteria"))
        #expect(try testFlightContractObject(inspection["arguments"])["group_id"] == .string("group-1"))
        #expect(await ambiguousTransport.recordedRequests().map(\.httpMethod) == [
            "GET", "GET", "POST", "GET"
        ])

        let rejectedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 404, body: testFlightAPIError(status: 404)),
            .init(statusCode: 422, body: testFlightAPIError(status: 422)),
            .init(statusCode: 200, body: testFlightCriterionResponse())
        ])
        let rejectedWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(rejectedTransport)
        )
        let rejected = try await rejectedWorker.handleTool(.init(
            name: "beta_groups_create_recruitment_criteria",
            arguments: testFlightCreateCriteriaArguments()
        ))
        #expect(rejected.isError == true)
        let rejectedRoot = try testFlightContractObject(rejected.structuredContent)
        #expect(rejectedRoot["operationCommitState"] == .string("rejected"))
        #expect(rejectedRoot["operationCommitted"] == .bool(false))
        #expect(rejectedRoot["retrySafe"] == .bool(true))
        #expect(rejectedRoot["createdByInvocation"] == .bool(false))
        #expect(rejectedRoot["candidateAttributionConfirmed"] == .bool(false))
        #expect(await rejectedTransport.requestCount() == 4)
    }

    @Test("create criteria treats every unexpected accepted response as committed unverified")
    func createCriteriaUnexpectedAcceptedResponsesFailClosed() async throws {
        let cases: [(Int, String)] = [
            (202, testFlightCriterionResponse(selfPath: "/v1/betaRecruitmentCriteria/criterion-1")),
            (201, #"{"data":{"type":"betaRecruitmentCriteria","id":"criterion-1"}}"#)
        ]
        for (statusCode, responseBody) in cases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: testFlightGroupResponse()),
                .init(statusCode: 404, body: testFlightAPIError(status: 404)),
                .init(statusCode: statusCode, body: responseBody),
                .init(statusCode: 200, body: testFlightCriterionResponse())
            ])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "beta_groups_create_recruitment_criteria",
                arguments: testFlightCreateCriteriaArguments()
            ))
            #expect(result.isError == true)
            let root = try testFlightContractObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string("committed_unverified"))
            #expect(root["operationCommitted"] == .bool(true))
            #expect(root["candidateAttributionConfirmed"] == .bool(false))
            #expect(root["createdByInvocation"] == .bool(false))
            #expect(await transport.requestCount() == 4)
        }
    }

    @Test("create criteria retains a canonical response ID when exact 201 validation fails")
    func createCriteriaRetainsCanonicalAcceptedResponseID() async throws {
        let invalidResponses = [
            testFlightCriterionResponse(
                selfPath: "/v1/betaRecruitmentCriteria/criterion-2"
            ),
            testFlightCriterionResponse(
                filtersJSON: "[]",
                selfPath: "/v1/betaRecruitmentCriteria/criterion-1"
            )
        ]

        for responseBody in invalidResponses {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: testFlightGroupResponse()),
                .init(statusCode: 404, body: testFlightAPIError(status: 404)),
                .init(statusCode: 201, body: responseBody),
                .init(statusCode: 200, body: testFlightCriterionResponse())
            ])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))

            let result = try await worker.handleTool(.init(
                name: "beta_groups_create_recruitment_criteria",
                arguments: testFlightCreateCriteriaArguments()
            ))

            #expect(result.isError == true)
            let root = try testFlightContractObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string("committed_unverified"))
            #expect(root["responseCriterionId"] == .string("criterion-1"))
            #expect(root["candidateAttributionConfirmed"] == .bool(false))
            #expect(root["createdByInvocation"] == .bool(false))
            #expect(await transport.recordedRequests().map(\.httpMethod) == [
                "GET", "GET", "POST", "GET"
            ])
        }
    }

    @Test("create criteria does not attribute a different fresh group candidate")
    func createCriteriaRejectsMismatchedPostflightLineage() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 404, body: testFlightAPIError(status: 404)),
            .init(
                statusCode: 201,
                body: testFlightCriterionResponse(
                    selfPath: "/v1/betaRecruitmentCriteria/criterion-1"
                )
            ),
            .init(statusCode: 200, body: testFlightCriterionResponse(id: "criterion-2")),
            .init(statusCode: 200, body: testFlightCriterionResponse(id: "criterion-2"))
        ])
        let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
        let result = try await worker.handleTool(.init(
            name: "beta_groups_create_recruitment_criteria",
            arguments: testFlightCreateCriteriaArguments()
        ))
        #expect(result.isError == true)
        let root = try testFlightContractObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(root["createdByInvocation"] == .bool(false))
        #expect(root["candidateAttributionConfirmed"] == .bool(false))
        #expect(root["responseCriterionId"] == .string("criterion-1"))
        #expect(root["candidateId"] == .string("criterion-2"))
        #expect(await transport.recordedRequests().map(\.httpMethod) == [
            "GET", "GET", "POST", "GET", "GET"
        ])
    }

    @Test("criteria update preserves explicit null with exact 200 and fresh postflight")
    func criteriaUpdateExplicitNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 200, body: testFlightCriterionResponse()),
            .init(
                statusCode: 200,
                body: testFlightCriterionResponse(
                    filtersJSON: "null",
                    selfPath: "/v1/betaRecruitmentCriteria/criterion-1"
                )
            ),
            .init(statusCode: 200, body: testFlightCriterionResponse(filtersJSON: "null"))
        ])
        let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))

        let result = try await worker.handleTool(.init(
            name: "beta_groups_update_recruitment_criteria",
            arguments: testFlightUpdateNullArguments()
        ))

        #expect(result.isError != true)
        let root = try testFlightContractObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["operationCommitted"] == .bool(true))
        #expect(root["changed"] == .bool(true))
        #expect(root["statusCode"] == .int(200))
        let criterion = try testFlightContractObject(root["recruitmentCriteria"])
        #expect(criterion["deviceFiltersState"] == .string("null"))
        #expect(criterion["deviceFilters"] == .null)

        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "PATCH", "GET"])
        let body = try testFlightContractJSONBody(try #require(requests[2].httpBody))
        let data = try #require(body["data"] as? [String: Any])
        #expect(data["id"] as? String == "criterion-1")
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes["deviceFamilyOsVersionFilters"] is NSNull)
    }

    @Test("criteria update distinguishes omitted null and matching values")
    func criteriaUpdateTriStateAndNoOp() async throws {
        let omittedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 200, body: testFlightCriterionWithoutFiltersResponse()),
            .init(
                statusCode: 200,
                body: testFlightCriterionResponse(
                    filtersJSON: "null",
                    selfPath: "/v1/betaRecruitmentCriteria/criterion-1"
                )
            ),
            .init(statusCode: 200, body: testFlightCriterionResponse(filtersJSON: "null"))
        ])
        let omittedWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(omittedTransport)
        )
        let omitted = try await omittedWorker.handleTool(.init(
            name: "beta_groups_update_recruitment_criteria",
            arguments: testFlightUpdateNullArguments()
        ))
        #expect(omitted.isError != true)
        #expect(await omittedTransport.recordedRequests().map(\.httpMethod) == [
            "GET", "GET", "PATCH", "GET"
        ])

        let nullNoOpTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 200, body: testFlightCriterionResponse(filtersJSON: "null"))
        ])
        let nullNoOpWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(nullNoOpTransport)
        )
        let nullNoOp = try await nullNoOpWorker.handleTool(.init(
            name: "beta_groups_update_recruitment_criteria",
            arguments: testFlightUpdateNullArguments()
        ))
        #expect(nullNoOp.isError != true)
        let nullNoOpRoot = try testFlightContractObject(nullNoOp.structuredContent)
        #expect(nullNoOpRoot["operationCommitState"] == .string("not_attempted"))
        #expect(nullNoOpRoot["operationCommitted"] == .bool(false))
        #expect(nullNoOpRoot["changed"] == .bool(false))
        #expect(await nullNoOpTransport.requestCount() == 2)

        let valueNoOpTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 200, body: testFlightCriterionResponse())
        ])
        let valueNoOpWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(valueNoOpTransport)
        )
        let valueNoOp = try await valueNoOpWorker.handleTool(.init(
            name: "beta_groups_update_recruitment_criteria",
            arguments: [
                "group_id": .string("group-1"),
                "criterion_id": .string("criterion-1"),
                "device_filters": testFlightCreateCriteriaArguments()["device_filters"] ?? .array([])
            ]
        ))
        #expect(valueNoOp.isError != true)
        let valueNoOpRoot = try testFlightContractObject(valueNoOp.structuredContent)
        #expect(valueNoOpRoot["operationCommitState"] == .string("not_attempted"))
        #expect(valueNoOpRoot["changed"] == .bool(false))
        #expect(await valueNoOpTransport.requestCount() == 2)
    }

    @Test("criteria update failures remain rejected unknown or committed unverified")
    func criteriaUpdateFailuresRemainFailClosed() async throws {
        let requestCases: [(Int, String, Value, Value)] = [
            (500, "unknown", .null, .bool(false)),
            (422, "rejected", .bool(false), .bool(true))
        ]
        for (statusCode, expectedState, expectedCommitted, expectedRetrySafe) in requestCases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: testFlightGroupResponse()),
                .init(statusCode: 200, body: testFlightCriterionResponse()),
                .init(statusCode: statusCode, body: testFlightAPIError(status: statusCode)),
                .init(statusCode: 200, body: testFlightCriterionResponse(filtersJSON: "null"))
            ])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "beta_groups_update_recruitment_criteria",
                arguments: testFlightUpdateNullArguments()
            ))
            #expect(result.isError == true)
            let root = try testFlightContractObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string(expectedState))
            #expect(root["operationCommitted"] == expectedCommitted)
            #expect(root["retrySafe"] == expectedRetrySafe)
            #expect(root["candidateAttributionConfirmed"] == .bool(false))
            #expect(await transport.requestCount() == 4)
        }

        let acceptedCases: [(Int, String)] = [
            (
                202,
                testFlightCriterionResponse(
                    filtersJSON: "null",
                    selfPath: "/v1/betaRecruitmentCriteria/criterion-1"
                )
            ),
            (
                200,
                testFlightCriterionWithoutFiltersResponse(
                    selfPath: "/v1/betaRecruitmentCriteria/criterion-1"
                )
            )
        ]
        for (statusCode, responseBody) in acceptedCases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: testFlightGroupResponse()),
                .init(statusCode: 200, body: testFlightCriterionResponse()),
                .init(statusCode: statusCode, body: responseBody),
                .init(statusCode: 200, body: testFlightCriterionResponse(filtersJSON: "null"))
            ])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "beta_groups_update_recruitment_criteria",
                arguments: testFlightUpdateNullArguments()
            ))
            #expect(result.isError == true)
            let root = try testFlightContractObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string("committed_unverified"))
            #expect(root["operationCommitted"] == .bool(true))
            #expect(root["candidateAttributionConfirmed"] == .bool(false))
            #expect(await transport.requestCount() == 4)
        }
    }

    @Test("recruitment filters follow Apple's unconstrained strings and duplicate-array contract")
    func recruitmentFiltersPreserveAppleValues() async throws {
        let filtersJSON = #"[{"deviceFamily":"IPHONE","minimumOsInclusive":"","maximumOsInclusive":" 19.0 "},{"deviceFamily":"IPHONE","minimumOsInclusive":"","maximumOsInclusive":" 19.0 "}]"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 404, body: testFlightAPIError(status: 404)),
            .init(
                statusCode: 201,
                body: testFlightCriterionResponse(
                    filtersJSON: filtersJSON,
                    selfPath: "/v1/betaRecruitmentCriteria/criterion-1"
                )
            ),
            .init(statusCode: 200, body: testFlightCriterionResponse(filtersJSON: filtersJSON))
        ])
        let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
        let duplicateFilter: Value = .object([
            "device_family": .string("IPHONE"),
            "minimum_os_inclusive": .string(""),
            "maximum_os_inclusive": .string(" 19.0 ")
        ])

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_create_recruitment_criteria",
            arguments: [
                "group_id": .string("group-1"),
                "device_filters": .array([duplicateFilter, duplicateFilter])
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        let body = try testFlightContractJSONBody(try #require(requests[2].httpBody))
        let data = try #require(body["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        let filters = try #require(attributes["deviceFamilyOsVersionFilters"] as? [[String: Any]])
        #expect(filters.count == 2)
        #expect(filters[0]["minimumOsInclusive"] as? String == "")
        #expect(filters[0]["maximumOsInclusive"] as? String == " 19.0 ")
    }

    @Test("criteria delete requires an exact confirmation before transport")
    func criteriaDeleteRequiresExactConfirmation() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
        let missing = try await worker.handleTool(.init(
            name: "beta_groups_delete_recruitment_criteria",
            arguments: [
                "group_id": .string("group-1"),
                "criterion_id": .string("criterion-1")
            ]
        ))
        let mismatched = try await worker.handleTool(.init(
            name: "beta_groups_delete_recruitment_criteria",
            arguments: [
                "group_id": .string("group-1"),
                "criterion_id": .string("criterion-1"),
                "confirm_criterion_id": .string("criterion-2")
            ]
        ))
        #expect(missing.isError == true)
        #expect(mismatched.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("criteria delete commits only an exact 204 receipt")
    func criteriaDeleteExact204() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightGroupResponse()),
            .init(statusCode: 200, body: testFlightCriterionResponse()),
            .init(statusCode: 204, body: "")
        ])
        let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
        let result = try await worker.handleTool(.init(
            name: "beta_groups_delete_recruitment_criteria",
            arguments: testFlightDeleteCriteriaArguments()
        ))
        #expect(result.isError != true)
        let root = try testFlightContractObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["operationCommitted"] == .bool(true))
        #expect(root["statusCode"] == .int(204))
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "DELETE"])
        #expect(requests.last?.url?.path == "/v1/betaRecruitmentCriteria/criterion-1")
    }

    @Test("criteria delete never converts 202 422 or ambiguous failures into success")
    func criteriaDeleteFailuresRemainFailClosed() async throws {
        let cases: [(Int, String, Value, Value, Int, String)] = [
            (202, "committed_unverified", .bool(true), .bool(false), 200, testFlightCriterionResponse()),
            (422, "rejected", .bool(false), .bool(true), 404, testFlightAPIError(status: 404)),
            (500, "unknown", .null, .bool(false), 404, testFlightAPIError(status: 404))
        ]
        for (
            statusCode,
            expectedState,
            expectedCommitted,
            expectedRetrySafe,
            diagnosticStatus,
            diagnosticBody
        ) in cases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: testFlightGroupResponse()),
                .init(statusCode: 200, body: testFlightCriterionResponse()),
                .init(
                    statusCode: statusCode,
                    body: statusCode == 202 ? "" : testFlightAPIError(status: statusCode)
                ),
                .init(statusCode: diagnosticStatus, body: diagnosticBody)
            ])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "beta_groups_delete_recruitment_criteria",
                arguments: testFlightDeleteCriteriaArguments()
            ))
            #expect(result.isError == true)
            let root = try testFlightContractObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string(expectedState))
            #expect(root["operationCommitted"] == expectedCommitted)
            #expect(root["retrySafe"] == expectedRetrySafe)
            #expect(await transport.recordedRequests().map(\.httpMethod) == [
                "GET", "GET", "DELETE", "GET"
            ])
        }
    }

    @Test("recruitment options preserve fixed sparse fields and pagination scope")
    func recruitmentOptionsPagination() async throws {
        let responseNext = "https://api.example.test/v1/betaRecruitmentCriterionOptions?cursor=next&fields%5BbetaRecruitmentCriterionOptions%5D=deviceFamilyOsVersions&limit=200"
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: testFlightOptionsResponse(next: responseNext, nextCursor: "next")
            )
        ])
        let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_list_recruitment_options",
            arguments: ["limit": .int(200)]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try testFlightContractQuery(request)
        #expect(query["limit"] == "200")
        #expect(query["fields[betaRecruitmentCriterionOptions]"] == "deviceFamilyOsVersions")
        let root = try testFlightContractObject(result.structuredContent)
        let options = try testFlightContractArray(root["options"])
        #expect(options.count == 1)
        #expect(root["limit"] == .int(200))
        #expect(root["next_url"] == .string(responseNext))

        let continuationTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightOptionsResponse())
        ])
        let continuationWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(continuationTransport)
        )
        let continuation = try await continuationWorker.handleTool(CallTool.Parameters(
            name: "beta_groups_list_recruitment_options",
            arguments: [
                "limit": .int(200),
                "next_url": .string("https://api.example.test/v1/betaRecruitmentCriterionOptions?cursor=next&fields%5BbetaRecruitmentCriterionOptions%5D=deviceFamilyOsVersions&limit=200")
            ]
        ))
        #expect(continuation.isError != true)
        let continuationRequest = try #require(await continuationTransport.recordedRequests().first)
        #expect(try testFlightContractQuery(continuationRequest)["cursor"] == "next")

        let rejectedTransport = TestHTTPTransport(responses: [])
        let rejectedWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(rejectedTransport)
        )
        let rejected = try await rejectedWorker.handleTool(CallTool.Parameters(
            name: "beta_groups_list_recruitment_options",
            arguments: [
                "limit": .int(25),
                "next_url": .string("https://api.example.test/v1/betaRecruitmentCriterionOptions?cursor=next&limit=25")
            ]
        ))
        #expect(rejected.isError == true)
        #expect(await rejectedTransport.requestCount() == 0)
    }

    @Test("recruitment options reject malformed documents and identity drift")
    func recruitmentOptionsRejectResponseDrift() async throws {
        let invalidBodies = [
            testFlightOptionsResponse(type: "apps"),
            testFlightOptionsResponse(id: "IPHONE/18"),
            testFlightOptionsResponse(deviceFamily: "FUTURE_DEVICE"),
            testFlightOptionsResponse(selfPath: "/v1/apps"),
            testFlightOptionsResponse(duplicate: true),
            testFlightOptionsResponse(next: "", nextCursor: "next"),
            #"{"data":[],"meta":{"paging":{"total":0,"limit":25}}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/betaRecruitmentCriterionOptions"},"meta":{}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/betaRecruitmentCriterionOptions"},"meta":{"paging":{"total":0}}}"#
        ]
        for body in invalidBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "beta_groups_list_recruitment_options",
                arguments: ["limit": .int(25)]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("compatibility response requires the exact type id and document self link")
    func compatibilityRejectsResponseDrift() async throws {
        let invalidBodies = [
            testFlightCompatibilityResponse(type: "apps"),
            testFlightCompatibilityResponse(id: "check/1"),
            testFlightCompatibilityResponse(selfPath: "/v1/betaGroups/group-2/betaRecruitmentCriterionCompatibleBuildCheck"),
            #"{"data":{"type":"betaRecruitmentCriterionCompatibleBuildChecks","id":"check-1","attributes":{"hasCompatibleBuild":true}}}"#
        ]
        for body in invalidBodies {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: testFlightGroupResponse()),
                .init(statusCode: 200, body: body)
            ])
            let worker = BetaGroupsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "beta_groups_check_recruitment_compatibility",
                arguments: ["group_id": .string("group-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 2)
        }
    }

    @Test("app and group beta tester metrics expose exact query echoes values and appDevices")
    func appAndGroupBetaTesterMetricsContract() async throws {
        let appPath = "/v1/apps/app-1/metrics/betaTesterUsages"
        let appNext = "https://api.example.test\(appPath)?cursor=next&filter%5BbetaTesters%5D=tester-1&period=P30D&groupBy=betaTesters&limit=200"
        let appTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightTesterMetricResponse(selfPath: appPath))
        ])
        let appWorker = MetricsWorker(httpClient: try await testFlightContractClient(appTransport))
        let app = try await appWorker.handleTool(.init(
            name: "metrics_app_beta_tester_usage",
            arguments: [
                "app_id": .string("app-1"),
                "period": .string("P30D"),
                "group_by": .array([.string("betaTesters")]),
                "beta_tester_id": .string("tester-1"),
                "limit": .int(200),
                "next_url": .string(appNext)
            ]
        ))
        #expect(app.isError != true)
        let appRequest = try #require(await appTransport.recordedRequests().first)
        #expect(appRequest.url?.path == appPath)
        let appQuery = try testFlightContractQuery(appRequest)
        #expect(appQuery["period"] == "P30D")
        #expect(appQuery["groupBy"] == "betaTesters")
        #expect(appQuery["filter[betaTesters]"] == "tester-1")
        #expect(appQuery["limit"] == "200")
        #expect(appQuery["cursor"] == "next")
        let appRoot = try testFlightContractObject(app.structuredContent)
        #expect(appRoot["metric"] == .string("app_beta_tester_usage"))
        #expect(appRoot["app_id"] == .string("app-1"))
        #expect(appRoot["period"] == .string("P30D"))
        #expect(appRoot["group_by"] == .array([.string("betaTesters")]))
        #expect(appRoot["beta_tester_id"] == .string("tester-1"))
        #expect(appRoot["limit"] == .int(200))
        let appValues = try testFlightFirstMetricValues(app)
        #expect(appValues["crash_count"] == .int(2))
        #expect(appValues["session_count"] == .int(17))
        #expect(appValues["feedback_count"] == .int(3))
        let included = try testFlightContractArray(appRoot["includedBetaTesters"])
        let tester = try testFlightContractObject(try #require(included.first))
        #expect(tester["type"] == .string("betaTesters"))
        #expect(tester["id"] == .string("tester-1"))
        let device = try testFlightContractObject(
            try #require(testFlightContractArray(tester["appDevices"]).first)
        )
        #expect(device["platform"] == .string("IOS"))
        #expect(device["appBuildVersion"] == .string("441"))

        let groupPath = "/v1/betaGroups/group-1/metrics/betaTesterUsages"
        let groupNext = "https://api.example.test\(groupPath)?cursor=next&filter%5BbetaTesters%5D=tester-1&period=P7D&groupBy=betaTesters&limit=25"
        let groupTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightTesterMetricResponse(selfPath: groupPath))
        ])
        let groupWorker = MetricsWorker(httpClient: try await testFlightContractClient(groupTransport))
        let group = try await groupWorker.handleTool(.init(
            name: "metrics_group_beta_tester_usage",
            arguments: [
                "group_id": .string("group-1"),
                "period": .string("P7D"),
                "group_by": .string("betaTesters"),
                "beta_tester_id": .string("tester-1"),
                "limit": .int(25),
                "next_url": .string(groupNext)
            ]
        ))
        #expect(group.isError != true)
        let groupRoot = try testFlightContractObject(group.structuredContent)
        #expect(groupRoot["metric"] == .string("group_beta_tester_usage"))
        #expect(groupRoot["group_id"] == .string("group-1"))
        #expect(groupRoot["period"] == .string("P7D"))
        #expect(groupRoot["group_by"] == .array([.string("betaTesters")]))
        #expect(groupRoot["beta_tester_id"] == .string("tester-1"))
        let groupQuery = try testFlightContractQuery(
            try #require(await groupTransport.recordedRequests().first)
        )
        #expect(groupQuery["cursor"] == "next")
        #expect(groupQuery["filter[betaTesters]"] == "tester-1")
    }

    @Test("tester metric requires and preserves the Apple app filter across pagination")
    func testerMetricRequiredFilterAndPagination() async throws {
        let missingTransport = TestHTTPTransport(responses: [])
        let missingWorker = MetricsWorker(
            httpClient: try await testFlightContractClient(missingTransport)
        )
        let missing = try await missingWorker.handleTool(.init(
            name: "metrics_tester_usage",
            arguments: ["tester_id": .string("tester-1")]
        ))
        #expect(missing.isError == true)
        #expect(await missingTransport.requestCount() == 0)

        let path = "/v1/betaTesters/tester-1/metrics/betaTesterUsages"
        let next = "https://api.example.test\(path)?cursor=next&filter%5Bapps%5D=app-1&period=P7D&limit=25"
        let validTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightTesterUsageMetricResponse(selfPath: path))
        ])
        let validWorker = MetricsWorker(httpClient: try await testFlightContractClient(validTransport))
        let valid = try await validWorker.handleTool(.init(
            name: "metrics_tester_usage",
            arguments: [
                "tester_id": .string("tester-1"),
                "app_id": .string("app-1"),
                "period": .string("P7D"),
                "next_url": .string(next)
            ]
        ))
        #expect(valid.isError != true)
        let root = try testFlightContractObject(valid.structuredContent)
        #expect(root["metric"] == .string("tester_usage"))
        #expect(root["tester_id"] == .string("tester-1"))
        #expect(root["app_id"] == .string("app-1"))
        #expect(root["period"] == .string("P7D"))
        #expect(root["limit"] == .int(25))
        let query = try testFlightContractQuery(
            try #require(await validTransport.recordedRequests().first)
        )
        #expect(query["cursor"] == "next")
        #expect(query["filter[apps]"] == "app-1")
        #expect(query["period"] == "P7D")
        #expect(query["limit"] == "25")
        let groups = try testFlightContractArray(root["groups"])
        let dimensions = try testFlightContractObject(
            try testFlightContractObject(try #require(groups.first))["dimensions"]
        )
        let appDimension = try testFlightContractObject(dimensions["apps"])
        #expect(appDimension["id"] == .string("app-1"))

        let changedTransport = TestHTTPTransport(responses: [])
        let changedWorker = MetricsWorker(httpClient: try await testFlightContractClient(changedTransport))
        let changed = try await changedWorker.handleTool(.init(
            name: "metrics_tester_usage",
            arguments: [
                "tester_id": .string("tester-1"),
                "app_id": .string("app-1"),
                "period": .string("P7D"),
                "next_url": .string("https://api.example.test\(path)?cursor=next&filter%5Bapps%5D=app-2&period=P7D&limit=25")
            ]
        ))
        #expect(changed.isError == true)
        #expect(await changedTransport.requestCount() == 0)
    }

    @Test("metric dimensions stay within requested filter identities")
    func metricDimensionsRejectForeignFilterIdentities() async throws {
        let cases: [(String, [String: Value], String)] = [
            (
                "metrics_tester_usage",
                ["tester_id": .string("tester-1"), "app_id": .string("app-1")],
                testFlightTesterUsageMetricResponse(
                    selfPath: "/v1/betaTesters/tester-1/metrics/betaTesterUsages",
                    dimensionsJSON: #"{"apps":{"data":"app-2","links":{"groupBy":"/v1/apps","related":"/v1/apps/app-2"}}}"#
                )
            ),
            (
                "metrics_app_beta_tester_usage",
                ["app_id": .string("app-1"), "beta_tester_id": .string("tester-1")],
                testFlightTesterMetricResponse(
                    selfPath: "/v1/apps/app-1/metrics/betaTesterUsages",
                    dimensionID: "tester-2"
                )
            ),
            (
                "metrics_group_beta_tester_usage",
                ["group_id": .string("group-1"), "beta_tester_id": .string("tester-1")],
                testFlightTesterMetricResponse(
                    selfPath: "/v1/betaGroups/group-1/metrics/betaTesterUsages",
                    dimensionID: "tester-2"
                )
            )
        ]

        for (tool, arguments, responseBody) in cases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: responseBody)
            ])
            let worker = MetricsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("public-link and build metrics expose every documented value and path pagination")
    func publicLinkAndBuildMetricValues() async throws {
        let publicPath = "/v1/betaGroups/group-1/metrics/publicLinkUsages"
        let publicNext = "https://api.example.test\(publicPath)?cursor=next&limit=25"
        let publicTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightPublicLinkMetricResponse(selfPath: publicPath))
        ])
        let publicWorker = MetricsWorker(httpClient: try await testFlightContractClient(publicTransport))
        let publicResult = try await publicWorker.handleTool(.init(
            name: "metrics_group_public_link_usage",
            arguments: [
                "group_id": .string("group-1"),
                "limit": .int(25),
                "next_url": .string(publicNext)
            ]
        ))
        #expect(publicResult.isError != true)
        let publicRoot = try testFlightContractObject(publicResult.structuredContent)
        #expect(publicRoot["metric"] == .string("group_public_link_usage"))
        #expect(publicRoot["group_id"] == .string("group-1"))
        #expect(publicRoot["limit"] == .int(25))
        let publicValues = try testFlightFirstMetricValues(publicResult)
        #expect(publicValues["view_count"] == .int(120))
        #expect(publicValues["accepted_count"] == .int(70))
        #expect(publicValues["did_not_accept_count"] == .int(20))
        #expect(publicValues["did_not_meet_criteria_count"] == .int(30))
        #expect(publicValues["not_relevant_ratio"] == .double(0.1))
        #expect(publicValues["not_clear_ratio"] == .double(0.2))
        #expect(publicValues["not_interesting_ratio"] == .double(0.3))
        #expect(try testFlightContractQuery(
            try #require(await publicTransport.recordedRequests().first)
        )["cursor"] == "next")

        let buildPath = "/v1/builds/build-1/metrics/betaBuildUsages"
        let buildNext = "https://api.example.test\(buildPath)?cursor=next&limit=25"
        let buildTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testFlightBuildMetricResponse(selfPath: buildPath))
        ])
        let buildWorker = MetricsWorker(httpClient: try await testFlightContractClient(buildTransport))
        let buildResult = try await buildWorker.handleTool(.init(
            name: "metrics_build_beta_usage",
            arguments: [
                "build_id": .string("build-1"),
                "limit": .int(25),
                "next_url": .string(buildNext)
            ]
        ))
        #expect(buildResult.isError != true)
        let buildRoot = try testFlightContractObject(buildResult.structuredContent)
        #expect(buildRoot["metric"] == .string("build_beta_usage"))
        #expect(buildRoot["build_id"] == .string("build-1"))
        #expect(buildRoot["limit"] == .int(25))
        let buildValues = try testFlightFirstMetricValues(buildResult)
        #expect(buildValues["crash_count"] == .int(1))
        #expect(buildValues["install_count"] == .int(22))
        #expect(buildValues["session_count"] == .int(44))
        #expect(buildValues["feedback_count"] == .int(5))
        #expect(buildValues["invite_count"] == .int(60))
        #expect(try testFlightContractQuery(
            try #require(await buildTransport.recordedRequests().first)
        )["cursor"] == "next")
    }

    @Test("metric models reject cross-endpoint drift and missing document links")
    func metricsRejectCrossEndpointDrift() async throws {
        let cases: [(String, [String: Value], String)] = [
            (
                "metrics_app_beta_tester_usage",
                ["app_id": .string("app-1")],
                testFlightTesterMetricResponse(
                    selfPath: "/v1/apps/app-1/metrics/betaTesterUsages",
                    valuesJSON: #"{"installCount":1}"#
                )
            ),
            (
                "metrics_group_public_link_usage",
                ["group_id": .string("group-1")],
                testFlightPublicLinkMetricResponse(
                    selfPath: "/v1/betaGroups/group-1/metrics/publicLinkUsages",
                    valuesJSON: #"{"crashCount":1}"#
                )
            ),
            (
                "metrics_tester_usage",
                ["tester_id": .string("tester-1"), "app_id": .string("app-1")],
                testFlightTesterUsageMetricResponse(
                    selfPath: "/v1/betaTesters/tester-1/metrics/betaTesterUsages",
                    dimensionsJSON: #"{"betaTesters":{"data":"tester-1"}}"#
                )
            ),
            (
                "metrics_build_beta_usage",
                ["build_id": .string("build-1")],
                testFlightBuildMetricResponse(
                    selfPath: "/v1/builds/build-1/metrics/betaBuildUsages",
                    topLevelSuffix: #", "included":[]"#
                )
            ),
            (
                "metrics_app_beta_tester_usage",
                ["app_id": .string("app-1")],
                #"{"data":[]}"#
            ),
            (
                "metrics_app_beta_tester_usage",
                ["app_id": .string("app-1")],
                #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/metrics/betaTesterUsages"},"meta":{}}"#
            ),
            (
                "metrics_app_beta_tester_usage",
                ["app_id": .string("app-1")],
                #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/metrics/betaTesterUsages"},"meta":{"paging":{"total":0}}}"#
            )
        ]
        for (tool, arguments, body) in cases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = MetricsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("app metric rejects included identity device and dimension drift")
    func appMetricRejectsIncludedAndDimensionDrift() async throws {
        let path = "/v1/apps/app-1/metrics/betaTesterUsages"
        let invalidBodies = [
            testFlightTesterMetricResponse(selfPath: path, includedType: "apps"),
            testFlightTesterMetricResponse(selfPath: path, duplicateIncluded: true),
            testFlightTesterMetricResponse(selfPath: path, includedID: "tester/1"),
            testFlightTesterMetricResponse(selfPath: path, includedPlatform: "FUTURE_OS"),
            testFlightTesterMetricResponse(selfPath: path, dimensionID: "tester/1"),
            testFlightTesterMetricResponse(selfPath: path, dimensionGroupBy: " /v1/betaTesters"),
            testFlightTesterMetricResponse(selfPath: "/v1/apps/app-2/metrics/betaTesterUsages")
        ]
        for body in invalidBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = MetricsWorker(httpClient: try await testFlightContractClient(transport))
            let result = try await worker.handleTool(.init(
                name: "metrics_app_beta_tester_usage",
                arguments: ["app_id": .string("app-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("invalid metric controls fail before transport")
    func invalidMetricControlsFailLocally() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = MetricsWorker(httpClient: try await testFlightContractClient(transport))

        let invalidPeriod = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_app_beta_tester_usage",
            arguments: ["app_id": .string("app-1"), "period": .string("P1D")]
        ))
        let invalidGrouping = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_group_beta_tester_usage",
            arguments: ["group_id": .string("group-1"), "group_by": .array([])]
        ))
        let invalidLimit = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_build_beta_usage",
            arguments: ["build_id": .string("build-1"), "limit": .int(201)]
        ))

        #expect(invalidPeriod.isError == true)
        #expect(invalidGrouping.isError == true)
        #expect(invalidLimit.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("unknown TestFlight parameters fail before transport")
    func unknownTestFlightParametersFailLocally() async throws {
        let recruitmentTransport = TestHTTPTransport(responses: [])
        let recruitmentWorker = BetaGroupsWorker(
            httpClient: try await testFlightContractClient(recruitmentTransport)
        )
        let recruitment = try await recruitmentWorker.handleTool(CallTool.Parameters(
            name: "beta_groups_get_recruitment_criteria",
            arguments: [
                "group_id": .string("group-1"),
                "groupd_id": .string("group-2")
            ]
        ))
        #expect(recruitment.isError == true)
        #expect(await recruitmentTransport.requestCount() == 0)

        let metricTransport = TestHTTPTransport(responses: [])
        let metricWorker = MetricsWorker(httpClient: try await testFlightContractClient(metricTransport))
        let metric = try await metricWorker.handleTool(CallTool.Parameters(
            name: "metrics_app_beta_tester_usage",
            arguments: [
                "app_id": .string("app-1"),
                "beta_testerid": .string("tester-1")
            ]
        ))
        #expect(metric.isError == true)
        #expect(await metricTransport.requestCount() == 0)
    }
}

private func testFlightContractClient(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func testFlightContractProperties(_ tool: Tool) throws -> [String: Value] {
    let schema = try testFlightContractSchema(tool)
    guard case .object(let properties)? = schema["properties"] else {
        throw TestFlightContractError.expectedObject
    }
    return properties
}

private func testFlightContractSchema(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema else {
        throw TestFlightContractError.expectedObject
    }
    return schema
}

private func testFlightContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw TestFlightContractError.expectedObject
    }
    return object
}

private func testFlightContractArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw TestFlightContractError.expectedArray
    }
    return array
}

private func testFlightContractStringSet(_ value: Value?) throws -> Set<String> {
    Set(try testFlightContractArray(value).compactMap { $0.stringValue })
}

private func testFlightContractQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func testFlightContractJSONBody(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func testFlightFirstMetricValues(_ result: CallTool.Result) throws -> [String: Value] {
    let root = try testFlightContractObject(result.structuredContent)
    let group = try testFlightContractObject(try #require(testFlightContractArray(root["groups"]).first))
    let point = try testFlightContractObject(try #require(testFlightContractArray(group["data_points"]).first))
    return try testFlightContractObject(point["values"])
}

private func testFlightCreateCriteriaArguments() -> [String: Value] {
    [
        "group_id": .string("group-1"),
        "device_filters": .array([
            .object([
                "device_family": .string("IPHONE"),
                "minimum_os_inclusive": .string("18.0"),
                "maximum_os_inclusive": .string("19.9")
            ])
        ])
    ]
}

private func testFlightUpdateNullArguments() -> [String: Value] {
    [
        "group_id": .string("group-1"),
        "criterion_id": .string("criterion-1"),
        "device_filters": .null
    ]
}

private func testFlightDeleteCriteriaArguments() -> [String: Value] {
    [
        "group_id": .string("group-1"),
        "criterion_id": .string("criterion-1"),
        "confirm_criterion_id": .string("criterion-1")
    ]
}

private func testFlightGroupResponse(
    type: String = "betaGroups",
    id: String = "group-1",
    selfPath: String = "/v1/betaGroups/group-1"
) -> String {
    """
    {
      "data":{"type":"\(type)","id":"\(id)","attributes":{"name":"Public Beta"}},
      "links":{"self":"https://api.example.test\(selfPath)"}
    }
    """
}

private func testFlightCriterionResponse(
    type: String = "betaRecruitmentCriteria",
    id: String = "criterion-1",
    filtersJSON: String? = nil,
    lastModifiedDate: String = "2026-07-20T00:00:00Z",
    selfPath: String = "/v1/betaGroups/group-1/betaRecruitmentCriteria"
) -> String {
    let filters = filtersJSON
        ?? #"[{"deviceFamily":"IPHONE","minimumOsInclusive":"18.0","maximumOsInclusive":"19.9"}]"#
    return """
    {
      "data":{"type":"\(type)","id":"\(id)","attributes":{"lastModifiedDate":"\(lastModifiedDate)","deviceFamilyOsVersionFilters":\(filters)}},
      "links":{"self":"https://api.example.test\(selfPath)"}
    }
    """
}

private func testFlightCriterionWithoutFiltersResponse(
    selfPath: String = "/v1/betaGroups/group-1/betaRecruitmentCriteria"
) -> String {
    """
    {
      "data":{"type":"betaRecruitmentCriteria","id":"criterion-1","attributes":{"lastModifiedDate":"2026-07-20T00:00:00Z"}},
      "links":{"self":"https://api.example.test\(selfPath)"}
    }
    """
}

private func testFlightOptionsResponse(
    type: String = "betaRecruitmentCriterionOptions",
    id: String = "IPHONE",
    deviceFamily: String = "IPHONE",
    selfPath: String = "/v1/betaRecruitmentCriterionOptions",
    duplicate: Bool = false,
    next: String? = nil,
    nextCursor: String? = nil
) -> String {
    let option = """
    {"type":"\(type)","id":"\(id)","attributes":{"deviceFamilyOsVersions":[{"deviceFamily":"\(deviceFamily)","osVersions":["18.0","19.0"]}]}}
    """
    let data = duplicate ? "\(option),\(option)" : option
    let nextLink = next.map { ", \"next\":\"\($0)\"" } ?? ""
    let nextCursorField = nextCursor.map { ", \"nextCursor\":\"\($0)\"" } ?? ""
    return """
    {
      "data":[\(data)],
      "links":{"self":"https://api.example.test\(selfPath)"\(nextLink)},
      "meta":{"paging":{"total":\(duplicate ? 2 : 1),"limit":25\(nextCursorField)}}
    }
    """
}

private func testFlightCompatibilityResponse(
    type: String = "betaRecruitmentCriterionCompatibleBuildChecks",
    id: String = "check-1",
    selfPath: String = "/v1/betaGroups/group-1/betaRecruitmentCriterionCompatibleBuildCheck"
) -> String {
    """
    {
      "data":{"type":"\(type)","id":"\(id)","attributes":{"hasCompatibleBuild":true}},
      "links":{"self":"https://api.example.test\(selfPath)"}
    }
    """
}

private func testFlightTesterResponse(
    appDevicesJSON: String = #"[{"model":"iPhone17,1","platform":"IOS","osVersion":"19.0","appBuildVersion":"441"}]"#
) -> String {
    """
    {"data":{"type":"betaTesters","id":"tester-1","attributes":{"email":"tester@example.com","firstName":"Test","lastName":"User","inviteType":"EMAIL","state":"INSTALLED","appDevices":\(appDevicesJSON)}}}
    """
}

private func testFlightTesterCollectionResponse(selfPath: String) -> String {
    """
    {
      "data":[{"type":"betaTesters","id":"tester-1","attributes":{"email":"tester@example.com","firstName":"Test","lastName":"User","inviteType":"EMAIL","state":"INSTALLED","appDevices":[{"model":"iPhone17,1","platform":"IOS","osVersion":"19.0","appBuildVersion":"441"}]}}],
      "links":{"self":"https://api.example.test\(selfPath)"},
      "meta":{"paging":{"total":1,"limit":25}}
    }
    """
}

private func testFlightBuildsIncludedTesterResponse() -> String {
    """
    {
      "data":[],
      "included":[{"type":"betaTesters","id":"tester-1","attributes":{"email":"tester@example.com","firstName":"Test","lastName":"User","inviteType":"EMAIL","state":"INSTALLED","appDevices":[{"model":"iPhone17,1","platform":"IOS","osVersion":"19.0","appBuildVersion":"441"}]}}],
      "links":{"self":"https://api.example.test/v1/builds"},
      "meta":{"paging":{"total":0,"limit":25}}
    }
    """
}

private func testFlightTesterMetricResponse(
    selfPath: String,
    valuesJSON: String = #"{"crashCount":2,"sessionCount":17,"feedbackCount":3}"#,
    includedType: String = "betaTesters",
    includedID: String = "tester-1",
    includedPlatform: String = "IOS",
    duplicateIncluded: Bool = false,
    dimensionID: String = "tester-1",
    dimensionGroupBy: String = "/v1/betaTesters"
) -> String {
    let tester = """
    {"type":"\(includedType)","id":"\(includedID)","attributes":{"email":"tester@example.com","firstName":"Test","lastName":"User","inviteType":"EMAIL","state":"INSTALLED","appDevices":[{"model":"iPhone17,1","platform":"\(includedPlatform)","osVersion":"19.0","appBuildVersion":"441"}]}}
    """
    let included = duplicateIncluded ? "\(tester),\(tester)" : tester
    return """
    {
      "data":[{"dataPoints":[{"start":"2026-07-01T00:00:00Z","end":"2026-07-02T00:00:00Z","values":\(valuesJSON)}],"dimensions":{"betaTesters":{"data":"\(dimensionID)","links":{"groupBy":"\(dimensionGroupBy)","related":"/v1/betaTesters/\(dimensionID)"}}}}],
      "included":[\(included)],
      "links":{"self":"https://api.example.test\(selfPath)"},
      "meta":{"paging":{"total":1,"limit":200}}
    }
    """
}

private func testFlightTesterUsageMetricResponse(
    selfPath: String,
    valuesJSON: String = #"{"crashCount":2,"sessionCount":17,"feedbackCount":3}"#,
    dimensionsJSON: String = #"{"apps":{"data":"app-1","links":{"groupBy":"/v1/apps","related":"/v1/apps/app-1"}}}"#
) -> String {
    """
    {
      "data":[{"dataPoints":[{"start":"2026-07-01T00:00:00Z","end":"2026-07-02T00:00:00Z","values":\(valuesJSON)}],"dimensions":\(dimensionsJSON)}],
      "links":{"self":"https://api.example.test\(selfPath)"},
      "meta":{"paging":{"total":1,"limit":25}}
    }
    """
}

private func testFlightPublicLinkMetricResponse(
    selfPath: String,
    valuesJSON: String = #"{"viewCount":120,"acceptedCount":70,"didNotAcceptCount":20,"didNotMeetCriteriaCount":30,"notRelevantRatio":0.1,"notClearRatio":0.2,"notInterestingRatio":0.3}"#
) -> String {
    """
    {
      "data":[{"dataPoints":[{"values":\(valuesJSON)}]}],
      "links":{"self":"https://api.example.test\(selfPath)"},
      "meta":{"paging":{"total":1,"limit":25}}
    }
    """
}

private func testFlightBuildMetricResponse(
    selfPath: String,
    valuesJSON: String = #"{"crashCount":1,"installCount":22,"sessionCount":44,"feedbackCount":5,"inviteCount":60}"#,
    topLevelSuffix: String = ""
) -> String {
    """
    {
      "data":[{"dataPoints":[{"values":\(valuesJSON)}]}],
      "links":{"self":"https://api.example.test\(selfPath)"},
      "meta":{"paging":{"total":1,"limit":25}}\(topLevelSuffix)
    }
    """
}

private func testFlightAPIError(status: Int) -> String {
    """
    {"errors":[{"id":"error-\(status)","status":"\(status)","code":"TEST_ERROR","title":"Test failure","detail":"Test failure"}]}
    """
}

private enum TestFlightContractError: Error {
    case expectedObject
    case expectedArray
}
