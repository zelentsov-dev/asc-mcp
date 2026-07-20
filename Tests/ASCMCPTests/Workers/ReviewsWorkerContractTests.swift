import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Reviews Worker Apple Contract Tests")
struct ReviewsWorkerContractTests {
    @Test("schemas expose current review filters, sort, response existence, and summarization continuation")
    func schemasExposeCurrentInputs() async throws {
        let worker = try await reviewsContractWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        for name in ["reviews_list", "reviews_list_for_version"] {
            let properties = try reviewsContractProperties(
                try #require(tools.first { $0.name == name })
            )
            #expect(properties["ratings"]?["type"] == .string("array"))
            #expect(properties["territories"]?["type"] == .string("array"))
            #expect(properties["has_published_response"]?["type"] == .string("boolean"))
            let sort = try #require(properties["sort"])
            let sortVariants = try reviewsContractArray(sort["oneOf"])
            #expect(sortVariants.count == 2)
            let scalarSort = try reviewsContractObject(try #require(sortVariants.first))
            let scalarSortValues = try reviewsContractArray(scalarSort["enum"])
            #expect(Set(scalarSortValues.compactMap(\.stringValue)) == Set([
                "rating", "-rating", "createdDate", "-createdDate"
            ]))
            let arraySort = try reviewsContractObject(try #require(sortVariants.last))
            #expect(arraySort["type"] == .string("array"))
            #expect(arraySort["minItems"] == .int(1))
            #expect(arraySort["uniqueItems"] == .bool(true))
            let arraySortItems = try reviewsContractObject(arraySort["items"])
            #expect(try reviewsContractArray(arraySortItems["enum"]) == scalarSortValues)
        }

        let stats = try reviewsContractProperties(
            try #require(tools.first { $0.name == "reviews_stats" })
        )
        #expect(stats["has_published_response"]?["type"] == .string("boolean"))

        let summarizations = try reviewsContractProperties(
            try #require(tools.first { $0.name == "reviews_summarizations" })
        )
        #expect(summarizations["territory_id"]?["type"] == .string("string"))
        #expect(summarizations["next_url"]?["type"] == .string("string"))
    }

    @Test("reviews_list sends Apple array filters and preserves included developer responses")
    func listProjectsIncludedResponses() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsContractPageWithResponse())
        ])
        let worker = try await reviewsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_list",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .int(50),
                "ratings": .array([.int(5), .int(3)]),
                "territories": .array([.string("usa"), .string("DEU")]),
                "sort": .string("-rating"),
                "include_response": .bool(true),
                "has_published_response": .bool(true)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/apps/app-1/customerReviews")
        let query = reviewsContractQuery(request)
        #expect(query["limit"] == "50")
        #expect(query["filter[rating]"] == "5,3")
        #expect(query["filter[territory]"] == "USA,DEU")
        #expect(query["sort"] == "-rating")
        #expect(query["include"] == "response")
        #expect(query["exists[publishedResponse]"] == "true")

        let payload = try reviewsContractObject(result.structuredContent)
        let reviews = try reviewsContractArray(payload["reviews"])
        let review = try reviewsContractObject(try #require(reviews.first))
        #expect(review["has_response"] == .bool(true))
        let response = try reviewsContractObject(review["response"])
        #expect(response["id"] == .string("response-1"))
        #expect(response["response_body"] == .string("Thanks for the feedback"))
        #expect(response["last_modified_date"] == .string("2026-07-19T12:34:56Z"))
        #expect(response["state"] == .string("PUBLISHED"))
        #expect(response["review_id"] == .string("review-1"))
    }

    @Test("version reviews use the version relationship endpoint and current query controls")
    func versionListUsesCurrentControls() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsContractEmptyPage(path: "/v1/appStoreVersions/version-1/customerReviews"))
        ])
        let worker = try await reviewsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_list_for_version",
            arguments: [
                "version_id": .string("version-1"),
                "rating": .int(4),
                "territory": .string("gbr"),
                "sort": .array([.string("-rating"), .string("-createdDate")]),
                "has_published_response": .bool(false)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/appStoreVersions/version-1/customerReviews")
        let query = reviewsContractQuery(request)
        #expect(query["filter[rating]"] == "4")
        #expect(query["filter[territory]"] == "GBR")
        #expect(query["exists[publishedResponse]"] == "false")
        #expect(query["sort"] == "-rating,-createdDate")
    }

    @Test("review continuation preserves filters, sort, include, and response-existence scope")
    func listContinuationProtectsQueryScope() async throws {
        let acceptedURL = "https://api.example.test/v1/apps/app-1/customerReviews?cursor=next&sort=-rating%2C-createdDate&filter%5Brating%5D=1%2C2&filter%5Bterritory%5D=USA%2CDEU&include=response&exists%5BpublishedResponse%5D=false&limit=100"
        let acceptedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsContractEmptyPage(path: "/v1/apps/app-1/customerReviews"))
        ])
        let acceptedWorker = try await reviewsContractWorker(transport: acceptedTransport)
        let arguments = reviewsContinuationArguments(nextURL: acceptedURL)
        let acceptedResult = try await acceptedWorker.handleTool(CallTool.Parameters(
            name: "reviews_list",
            arguments: arguments
        ))

        #expect(acceptedResult.isError != true)
        #expect(await acceptedTransport.requestCount() == 1)

        let rejectedURL = "https://api.example.test/v1/apps/app-1/customerReviews?cursor=next&sort=-rating%2C-createdDate&filter%5Brating%5D=1%2C2&filter%5Bterritory%5D=USA%2CDEU&exists%5BpublishedResponse%5D=false&limit=100"
        let rejectedTransport = TestHTTPTransport(responses: [])
        let rejectedWorker = try await reviewsContractWorker(transport: rejectedTransport)
        let rejectedResult = try await rejectedWorker.handleTool(CallTool.Parameters(
            name: "reviews_list",
            arguments: reviewsContinuationArguments(nextURL: rejectedURL)
        ))

        #expect(rejectedResult.isError == true)
        #expect(await rejectedTransport.requestCount() == 0)

        let changedSortURL = "https://api.example.test/v1/apps/app-1/customerReviews?cursor=next&sort=-createdDate&filter%5Brating%5D=1%2C2&filter%5Bterritory%5D=USA%2CDEU&include=response&exists%5BpublishedResponse%5D=false&limit=100"
        let changedSortTransport = TestHTTPTransport(responses: [])
        let changedSortWorker = try await reviewsContractWorker(transport: changedSortTransport)
        let changedSortResult = try await changedSortWorker.handleTool(CallTool.Parameters(
            name: "reviews_list",
            arguments: reviewsContinuationArguments(nextURL: changedSortURL)
        ))

        #expect(changedSortResult.isError == true)
        #expect(await changedSortTransport.requestCount() == 0)
    }

    @Test("reviews_get_response uses Apple's documented response relationship endpoint")
    func getResponseUsesRelatedEndpoint() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsContractResponseResource())
        ])
        let worker = try await reviewsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_get_response",
            arguments: ["review_id": .string("review-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/customerReviews/review-1/response")
        let requestURL = try #require(request.url)
        let queryItems = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems.isEmpty)
        let payload = try reviewsContractObject(result.structuredContent)
        #expect(payload["has_response"] == .bool(true))
        let response = try reviewsContractObject(payload["response"])
        #expect(response["last_modified_date"] == .string("2026-07-19T12:34:56Z"))
        #expect(response["review_id"] == .string("review-1"))
    }

    @Test("reviews_get_response confirms the parent review before mapping response 404 to absent")
    func getResponseConfirmsParentBeforeMappingNotFound() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 404, body: "{}"),
            .init(statusCode: 200, body: reviewsContractReviewResource())
        ])
        let worker = try await reviewsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_get_response",
            arguments: ["review_id": .string("review-without-response")]
        ))

        #expect(result.isError != true)
        let payload = try reviewsContractObject(result.structuredContent)
        #expect(payload["has_response"] == .bool(false))
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests.first?.url?.path == "/v1/customerReviews/review-without-response/response")
        #expect(requests.last?.url?.path == "/v1/customerReviews/review-without-response")
    }

    @Test("reviews_get_response preserves parent lookup failures after response 404")
    func getResponseDoesNotMaskMissingOrFailedParent() async throws {
        for parentStatus in [404, 500] {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 404, body: "{}"),
                .init(statusCode: parentStatus, body: "{}")
            ])
            let worker = try await reviewsContractWorker(transport: transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "reviews_get_response",
                arguments: ["review_id": .string("missing-review")]
            ))

            #expect(result.isError == true)
            #expect(reviewsContractText(result).contains("Failed to verify review"))
            #expect(await transport.requestCount() == 2)
        }
    }

    @Test("review sort rejects malformed arrays before the network")
    func sortRejectsMalformedArrays() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await reviewsContractWorker(transport: transport)
        let invalidSorts: [Value] = [
            .array([]),
            .array([.string("-createdDate"), .int(1)]),
            .array([.string("rating"), .string("rating")]),
            .array([.string("unsupported")]),
            .array([.string(" rating")])
        ]

        for sort in invalidSorts {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "reviews_list",
                arguments: [
                    "app_id": .string("app-1"),
                    "sort": sort
                ]
            ))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("reviews manifest records compound response lookup and multi-value sort")
    func manifestRecordsResponseFallbackAndSortCardinality() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let responseLookup = try #require(manifest.mapping(for: "reviews_get_response"))
        #expect(responseLookup.kind == .compound)
        let parentLookup = try #require(
            responseLookup.operations.first { $0.operationID == "customerReviews_getInstance" }
        )
        #expect(parentLookup.role == .conditional)
        #expect(parentLookup.condition?.contains("returns 404") == true)

        for toolName in ["reviews_list", "reviews_list_for_version"] {
            let mapping = try #require(manifest.mapping(for: toolName))
            let sort = try #require(mapping.fields.first { $0.toolField == "sort" })
            #expect(sort.appleName == "sort")
            #expect(sort.localRole?.contains("scalar or ordered string array") == true)
            #expect(mapping.note?.contains("explode=false CSV semantics") == true)
        }
    }

    @Test("review stats forwards published-response existence with fixed descending sort")
    func statsForwardsResponseExistence() async throws {
        let nextURL = "https://api.example.test/v1/apps/app-1/customerReviews?cursor=next&sort=-createdDate&exists%5BpublishedResponse%5D=false&limit=200"
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: reviewsContractEmptyPage(
                    path: "/v1/apps/app-1/customerReviews",
                    nextURL: nextURL
                )
            ),
            .init(statusCode: 200, body: reviewsContractEmptyPage(path: "/v1/apps/app-1/customerReviews"))
        ])
        let worker = try await reviewsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string("app-1"),
                "period": .string("all_time"),
                "has_published_response": .bool(false)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = reviewsContractQuery(request)
        #expect(query["limit"] == "200")
        #expect(query["sort"] == "-createdDate")
        #expect(query["exists[publishedResponse]"] == "false")
        #expect(await transport.requestCount() == 2)
    }

    @Test("summarizations forward territory and protect platform and territory on continuation")
    func summarizationsSupportTerritoryAndContinuation() async throws {
        let nextURL = "https://api.example.test/v1/apps/app-1/customerReviewSummarizations?cursor=next&filter%5Bplatform%5D=IOS&filter%5Bterritory%5D=territory-1&limit=40"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsContractSummarizations(nextURL: nextURL)),
            .init(statusCode: 200, body: reviewsContractSummarizations(nextURL: nil))
        ])
        let worker = try await reviewsContractWorker(transport: transport)
        let baseArguments: [String: Value] = [
            "app_id": .string("app-1"),
            "platform": .string("IOS"),
            "territory_id": .string("territory-1"),
            "limit": .int(40)
        ]

        let firstResult = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_summarizations",
            arguments: baseArguments
        ))
        #expect(firstResult.isError != true)
        let firstRequest = try #require(await transport.recordedRequests().first)
        let firstQuery = reviewsContractQuery(firstRequest)
        #expect(firstQuery["filter[platform]"] == "IOS")
        #expect(firstQuery["filter[territory]"] == "territory-1")
        #expect(firstQuery["limit"] == "40")
        #expect(try reviewsContractObject(firstResult.structuredContent)["next_url"] == .string(nextURL))

        var continuationArguments = baseArguments
        continuationArguments["next_url"] = .string(nextURL)
        let continuationResult = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_summarizations",
            arguments: continuationArguments
        ))
        #expect(continuationResult.isError != true)
        #expect(await transport.requestCount() == 2)
    }
}

private func reviewsContractWorker(transport: TestHTTPTransport) async throws -> ReviewsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return ReviewsWorker(httpClient: client)
}

private func reviewsContractProperties(_ tool: Tool) throws -> [String: [String: Value]] {
    guard case .object(let root) = tool.inputSchema,
          case .object(let properties)? = root["properties"] else {
        throw ReviewsWorkerContractFailure.expectedObject
    }
    var result: [String: [String: Value]] = [:]
    for (name, value) in properties {
        if case .object(let property) = value {
            result[name] = property
        }
    }
    return result
}

private func reviewsContinuationArguments(nextURL: String) -> [String: Value] {
    [
        "app_id": .string("app-1"),
        "ratings": .array([.int(1), .int(2)]),
        "territories": .array([.string("USA"), .string("DEU")]),
        "sort": .array([.string("-rating"), .string("-createdDate")]),
        "include_response": .bool(true),
        "has_published_response": .bool(false),
        "next_url": .string(nextURL)
    ]
}

private func reviewsContractText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private func reviewsContractQuery(_ request: URLRequest) -> [String: String] {
    guard let url = request.url else { return [:] }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func reviewsContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw ReviewsWorkerContractFailure.expectedObject
    }
    return object
}

private func reviewsContractArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw ReviewsWorkerContractFailure.expectedArray
    }
    return array
}

private func reviewsContractEmptyPage(path: String, nextURL: String? = nil) -> String {
    let next = nextURL.map { ", \"next\": \"\($0)\"" } ?? ""
    return """
    {
      "data": [],
      "links": {"self": "https://api.example.test\(path)"\(next)}
    }
    """
}

private func reviewsContractPageWithResponse() -> String {
    """
    {
      "data": [
        {
          "type": "customerReviews",
          "id": "review-1",
          "attributes": {
            "rating": 5,
            "title": "Great",
            "body": "Useful app",
            "reviewerNickname": "Reviewer",
            "createdDate": "2026-07-18T10:00:00Z",
            "territory": "USA"
          },
          "relationships": {
            "response": {
              "data": {"type": "customerReviewResponses", "id": "response-1"}
            }
          }
        }
      ],
      "included": [
        {
          "type": "customerReviewResponses",
          "id": "response-1",
          "attributes": {
            "responseBody": "Thanks for the feedback",
            "lastModifiedDate": "2026-07-19T12:34:56Z",
            "state": "PUBLISHED"
          },
          "relationships": {
            "review": {
              "data": {"type": "customerReviews", "id": "review-1"}
            }
          }
        }
      ],
      "links": {"self": "https://api.example.test/v1/apps/app-1/customerReviews"},
      "meta": {"paging": {"total": 1, "limit": 50}}
    }
    """
}

private func reviewsContractResponseResource() -> String {
    """
    {
      "data": {
        "type": "customerReviewResponses",
        "id": "response-1",
        "attributes": {
          "responseBody": "Thanks for the feedback",
          "lastModifiedDate": "2026-07-19T12:34:56Z",
          "state": "PUBLISHED"
        },
        "relationships": {
          "review": {
            "data": {"type": "customerReviews", "id": "review-1"}
          }
        }
      }
    }
    """
}

private func reviewsContractReviewResource() -> String {
    """
    {
      "data": {
        "type": "customerReviews",
        "id": "review-without-response"
      }
    }
    """
}

private func reviewsContractSummarizations(nextURL: String?) -> String {
    let next = nextURL.map { ", \"next\": \"\($0)\"" } ?? ""
    return """
    {
      "data": [],
      "links": {"self": "https://api.example.test/v1/apps/app-1/customerReviewSummarizations"\(next)}
    }
    """
}

private enum ReviewsWorkerContractFailure: Error {
    case expectedArray
    case expectedObject
}
