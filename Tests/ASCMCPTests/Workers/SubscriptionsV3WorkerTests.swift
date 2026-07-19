import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Subscriptions v3 Worker Tests")
struct SubscriptionsV3WorkerTests {
    @Test("old offer worker prefixes are not public in v3")
    func oldOfferWorkerPrefixesAreNotPublic() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["subscriptions"])

        let oldOffer = try await manager.routeTool(CallTool.Parameters(
            name: "offer_codes_list",
            arguments: ["subscription_id": .string("sub-1")]
        ))
        let oldIntro = try await manager.routeTool(CallTool.Parameters(
            name: "intro_offers_list",
            arguments: ["subscription_id": .string("sub-1")]
        ))
        let newOffer = try await manager.routeTool(CallTool.Parameters(
            name: "subscriptions_list_offer_codes",
            arguments: nil
        ))

        #expect(oldOffer.isError == true)
        #expect(oldIntro.isError == true)
        #expect(newOffer.isError == true)
        #expect(text(oldOffer).contains("Unknown tool"))
        #expect(text(oldIntro).contains("Unknown tool"))
        #expect(text(newOffer).contains("subscription_id"))
    }

    @Test("list subscription prices filters by territory and returns price point and currency")
    func listPricesFiltersByTerritoryAndReturnsCurrency() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "subscriptionPrices",
                  "id": "price-1",
                  "attributes": {"startDate": "2026-05-01", "preserved": false},
                  "relationships": {
                    "territory": {"data": {"type": "territories", "id": "USA"}},
                    "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": "pp-usa-999"}}
                  }
                }
              ],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
                {"type": "subscriptionPricePoints", "id": "pp-usa-999", "attributes": {"customerPrice": "9.99", "proceeds": "7.00", "proceedsYear2": "8.50"}}
              ]
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_prices",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "limit": .int(200)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = queryItems(request)
        #expect(request.url?.path == "/v1/subscriptions/sub-1/prices")
        #expect(query["filter[territory]"] == "USA")
        #expect(query["include"] == "territory,subscriptionPricePoint")
        #expect(query["fields[territories]"] == "currency")

        let root = try object(result.structuredContent)
        let prices = try array(root["prices"])
        let price = try object(prices.first)
        #expect(price["territory_id"] == .string("USA"))
        #expect(price["currency"] == .string("USD"))
        #expect(price["price_point_id"] == .string("pp-usa-999"))
        #expect(price["customer_price"] == .string("9.99"))
        #expect(price["proceeds_year2"] == .string("8.50"))
    }

    @Test("subscription pagination rejects another subscription parent")
    func subscriptionPaginationRejectsWrongParent() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_prices",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "next_url": .string("https://api.example.test/v1/subscriptions/sub-2/prices?filter%5Bterritory%5D=USA&cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("subscription pagination preserves the originating territory filter")
    func subscriptionPaginationRejectsChangedFilter() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_prices",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "next_url": .string("https://api.example.test/v1/subscriptions/sub-1/prices?filter%5Bterritory%5D=GBR&cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("present subscription next URL must be a string")
    func subscriptionPaginationRejectsNonStringURL() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_prices",
            arguments: [
                "subscription_id": .string("sub-1"),
                "next_url": .int(1)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("list subscription price points supports territory and 8000 limit")
    func listPricePointsSupportsTerritoryAndLargeLimit() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "subscriptionPricePoints",
                  "id": "pp-1",
                  "attributes": {"customerPrice": "9.99", "proceeds": "7.00", "proceedsYear2": "8.50"},
                  "relationships": {"territory": {"data": {"type": "territories", "id": "USA"}}}
                }
              ],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}}
              ]
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_price_points",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "limit": .int(8000)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = queryItems(request)
        #expect(request.url?.path == "/v1/subscriptions/sub-1/pricePoints")
        #expect(query["filter[territory]"] == "USA")
        #expect(query["include"] == "territory")
        #expect(query["limit"] == "8000")

        let root = try object(result.structuredContent)
        let points = try array(root["price_points"])
        let point = try object(points.first)
        #expect(point["territory_id"] == .string("USA"))
        #expect(point["currency"] == .string("USD"))
        #expect(point["customer_price"] == .string("9.99"))
    }

    @Test("price point equalizations use Apple filters and large limit")
    func pricePointEqualizationsUseFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_price_point_equalizations",
            arguments: [
                "price_point_id": .string("pp-1"),
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "limit": .int(8000)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = queryItems(request)
        #expect(request.url?.path == "/v1/subscriptionPricePoints/pp-1/equalizations")
        #expect(query["filter[subscription]"] == "sub-1")
        #expect(query["filter[territory]"] == "USA")
        #expect(query["limit"] == "8000")
    }

    @Test("get subscription availability includes available territories")
    func getAvailabilityIncludesTerritories() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "subscriptionAvailabilities",
                "id": "avail-1",
                "attributes": {"availableInNewTerritories": true},
                "relationships": {"availableTerritories": {"data": [{"type": "territories", "id": "USA"}]}}
              },
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}}
              ]
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_availability",
            arguments: ["subscription_id": .string("sub-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = queryItems(request)
        #expect(request.url?.path == "/v1/subscriptions/sub-1/subscriptionAvailability")
        #expect(query["include"] == "availableTerritories")
        let root = try object(result.structuredContent)
        let availability = try object(root["availability"])
        let territories = try array(availability["available_territories"])
        let territory = try object(territories.first)
        #expect(availability["available_in_new_territories"] == .bool(true))
        #expect(territory["id"] == .string("USA"))
        #expect(territory["currency"] == .string("USD"))
    }

    @Test("promotional offer creation rejects mismatched price point and territory arrays before network")
    func promotionalOfferRejectsMismatchedPriceArrays() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_promotional_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "name": .string("Launch"),
                "offer_code": .string("LAUNCH"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("PAY_UP_FRONT"),
                "number_of_periods": .int(1),
                "territory_ids": .array([.string("USA"), .string("GBR")]),
                "price_point_ids": .array([.string("pp-usa")])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(text(result).contains("same non-zero count"))
    }

    @Test("offer code creation keeps customer and introductory offer eligibility separate")
    func offerCodeCreationSeparatesEligibilityFields() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "subscriptionOfferCodes",
                "id": "offer-1",
                "attributes": {
                  "name": "Launch",
                  "offerMode": "FREE_TRIAL",
                  "productionCodeCount": 17,
                  "sandboxCodeCount": 3
                }
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_offer_code",
            arguments: [
                "subscription_id": .string("sub-1"),
                "name": .string("Launch"),
                "customer_eligibilities": .array([.string("NEW"), .string("EXPIRED")]),
                "offer_eligibility": .string("STACK_WITH_INTRO_OFFERS"),
                "offer_mode": .string("FREE_TRIAL"),
                "duration": .string("ONE_MONTH"),
                "number_of_periods": .int(1),
                "territory_ids": .array([.string("USA")]),
                "auto_renew_enabled": .bool(true),
                "target_subscription_plan_type": .string("MONTHLY")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(await transport.recordedBodyStrings().first)
        #expect(request.url?.path == "/v1/subscriptionOfferCodes")
        #expect(body.contains(#""customerEligibilities":["NEW","EXPIRED"]"#))
        #expect(body.contains(#""offerEligibility":"STACK_WITH_INTRO_OFFERS""#))
        #expect(body.contains(#""autoRenewEnabled":true"#))
        #expect(body.contains(#""targetSubscriptionPlanType":"MONTHLY""#))
        #expect(
            body.contains(#""prices":{"data":[{"id":"${price-0}","type":"subscriptionOfferCodePrices"}]"#)
                || body.contains(#""prices":{"data":[{"type":"subscriptionOfferCodePrices","id":"${price-0}"}]"#)
        )
        let root = try object(result.structuredContent)
        let offerCode = try object(root["offer_code"])
        #expect(offerCode["productionCodeCount"] == .int(17))
        #expect(offerCode["sandboxCodeCount"] == .int(3))
    }

    @Test("offer code creation requires explicit customer eligibility")
    func offerCodeCreationRequiresCustomerEligibility() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_offer_code",
            arguments: [
                "subscription_id": .string("sub-1"),
                "name": .string("Launch"),
                "offer_eligibility": .string("STACK_WITH_INTRO_OFFERS"),
                "offer_mode": .string("FREE_TRIAL"),
                "duration": .string("ONE_MONTH"),
                "number_of_periods": .int(1),
                "territory_ids": .array([.string("USA")])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(text(result).contains("customer_eligibilities"))
    }

    @Test("non-renewing offer code rejects introductory-offer stacking")
    func nonRenewingOfferCodeRejectsIntroStacking() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_offer_code",
            arguments: [
                "subscription_id": .string("sub-1"),
                "name": .string("Launch"),
                "customer_eligibilities": .array([.string("NEW")]),
                "offer_eligibility": .string("STACK_WITH_INTRO_OFFERS"),
                "offer_mode": .string("FREE_TRIAL"),
                "duration": .string("ONE_MONTH"),
                "number_of_periods": .int(1),
                "territory_ids": .array([.string("USA")]),
                "auto_renew_enabled": .bool(false)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(text(result).contains("REPLACE_INTRO_OFFERS"))
    }

    @Test("non-renewing free offer code replaces introductory offers")
    func nonRenewingFreeOfferCodeReplacesIntroOffers() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "subscriptionOfferCodes",
                "id": "offer-1",
                "attributes": {"name": "Launch", "offerMode": "FREE_TRIAL", "autoRenewEnabled": false}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_offer_code",
            arguments: [
                "subscription_id": .string("sub-1"),
                "name": .string("Launch"),
                "customer_eligibilities": .array([.string("NEW")]),
                "offer_eligibility": .string("REPLACE_INTRO_OFFERS"),
                "offer_mode": .string("FREE_TRIAL"),
                "duration": .string("ONE_MONTH"),
                "number_of_periods": .int(1),
                "territory_ids": .array([.string("USA")]),
                "auto_renew_enabled": .bool(false)
            ]
        ))

        #expect(result.isError != true)
        let body = try #require(await transport.recordedBodyStrings().first)
        #expect(body.contains(#""offerEligibility":"REPLACE_INTRO_OFFERS""#))
        #expect(body.contains(#""offerMode":"FREE_TRIAL""#))
        #expect(body.contains(#""autoRenewEnabled":false"#))
    }

    @Test("promotional offer creation requires territory prices")
    func promotionalOfferCreationRequiresTerritoryPrices() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_promotional_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "name": .string("Launch"),
                "offer_code": .string("LAUNCH"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("FREE_TRIAL"),
                "number_of_periods": .int(1),
                "territory_ids": .array([])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(text(result).contains("territory_ids"))
    }

    @Test("promotional offer creation sends required paid prices relationship")
    func promotionalOfferCreationSendsPaidPrices() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "subscriptionPromotionalOffers",
                "id": "promo-1",
                "attributes": {"name": "Launch", "offerMode": "PAY_UP_FRONT"}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_promotional_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "name": .string("Launch"),
                "offer_code": .string("LAUNCH"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("PAY_UP_FRONT"),
                "number_of_periods": .int(1),
                "territory_ids": .array([.string("USA")]),
                "price_point_ids": .array([.string("pp-usa")]),
                "target_subscription_plan_type": .string("MONTHLY")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(await transport.recordedBodyStrings().first)
        #expect(request.url?.path == "/v1/subscriptionPromotionalOffers")
        #expect(body.contains(#""type":"subscriptionPromotionalOfferPrices""#))
        #expect(body.contains(#""type":"subscriptionPricePoints""#))
        #expect(body.contains(#""id":"pp-usa""#))
        #expect(body.contains(#""targetSubscriptionPlanType":"MONTHLY""#))
    }

    @Test("promotional offer update rejects a no-op before network")
    func promotionalOfferUpdateRejectsNoOp() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_promotional_offer",
            arguments: ["promotional_offer_id": .string("promo-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(text(result).contains("territory_ids"))
    }

    @Test("promotional offer update sends free-trial territory prices")
    func promotionalOfferUpdateSendsFreeTrialPrices() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "subscriptionPromotionalOffers",
                "id": "promo-1",
                "attributes": {"name": "Launch", "offerMode": "FREE_TRIAL"}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_promotional_offer",
            arguments: [
                "promotional_offer_id": .string("promo-1"),
                "territory_ids": .array([.string("USA")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(await transport.recordedBodyStrings().first)
        #expect(request.url?.path == "/v1/subscriptionPromotionalOffers/promo-1")
        #expect(
            body.contains(#""prices":{"data":[{"id":"${price-0}","type":"subscriptionPromotionalOfferPrices"}]"#)
                || body.contains(#""prices":{"data":[{"type":"subscriptionPromotionalOfferPrices","id":"${price-0}"}]"#)
        )
        #expect(
            body.contains(#""territory":{"data":{"id":"USA","type":"territories"}}"#)
                || body.contains(#""territory":{"data":{"type":"territories","id":"USA"}}"#)
        )
        #expect(!body.contains("subscriptionPricePoint"))
    }

    @Test("win-back creation requires subscription price points")
    func winBackCreationRequiresPricePoints() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_winback_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("Come Back"),
                "offer_id": .string("come_back"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("FREE_TRIAL"),
                "period_count": .int(1),
                "priority": .string("NORMAL"),
                "eligibility_duration_months": .int(1),
                "eligibility_time_since_last_months_min": .int(1),
                "eligibility_time_since_last_months_max": .int(12),
                "start_date": .string("2026-08-01")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(text(result).contains("price_point_ids"))
    }

    @Test("win-back creation sends required paid prices relationship")
    func winBackCreationSendsPaidPrices() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "winBackOffers",
                "id": "winback-1",
                "attributes": {"referenceName": "Come Back", "offerMode": "PAY_UP_FRONT"}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_winback_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("Come Back"),
                "offer_id": .string("come_back"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("PAY_UP_FRONT"),
                "period_count": .int(1),
                "priority": .string("NORMAL"),
                "eligibility_duration_months": .int(1),
                "eligibility_time_since_last_months_min": .int(1),
                "eligibility_time_since_last_months_max": .int(12),
                "start_date": .string("2026-08-01"),
                "territory_ids": .array([.string("USA")]),
                "price_point_ids": .array([.string("pp-usa")]),
                "target_subscription_plan_type": .string("UPFRONT")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(await transport.recordedBodyStrings().first)
        #expect(request.url?.path == "/v1/winBackOffers")
        #expect(body.contains(#""type":"winBackOfferPrices""#))
        #expect(body.contains(#""type":"subscriptionPricePoints""#))
        #expect(body.contains(#""id":"pp-usa""#))
        #expect(body.contains(#""targetSubscriptionPlanType":"UPFRONT""#))
        #expect(!body.contains("promotionIntent"))
        let json = try JSONSerialization.jsonObject(with: Data(body.utf8))
        let payload = try #require(json as? [String: Any])
        let inlineResources = try #require(payload["included"] as? [[String: Any]])
        let inline = try #require(inlineResources.first)
        let relationships = try #require(inline["relationships"] as? [String: Any])
        #expect(Set(relationships.keys) == Set(["subscriptionPricePoint"]))
    }

    @Test("win-back creation sends either eligibility range bound independently")
    func winBackCreationSendsIndependentEligibilityRangeBounds() async throws {
        let response = """
        {
          "data": {
            "type": "winBackOffers",
            "id": "winback-1",
            "attributes": {}
          }
        }
        """
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: response),
            .init(statusCode: 201, body: response)
        ])
        let worker = try await makeWorker(transport: transport)
        let commonArguments: [String: Value] = [
            "subscription_id": .string("sub-1"),
            "reference_name": .string("Come Back"),
            "offer_id": .string("come_back"),
            "duration": .string("ONE_MONTH"),
            "offer_mode": .string("PAY_UP_FRONT"),
            "period_count": .int(1),
            "priority": .string("NORMAL"),
            "eligibility_duration_months": .int(1),
            "start_date": .string("2026-08-01"),
            "price_point_ids": .array([.string("pp-usa")])
        ]
        var minimumArguments = commonArguments
        minimumArguments["eligibility_time_since_last_months_min"] = .int(2)
        var maximumArguments = commonArguments
        maximumArguments["eligibility_time_since_last_months_max"] = .int(24)

        let minimumResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_winback_offer",
            arguments: minimumArguments
        ))
        let maximumResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_winback_offer",
            arguments: maximumArguments
        ))

        #expect(minimumResult.isError != true)
        #expect(maximumResult.isError != true)
        let bodies = await transport.recordedBodyStrings()
        let minimumBody = try #require(bodies.first)
        let maximumBody = try #require(bodies.last)
        #expect(minimumBody.contains(#""customerEligibilityTimeSinceLastSubscribedInMonths":{"minimum":2}"#))
        #expect(!minimumBody.contains(#""maximum""#))
        #expect(maximumBody.contains(#""customerEligibilityTimeSinceLastSubscribedInMonths":{"maximum":24}"#))
        #expect(!maximumBody.contains(#""minimum""#))
        #expect(!minimumBody.contains(#""territory""#))
        #expect(!maximumBody.contains(#""territory""#))
    }

    @Test("win-back eligibility duration rejects values outside Apple's discrete set")
    func winBackEligibilityDurationRejectsUnsupportedValues() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        for months in [0, 25, 61] {
            let createResult = try await worker.handleTool(CallTool.Parameters(
                name: "subscriptions_create_winback_offer",
                arguments: [
                    "subscription_id": .string("sub-1"),
                    "reference_name": .string("Come Back"),
                    "offer_id": .string("come_back"),
                    "duration": .string("ONE_MONTH"),
                    "offer_mode": .string("PAY_UP_FRONT"),
                    "period_count": .int(1),
                    "priority": .string("NORMAL"),
                    "eligibility_duration_months": .int(months),
                    "eligibility_time_since_last_months_min": .int(1),
                    "eligibility_time_since_last_months_max": .int(12),
                    "start_date": .string("2026-08-01"),
                    "price_point_ids": .array([.string("pp-usa")])
                ]
            ))
            let updateResult = try await worker.handleTool(CallTool.Parameters(
                name: "subscriptions_update_winback_offer",
                arguments: [
                    "winback_offer_id": .string("winback-1"),
                    "eligibility_duration_months": .int(months)
                ]
            ))

            #expect(createResult.isError == true)
            #expect(updateResult.isError == true)
            #expect(text(createResult).contains("1 through 24, 36, 48, or 60"))
            #expect(text(updateResult).contains("1 through 24, 36, 48, or 60"))
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("win-back eligibility duration accepts Apple's extended month values")
    func winBackEligibilityDurationAcceptsExtendedValues() async throws {
        let response = """
        {
          "data": {
            "type": "winBackOffers",
            "id": "winback-1",
            "attributes": {}
          }
        }
        """
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: response),
            .init(statusCode: 200, body: response),
            .init(statusCode: 200, body: response)
        ])
        let worker = try await makeWorker(transport: transport)

        for months in [36, 48, 60] {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "subscriptions_update_winback_offer",
                arguments: [
                    "winback_offer_id": .string("winback-1"),
                    "eligibility_duration_months": .int(months)
                ]
            ))
            #expect(result.isError != true)
        }
        #expect(await transport.requestCount() == 3)
    }

    @Test("win-back update rejects a no-op before network")
    func winBackUpdateRejectsNoOp() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_winback_offer",
            arguments: ["winback_offer_id": .string("winback-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(text(result).contains("At least one mutable"))
    }

    @Test("win-back update sends Apple mutable eligibility attributes")
    func winBackUpdateSendsMutableAttributes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "winBackOffers",
                "id": "winback-1",
                "attributes": {"priority": "HIGH", "promotionIntent": "USE_AUTO_GENERATED_ASSETS"}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_winback_offer",
            arguments: [
                "winback_offer_id": .string("winback-1"),
                "eligibility_duration_months": .int(6),
                "eligibility_time_since_last_months_min": .int(2),
                "eligibility_time_since_last_months_max": .int(24),
                "eligibility_wait_between_months": .int(3),
                "priority": .string("HIGH"),
                "promotion_intent": .string("USE_AUTO_GENERATED_ASSETS"),
                "start_date": .string("2026-08-01"),
                "end_date": .string("2026-12-31")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(await transport.recordedBodyStrings().first)
        #expect(request.url?.path == "/v1/winBackOffers/winback-1")
        #expect(body.contains(#""customerEligibilityPaidSubscriptionDurationInMonths":6"#))
        #expect(
            body.contains(#""customerEligibilityTimeSinceLastSubscribedInMonths":{"minimum":2,"maximum":24}"#)
                || body.contains(#""customerEligibilityTimeSinceLastSubscribedInMonths":{"maximum":24,"minimum":2}"#)
        )
        #expect(body.contains(#""customerEligibilityWaitBetweenOffersInMonths":3"#))
        #expect(body.contains(#""promotionIntent":"USE_AUTO_GENERATED_ASSETS""#))
    }

    @Test("win-back update preserves explicit null clearing")
    func winBackUpdatePreservesExplicitNullClearing() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "winBackOffers",
                "id": "winback-1",
                "attributes": {}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_winback_offer",
            arguments: [
                "winback_offer_id": .string("winback-1"),
                "eligibility_duration_months": .null,
                "eligibility_time_since_last_months_min": .null,
                "eligibility_wait_between_months": .null,
                "priority": .null,
                "promotion_intent": .null,
                "start_date": .null,
                "end_date": .null
            ]
        ))

        #expect(result.isError != true)
        let body = try #require(await transport.recordedBodyStrings().first)
        let json = try JSONSerialization.jsonObject(with: Data(body.utf8))
        let payload = try #require(json as? [String: Any])
        let data = try #require(payload["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        let expectedKeys: Set<String> = [
            "customerEligibilityPaidSubscriptionDurationInMonths",
            "customerEligibilityTimeSinceLastSubscribedInMonths",
            "customerEligibilityWaitBetweenOffersInMonths",
            "priority",
            "promotionIntent",
            "startDate",
            "endDate"
        ]
        #expect(Set(attributes.keys) == expectedKeys)
        #expect(attributes.values.allSatisfy { $0 is NSNull })
    }

    @Test("win-back update sends either eligibility range bound independently")
    func winBackUpdateSendsIndependentEligibilityRangeBounds() async throws {
        let response = """
        {
          "data": {
            "type": "winBackOffers",
            "id": "winback-1",
            "attributes": {}
          }
        }
        """
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: response),
            .init(statusCode: 200, body: response)
        ])
        let worker = try await makeWorker(transport: transport)

        let minimumResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_winback_offer",
            arguments: [
                "winback_offer_id": .string("winback-1"),
                "eligibility_time_since_last_months_min": .int(2)
            ]
        ))
        let maximumResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_winback_offer",
            arguments: [
                "winback_offer_id": .string("winback-1"),
                "eligibility_time_since_last_months_max": .int(24)
            ]
        ))

        #expect(minimumResult.isError != true)
        #expect(maximumResult.isError != true)
        let bodies = await transport.recordedBodyStrings()
        #expect(bodies.count == 2)
        let minimumBody = try #require(bodies.first)
        let maximumBody = try #require(bodies.last)
        #expect(minimumBody.contains(#""customerEligibilityTimeSinceLastSubscribedInMonths":{"minimum":2}"#))
        #expect(!minimumBody.contains(#""maximum""#))
        #expect(maximumBody.contains(#""customerEligibilityTimeSinceLastSubscribedInMonths":{"maximum":24}"#))
        #expect(!maximumBody.contains(#""minimum""#))
    }

    @Test("subscription images list uses Apple images relationship endpoint")
    func subscriptionImagesListUsesOfficialEndpoint() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_images",
            arguments: ["subscription_id": .string("sub-1"), "limit": .int(200)]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/subscriptions/sub-1/images")
        #expect(queryItems(request)["limit"] == "200")
    }

    @Test("subscription commerce schemas expose Apple enums, dates, ranges, and null clearing")
    func subscriptionCommerceSchemasExposeAppleConstraints() async throws {
        let worker = try await makeWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()
        let createWinBack = try #require(tools.first { $0.name == "subscriptions_create_winback_offer" })
        let updateWinBack = try #require(tools.first { $0.name == "subscriptions_update_winback_offer" })
        let createOfferCode = try #require(tools.first { $0.name == "subscriptions_create_offer_code" })

        let createProperties = try object(try object(createWinBack.inputSchema)["properties"])
        let createDuration = try object(createProperties["eligibility_duration_months"])
        let createDurationValues = try array(createDuration["enum"])
        #expect(createDurationValues.contains(.int(1)))
        #expect(createDurationValues.contains(.int(24)))
        #expect(createDurationValues.contains(.int(36)))
        #expect(createDurationValues.contains(.int(48)))
        #expect(createDurationValues.contains(.int(60)))
        #expect(!createDurationValues.contains(.int(25)))
        #expect(try object(createProperties["start_date"])["format"] == .string("date"))
        #expect(try object(createProperties["eligibility_wait_between_months"])["minimum"] == .int(2))
        #expect(try object(createProperties["eligibility_wait_between_months"])["maximum"] == .int(24))
        let required = try array(try object(createWinBack.inputSchema)["required"]).compactMap(\.stringValue)
        #expect(required.contains("price_point_ids"))
        #expect(!required.contains("territory_ids"))
        #expect(!required.contains("eligibility_time_since_last_months_min"))
        #expect(!required.contains("eligibility_time_since_last_months_max"))

        let updateProperties = try object(try object(updateWinBack.inputSchema)["properties"])
        let updateDuration = try object(updateProperties["eligibility_duration_months"])
        #expect(try array(updateDuration["type"]) == [.string("integer"), .string("null")])
        #expect(try array(updateDuration["enum"]).contains(.null))
        let minimumRange = try object(updateProperties["eligibility_time_since_last_months_min"])
        let maximumRange = try object(updateProperties["eligibility_time_since_last_months_max"])
        #expect(try array(minimumRange["type"]).contains(.null))
        #expect(try array(maximumRange["type"]).contains(.null))
        #expect(try object(updateProperties["end_date"])["format"] == .string("date"))

        let offerProperties = try object(try object(createOfferCode.inputSchema)["properties"])
        let customerEligibilityItems = try object(try object(offerProperties["customer_eligibilities"])["items"])
        #expect(try array(customerEligibilityItems["enum"]) == [.string("NEW"), .string("EXISTING"), .string("EXPIRED")])
        #expect(try object(offerProperties["customer_eligibilities"])["uniqueItems"] == .bool(true))
    }

    @Test("introductory offer creation preserves territory_id for Apple relationship")
    func introductoryOfferCreateKeepsTerritoryID() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "subscriptionIntroductoryOffers",
                "id": "intro-1",
                "attributes": {"duration": "ONE_MONTH", "offerMode": "FREE_TRIAL", "numberOfPeriods": 1}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_intro_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("FREE_TRIAL"),
                "number_of_periods": .int(1),
                "territory_id": .string("USA")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/subscriptionIntroductoryOffers")
        let body = try #require(await transport.recordedBodyStrings().first)
        #expect(
            body.contains(#""territory":{"data":{"type":"territories","id":"USA"}}"#)
                || body.contains(#""territory":{"data":{"id":"USA","type":"territories"}}"#)
        )
        #expect(!body.contains("filter_territory"))
    }

    @Test("list subscription promotional offers supports territory filter")
    func listPromotionalOffersSupportsTerritoryFilter() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "subscriptionPromotionalOffers",
                  "id": "promo-1",
                  "attributes": {"name": "Launch", "offerCode": "LAUNCH"},
                  "relationships": {
                    "prices": {"data": [{"type": "subscriptionPromotionalOfferPrices", "id": "promo-price-1"}]}
                  }
                }
              ]
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_promotional_offers",
            arguments: ["subscription_id": .string("sub-1"), "territory_id": .string("USA")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = queryItems(request)
        #expect(request.url?.path == "/v1/subscriptions/sub-1/promotionalOffers")
        #expect(query["filter[territory]"] == "USA")
        #expect(query["include"] == "prices")
        let root = try object(result.structuredContent)
        let offer = try object(try array(root["promotional_offers"]).first)
        #expect(offer["offer_code"] == .string("LAUNCH"))
        #expect(offer["prices_ids"] == .array([.string("promo-price-1")]))
    }

    @Test("list subscription offer codes supports territory filter")
    func listOfferCodesSupportsTerritoryFilter() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "subscriptionOfferCodes",
                  "id": "offer-1",
                  "attributes": {"name": "Launch", "active": true},
                  "relationships": {
                    "prices": {"data": [{"type": "subscriptionOfferCodePrices", "id": "offer-price-1"}]}
                  }
                }
              ]
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_offer_codes",
            arguments: ["subscription_id": .string("sub-1"), "territory_id": .string("USA")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = queryItems(request)
        #expect(request.url?.path == "/v1/subscriptions/sub-1/offerCodes")
        #expect(query["filter[territory]"] == "USA")
        #expect(query["include"] == "oneTimeUseCodes,customCodes,prices")
        let root = try object(result.structuredContent)
        let offer = try object(try array(root["offer_codes"]).first)
        #expect(offer["name"] == .string("Launch"))
        #expect(offer["prices_ids"] == .array([.string("offer-price-1")]))
    }

    @Test("subscription offer code get uses direct v3 endpoint")
    func offerCodeGetUsesDirectEndpoint() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "subscriptionOfferCodes",
                "id": "offer-1",
                "attributes": {"name": "Launch", "active": true}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_offer_code",
            arguments: ["offer_code_id": .string("offer-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/subscriptionOfferCodes/offer-1")
        let root = try object(result.structuredContent)
        let offer = try object(root["offer_code"])
        #expect(offer["id"] == .string("offer-1"))
        #expect(offer["name"] == .string("Launch"))
        #expect(offer["active"] == .bool(true))
    }

    @Test("subscription offer code prices support territory filter and normalized price fields")
    func offerCodePricesSupportTerritoryFilter() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "subscriptionOfferCodePrices",
                  "id": "offer-price-1",
                  "relationships": {
                    "territory": {"data": {"type": "territories", "id": "USA"}},
                    "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": "pp-1"}}
                  }
                }
              ],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
                {"type": "subscriptionPricePoints", "id": "pp-1", "attributes": {"customerPrice": "1.99", "proceeds": "1.40", "proceedsYear2": "1.70"}}
              ]
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_offer_code_prices",
            arguments: ["offer_code_id": .string("offer-1"), "territory_id": .string("USA")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = queryItems(request)
        #expect(request.url?.path == "/v1/subscriptionOfferCodes/offer-1/prices")
        #expect(query["filter[territory]"] == "USA")
        #expect(query["include"] == "territory,subscriptionPricePoint")

        let root = try object(result.structuredContent)
        let price = try object(try array(root["prices"]).first)
        #expect(price["territory_id"] == .string("USA"))
        #expect(price["currency"] == .string("USD"))
        #expect(price["price_point_id"] == .string("pp-1"))
        #expect(price["customer_price"] == .string("1.99"))
        #expect(price["proceeds_year2"] == .string("1.70"))
    }

    @Test("subscription win-back offer get uses direct v3 endpoint")
    func winBackOfferGetUsesDirectEndpoint() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "winBackOffers",
                "id": "winback-1",
                "attributes": {"referenceName": "Come Back", "offerId": "comeback"}
              }
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_winback_offer",
            arguments: ["winback_offer_id": .string("winback-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/winBackOffers/winback-1")
        let root = try object(result.structuredContent)
        let offer = try object(root["win_back_offer"])
        #expect(offer["id"] == .string("winback-1"))
        #expect(offer["reference_name"] == .string("Come Back"))
    }

    @Test("subscription inventory includes availability and current territory price when territory is provided")
    func inventoryIncludesAvailabilityAndCurrentPrice() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "subscriptionGroups",
                  "id": "group-1",
                  "attributes": {"referenceName": "Main"},
                  "relationships": {"subscriptions": {"data": [{"type": "subscriptions", "id": "sub-1"}]}}
                }
              ],
              "included": [
                {"type": "subscriptions", "id": "sub-1", "attributes": {"name": "Premium", "productId": "premium.monthly", "state": "APPROVED"}}
              ]
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "subscriptionAvailabilities",
                "id": "avail-1",
                "attributes": {"availableInNewTerritories": true},
                "relationships": {"availableTerritories": {"data": [{"type": "territories", "id": "USA"}]}}
              },
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}}
              ]
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "subscriptionPrices",
                  "id": "price-1",
                  "attributes": {"startDate": "2026-01-01", "preserved": false},
                  "relationships": {
                    "territory": {"data": {"type": "territories", "id": "USA"}},
                    "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": "pp-1"}}
                  }
                }
              ],
              "included": [
                {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
                {"type": "subscriptionPricePoints", "id": "pp-1", "attributes": {"customerPrice": "9.99", "proceeds": "7.00", "proceedsYear2": "8.50"}}
              ]
            }
            """)
        ])
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_inventory",
            arguments: ["app_id": .string("app-1"), "territory_id": .string("USA")]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.url?.path } == [
            "/v1/apps/app-1/subscriptionGroups",
            "/v1/subscriptions/sub-1/subscriptionAvailability",
            "/v1/subscriptions/sub-1/prices"
        ])

        let root = try object(result.structuredContent)
        let subscription = try object(try array(root["subscriptions"]).first)
        let availability = try object(subscription["availability"])
        let currentPrice = try object(subscription["current_price"])
        #expect(subscription["id"] == .string("sub-1"))
        #expect(availability["available_in_new_territories"] == .bool(true))
        #expect(currentPrice["territory_id"] == .string("USA"))
        #expect(currentPrice["currency"] == .string("USD"))
        #expect(currentPrice["customer_price"] == .string("9.99"))
    }
}

private func makeWorker(transport: TestHTTPTransport) async throws -> SubscriptionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return SubscriptionsWorker(httpClient: client, uploadService: UploadService())
}

private func queryItems(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func object(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw SubscriptionsV3TestFailure.expectedObject
    }
    return object
}

private func array(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw SubscriptionsV3TestFailure.expectedArray
    }
    return array
}

private func text(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private enum SubscriptionsV3TestFailure: Error {
    case expectedObject
    case expectedArray
}
