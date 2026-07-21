import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Build Run Safety Contract Tests")
struct XcodeCloudBuildRunSafetyContractTests {
    @Test("build run start requires an exact 201 response with canonical identity and document link")
    func startBuildRunRequiresExactCreateReceipt() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "ciBuildRuns",
                "id": "run-created",
                "attributes": {
                  "number": 18,
                  "executionProgress": "PENDING",
                  "startReason": "MANUAL"
                },
                "relationships": {
                  "workflow": { "data": { "type": "ciWorkflows", "id": "workflow-1" } }
                },
                "links": { "self": "https://api.example.test/v1/ciBuildRuns/run-created" }
              },
              "included": [{
                "type": "ciWorkflows",
                "id": "workflow-1",
                "attributes": { "name": "Release" },
                "links": { "self": "https://api.example.test/v1/ciWorkflows/workflow-1" }
              }],
              "links": { "self": "https://api.example.test/v1/ciBuildRuns" }
            }
            """)
        ])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "source_branch_or_tag_id": .string("branch-main"),
                "clean": .bool(true)
            ]
        ))

        #expect(result.isError == nil)
        let requests = await transport.recordedRequests()
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/ciBuildRuns")
        let requestBody = try xcodeCloudSafetyJSONObject(request.httpBody)
        let data = try xcodeCloudSafetyJSONObject(requestBody["data"])
        let relationships = try xcodeCloudSafetyJSONObject(data["relationships"])
        let workflow = try xcodeCloudSafetyJSONObject(relationships["workflow"])
        let workflowData = try xcodeCloudSafetyJSONObject(workflow["data"])
        let source = try xcodeCloudSafetyJSONObject(relationships["sourceBranchOrTag"])
        let sourceData = try xcodeCloudSafetyJSONObject(source["data"])
        let attributes = try xcodeCloudSafetyJSONObject(data["attributes"])
        #expect(workflowData["type"] as? String == "ciWorkflows")
        #expect(workflowData["id"] as? String == "workflow-1")
        #expect(sourceData["type"] as? String == "scmGitReferences")
        #expect(sourceData["id"] as? String == "branch-main")
        #expect(attributes["clean"] as? Bool == true)

        let root = try xcodeCloudSafetyObject(result.structuredContent)
        let buildRun = try xcodeCloudSafetyObject(root["buildRun"])
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["operationCommitted"] == .bool(true))
        #expect(root["retrySafe"] == .bool(false))
        #expect(root["statusCode"] == .int(201))
        #expect(buildRun["id"] == .string("run-created"))
        #expect(buildRun["number"] == .int(18))
        #expect(buildRun["workflowId"] == .string("workflow-1"))
        guard case .array(let included)? = root["included"] else {
            Issue.record("Expected validated start response included resources")
            return
        }
        let includedWorkflow = try xcodeCloudSafetyObject(included.first)
        #expect(includedWorkflow["type"] == .string("ciWorkflows"))
        #expect(includedWorkflow["id"] == .string("workflow-1"))
    }

    @Test("accepted but unverifiable build run starts are committed unverified")
    func acceptedResponseFailuresAreCommittedUnverified() async throws {
        let cases: [(Int, String)] = [
            (200, xcodeCloudValidStartResponse),
            (201, #"{"data": "#),
            (201, #"{"data":{"type":"unexpectedResources","id":"run-created"},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"bad/id"},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created"},"links":{"self":"https://api.example.test/v1/ciBuildRuns/run-created"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created"},"links":{"self":"https://other.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"workflow":{"data":{"type":"apps","id":"workflow-1"}}}},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"workflow":{"data":{"type":"ciWorkflows","id":"workflow-other"}}}},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"builds":{"links":{"self":"https://api.example.test/v1/ciBuildRuns/run-other/relationships/builds"}}}},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"actions":{"links":{"related":"https://api.example.test/v1/ciBuildRuns/run-other/actions"}}}},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"actions":{"links":{"related":"https://other.example.test/v1/ciBuildRuns/run-created/actions"}}}},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"builds":{"data":[{"type":"builds","id":"build-1"},{"type":"builds","id":"build-2"}],"meta":{"paging":{"limit":1,"total":2}}}}},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","links":{"self":"https://other.example.test/v1/ciBuildRuns/run-created"}},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created"},"included":[{"type":"apps","id":"app-1"}],"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"workflow":{"data":{"type":"ciWorkflows","id":"workflow-1"}}}},"included":[{"type":"ciWorkflows","id":"workflow-1"},{"type":"ciWorkflows","id":"workflow-1"}],"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"workflow":{"data":{"type":"ciWorkflows","id":"workflow-1"}}}},"included":[{"type":"ciWorkflows","id":"workflow-other"}],"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"workflow":{"data":{"type":"ciWorkflows","id":"workflow-1"}}}},"included":[{"type":"ciWorkflows","id":"workflow-1","attributes":{"isEnabled":"yes"}}],"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"workflow":{"data":{"type":"ciWorkflows","id":"workflow-1"}}}},"included":[{"type":"ciWorkflows","id":"workflow-1","relationships":{"product":{"data":{"type":"apps","id":"product-1"}}}}],"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"workflow":{"data":{"type":"ciWorkflows","id":"workflow-1"}}}},"included":[{"type":"ciWorkflows","id":"workflow-1","links":{"self":"https://other.example.test/v1/ciWorkflows/workflow-1"}}],"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#),
            (201, #"{"data":{"type":"ciBuildRuns","id":"run-created","relationships":{"builds":{"data":[{"type":"builds","id":"build-1"}]}}},"included":[{"type":"builds","id":"build-1","relationships":{"app":{"data":{"type":"betaGroups","id":"app-1"}}}}],"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#)
        ]

        for testCase in cases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: testCase.0, body: testCase.1)
            ])
            let worker = try await xcodeCloudSafetyWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_runs_start",
                arguments: ["workflow_id": .string("workflow-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
            let details = try xcodeCloudSafetyDetails(result)
            #expect(details["write_outcome"] == .string("committed_unverified"))
            #expect(details["operationCommitState"] == .string("committed_unverified"))
            #expect(details["operationCommitted"] == .bool(true))
            #expect(details["outcomeUnknown"] == .bool(false))
            #expect(details["inspectionRequired"] == .bool(true))
            #expect(details["retrySafe"] == .bool(false))
            #expect(details["recovered"] == .bool(false))
            let recovery = try xcodeCloudSafetyObject(details["recovery"])
            let list = try xcodeCloudSafetyObject(recovery["list_candidates"])
            #expect(list["tool"] == .string("xcode_cloud_workflow_build_runs_list"))
            let get = try xcodeCloudSafetyObject(recovery["inspect_candidate"])
            #expect(get["tool"] == .string("xcode_cloud_build_runs_get"))
        }

        let requestLineageCases: [([String: Value], String)] = [
            (
                [
                    "workflow_id": .string("workflow-1"),
                    "source_branch_or_tag_id": .string("branch-main")
                ],
                #"{"sourceBranchOrTag":{"data":{"type":"scmGitReferences","id":"branch-other"}}}"#
            ),
            (
                [
                    "workflow_id": .string("workflow-1"),
                    "pull_request_id": .string("pull-1")
                ],
                #"{"pullRequest":{"data":{"type":"scmPullRequests","id":"pull-other"}}}"#
            )
        ]
        for testCase in requestLineageCases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: """
                {
                  "data": {
                    "type": "ciBuildRuns",
                    "id": "run-created",
                    "relationships": \(testCase.1)
                  },
                  "links": { "self": "https://api.example.test/v1/ciBuildRuns" }
                }
                """)
            ])
            let worker = try await xcodeCloudSafetyWorker(transport: transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_runs_start",
                arguments: testCase.0
            ))

            let details = try xcodeCloudSafetyDetails(result)
            #expect(details["write_outcome"] == .string("committed_unverified"))
            #expect(details["retrySafe"] == .bool(false))
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("request failures distinguish deterministic rejection from unknown outcome")
    func requestFailureClassificationAndWorkflowRecovery() async throws {
        let rejectedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 422, body: xcodeCloudAPIError(status: 422))
        ])
        let rejectedWorker = try await xcodeCloudSafetyWorker(transport: rejectedTransport)
        let rejected = try await rejectedWorker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: ["workflow_id": .string("workflow-1")]
        ))
        let rejectedDetails = try xcodeCloudSafetyDetails(rejected)
        #expect(rejected.isError == true)
        #expect(rejectedDetails["write_outcome"] == .string("rejected"))
        #expect(rejectedDetails["retrySafe"] == .bool(false))
        #expect(rejectedDetails["recovered"] == .bool(false))
        #expect(rejectedDetails["recovery"] == nil)

        for statusCode in [408, 503] {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: statusCode, body: xcodeCloudAPIError(status: statusCode))
            ])
            let worker = try await xcodeCloudSafetyWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_runs_start",
                arguments: ["workflow_id": .string("workflow-1")]
            ))
            let details = try xcodeCloudSafetyDetails(result)
            #expect(details["write_outcome"] == .string("unknown"))
            #expect(details["outcomeUnknown"] == .bool(true))
            #expect(details["retrySafe"] == .bool(false))
            #expect(details["recovered"] == .bool(false))
        }

        let networkTransport = TestHTTPTransport(responses: [])
        let networkWorker = try await xcodeCloudSafetyWorker(transport: networkTransport)
        let network = try await networkWorker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: ["workflow_id": .string("workflow-1")]
        ))
        let networkDetails = try xcodeCloudSafetyDetails(network)
        #expect(networkDetails["write_outcome"] == .string("unknown"))
        #expect(networkDetails["outcomeUnknown"] == .bool(true))
        let recovery = try xcodeCloudSafetyObject(networkDetails["recovery"])
        let list = try xcodeCloudSafetyObject(recovery["list_candidates"])
        let listArguments = try xcodeCloudSafetyObject(list["arguments"])
        #expect(listArguments["workflow_id"] == .string("workflow-1"))
    }

    @Test("build run start never retries an ambiguous transport failure")
    func buildRunStartDoesNotReplayPOSTAfterNetworkFailure() async throws {
        let transport = XcodeCloudNoRetryStartTransport(successBody: xcodeCloudValidStartResponse)
        let worker = try await xcodeCloudSafetyWorker(transport: transport, maxRetries: 3)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: ["workflow_id": .string("workflow-1")]
        ))

        let details = try xcodeCloudSafetyDetails(result)
        #expect(result.isError == true)
        #expect(details["write_outcome"] == .string("unknown"))
        #expect(details["outcomeUnknown"] == .bool(true))
        #expect(details["retrySafe"] == .bool(false))
        #expect(await transport.requestCount() == 1)
        #expect(await transport.recordedMethods() == ["POST"])
        #expect(await transport.didConsumeSuccessResponse() == false)
    }

    @Test("rebuild ambiguity inspects the source run before workflow candidates")
    func rebuildRecoveryDoesNotClaimSuccess() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: ["build_run_id": .string("run-source")]
        ))

        let details = try xcodeCloudSafetyDetails(result)
        #expect(details["write_outcome"] == .string("unknown"))
        #expect(details["recovered"] == .bool(false))
        #expect(details["operationCommitted"] == nil)
        let recovery = try xcodeCloudSafetyObject(details["recovery"])
        let inspectSource = try xcodeCloudSafetyObject(recovery["inspect_source_run"])
        let inspectArguments = try xcodeCloudSafetyObject(inspectSource["arguments"])
        let list = try xcodeCloudSafetyObject(recovery["list_candidates"])
        #expect(inspectSource["tool"] == .string("xcode_cloud_build_runs_get"))
        #expect(inspectArguments["build_run_id"] == .string("run-source"))
        #expect(list["tool"] == .string("xcode_cloud_workflow_build_runs_list"))
        #expect(list["after"] == .string("inspect_source_run"))
        guard case .string(let instruction)? = recovery["instruction"] else {
            Issue.record("Expected rebuild recovery instruction")
            return
        }
        #expect(instruction.contains("First inspect the source build run"))
        #expect(instruction.contains("does not claim successful recovery"))
    }

    @Test("build run start rejects unknown keys, wrong types, and noncanonical IDs before transport")
    func startPreflightRejectsInvalidArguments() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)
        let invalidArguments: [[String: Value]] = [
            ["workflow_id": .string("workflow-1"), "unknown": .bool(true)],
            ["workflow_id": .string("workflow-1"), "clean": .string("true")],
            ["workflow_id": .string("workflow/1")],
            ["build_run_id": .string("run%2Fsource")]
        ]

        for arguments in invalidArguments {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_runs_start",
                arguments: arguments
            ))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("build run builds forward official includes and related limits with permissive projection")
    func buildRunBuildsForwardOfficialExpansionAndProjectCompleteBuilds() async throws {
        let iconTemplate = "https://assets.example.test/icon/{w}x{h}.png?token=asset-token"
        let includes = [
            "preReleaseVersion", "individualTesters", "betaGroups", "betaBuildLocalizations",
            "appEncryptionDeclaration", "betaAppReviewSubmission", "app", "buildBetaDetail",
            "appStoreVersion", "icons", "buildBundles", "buildUpload"
        ]
        let pageQuery = [
            "limit=25",
            "include=\(includes.joined(separator: ","))",
            "limit%5BindividualTesters%5D=11",
            "limit%5BbetaGroups%5D=12",
            "limit%5BbetaBuildLocalizations%5D=13",
            "limit%5Bicons%5D=14",
            "limit%5BbuildBundles%5D=15"
        ].joined(separator: "&")
        let selfURL = "https://api.example.test/v1/ciBuildRuns/run-1/builds?\(pageQuery)"
        let nextURL = "\(selfURL)&cursor=next"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "builds",
                  "id": "build-1",
                  "attributes": {
                    "version": "42",
                    "uploadedDate": "2026-07-20T08:00:00Z",
                    "expirationDate": "2026-10-18T08:00:00Z",
                    "expired": false,
                    "minOsVersion": "17.0",
                    "lsMinimumSystemVersion": "14.0",
                    "computedMinMacOsVersion": "14.0",
                    "computedMinVisionOsVersion": "2.0",
                    "iconAssetToken": {
                      "templateUrl": "\(iconTemplate)",
                      "width": 1024,
                      "height": 1024
                    },
                    "processingState": "VALID",
                    "buildAudienceType": "APP_STORE_ELIGIBLE",
                    "usesNonExemptEncryption": false
                  },
                  "relationships": {
                    "preReleaseVersion": { "data": { "type": "preReleaseVersions", "id": "pre-1" }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/preReleaseVersion", "related": "https://api.example.test/v1/builds/build-1/preReleaseVersion" } },
                    "individualTesters": { "data": [{ "type": "betaTesters", "id": "tester-1" }], "meta": { "paging": { "limit": 11, "total": 5, "nextCursor": "tester-next" } }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/individualTesters", "related": "https://api.example.test/v1/builds/build-1/individualTesters" } },
                    "betaGroups": { "data": [{ "type": "betaGroups", "id": "group-1" }], "meta": { "paging": { "limit": 12, "total": 1 } }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/betaGroups" } },
                    "betaBuildLocalizations": { "data": [{ "type": "betaBuildLocalizations", "id": "localization-1" }], "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/betaBuildLocalizations", "related": "https://api.example.test/v1/builds/build-1/betaBuildLocalizations" } },
                    "appEncryptionDeclaration": { "data": { "type": "appEncryptionDeclarations", "id": "encryption-1" }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/appEncryptionDeclaration", "related": "https://api.example.test/v1/builds/build-1/appEncryptionDeclaration" } },
                    "betaAppReviewSubmission": { "data": { "type": "betaAppReviewSubmissions", "id": "review-1" }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/betaAppReviewSubmission", "related": "https://api.example.test/v1/builds/build-1/betaAppReviewSubmission" } },
                    "app": { "data": { "type": "apps", "id": "app-1" }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/app", "related": "https://api.example.test/v1/builds/build-1/app" } },
                    "buildBetaDetail": { "data": { "type": "buildBetaDetails", "id": "detail-1" }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/buildBetaDetail", "related": "https://api.example.test/v1/builds/build-1/buildBetaDetail" } },
                    "appStoreVersion": { "data": { "type": "appStoreVersions", "id": "version-1" }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/appStoreVersion", "related": "https://api.example.test/v1/builds/build-1/appStoreVersion" } },
                    "icons": { "data": [{ "type": "buildIcons", "id": "icon-1" }], "meta": { "paging": { "limit": 14, "total": 1 } }, "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/icons", "related": "https://api.example.test/v1/builds/build-1/icons" } },
                    "buildBundles": { "data": [{ "type": "buildBundles", "id": "bundle-1" }], "meta": { "paging": { "limit": 15, "total": 2, "nextCursor": "bundle-next" } } },
                    "buildUpload": { "data": { "type": "buildUploads", "id": "upload-1" } },
                    "perfPowerMetrics": { "links": { "related": "https://api.example.test/v1/builds/build-1/perfPowerMetrics" } },
                    "diagnosticSignatures": { "links": { "self": "https://api.example.test/v1/builds/build-1/relationships/diagnosticSignatures", "related": "https://api.example.test/v1/builds/build-1/diagnosticSignatures" } }
                  },
                  "links": { "self": "https://api.example.test/v1/builds/build-1" }
                },
                { "type": "builds", "id": "build-2" }
              ],
              "included": [
                {
                  "type": "betaBuildLocalizations",
                  "id": "localization-1",
                  "attributes": { "locale": "en-US", "whatsNew": "Test notes" }
                }
              ],
              "links": {
                "first": "\(selfURL)",
                "self": "\(selfURL)",
                "next": "\(nextURL)"
              },
              "meta": { "paging": { "total": 3, "limit": 25, "nextCursor": "next" } }
            }
            """)
        ])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "include": .array(includes.map(Value.string)),
                "individual_testers_limit": .int(11),
                "beta_groups_limit": .int(12),
                "beta_build_localizations_limit": .int(13),
                "icons_limit": .int(14),
                "build_bundles_limit": .int(15)
            ]
        ))

        #expect(result.isError == nil)
        let requests = await transport.recordedRequests()
        let request = try #require(requests.first)
        let query = xcodeCloudSafetyQuery(request)
        #expect(query["include"] == includes.joined(separator: ","))
        #expect(query["limit[individualTesters]"] == "11")
        #expect(query["limit[betaGroups]"] == "12")
        #expect(query["limit[betaBuildLocalizations]"] == "13")
        #expect(query["limit[icons]"] == "14")
        #expect(query["limit[buildBundles]"] == "15")

        let root = try xcodeCloudSafetyObject(result.structuredContent)
        guard case .array(let builds)? = root["builds"] else {
            Issue.record("Expected projected builds")
            return
        }
        let full = try xcodeCloudSafetyObject(builds.first)
        let minimal = try xcodeCloudSafetyObject(builds.last)
        #expect(root["count"] == .int(2))
        #expect(root["total"] == .int(3))
        #expect(root["self_url"] == .string(selfURL))
        #expect(root["first_url"] == .string(selfURL))
        #expect(root["next_url"] == .string(nextURL))
        #expect(full["version"] == .string("42"))
        #expect(full["uploadedDate"] == .string("2026-07-20T08:00:00Z"))
        #expect(full["expirationDate"] == .string("2026-10-18T08:00:00Z"))
        #expect(full["expired"] == .bool(false))
        #expect(full["minOsVersion"] == .string("17.0"))
        #expect(full["lsMinimumSystemVersion"] == .string("14.0"))
        #expect(full["computedMinMacOsVersion"] == .string("14.0"))
        #expect(full["computedMinVisionOsVersion"] == .string("2.0"))
        #expect(full["processingState"] == .string("VALID"))
        #expect(full["buildAudienceType"] == .string("APP_STORE_ELIGIBLE"))
        #expect(full["usesNonExemptEncryption"] == .bool(false))
        let icon = try xcodeCloudSafetyObject(full["iconAssetToken"])
        #expect(icon["templateUrl"] == .string(iconTemplate))
        #expect(icon["width"] == .int(1024))
        #expect(full["preReleaseVersionId"] == .string("pre-1"))
        #expect(full["preReleaseVersionUrl"] == .string("https://api.example.test/v1/builds/build-1/preReleaseVersion"))
        #expect(full["preReleaseVersionRelationshipUrl"] == .string("https://api.example.test/v1/builds/build-1/relationships/preReleaseVersion"))
        #expect(full["individualTesterIds"] == .array([.string("tester-1")]))
        let individualTesterMeta = try xcodeCloudSafetyObject(full["individualTesterIdsMeta"])
        #expect(individualTesterMeta["returnedCount"] == .int(1))
        #expect(individualTesterMeta["total"] == .int(5))
        #expect(individualTesterMeta["limit"] == .int(11))
        #expect(individualTesterMeta["nextCursor"] == .string("tester-next"))
        #expect(individualTesterMeta["isComplete"] == .bool(false))
        #expect(full["betaGroupIds"] == .array([.string("group-1")]))
        let betaGroupMeta = try xcodeCloudSafetyObject(full["betaGroupIdsMeta"])
        #expect(betaGroupMeta["returnedCount"] == .int(1))
        #expect(betaGroupMeta["total"] == .int(1))
        #expect(betaGroupMeta["isComplete"] == .bool(true))
        #expect(full["betaGroupsUrl"] == .null)
        #expect(full["betaGroupsRelationshipUrl"] == .string("https://api.example.test/v1/builds/build-1/relationships/betaGroups"))
        #expect(full["betaBuildLocalizationIds"] == .array([.string("localization-1")]))
        let localizationMeta = try xcodeCloudSafetyObject(full["betaBuildLocalizationIdsMeta"])
        #expect(localizationMeta["returnedCount"] == .int(1))
        #expect(localizationMeta["isComplete"] == .null)
        #expect(full["appEncryptionDeclarationId"] == .string("encryption-1"))
        #expect(full["betaAppReviewSubmissionId"] == .string("review-1"))
        #expect(full["appId"] == .string("app-1"))
        #expect(full["buildBetaDetailId"] == .string("detail-1"))
        #expect(full["appStoreVersionId"] == .string("version-1"))
        #expect(full["iconIds"] == .array([.string("icon-1")]))
        let iconMeta = try xcodeCloudSafetyObject(full["iconIdsMeta"])
        #expect(iconMeta["isComplete"] == .bool(true))
        #expect(full["buildBundleIds"] == .array([.string("bundle-1")]))
        let bundleMeta = try xcodeCloudSafetyObject(full["buildBundleIdsMeta"])
        #expect(bundleMeta["total"] == .int(2))
        #expect(bundleMeta["isComplete"] == .bool(false))
        #expect(full["buildUploadId"] == .string("upload-1"))
        #expect(full["perfPowerMetricIds"] == nil)
        #expect(full["perfPowerMetricsUrl"] == .string("https://api.example.test/v1/builds/build-1/perfPowerMetrics"))
        #expect(full["perfPowerMetricsRelationshipUrl"] == .null)
        #expect(full["diagnosticSignatureIds"] == nil)
        #expect(full["diagnosticSignaturesUrl"] == .string("https://api.example.test/v1/builds/build-1/diagnosticSignatures"))
        #expect(full["diagnosticSignaturesRelationshipUrl"] == .string("https://api.example.test/v1/builds/build-1/relationships/diagnosticSignatures"))
        #expect(minimal["id"] == .string("build-2"))
        #expect(minimal["version"] == .null)
        #expect(minimal["appId"] == .null)
        #expect(minimal["betaGroupsRelationshipUrl"] == .null)
        guard case .array(let included)? = root["included"] else {
            Issue.record("Expected permissive included resources")
            return
        }
        let includedLocalization = try xcodeCloudSafetyObject(included.first)
        #expect(includedLocalization["type"] == .string("betaBuildLocalizations"))
        #expect(includedLocalization["id"] == .string("localization-1"))
    }

    @Test("all documented build include mappings accept lineage-bound resources")
    func buildListAcceptsEveryDocumentedIncludedResourceType() async throws {
        let cases: [(include: String, type: String, id: String, relationship: String, selfURL: String)] = [
            (
                "preReleaseVersion", "preReleaseVersions", "pre-1",
                #""preReleaseVersion":{"data":{"type":"preReleaseVersions","id":"pre-1"}}"#,
                "https://api.example.test/v1/preReleaseVersions/pre-1"
            ),
            (
                "individualTesters", "betaTesters", "tester-1",
                #""individualTesters":{"data":[{"type":"betaTesters","id":"tester-1"}]}"#,
                "https://api.example.test/v1/betaTesters/tester-1"
            ),
            (
                "betaGroups", "betaGroups", "group-1",
                #""betaGroups":{"data":[{"type":"betaGroups","id":"group-1"}]}"#,
                "https://api.example.test/v1/betaGroups/group-1"
            ),
            (
                "betaBuildLocalizations", "betaBuildLocalizations", "localization-1",
                #""betaBuildLocalizations":{"data":[{"type":"betaBuildLocalizations","id":"localization-1"}]}"#,
                "https://api.example.test/v1/betaBuildLocalizations/localization-1"
            ),
            (
                "appEncryptionDeclaration", "appEncryptionDeclarations", "encryption-1",
                #""appEncryptionDeclaration":{"data":{"type":"appEncryptionDeclarations","id":"encryption-1"}}"#,
                "https://api.example.test/v1/appEncryptionDeclarations/encryption-1"
            ),
            (
                "betaAppReviewSubmission", "betaAppReviewSubmissions", "review-1",
                #""betaAppReviewSubmission":{"data":{"type":"betaAppReviewSubmissions","id":"review-1"}}"#,
                "https://api.example.test/v1/betaAppReviewSubmissions/review-1"
            ),
            (
                "app", "apps", "app-1",
                #""app":{"data":{"type":"apps","id":"app-1"}}"#,
                "https://api.example.test/v1/apps/app-1"
            ),
            (
                "buildBetaDetail", "buildBetaDetails", "detail-1",
                #""buildBetaDetail":{"data":{"type":"buildBetaDetails","id":"detail-1"}}"#,
                "https://api.example.test/v1/buildBetaDetails/detail-1"
            ),
            (
                "appStoreVersion", "appStoreVersions", "version-1",
                #""appStoreVersion":{"data":{"type":"appStoreVersions","id":"version-1"}}"#,
                "https://api.example.test/v1/appStoreVersions/version-1"
            ),
            (
                "icons", "buildIcons", "icon-1",
                #""icons":{"data":[{"type":"buildIcons","id":"icon-1"}]}"#,
                "/v1/builds/build-1/icons/icon-1"
            ),
            (
                "buildBundles", "buildBundles", "bundle-1",
                #""buildBundles":{"data":[{"type":"buildBundles","id":"bundle-1"}]}"#,
                "https://api.example.test/v1/buildBundles/bundle-1"
            ),
            (
                "buildUpload", "buildUploads", "upload-1",
                #""buildUpload":{"data":{"type":"buildUploads","id":"upload-1"}}"#,
                "https://api.example.test/v1/buildUploads/upload-1"
            )
        ]

        for testCase in cases {
            let selfURL = "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=25&include=\(testCase.include)"
            let build = """
            {"type":"builds","id":"build-1","relationships":{\(testCase.relationship)}}
            """
            let included = """
            {"type":"\(testCase.type)","id":"\(testCase.id)","links":{"self":"\(testCase.selfURL)"}}
            """
            let transport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 200,
                    body: xcodeCloudBuildListBody(
                        build: build,
                        selfURL: selfURL,
                        included: included
                    )
                )
            ])
            let worker = try await xcodeCloudSafetyWorker(transport: transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_run_builds_list",
                arguments: [
                    "build_run_id": .string("run-1"),
                    "include": .string(testCase.include)
                ]
            ))

            #expect(result.isError == nil)
            let root = try xcodeCloudSafetyObject(result.structuredContent)
            guard case .array(let includedOutput)? = root["included"] else {
                Issue.record("Expected included output for \(testCase.include)")
                continue
            }
            let resource = try xcodeCloudSafetyObject(includedOutput.first)
            #expect(resource["type"] == .string(testCase.type))
            #expect(resource["id"] == .string(testCase.id))
        }
    }

    @Test("build list rejects unrequested, malformed, duplicate, hostile, and unlinked included resources")
    func buildListRejectsInvalidIncludedResources() async throws {
        let appBuild = #"{"type":"builds","id":"build-1","relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}"#
        let iconBuild = #"{"type":"builds","id":"build-1","relationships":{"icons":{"data":[{"type":"buildIcons","id":"icon-1"}]}}}"#
        let bundleBuild = #"{"type":"builds","id":"build-1","relationships":{"buildBundles":{"data":[{"type":"buildBundles","id":"bundle-1"}]}}}"#
        let cases: [(include: String?, build: String, included: String)] = [
            (
                nil,
                appBuild,
                #"{"type":"apps","id":"app-1","links":{"self":"https://api.example.test/v1/apps/app-1"}}"#
            ),
            (
                "app",
                #"{"type":"builds","id":"build-1","relationships":{"betaGroups":{"data":[{"type":"betaGroups","id":"group-1"}]}}}"#,
                #"{"type":"betaGroups","id":"group-1","links":{"self":"https://api.example.test/v1/betaGroups/group-1"}}"#
            ),
            (
                "app",
                appBuild,
                #"{"type":"apps","id":"app-1"},{"type":"apps","id":"app-1"}"#
            ),
            (
                "app",
                appBuild,
                #"{"type":"apps","id":"app-1","links":{"self":"https://other.example.test/v1/apps/app-1"}}"#
            ),
            (
                "app",
                appBuild,
                #"{"type":"apps","id":"app-1","links":{"self":"https://api.example.test/v1/apps/app-2"}}"#
            ),
            (
                "app",
                appBuild,
                #"{"type":"apps","id":"app-2","links":{"self":"https://api.example.test/v1/apps/app-2"}}"#
            ),
            (
                "icons",
                iconBuild,
                #"{"type":"buildIcons","id":"icon-1","links":{"self":"https://other.example.test/v1/builds/build-1/icons/icon-1"}}"#
            ),
            (
                "icons",
                iconBuild,
                #"{"type":"buildIcons","id":"icon-1","links":{"self":"/v1/builds/build-1/icons/icon-2"}}"#
            ),
            (
                "buildBundles",
                bundleBuild,
                #"{"type":"buildBundles","id":"bundle-1","links":{"self":"https://api.example.test/v1/buildBundles/bundle-1?token=unexpected"}}"#
            )
        ]

        for testCase in cases {
            let selfURL: String
            var arguments: [String: Value] = ["build_run_id": .string("run-1")]
            if let include = testCase.include {
                arguments["include"] = .string(include)
                selfURL = "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=25&include=\(include)"
            } else {
                selfURL = "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=25"
            }
            let transport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 200,
                    body: xcodeCloudBuildListBody(
                        build: testCase.build,
                        selfURL: selfURL,
                        included: testCase.included
                    )
                )
            ])
            let worker = try await xcodeCloudSafetyWorker(transport: transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_run_builds_list",
                arguments: arguments
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("build list rejects duplicate build identities")
    func buildListRejectsDuplicateBuildResources() async throws {
        let duplicate = #"{"type":"builds","id":"build-1"}"#
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: xcodeCloudBuildListBody(build: "\(duplicate),\(duplicate)")
            )
        ])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: ["build_run_id": .string("run-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("build list rejects malformed resource lineage before projection")
    func buildListRejectsMalformedResourceLineage() async throws {
        let invalidBuilds = [
            #"{"type":"builds","id":"build-1","relationships":{"app":{"data":{"type":"betaGroups","id":"app-1"}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"app":{"data":{"type":"apps","id":"bad/id"}}}}"#,
            #"{"type":"builds","id":"build-1","links":{"self":"https://api.example.test/v1/builds/build-2"}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"individualTesters":{"data":[{"type":"betaTesters","id":"tester-1"}],"meta":{"paging":{"limit":10,"total":0}}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"individualTesters":{"data":[{"type":"betaTesters","id":"tester-1"},{"type":"betaTesters","id":"tester-1"}]}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"individualTesters":{"data":[{"type":"betaTesters","id":"tester-1"},{"type":"betaTesters","id":"tester-2"}],"meta":{"paging":{"limit":1,"total":2}}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"individualTesters":{"data":[],"meta":{"paging":{"limit":1,"nextCursor":" "}}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"app":{"data":{"type":"apps","id":"app-1"},"links":{"self":"https://api.example.test/v1/builds/build-2/relationships/app"}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"app":{"data":{"type":"apps","id":"app-1"},"links":{"related":"https://other.example.test/v1/builds/build-1/app"}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"betaGroups":{"data":[],"links":{"related":"https://api.example.test/v1/builds/build-1/betaGroups"}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"buildBundles":{"data":[],"links":{"self":"https://api.example.test/v1/builds/build-1/relationships/buildBundles"}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"buildUpload":{"data":{"type":"buildUploads","id":"upload-1"},"links":{"related":"https://api.example.test/v1/builds/build-1/buildUpload"}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"perfPowerMetrics":{"data":[]}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"perfPowerMetrics":{"links":{"self":"https://api.example.test/v1/builds/build-1/relationships/perfPowerMetrics"}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"perfPowerMetrics":{"links":{"related":"https://api.example.test/v1/builds/build-2/perfPowerMetrics"}}}}"#,
            #"{"type":"builds","id":"build-1","relationships":{"diagnosticSignatures":{"links":{"self":"https://other.example.test/v1/builds/build-1/relationships/diagnosticSignatures"}}}}"#
        ]

        for build in invalidBuilds {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: xcodeCloudBuildListBody(build: build))
            ])
            let worker = try await xcodeCloudSafetyWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_run_builds_list",
                arguments: ["build_run_id": .string("run-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("build list rejects hostile page links and inconsistent paging metadata")
    func buildListRejectsInvalidPageReceipts() async throws {
        let selfURL = "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=25"
        let nextURL = "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=25&cursor=next"
        let invalidBodies = [
            xcodeCloudBuildListBody(
                build: #"{"type":"builds","id":"build-1"}"#,
                selfURL: "https://other.example.test/v1/ciBuildRuns/run-1/builds?limit=25"
            ),
            xcodeCloudBuildListBody(
                build: #"{"type":"builds","id":"build-1"}"#,
                selfURL: selfURL,
                limit: 24
            ),
            xcodeCloudBuildListBody(
                build: #"{"type":"builds","id":"build-1"}"#,
                selfURL: selfURL,
                nextURL: nextURL,
                nextCursor: "stale"
            ),
            """
            {
              "data": [{ "type": "builds", "id": "build-1" }],
              "links": { "self": "\(selfURL)" },
              "meta": {}
            }
            """
        ]

        for body in invalidBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await xcodeCloudSafetyWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_run_builds_list",
                arguments: ["build_run_id": .string("run-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("build relationship paging limit must match the explicit nested limit")
    func buildRelationshipPagingLimitMatchesRequest() async throws {
        let selfURL = "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=25&include=individualTesters&limit%5BindividualTesters%5D=11"
        let build = #"{"type":"builds","id":"build-1","relationships":{"individualTesters":{"data":[{"type":"betaTesters","id":"tester-1"}],"meta":{"paging":{"limit":10,"total":1}}}}}"#
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: xcodeCloudBuildListBody(build: build, selfURL: selfURL)
            )
        ])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "include": .string("individualTesters"),
                "individual_testers_limit": .int(11)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("build relationship data cannot exceed an explicit nested limit without meta")
    func buildRelationshipDataRespectsRequestWithoutMeta() async throws {
        let selfURL = "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=25&include=individualTesters&limit%5BindividualTesters%5D=1"
        let build = #"{"type":"builds","id":"build-1","relationships":{"individualTesters":{"data":[{"type":"betaTesters","id":"tester-1"},{"type":"betaTesters","id":"tester-2"}]}}}"#
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: xcodeCloudBuildListBody(build: build, selfURL: selfURL)
            )
        ])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "include": .string("individualTesters"),
                "individual_testers_limit": .int(1)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("build expansion limits require matching includes and valid bounds")
    func buildExpansionLimitPreflight() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)
        let invalidArguments: [[String: Value]] = [
            ["build_run_id": .string("run-1"), "individual_testers_limit": .int(10)],
            [
                "build_run_id": .string("run-1"),
                "include": .string("individualTesters"),
                "individual_testers_limit": .int(51)
            ],
            ["build_run_id": .string("run/1")]
        ]

        for arguments in invalidArguments {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_run_builds_list",
                arguments: arguments
            ))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("artifact reads preserve Apple's signed download URL")
    func signedArtifactDownloadURLIsPreserved() async throws {
        let signedURL = "https://downloads.example.test/artifact.zip?X-Amz-Credential=credential-value&X-Amz-Signature=signature-value"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "ciArtifacts",
                "id": "artifact-1",
                "attributes": {
                  "fileType": "ARCHIVE",
                  "fileName": "artifact.zip",
                  "fileSize": 1024,
                  "downloadUrl": "\(signedURL)"
                },
                "links": { "self": "https://api.example.test/v1/ciArtifacts/artifact-1" }
              },
              "links": { "self": "https://api.example.test/v1/ciArtifacts/artifact-1" }
            }
            """)
        ])
        let worker = try await xcodeCloudSafetyWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_artifacts_get",
            arguments: ["artifact_id": .string("artifact-1")]
        ))

        #expect(result.isError == nil)
        let root = try xcodeCloudSafetyObject(result.structuredContent)
        let artifact = try xcodeCloudSafetyObject(root["artifact"])
        #expect(artifact["downloadUrl"] == .string(signedURL))
    }
}

private let xcodeCloudValidStartResponse = #"{"data":{"type":"ciBuildRuns","id":"run-created"},"links":{"self":"https://api.example.test/v1/ciBuildRuns"}}"#

private func xcodeCloudAPIError(status: Int) -> String {
    """
    {
      "errors": [{
        "status": "\(status)",
        "code": "XCODE_CLOUD_ERROR",
        "title": "Build run request failed",
        "detail": "The request was not accepted"
      }]
    }
    """
}

private func xcodeCloudBuildListBody(
    build: String,
    selfURL: String = "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=25",
    nextURL: String? = nil,
    limit: Int = 25,
    nextCursor: String? = nil,
    included: String? = nil
) -> String {
    let nextLink = nextURL.map { ", \"next\": \"\($0)\"" } ?? ""
    let cursor = nextCursor.map { ", \"nextCursor\": \"\($0)\"" } ?? ""
    let includedMember = included.map { ", \"included\": [\($0)]" } ?? ""
    return """
    {
      "data": [\(build)],
      "links": { "self": "\(selfURL)"\(nextLink) },
      "meta": { "paging": { "limit": \(limit)\(cursor) } }\(includedMember)
    }
    """
}

private func xcodeCloudSafetyWorker(
    transport: any HTTPTransport,
    maxRetries: Int = 1
) async throws -> XcodeCloudWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: maxRetries
    )
    return XcodeCloudWorker(httpClient: client)
}

private func xcodeCloudSafetyObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object)? = value else {
        throw XcodeCloudBuildRunSafetyTestFailure.expectedObject
    }
    return object
}

private func xcodeCloudSafetyDetails(_ result: CallTool.Result) throws -> [String: Value] {
    let root = try xcodeCloudSafetyObject(result.structuredContent)
    return try xcodeCloudSafetyObject(root["details"])
}

private func xcodeCloudSafetyJSONObject(_ data: Data?) throws -> [String: Any] {
    guard let data,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw XcodeCloudBuildRunSafetyTestFailure.expectedJSONObject
    }
    return object
}

private func xcodeCloudSafetyJSONObject(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw XcodeCloudBuildRunSafetyTestFailure.expectedJSONObject
    }
    return object
}

private func xcodeCloudSafetyQuery(_ request: URLRequest) -> [String: String] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return [:]
    }
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private enum XcodeCloudBuildRunSafetyTestFailure: Error {
    case expectedObject
    case expectedJSONObject
}

private actor XcodeCloudNoRetryStartTransport: HTTPTransport {
    private let successBody: Data
    private var requests: [URLRequest] = []
    private var successResponseConsumed = false

    init(successBody: String) {
        self.successBody = Data(successBody.utf8)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if requests.count == 1 {
            throw URLError(.networkConnectionLost)
        }
        successResponseConsumed = true
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            throw URLError(.badServerResponse)
        }
        return (successBody, response)
    }

    func requestCount() -> Int {
        requests.count
    }

    func recordedMethods() -> [String] {
        requests.compactMap(\.httpMethod)
    }

    func didConsumeSuccessResponse() -> Bool {
        successResponseConsumed
    }
}
