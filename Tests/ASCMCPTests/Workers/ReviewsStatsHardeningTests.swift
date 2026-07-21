import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Reviews Stats Hardening Tests")
struct ReviewsStatsHardeningTests {
    @Test("stats schema exposes the implemented periods")
    func statsSchemaExposesImplementedPeriods() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeReviewsWorker(transport: transport)
        let tool = try #require(await worker.getTools().first { $0.name == "reviews_stats" })
        guard case .object(let schema) = tool.inputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let period)? = properties["period"],
              case .array(let values)? = period["enum"] else {
            throw ReviewsStatsHardeningFailure.expectedSchema
        }

        #expect(Set(values.compactMap(\.stringValue)) == Set([
            "last_week", "last_month", "last_3_months", "all_time"
        ]))
    }

    @Test("all-time stats follow every customer reviews page")
    func allTimeStatsFollowPagination() async throws {
        let nextURL = "https://api.example.test/v1/apps/app-1/customerReviews?cursor=next-page&limit=200&filter%5Bterritory%5D=USA&sort=-createdDate"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsPage(
                reviews: [
                    reviewJSON(id: "review-1", rating: 5, date: "2026-07-18T10:00:00Z", territory: "USA"),
                    reviewJSON(id: "review-2", rating: 1, date: "2026-07-17T10:00:00Z", territory: "USA")
                ],
                nextURL: nextURL
            )),
            .init(statusCode: 200, body: reviewsPage(
                reviews: [
                    reviewJSON(id: "review-3", rating: 4, date: "2025-01-01T10:00:00Z", territory: "USA")
                ]
            ))
        ])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string("app-1"),
                "period": .string("all_time"),
                "territory": .string("USA")
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 2)
        let requests = await transport.recordedRequests()
        let firstQuery = reviewsQueryItems(requests[0])
        #expect(firstQuery["filter[territory]"] == "USA")
        #expect(firstQuery["limit"] == "200")
        #expect(firstQuery["sort"] == "-createdDate")
        #expect(reviewsQueryItems(requests[1])["cursor"] == "next-page")

        let root = try reviewsObject(result.structuredContent)
        #expect(root["period"] == .string("all_time"))
        #expect(root["total_in_period"] == .int(3))
        #expect(root["total_in_sample"] == .int(3))
        #expect(root["reviews_scanned"] == .int(3))
        #expect(root["unique_reviews_scanned"] == .int(3))
        #expect(root["duplicates_skipped"] == .int(0))
        #expect(root["pages_fetched"] == .int(2))
        #expect(root["complete"] == .bool(true))
    }

    @Test("stats reject a same-origin next link for another API collection")
    func statsRejectCrossRoutePagination() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsPage(
                reviews: [
                    reviewJSON(id: "review-1", rating: 5, date: "2026-07-18T10:00:00Z", territory: "USA")
                ],
                nextURL: "https://api.example.test/v1/users?cursor=next-page"
            ))
        ])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string("app-1"),
                "period": .string("all_time")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("stats reject a next link that drops the originating territory filter")
    func statsRejectDroppedTerritoryFilter() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsPage(
                reviews: [
                    reviewJSON(id: "review-1", rating: 5, date: "2026-07-18T10:00:00Z", territory: "USA")
                ],
                nextURL: "https://api.example.test/v1/apps/app-1/customerReviews?cursor=next-page"
            ))
        ])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string("app-1"),
                "period": .string("all_time"),
                "territory": .string("USA")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("bounded stats stop after the requested period is complete")
    func boundedStatsStopAtPeriodBoundary() async throws {
        let recentDate = ISO8601DateFormatter().string(from: Date())
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsPage(
                reviews: [
                    reviewJSON(id: "review-recent", rating: 5, date: recentDate, territory: "USA"),
                    reviewJSON(id: "review-old", rating: 1, date: "2000-01-01T00:00:00Z", territory: "USA")
                ],
                nextURL: "https://api.example.test/v1/apps/app-1/customerReviews?cursor=unused"
            ))
        ])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string("app-1"),
                "period": .string("last_week")
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
        let root = try reviewsObject(result.structuredContent)
        #expect(root["total_in_period"] == .int(1))
        #expect(root["reviews_scanned"] == .int(2))
        #expect(root["pages_fetched"] == .int(1))
        #expect(root["period_start"] != nil)
        #expect(root["period_end"] != nil)
    }

    @Test("bounded stats aggregate pages numerically and deduplicate review IDs")
    func boundedStatsAggregatePagesAndDeduplicate() async throws {
        let recentDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let secondPage = "https://api.example.test/v1/apps/app-1/customerReviews?cursor=second&limit=200&sort=-createdDate"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsPage(
                reviews: [
                    reviewJSON(id: "review-1", rating: 5, date: recentDate, territory: "USA")
                ],
                nextURL: secondPage
            )),
            .init(statusCode: 200, body: reviewsPage(
                reviews: [
                    reviewJSON(id: "review-1", rating: 5, date: recentDate, territory: "USA"),
                    reviewJSON(id: "review-2", rating: 3, date: recentDate, territory: "USA"),
                    reviewJSON(id: "review-old", rating: 1, date: "2000-01-01T00:00:00Z", territory: "DEU")
                ],
                nextURL: "https://api.example.test/v1/apps/app-1/customerReviews?cursor=unused"
            ))
        ])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string(" app-1 "),
                "period": .string("last_week")
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 2)
        let requests = await transport.recordedRequests()
        #expect(requests.first?.url?.path == "/v1/apps/app-1/customerReviews")
        let root = try reviewsObject(result.structuredContent)
        #expect(root["total_in_period"] == .int(2))
        #expect(root["average_rating"] == .double(4))
        #expect(root["reviews_scanned"] == .int(4))
        #expect(root["unique_reviews_scanned"] == .int(3))
        #expect(root["duplicates_skipped"] == .int(1))
        #expect(root["pages_fetched"] == .int(2))
        let distribution = try reviewsObject(root["rating_distribution"])
        #expect(distribution["5"] == .int(1))
        #expect(distribution["3"] == .int(1))
        #expect(distribution["1"] == .int(0))
    }

    @Test("last three months has exact rolling calendar semantics")
    func lastThreeMonthsUsesCalendarBoundary() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeReviewsWorker(transport: transport)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-19T12:00:00Z"))
        let reviews = [
            review(id: "at-boundary", rating: 5, date: "2026-04-19T12:00:00Z"),
            review(id: "before-boundary", rating: 1, date: "2026-04-19T11:59:59Z")
        ]

        let stats = worker.calculateStats(from: reviews, period: "last_3_months", now: now)

        #expect(stats.totalCount == 1)
        #expect(stats.averageRating == 5)
        #expect(stats.periodStart == "2026-04-19T12:00:00Z")
        #expect(stats.periodEnd == "2026-07-19T12:00:00Z")
        #expect(worker.normalizeReviewPeriod("last_quarter") == "last_3_months")
    }

    @Test("unknown stats period is rejected before network")
    func unknownPeriodIsRejected() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string("app-1"),
                "period": .string("last_quarterish")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("empty app ID is rejected before network")
    func emptyAppIdIsRejected() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string(" \n ")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("stats reject a repeated strict continuation URL")
    func statsRejectPaginationCycle() async throws {
        let next = "https://api.example.test/v1/apps/app-1/customerReviews?cursor=repeat&limit=200&sort=-createdDate"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsPage(reviews: [], nextURL: next)),
            .init(statusCode: 200, body: reviewsPage(reviews: [], nextURL: next))
        ])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: [
                "app_id": .string("app-1"),
                "period": .string("all_time")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 2)
    }

    @Test("stats skip sparse reviews without failing and report incomplete aggregation")
    func statsHandleSparseReviewAttributes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewsPage(reviews: [
                "{\"type\":\"customerReviews\",\"id\":\"review-sparse\"}",
                reviewJSON(id: "review-1", rating: 5, date: "2026-07-18T10:00:00Z", territory: "USA")
            ]))
        ])
        let worker = try await makeReviewsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "reviews_stats",
            arguments: ["app_id": .string("app-1"), "period": .string("all_time")]
        ))

        #expect(result.isError != true)
        let root = try reviewsObject(result.structuredContent)
        #expect(root["total_in_period"] == .int(1))
        #expect(root["reviews_scanned"] == .int(2))
        #expect(root["unique_reviews_scanned"] == .int(2))
        #expect(root["unaggregatable_reviews_skipped"] == .int(1))
        #expect(root["complete"] == .bool(false))
    }
}

private func makeReviewsWorker(transport: TestHTTPTransport) async throws -> ReviewsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return ReviewsWorker(httpClient: client)
}

private func reviewsPage(reviews: [String], nextURL: String? = nil) -> String {
    let next = nextURL.map { ", \"next\": \"\($0)\"" } ?? ""
    return """
    {
      "data": [\(reviews.joined(separator: ","))],
      "links": {"self": "https://api.example.test/v1/apps/app-1/customerReviews"\(next)}
    }
    """
}

private func reviewJSON(id: String, rating: Int, date: String, territory: String) -> String {
    """
    {
      "type": "customerReviews",
      "id": "\(id)",
      "attributes": {
        "rating": \(rating),
        "title": "Title",
        "body": "Body",
        "reviewerNickname": "Reviewer",
        "createdDate": "\(date)",
        "territory": "\(territory)"
      }
    }
    """
}

private func review(id: String, rating: Int, date: String) -> ReviewsWorker.CustomerReview {
    ReviewsWorker.CustomerReview(
        id: id,
        type: "customerReviews",
        attributes: ReviewsWorker.ReviewAttributes(
            rating: rating,
            title: nil,
            body: nil,
            reviewerNickname: "Reviewer",
            createdDate: date,
            territory: "USA"
        ),
        relationships: nil,
        links: nil
    )
}

private func reviewsQueryItems(_ request: URLRequest) -> [String: String] {
    guard let url = request.url else { return [:] }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func reviewsObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw ReviewsStatsHardeningFailure.expectedObject
    }
    return object
}

private enum ReviewsStatsHardeningFailure: Error {
    case expectedObject
    case expectedSchema
}
