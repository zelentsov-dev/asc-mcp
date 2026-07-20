import Foundation
import Testing
@testable import asc_mcp

@Suite("Subscription Plan Availability Model Tests")
struct SubscriptionPlanAvailabilityModelTests {
    @Test("plan availability response decodes typed plan, relationship paging, and territory currency")
    func decodesPlanAvailabilityResponse() throws {
        let response = try JSONDecoder().decode(
            ASCSubscriptionPlanAvailabilityResponse.self,
            from: Data(subscriptionPlanAvailabilityResponseBody.utf8)
        )

        #expect(response.data.type == "subscriptionPlanAvailabilities")
        #expect(response.data.id == "availability-1")
        #expect(response.data.attributes?.planType == .monthly)
        #expect(response.data.attributes?.availableInNewTerritories == false)
        #expect(response.data.relationships?.availableTerritories?.data?.map(\.id) == ["USA", "GBR"])
        #expect(response.data.relationships?.availableTerritories?.meta?.paging?.total == 2)
        #expect(response.data.relationships?.availableTerritories?.meta?.paging?.limit == 50)
        #expect(response.included?.first?.attributes?.currency == "USD")
        #expect(response.links.`self` == "https://api.example.test/v1/subscriptionPlanAvailabilities/availability-1")
    }

    @Test("unknown Apple plan values fail typed decoding")
    func rejectsUnknownPlanType() {
        let body = #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1","attributes":{"planType":"ANNUAL"}},"links":{"self":"https://api.example.test/v1/subscriptionPlanAvailabilities/availability-1"}}"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCSubscriptionPlanAvailabilityResponse.self,
                from: Data(body.utf8)
            )
        }
    }

    @Test("Apple document links and links.self are required")
    func requiresDocumentLinksSelf() {
        let bodies = [
            #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1"}}"#,
            #"{"data":{"type":"subscriptionPlanAvailabilities","id":"availability-1"},"links":{}}"#
        ]

        for body in bodies {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(
                    ASCSubscriptionPlanAvailabilityResponse.self,
                    from: Data(body.utf8)
                )
            }
        }
    }

    @Test("create request preserves omitted, Boolean, and null availability states")
    func createRequestPreservesNullableBoolTriState() throws {
        let omitted = ASCSubscriptionPlanAvailabilityCreateRequest(
            subscriptionID: "sub-1",
            planType: .monthly,
            territoryIDs: ["USA", "GBR"],
            availableInNewTerritories: nil
        )
        let value = ASCSubscriptionPlanAvailabilityCreateRequest(
            subscriptionID: "sub-1",
            planType: .upfront,
            territoryIDs: [],
            availableInNewTerritories: .bool(false)
        )
        let null = ASCSubscriptionPlanAvailabilityCreateRequest(
            subscriptionID: "sub-1",
            planType: .monthly,
            territoryIDs: ["USA"],
            availableInNewTerritories: .null
        )

        let omittedData = try modelRequestData(omitted)
        let valueData = try modelRequestData(value)
        let nullData = try modelRequestData(null)
        let omittedAttributes = try modelObject(try modelObject(omittedData["data"])["attributes"])
        let valueAttributes = try modelObject(try modelObject(valueData["data"])["attributes"])
        let nullAttributes = try modelObject(try modelObject(nullData["data"])["attributes"])

        #expect(omittedAttributes["availableInNewTerritories"] == nil)
        #expect(valueAttributes["availableInNewTerritories"] as? Bool == false)
        #expect(nullAttributes["availableInNewTerritories"] is NSNull)
        #expect(valueAttributes["planType"] as? String == "UPFRONT")

        let omittedRelationships = try modelObject(try modelObject(omittedData["data"])["relationships"])
        let subscription = try modelObject(try modelObject(omittedRelationships["subscription"])["data"])
        let territories = try modelArray(try modelObject(omittedRelationships["availableTerritories"])["data"])
        #expect(subscription["type"] as? String == "subscriptions")
        #expect(subscription["id"] as? String == "sub-1")
        #expect(territories.compactMap { item in
            (try? modelObject(item))?["id"] as? String
        } == ["USA", "GBR"])
    }

    @Test("update request omits untouched containers and preserves explicit null and empty linkage")
    func updateRequestPreservesOptionalContainers() throws {
        let boolOnly = ASCSubscriptionPlanAvailabilityUpdateRequest(
            id: "availability-1",
            availableInNewTerritories: .bool(true),
            territoryIDs: nil
        )
        let territoriesOnly = ASCSubscriptionPlanAvailabilityUpdateRequest(
            id: "availability-1",
            availableInNewTerritories: nil,
            territoryIDs: []
        )
        let nullAndTerritories = ASCSubscriptionPlanAvailabilityUpdateRequest(
            id: "availability-1",
            availableInNewTerritories: .null,
            territoryIDs: ["USA"]
        )

        let boolData = try modelObject(try modelRequestData(boolOnly)["data"])
        let territoryData = try modelObject(try modelRequestData(territoriesOnly)["data"])
        let nullData = try modelObject(try modelRequestData(nullAndTerritories)["data"])

        #expect(boolData["relationships"] == nil)
        #expect(territoryData["attributes"] == nil)
        let emptyTerritories = try modelArray(
            try modelObject(try modelObject(territoryData["relationships"])["availableTerritories"])["data"]
        )
        #expect(emptyTerritories.isEmpty)
        let nullAttributes = try modelObject(nullData["attributes"])
        #expect(nullAttributes["availableInNewTerritories"] is NSNull)
        #expect(nullData["type"] as? String == "subscriptionPlanAvailabilities")
        #expect(nullData["id"] as? String == "availability-1")
    }

    @Test("adjusted equalizations response decodes totals and included territory")
    func decodesAdjustedEqualizationsResponse() throws {
        let body = """
        {
          "data": [{
            "type": "subscriptionPricePoints",
            "id": "price-point-2",
            "attributes": {"customerPrice": "11.99", "proceeds": "8.00", "proceedsYear2": "9.25"},
            "relationships": {"territory": {"data": {"type": "territories", "id": "GBR"}}}
          }],
          "included": [{"type": "territories", "id": "GBR", "attributes": {"currency": "GBP"}}],
          "links": {"self": "https://api.example.test/v1/subscriptionPricePoints/price-point-1/adjustedEqualizations"},
          "meta": {"paging": {"total": 1, "limit": 8000}}
        }
        """
        let response = try JSONDecoder().decode(
            ASCSubscriptionAdjustedPricePointsResponse.self,
            from: Data(body.utf8)
        )

        #expect(response.data.first?.relationships?.territory?.data?.id == "GBR")
        #expect(response.data.first?.attributes?.proceedsYear2 == "9.25")
        #expect(response.included?.first?.attributes?.currency == "GBP")
        #expect(response.meta?.paging?.total == 1)
        #expect(response.meta?.paging?.limit == 8000)
    }
}

private let subscriptionPlanAvailabilityResponseBody = """
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
        "meta": {"paging": {"total": 2, "limit": 50}},
        "links": {
          "related": "https://api.example.test/v1/subscriptionPlanAvailabilities/availability-1/availableTerritories",
          "self": "https://api.example.test/v1/subscriptionPlanAvailabilities/availability-1/relationships/availableTerritories"
        }
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

private func modelRequestData<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func modelObject(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

private func modelArray(_ value: Any?) throws -> [Any] {
    try #require(value as? [Any])
}
