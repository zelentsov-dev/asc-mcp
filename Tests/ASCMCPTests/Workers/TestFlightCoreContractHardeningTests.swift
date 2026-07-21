import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("TestFlight Core Contract Hardening Tests")
struct TestFlightCoreContractHardeningTests {
    @Test("build list forwards current collection filters and preserves included resources")
    func buildListForwardsCurrentFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"included":[{"type":"apps","id":"app-1","attributes":{"name":"Example"}}],"meta":{"paging":{"total":12,"limit":25}}}"#
            )
        ])
        let worker = try await testFlightBuildsWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_list",
            arguments: [
                "app_id": .string("app-1"),
                "version": .array([.string("41"), .string("42")]),
                "processing_state": .array([.string("PROCESSING"), .string("VALID")]),
                "app_store_version_ids": .array([.string("version-1")]),
                "beta_review_states": .array([.string("WAITING_FOR_REVIEW"), .string("APPROVED")]),
                "beta_group_ids": .array([.string("group-1"), .string("group-2")]),
                "build_audience_types": .array([.string("APP_STORE_ELIGIBLE")]),
                "build_ids": .array([.string("build-1")]),
                "pre_release_platforms": .array([.string("IOS"), .string("VISION_OS")]),
                "pre_release_versions": .array([.string("2.0")]),
                "pre_release_version_ids": .array([.string("pre-1")]),
                "uses_non_exempt_encryption": .bool(false),
                "uses_non_exempt_encryption_set": .bool(true)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = testFlightQuery(request)
        #expect(query["filter[version]"] == "41,42")
        #expect(query["filter[processingState]"] == "PROCESSING,VALID")
        #expect(query["filter[appStoreVersion]"] == "version-1")
        #expect(query["filter[betaAppReviewSubmission.betaReviewState]"] == "WAITING_FOR_REVIEW,APPROVED")
        #expect(query["filter[betaGroups]"] == "group-1,group-2")
        #expect(query["filter[buildAudienceType]"] == "APP_STORE_ELIGIBLE")
        #expect(query["filter[id]"] == "build-1")
        #expect(query["filter[preReleaseVersion.platform]"] == "IOS,VISION_OS")
        #expect(query["filter[preReleaseVersion.version]"] == "2.0")
        #expect(query["filter[preReleaseVersion]"] == "pre-1")
        #expect(query["filter[usesNonExemptEncryption]"] == "false")
        #expect(query["exists[usesNonExemptEncryption]"] == "true")

        let payload = try testFlightObject(result.structuredContent)
        #expect(payload["total"] == .int(12))
        guard case .array(let included)? = payload["included"] else {
            Issue.record("Expected included build resources")
            return
        }
        #expect(included.count == 1)
    }

    @Test("readiness does not classify expired or pre-review builds as testable")
    func readinessUsesTestableStatesOnly() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"builds","id":"build-1","attributes":{"version":"42","processingState":"VALID","expired":true,"usesNonExemptEncryption":false},"relationships":{"buildBetaDetail":{"data":{"type":"buildBetaDetails","id":"detail-1"}}}},"included":[{"type":"buildBetaDetails","id":"detail-1","attributes":{"internalBuildState":"EXPIRED","externalBuildState":"WAITING_FOR_BETA_REVIEW"}}]}"#
            )
        ])
        let worker = try await testFlightBuildProcessingWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_check_readiness",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError != true)
        let payload = try testFlightObject(result.structuredContent)
        let readiness = try testFlightObject(payload["readiness"])
        #expect(readiness["buildPrerequisitesSatisfied"] == .bool(false))
        #expect(readiness["isReadyForInternalTesting"] == .bool(false))
        #expect(readiness["isReadyForExternalTesting"] == .bool(false))
        #expect(readiness["isReadyForBetaReviewSubmission"] == .bool(false))
        #expect(readiness["appStoreSubmissionStatus"] == .string("NOT_DETERMINED"))
        #expect(readiness["isReadyForSubmission"] == nil)
    }

    @Test("beta detail uses the direct related-resource endpoint")
    func betaDetailUsesDirectEndpoint() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"buildBetaDetails","id":"detail-1","attributes":{"internalBuildState":"READY_FOR_BETA_TESTING"}}}"#)
        ])
        let worker = BuildBetaDetailsWorker(httpClient: try await testFlightClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_get_beta_detail",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.path == "/v1/builds/build-1/buildBetaDetail")
    }

    @Test("beta detail update rejects an empty patch")
    func betaDetailUpdateRejectsEmptyPatch() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BuildBetaDetailsWorker(httpClient: try await testFlightClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_update_beta_detail",
            arguments: ["beta_detail_id": .string("detail-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("beta group list forwards public-link and identity filters")
    func betaGroupListForwardsFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"meta":{"paging":{"total":3,"limit":25}}}"#)
        ])
        let worker = try await testFlightBetaGroupsWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_list",
            arguments: [
                "app_id": .string("app-1"),
                "name": .array([.string("External")]),
                "build_ids": .array([.string("build-1")]),
                "group_ids": .array([.string("group-1")]),
                "public_link_enabled": .bool(true),
                "public_link_limit_enabled": .bool(true),
                "public_link": .string("https://testflight.apple.com/join/example"),
                "sort": .string("-createdDate")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = testFlightQuery(request)
        #expect(query["filter[app]"] == "app-1")
        #expect(query["filter[name]"] == "External")
        #expect(query["filter[builds]"] == "build-1")
        #expect(query["filter[id]"] == "group-1")
        #expect(query["filter[publicLinkEnabled]"] == "true")
        #expect(query["filter[publicLinkLimitEnabled]"] == "true")
        #expect(query["filter[publicLink]"] == "https://testflight.apple.com/join/example")
        #expect(query["sort"] == "-createdDate")
        #expect(try testFlightObject(result.structuredContent)["total"] == .int(3))
    }

    @Test("beta group create sends current public-link fields and initial relationships")
    func betaGroupCreateSendsCurrentFields() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"betaGroups","id":"group-1","attributes":{"name":"External","publicLinkEnabled":true,"publicLinkLimitEnabled":true,"publicLinkLimit":500,"iosBuildsAvailableForAppleSiliconMac":true,"iosBuildsAvailableForAppleVision":false}}}"#
            )
        ])
        let worker = try await testFlightBetaGroupsWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("External"),
                "public_link_enabled": .bool(true),
                "public_link_limit_enabled": .bool(true),
                "public_link_limit": .int(500),
                "build_ids": .array([.string("build-1")]),
                "tester_ids": .array([.string("tester-1")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try testFlightBody(request)
        let data = try testFlightDictionary(body["data"])
        let attributes = try testFlightDictionary(data["attributes"])
        let relationships = try testFlightDictionary(data["relationships"])
        #expect(attributes["publicLinkLimitEnabled"] as? Bool == true)
        #expect(attributes["publicLinkLimit"] as? Int == 500)
        #expect(try testFlightRelationshipIDs(relationships["builds"]) == ["build-1"])
        #expect(try testFlightRelationshipIDs(relationships["betaTesters"]) == ["tester-1"])
    }

    @Test("beta group update rejects an empty patch")
    func betaGroupUpdateRejectsEmptyPatch() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await testFlightBetaGroupsWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_update",
            arguments: ["group_id": .string("group-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("beta group update sends current platform availability fields")
    func betaGroupUpdateSendsCurrentAvailabilityFields() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"betaGroups","id":"group-1","attributes":{"publicLinkLimitEnabled":true,"iosBuildsAvailableForAppleSiliconMac":true,"iosBuildsAvailableForAppleVision":false}}}"#
            )
        ])
        let worker = try await testFlightBetaGroupsWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_update",
            arguments: [
                "group_id": .string("group-1"),
                "public_link_limit_enabled": .bool(true),
                "ios_builds_available_for_apple_silicon_mac": .bool(true),
                "ios_builds_available_for_apple_vision": .bool(false)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try testFlightBody(request)
        let data = try testFlightDictionary(body["data"])
        let attributes = try testFlightDictionary(data["attributes"])
        #expect(attributes["publicLinkLimitEnabled"] as? Bool == true)
        #expect(attributes["iosBuildsAvailableForAppleSiliconMac"] as? Bool == true)
        #expect(attributes["iosBuildsAvailableForAppleVision"] as? Bool == false)
    }

    @Test("beta group update preserves explicit null")
    func betaGroupUpdatePreservesExplicitNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"betaGroups","id":"group-1"}}"#)
        ])
        let worker = try await testFlightBetaGroupsWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_groups_update",
            arguments: [
                "group_id": .string("group-1"),
                "public_link_limit": .null,
                "feedback_enabled": .null
            ]
        ))

        #expect(result.isError != true)
        let body = try testFlightBody(try #require(await transport.recordedRequests().first))
        let data = try testFlightDictionary(body["data"])
        let attributes = try testFlightDictionary(data["attributes"])
        #expect(attributes["publicLinkLimit"] is NSNull)
        #expect(attributes["feedbackEnabled"] is NSNull)
        #expect(Set(attributes.keys) == ["publicLinkLimit", "feedbackEnabled"])
    }

    @Test("beta tester can be created without a group")
    func betaTesterCreateWithoutGroup() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"betaTesters","id":"tester-1","attributes":{"email":"person@example.com"}}}"#)
        ])
        let worker = try await testFlightBetaTestersWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_testers_create",
            arguments: ["email": .string("person@example.com")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try testFlightBody(request)
        let data = try testFlightDictionary(body["data"])
        #expect(data["relationships"] == nil)
    }

    @Test("beta tester create rejects malformed email before network")
    func betaTesterCreateRejectsMalformedEmail() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await testFlightBetaTestersWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_testers_create",
            arguments: ["email": .string("not-an-email")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("relationship ID arrays reject mixed values atomically")
    func relationshipIDArraysRejectMixedValues() async throws {
        let transport = TestHTTPTransport(responses: [])
        let invalidIDs: Value = .array([.string("valid-id"), .int(7)])

        let groupsWorker = try await testFlightBetaGroupsWorker(transport)
        for (tool, field) in [
            ("beta_groups_add_testers", "tester_ids"),
            ("beta_groups_remove_testers", "tester_ids"),
            ("beta_groups_add_builds", "build_ids"),
            ("beta_groups_remove_builds", "build_ids")
        ] {
            let result = try await groupsWorker.handleTool(.init(
                name: tool,
                arguments: ["group_id": .string("group-1"), field: invalidIDs]
            ))
            #expect(result.isError == true)
        }

        let testersWorker = try await testFlightBetaTestersWorker(transport)
        for (tool, field) in [
            ("beta_testers_add_to_groups", "group_ids"),
            ("beta_testers_remove_from_groups", "group_ids"),
            ("beta_testers_add_to_builds", "build_ids"),
            ("beta_testers_remove_from_builds", "build_ids")
        ] {
            let result = try await testersWorker.handleTool(.init(
                name: tool,
                arguments: ["beta_tester_id": .string("tester-1"), field: invalidIDs]
            ))
            #expect(result.isError == true)
        }

        let buildsWorker = BuildBetaDetailsWorker(httpClient: try await testFlightClient(transport))
        for (tool, field) in [
            ("builds_add_to_beta_groups", "group_ids"),
            ("builds_add_individual_testers", "beta_tester_ids"),
            ("builds_remove_individual_testers", "beta_tester_ids")
        ] {
            let result = try await buildsWorker.handleTool(.init(
                name: tool,
                arguments: ["build_id": .string("build-1"), field: invalidIDs]
            ))
            #expect(result.isError == true)
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("relationship creates require Apple's exact 204 status")
    func relationshipCreatesRequireExact204() async throws {
        let groupTesterTransport = TestHTTPTransport(responses: [.init(statusCode: 201, body: "")])
        let groupTesterWorker = try await testFlightBetaGroupsWorker(groupTesterTransport)
        let groupTesterResult = try await groupTesterWorker.handleTool(.init(
            name: "beta_groups_add_testers",
            arguments: ["group_id": .string("group-1"), "tester_ids": .array([.string("tester-1")])]
        ))
        try testFlightExpectUnverified204(groupTesterResult)

        let groupBuildTransport = TestHTTPTransport(responses: [.init(statusCode: 201, body: "")])
        let groupBuildWorker = try await testFlightBetaGroupsWorker(groupBuildTransport)
        let groupBuildResult = try await groupBuildWorker.handleTool(.init(
            name: "beta_groups_add_builds",
            arguments: ["group_id": .string("group-1"), "build_ids": .array([.string("build-1")])]
        ))
        try testFlightExpectUnverified204(groupBuildResult)

        let buildGroupTransport = TestHTTPTransport(responses: [.init(statusCode: 201, body: "")])
        let buildGroupWorker = BuildBetaDetailsWorker(httpClient: try await testFlightClient(buildGroupTransport))
        let buildGroupResult = try await buildGroupWorker.handleTool(.init(
            name: "builds_add_to_beta_groups",
            arguments: ["build_id": .string("build-1"), "group_ids": .array([.string("group-1")])]
        ))
        try testFlightExpectUnverified204(buildGroupResult)

        let buildTesterTransport = TestHTTPTransport(responses: [.init(statusCode: 201, body: "")])
        let buildTesterWorker = BuildBetaDetailsWorker(httpClient: try await testFlightClient(buildTesterTransport))
        let buildTesterResult = try await buildTesterWorker.handleTool(.init(
            name: "builds_add_individual_testers",
            arguments: ["build_id": .string("build-1"), "beta_tester_ids": .array([.string("tester-1")])]
        ))
        try testFlightExpectUnverified204(buildTesterResult)

        let testerGroupTransport = TestHTTPTransport(responses: [.init(statusCode: 201, body: "")])
        let testerGroupWorker = try await testFlightBetaTestersWorker(testerGroupTransport)
        let testerGroupResult = try await testerGroupWorker.handleTool(.init(
            name: "beta_testers_add_to_groups",
            arguments: ["beta_tester_id": .string("tester-1"), "group_ids": .array([.string("group-1")])]
        ))
        try testFlightExpectUnverified204(testerGroupResult)

        let testerBuildTransport = TestHTTPTransport(responses: [.init(statusCode: 201, body: "")])
        let testerBuildWorker = try await testFlightBetaTestersWorker(testerBuildTransport)
        let testerBuildResult = try await testerBuildWorker.handleTool(.init(
            name: "beta_testers_add_to_builds",
            arguments: ["beta_tester_id": .string("tester-1"), "build_ids": .array([.string("build-1")])]
        ))
        try testFlightExpectUnverified204(testerBuildResult)
    }

    @Test("resource patch decode failures preserve committed-unverified state")
    func resourcePatchDecodeFailuresPreserveMutationState() async throws {
        let betaDetailTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":"#)
        ])
        let betaDetailWorker = BuildBetaDetailsWorker(httpClient: try await testFlightClient(betaDetailTransport))
        let betaDetailResult = try await betaDetailWorker.handleTool(.init(
            name: "builds_update_beta_detail",
            arguments: ["beta_detail_id": .string("detail-1"), "auto_notify": .bool(true)]
        ))
        try testFlightExpectMutationUnverified(
            betaDetailResult,
            method: "PATCH",
            expectedStatusCode: 200,
            statusCode: 200
        )

        let processingTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":"#)
        ])
        let processingWorker = try await testFlightBuildProcessingWorker(processingTransport)
        let processingResult = try await processingWorker.handleTool(.init(
            name: "builds_update_encryption",
            arguments: [
                "build_id": .string("build-1"),
                "uses_non_exempt_encryption": .bool(false)
            ]
        ))
        try testFlightExpectMutationUnverified(
            processingResult,
            method: "PATCH",
            expectedStatusCode: 200,
            statusCode: 200
        )

        let licenseTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":"#)
        ])
        let licenseWorker = BetaLicenseAgreementsWorker(httpClient: try await testFlightClient(licenseTransport))
        let licenseResult = try await licenseWorker.handleTool(.init(
            name: "beta_license_update",
            arguments: [
                "beta_license_agreement_id": .string("license-1"),
                "agreement_text": .string("Terms")
            ]
        ))
        try testFlightExpectMutationUnverified(
            licenseResult,
            method: "PATCH",
            expectedStatusCode: 200,
            statusCode: 200
        )
    }

    @Test("related collection limits fail closed outside Apple's range")
    func relatedCollectionLimitsFailClosed() async throws {
        let transport = TestHTTPTransport(responses: [])
        let buildWorker = BuildBetaDetailsWorker(httpClient: try await testFlightClient(transport))
        for tool in [
            "builds_list_beta_localizations",
            "builds_get_beta_groups",
            "builds_get_beta_testers",
            "builds_list_individual_testers"
        ] {
            let result = try await buildWorker.handleTool(.init(
                name: tool,
                arguments: ["build_id": .string("build-1"), "limit": .int(201)]
            ))
            #expect(result.isError == true)
        }

        let groupWorker = try await testFlightBetaGroupsWorker(transport)
        let groupResult = try await groupWorker.handleTool(.init(
            name: "beta_groups_list_testers",
            arguments: ["group_id": .string("group-1"), "limit": .int(0)]
        ))
        #expect(groupResult.isError == true)

        let groupListResult = try await groupWorker.handleTool(.init(
            name: "beta_groups_list",
            arguments: ["app_id": .string("app-1"), "limit": .string("25")]
        ))
        #expect(groupListResult.isError == true)

        let testerWorker = try await testFlightBetaTestersWorker(transport)
        let testerResult = try await testerWorker.handleTool(.init(
            name: "beta_testers_list_apps",
            arguments: ["tester_id": .string("tester-1"), "limit": .string("25")]
        ))
        #expect(testerResult.isError == true)

        let testerListResult = try await testerWorker.handleTool(.init(
            name: "beta_testers_list",
            arguments: ["limit": .int(201)]
        ))
        #expect(testerListResult.isError == true)

        let testerSearchResult = try await testerWorker.handleTool(.init(
            name: "beta_testers_search",
            arguments: ["email": .string("person@example.com"), "limit": .int(0)]
        ))
        #expect(testerSearchResult.isError == true)

        let buildsWorker = try await testFlightBuildsWorker(transport)
        let buildsResult = try await buildsWorker.handleTool(.init(
            name: "builds_list",
            arguments: ["app_id": .string("app-1"), "limit": .int(500)]
        ))
        #expect(buildsResult.isError == true)

        let preReleaseWorker = try await testFlightPreReleaseWorker(transport)
        let preReleaseResult = try await preReleaseWorker.handleTool(.init(
            name: "pre_release_list_builds",
            arguments: ["pre_release_version_id": .string("pre-1"), "limit": .int(-1)]
        ))
        #expect(preReleaseResult.isError == true)

        let preReleaseListResult = try await preReleaseWorker.handleTool(.init(
            name: "pre_release_list",
            arguments: ["limit": .string("25")]
        ))
        #expect(preReleaseListResult.isError == true)

        let licenseWorker = BetaLicenseAgreementsWorker(httpClient: try await testFlightClient(transport))
        let licenseResult = try await licenseWorker.handleTool(.init(
            name: "beta_license_list",
            arguments: ["limit": .int(500)]
        ))
        #expect(licenseResult.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("beta tester create supports direct build assignment")
    func betaTesterCreateWithBuild() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"betaTesters","id":"tester-1","attributes":{"email":"person@example.com"}}}"#)
        ])
        let worker = try await testFlightBetaTestersWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_testers_create",
            arguments: [
                "email": .string("person@example.com"),
                "build_ids": .array([.string("build-1"), .string("build-2")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try testFlightBody(request)
        let data = try testFlightDictionary(body["data"])
        let relationships = try testFlightDictionary(data["relationships"])
        #expect(try testFlightRelationshipIDs(relationships["builds"]) == ["build-1", "build-2"])
    }

    @Test("beta tester get decodes included builds")
    func betaTesterGetDecodesBuilds() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"betaTesters","id":"tester-1","attributes":{"email":"person@example.com"}},"included":[{"type":"builds","id":"build-1","attributes":{"version":"42","processingState":"VALID","expired":false,"buildAudienceType":"APP_STORE_ELIGIBLE"}}]}"#
            )
        ])
        let worker = try await testFlightBetaTestersWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_testers_get",
            arguments: [
                "tester_id": .string("tester-1"),
                "include": .array([.string("builds")])
            ]
        ))

        #expect(result.isError != true)
        #expect(testFlightQuery(try #require(await transport.recordedRequests().first))["include"] == "builds")
        let payload = try testFlightObject(result.structuredContent)
        let tester = try testFlightObject(payload["beta_tester"])
        guard case .array(let builds)? = tester["builds"] else {
            Issue.record("Expected included builds")
            return
        }
        #expect(builds.count == 1)
    }

    @Test("beta tester delete preserves documented acceptance states", arguments: [204, 202, 200])
    func betaTesterDeletePreservesAcceptanceState(_ statusCode: Int) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: statusCode, body: "")
        ])
        let worker = try await testFlightBetaTestersWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_testers_delete",
            arguments: ["tester_id": .string("tester-1")]
        ))

        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "DELETE")
        #expect(requests.first?.url?.path == "/v1/betaTesters/tester-1")

        let payload = try testFlightObject(result.structuredContent)
        #expect(payload["statusCode"] == .int(statusCode))
        #expect(payload["tester_id"] == .string("tester-1"))
        #expect(payload["retrySafe"] == .bool(false))

        switch statusCode {
        case 204:
            #expect(result.isError != true)
            #expect(payload["success"] == .bool(true))
            #expect(payload["deletionState"] == .string("confirmed"))
            #expect(payload["operationCommitted"] == .bool(true))
            #expect(payload["processingComplete"] == .bool(true))
            #expect(payload["inspection"] == nil)
        case 202:
            #expect(result.isError != true)
            #expect(payload["success"] == .bool(true))
            #expect(payload["deletionState"] == .string("accepted"))
            #expect(payload["operationCommitState"] == .string("accepted"))
            #expect(payload["acceptedForProcessing"] == .bool(true))
            #expect(payload["processingComplete"] == .bool(false))
            #expect(payload["outcomeUnknown"] == .bool(false))
            #expect(payload["inspectionRequired"] == .bool(true))
            let inspection = try testFlightObject(payload["inspection"])
            #expect(inspection["tool"] == .string("beta_testers_get"))
            let arguments = try testFlightObject(inspection["arguments"])
            #expect(arguments == ["tester_id": .string("tester-1")])
        default:
            #expect(result.isError == true)
            #expect(payload["success"] == .bool(false))
            #expect(payload["deletionState"] == .string("committed_unverified"))
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["operationCommitted"] == .bool(true))
            #expect(payload["processingComplete"] == .bool(false))
            #expect(payload["inspectionRequired"] == .bool(true))
            #expect(payload["outcomeUnknown"] == nil)
            let inspection = try testFlightObject(payload["inspection"])
            #expect(inspection["tool"] == .string("beta_testers_get"))
            let arguments = try testFlightObject(inspection["arguments"])
            #expect(arguments == ["tester_id": .string("tester-1")])
        }
    }

    @Test("beta tester app removal preserves documented acceptance states", arguments: [204, 202, 200])
    func betaTesterAppRemovalPreservesAcceptanceState(_ statusCode: Int) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: statusCode, body: "")
        ])
        let worker = try await testFlightBetaTestersWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_testers_remove_from_app",
            arguments: [
                "beta_tester_id": .string("tester-1"),
                "app_id": .string("app-1")
            ]
        ))

        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "DELETE")
        #expect(requests.first?.url?.path == "/v1/betaTesters/tester-1/relationships/apps")
        let requestBody = try testFlightBody(try #require(requests.first))
        #expect(try testFlightRelationshipIDs(requestBody) == ["app-1"])

        let payload = try testFlightObject(result.structuredContent)
        #expect(payload["statusCode"] == .int(statusCode))
        #expect(payload["beta_tester_id"] == .string("tester-1"))
        #expect(payload["app_id"] == .string("app-1"))
        #expect(payload["retrySafe"] == .bool(false))

        switch statusCode {
        case 204:
            #expect(result.isError != true)
            #expect(payload["success"] == .bool(true))
            #expect(payload["deletionState"] == .string("confirmed"))
            #expect(payload["operationCommitted"] == .bool(true))
            #expect(payload["processingComplete"] == .bool(true))
            #expect(payload["inspection"] == nil)
        case 202:
            #expect(result.isError != true)
            #expect(payload["success"] == .bool(true))
            #expect(payload["deletionState"] == .string("accepted"))
            #expect(payload["operationCommitState"] == .string("accepted"))
            #expect(payload["acceptedForProcessing"] == .bool(true))
            #expect(payload["processingComplete"] == .bool(false))
            #expect(payload["outcomeUnknown"] == .bool(false))
            #expect(payload["inspectionRequired"] == .bool(true))
            let inspection = try testFlightObject(payload["inspection"])
            #expect(inspection["tool"] == .string("beta_testers_list_apps"))
            let arguments = try testFlightObject(inspection["arguments"])
            #expect(arguments == ["tester_id": .string("tester-1"), "limit": .int(200)])
            #expect(inspection["paginationRequired"] == .bool(true))
            #expect(inspection["instruction"] == .string("Inspect this exact tester with limit 200, then follow every returned next_url with the same tester_id and limit until no next_url remains. Only absence of app_id 'app-1' across the complete collection confirms removal before another delete attempt."))
        default:
            #expect(result.isError == true)
            #expect(payload["success"] == .bool(false))
            #expect(payload["deletionState"] == .string("committed_unverified"))
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["operationCommitted"] == .bool(true))
            #expect(payload["processingComplete"] == .bool(false))
            #expect(payload["inspectionRequired"] == .bool(true))
            #expect(payload["outcomeUnknown"] == nil)
            let inspection = try testFlightObject(payload["inspection"])
            #expect(inspection["tool"] == .string("beta_testers_list_apps"))
            let arguments = try testFlightObject(inspection["arguments"])
            #expect(arguments == ["tester_id": .string("tester-1"), "limit": .int(200)])
            #expect(inspection["paginationRequired"] == .bool(true))
            #expect(inspection["instruction"] == .string("Inspect this exact tester with limit 200, then follow every returned next_url with the same tester_id and limit until no next_url remains. Only absence of app_id 'app-1' across the complete collection confirms removal before another delete attempt."))
        }
    }

    @Test("pre-release list forwards related build filters and exposes relationships")
    func preReleaseListForwardsBuildFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"preReleaseVersions","id":"pre-1","attributes":{"version":"2.0","platform":"IOS"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}},"builds":{"data":[{"type":"builds","id":"build-1"}]}}}],"meta":{"paging":{"total":1,"limit":25}}}"#
            )
        ])
        let worker = try await testFlightPreReleaseWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pre_release_list",
            arguments: [
                "platform": .array([.string("IOS"), .string("VISION_OS")]),
                "build_audience_types": .array([.string("APP_STORE_ELIGIBLE")]),
                "build_expired": .bool(false),
                "build_processing_states": .array([.string("VALID")]),
                "build_versions": .array([.string("42")]),
                "build_ids": .array([.string("build-1")])
            ]
        ))

        #expect(result.isError != true)
        let query = testFlightQuery(try #require(await transport.recordedRequests().first))
        #expect(query["filter[platform]"] == "IOS,VISION_OS")
        #expect(query["filter[builds.buildAudienceType]"] == "APP_STORE_ELIGIBLE")
        #expect(query["filter[builds.expired]"] == "false")
        #expect(query["filter[builds.processingState]"] == "VALID")
        #expect(query["filter[builds.version]"] == "42")
        #expect(query["filter[builds]"] == "build-1")

        let payload = try testFlightObject(result.structuredContent)
        #expect(payload["total"] == .int(1))
        guard case .array(let versions)? = payload["pre_release_versions"],
              let first = versions.first else {
            Issue.record("Expected pre-release version")
            return
        }
        let version = try testFlightObject(first)
        let relationships = try testFlightObject(version["relationships"])
        #expect(relationships["appId"] == .string("app-1"))
        #expect(relationships["buildIds"] == .array([.string("build-1")]))
    }

    @Test("current beta group and build model fields decode")
    func currentModelFieldsDecode() throws {
        let groupData = #"{"type":"betaGroups","id":"group-1","attributes":{"iosBuildsAvailableForAppleSiliconMac":true,"iosBuildsAvailableForAppleVision":false,"publicLinkLimitEnabled":true},"relationships":{"betaRecruitmentCriteria":{"data":{"type":"betaRecruitmentCriteria","id":"criteria-1"}},"betaRecruitmentCriterionCompatibleBuildCheck":{"links":{"related":"https://api.example.test/v1/betaGroups/group-1/betaRecruitmentCriterionCompatibleBuildCheck"}}}}"#.data(using: .utf8)!
        let group = try JSONDecoder().decode(ASCBetaGroup.self, from: groupData)
        #expect(group.attributes?.iosBuildsAvailableForAppleSiliconMac == true)
        #expect(group.attributes?.iosBuildsAvailableForAppleVision == false)
        #expect(group.attributes?.publicLinkLimitEnabled == true)
        #expect(group.relationships?.betaRecruitmentCriteria?.data?.id == "criteria-1")
        #expect(group.relationships?.betaRecruitmentCriterionCompatibleBuildCheck?.links?.related != nil)

        let buildData = #"{"type":"builds","id":"build-1","attributes":{"computedMinVisionOsVersion":"2.0"},"relationships":{"icons":{"data":[{"type":"buildIcons","id":"icon-1"}]}}}"#.data(using: .utf8)!
        let build = try JSONDecoder().decode(ASCBuild.self, from: buildData)
        #expect(build.attributes.computedMinVisionOsVersion == "2.0")
        #expect(build.relationships?.icons?.data?.first?.id == "icon-1")
    }

    @Test("public schemas expose fixed TestFlight core contracts")
    func schemasExposeFixedContracts() async throws {
        let transport = TestHTTPTransport(responses: [])
        let testerWorker = try await testFlightBetaTestersWorker(transport)
        let testerTools = await testerWorker.getTools()
        let createTester = try #require(testerTools.first { $0.name == "beta_testers_create" })
        let createTesterProperties = try testFlightProperties(createTester)
        #expect(try testFlightRequired(createTester) == ["email"])
        #expect(createTesterProperties["build_ids"] != nil)
        let emailSchema = try testFlightObject(try #require(createTesterProperties["email"]))
        #expect(emailSchema["format"] == .string("email"))

        let buildsWorker = try await testFlightBuildsWorker(transport)
        let buildTools = await buildsWorker.getTools()
        let listBuilds = try #require(buildTools.first { $0.name == "builds_list" })
        #expect(try testFlightProperties(listBuilds)["pre_release_platforms"] != nil)
        #expect(try testFlightProperties(listBuilds)["uses_non_exempt_encryption_set"] != nil)

        let groupsWorker = try await testFlightBetaGroupsWorker(transport)
        let groupTools = await groupsWorker.getTools()
        let updateGroup = try #require(groupTools.first { $0.name == "beta_groups_update" })
        let updateGroupProperties = try testFlightProperties(updateGroup)
        #expect(updateGroupProperties["ios_builds_available_for_apple_vision"] != nil)
        let listGroupTesters = try #require(groupTools.first { $0.name == "beta_groups_list_testers" })
        let listGroupTesterProperties = try testFlightProperties(listGroupTesters)
        let limitSchema = try testFlightObject(try #require(listGroupTesterProperties["limit"]))
        #expect(limitSchema["minimum"] == .int(1))
        #expect(limitSchema["maximum"] == .int(200))
        #expect(limitSchema["default"] == .int(25))
        let nullableLimit = try testFlightObject(try #require(updateGroupProperties["public_link_limit"]))
        #expect(nullableLimit["type"] == .array([.string("integer"), .string("null")]))
    }
}

private func testFlightBuildsWorker(_ transport: TestHTTPTransport) async throws -> BuildsWorker {
    BuildsWorker(httpClient: try await testFlightClient(transport))
}

private func testFlightBuildProcessingWorker(_ transport: TestHTTPTransport) async throws -> BuildProcessingWorker {
    BuildProcessingWorker(httpClient: try await testFlightClient(transport))
}

private func testFlightBetaGroupsWorker(_ transport: TestHTTPTransport) async throws -> BetaGroupsWorker {
    BetaGroupsWorker(httpClient: try await testFlightClient(transport))
}

private func testFlightBetaTestersWorker(_ transport: TestHTTPTransport) async throws -> BetaTestersWorker {
    BetaTestersWorker(httpClient: try await testFlightClient(transport))
}

private func testFlightPreReleaseWorker(_ transport: TestHTTPTransport) async throws -> PreReleaseVersionsWorker {
    PreReleaseVersionsWorker(httpClient: try await testFlightClient(transport))
}

private func testFlightClient(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func testFlightQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
    })
}

private func testFlightBody(_ request: URLRequest) throws -> [String: Any] {
    guard let data = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TestFlightCoreContractFailure.expectedDictionary
    }
    return object
}

private func testFlightDictionary(_ value: Any?) throws -> [String: Any] {
    guard let dictionary = value as? [String: Any] else {
        throw TestFlightCoreContractFailure.expectedDictionary
    }
    return dictionary
}

private func testFlightRelationshipIDs(_ value: Any?) throws -> [String] {
    let relationship = try testFlightDictionary(value)
    guard let data = relationship["data"] as? [[String: Any]] else {
        throw TestFlightCoreContractFailure.expectedArray
    }
    return data.compactMap { $0["id"] as? String }
}

private func testFlightObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw TestFlightCoreContractFailure.expectedObject
    }
    return object
}

private func testFlightProperties(_ tool: Tool) throws -> [String: Value] {
    let root = try testFlightObject(tool.inputSchema)
    return try testFlightObject(root["properties"])
}

private func testFlightRequired(_ tool: Tool) throws -> [String] {
    let root = try testFlightObject(tool.inputSchema)
    guard case .array(let values)? = root["required"] else {
        throw TestFlightCoreContractFailure.expectedArray
    }
    return values.compactMap(\.stringValue)
}

private func testFlightExpectUnverified204(_ result: CallTool.Result) throws {
    try testFlightExpectMutationUnverified(
        result,
        method: "POST",
        expectedStatusCode: 204,
        statusCode: 201
    )
}

private func testFlightExpectMutationUnverified(
    _ result: CallTool.Result,
    method: String,
    expectedStatusCode: Int,
    statusCode: Int
) throws {
    #expect(result.isError == true)
    let payload = try testFlightObject(result.structuredContent)
    let details = try testFlightObject(payload["details"])
    #expect(payload["operationCommitState"] == .string("committed_unverified"))
    #expect(details["type"] == .string("mutation_unverified"))
    #expect(details["method"] == .string(method))
    #expect(details["expectedStatusCode"] == .int(expectedStatusCode))
    #expect(details["statusCode"] == .int(statusCode))
}

private enum TestFlightCoreContractFailure: Error {
    case expectedArray
    case expectedDictionary
    case expectedObject
}
