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
        let nextURL = "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&include=build%2CappStoreVersionSubmission%2CappStoreVersionPhasedRelease&filter%5BappVersionState%5D=READY_FOR_DISTRIBUTION&limit=200"

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

    @Test("version pagination uses the clamped page size")
    func versionPaginationUsesClampedLimit() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/appStoreVersions"}}"#)
        ])
        let worker = try await makeWorker(transport: transport)
        let nextURL = "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&include=build%2CappStoreVersionSubmission%2CappStoreVersionPhasedRelease&limit=200"

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .int(500),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("version pagination rejects a changed default page size")
    func versionPaginationPreservesDefaultLimit() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)
        let nextURL = "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&include=build%2CappStoreVersionSubmission%2CappStoreVersionPhasedRelease&limit=200"

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

private func appVersionBody(state: String, version: String) -> String {
    """
    {
      "data": {
        "type": "appStoreVersions",
        "id": "ver-1",
        "attributes": {
          "platform": "IOS",
          "versionString": "\(version)",
          "appVersionState": "\(state)"
        }
      }
    }
    """
}

private func submissionVersionBody(appId: String) -> String {
    #"{"data":{"type":"appStoreVersions","id":"ver-1","attributes":{"platform":"IOS","versionString":"1.0","appVersionState":"READY_FOR_REVIEW"},"relationships":{"app":{"data":{"type":"apps","id":"\#(appId)"}}}}}"#
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
