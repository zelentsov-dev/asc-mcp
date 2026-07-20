import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Beta App Worker Contract Tests")
struct BetaAppWorkerContractTests {
    @Test("review detail update preserves value null and omission")
    func reviewDetailUpdatePreservesValueNullAndOmission() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "betaAppReviewDetails",
                "id": "detail-1",
                "attributes": {"contactFirstName": "Alex", "contactEmail": null, "demoAccountRequired": null, "demoAccountPassword": "secret"}
              }
            }
            """)
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_update_review_details",
            arguments: [
                "review_detail_id": .string("detail-1"),
                "contact_first_name": .string("Alex"),
                "contact_email": .null,
                "demo_account_required": .null
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/betaAppReviewDetails/detail-1")
        let attributes = try betaAppContractRequestAttributes(request)
        #expect(Set(attributes.keys) == ["contactFirstName", "contactEmail", "demoAccountRequired"])
        #expect(attributes["contactFirstName"] as? String == "Alex")
        #expect(attributes["contactEmail"] is NSNull)
        #expect(attributes["demoAccountRequired"] is NSNull)
        #expect(attributes["notes"] == nil)
        let root = try betaAppContractObject(result.structuredContent)
        let reviewDetail = try betaAppContractObject(root["review_detail"])
        #expect(reviewDetail["demoAccountPassword"] == .string("[REDACTED]"))
    }

    @Test("review detail update rejects empty and malformed patches")
    func reviewDetailUpdateRejectsEmptyAndMalformedPatches() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_update_review_details",
            arguments: ["review_detail_id": .string("detail-1")]
        ))
        let malformed = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_update_review_details",
            arguments: [
                "review_detail_id": .string("detail-1"),
                "contact_email": .int(1)
            ]
        ))

        #expect(empty.isError == true)
        #expect(malformed.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("localization update rejects null malformed and empty writes")
    func localizationUpdateRejectsInvalidWrites() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let explicitNull = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_update_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "description": .null
            ]
        ))
        let malformed = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_update_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "feedback_email": .int(1)
            ]
        ))
        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_update_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))

        #expect(explicitNull.isError == true)
        #expect(malformed.isError == true)
        #expect(empty.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("localization create rejects malformed optional values")
    func localizationCreateRejectsMalformedOptionalValues() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_create_localization",
            arguments: [
                "app_id": .string("app-1"),
                "locale": .string("en-US"),
                "marketing_url": .bool(true)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("localization get requires only its resource ID")
    func localizationGetRequiresOnlyResourceID() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"betaAppLocalizations","id":"loc-1","attributes":{"locale":"en-US"}}}"#)
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/betaAppLocalizations/loc-1")
    }

    @Test("submission list encodes Apple array filters and preserves build linkage")
    func submissionListEncodesArrayFiltersAndPreservesBuildLinkage() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "betaAppReviewSubmissions",
                  "id": "submission-1",
                  "attributes": {"betaReviewState": "IN_REVIEW"},
                  "relationships": {
                    "build": {
                      "data": {"type": "builds", "id": "build-1"},
                      "links": {"related": "https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions/submission-1/build"}
                    }
                  }
                }
              ],
              "meta": {"paging": {"total": 3, "limit": 25}}
            }
            """)
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: [
                "build_id": .array([.string("build-1"), .string("build-2")]),
                "review_state": .array([.string("WAITING_FOR_REVIEW"), .string("IN_REVIEW")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = betaAppContractQuery(request)
        #expect(query["filter[build]"] == "build-1,build-2")
        #expect(query["filter[betaReviewState]"] == "WAITING_FOR_REVIEW,IN_REVIEW")
        let root = try betaAppContractObject(result.structuredContent)
        #expect(root["total"] == .int(3))
        let submissions = try betaAppContractArray(root["submissions"])
        let submission = try betaAppContractObject(submissions.first)
        #expect(submission["buildId"] == .string("build-1"))
        #expect(submission["betaReviewState"] == .string("IN_REVIEW"))
    }

    @Test("submission list rejects unsupported filter values before network")
    func submissionListRejectsUnsupportedFilterValues() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: [
                "build_id": .string("build-1"),
                "review_state": .array([.string("APPROVED"), .string("UNKNOWN")])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("localization list preserves paging total and sparse resources")
    func localizationListPreservesPagingTotalAndSparseResources() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{"type": "betaAppLocalizations", "id": "loc-1"}],
              "meta": {"paging": {"total": 4, "limit": 25}}
            }
            """)
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_localizations",
            arguments: ["app_id": .string("app-1")]
        ))

        #expect(result.isError != true)
        let root = try betaAppContractObject(result.structuredContent)
        #expect(root["total"] == .int(4))
        let localization = try betaAppContractObject(try betaAppContractArray(root["localizations"]).first)
        #expect(localization["id"] == .string("loc-1"))
        #expect(localization["locale"] == .null)
    }

    @Test("beta app schemas expose nullable updates arrays and bounds")
    func betaAppSchemasExposeContracts() async throws {
        let worker = BetaAppWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tools = await worker.getTools()
        let updateReview = try #require(tools.first { $0.name == "beta_app_update_review_details" })
        let updateLocalization = try #require(tools.first { $0.name == "beta_app_update_localization" })
        let listSubmissions = try #require(tools.first { $0.name == "beta_app_list_submissions" })

        let reviewProperties = try betaAppContractProperties(updateReview)
        #expect(try betaAppContractArray(try betaAppContractObject(reviewProperties["contact_email"])["type"]) == [.string("string"), .string("null")])
        #expect(try betaAppContractObject(updateReview.inputSchema)["minProperties"] == .int(2))
        #expect(try betaAppContractObject(updateLocalization.inputSchema)["minProperties"] == .int(2))
        let submissionProperties = try betaAppContractProperties(listSubmissions)
        #expect(try betaAppContractObject(submissionProperties["build_id"])["oneOf"] != nil)
        let limit = try betaAppContractObject(submissionProperties["limit"])
        #expect(limit["minimum"] == .int(1))
        #expect(limit["maximum"] == .int(200))
    }
}

private func makeBetaAppContractClient(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func betaAppContractQuery(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func betaAppContractRequestAttributes(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(json["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private func betaAppContractProperties(_ tool: Tool) throws -> [String: Value] {
    let schema = try betaAppContractObject(tool.inputSchema)
    return try betaAppContractObject(schema["properties"])
}

private func betaAppContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw BetaAppContractTestError.expectedObject
    }
    return object
}

private func betaAppContractArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw BetaAppContractTestError.expectedArray
    }
    return array
}

private enum BetaAppContractTestError: Error {
    case expectedObject
    case expectedArray
}
