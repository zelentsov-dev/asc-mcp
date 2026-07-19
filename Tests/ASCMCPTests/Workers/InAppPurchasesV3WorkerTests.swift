import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("In-App Purchases v3 Worker Tests")
struct InAppPurchasesV3WorkerTests {
    @Test("IAP price points support territory_id, territory include, and 8000 limit")
    func pricePointsSupportTerritoryIdAndLargeLimit() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "inAppPurchasePricePoints",
                  "id": "iap-pp-1",
                  "attributes": {"customerPrice": "4.99", "proceeds": "3.50"},
                  "relationships": {"territory": {"data": {"type": "territories", "id": "USA"}}}
                }
              ],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}}
              ]
            }
            """)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_price_points",
            arguments: [
                "iap_id": .string("iap-1"),
                "territory_id": .string("USA"),
                "limit": .int(8000)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = iapQueryItems(request)
        #expect(request.url?.path == "/v2/inAppPurchases/iap-1/pricePoints")
        #expect(query["filter[territory]"] == "USA")
        #expect(query["include"] == "territory")
        #expect(query["fields[territories]"] == "currency")
        #expect(query["limit"] == "8000")

        let root = try iapObject(result.structuredContent)
        let point = try iapObject(try iapArray(root["price_points"]).first)
        #expect(point["territory_id"] == .string("USA"))
        #expect(point["currency"] == .string("USD"))
        #expect(point["price_point_id"] == .string("iap-pp-1"))
        #expect(point["customer_price"] == .string("4.99"))
    }

    @Test("IAP price point pagination rejects another parent before network")
    func pricePointPaginationRejectsAnotherParent() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_price_points",
            arguments: [
                "iap_id": .string("iap-1"),
                "next_url": .string("https://api.example.test/v2/inAppPurchases/iap-2/pricePoints?cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("IAP price point pagination preserves the requested territory filter")
    func pricePointPaginationPreservesTerritoryFilter() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_price_points",
            arguments: [
                "iap_id": .string("iap-1"),
                "territory_id": .string("USA"),
                "next_url": .string("https://api.example.test/v2/inAppPurchases/iap-1/pricePoints?filter%5Bterritory%5D=GBR&cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("IAP availability can be read directly from an IAP id")
    func availabilityCanBeReadFromIAPID() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "inAppPurchaseAvailabilities",
                "id": "iap-avail-1",
                "attributes": {"availableInNewTerritories": false},
                "relationships": {"availableTerritories": {"data": [{"type": "territories", "id": "USA"}]}}
              },
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}}
              ]
            }
            """)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_availability",
            arguments: ["iap_id": .string("iap-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = iapQueryItems(request)
        #expect(request.url?.path == "/v2/inAppPurchases/iap-1/inAppPurchaseAvailability")
        #expect(query["include"] == "availableTerritories")

        let root = try iapObject(result.structuredContent)
        let availability = try iapObject(root["availability"])
        let territory = try iapObject(try iapArray(availability["available_territories"]).first)
        #expect(availability["available_in_new_territories"] == .bool(false))
        #expect(territory["id"] == .string("USA"))
        #expect(territory["currency"] == .string("USD"))
    }

    @Test("IAP pricing summary reads schedule prices by territory")
    func pricingSummaryReadsSchedulePricesByTerritory() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"inAppPurchasePriceSchedules","id":"schedule-1"}}"#),
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "inAppPurchasePrices",
                  "id": "price-current",
                  "attributes": {"startDate": "2026-01-01", "manual": true},
                  "relationships": {
                    "territory": {"data": {"type": "territories", "id": "USA"}},
                    "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": "iap-pp-current"}}
                  }
                }
              ],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
                {"type": "inAppPurchasePricePoints", "id": "iap-pp-current", "attributes": {"customerPrice": "4.99", "proceeds": "3.50"}}
              ]
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "inAppPurchasePrices",
                  "id": "price-future",
                  "attributes": {"startDate": "2026-12-01", "manual": false},
                  "relationships": {
                    "territory": {"data": {"type": "territories", "id": "USA"}},
                    "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": "iap-pp-future"}}
                  }
                }
              ],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
                {"type": "inAppPurchasePricePoints", "id": "iap-pp-future", "attributes": {"customerPrice": "5.99", "proceeds": "4.20"}}
              ]
            }
            """)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_pricing_summary",
            arguments: ["iap_id": .string("iap-1"), "territory_id": .string("USA")]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.url?.path } == [
            "/v2/inAppPurchases/iap-1/iapPriceSchedule",
            "/v1/inAppPurchasePriceSchedules/schedule-1/manualPrices",
            "/v1/inAppPurchasePriceSchedules/schedule-1/automaticPrices"
        ])
        #expect(iapQueryItems(requests[1])["filter[territory]"] == "USA")
        #expect(iapQueryItems(requests[1])["include"] == "inAppPurchasePricePoint,territory")

        let root = try iapObject(result.structuredContent)
        let current = try iapObject(root["current_price"])
        let future = try iapObject(try iapArray(root["scheduled_prices"]).first)
        #expect(current["price_point_id"] == .string("iap-pp-current"))
        #expect(current["customer_price"] == .string("4.99"))
        #expect(future["price_point_id"] == .string("iap-pp-future"))
    }

    @Test("IAP offer code prices support territory filter and normalized price fields")
    func offerCodePricesSupportTerritoryFilter() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "inAppPurchaseOfferPrices",
                  "id": "offer-price-1",
                  "relationships": {
                    "territory": {"data": {"type": "territories", "id": "USA"}},
                    "pricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": "iap-pp-1"}}
                  }
                }
              ],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
                {"type": "inAppPurchasePricePoints", "id": "iap-pp-1", "attributes": {"customerPrice": "1.99", "proceeds": "1.40"}}
              ]
            }
            """)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_offer_code_prices",
            arguments: ["offer_code_id": .string("iap-offer-1"), "territory_id": .string("USA")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = iapQueryItems(request)
        #expect(request.url?.path == "/v1/inAppPurchaseOfferCodes/iap-offer-1/prices")
        #expect(query["filter[territory]"] == "USA")
        #expect(query["include"] == "territory,pricePoint")

        let root = try iapObject(result.structuredContent)
        let price = try iapObject(try iapArray(root["prices"]).first)
        #expect(price["territory_id"] == .string("USA"))
        #expect(price["currency"] == .string("USD"))
        #expect(price["price_point_id"] == .string("iap-pp-1"))
        #expect(price["customer_price"] == .string("1.99"))
    }

    @Test("IAP offer code creation rejects mismatched price point and territory arrays before network")
    func createOfferCodeRejectsMismatchedPrices() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_create_offer_code",
            arguments: [
                "iap_id": .string("iap-1"),
                "name": .string("Launch"),
                "customer_eligibilities": .array([.string("NON_SPENDER")]),
                "territory_ids": .array([.string("USA"), .string("GBR")]),
                "price_point_ids": .array([.string("iap-pp-usa")])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(iapText(result).contains("same count"))
    }
}

private func makeIAPWorker(transport: TestHTTPTransport) async throws -> InAppPurchasesWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return InAppPurchasesWorker(httpClient: client, uploadService: UploadService())
}

private func iapQueryItems(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func iapObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw InAppPurchasesV3TestFailure.expectedObject
    }
    return object
}

private func iapArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw InAppPurchasesV3TestFailure.expectedArray
    }
    return array
}

private func iapText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private enum InAppPurchasesV3TestFailure: Error {
    case expectedObject
    case expectedArray
}
