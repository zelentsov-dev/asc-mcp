import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Commerce Pagination Hardening Tests")
struct CommercePaginationHardeningTests {
    @Test("legacy commerce lists accept complete Apple continuation URLs")
    func acceptsCompleteContinuations() async throws {
        for fixture in commercePaginationFixtures() {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: #"{"data":[]}"#)
            ])
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query["cursor"] = "next"
            arguments["next_url"] = .string(commercePaginationURL(path: fixture.path, query: query))

            let result = try await invokeCommercePaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError != true, "Expected valid continuation for \(fixture.toolName)")
            let request = try #require(await transport.recordedRequests().first)
            #expect(request.url?.path == fixture.path)
            let actualQuery = commercePaginationQuery(request)
            for (name, value) in query {
                #expect(actualQuery[name] == value, "Expected \(name) for \(fixture.toolName)")
            }
        }
    }

    @Test("legacy commerce lists reject missing and empty cursors before network access")
    func rejectsMissingOrEmptyCursors() async throws {
        for fixture in commercePaginationFixtures() {
            for cursor in [String?.none, String?.some("")] {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var query = fixture.requiredQuery
                if let cursor {
                    query["cursor"] = cursor
                }
                arguments["next_url"] = .string(commercePaginationURL(path: fixture.path, query: query))

                let result = try await invokeCommercePaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected cursor validation for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("legacy commerce lists reject missing fixed controls before network access")
    func rejectsMissingFixedControls() async throws {
        for fixture in commercePaginationFixtures() {
            let transport = TestHTTPTransport(responses: [])
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query.removeValue(forKey: fixture.missingKey)
            query["cursor"] = "next"
            arguments["next_url"] = .string(commercePaginationURL(path: fixture.path, query: query))

            let result = try await invokeCommercePaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError == true, "Expected missing \(fixture.missingKey) to fail for \(fixture.toolName)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("legacy commerce lists reject changed projection, limits, and filters before network access")
    func rejectsChangedQueryInvariants() async throws {
        for fixture in commercePaginationFixtures() {
            let transport = TestHTTPTransport(responses: [])
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query[fixture.changedKey] = "drift"
            query["cursor"] = "next"
            arguments["next_url"] = .string(commercePaginationURL(path: fixture.path, query: query))

            let result = try await invokeCommercePaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError == true, "Expected changed \(fixture.changedKey) to fail for \(fixture.toolName)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("legacy commerce lists reject another concrete parent before network access")
    func rejectsAnotherParent() async throws {
        for fixture in commercePaginationFixtures() {
            let transport = TestHTTPTransport(responses: [])
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query["cursor"] = "next"
            arguments["next_url"] = .string(commercePaginationURL(path: fixture.wrongParentPath, query: query))

            let result = try await invokeCommercePaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError == true, "Expected parent drift to fail for \(fixture.toolName)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("legacy commerce lists reject duplicate continuation query controls")
    func rejectsDuplicateQueryControls() async throws {
        for fixture in commercePaginationFixtures() {
            let transport = TestHTTPTransport(responses: [])
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query["cursor"] = "next"
            let nextURL = commercePaginationURL(path: fixture.path, query: query) + "&limit=1"
            arguments["next_url"] = .string(nextURL)

            let result = try await invokeCommercePaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError == true, "Expected duplicate limit to fail for \(fixture.toolName)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("legacy commerce lists reject unrequested continuation filters")
    func rejectsUnrequestedFilters() async throws {
        for fixture in commercePaginationFixtures() {
            let transport = TestHTTPTransport(responses: [])
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query["filter[unexpected]"] = "drift"
            query["cursor"] = "next"
            arguments["next_url"] = .string(commercePaginationURL(path: fixture.path, query: query))

            let result = try await invokeCommercePaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError == true, "Expected an unrequested filter to fail for \(fixture.toolName)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("commerce manifests record full continuation invariants")
    func manifestsRecordContinuationInvariants() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let reason = "The handler fixes this query control and requires the same value on every continuation; it is not exposed as a direct public input."
        let localRole = "Validated Apple pagination URL bound to the concrete parent path and full originating query projection."

        for fixture in commercePaginationFixtures() {
            let mapping = try #require(manifest.mapping(for: fixture.toolName))
            #expect(mapping.operations.map(\.operationID) == [fixture.operationID])
            let operation = try #require(mapping.operations.first)
            let internalControls = (operation.optionalParameterClassifications ?? []).filter {
                $0.disposition == .internalControl
            }
            #expect(!internalControls.isEmpty)
            #expect(internalControls.allSatisfy { $0.reason == reason && $0.reviewAtSpec == "4.4.1" })
            let continuation = try #require(mapping.fields.first { $0.toolField == "next_url" })
            #expect(continuation.sourceKind == .local)
            #expect(continuation.localRole == localRole)
        }
    }
}

private enum CommercePaginationWorkerKind {
    case iap
    case subscriptions
}

private struct CommercePaginationFixture {
    let worker: CommercePaginationWorkerKind
    let toolName: String
    let operationID: String
    let arguments: [String: Value]
    let path: String
    let wrongParentPath: String
    let requiredQuery: [String: String]
    let missingKey: String
    let changedKey: String
}

private func commercePaginationFixtures() -> [CommercePaginationFixture] {
    [
        CommercePaginationFixture(
            worker: .iap,
            toolName: "iap_list_price_points",
            operationID: "inAppPurchasesV2_pricePoints_getToManyRelated",
            arguments: [
                "iap_id": .string("iap-1"),
                "territory_id": .string("USA"),
                "limit": .int(8000)
            ],
            path: "/v2/inAppPurchases/iap-1/pricePoints",
            wrongParentPath: "/v2/inAppPurchases/iap-2/pricePoints",
            requiredQuery: iapPricePointContinuationQuery(limit: "8000", iapID: nil),
            missingKey: "include",
            changedKey: "limit"
        ),
        CommercePaginationFixture(
            worker: .iap,
            toolName: "iap_list_price_point_equalizations",
            operationID: "inAppPurchasePricePoints_equalizations_getToManyRelated",
            arguments: [
                "price_point_id": .string("iap-pp-1"),
                "iap_id": .string("iap-1"),
                "territory_id": .string("USA"),
                "limit": .int(8000)
            ],
            path: "/v1/inAppPurchasePricePoints/iap-pp-1/equalizations",
            wrongParentPath: "/v1/inAppPurchasePricePoints/iap-pp-2/equalizations",
            requiredQuery: iapPricePointContinuationQuery(limit: "8000", iapID: "iap-1"),
            missingKey: "fields[territories]",
            changedKey: "filter[inAppPurchaseV2]"
        ),
        CommercePaginationFixture(
            worker: .iap,
            toolName: "iap_list_offer_codes",
            operationID: "inAppPurchasesV2_offerCodes_getToManyRelated",
            arguments: ["iap_id": .string("iap-1"), "limit": .int(200)],
            path: "/v2/inAppPurchases/iap-1/offerCodes",
            wrongParentPath: "/v2/inAppPurchases/iap-2/offerCodes",
            requiredQuery: [
                "include": "oneTimeUseCodes,customCodes,prices",
                "fields[inAppPurchaseOfferCodes]": "name,customerEligibilities,productionCodeCount,sandboxCodeCount,active,oneTimeUseCodes,customCodes,prices",
                "limit[oneTimeUseCodes]": "50",
                "limit[customCodes]": "50",
                "limit[prices]": "50",
                "limit": "200"
            ],
            missingKey: "limit[customCodes]",
            changedKey: "include"
        ),
        CommercePaginationFixture(
            worker: .iap,
            toolName: "iap_list_offer_code_prices",
            operationID: "inAppPurchaseOfferCodes_prices_getToManyRelated",
            arguments: [
                "offer_code_id": .string("iap-offer-1"),
                "territory_id": .string("USA"),
                "limit": .int(200)
            ],
            path: "/v1/inAppPurchaseOfferCodes/iap-offer-1/prices",
            wrongParentPath: "/v1/inAppPurchaseOfferCodes/iap-offer-2/prices",
            requiredQuery: [
                "include": "territory,pricePoint",
                "fields[inAppPurchaseOfferPrices]": "territory,pricePoint",
                "fields[inAppPurchasePricePoints]": "customerPrice,proceeds,territory,equalizations",
                "fields[territories]": "currency",
                "filter[territory]": "USA",
                "limit": "200"
            ],
            missingKey: "fields[inAppPurchaseOfferPrices]",
            changedKey: "filter[territory]"
        ),
        CommercePaginationFixture(
            worker: .subscriptions,
            toolName: "subscriptions_list_prices",
            operationID: "subscriptions_prices_getToManyRelated",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "price_point_id": .string("sub-pp-1"),
                "limit": .int(200)
            ],
            path: "/v1/subscriptions/sub-1/prices",
            wrongParentPath: "/v1/subscriptions/sub-2/prices",
            requiredQuery: [
                "include": "territory,subscriptionPricePoint",
                "fields[subscriptionPrices]": "startDate,preserved,planType,territory,subscriptionPricePoint",
                "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations",
                "fields[territories]": "currency",
                "filter[territory]": "USA",
                "filter[subscriptionPricePoint]": "sub-pp-1",
                "limit": "200"
            ],
            missingKey: "fields[subscriptionPrices]",
            changedKey: "filter[subscriptionPricePoint]"
        ),
        CommercePaginationFixture(
            worker: .subscriptions,
            toolName: "subscriptions_list_price_points",
            operationID: "subscriptions_pricePoints_getToManyRelated",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "limit": .int(8000)
            ],
            path: "/v1/subscriptions/sub-1/pricePoints",
            wrongParentPath: "/v1/subscriptions/sub-2/pricePoints",
            requiredQuery: subscriptionPricePointContinuationQuery(limit: "8000", subscriptionID: nil),
            missingKey: "include",
            changedKey: "fields[subscriptionPricePoints]"
        ),
        CommercePaginationFixture(
            worker: .subscriptions,
            toolName: "subscriptions_list_price_point_equalizations",
            operationID: "subscriptionPricePoints_equalizations_getToManyRelated",
            arguments: [
                "price_point_id": .string("sub-pp-1"),
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "limit": .int(8000)
            ],
            path: "/v1/subscriptionPricePoints/sub-pp-1/equalizations",
            wrongParentPath: "/v1/subscriptionPricePoints/sub-pp-2/equalizations",
            requiredQuery: subscriptionPricePointContinuationQuery(limit: "8000", subscriptionID: "sub-1"),
            missingKey: "limit",
            changedKey: "filter[subscription]"
        )
    ]
}

private func iapPricePointContinuationQuery(limit: String, iapID: String?) -> [String: String] {
    var query = [
        "include": "territory",
        "fields[inAppPurchasePricePoints]": "customerPrice,proceeds,territory,equalizations",
        "fields[territories]": "currency",
        "filter[territory]": "USA",
        "limit": limit
    ]
    if let iapID {
        query["filter[inAppPurchaseV2]"] = iapID
    }
    return query
}

private func subscriptionPricePointContinuationQuery(limit: String, subscriptionID: String?) -> [String: String] {
    var query = [
        "include": "territory",
        "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations",
        "fields[territories]": "currency",
        "filter[territory]": "USA",
        "limit": limit
    ]
    if let subscriptionID {
        query["filter[subscription]"] = subscriptionID
    }
    return query
}

private func invokeCommercePaginationFixture(
    _ fixture: CommercePaginationFixture,
    arguments: [String: Value],
    transport: TestHTTPTransport
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    switch fixture.worker {
    case .iap:
        return try await InAppPurchasesWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(.init(name: fixture.toolName, arguments: arguments))
    case .subscriptions:
        return try await SubscriptionsWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(.init(name: fixture.toolName, arguments: arguments))
    }
}

private func commercePaginationURL(path: String, query: [String: String]) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.example.test"
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    guard let url = components.url else {
        preconditionFailure("Unable to construct pagination test URL")
    }
    return url.absoluteString
}

private func commercePaginationQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
