import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("AppLifecycleWorker Hardening Tests")
struct AppLifecycleWorkerHardeningTests {
    @Test("version pagination rejects a same-origin cross-route URL before network")
    func versionPaginationRejectsCrossRoute() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://api.example.test/v1/users?cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test(
        "version pagination rejects malformed and off-origin URLs before network",
        arguments: [
            "not a URL",
            "https://example.invalid/v1/apps/app-1/appStoreVersions?cursor=next"
        ]
    )
    func versionPaginationRejectsInvalidURL(_ nextURL: String) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version pagination rejects non-string and empty values before network")
    func versionPaginationRejectsInvalidValue() async throws {
        let invalidValues: [Value] = [.int(42), .string("   ")]

        for invalidValue in invalidValues {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeWorker(transport: transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "app_versions_list",
                arguments: [
                    "app_id": .string("app-1"),
                    "next_url": invalidValue
                ]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("version pagination preserves include filters and page size")
    func versionPaginationRequiresQueryInvariants() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)
        let nextURL = "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&filter%5BappVersionState%5D=READY_FOR_DISTRIBUTION&limit=200"

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "app_version_states": .array([.string("READY_FOR_DISTRIBUTION")]),
                "limit": .int(200),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version pagination accepts preserved include filters and page size")
    func versionPaginationAcceptsQueryInvariants() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/appStoreVersions"}}"#)
        ])
        let worker = try await makeWorker(transport: transport)
        let nextURL = "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&include=build%2CappStoreVersionPhasedRelease&filter%5BappVersionState%5D=READY_FOR_DISTRIBUTION&limit=200"

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "app_version_states": .array([.string("READY_FOR_DISTRIBUTION")]),
                "limit": .int(200),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("version pagination rejects an out-of-range page size")
    func versionPaginationRejectsOutOfRangeLimit() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)
        let nextURL = "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&include=build%2CappStoreVersionPhasedRelease&limit=200"

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .int(500),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version pagination rejects a changed default page size")
    func versionPaginationPreservesDefaultLimit() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)
        let nextURL = "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&include=build%2CappStoreVersionPhasedRelease&limit=200"

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version list forwards multiple platforms and returns count and paging metadata")
    func versionListForwardsPlatformsAndPagingMetadata() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {"type":"appStoreVersions","id":"ios-1"},
                {"type":"appStoreVersions","id":"mac-1"}
              ],
              "links":{"self":"https://api.example.test/v1/apps/app-1/appStoreVersions"},
              "meta":{"paging":{"total":4,"limit":2,"nextCursor":"page-2"}}
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "platforms": .array([.string("IOS"), .string("MAC_OS")]),
                "limit": .int(2)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["filter[platform]"] == "IOS,MAC_OS")
        let payload = try object(result.structuredContent)
        #expect(payload["count"] == .int(2))
        #expect(payload["total"] == .int(4))
        #expect(payload["meta"]?.objectValue?["paging"]?.objectValue?["nextCursor"] == .string("page-2"))
    }

    @Test("version list rejects malformed or mismatched JSON API resources")
    func versionListRejectsInvalidResourceIdentity() async throws {
        let responses = [
            #"{"data":{"type":"appStoreVersions","id":"ver-1"}}"#,
            #"{"data":[{"type":"apps","id":"ver-1"}]}"#,
            #"{"data":[{"type":"appStoreVersions","id":""}]}"#,
            #"{"data":[{"type":"appStoreVersions","id":"ver-1"}],"included":[{"type":"users","id":"user-1"}]}"#,
            #"{"data":[{"type":"appStoreVersions","id":"ver-1","relationships":{"build":{"data":{"type":"apps","id":"build-1"}}}}]}"#,
            #"{"data":[{"type":"appStoreVersions","id":"ver-1","relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}]}"#,
            #"{"data":[{"type":"appStoreVersions","id":"ver-1"}],"included":[{"type":"builds","id":"build-1"}]}"#,
            #"{"data":[{"type":"appStoreVersions","id":"ver-1"},{"type":"appStoreVersions","id":"ver-1"}]}"#
        ]

        for response in responses {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: response)])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_list",
                arguments: ["app_id": .string("app-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("version list rejects resources outside the requested ID filter")
    func versionListRejectsUnexpectedFilteredIdentity() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[{"type":"appStoreVersions","id":"ver-other"}]}"#)
        ])
        let worker = try await makeWorker(transport: transport)
        let result = try await worker.handleTool(.init(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "version_ids": .array([.string("ver-1")])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("version list accepts included resources linked from the primary version")
    func versionListAcceptsLinkedIncludedResources() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[{"type":"appStoreVersions","id":"ver-1","relationships":{"build":{"data":{"type":"builds","id":"build-1"}},"appStoreVersionPhasedRelease":{"data":{"type":"appStoreVersionPhasedReleases","id":"phase-1"}}}}],"included":[{"type":"builds","id":"build-1"},{"type":"appStoreVersionPhasedReleases","id":"phase-1"}]}"#)
        ])
        let worker = try await makeWorker(transport: transport)
        let result = try await worker.handleTool(.init(
            name: "app_versions_list",
            arguments: ["app_id": .string("app-1")]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("version list accepts schema-valid links-only version relationships")
    func versionListAcceptsLinksOnlyRelationships() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[{"type":"appStoreVersions","id":"ver-1","relationships":{"build":{"links":{"related":"https://api.example.test/v1/appStoreVersions/ver-1/build"}}}}]}"#)
        ])
        let worker = try await makeWorker(transport: transport)
        let result = try await worker.handleTool(.init(
            name: "app_versions_list",
            arguments: ["app_id": .string("app-1")]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("version detail rejects malformed type and exact ID mismatches")
    func versionDetailRejectsInvalidResourceIdentity() async throws {
        let responses = [
            #"{"data":[]}"#,
            #"{"data":{"type":"apps","id":"ver-1"}}"#,
            #"{"data":{"type":"appStoreVersions","id":"ver-other"}}"#,
            #"{"data":{"type":"appStoreVersions","id":" "}}"#,
            #"{"data":{"type":"appStoreVersions","id":"ver-1"},"included":[{"type":"users","id":"user-1"}]}"#,
            #"{"data":{"type":"appStoreVersions","id":"ver-1","relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}}"#,
            #"{"data":{"type":"appStoreVersions","id":"ver-1"},"included":[{"type":"builds","id":"build-1"}]}"#,
            #"{"data":{"type":"appStoreVersions","id":"ver-1"},"included":[{"type":"builds","id":"build-1"},{"type":"builds","id":"build-1"}]}"#
        ]

        for response in responses {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: response)])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_get",
                arguments: ["version_id": .string("ver-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test(
        "invalid version list controls fail before network access",
        arguments: [
            ["limit": Value.int(0)],
            ["limit": Value.int(201)],
            ["limit": Value.string("25")],
            ["platforms": Value.array([.string("IOS"), .string("IOS")])],
            ["platforms": Value.array([.string("ANDROID")])],
            ["states": Value.array([.string("READY_FOR_DISTRIBUTION")])],
            ["app_version_states": Value.array([.string("READY_FOR_SALE")])],
            ["version_ids": Value.array([.string("ver-1"), .bool(true)])]
        ]
    )
    func versionListRejectsInvalidControls(_ invalid: [String: Value]) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)
        var arguments = invalid
        arguments["app_id"] = .string("app-1")

        let result = try await worker.handleTool(.init(
            name: "app_versions_list",
            arguments: arguments
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("legacy and plural version platforms cannot be combined")
    func versionListRejectsPlatformAliasConflict() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "platform": .string("IOS"),
                "platforms": .array([.string("MAC_OS")])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("phased release mutations require exact confirmations before network access")
    func phasedReleaseMutationsRequireConfirmations() async throws {
        let cases: [(String, [String: Value])] = [
            (
                "app_versions_create_phased_release",
                ["version_id": .string("ver-1"), "phased_release_state": .string("ACTIVE")]
            ),
            (
                "app_versions_update_phased_release",
                ["phased_release_id": .string("phase-1"), "phased_release_state": .string("ACTIVE")]
            ),
            (
                "app_versions_update_phased_release",
                ["phased_release_id": .string("phase-1"), "phased_release_state": .string("COMPLETE")]
            ),
            (
                "app_versions_delete_phased_release",
                ["phased_release_id": .string("phase-1")]
            )
        ]

        for (tool, arguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("phased release mutations proceed after exact confirmations")
    func phasedReleaseMutationsAcceptExactConfirmations() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"appStoreVersionPhasedReleases","id":"phase-1","attributes":{"phasedReleaseState":"ACTIVE"}}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreVersionPhasedReleases","id":"phase-1","attributes":{"phasedReleaseState":"ACTIVE"}}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreVersionPhasedReleases","id":"phase-1","attributes":{"phasedReleaseState":"COMPLETE"}}}"#)
        ])
        let worker = try await makeWorker(transport: transport)

        let create = try await worker.handleTool(.init(
            name: "app_versions_create_phased_release",
            arguments: [
                "version_id": .string("ver-1"),
                "phased_release_state": .string("ACTIVE"),
                "confirm_version_id": .string("ver-1")
            ]
        ))
        let activate = try await worker.handleTool(.init(
            name: "app_versions_update_phased_release",
            arguments: [
                "phased_release_id": .string("phase-1"),
                "phased_release_state": .string("ACTIVE"),
                "confirm_phased_release_id": .string("phase-1")
            ]
        ))
        let complete = try await worker.handleTool(.init(
            name: "app_versions_update_phased_release",
            arguments: [
                "phased_release_id": .string("phase-1"),
                "phased_release_state": .string("COMPLETE"),
                "confirm_phased_release_id": .string("phase-1")
            ]
        ))

        #expect(create.isError != true)
        #expect(activate.isError != true)
        #expect(complete.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "PATCH"])
        #expect(requests[0].url?.path == "/v1/appStoreVersionPhasedReleases")
        #expect(requests[1].url?.path == "/v1/appStoreVersionPhasedReleases/phase-1")
        #expect(requests[2].url?.path == "/v1/appStoreVersionPhasedReleases/phase-1")
        let bodies = await transport.recordedBodyStrings()
        #expect(bodies[0].contains(#""phasedReleaseState":"ACTIVE""#))
        #expect(bodies[1].contains(#""phasedReleaseState":"ACTIVE""#))
        #expect(bodies[2].contains(#""phasedReleaseState":"COMPLETE""#))
    }

    @Test("phased release handlers reject workflow-incompatible states")
    func phasedReleaseHandlersRejectWrongStateSubsets() async throws {
        let cases: [(String, [String: Value])] = [
            (
                "app_versions_create_phased_release",
                ["version_id": .string("ver-1"), "phased_release_state": .string("COMPLETE")]
            ),
            (
                "app_versions_update_phased_release",
                ["phased_release_id": .string("phase-1"), "phased_release_state": .string("INACTIVE")]
            )
        ]

        for (tool, arguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("successful lifecycle mutations with invalid resource identities are committed unverified")
    func lifecycleMutationsRejectInvalidSuccessIdentities() async throws {
        let cases: [(String, [String: Value], Int, String, String)] = [
            (
                "app_versions_create",
                ["app_id": .string("app-1"), "platform": .string("IOS"), "version_string": .string("3.0")],
                201,
                #"{"data":{"type":"apps","id":"ver-1"}}"#,
                "POST"
            ),
            (
                "app_versions_update",
                ["version_id": .string("ver-1"), "copyright": .string("2026 Example")],
                200,
                #"{"data":{"type":"appStoreVersions","id":"ver-other"}}"#,
                "PATCH"
            ),
            (
                "app_versions_cancel_review",
                ["review_submission_id": .string("sub-1")],
                200,
                #"{"data":{"type":"reviewSubmissions","id":"sub-other"}}"#,
                "PATCH"
            ),
            (
                "app_versions_create_phased_release",
                ["version_id": .string("ver-1")],
                201,
                #"{"data":{"type":"appStoreVersionPhasedReleases","id":"phase/1"}}"#,
                "POST"
            ),
            (
                "app_versions_update_phased_release",
                ["phased_release_id": .string("phase-1"), "phased_release_state": .string("PAUSED")],
                200,
                #"{"data":{"type":"appStoreVersionPhasedReleases","id":"phase-other"}}"#,
                "PATCH"
            )
        ]

        for (tool, arguments, statusCode, response, method) in cases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: statusCode, body: response)])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))

            #expect(result.isError == true)
            let payload = try object(result.structuredContent)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["operationCommitted"] == .bool(true))
            #expect(payload["retrySafe"] == .bool(false))
            let requests = await transport.recordedRequests()
            #expect(requests.count == 1)
            #expect(requests.first?.httpMethod == method)
        }
    }

    @Test("phased release read rejects malformed resource identity")
    func phasedReleaseReadRejectsInvalidIdentity() async throws {
        let responses = [
            #"{"data":[]}"#,
            #"{"data":{"type":"appStoreVersions","id":"phase-1"}}"#,
            #"{"data":{"type":"appStoreVersionPhasedReleases","id":"phase/1"}}"#
        ]

        for response in responses {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: response)])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_get_phased_release",
                arguments: ["version_id": .string("ver-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("submit for review exposes submission id after item creation failure")
    func submitForReviewExposesSubmissionIdAfterItemFailure() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: submissionVersionBody(appId: "app-1")),
            .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissions","id":"sub-1","attributes":{"state":"READY_FOR_REVIEW"}}}"#),
            .init(statusCode: 422, body: #"{"errors":[{"status":"422","detail":"item failed"}]}"#)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_submit_for_review",
            arguments: [
                "version_id": .string("ver-1"),
                "app_id": .string("app-1")
            ]
        ))

        #expect(result.isError == true)
        let payload = try object(result.structuredContent)
        #expect(payload["partial_success"] == .bool(true))
        #expect(payload["submission_id"] == .string("sub-1"))
        #expect(payload["failed_step"] == .string("create_review_submission_item"))
        #expect(payload["recovery_tools"] == .array([
            .string("app_versions_cancel_review")
        ]))
        #expect(payload["message"]?.stringValue?.contains("no review-submission inspection or resume tool") == true)
        #expect(payload["message"]?.stringValue?.contains("review_submission_id set to the returned submission_id") == true)
    }

    @Test("partial submit mutation preserves typed committed-unverified state")
    func partialSubmitMutationPreservesCommitState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: submissionVersionBody(appId: "app-1")),
            .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissions","id":"sub-1"}}"#),
            .init(statusCode: 202, body: #"{"data":{"type":"reviewSubmissionItems","id":"item-1"}}"#)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_submit_for_review",
            arguments: ["version_id": .string("ver-1"), "app_id": .string("app-1")]
        ))

        #expect(result.isError == true)
        let payload = try object(result.structuredContent)
        #expect(payload["partial_success"] == .bool(true))
        #expect(payload["submission_id"] == .string("sub-1"))
        #expect(payload["failed_step"] == .string("create_review_submission_item"))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["outcomeUnknown"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["inspectionRequired"] == .bool(true))
        let details = try object(payload["details"])
        #expect(details["type"] == .string("mutation_unverified"))
        #expect(details["method"] == .string("POST"))
        #expect(details["statusCode"] == .int(202))
        #expect(await transport.requestCount() == 3)
    }

    @Test("submit for review exposes submission id after confirm failure")
    func submitForReviewExposesSubmissionIdAfterConfirmFailure() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: submissionVersionBody(appId: "app-1")),
            .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissions","id":"sub-2","attributes":{"state":"READY_FOR_REVIEW"}}}"#),
            .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissionItems","id":"item-1"}}"#),
            .init(statusCode: 409, body: #"{"errors":[{"status":"409","detail":"confirm failed"}]}"#)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_submit_for_review",
            arguments: [
                "version_id": .string("ver-1"),
                "app_id": .string("app-1")
            ]
        ))

        #expect(result.isError == true)
        let payload = try object(result.structuredContent)
        #expect(payload["partial_success"] == .bool(true))
        #expect(payload["submission_id"] == .string("sub-2"))
        #expect(payload["failed_step"] == .string("confirm_review_submission"))
    }

    @Test("submit preflight rejects mismatched resource identities before mutation")
    func submitForReviewRejectsMismatchedPreflightIdentity() async throws {
        let responses = [
            submissionVersionBody(type: "apps", appId: "app-1"),
            submissionVersionBody(id: "ver-other", appId: "app-1"),
            submissionVersionBody(appType: "users", appId: "app-1"),
            submissionVersionBody(appId: " ")
        ]

        for response in responses {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: response)])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_submit_for_review",
                arguments: ["version_id": .string("ver-1"), "app_id": .string("app-1")]
            ))

            #expect(result.isError == true)
            let requests = await transport.recordedRequests()
            #expect(requests.count == 1)
            #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }

    @Test("submit create response must identify a review submission before downstream mutation")
    func submitForReviewRejectsInvalidCreateIdentity() async throws {
        let createResponses = [
            #"{"data":42}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"sub-1"}}"#,
            #"{"data":{"type":"reviewSubmissions","id":""}}"#,
            #"{"data":{"type":"reviewSubmissions","id":"sub-1","relationships":{"app":{"data":{"type":"apps","id":"app-other"}}}}}"#
        ]

        for createResponse in createResponses {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: submissionVersionBody(appId: "app-1")),
                .init(statusCode: 201, body: createResponse)
            ])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_submit_for_review",
                arguments: ["version_id": .string("ver-1"), "app_id": .string("app-1")]
            ))

            #expect(result.isError == true)
            let payload = try object(result.structuredContent)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["retrySafe"] == .bool(false))
            let requests = await transport.recordedRequests()
            #expect(requests.map(\.httpMethod) == ["GET", "POST"])
            #expect(requests.last?.url?.path == "/v1/reviewSubmissions")
        }
    }

    @Test("submit item response must identify the version item before confirmation")
    func submitForReviewRejectsInvalidItemIdentity() async throws {
        let itemResponses = [
            #"{"data":42}"#,
            #"{"data":{"type":"reviewSubmissions","id":"item-1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"item/1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"item-1","relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":"ver-other"}}}}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"item-1","relationships":{"reviewSubmission":{"data":{"type":"reviewSubmissions","id":"sub-other"}}}}}"#
        ]

        for itemResponse in itemResponses {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: submissionVersionBody(appId: "app-1")),
                .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissions","id":"sub-1"}}"#),
                .init(statusCode: 201, body: itemResponse)
            ])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_submit_for_review",
                arguments: ["version_id": .string("ver-1"), "app_id": .string("app-1")]
            ))

            #expect(result.isError == true)
            let payload = try object(result.structuredContent)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["retrySafe"] == .bool(false))
            #expect(payload["submission_id"] == .string("sub-1"))
            #expect(payload["failed_step"] == .string("create_review_submission_item"))
            let requests = await transport.recordedRequests()
            #expect(requests.map(\.httpMethod) == ["GET", "POST", "POST"])
            #expect(requests.last?.url?.path == "/v1/reviewSubmissionItems")
        }
    }

    @Test("submit confirmation response must preserve the created submission identity")
    func submitForReviewRejectsMismatchedConfirmationIdentity() async throws {
        let confirmationResponses = [
            #"{"data":42}"#,
            #"{"data":{"type":"reviewSubmissions","id":"sub-other"}}"#,
            #"{"data":{"type":"reviewSubmissions","id":"sub-1","relationships":{"app":{"data":{"type":"apps","id":"app-other"}}}}}"#
        ]

        for confirmationResponse in confirmationResponses {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: submissionVersionBody(appId: "app-1")),
                .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissions","id":"sub-1"}}"#),
                .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissionItems","id":"item-1"}}"#),
                .init(statusCode: 200, body: confirmationResponse)
            ])
            let worker = try await makeWorker(transport: transport)

            let result = try await worker.handleTool(.init(
                name: "app_versions_submit_for_review",
                arguments: ["version_id": .string("ver-1"), "app_id": .string("app-1")]
            ))

            #expect(result.isError == true)
            let payload = try object(result.structuredContent)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["retrySafe"] == .bool(false))
            #expect(payload["submission_id"] == .string("sub-1"))
            #expect(payload["failed_step"] == .string("confirm_review_submission"))
            #expect(await transport.requestCount() == 4)
        }
    }

    @Test("release without confirmation returns preflight and does not post")
    func releaseWithoutConfirmationDoesNotPost() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appVersionBody(state: "PENDING_DEVELOPER_RELEASE", version: "2.5.0"))
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_release",
            arguments: ["version_id": .string("ver-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try object(result.structuredContent)
        #expect(payload["reason"] == .string("confirmation_required"))
        #expect(payload["version_string"] == .string("2.5.0"))
    }

    @Test("release blocks non pending developer release state")
    func releaseBlocksWrongState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appVersionBody(state: "READY_FOR_REVIEW", version: "2.5.0"))
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_release",
            arguments: [
                "version_id": .string("ver-1"),
                "confirm_version_string": .string("2.5.0")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try object(result.structuredContent)
        #expect(payload["reason"] == .string("invalid_app_version_state"))
        #expect(payload["app_version_state"] == .string("READY_FOR_REVIEW"))
    }

    @Test("release blocks confirmation mismatch")
    func releaseBlocksConfirmationMismatch() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appVersionBody(state: "PENDING_DEVELOPER_RELEASE", version: "2.5.0"))
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_release",
            arguments: [
                "version_id": .string("ver-1"),
                "confirm_version_string": .string("2.4.0")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try object(result.structuredContent)
        #expect(payload["reason"] == .string("confirmation_mismatch"))
    }

    @Test("release posts after valid preflight and matching confirmation")
    func releasePostsAfterValidPreflight() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appVersionBody(state: "PENDING_DEVELOPER_RELEASE", version: "2.5.0")),
            .init(statusCode: 201, body: #"{"data":{"type":"appStoreVersionReleaseRequests","id":"release-1"}}"#)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_release",
            arguments: [
                "version_id": .string("ver-1"),
                "confirm_version_string": .string("2.5.0")
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 2)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "POST"])
        let query = URLComponents(url: try #require(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first(where: { $0.name == "fields[appStoreVersions]" })?.value == "platform,versionString,appVersionState")
    }

    @Test("release preflight rejects mismatched version identity before mutation")
    func releaseRejectsMismatchedVersionIdentity() async throws {
        let responses = [
            appVersionBody(type: "apps", state: "PENDING_DEVELOPER_RELEASE", version: "2.5.0"),
            appVersionBody(id: "ver-other", state: "PENDING_DEVELOPER_RELEASE", version: "2.5.0")
        ]

        for response in responses {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: response)])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_release",
                arguments: [
                    "version_id": .string("ver-1"),
                    "confirm_version_string": .string("2.5.0")
                ]
            ))

            #expect(result.isError == true)
            let requests = await transport.recordedRequests()
            #expect(requests.count == 1)
            #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }

    @Test("release request response must identify a created release request")
    func releaseRejectsInvalidCreateResponseIdentity() async throws {
        let responses = [
            #"{"data":42}"#,
            #"{"data":{"type":"appStoreVersions","id":"release-1"}}"#,
            #"{"data":{"type":"appStoreVersionReleaseRequests","id":""}}"#
        ]

        for response in responses {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: appVersionBody(state: "PENDING_DEVELOPER_RELEASE", version: "2.5.0")),
                .init(statusCode: 201, body: response)
            ])
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_release",
                arguments: [
                    "version_id": .string("ver-1"),
                    "confirm_version_string": .string("2.5.0")
                ]
            ))

            #expect(result.isError == true)
            let payload = try object(result.structuredContent)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["retrySafe"] == .bool(false))
            #expect(await transport.requestCount() == 2)
        }
    }

    @Test("review submission create request omits platform unless explicitly provided")
    func reviewSubmissionCreateRequestOmitsPlatformByDefault() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: submissionVersionBody(appId: "app-1")),
            .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissions","id":"sub-3","attributes":{"state":"READY_FOR_REVIEW"}}}"#),
            .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissionItems","id":"item-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"reviewSubmissions","id":"sub-3","attributes":{"state":"IN_REVIEW"}}}"#)
        ])
        let worker = try await makeWorker(transport: transport)

        _ = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_submit_for_review",
            arguments: [
                "version_id": .string("ver-1"),
                "app_id": .string("app-1")
            ]
        ))

        let requests = await transport.recordedRequests()
        let createRequest = try #require(requests.first(where: {
            $0.httpMethod == "POST" && $0.url?.path == "/v1/reviewSubmissions"
        }))
        let body = try #require(createRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("\"reviewSubmissions\""))
        #expect(!body.contains("platform"))
    }
}

private func makeWorker(transport: TestHTTPTransport) async throws -> AppLifecycleWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppLifecycleWorker(httpClient: client)
}

private func appVersionBody(
    type: String = "appStoreVersions",
    id: String = "ver-1",
    state: String,
    version: String
) -> String {
    """
    {
      "data": {
        "type": "\(type)",
        "id": "\(id)",
        "attributes": {
          "platform": "IOS",
          "versionString": "\(version)",
          "appVersionState": "\(state)"
        }
      }
    }
    """
}

private func submissionVersionBody(
    type: String = "appStoreVersions",
    id: String = "ver-1",
    appType: String = "apps",
    appId: String
) -> String {
    #"{"data":{"type":"\#(type)","id":"\#(id)","attributes":{"platform":"IOS","versionString":"1.0","appVersionState":"READY_FOR_REVIEW"},"relationships":{"app":{"data":{"type":"\#(appType)","id":"\#(appId)"}}}}}"#
}

private func object(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw AppLifecycleWorkerHardeningFailure.expectedObject
    }
    return object
}

private enum AppLifecycleWorkerHardeningFailure: Error {
    case expectedObject
}
