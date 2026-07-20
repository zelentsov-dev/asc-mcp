import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Subscription Plan Availability Contract Tests")
struct SubscriptionPlanAvailabilityContractTests {
    @Test("six new tools expose strict schemas and Apple limits")
    func toolSchemas() async throws {
        let worker = try await planWorker(TestHTTPTransport(responses: []))
        let tools = Dictionary(uniqueKeysWithValues: await worker.getTools().map { ($0.name, $0) })
        let names: Set<String> = [
            "subscriptions_create_plan_availability",
            "subscriptions_get_plan_availability",
            "subscriptions_update_plan_availability",
            "subscriptions_list_plan_availabilities",
            "subscriptions_list_plan_availability_territories",
            "subscriptions_list_price_point_adjusted_equalizations"
        ]

        #expect(names.allSatisfy { tools[$0] != nil })
        for name in names {
            let schema = try planSchema(try #require(tools[name]))
            #expect(schema["type"] == .string("object"))
            #expect(schema["additionalProperties"] == .bool(false))
        }
        let create = try planSchema(try #require(tools["subscriptions_create_plan_availability"]))
        let createProperties = try planObject(create["properties"])
        let canonicalIDPattern = #"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#
        #expect(try planObject(createProperties["subscription_id"])["pattern"] == .string(canonicalIDPattern))
        let planType = try planObject(createProperties["plan_type"])
        #expect(Set(try planArray(planType["enum"]).compactMap(\.stringValue)) == ["MONTHLY", "UPFRONT"])
        let territoryIDs = try planObject(createProperties["territory_ids"])
        #expect(territoryIDs["uniqueItems"] == .bool(true))
        #expect(try planObject(territoryIDs["items"])["pattern"] == .string(canonicalIDPattern))
        #expect(try planObject(createProperties["available_in_new_territories"])["type"] == .array([.string("boolean"), .string("null")]))

        let update = try planSchema(try #require(tools["subscriptions_update_plan_availability"]))
        #expect(update["additionalProperties"] == .bool(false))
        #expect(update["minProperties"] == .int(2))

        for name in [
            "subscriptions_list_plan_availabilities",
            "subscriptions_list_plan_availability_territories"
        ] {
            let properties = try planProperties(try #require(tools[name]))
            #expect(try planObject(properties["limit"])["minimum"] == .int(1))
            #expect(try planObject(properties["limit"])["maximum"] == .int(200))
            #expect(try planObject(properties["limit"])["default"] == .int(25))
            #expect(try planObject(properties["next_url"])["format"] == .string("uri-reference"))
            #expect(try planObject(properties["next_url"])["description"]?.stringValue?.contains("default 25") == true)
        }

        let adjusted = try planProperties(try #require(tools["subscriptions_list_price_point_adjusted_equalizations"]))
        #expect(try planObject(adjusted["price_point_id"])["pattern"] == .string(canonicalIDPattern))
        #expect(try planObject(adjusted["limit"])["minimum"] == .int(1))
        #expect(try planObject(adjusted["limit"])["maximum"] == .int(8000))
        #expect(try planObject(adjusted["limit"])["default"] == .int(25))
        #expect(try planObject(adjusted["next_url"])["format"] == .string("uri-reference"))
        for field in ["territory_ids", "subscription_ids", "upfront_price_point_ids", "plan_types"] {
            #expect(try planArray(try planObject(adjusted[field])["oneOf"]).count == 2)
        }
        for field in ["territory_ids", "subscription_ids", "upfront_price_point_ids"] {
            let alternatives = try planArray(try planObject(adjusted[field])["oneOf"])
            #expect(try planObject(alternatives.first)["pattern"] == .string(canonicalIDPattern))
            #expect(try planObject(try planObject(alternatives.last)["items"])["pattern"] == .string(canonicalIDPattern))
        }
    }

    @Test("create sends exact JSON API linkage and preserves nullable Boolean states")
    func createRequestContract() async throws {
        let transport = TestHTTPTransport(responses: Array(repeating:
            .init(statusCode: 201, body: subscriptionPlanResponseBody()),
            count: 3
        ))
        let worker = try await planWorker(transport)
        let variants: [Value?] = [nil, .bool(false), .null]

        for value in variants {
            var arguments: [String: Value] = [
                "subscription_id": .string("sub-1"),
                "plan_type": .string("MONTHLY"),
                "territory_ids": .array([.string("USA"), .string("GBR")])
            ]
            if let value {
                arguments["available_in_new_territories"] = value
            }
            let result = try await worker.handleTool(.init(
                name: "subscriptions_create_plan_availability",
                arguments: arguments
            ))
            #expect(result.isError != true)
            let payload = try planObject(result.structuredContent)
            let availability = try planObject(payload["plan_availability"])
            #expect(availability["plan_type"] == .string("MONTHLY"))
            #expect(availability["available_territory_ids"] == .array([.string("USA"), .string("GBR")]))
            #expect(availability["available_territories_count"] == .int(2))
            #expect(availability["available_territories_total"] == .int(2))
            #expect(availability["available_territories_next_cursor"] == .null)
            #expect(availability["available_territories_truncated"] == .bool(false))
            #expect(availability["available_territories_completeness_known"] == .bool(true))
        }

        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "POST", "POST"])
        #expect(requests.allSatisfy { $0.url?.path == "/v1/subscriptionPlanAvailabilities" })
        let bodies = try requests.map(planRequestBody)
        for body in bodies {
            let data = try planJSONBodyData(body)
            #expect(data["type"] as? String == "subscriptionPlanAvailabilities")
            let attributes = try planAnyObject(data["attributes"])
            #expect(attributes["planType"] as? String == "MONTHLY")
            let relationships = try planAnyObject(data["relationships"])
            let subscription = try planAnyObject(try planAnyObject(relationships["subscription"])["data"])
            #expect(subscription["type"] as? String == "subscriptions")
            #expect(subscription["id"] as? String == "sub-1")
            let territories = try planAnyArray(try planAnyObject(relationships["availableTerritories"])["data"])
            #expect(territories.compactMap { (try? planAnyObject($0))?["id"] as? String } == ["USA", "GBR"])
            #expect(territories.allSatisfy { (try? planAnyObject($0))?["type"] as? String == "territories" })
        }
        let omittedAttributes = try planAnyObject(try planJSONBodyData(bodies[0])["attributes"])
        let valueAttributes = try planAnyObject(try planJSONBodyData(bodies[1])["attributes"])
        let nullAttributes = try planAnyObject(try planJSONBodyData(bodies[2])["attributes"])
        #expect(omittedAttributes["availableInNewTerritories"] == nil)
        #expect(valueAttributes["availableInNewTerritories"] as? Bool == false)
        #expect(nullAttributes["availableInNewTerritories"] is NSNull)
    }

    @Test("update omits untouched containers and supports empty territory replacement")
    func updateRequestContract() async throws {
        let transport = TestHTTPTransport(responses: Array(repeating:
            .init(statusCode: 200, body: subscriptionPlanResponseBody()),
            count: 3
        ))
        let worker = try await planWorker(transport)
        let arguments: [[String: Value]] = [
            ["plan_availability_id": .string("availability-1"), "available_in_new_territories": .bool(false)],
            ["plan_availability_id": .string("availability-1"), "available_in_new_territories": .null],
            ["plan_availability_id": .string("availability-1"), "territory_ids": .array([])]
        ]

        for value in arguments {
            let result = try await worker.handleTool(.init(
                name: "subscriptions_update_plan_availability",
                arguments: value
            ))
            #expect(result.isError != true)
        }

        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["PATCH", "PATCH", "PATCH"])
        #expect(requests.allSatisfy { $0.url?.path == "/v1/subscriptionPlanAvailabilities/availability-1" })
        let bodies = try requests.map(planRequestBody).map(planJSONBodyData)
        #expect(try planAnyObject(bodies[0]["attributes"])["availableInNewTerritories"] as? Bool == false)
        #expect(bodies[0]["relationships"] == nil)
        #expect(try planAnyObject(bodies[1]["attributes"])["availableInNewTerritories"] is NSNull)
        #expect(bodies[2]["attributes"] == nil)
        let relationships = try planAnyObject(bodies[2]["relationships"])
        #expect(try planAnyArray(try planAnyObject(relationships["availableTerritories"])["data"]).isEmpty)
    }

    @Test("plan PATCH recovery preserves exact requested tri-state values")
    func updateRecoveryPreservesRequestedValues() async throws {
        let arguments: [String: Value] = [
            "plan_availability_id": .string("availability-1"),
            "available_in_new_territories": .null,
            "territory_ids": .array([])
        ]

        let acceptedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 202, body: subscriptionPlanResponseBody())
        ])
        let acceptedWorker = try await planWorker(acceptedTransport)
        let accepted = try await acceptedWorker.handleTool(.init(
            name: "subscriptions_update_plan_availability",
            arguments: arguments
        ))
        #expect(accepted.isError == true)
        #expect(await acceptedTransport.requestCount() == 1)
        let acceptedPayload = try planObject(accepted.structuredContent)
        #expect(acceptedPayload["operationCommitState"] == .string("committed_unverified"))
        #expect(acceptedPayload["operationCommitted"] == .bool(true))
        #expect(acceptedPayload["retrySafe"] == .bool(false))
        let acceptedDetails = try planObject(acceptedPayload["details"])
        #expect(acceptedDetails["available_in_new_territories"] == .null)
        #expect(acceptedDetails["territory_ids"] == .array([]))
        #expect(acceptedDetails["requestedArguments"] == .object(arguments))
        let acceptedCause = try planObject(acceptedDetails["cause"])
        #expect(acceptedCause["statusCode"] == .int(202))

        let unknownTransport = TestHTTPTransport(responses: [])
        let unknownWorker = try await planWorker(unknownTransport, maxRetries: 3)
        let unknown = try await unknownWorker.handleTool(.init(
            name: "subscriptions_update_plan_availability",
            arguments: arguments
        ))
        #expect(unknown.isError == true)
        #expect(await unknownTransport.requestCount() == 1)
        let unknownPayload = try planObject(unknown.structuredContent)
        #expect(unknownPayload["operationCommitState"] == .string("unknown"))
        #expect(unknownPayload["outcomeUnknown"] == .bool(true))
        #expect(unknownPayload["retrySafe"] == .bool(false))
        let unknownDetails = try planObject(unknownPayload["details"])
        #expect(unknownDetails["requestedArguments"] == .object(arguments))
    }

    @Test("plan create recovery matches scoped candidates by plan type only")
    func createRecoveryUsesUsableMatchFields() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await planWorker(transport, maxRetries: 3)
        let result = try await worker.handleTool(.init(
            name: "subscriptions_create_plan_availability",
            arguments: [
                "subscription_id": .string("sub-1"),
                "plan_type": .string("MONTHLY"),
                "territory_ids": .array([.string("USA")]),
                "available_in_new_territories": .bool(false)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let details = try planObject(try planObject(result.structuredContent)["details"])
        let recovery = try planObject(details["recovery"])
        let match = try planObject(recovery["match_requested"])
        #expect(match["fields"] == .array([.string("plan_type")]))
        let list = try planObject(recovery["list_candidates"])
        #expect(try planObject(list["arguments"])["subscription_id"] == .string("sub-1"))
    }

    @Test("get uses the full stable Apple projection and reports relationship completeness")
    func getRequestAndOutputContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: subscriptionPlanResponseBody(total: 3))
        ])
        let worker = try await planWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_get_plan_availability",
            arguments: ["plan_availability_id": .string("availability-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/subscriptionPlanAvailabilities/availability-1")
        #expect(planQuery(request) == subscriptionPlanAvailabilityQueryFixture())
        let payload = try planObject(result.structuredContent)
        let availability = try planObject(payload["plan_availability"])
        #expect(availability["available_territories_count"] == .int(2))
        #expect(availability["available_territories_total"] == .int(3))
        #expect(availability["available_territories_next_cursor"] == .null)
        #expect(availability["available_territories_included_count"] == .int(2))
        #expect(availability["available_territories_truncated"] == .bool(true))
        #expect(availability["available_territories_completeness_known"] == .bool(true))
        let territories = try planArray(availability["available_territories"])
        #expect(try planObject(territories.first)["currency"] == .string("USD"))
    }

    @Test("plan responses require exact identity self path and coherent paging")
    func responsesRequireExactIdentityAndPaging() async throws {
        let getBodies = [
            #"{"data":{"type":"unexpectedResources","id":"availability-1"},"links":{"self":"/v1/subscriptionPlanAvailabilities/availability-1"}}"#,
            #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-2"},"links":{"self":"/v1/subscriptionPlanAvailabilities/availability-2"}}"#,
            #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1"},"links":{"self":"/v1/subscriptionPlanAvailabilities/sibling"}}"#,
            #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1","relationships":{"availableTerritories":{"data":[{"type":"territories","id":"USA"},{"type":"territories","id":"GBR"}],"meta":{"paging":{"total":1,"limit":2}}}}},"links":{"self":"/v1/subscriptionPlanAvailabilities/availability-1"}}"#,
            #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1","relationships":{"availableTerritories":{"data":[],"meta":{}}}},"links":{"self":"/v1/subscriptionPlanAvailabilities/availability-1"}}"#,
            #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1"}}"#
        ]
        for body in getBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await planWorker(transport)
            let result = try await worker.handleTool(.init(
                name: "subscriptions_get_plan_availability",
                arguments: ["plan_availability_id": .string("availability-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }

        let listBodies = [
            "{\"data\":[\(subscriptionPlanResourceJSON),\(subscriptionPlanResourceJSON)],\"links\":{\"self\":\"/v1/subscriptions/sub-1/planAvailabilities\"}}",
            "{\"data\":[\(subscriptionPlanResourceJSON)],\"links\":{\"self\":\"/v1/subscriptions/sub-1/planAvailabilities\"},\"meta\":{\"paging\":{\"total\":0,\"limit\":25}}}",
            #"{"data":[],"links":{"self":"/v1/subscriptions/sub-1/planAvailabilities"},"meta":{}}"#,
            #"{"data":[],"links":{"self":"/v1/subscriptions/sub-1/planAvailabilities"},"meta":{"paging":{"total":0,"limit":0}}}"#,
            #"{"data":[],"links":{"self":"/v1/subscriptions/sub-1/planAvailabilities"},"meta":{"paging":{"total":0,"limit":25,"nextCursor":"next"}}}"#
        ]
        for body in listBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await planWorker(transport)
            let result = try await worker.handleTool(.init(
                name: "subscriptions_list_plan_availabilities",
                arguments: ["subscription_id": .string("sub-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("missing Apple territory linkage data remains unknown instead of looking empty")
    func missingTerritoryLinkageRemainsUnknown() async throws {
        let body = #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1","attributes":{"availableInNewTerritories":true,"planType":"UPFRONT"},"relationships":{"availableTerritories":{"meta":{"paging":{"total":2,"limit":50}}}}},"links":{"self":"https://api.example.test/v1/subscriptionPlanAvailabilities/availability-1"}}"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: body)
        ])
        let worker = try await planWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_get_plan_availability",
            arguments: ["plan_availability_id": .string("availability-1")]
        ))

        #expect(result.isError != true)
        let payload = try planObject(result.structuredContent)
        let availability = try planObject(payload["plan_availability"])
        for field in [
            "available_territory_ids",
            "available_territories",
            "available_territories_count",
            "available_territories_next_cursor",
            "available_territories_included_count",
            "available_territories_truncated",
            "available_territories_completeness_known"
        ] {
            #expect(availability[field] == .null)
        }
        #expect(availability["available_territories_total"] == .int(2))
        #expect(availability["available_territories_limit"] == .int(50))
    }

    @Test("relationship nextCursor preserves known truncation without total")
    func relationshipCursorPreservesTruncation() async throws {
        let body = #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1","relationships":{"availableTerritories":{"data":[{"type":"territories","id":"USA"}],"meta":{"paging":{"limit":1,"nextCursor":"next-territory"}}}}},"links":{"self":"/v1/subscriptionPlanAvailabilities/availability-1"}}"#
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await planWorker(transport)
        let result = try await worker.handleTool(.init(
            name: "subscriptions_get_plan_availability",
            arguments: ["plan_availability_id": .string("availability-1")]
        ))

        #expect(result.isError != true)
        let availability = try planObject(try planObject(result.structuredContent)["plan_availability"])
        #expect(availability["available_territories_count"] == .int(1))
        #expect(availability["available_territories_next_cursor"] == .string("next-territory"))
        #expect(availability["available_territories_truncated"] == .bool(true))
        #expect(availability["available_territories_completeness_known"] == .bool(true))
    }

    @Test("plan availability and territory lists expose totals and continuations")
    func listContracts() async throws {
        let planNext = planPaginationURL(
            path: "/v1/subscriptions/sub-1/planAvailabilities",
            query: subscriptionPlanAvailabilityQueryFixture(limit: "125").merging(["cursor": "next"]) { _, new in new }
        )
        let territoryNext = planPaginationURL(
            path: "/v1/subscriptionPlanAvailabilities/availability-1/availableTerritories",
            query: ["fields[territories]": "currency", "limit": "200", "cursor": "next"]
        )
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: subscriptionPlanListResponseBody(nextURL: planNext)),
            .init(statusCode: 200, body: subscriptionPlanTerritoriesResponseBody(nextURL: territoryNext))
        ])
        let worker = try await planWorker(transport)

        let planResult = try await worker.handleTool(.init(
            name: "subscriptions_list_plan_availabilities",
            arguments: ["subscription_id": .string("sub-1"), "limit": .int(125)]
        ))
        let territoryResult = try await worker.handleTool(.init(
            name: "subscriptions_list_plan_availability_territories",
            arguments: ["plan_availability_id": .string("availability-1"), "limit": .int(200)]
        ))

        #expect(planResult.isError != true)
        #expect(territoryResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests[0].url?.path == "/v1/subscriptions/sub-1/planAvailabilities")
        #expect(planQuery(requests[0]) == subscriptionPlanAvailabilityQueryFixture(limit: "125"))
        #expect(requests[1].url?.path == "/v1/subscriptionPlanAvailabilities/availability-1/availableTerritories")
        #expect(planQuery(requests[1]) == ["fields[territories]": "currency", "limit": "200"])
        let plans = try planObject(planResult.structuredContent)
        #expect(plans["count"] == .int(1))
        #expect(plans["total"] == .int(1))
        #expect(plans["next_url"] == .string(planNext))
        let firstPlan = try planObject(try planArray(plans["plan_availabilities"]).first)
        #expect(firstPlan["available_territories_count"] == .int(2))
        #expect(firstPlan["available_territories_next_cursor"] == .null)
        #expect(firstPlan["available_territories_completeness_known"] == .bool(true))
        let territories = try planObject(territoryResult.structuredContent)
        #expect(territories["count"] == .int(2))
        #expect(territories["total"] == .int(2))
        #expect(territories["next_url"] == .string(territoryNext))
        #expect(try planObject(try planArray(territories["territories"]).last)["currency"] == .string("GBP"))
    }

    @Test("adjusted equalizations sends every documented filter and projects currency and total")
    func adjustedEqualizationsContract() async throws {
        let nextURL = planPaginationURL(
            path: "/v1/subscriptionPricePoints/price-point-1/adjustedEqualizations",
            query: adjustedEqualizationsQueryFixture().merging(["cursor": "next"]) { _, new in new }
        )
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: adjustedEqualizationsResponseBody(nextURL: nextURL))
        ])
        let worker = try await planWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_list_price_point_adjusted_equalizations",
            arguments: adjustedEqualizationsArguments()
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/subscriptionPricePoints/price-point-1/adjustedEqualizations")
        #expect(planQuery(request) == adjustedEqualizationsQueryFixture())
        let payload = try planObject(result.structuredContent)
        #expect(payload["count"] == .int(1))
        #expect(payload["total"] == .int(1))
        #expect(payload["next_url"] == .string(nextURL))
        let pricePoint = try planObject(try planArray(payload["price_points"]).first)
        #expect(pricePoint["territory_id"] == .string("GBR"))
        #expect(pricePoint["currency"] == .string("GBP"))
        #expect(pricePoint["customer_price"] == .string("11.99"))
        #expect(pricePoint["proceeds_year2"] == .string("9.25"))
    }

    @Test("invalid enums limits identifiers CSV values and no-op updates fail before network access")
    func rejectsInvalidInputsBeforeNetwork() async throws {
        let cases: [(String, [String: Value])] = [
            ("subscriptions_create_plan_availability", ["subscription_id": .string("sub-1"), "plan_type": .string("ANNUAL"), "territory_ids": .array([])]),
            ("subscriptions_create_plan_availability", ["subscription_id": .string("sub-1"), "plan_type": .string("MONTHLY"), "territory_ids": .array([.string("USA"), .string("USA")])]),
            ("subscriptions_create_plan_availability", ["subscription_id": .string("sub-1"), "plan_type": .string("MONTHLY"), "territory_ids": .array([.string("USA,GBR")])]),
            ("subscriptions_create_plan_availability", ["subscription_id": .string(" sub-1"), "plan_type": .string("MONTHLY"), "territory_ids": .array([])]),
            ("subscriptions_update_plan_availability", ["plan_availability_id": .string("availability-1")]),
            ("subscriptions_update_plan_availability", ["plan_availability_id": .string("availability-1"), "available_in_new_territories": .string("true")]),
            ("subscriptions_list_plan_availabilities", ["subscription_id": .string("sub-1"), "limit": .int(0)]),
            ("subscriptions_list_plan_availability_territories", ["plan_availability_id": .string("availability-1"), "limit": .int(201)]),
            ("subscriptions_list_price_point_adjusted_equalizations", ["price_point_id": .string("price-point-1"), "limit": .int(8001)]),
            ("subscriptions_list_price_point_adjusted_equalizations", ["price_point_id": .string("price-point-1"), "territory_ids": .array([.string("USA"), .string("USA")])]),
            ("subscriptions_list_price_point_adjusted_equalizations", ["price_point_id": .string("price-point-1"), "subscription_ids": .array([.string("sub-1,sub-2")])]),
            ("subscriptions_list_price_point_adjusted_equalizations", ["price_point_id": .string("price-point-1"), "plan_types": .array([.string("ANNUAL")])]),
            ("subscriptions_list_plan_availabilities", ["subscription_id": .string("sub-1"), "unexpected": .bool(true)])
        ]

        for (name, arguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await planWorker(transport)
            let result = try await worker.handleTool(.init(name: name, arguments: arguments))
            #expect(result.isError == true, "Expected validation failure for \(name): \(arguments)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("continuations preserve concrete parent full query origin and cursor")
    func strictPaginationMatrix() async throws {
        for fixture in planPaginationFixtures() {
            var validQuery = fixture.query
            validQuery["cursor"] = "next"
            var validArguments = fixture.arguments
            validArguments["next_url"] = .string(planPaginationURL(
                path: fixture.path,
                query: validQuery,
                rootRelative: true
            ))
            let validTransport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 200,
                    body: "{\"data\":[],\"links\":{\"self\":\"\(fixture.path)\"},\"meta\":{\"paging\":{\"total\":0,\"limit\":\(fixture.query["limit"] ?? "25")}}}"
                )
            ])
            let validWorker = try await planWorker(validTransport)
            let validResult = try await validWorker.handleTool(.init(name: fixture.tool, arguments: validArguments))
            #expect(validResult.isError != true, "Expected valid continuation for \(fixture.tool)")
            #expect(await validTransport.requestCount() == 1)

            var changedQuery = validQuery
            changedQuery["limit"] = "1"
            var missingQuery = validQuery
            missingQuery.removeValue(forKey: try #require(fixture.query.keys.sorted().first))
            let invalidURLs = [
                planPaginationURL(path: fixture.wrongPath, query: validQuery),
                planPaginationURL(path: fixture.path, query: validQuery, host: "other.example.test"),
                planPaginationURL(path: fixture.path, query: validQuery, scheme: "http"),
                planPaginationURL(path: fixture.path, query: validQuery, port: 444),
                planPaginationURL(path: fixture.path, query: fixture.query),
                planPaginationURL(path: fixture.path, query: fixture.query.merging(["cursor": ""]) { _, new in new }),
                planPaginationURL(path: fixture.path, query: missingQuery),
                planPaginationURL(path: fixture.path, query: validQuery.merging(["unexpected": "value"]) { _, new in new }),
                planPaginationURL(path: fixture.path, query: changedQuery),
                planPaginationURL(path: fixture.path, query: validQuery) + "&limit=1"
            ]
            for nextURL in invalidURLs {
                let transport = TestHTTPTransport(responses: [])
                let worker = try await planWorker(transport)
                var arguments = fixture.arguments
                arguments["next_url"] = .string(nextURL)
                let result = try await worker.handleTool(.init(name: fixture.tool, arguments: arguments))
                #expect(result.isError == true, "Expected strict continuation rejection for \(fixture.tool): \(nextURL)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("operation manifest maps six new operations and retains only linkage twins as deferred")
    func operationManifestLineage() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expected = [
            "subscriptions_create_plan_availability": "subscriptionPlanAvailabilities_createInstance",
            "subscriptions_get_plan_availability": "subscriptionPlanAvailabilities_getInstance",
            "subscriptions_update_plan_availability": "subscriptionPlanAvailabilities_updateInstance",
            "subscriptions_list_plan_availabilities": "subscriptions_planAvailabilities_getToManyRelated",
            "subscriptions_list_plan_availability_territories": "subscriptionPlanAvailabilities_availableTerritories_getToManyRelated",
            "subscriptions_list_price_point_adjusted_equalizations": "subscriptionPricePoints_adjustedEqualizations_getToManyRelated"
        ]
        for (tool, operationID) in expected {
            let mapping = try #require(manifest.mapping(for: tool))
            #expect(mapping.operations.map(\.operationID) == [operationID])
            #expect(mapping.implementationState == .asBuilt)
            #expect(mapping.response.mode == .projection)
            #expect(mapping.fields.contains { $0.toolField == "next_url" } == tool.hasPrefix("subscriptions_list_"))
        }

        let mappedOperationIDs = Set(expected.values)
        #expect(manifest.index.waivers.allSatisfy { waiver in
            waiver.operationID.map { !mappedOperationIDs.contains($0) } ?? true
        })
        let remaining = Set(manifest.index.waivers.compactMap(\.operationID))
        #expect(remaining.contains("subscriptionPlanAvailabilities_availableTerritories_getToManyRelationship"))
        #expect(remaining.contains("subscriptionPlanAvailabilities_availableTerritories_replaceToManyRelationship"))

        let adjusted = try #require(manifest.mapping(for: "subscriptions_list_price_point_adjusted_equalizations"))
        #expect(Set(adjusted.fields.compactMap(\.appleName)) == [
            "id",
            "filter[territory]",
            "filter[subscription]",
            "filter[upfrontPricePointId]",
            "filter[planType]",
            "limit"
        ])
        let update = try #require(manifest.mapping(for: "subscriptions_update_plan_availability"))
        #expect(update.fields.contains { $0.jsonPointer == "/data/attributes/availableInNewTerritories" })
        #expect(update.fields.contains { $0.jsonPointer == "/data/relationships/availableTerritories/data/*/id" })
        for tool in [
            "subscriptions_create_plan_availability",
            "subscriptions_get_plan_availability",
            "subscriptions_update_plan_availability"
        ] {
            let mapping = try #require(manifest.mapping(for: tool))
            #expect(mapping.response.fields.contains {
                $0.outputField == "plan_availability.available_territories.*.id" &&
                    $0.jsonPointer == "/data/relationships/availableTerritories/data/*/id"
            })
            #expect(mapping.response.fields.contains {
                $0.outputField == "plan_availability.available_territories.*.currency" &&
                    $0.jsonPointer == "/included" && $0.localRole != nil
            })
        }
        let list = try #require(manifest.mapping(for: "subscriptions_list_plan_availabilities"))
        let listOutputs = Set(list.response.fields.map(\.outputField))
        #expect([
            "plan_availabilities.*.type",
            "plan_availabilities.*.available_territories.*.id",
            "plan_availabilities.*.available_territories.*.type",
            "plan_availabilities.*.available_territories.*.currency",
            "plan_availabilities.*.available_territories_total",
            "plan_availabilities.*.available_territories_limit",
            "plan_availabilities.*.available_territories_count",
            "plan_availabilities.*.available_territories_next_cursor",
            "plan_availabilities.*.available_territories_included_count",
            "plan_availabilities.*.available_territories_truncated",
            "plan_availabilities.*.available_territories_completeness_known"
        ].allSatisfy(listOutputs.contains))
        #expect(manifest.mapping(for: "subscriptions_get_availability")?.replacementTool == "subscriptions_list_plan_availabilities")
        #expect(manifest.mapping(for: "subscriptions_set_availability")?.replacementTool == "subscriptions_create_plan_availability")
        #expect(manifest.mapping(for: "subscriptions_list_available_territories")?.replacementTool == "subscriptions_list_plan_availability_territories")
    }
}

private struct PlanPaginationFixture {
    let tool: String
    let arguments: [String: Value]
    let path: String
    let wrongPath: String
    let query: [String: String]
}

private func planPaginationFixtures() -> [PlanPaginationFixture] {
    [
        PlanPaginationFixture(
            tool: "subscriptions_list_plan_availabilities",
            arguments: ["subscription_id": .string("sub-1"), "limit": .int(200)],
            path: "/v1/subscriptions/sub-1/planAvailabilities",
            wrongPath: "/v1/subscriptions/sub-2/planAvailabilities",
            query: subscriptionPlanAvailabilityQueryFixture(limit: "200")
        ),
        PlanPaginationFixture(
            tool: "subscriptions_list_plan_availability_territories",
            arguments: ["plan_availability_id": .string("availability-1"), "limit": .int(200)],
            path: "/v1/subscriptionPlanAvailabilities/availability-1/availableTerritories",
            wrongPath: "/v1/subscriptionPlanAvailabilities/availability-2/availableTerritories",
            query: ["fields[territories]": "currency", "limit": "200"]
        ),
        PlanPaginationFixture(
            tool: "subscriptions_list_price_point_adjusted_equalizations",
            arguments: adjustedEqualizationsArguments(),
            path: "/v1/subscriptionPricePoints/price-point-1/adjustedEqualizations",
            wrongPath: "/v1/subscriptionPricePoints/price-point-2/adjustedEqualizations",
            query: adjustedEqualizationsQueryFixture()
        )
    ]
}

private func adjustedEqualizationsArguments() -> [String: Value] {
    [
        "price_point_id": .string("price-point-1"),
        "territory_ids": .array([.string("USA"), .string("GBR")]),
        "subscription_ids": .array([.string("sub-1"), .string("sub-2")]),
        "upfront_price_point_ids": .array([.string("upfront-1"), .string("upfront-2")]),
        "plan_types": .array([.string("MONTHLY"), .string("UPFRONT")]),
        "limit": .int(8000)
    ]
}

private func adjustedEqualizationsQueryFixture() -> [String: String] {
    [
        "include": "territory",
        "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,adjustedEqualizations",
        "fields[territories]": "currency",
        "filter[territory]": "USA,GBR",
        "filter[subscription]": "sub-1,sub-2",
        "filter[upfrontPricePointId]": "upfront-1,upfront-2",
        "filter[planType]": "MONTHLY,UPFRONT",
        "limit": "8000"
    ]
}

private func subscriptionPlanAvailabilityQueryFixture(limit: String? = nil) -> [String: String] {
    var query = [
        "include": "availableTerritories",
        "fields[subscriptionPlanAvailabilities]": "availableInNewTerritories,planType,availableTerritories",
        "fields[territories]": "currency",
        "limit[availableTerritories]": "50"
    ]
    if let limit {
        query["limit"] = limit
    }
    return query
}

private func subscriptionPlanResponseBody(total: Int = 2) -> String {
    """
    {
      "data": {
        "type": "subscriptionPlanAvailabilities",
        "id": "availability-1",
        "attributes": {"availableInNewTerritories": false, "planType": "MONTHLY"},
        "relationships": {
          "availableTerritories": {
            "data": [
              {"type": "territories", "id": "USA"},
              {"type": "territories", "id": "GBR"}
            ],
            "meta": {"paging": {"total": \(total), "limit": 50}}
          }
        }
      },
      "included": [
        {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
        {"type": "territories", "id": "GBR", "attributes": {"currency": "GBP"}}
      ],
      "links": {"self": "https://api.example.test/v1/subscriptionPlanAvailabilities/availability-1"}
    }
    """
}

private func subscriptionPlanListResponseBody(nextURL: String) -> String {
    """
    {
      "data": [\(subscriptionPlanResourceJSON)],
      "included": [
        {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
        {"type": "territories", "id": "GBR", "attributes": {"currency": "GBP"}}
      ],
      "links": {
        "self": "https://api.example.test/v1/subscriptions/sub-1/planAvailabilities?limit=125",
        "next": "\(nextURL)"
      },
      "meta": {"paging": {"total": 1, "limit": 125}}
    }
    """
}

private let subscriptionPlanResourceJSON = """
{
  "type": "subscriptionPlanAvailabilities",
  "id": "availability-1",
  "attributes": {"availableInNewTerritories": false, "planType": "MONTHLY"},
  "relationships": {
    "availableTerritories": {
      "data": [
        {"type": "territories", "id": "USA"},
        {"type": "territories", "id": "GBR"}
      ],
      "meta": {"paging": {"total": 2, "limit": 50}}
    }
  }
}
"""

private func subscriptionPlanTerritoriesResponseBody(nextURL: String) -> String {
    """
    {
      "data": [
        {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}},
        {"type": "territories", "id": "GBR", "attributes": {"currency": "GBP"}}
      ],
      "links": {
        "self": "https://api.example.test/v1/subscriptionPlanAvailabilities/availability-1/availableTerritories?limit=200",
        "next": "\(nextURL)"
      },
      "meta": {"paging": {"total": 2, "limit": 200}}
    }
    """
}

private func adjustedEqualizationsResponseBody(nextURL: String) -> String {
    """
    {
      "data": [{
        "type": "subscriptionPricePoints",
        "id": "price-point-2",
        "attributes": {"customerPrice": "11.99", "proceeds": "8.00", "proceedsYear2": "9.25"},
        "relationships": {"territory": {"data": {"type": "territories", "id": "GBR"}}}
      }],
      "included": [{"type": "territories", "id": "GBR", "attributes": {"currency": "GBP"}}],
      "links": {
        "self": "https://api.example.test/v1/subscriptionPricePoints/price-point-1/adjustedEqualizations",
        "next": "\(nextURL)"
      },
      "meta": {"paging": {"total": 1, "limit": 8000}}
    }
    """
}

private func planWorker(
    _ transport: TestHTTPTransport,
    maxRetries: Int = 1
) async throws -> SubscriptionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: maxRetries
    )
    return SubscriptionsWorker(httpClient: client, uploadService: UploadService())
}

private func planSchema(_ tool: Tool) throws -> [String: Value] {
    try planObject(tool.inputSchema)
}

private func planProperties(_ tool: Tool) throws -> [String: Value] {
    try planObject(try planSchema(tool)["properties"])
}

private func planObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw SubscriptionPlanContractFailure.expectedObject
    }
    return object
}

private func planArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw SubscriptionPlanContractFailure.expectedArray
    }
    return array
}

private func planRequestBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func planJSONBodyData(_ body: [String: Any]) throws -> [String: Any] {
    try planAnyObject(body["data"])
}

private func planAnyObject(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

private func planAnyArray(_ value: Any?) throws -> [Any] {
    try #require(value as? [Any])
}

private func planQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues:
        (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap {
            item in item.value.map { (item.name, $0) }
        }
    )
}

private func planPaginationURL(
    path: String,
    query: [String: String],
    host: String = "api.example.test",
    scheme: String = "https",
    port: Int? = nil,
    rootRelative: Bool = false
) -> String {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    if rootRelative {
        return components.percentEncodedPath + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
    }
    return components.url!.absoluteString
}

private enum SubscriptionPlanContractFailure: Error {
    case expectedObject
    case expectedArray
}
