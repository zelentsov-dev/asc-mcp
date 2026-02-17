import Testing
import Foundation
@testable import asc_mcp

@Suite("Pricing Model Tests")
struct PricingModelTests {
    @Test func decodeTerritory() throws {
        let json = """
        {"type":"territories","id":"USA","attributes":{"currency":"USD"}}
        """.data(using: .utf8)!
        let territory = try JSONDecoder().decode(ASCTerritory.self, from: json)
        #expect(territory.id == "USA")
        #expect(territory.attributes?.currency == "USD")
    }

    @Test func territoriesResponse() throws {
        let json = """
        {"data":[{"type":"territories","id":"USA","attributes":{"currency":"USD"}},{"type":"territories","id":"GBR","attributes":{"currency":"GBP"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCTerritoriesResponse.self, from: json)
        #expect(response.data.count == 2)
    }

    @Test func appAvailability() throws {
        let json = """
        {"data":{"type":"appAvailabilities","id":"aa-1","attributes":{"availableInNewTerritories":true}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppAvailabilityV2Response.self, from: json)
        #expect(response.data.attributes?.availableInNewTerritories == true)
    }

    @Test func pricePoint() throws {
        let json = """
        {"type":"appPricePoints","id":"pp-1","attributes":{"customerPrice":"0.99","proceeds":"0.70"}}
        """.data(using: .utf8)!
        let point = try JSONDecoder().decode(ASCAppPricePointV3.self, from: json)
        #expect(point.attributes?.customerPrice == "0.99")
        #expect(point.attributes?.proceeds == "0.70")
    }

    @Test func pricingIncludedResourceTerritory() throws {
        let json = """
        {"type":"territories","id":"USA","attributes":{"currency":"USD"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCPricingIncludedResource.self, from: json)
        if case .territory(let t) = included {
            #expect(t.id == "USA")
        } else {
            Issue.record("Expected territory")
        }
    }

    @Test func pricingIncludedResourceAppPrice() throws {
        let json = """
        {"type":"appPrices","id":"ap-1","attributes":{"startDate":"2025-01-01","manual":true}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCPricingIncludedResource.self, from: json)
        if case .appPrice(let p) = included {
            #expect(p.attributes?.manual == true)
        } else {
            Issue.record("Expected appPrice")
        }
    }
}
