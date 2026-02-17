import Testing
import Foundation
@testable import asc_mcp

@Suite("AppEvent Model Tests")
struct AppEventModelTests {
    @Test func decodeAppEvent() throws {
        let json = """
        {"type":"appEvents","id":"evt-1","attributes":{"referenceName":"Sale","badge":"LIVE_EVENT","eventState":"ACCEPTED","territorySchedules":[{"territories":["USA"],"publishStart":"2025-06-01T00:00:00Z","eventStart":"2025-06-15T00:00:00Z","eventEnd":"2025-06-30T00:00:00Z"}]}}
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(ASCAppEvent.self, from: json)
        #expect(event.id == "evt-1")
        #expect(event.attributes?.referenceName == "Sale")
        #expect(event.attributes?.territorySchedules?.count == 1)
    }

    @Test func appEventLocalization() throws {
        let json = """
        {"type":"appEventLocalizations","id":"evtl-1","attributes":{"locale":"en-US","name":"Summer Sale","shortDescription":"Big discounts","longDescription":"All items 50% off"}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCAppEventLocalization.self, from: json)
        #expect(loc.attributes?.name == "Summer Sale")
    }

    @Test func appEventIncludedLocalization() throws {
        let json = """
        {"type":"appEventLocalizations","id":"evtl-1","attributes":{"locale":"en-US","name":"Test"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCAppEventIncludedResource.self, from: json)
        if case .localization(let loc) = included {
            #expect(loc.id == "evtl-1")
        } else {
            Issue.record("Expected localization")
        }
    }

    @Test func appEventIncludedUnknown() {
        let json = """
        {"type":"unknownType","id":"x","attributes":{}}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ASCAppEventIncludedResource.self, from: json)
        }
    }

    @Test func createAppEventRequest() throws {
        let request = CreateAppEventRequest(data: .init(
            attributes: .init(referenceName: "New Event", badge: nil, deepLink: nil, purchaseRequirement: nil, purpose: nil, territorySchedules: nil),
            relationships: .init(app: .init(data: ASCResourceIdentifier(type: "apps", id: "app-1")))
        ))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateAppEventRequest.self, from: data)
        #expect(decoded.data.attributes.referenceName == "New Event")
    }
}
