import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Pricing Territory Availability Contract Tests")
struct PricingTerritoryAvailabilityContractTests {
    @Test("app availability is resolved before its paginated territory collection is listed")
    func resolvesThenListsWithRequestedLimit() async throws {
        let nextURL = "https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities?cursor=next-page&include=territory"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"appAvailabilities","id":"availability-1","attributes":{"availableInNewTerritories":true}},"links":{"self":"https://api.example.test/v1/apps/app-1/appAvailabilityV2"}}"#),
            .init(statusCode: 200, body: territoryAvailabilitiesBody(nextURL: nextURL))
        ])
        let worker = try await makePricingWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_list_territory_availability",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .int(125)
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET"])
        let resolveRequest = try #require(requests.first)
        let listRequest = try #require(requests.last)
        #expect(resolveRequest.url?.path == "/v1/apps/app-1/appAvailabilityV2")
        #expect(listRequest.url?.path == "/v2/appAvailabilities/availability-1/territoryAvailabilities")
        #expect(try queryItems(listRequest)["limit"] == "125")
        #expect(try queryItems(listRequest)["include"] == "territory")
        #expect(try queryItems(listRequest)["limit[territoryAvailabilities]"] == nil)

        let payload = try pricingObject(result.structuredContent)
        #expect(payload["count"] == .int(1))
        #expect(payload["next_url"] == .string(nextURL))
        let availability = try pricingObject(try pricingArray(payload["territory_availabilities"]).first)
        #expect(availability["id"] == .string("territory-availability-1"))
        #expect(availability["territory_id"] == .string("USA"))
        #expect(availability["currency"] == .string("USD"))
        #expect(availability["preOrderPublishDate"] == .string("2026-07-18"))
        #expect(availability["contentStatuses"] == .array([.string("AVAILABLE")]))
        #expect(payload["total"] == .int(1))
    }

    @Test("next URL is bound to the freshly resolved app availability")
    func nextURLUsesFreshlyResolvedAvailability() async throws {
        let nextURL = "https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities?cursor=next-page&limit=25&include=territory"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appAvailabilityBody(id: "availability-1")),
            .init(statusCode: 200, body: #"{"data":[],"links":{"self":"https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities?cursor=next-page&limit=25&include=territory"}}"#)
        ])
        let worker = try await makePricingWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_list_territory_availability",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .int(200),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests.first?.url?.path == "/v1/apps/app-1/appAvailabilityV2")
        let request = try #require(requests.last)
        #expect(request.url?.path == "/v2/appAvailabilities/availability-1/territoryAvailabilities")
        #expect(try queryItems(request)["cursor"] == "next-page")
        #expect(try queryItems(request)["limit"] == "25")
        #expect(try queryItems(request)["include"] == "territory")
    }

    @Test("foreign pagination URL is rejected after authoritative availability resolution")
    func rejectsForeignNextURL() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appAvailabilityBody(id: "availability-1"))
        ])
        let worker = try await makePricingWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_list_territory_availability",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://example.invalid/v2/appAvailabilities/availability-1/territoryAvailabilities?cursor=bad")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("same-host pagination URL for another route is rejected after resolution")
    func rejectsSameHostForeignPath() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appAvailabilityBody(id: "availability-1"))
        ])
        let worker = try await makePricingWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_list_territory_availability",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://api.example.test/v1/apps/app-1/appAvailabilityV2?cursor=bad")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("same-host pagination URL for another resolved availability is rejected")
    func rejectsWrongResolvedAvailabilityParent() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appAvailabilityBody(id: "availability-1"))
        ])
        let worker = try await makePricingWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_list_territory_availability",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://api.example.test/v2/appAvailabilities/availability-2/territoryAvailabilities?cursor=bad")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }
}

private func makePricingWorker(transport: TestHTTPTransport) async throws -> PricingWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return PricingWorker(httpClient: client)
}

private func territoryAvailabilitiesBody(nextURL: String) -> String {
    """
    {
      "data": [
        {
          "type": "territoryAvailabilities",
          "id": "territory-availability-1",
          "attributes": {
            "available": true,
            "releaseDate": "2026-07-19",
            "preOrderEnabled": false,
            "preOrderPublishDate": "2026-07-18",
            "contentStatuses": ["AVAILABLE"]
          },
          "relationships": {
            "territory": {
              "data": {"type": "territories", "id": "USA"}
            }
          }
        }
      ],
      "links": {
        "self": "https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities?limit=125&include=territory",
        "next": "\(nextURL)"
      },
      "meta": {
        "paging": {"total": 1, "limit": 125}
      },
      "included": [
        {
          "type": "territories",
          "id": "USA",
          "attributes": {"currency": "USD"}
        }
      ]
    }
    """
}

private func appAvailabilityBody(id: String) -> String {
    #"{"data":{"type":"appAvailabilities","id":"\#(id)","attributes":{"availableInNewTerritories":true}}}"#
}

private func queryItems(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func pricingObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw PricingTerritoryAvailabilityTestFailure.expectedObject
    }
    return object
}

private func pricingArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw PricingTerritoryAvailabilityTestFailure.expectedArray
    }
    return array
}

private enum PricingTerritoryAvailabilityTestFailure: Error {
    case expectedObject
    case expectedArray
}
