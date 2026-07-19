import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Pricing Territory Availability Contract Tests")
struct PricingTerritoryAvailabilityContractTests {
    @Test("app availability is resolved before its paginated territory collection is listed")
    func resolvesThenListsWithRequestedLimit() async throws {
        let nextURL = "https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities?cursor=next-page"
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
        #expect(try queryItems(listRequest)["limit[territoryAvailabilities]"] == nil)

        let payload = try pricingObject(result.structuredContent)
        #expect(payload["count"] == .int(1))
        #expect(payload["next_url"] == .string(nextURL))
        let availability = try pricingObject(try pricingArray(payload["territory_availabilities"]).first)
        #expect(availability["id"] == .string("territory-availability-1"))
        #expect(availability["territory_id"] == .string("USA"))
        #expect(availability["preOrderPublishDate"] == .string("2026-07-18"))
        #expect(availability["contentStatuses"] == .array([.string("AVAILABLE")]))
    }

    @Test("next URL replays the collection page without resolving app availability again")
    func nextURLReplaysCollectionPage() async throws {
        let nextURL = "https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities?cursor=next-page&limit=25"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"links":{"self":"https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities?cursor=next-page&limit=25"}}"#)
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
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.path == "/v2/appAvailabilities/availability-1/territoryAvailabilities")
        #expect(try queryItems(request)["cursor"] == "next-page")
        #expect(try queryItems(request)["limit"] == "25")
    }

    @Test("foreign pagination URL is rejected before transport")
    func rejectsForeignNextURL() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makePricingWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_list_territory_availability",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://example.invalid/v2/appAvailabilities/availability-1/territoryAvailabilities?cursor=bad")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("same-host pagination URL for another route is rejected before transport")
    func rejectsSameHostForeignPath() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makePricingWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "pricing_list_territory_availability",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://api.example.test/v1/apps/app-1/appAvailabilityV2?cursor=bad")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
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
        "self": "https://api.example.test/v2/appAvailabilities/availability-1/territoryAvailabilities?limit=125",
        "next": "\(nextURL)"
      }
    }
    """
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
