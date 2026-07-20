import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Subscription Pricing Summary Contract Tests")
struct SubscriptionPricingSummaryContractTests {
    @Test("manifest binds plan and limit and classifies the omitted price-point filter")
    func manifestClassifiesPricingSummaryInputs() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let mapping = try #require(manifest.mapping(for: "subscriptions_pricing_summary"))
        let operation = try #require(mapping.operations.first)
        let fixedInputs = operation.inputs ?? []
        let classification = try #require(operation.optionalParameterClassifications?.first)

        #expect(mapping.response.mode == .aggregate)
        #expect(mapping.fields.contains { $0.toolField == "plan_type" && $0.appleName == "filter[planType]" })
        #expect(mapping.fields.contains { $0.toolField == "limit" && $0.appleName == "limit" })
        #expect(mapping.fields.contains { $0.toolField == "max_pages" && $0.sourceKind == .local })
        #expect(fixedInputs.contains {
            $0.appleName == "include" && $0.fixedValue == .array([.string("territory"), .string("subscriptionPricePoint")])
        })
        #expect(fixedInputs.contains {
            $0.appleName == "fields[subscriptionPrices]" &&
                $0.fixedValue == .array([
                    .string("startDate"), .string("preserved"), .string("planType"),
                    .string("territory"), .string("subscriptionPricePoint")
                ])
        })
        #expect(classification.appleName == "filter[subscriptionPricePoint]")
        #expect(classification.disposition == .intentionallyOmitted)
        #expect(classification.reviewAtSpec == "4.4.1")
    }

    @Test("schema exposes plan-aware bounded traversal controls")
    func schemaExposesPlanAwareTraversal() async throws {
        let worker = SubscriptionsWorker(
            httpClient: try await TestFactory.makeHTTPClient(),
            uploadService: UploadService()
        )
        let tool = try #require(await worker.getTools().first { $0.name == "subscriptions_pricing_summary" })
        let root = try pricingSummaryObject(tool.inputSchema)
        let properties = try pricingSummaryObject(root["properties"])
        let planType = try pricingSummaryObject(properties["plan_type"])
        let limit = try pricingSummaryObject(properties["limit"])
        let maxPages = try pricingSummaryObject(properties["max_pages"])
        let territory = try pricingSummaryObject(properties["territory_id"])

        #expect(root["additionalProperties"] == .bool(false))
        #expect(try pricingSummaryArray(planType["enum"]) == [.string("MONTHLY"), .string("UPFRONT")])
        #expect(limit["minimum"] == .int(1))
        #expect(limit["maximum"] == .int(200))
        #expect(limit["default"] == .int(200))
        #expect(maxPages["minimum"] == .int(1))
        #expect(maxPages["maximum"] == .int(100))
        #expect(territory["pattern"] == .string("^[A-Za-z]{3}$"))
    }

    @Test("summary follows pages, deduplicates prices, and selects the latest current price")
    func followsPagesAndBuildsStablePlanSummary() async throws {
        let nextURL = try pricingSummaryNextURL(planType: "MONTHLY", limit: 2, cursor: "page-2")
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: try pricingSummaryPage(
                prices: [
                    .init(id: "monthly-old", planType: "MONTHLY", startDate: "2020-01-01", customerPrice: "5.99"),
                    .init(id: "monthly-future", planType: "MONTHLY", startDate: "2999-01-01", customerPrice: "12.99")
                ],
                nextURL: nextURL
            )),
            .init(statusCode: 200, body: try pricingSummaryPage(prices: [
                .init(id: "monthly-old", planType: "MONTHLY", startDate: "2020-01-01", customerPrice: "5.99"),
                .init(id: "monthly-current", planType: "MONTHLY", startDate: "2025-01-01", customerPrice: "9.99")
            ]))
        ])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: [
                "subscription_id": .string(" sub-1 "),
                "territory_id": .string(" usa "),
                "plan_type": .string("monthly"),
                "limit": .int(2)
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let firstQuery = pricingSummaryQuery(requests[0])
        let secondQuery = pricingSummaryQuery(requests[1])
        #expect(requests[0].url?.path == "/v1/subscriptions/sub-1/prices")
        #expect(firstQuery["filter[territory]"] == "USA")
        #expect(firstQuery["filter[planType]"] == "MONTHLY")
        #expect(firstQuery["fields[subscriptionPrices]"] == "startDate,preserved,planType,territory,subscriptionPricePoint")
        #expect(firstQuery["limit"] == "2")
        #expect(secondQuery["filter[territory]"] == "USA")
        #expect(secondQuery["filter[planType]"] == "MONTHLY")
        #expect(secondQuery["cursor"] == "page-2")

        let root = try pricingSummaryObject(result.structuredContent)
        #expect(root["subscription_id"] == .string("sub-1"))
        #expect(root["territory_id"] == .string("USA"))
        #expect(root["plan_type"] == .string("MONTHLY"))
        #expect(root["price_count"] == .int(3))
        #expect(root["duplicates_skipped"] == .int(1))
        #expect(root["pages_fetched"] == .int(2))
        #expect(root["complete"] == .bool(true))
        #expect(root["truncated"] == .bool(false))
        #expect(root["next_url"] == .null)
        let current = try pricingSummaryObject(root["current_price"])
        let effective = try pricingSummaryArray(root["effective_prices"])
        let scheduled = try pricingSummaryArray(root["scheduled_prices"])
        #expect(current["id"] == .string("monthly-current"))
        #expect(effective.count == 2)
        #expect(try pricingSummaryObject(effective[0])["id"] == .string("monthly-current"))
        #expect(try pricingSummaryObject(effective[1])["id"] == .string("monthly-old"))
        #expect(try pricingSummaryObject(scheduled.first)["id"] == .string("monthly-future"))
        #expect(try pricingSummaryObject(try pricingSummaryArray(root["plan_summaries"]).first)["plan_type"] == .string("MONTHLY"))
    }

    @Test("summary rejects conflicting duplicate resources across pages")
    func rejectsConflictingDuplicateResources() async throws {
        let nextURL = try pricingSummaryNextURL(planType: "MONTHLY", limit: 200, cursor: "page-2")
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: try pricingSummaryPage(
                prices: [.init(id: "monthly", planType: "MONTHLY", startDate: "2025-01-01", customerPrice: "9.99")],
                nextURL: nextURL
            )),
            .init(statusCode: 200, body: try pricingSummaryPage(prices: [
                .init(id: "monthly", planType: "MONTHLY", startDate: "2025-01-01", customerPrice: "10.99")
            ]))
        ])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "plan_type": .string("MONTHLY")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 2)
        #expect(pricingSummaryText(result).contains("conflicting resources"))
    }

    @Test("summary keeps monthly and upfront plans separate")
    func separatesMonthlyAndUpfrontPlans() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: try pricingSummaryPage(prices: [
                .init(id: "monthly", planType: "MONTHLY", startDate: "2025-01-01", customerPrice: "9.99"),
                .init(id: "upfront", planType: "UPFRONT", startDate: "2025-01-01", customerPrice: "99.99")
            ]))
        ])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: ["subscription_id": .string("sub-1"), "territory_id": .string("USA")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(pricingSummaryQuery(request)["filter[planType]"] == nil)
        let root = try pricingSummaryObject(result.structuredContent)
        #expect(root["legacy_summary_unambiguous"] == .bool(false))
        #expect(root["current_price"] == .null)
        #expect(try pricingSummaryArray(root["scheduled_prices"]).isEmpty)
        #expect(try pricingSummaryArray(root["available_plan_types"]) == [.string("MONTHLY"), .string("UPFRONT")])
        let plans = try pricingSummaryArray(root["plan_summaries"])
        #expect(plans.count == 2)
        let monthly = try pricingSummaryObject(plans[0])
        let upfront = try pricingSummaryObject(plans[1])
        #expect(monthly["plan_type"] == .string("MONTHLY"))
        #expect(try pricingSummaryObject(monthly["current_price"])["id"] == .string("monthly"))
        #expect(upfront["plan_type"] == .string("UPFRONT"))
        #expect(try pricingSummaryObject(upfront["current_price"])["id"] == .string("upfront"))
    }

    @Test("complete summary uses a stable undated starting price as current")
    func usesUndatedStartingPriceAsCurrent() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: try pricingSummaryPage(prices: [
                .init(id: "starting-b", planType: "MONTHLY", startDate: nil, customerPrice: "9.99"),
                .init(id: "starting-a", planType: "MONTHLY", startDate: nil, customerPrice: "8.99"),
                .init(id: "future", planType: "MONTHLY", startDate: "2999-01-01", customerPrice: "12.99")
            ]))
        ])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "plan_type": .string("MONTHLY")
            ]
        ))

        #expect(result.isError != true)
        let root = try pricingSummaryObject(result.structuredContent)
        #expect(try pricingSummaryObject(root["current_price"])["id"] == .string("starting-a"))
        let undated = try pricingSummaryArray(root["undated_prices"])
        #expect(undated.count == 2)
        #expect(try pricingSummaryObject(undated[0])["id"] == .string("starting-a"))
        #expect(try pricingSummaryObject(undated[1])["id"] == .string("starting-b"))
        #expect(try pricingSummaryObject(try pricingSummaryArray(root["scheduled_prices"]).first)["id"] == .string("future"))
    }

    @Test("max pages reports truncation and a stable continuation")
    func maxPagesReportsTruncation() async throws {
        let nextURL = try pricingSummaryNextURL(planType: "MONTHLY", limit: 200, cursor: "page-2")
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: try pricingSummaryPage(
                prices: [.init(id: "monthly", planType: "MONTHLY", startDate: "2025-01-01", customerPrice: "9.99")],
                nextURL: nextURL
            ))
        ])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "plan_type": .string("MONTHLY"),
                "max_pages": .int(1)
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
        let root = try pricingSummaryObject(result.structuredContent)
        #expect(root["complete"] == .bool(false))
        #expect(root["truncated"] == .bool(true))
        #expect(root["continuation_exhausted"] == .bool(false))
        #expect(root["next_url"] == .string(nextURL))
        #expect(root["pages_fetched"] == .int(1))
        #expect(root["legacy_summary_unambiguous"] == .bool(false))
        #expect(root["current_price"] == .null)
        let plan = try pricingSummaryObject(try pricingSummaryArray(root["plan_summaries"]).first)
        #expect(plan["complete"] == .bool(false))
        #expect(plan["current_price"] == .null)
    }

    @Test("continuation preserves the complete pricing scope")
    func continuationPreservesScope() async throws {
        let nextURL = try pricingSummaryNextURL(planType: "MONTHLY", limit: 25, cursor: "page-2")
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: try pricingSummaryPage(prices: [
                .init(id: "monthly", planType: "MONTHLY", startDate: "2025-01-01", customerPrice: "9.99")
            ]))
        ])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "plan_type": .string("MONTHLY"),
                "limit": .int(25),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = pricingSummaryQuery(request)
        #expect(query["filter[territory]"] == "USA")
        #expect(query["filter[planType]"] == "MONTHLY")
        #expect(query["include"] == "territory,subscriptionPricePoint")
        #expect(query["cursor"] == "page-2")
        let root = try pricingSummaryObject(result.structuredContent)
        #expect(root["started_from_continuation"] == .bool(true))
        #expect(root["continuation_exhausted"] == .bool(true))
        #expect(root["complete"] == .bool(false))
        #expect(root["truncated"] == .bool(false))
    }

    @Test("changed continuation scope fails before network access")
    func changedContinuationScopeFailsBeforeNetwork() async throws {
        let wrongPlanURL = try pricingSummaryNextURL(planType: "UPFRONT", limit: 200, cursor: "bad")
        let transport = TestHTTPTransport(responses: [])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "plan_type": .string("MONTHLY"),
                "next_url": .string(wrongPlanURL)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(pricingSummaryText(result).contains("filter[planType]"))
    }

    @Test("continuation requires a non-empty cursor before network access")
    func continuationRequiresNonEmptyCursor() async throws {
        for cursor in [String?.none, .some(""), .some(" ")] {
            let nextURL = try pricingSummaryNextURL(
                planType: "MONTHLY",
                limit: 200,
                cursor: cursor
            )
            let transport = TestHTTPTransport(responses: [])
            let worker = try await pricingSummaryWorker(transport)

            let result = try await worker.handleTool(.init(
                name: "subscriptions_pricing_summary",
                arguments: [
                    "subscription_id": .string("sub-1"),
                    "territory_id": .string("USA"),
                    "plan_type": .string("MONTHLY"),
                    "next_url": .string(nextURL)
                ]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("invalid inputs fail before network access")
    func invalidInputsFailBeforeNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await pricingSummaryWorker(transport)
        let invalidArguments: [[String: Value]] = [
            ["subscription_id": .string(" "), "territory_id": .string("USA")],
            ["subscription_id": .string("sub-1"), "territory_id": .string("US")],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "plan_type": .string("YEARLY")],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "plan_type": .int(1)],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "limit": .int(0)],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "limit": .int(201)],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "limit": .string("25")],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "max_pages": .int(0)],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "max_pages": .int(101)],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "next_url": .int(1)],
            ["subscription_id": .string("sub-1"), "territory_id": .string("USA"), "unexpected": .bool(true)]
        ]

        for arguments in invalidArguments {
            let result = try await worker.handleTool(.init(name: "subscriptions_pricing_summary", arguments: arguments))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("response plan mismatch fails instead of returning a misleading summary")
    func responsePlanMismatchFails() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: try pricingSummaryPage(prices: [
                .init(id: "upfront", planType: "UPFRONT", startDate: "2025-01-01", customerPrice: "99.99")
            ]))
        ])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "plan_type": .string("MONTHLY")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        #expect(pricingSummaryText(result).contains("does not match requested plan_type"))
    }

    @Test("repeated pagination link fails instead of looping")
    func repeatedPaginationLinkFails() async throws {
        let nextURL = try pricingSummaryNextURL(planType: "MONTHLY", limit: 200, cursor: "page-2")
        let firstPage = try pricingSummaryPage(
            prices: [.init(id: "one", planType: "MONTHLY", startDate: "2024-01-01", customerPrice: "8.99")],
            nextURL: nextURL
        )
        let secondPage = try pricingSummaryPage(
            prices: [.init(id: "two", planType: "MONTHLY", startDate: "2025-01-01", customerPrice: "9.99")],
            nextURL: nextURL
        )
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: firstPage),
            .init(statusCode: 200, body: secondPage)
        ])
        let worker = try await pricingSummaryWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_pricing_summary",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "plan_type": .string("MONTHLY")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 2)
        #expect(pricingSummaryText(result).contains("repeated next URL"))
    }
}

private struct PricingSummaryFixture {
    let id: String
    let planType: String?
    let startDate: String?
    let customerPrice: String
}

private func pricingSummaryWorker(_ transport: TestHTTPTransport) async throws -> SubscriptionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return SubscriptionsWorker(httpClient: client, uploadService: UploadService())
}

private func pricingSummaryPage(prices: [PricingSummaryFixture], nextURL: String? = nil) throws -> String {
    let resources: [[String: Any]] = prices.map { price in
        var attributes: [String: Any] = ["preserved": false]
        if let planType = price.planType {
            attributes["planType"] = planType
        }
        if let startDate = price.startDate {
            attributes["startDate"] = startDate
        }
        return [
            "type": "subscriptionPrices",
            "id": price.id,
            "attributes": attributes,
            "relationships": [
                "territory": ["data": ["type": "territories", "id": "USA"]],
                "subscriptionPricePoint": ["data": ["type": "subscriptionPricePoints", "id": "point-\(price.id)"]]
            ]
        ]
    }
    var included: [[String: Any]] = [
        ["type": "territories", "id": "USA", "attributes": ["currency": "USD"]]
    ]
    included.append(contentsOf: prices.map { price in
        [
            "type": "subscriptionPricePoints",
            "id": "point-\(price.id)",
            "attributes": [
                "customerPrice": price.customerPrice,
                "proceeds": "7.00",
                "proceedsYear2": "8.50"
            ]
        ]
    })
    var links: [String: Any] = ["self": "https://api.example.test/v1/subscriptions/sub-1/prices"]
    if let nextURL {
        links["next"] = nextURL
    }
    let document: [String: Any] = ["data": resources, "included": included, "links": links]
    let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    guard let string = String(data: data, encoding: .utf8) else {
        throw SubscriptionPricingSummaryTestFailure.invalidUTF8
    }
    return string
}

private func pricingSummaryNextURL(
    subscriptionId: String = "sub-1",
    territoryId: String = "USA",
    planType: String? = nil,
    limit: Int,
    cursor: String?
) throws -> String {
    var components = URLComponents(string: "https://api.example.test/v1/subscriptions/\(subscriptionId)/prices")
    var queryItems = [
        URLQueryItem(name: "filter[territory]", value: territoryId),
        URLQueryItem(name: "include", value: "territory,subscriptionPricePoint"),
        URLQueryItem(name: "fields[subscriptionPrices]", value: "startDate,preserved,planType,territory,subscriptionPricePoint"),
        URLQueryItem(name: "fields[subscriptionPricePoints]", value: "customerPrice,proceeds,proceedsYear2,territory,equalizations"),
        URLQueryItem(name: "fields[territories]", value: "currency"),
        URLQueryItem(name: "limit", value: String(limit))
    ]
    if let cursor {
        queryItems.append(URLQueryItem(name: "cursor", value: cursor))
    }
    if let planType {
        queryItems.append(URLQueryItem(name: "filter[planType]", value: planType))
    }
    components?.queryItems = queryItems
    guard let url = components?.url?.absoluteString else {
        throw SubscriptionPricingSummaryTestFailure.invalidURL
    }
    return url
}

private func pricingSummaryQuery(_ request: URLRequest) -> [String: String] {
    let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func pricingSummaryObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw SubscriptionPricingSummaryTestFailure.expectedObject
    }
    return object
}

private func pricingSummaryArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw SubscriptionPricingSummaryTestFailure.expectedArray
    }
    return array
}

private func pricingSummaryText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private enum SubscriptionPricingSummaryTestFailure: Error {
    case expectedObject
    case expectedArray
    case invalidURL
    case invalidUTF8
}
