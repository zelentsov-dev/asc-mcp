import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Legacy Commerce Pagination Scope Tests")
struct LegacyCommercePaginationScopeTests {
    @Test("every legacy commerce continuation preserves its complete scope")
    func acceptsCompleteScopes() async throws {
        for fixture in legacyCommercePaginationFixtures() {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: #"{"data":[]}"#)
            ])
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query["cursor"] = "next"
            arguments["next_url"] = .string(legacyCommercePaginationURL(path: fixture.path, query: query))

            let result = try await invokeLegacyCommerceFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError != true, "Expected valid continuation for \(fixture.toolName)")
            let request = try #require(await transport.recordedRequests().first)
            #expect(request.url?.path == fixture.path)
            #expect(legacyCommercePaginationQuery(request) == query)
        }
    }

    @Test("legacy commerce continuations preserve distinct effective default limits")
    func preservesEffectiveDefaultLimits() async throws {
        for fixture in legacyCommerceDefaultLimitFixtures() {
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"

            let validTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: #"{"data":[]}"#)
            ])
            var validArguments = fixture.arguments
            validArguments["next_url"] = .string(legacyCommercePaginationURL(
                path: fixture.path,
                query: validQuery
            ))
            let validResult = try await invokeLegacyCommerceFixture(
                fixture,
                arguments: validArguments,
                transport: validTransport
            )
            #expect(validResult.isError != true, "Expected default limit for \(fixture.toolName)")
            let request = try #require(await validTransport.recordedRequests().first)
            #expect(legacyCommercePaginationQuery(request)["limit"] == fixture.requiredQuery["limit"])

            let changedTransport = TestHTTPTransport(responses: [])
            var changedArguments = fixture.arguments
            var changedQuery = validQuery
            changedQuery["limit"] = "1"
            changedArguments["next_url"] = .string(legacyCommercePaginationURL(
                path: fixture.path,
                query: changedQuery
            ))
            let changedResult = try await invokeLegacyCommerceFixture(
                fixture,
                arguments: changedArguments,
                transport: changedTransport
            )
            #expect(changedResult.isError == true, "Expected default limit drift rejection for \(fixture.toolName)")
            #expect(await changedTransport.requestCount() == 0)
        }
    }

    @Test("every legacy commerce continuation requires a non-empty cursor")
    func rejectsMissingAndEmptyCursors() async throws {
        for fixture in legacyCommercePaginationFixtures() {
            for cursor in [String?.none, .some(""), .some(" ")] {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var query = fixture.requiredQuery
                if let cursor {
                    query["cursor"] = cursor
                }
                arguments["next_url"] = .string(legacyCommercePaginationURL(path: fixture.path, query: query))

                let result = try await invokeLegacyCommerceFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected cursor rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("every legacy commerce continuation preserves each originating query value")
    func rejectsMissingAndChangedQueryValues() async throws {
        for fixture in legacyCommercePaginationFixtures() {
            for name in fixture.requiredQuery.keys {
                for mutation in LegacyCommerceQueryMutation.allCases {
                    let transport = TestHTTPTransport(responses: [])
                    var arguments = fixture.arguments
                    var query = fixture.requiredQuery
                    switch mutation {
                    case .missing:
                        query.removeValue(forKey: name)
                    case .changed:
                        query[name] = "drift"
                    }
                    query["cursor"] = "next"
                    arguments["next_url"] = .string(legacyCommercePaginationURL(path: fixture.path, query: query))

                    let result = try await invokeLegacyCommerceFixture(
                        fixture,
                        arguments: arguments,
                        transport: transport
                    )

                    #expect(result.isError == true, "Expected \(name) rejection for \(fixture.toolName)")
                    #expect(await transport.requestCount() == 0)
                }
            }
        }
    }

    @Test("every legacy commerce continuation rejects parent and query injection")
    func rejectsParentAndQueryInjection() async throws {
        for fixture in legacyCommercePaginationFixtures() {
            var invalidQueries: [[String: String]] = []
            var unexpected = fixture.requiredQuery
            unexpected["cursor"] = "next"
            unexpected["filter[unexpected]"] = "drift"
            invalidQueries.append(unexpected)

            for query in invalidQueries {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(legacyCommercePaginationURL(path: fixture.path, query: query))
                let result = try await invokeLegacyCommerceFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )
                #expect(result.isError == true, "Expected query injection rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }

            let wrongParentTransport = TestHTTPTransport(responses: [])
            var wrongParentArguments = fixture.arguments
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"
            wrongParentArguments["next_url"] = .string(legacyCommercePaginationURL(
                path: fixture.wrongParentPath,
                query: validQuery
            ))
            let wrongParentResult = try await invokeLegacyCommerceFixture(
                fixture,
                arguments: wrongParentArguments,
                transport: wrongParentTransport
            )
            #expect(wrongParentResult.isError == true, "Expected parent rejection for \(fixture.toolName)")
            #expect(await wrongParentTransport.requestCount() == 0)

            let duplicateTransport = TestHTTPTransport(responses: [])
            var duplicateArguments = fixture.arguments
            let duplicateURL = legacyCommercePaginationURL(path: fixture.path, query: validQuery) + "&limit=1"
            duplicateArguments["next_url"] = .string(duplicateURL)
            let duplicateResult = try await invokeLegacyCommerceFixture(
                fixture,
                arguments: duplicateArguments,
                transport: duplicateTransport
            )
            #expect(duplicateResult.isError == true, "Expected duplicate query rejection for \(fixture.toolName)")
            #expect(await duplicateTransport.requestCount() == 0)
        }
    }
}

private enum LegacyCommerceWorkerKind {
    case iap
    case introductoryOffers
    case promotionalOffers
    case offerCodes
    case winBackOffers
}

private enum LegacyCommerceQueryMutation: CaseIterable {
    case missing
    case changed
}

private struct LegacyCommercePaginationFixture {
    let worker: LegacyCommerceWorkerKind
    let toolName: String
    let arguments: [String: Value]
    let path: String
    let wrongParentPath: String
    let requiredQuery: [String: String]
}

private func legacyCommercePaginationFixtures() -> [LegacyCommercePaginationFixture] {
    [
        LegacyCommercePaginationFixture(
            worker: .iap,
            toolName: "iap_list_price_points legacy handler",
            arguments: [
                "iap_id": .string("iap-1"),
                "territory": .string("USA"),
                "limit": .int(200)
            ],
            path: "/v2/inAppPurchases/iap-1/pricePoints",
            wrongParentPath: "/v2/inAppPurchases/iap-2/pricePoints",
            requiredQuery: ["filter[territory]": "USA", "limit": "200"]
        ),
        LegacyCommercePaginationFixture(
            worker: .introductoryOffers,
            toolName: "intro_offers_list",
            arguments: [
                "subscription_id": .string("sub-1"),
                "filter_territory": .string("USA"),
                "limit": .int(200)
            ],
            path: "/v1/subscriptions/sub-1/introductoryOffers",
            wrongParentPath: "/v1/subscriptions/sub-2/introductoryOffers",
            requiredQuery: ["filter[territory]": "USA", "limit": "200"]
        ),
        LegacyCommercePaginationFixture(
            worker: .promotionalOffers,
            toolName: "promo_offers_list",
            arguments: ["subscription_id": .string("sub-1"), "limit": .int(200)],
            path: "/v1/subscriptions/sub-1/promotionalOffers",
            wrongParentPath: "/v1/subscriptions/sub-2/promotionalOffers",
            requiredQuery: ["limit": "200"]
        ),
        LegacyCommercePaginationFixture(
            worker: .promotionalOffers,
            toolName: "promo_offers_list_prices",
            arguments: ["promotional_offer_id": .string("promo-1"), "limit": .int(200)],
            path: "/v1/subscriptionPromotionalOffers/promo-1/prices",
            wrongParentPath: "/v1/subscriptionPromotionalOffers/promo-2/prices",
            requiredQuery: ["limit": "200"]
        ),
        LegacyCommercePaginationFixture(
            worker: .offerCodes,
            toolName: "offer_codes_list",
            arguments: ["subscription_id": .string("sub-1"), "limit": .int(200)],
            path: "/v1/subscriptions/sub-1/offerCodes",
            wrongParentPath: "/v1/subscriptions/sub-2/offerCodes",
            requiredQuery: ["limit": "200"]
        ),
        LegacyCommercePaginationFixture(
            worker: .offerCodes,
            toolName: "offer_codes_list_prices",
            arguments: ["offer_code_id": .string("offer-1"), "limit": .int(200)],
            path: "/v1/subscriptionOfferCodes/offer-1/prices",
            wrongParentPath: "/v1/subscriptionOfferCodes/offer-2/prices",
            requiredQuery: ["limit": "200"]
        ),
        LegacyCommercePaginationFixture(
            worker: .winBackOffers,
            toolName: "winback_list_prices",
            arguments: ["winback_offer_id": .string("winback-1"), "limit": .int(200)],
            path: "/v1/winBackOffers/winback-1/prices",
            wrongParentPath: "/v1/winBackOffers/winback-2/prices",
            requiredQuery: ["limit": "200"]
        )
    ]
}

private func legacyCommerceDefaultLimitFixtures() -> [LegacyCommercePaginationFixture] {
    [
        LegacyCommercePaginationFixture(
            worker: .iap,
            toolName: "iap_list_price_points legacy default",
            arguments: ["iap_id": .string("iap-1")],
            path: "/v2/inAppPurchases/iap-1/pricePoints",
            wrongParentPath: "/v2/inAppPurchases/iap-2/pricePoints",
            requiredQuery: ["limit": "50"]
        ),
        LegacyCommercePaginationFixture(
            worker: .promotionalOffers,
            toolName: "promo_offers_list",
            arguments: ["subscription_id": .string("sub-1")],
            path: "/v1/subscriptions/sub-1/promotionalOffers",
            wrongParentPath: "/v1/subscriptions/sub-2/promotionalOffers",
            requiredQuery: ["limit": "25"]
        )
    ]
}

private func invokeLegacyCommerceFixture(
    _ fixture: LegacyCommercePaginationFixture,
    arguments: [String: Value],
    transport: TestHTTPTransport
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    let parameters = CallTool.Parameters(name: fixture.toolName, arguments: arguments)
    switch fixture.worker {
    case .iap:
        return try await InAppPurchasesWorker(
            httpClient: client,
            uploadService: UploadService()
        ).listIAPPricePoints(parameters)
    case .introductoryOffers:
        return try await IntroductoryOffersWorker(httpClient: client).handleTool(parameters)
    case .promotionalOffers:
        return try await PromotionalOffersWorker(httpClient: client).handleTool(parameters)
    case .offerCodes:
        return try await OfferCodesWorker(httpClient: client).handleTool(parameters)
    case .winBackOffers:
        return try await WinBackOffersWorker(httpClient: client).handleTool(parameters)
    }
}

private func legacyCommercePaginationURL(path: String, query: [String: String]) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.example.test"
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    guard let url = components.url else {
        preconditionFailure("Unable to construct pagination URL")
    }
    return url.absoluteString
}

private func legacyCommercePaginationQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(
        url: request.url!,
        resolvingAgainstBaseURL: false
    )?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
