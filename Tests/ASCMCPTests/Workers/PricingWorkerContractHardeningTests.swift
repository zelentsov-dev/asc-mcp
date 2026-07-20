import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Pricing Worker Contract Hardening Tests")
struct PricingWorkerContractHardeningTests {
    @Test("published availability creation requires at least one territory source")
    func availabilityCreationSchemaPreservesSourceRequirement() async throws {
        let worker = try await makePricingHardeningWorker(
            transport: TestHTTPTransport(responses: [])
        )
        let tools = await worker.getTools()
        let tool = try #require(tools.first { $0.name == "pricing_create_availability" })
        let raw = try pricingHardeningObject(tool.inputSchema)
        let published = try pricingHardeningObject(ToolMetadataPolicy.apply(to: tool).inputSchema)

        #expect(raw["minProperties"] == .int(3))
        #expect(raw["additionalProperties"] == .bool(false))
        #expect(published["minProperties"] == .int(3))
        #expect(published["additionalProperties"] == .bool(false))
        #expect(published["anyOf"] == nil)
    }

    @Test("price schedule exposes nested limits, linkage classification, and truncation")
    func priceScheduleCompleteness() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: priceScheduleBody)
        ])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_get_price_schedule",
            arguments: [
                "app_id": .string("app-1"),
                "manual_prices_limit": .int(1),
                "automatic_prices_limit": .int(1)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try pricingHardeningQuery(request)
        #expect(query["include"] == "manualPrices,automaticPrices,baseTerritory")
        #expect(query["limit[manualPrices]"] == "1")
        #expect(query["limit[automaticPrices]"] == "1")

        let root = try pricingHardeningObject(result.structuredContent)
        let schedule = try pricingHardeningObject(root["price_schedule"])
        let manual = try pricingHardeningArray(schedule["manual_prices"])
        let automatic = try pricingHardeningArray(schedule["automatic_prices"])
        #expect(try pricingHardeningObject(manual.first)["id"] == .string("manual-1"))
        #expect(try pricingHardeningObject(automatic.first)["id"] == .string("automatic-1"))
        #expect(schedule["manual_prices_total"] == .int(2))
        #expect(schedule["manual_prices_truncated"] == .bool(true))
        #expect(schedule["automatic_prices_truncated"] == .bool(false))
        #expect(schedule["manual_prices_related_url"] == .string("https://api.example.test/v1/appPriceSchedules/schedule-1/manualPrices"))
        #expect(try pricingHardeningObject(schedule["base_territory"])["currency"] == .string("USD"))
    }

    @Test("multiple manual prices encode Apple inline resources with nullable boundaries")
    func createsMultipleManualPrices() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: createdPriceScheduleBody)
        ])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_set_price_schedule",
            arguments: [
                "app_id": .string("app-1"),
                "base_territory_id": .string("USA"),
                "manual_prices": .array([
                    .object([
                        "price_point_id": .string("point-1"),
                        "start_date": .null,
                        "end_date": .string("2026-08-31")
                    ]),
                    .object([
                        "price_point_id": .string("point-2"),
                        "start_date": .string("2026-09-01"),
                        "end_date": .null
                    ])
                ])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try pricingHardeningRequestBody(request)
        let data = try #require(body["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let manualRelationship = try #require(relationships["manualPrices"] as? [String: Any])
        let linkage = try #require(manualRelationship["data"] as? [[String: Any]])
        #expect(linkage.compactMap { $0["id"] as? String } == ["${price-0}", "${price-1}"])

        let included = try #require(body["included"] as? [[String: Any]])
        #expect(included.count == 2)
        let firstAttributes = try #require(included[0]["attributes"] as? [String: Any])
        let secondAttributes = try #require(included[1]["attributes"] as? [String: Any])
        #expect(firstAttributes["startDate"] is NSNull)
        #expect(firstAttributes["endDate"] as? String == "2026-08-31")
        #expect(secondAttributes["startDate"] as? String == "2026-09-01")
        #expect(secondAttributes["endDate"] is NSNull)

        let root = try pricingHardeningObject(result.structuredContent)
        let schedule = try pricingHardeningObject(root["price_schedule"])
        #expect(schedule["submitted_manual_prices_count"] == .int(2))
    }

    @Test("legacy single price input remains supported")
    func preservesLegacySinglePriceInput() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: createdPriceScheduleBody)
        ])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_set_price_schedule",
            arguments: [
                "app_id": .string("app-1"),
                "base_territory_id": .string("USA"),
                "price_point_id": .string("point-1")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try pricingHardeningRequestBody(request)
        let included = try #require(body["included"] as? [[String: Any]])
        #expect(included.count == 1)
        let attributes = try #require(included[0]["attributes"] as? [String: Any])
        #expect(attributes["startDate"] is NSNull)
        #expect(attributes["endDate"] is NSNull)
    }

    @Test("price schedule rejects a missing price mode before the network")
    func rejectsMissingPriceScheduleMode() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_set_price_schedule",
            arguments: [
                "app_id": .string("app-1"),
                "base_territory_id": .string("USA")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("price schedule rejects conflicting input modes before the network")
    func rejectsConflictingPriceScheduleModes() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_set_price_schedule",
            arguments: [
                "app_id": .string("app-1"),
                "base_territory_id": .string("USA"),
                "price_point_id": .string("point-1"),
                "manual_prices": .array([
                    .object(["price_point_id": .string("point-2")])
                ])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("availability include exposes relationship paging and truncation")
    func availabilityIncludeCompleteness() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appAvailabilityWithIncludedBody)
        ])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_get_availability_v2",
            arguments: [
                "availability_id": .string("availability-1"),
                "include_territory_availabilities": .bool(true),
                "territory_availabilities_limit": .int(1)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try pricingHardeningQuery(request)
        #expect(query["include"] == "territoryAvailabilities")
        #expect(query["limit[territoryAvailabilities]"] == "1")

        let root = try pricingHardeningObject(result.structuredContent)
        let availability = try pricingHardeningObject(root["availability"])
        #expect(availability["territory_availabilities_total"] == .int(2))
        #expect(availability["territory_availabilities_truncated"] == .bool(true))
        #expect(try pricingHardeningArray(availability["territory_availability_ids"]) == [.string("territory-availability-1")])
    }

    @Test("availability creation supports Apple inline territory resources")
    func createsInlineTerritoryAvailability() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: createdAvailabilityBody)
        ])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_create_availability",
            arguments: [
                "app_id": .string("app-1"),
                "available_in_new_territories": .bool(true),
                "territory_availabilities": .array([
                    .object([
                        "territory_id": .string("USA"),
                        "available": .bool(true),
                        "release_date": .string("2026-09-01"),
                        "pre_order_enabled": .bool(true)
                    ]),
                    .object([
                        "territory_id": .string("GBR")
                    ])
                ])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try pricingHardeningRequestBody(request)
        let data = try #require(body["data"] as? [String: Any])
        let primaryRelationships = try #require(data["relationships"] as? [String: Any])
        let territoryAvailabilities = try #require(primaryRelationships["territoryAvailabilities"] as? [String: Any])
        let linkage = try #require(territoryAvailabilities["data"] as? [[String: Any]])
        #expect(linkage.compactMap { $0["id"] as? String } == ["${territoryAvailability-0}", "${territoryAvailability-1}"])
        let included = try #require(body["included"] as? [[String: Any]])
        #expect(included.count == 2)
        #expect(included[0]["id"] as? String == "${territoryAvailability-0}")
        let attributes = try #require(included[0]["attributes"] as? [String: Any])
        #expect(attributes["releaseDate"] as? String == "2026-09-01")
        let omittedAttributes = try #require(included[1]["attributes"] as? [String: Any])
        #expect(omittedAttributes["available"] is NSNull)
        #expect(omittedAttributes["releaseDate"] is NSNull)
        #expect(omittedAttributes["preOrderEnabled"] is NSNull)
        let relationships = try #require(included[0]["relationships"] as? [String: Any])
        let territory = try #require(relationships["territory"] as? [String: Any])
        let territoryData = try #require(territory["data"] as? [String: Any])
        #expect(territoryData["id"] as? String == "USA")

        let root = try pricingHardeningObject(result.structuredContent)
        #expect(root["submitted_inline_territory_availability_count"] == .int(2))
    }

    @Test("legacy territory availability relationship IDs remain supported")
    func preservesLegacyTerritoryAvailabilityIds() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: createdAvailabilityBody)
        ])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_create_availability",
            arguments: [
                "app_id": .string("app-1"),
                "available_in_new_territories": .bool(false),
                "territory_ids": .array([.string("territory-availability-existing")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try pricingHardeningRequestBody(request)
        #expect(body["included"] == nil)
        let data = try #require(body["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let territoryAvailabilities = try #require(relationships["territoryAvailabilities"] as? [String: Any])
        let linkage = try #require(territoryAvailabilities["data"] as? [[String: Any]])
        #expect(linkage.compactMap { $0["id"] as? String } == ["territory-availability-existing"])
    }

    @Test("price point continuation must preserve the included territory projection")
    func rejectsPricePointContinuationWithoutInclude() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makePricingHardeningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_list_price_points",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://api.example.test/v1/apps/app-1/appPricePoints?cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }
}

private let priceScheduleBody = #"""
{
  "data": {
    "type": "appPriceSchedules",
    "id": "schedule-1",
    "relationships": {
      "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
      "manualPrices": {
        "links": {"related": "https://api.example.test/v1/appPriceSchedules/schedule-1/manualPrices"},
        "meta": {"paging": {"total": 2, "limit": 1}},
        "data": [{"type": "appPrices", "id": "manual-1"}]
      },
      "automaticPrices": {
        "links": {"related": "https://api.example.test/v1/appPriceSchedules/schedule-1/automaticPrices"},
        "meta": {"paging": {"total": 1, "limit": 1}},
        "data": [{"type": "appPrices", "id": "automatic-1"}]
      }
    }
  },
  "included": [
    {"type": "appPrices", "id": "manual-1", "attributes": {"manual": false}},
    {"type": "appPrices", "id": "automatic-1", "attributes": {"manual": true}},
    {"type": "territories", "id": "USA", "attributes": {"currency": "USD"}}
  ]
}
"""#

private let createdPriceScheduleBody = #"""
{"data":{"type":"appPriceSchedules","id":"schedule-1","relationships":{"baseTerritory":{"data":{"type":"territories","id":"USA"}}}}}
"""#

private let appAvailabilityWithIncludedBody = #"""
{
  "data": {
    "type": "appAvailabilities",
    "id": "availability-1",
    "attributes": {"availableInNewTerritories": true},
    "relationships": {
      "territoryAvailabilities": {
        "links": {"related": "https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities"},
        "meta": {"paging": {"total": 2, "limit": 1}},
        "data": [{"type": "territoryAvailabilities", "id": "territory-availability-1"}]
      }
    }
  },
  "included": [
    {
      "type": "territoryAvailabilities",
      "id": "territory-availability-1",
      "attributes": {"available": true},
      "relationships": {"territory": {"data": {"type": "territories", "id": "USA"}}}
    }
  ]
}
"""#

private let createdAvailabilityBody = #"""
{"data":{"type":"appAvailabilities","id":"availability-1","attributes":{"availableInNewTerritories":true}}}
"""#

private func makePricingHardeningWorker(transport: TestHTTPTransport) async throws -> PricingWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return PricingWorker(httpClient: client)
}

private func pricingHardeningRequestBody(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func pricingHardeningQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func pricingHardeningObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw PricingWorkerContractHardeningTestFailure.expectedObject
    }
    return object
}

private func pricingHardeningArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw PricingWorkerContractHardeningTestFailure.expectedArray
    }
    return array
}

private enum PricingWorkerContractHardeningTestFailure: Error {
    case expectedObject
    case expectedArray
}
