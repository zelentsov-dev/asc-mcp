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

    @Test("IAP availability rejects missing or ambiguous selectors before the network")
    func availabilityRejectsInvalidSelectors() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)

        let missing = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_availability",
            arguments: ["include_territories": .bool(true)]
        ))
        let ambiguous = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_availability",
            arguments: [
                "iap_id": .string("iap-1"),
                "availability_id": .string("availability-1")
            ]
        ))

        #expect(missing.isError == true)
        #expect(ambiguous.isError == true)
        #expect(await transport.requestCount() == 0)
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

    @Test("IAP pricing summary exhausts manual and automatic pagination")
    func pricingSummaryExhaustsAllPages() async throws {
        let manualNext = try iapPricingContinuationURL(
            path: "/v1/inAppPurchasePriceSchedules/schedule-1/manualPrices",
            cursor: "manual-next"
        )
        let automaticNext = try iapPricingContinuationURL(
            path: "/v1/inAppPurchasePriceSchedules/schedule-1/automaticPrices",
            cursor: "automatic-next"
        )
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"inAppPurchasePriceSchedules","id":"schedule-1"}}"#),
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "inAppPurchasePrices",
                "id": "price-expired",
                "attributes": {"startDate": "2020-01-01", "endDate": "2020-12-31", "manual": true},
                "relationships": {
                  "territory": {"data": {"type": "territories", "id": "USA"}},
                  "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": "point-expired"}}
                }
              }],
              "links": {"next": "\(manualNext)"}
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "inAppPurchasePrices",
                "id": "price-current-page-two",
                "attributes": {"startDate": "2021-01-01", "manual": true},
                "relationships": {
                  "territory": {"data": {"type": "territories", "id": "USA"}},
                  "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": "point-current"}}
                }
              }],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
                {"type": "inAppPurchasePricePoints", "id": "point-current", "attributes": {"customerPrice": "4.99", "proceeds": "3.50"}}
              ],
              "links": {"next": null}
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "inAppPurchasePrices",
                "id": "price-future",
                "attributes": {"startDate": "2099-01-01", "manual": false},
                "relationships": {
                  "territory": {"data": {"type": "territories", "id": "USA"}},
                  "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": "point-future"}}
                }
              }],
              "links": {"next": "\(automaticNext)"}
            }
            """),
            .init(statusCode: 200, body: #"{"data":[],"links":{"next":null}}"#)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_pricing_summary",
            arguments: ["iap_id": .string("iap-1"), "territory_id": .string("USA")]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 5)
        let requests = await transport.recordedRequests()
        #expect(iapQueryItems(requests[2])["cursor"] == "manual-next")
        #expect(iapQueryItems(requests[4])["cursor"] == "automatic-next")
        let root = try iapObject(result.structuredContent)
        #expect(root["manual_pages_fetched"] == .int(2))
        #expect(root["automatic_pages_fetched"] == .int(2))
        #expect(root["complete"] == .bool(true))
        #expect(root["truncated"] == .bool(false))
        let current = try iapObject(root["current_price"])
        #expect(current["id"] == .string("price-current-page-two"))
        #expect(current["customer_price"] == .string("4.99"))
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

    @Test("IAP create and update preserve explicit null and reject update no-op")
    func iapWritesPreserveExplicitNull() async throws {
        let response = #"{"data":{"type":"inAppPurchases","id":"iap-1","attributes":{}}}"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: response),
            .init(statusCode: 200, body: response)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let created = try await worker.handleTool(CallTool.Parameters(
            name: "iap_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Coins"),
                "product_id": .string("coins"),
                "iap_type": .string("CONSUMABLE"),
                "review_note": .null,
                "family_sharable": .null
            ]
        ))
        let updated = try await worker.handleTool(CallTool.Parameters(
            name: "iap_update",
            arguments: [
                "iap_id": .string("iap-1"),
                "name": .null,
                "review_note": .null,
                "family_sharable": .null
            ]
        ))
        let noOp = try await worker.handleTool(CallTool.Parameters(
            name: "iap_update",
            arguments: ["iap_id": .string("iap-1")]
        ))

        #expect(created.isError != true)
        #expect(updated.isError != true)
        #expect(noOp.isError == true)
        #expect(await transport.requestCount() == 2)
        let bodies = await transport.recordedBodyStrings()
        let createAttributes = try iapRequestAttributes(bodies[0])
        #expect(createAttributes["reviewNote"] is NSNull)
        #expect(createAttributes["familySharable"] is NSNull)
        let updateAttributes = try iapRequestAttributes(bodies[1])
        #expect(Set(updateAttributes.keys) == ["name", "reviewNote", "familySharable"])
        #expect(updateAttributes.values.allSatisfy { $0 is NSNull })
    }

    @Test("IAP active updates require a value and preserve explicit null")
    func activeUpdatesPreserveExplicitNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"inAppPurchaseOfferCodes","id":"offer-1","attributes":{}}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"inAppPurchaseOfferCodeOneTimeUseCodes","id":"batch-1","attributes":{}}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"inAppPurchaseOfferCodeCustomCodes","id":"custom-1","attributes":{}}}"#)
        ])
        let worker = try await makeIAPWorker(transport: transport)
        let calls: [(String, String, String)] = [
            ("iap_update_offer_code", "offer_code_id", "offer-1"),
            ("iap_update_one_time_code", "one_time_code_id", "batch-1"),
            ("iap_update_custom_code", "custom_code_id", "custom-1")
        ]

        for (tool, idKey, id) in calls {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: tool,
                arguments: [idKey: .string(id), "active": .null]
            ))
            #expect(result.isError != true)
        }
        let missing = try await worker.handleTool(CallTool.Parameters(
            name: "iap_update_offer_code",
            arguments: ["offer_code_id": .string("offer-1")]
        ))

        #expect(missing.isError == true)
        #expect(await transport.requestCount() == 3)
        let bodies = await transport.recordedBodyStrings()
        for body in bodies {
            let attributes = try iapRequestAttributes(body)
            #expect(attributes["active"] is NSNull)
        }
    }

    @Test("IAP offer eligibility and one-time environment reject unsupported values")
    func offerEnumsRejectUnsupportedValues() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)

        let eligibility = try await worker.handleTool(CallTool.Parameters(
            name: "iap_create_offer_code",
            arguments: [
                "iap_id": .string("iap-1"),
                "name": .string("Launch"),
                "customer_eligibilities": .array([.string("NEW")]),
                "territory_ids": .array([.string("USA")]),
                "price_point_ids": .array([.string("point-1")])
            ]
        ))
        let environment = try await worker.handleTool(CallTool.Parameters(
            name: "iap_generate_one_time_codes",
            arguments: [
                "offer_code_id": .string("offer-1"),
                "number_of_codes": .int(1),
                "expiration_date": .string("2026-12-31"),
                "environment": .string("TEST")
            ]
        ))

        #expect(eligibility.isError == true)
        #expect(environment.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("IAP one-time code generation preserves explicit null environment")
    func oneTimeEnvironmentPreservesExplicitNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"inAppPurchaseOfferCodeOneTimeUseCodes","id":"batch-1","attributes":{}}}"#)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_generate_one_time_codes",
            arguments: [
                "offer_code_id": .string("offer-1"),
                "number_of_codes": .int(1),
                "expiration_date": .string("2026-12-31"),
                "environment": .null
            ]
        ))

        #expect(result.isError != true)
        let body = try #require(await transport.recordedBodyStrings().first)
        let attributes = try iapRequestAttributes(body)
        #expect(attributes["environment"] is NSNull)
    }

    @Test("one-time code values use the non-paginated CSV contract losslessly")
    func oneTimeCodeValuesUseRawCSVContract() async throws {
        let csv = "code,status\r\n\"A,1\",ACTIVE\r\nКОД-2,ACTIVE\r\n"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, headers: ["Content-Type": "text/csv"], body: csv)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_one_time_code_values",
            arguments: ["one_time_code_id": .string("batch:1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.percentEncodedPath == "/v1/inAppPurchaseOfferCodeOneTimeUseCodes/batch%3A1/values")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/csv")

        let root = try iapObject(result.structuredContent)
        #expect(root["one_time_code_id"] == .string("batch:1"))
        #expect(root["media_type"] == .string("text/csv"))
        #expect(root["values_csv"] == .string(csv))
        #expect(root["values_base64"] == .string(Data(csv.utf8).base64EncodedString()))
        #expect(root["byte_count"] == .int(Data(csv.utf8).count))
    }

    @Test("one-time code values schema exposes no unsupported pagination inputs")
    func oneTimeCodeValuesSchemaHasNoPagination() async throws {
        let worker = try await makeIAPWorker(transport: TestHTTPTransport(responses: []))
        let tool = try #require(await worker.getTools().first { $0.name == "iap_get_one_time_code_values" })
        let root = try iapObject(tool.inputSchema)
        let properties = try iapObject(root["properties"])

        #expect(Set(properties.keys) == Set(["one_time_code_id"]))
    }

    @Test("price schedule creates inline manual prices with Apple dates and relationships")
    func priceScheduleCreatesInlineManualPrices() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"inAppPurchasePriceSchedules","id":"schedule-1"}}"#)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_set_price_schedule",
            arguments: [
                "iap_id": .string("iap-1"),
                "base_territory_id": .string("USA"),
                "manual_prices": .array([
                    .object([
                        "price_point_id": .string("price-point-1"),
                        "start_date": .string("2026-08-01"),
                        "end_date": .string("2026-08-31")
                    ]),
                    .object(["price_point_id": .string("price-point-2")])
                ])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/inAppPurchasePriceSchedules")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(json["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let manualPrices = try #require(relationships["manualPrices"] as? [String: Any])
        let linkage = try #require(manualPrices["data"] as? [[String: Any]])
        #expect(linkage.compactMap { $0["id"] as? String } == ["${price-0}", "${price-1}"])

        let included = try #require(json["included"] as? [[String: Any]])
        #expect(included.count == 2)
        let firstAttributes = try #require(included[0]["attributes"] as? [String: Any])
        #expect(firstAttributes["startDate"] as? String == "2026-08-01")
        #expect(firstAttributes["endDate"] as? String == "2026-08-31")
        let firstRelationships = try #require(included[0]["relationships"] as? [String: Any])
        let pricePoint = try #require(firstRelationships["inAppPurchasePricePoint"] as? [String: Any])
        let pricePointData = try #require(pricePoint["data"] as? [String: Any])
        #expect(pricePointData["id"] as? String == "price-point-1")
        #expect(included[1]["attributes"] == nil)
    }

    @Test("price schedule preserves legacy existing-price linkage")
    func priceSchedulePreservesLegacyPriceIDs() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"inAppPurchasePriceSchedules","id":"schedule-legacy"}}"#)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_set_price_schedule",
            arguments: [
                "iap_id": .string("iap-1"),
                "base_territory_id": .string("USA"),
                "manual_price_ids": .string("existing-1, existing-2")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(json["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let manualPrices = try #require(relationships["manualPrices"] as? [String: Any])
        let linkage = try #require(manualPrices["data"] as? [[String: Any]])
        #expect(linkage.compactMap { $0["id"] as? String } == ["existing-1", "existing-2"])
        #expect(json["included"] == nil)
    }

    @Test("price schedule rejects ambiguous and invalid manual price forms before network")
    func priceScheduleValidatesManualPriceForms() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)

        let ambiguous = try await worker.handleTool(CallTool.Parameters(
            name: "iap_set_price_schedule",
            arguments: [
                "iap_id": .string("iap-1"),
                "base_territory_id": .string("USA"),
                "manual_price_ids": .string("existing-price"),
                "manual_prices": .array([.object(["price_point_id": .string("point-1")])])
            ]
        ))
        let invalidDate = try await worker.handleTool(CallTool.Parameters(
            name: "iap_set_price_schedule",
            arguments: [
                "iap_id": .string("iap-1"),
                "base_territory_id": .string("USA"),
                "manual_prices": .array([.object([
                    "price_point_id": .string("point-1"),
                    "start_date": .string("2026-02-30")
                ])])
            ]
        ))

        #expect(ambiguous.isError == true)
        #expect(iapText(ambiguous).contains("mutually exclusive"))
        #expect(invalidDate.isError == true)
        #expect(iapText(invalidDate).contains("YYYY-MM-DD"))
        #expect(await transport.requestCount() == 0)
    }

    @Test("IAP schemas publish only Apple 4.4.1 purchase types")
    func iapSchemasPublishOnlyCurrentTypes() async throws {
        let worker = try await makeIAPWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()
        let expected: Set<String> = ["CONSUMABLE", "NON_CONSUMABLE", "NON_RENEWING_SUBSCRIPTION"]

        for (toolName, field) in [("iap_create", "iap_type"), ("iap_list", "filter_type")] {
            let tool = try #require(tools.first { $0.name == toolName })
            let root = try iapObject(tool.inputSchema)
            let properties = try iapObject(root["properties"])
            let fieldSchema = try iapObject(properties[field])
            let enumSets = try iapPublishedEnumSets(fieldSchema)
            #expect(!enumSets.isEmpty)
            for values in enumSets {
                #expect(values == expected)
            }
        }
    }

    @Test("IAP schemas expose nullable writes and bounded offer enums")
    func schemasExposeNullableWritesAndOfferEnums() async throws {
        let worker = try await makeIAPWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        for toolName in ["iap_create", "iap_update"] {
            let tool = try #require(tools.first { $0.name == toolName })
            let properties = try iapObject(try iapObject(tool.inputSchema)["properties"])
            #expect(Set(try iapArray(try iapObject(properties["review_note"])["type"]).compactMap(\.stringValue)) == ["string", "null"])
            #expect(Set(try iapArray(try iapObject(properties["family_sharable"])["type"]).compactMap(\.stringValue)) == ["boolean", "null"])
        }

        let offer = try #require(tools.first { $0.name == "iap_create_offer_code" })
        let offerProperties = try iapObject(try iapObject(offer.inputSchema)["properties"])
        let eligibilities = try iapObject(offerProperties["customer_eligibilities"])
        let eligibilityItems = try iapObject(eligibilities["items"])
        #expect(eligibilities["minItems"] == .int(1))
        #expect(eligibilities["uniqueItems"] == .bool(true))
        #expect(Set(try iapArray(eligibilityItems["enum"]).compactMap(\.stringValue)) == ["NON_SPENDER", "ACTIVE_SPENDER", "CHURNED_SPENDER"])

        let generate = try #require(tools.first { $0.name == "iap_generate_one_time_codes" })
        let generateProperties = try iapObject(try iapObject(generate.inputSchema)["properties"])
        let environment = try iapObject(generateProperties["environment"])
        #expect(Set(try iapArray(environment["type"]).compactMap(\.stringValue)) == ["string", "null"])
        let environmentValues = try iapArray(environment["enum"])
        #expect(Set(environmentValues.compactMap(\.stringValue)) == ["PRODUCTION", "SANDBOX"])
        #expect(environmentValues.contains(.null))

        for toolName in ["iap_update_offer_code", "iap_update_one_time_code", "iap_update_custom_code"] {
            let tool = try #require(tools.first { $0.name == toolName })
            let root = try iapObject(tool.inputSchema)
            let properties = try iapObject(root["properties"])
            #expect(Set(try iapArray(root["required"]).compactMap(\.stringValue)).contains("active"))
            #expect(Set(try iapArray(try iapObject(properties["active"])["type"]).compactMap(\.stringValue)) == ["boolean", "null"])
        }
    }

    @Test("IAP price and availability schemas expose the bounded Apple forms")
    func reliabilitySchemasExposeInlinePricesAndTerritoryProjection() async throws {
        let worker = try await makeIAPWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        let priceTool = try #require(tools.first { $0.name == "iap_set_price_schedule" })
        let priceRoot = try iapObject(priceTool.inputSchema)
        let priceProperties = try iapObject(priceRoot["properties"])
        let manualPrices = try iapObject(priceProperties["manual_prices"])
        let item = try iapObject(manualPrices["items"])
        let itemRequired = Set(try iapArray(item["required"]).compactMap(\.stringValue))
        #expect(itemRequired == ["price_point_id"])
        #expect(try iapArray(priceRoot["allOf"]).count == 1)
        #expect(priceRoot["additionalProperties"] == .bool(false))
        #expect(priceRoot["maxProperties"] == .int(3))
        let publishedPriceRoot = try iapObject(ToolMetadataPolicy.apply(to: priceTool).inputSchema)
        #expect(publishedPriceRoot["allOf"] == nil)
        #expect(publishedPriceRoot["maxProperties"] == .int(3))
        #expect(publishedPriceRoot["additionalProperties"] == .bool(false))

        let availabilityTool = try #require(tools.first { $0.name == "iap_get_availability" })
        let availabilityRoot = try iapObject(availabilityTool.inputSchema)
        let availabilityProperties = try iapObject(availabilityRoot["properties"])
        let territoryLimit = try iapObject(availabilityProperties["territory_limit"])
        #expect(territoryLimit["maximum"] == .int(50))
        #expect(try iapArray(availabilityRoot["oneOf"]).count == 2)
    }

    @Test("unsupported IAP type is rejected before network")
    func unsupportedIAPTypeIsRejectedBeforeNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Legacy subscription"),
                "product_id": .string("com.example.legacy"),
                "iap_type": .string("AUTO_RENEWABLE")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("subscription group and inventory preserve Apple included resources")
    func includedResourcesArePreserved() async throws {
        let inventoryNextURL =
            "https://api.example.test/v1/apps/app-1/inAppPurchasesV2?cursor=next" +
            "&include=inAppPurchaseLocalizations%2CiapPriceSchedule%2CinAppPurchaseAvailability%2CpromotedPurchase%2CofferCodes" +
            "&fields%5BinAppPurchases%5D=name%2CproductId%2CinAppPurchaseType%2Cstate%2CreviewNote%2CfamilySharable%2CcontentHosting%2CinAppPurchaseLocalizations%2CpromotedPurchase%2CiapPriceSchedule%2CinAppPurchaseAvailability%2CofferCodes" +
            "&fields%5BinAppPurchaseLocalizations%5D=name%2Clocale%2Cdescription%2Cstate" +
            "&fields%5BinAppPurchasePriceSchedules%5D=baseTerritory%2CmanualPrices%2CautomaticPrices" +
            "&fields%5BinAppPurchaseAvailabilities%5D=availableInNewTerritories%2CavailableTerritories" +
            "&fields%5BpromotedPurchases%5D=visibleForAllUsers%2Cenabled%2Cstate" +
            "&limit=25"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data":{"type":"subscriptionGroups","id":"group-1","attributes":{"referenceName":"Premium"}},
              "included":[{"type":"subscriptions","id":"sub-1","attributes":{"name":"Monthly","productId":"monthly"}}]
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data":[{"type":"inAppPurchases","id":"iap-1","attributes":{"name":"Coins"}}],
              "included":[{"type":"inAppPurchaseLocalizations","id":"loc-1","attributes":{"locale":"en-US","name":"Coins"}}],
              "links":{"next":"\(inventoryNextURL)"}
            }
            """)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let groupResult = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_subscription_group",
            arguments: ["group_id": .string("group-1"), "include_subscriptions": .bool(true)]
        ))
        let inventoryResult = try await worker.handleTool(CallTool.Parameters(
            name: "iap_inventory",
            arguments: ["app_id": .string("app-1")]
        ))

        #expect(groupResult.isError != true)
        #expect(inventoryResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(iapQueryItems(requests[0])["include"] == "subscriptions")
        #expect(iapQueryItems(requests[1])["include"]?.contains("inAppPurchaseLocalizations") == true)

        let groupRoot = try iapObject(groupResult.structuredContent)
        let subscription = try iapObject(try iapArray(groupRoot["subscriptions"]).first)
        #expect(subscription["id"] == .string("sub-1"))
        #expect(try iapArray(groupRoot["included"]).count == 1)

        let inventoryRoot = try iapObject(inventoryResult.structuredContent)
        let localization = try iapObject(try iapArray(inventoryRoot["included"]).first)
        #expect(localization["id"] == .string("loc-1"))
        #expect(inventoryRoot["included_count"] == .int(1))
        #expect(inventoryRoot["next_url"] == .string(inventoryNextURL))
    }

    @Test("inventory continuation cannot drop the included projection")
    func inventoryContinuationPreservesProjection() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_inventory",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://api.example.test/v1/apps/app-1/inAppPurchasesV2?cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("availability labels a truncated territory projection and points to paginated listing")
    func availabilityProjectionIsHonestAboutTruncation() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data":{
                "type":"inAppPurchaseAvailabilities",
                "id":"availability-1",
                "attributes":{"availableInNewTerritories":false},
                "relationships":{"availableTerritories":{
                  "meta":{"paging":{"total":2,"limit":1,"nextCursor":"next"}},
                  "data":[{"type":"territories","id":"USA"}]
                }}
              },
              "included":[{"type":"territories","id":"USA","attributes":{"currency":"USD"}}]
            }
            """)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_availability",
            arguments: [
                "availability_id": .string("availability-1"),
                "include_territories": .bool(true),
                "territory_limit": .int(1)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = iapQueryItems(request)
        #expect(query["include"] == "availableTerritories")
        #expect(query["limit[availableTerritories]"] == "1")

        let root = try iapObject(result.structuredContent)
        let availability = try iapObject(root["availability"])
        #expect(try iapArray(availability["available_territories"]).count == 1)
        let projection = try iapObject(availability["territory_projection"])
        #expect(projection["returned"] == .int(1))
        #expect(projection["total"] == .int(2))
        #expect(projection["limit"] == .int(1))
        #expect(projection["has_more"] == .bool(true))
        #expect(projection["complete"] == .bool(false))
        #expect(projection["continuation_tool"] == .string("iap_list_available_territories"))
    }

    @Test("availability omission and territory listing have explicit projection semantics")
    func availabilityOmissionAndTerritoryPaginationAreExplicit() async throws {
        let nextURL = "https://api.example.test/v1/inAppPurchaseAvailabilities/availability-1/availableTerritories?cursor=next&fields%5Bterritories%5D=currency&limit=200"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {"data":{"type":"inAppPurchaseAvailabilities","id":"availability-1","attributes":{"availableInNewTerritories":true}}}
            """),
            .init(statusCode: 200, body: """
            {"data":[{"type":"territories","id":"USA","attributes":{"currency":"USD"}}],"links":{"next":"\(nextURL)"}}
            """)
        ])
        let worker = try await makeIAPWorker(transport: transport)

        let availabilityResult = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_availability",
            arguments: ["availability_id": .string("availability-1"), "include_territories": .bool(false)]
        ))
        let listResult = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_available_territories",
            arguments: ["availability_id": .string("availability-1"), "limit": .int(200)]
        ))

        let requests = await transport.recordedRequests()
        #expect(iapQueryItems(requests[0])["include"] == nil)
        #expect(iapQueryItems(requests[0])["limit[availableTerritories]"] == nil)
        #expect(iapQueryItems(requests[1])["limit"] == "200")

        let availabilityRoot = try iapObject(availabilityResult.structuredContent)
        let availability = try iapObject(availabilityRoot["availability"])
        #expect(availability["available_territories"] == nil)
        let projection = try iapObject(availability["territory_projection"])
        #expect(projection["requested"] == .bool(false))

        let listRoot = try iapObject(listResult.structuredContent)
        #expect(listRoot["page_is_last"] == .bool(false))
        #expect(listRoot["next_url"] == .string(nextURL))
    }

    @Test("IAP mutation failures retain commit-state semantics")
    func mutationFailuresRetainCommitState() async throws {
        let unknownTransport = TestHTTPTransport(responses: [])
        let unknownWorker = try await makeIAPWorker(transport: unknownTransport)
        let unknown = try await unknownWorker.handleTool(.init(
            name: "iap_update",
            arguments: ["iap_id": .string("iap-1"), "name": .string("Updated")]
        ))

        #expect(unknown.isError == true)
        let unknownRoot = try iapObject(unknown.structuredContent)
        #expect(unknownRoot["operationCommitState"] == .string("unknown"))
        #expect(unknownRoot["outcomeUnknown"] == .bool(true))
        #expect(unknownRoot["retrySafe"] == .bool(false))

        let unverifiedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "not-json")
        ])
        let unverifiedWorker = try await makeIAPWorker(transport: unverifiedTransport)
        let unverified = try await unverifiedWorker.handleTool(.init(
            name: "iap_update_offer_code",
            arguments: ["offer_code_id": .string("offer-1"), "active": .bool(false)]
        ))

        #expect(unverified.isError == true)
        let unverifiedRoot = try iapObject(unverified.structuredContent)
        #expect(unverifiedRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(unverifiedRoot["operationCommitted"] == .bool(true))
        #expect(unverifiedRoot["retrySafe"] == .bool(false))
    }

    @Test("IAP limits reject present invalid values before network")
    func limitsRejectInvalidValuesBeforeNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPWorker(transport: transport)
        let cases: [(String, [String: Value])] = [
            ("iap_list", ["app_id": .string("app-1"), "limit": .int(0)]),
            ("iap_list_price_points", ["iap_id": .string("iap-1"), "limit": .int(8001)]),
            ("iap_list_offer_codes", ["iap_id": .string("iap-1"), "limit": .int(201)]),
            ("iap_list_images", ["iap_id": .string("iap-1"), "limit": .string("25")])
        ]

        for (name, arguments) in cases {
            let result = try await worker.handleTool(.init(name: name, arguments: arguments))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("IAP limit schemas publish the runtime bounds")
    func limitSchemasPublishRuntimeBounds() async throws {
        let worker = try await makeIAPWorker(transport: TestHTTPTransport(responses: []))
        let largeLimitTools: Set<String> = ["iap_list_price_points", "iap_list_price_point_equalizations"]

        for tool in await worker.getTools() {
            let root = try iapObject(tool.inputSchema)
            let properties = try iapObject(root["properties"])
            guard let limitValue = properties["limit"] else { continue }
            let limit = try iapObject(limitValue)
            #expect(limit["minimum"] == .int(1))
            #expect(limit["maximum"] == .int(largeLimitTools.contains(tool.name) ? 8000 : 200))
        }
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

private func iapPricingContinuationURL(path: String, cursor: String) throws -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.example.test"
    components.path = path
    components.queryItems = [
        .init(name: "filter[territory]", value: "USA"),
        .init(name: "include", value: "inAppPurchasePricePoint,territory"),
        .init(name: "fields[inAppPurchasePrices]", value: "startDate,endDate,manual,inAppPurchasePricePoint,territory"),
        .init(name: "fields[inAppPurchasePricePoints]", value: "customerPrice,proceeds,territory,equalizations"),
        .init(name: "fields[territories]", value: "currency"),
        .init(name: "limit", value: "200"),
        .init(name: "cursor", value: cursor)
    ]
    return try #require(components.url?.absoluteString)
}

private func iapRequestAttributes(_ body: String) throws -> [String: Any] {
    let root = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
    let data = try #require(root["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
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

private func iapPublishedEnumSets(_ schema: [String: Value]) throws -> [Set<String>] {
    if let directEnum = schema["enum"] {
        return [Set(try iapArray(directEnum).compactMap(\.stringValue))]
    }

    return try iapArray(schema["oneOf"]).map { variantValue in
        let variant = try iapObject(variantValue)
        if let variantEnum = variant["enum"] {
            return Set(try iapArray(variantEnum).compactMap(\.stringValue))
        }
        let items = try iapObject(variant["items"])
        return Set(try iapArray(items["enum"]).compactMap(\.stringValue))
    }
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
