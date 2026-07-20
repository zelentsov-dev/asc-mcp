import Testing
import Foundation
@testable import asc_mcp

@Suite("AppEvent Model Tests")
struct AppEventModelTests {
    @Test func decodeAppEvent() throws {
        let json = """
        {"type":"appEvents","id":"evt-1","attributes":{"referenceName":"Sale","badge":"LIVE_EVENT","primaryLocale":"en-US","priority":"HIGH","eventState":"ACCEPTED","territorySchedules":[{"territories":["USA"],"publishStart":"2025-06-01T00:00:00Z","eventStart":"2025-06-15T00:00:00Z","eventEnd":"2025-06-30T00:00:00Z"}]},"relationships":{"localizations":{"data":[{"type":"appEventLocalizations","id":"evtl-1"}]}}}
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(ASCAppEvent.self, from: json)
        #expect(event.id == "evt-1")
        #expect(event.attributes?.referenceName == "Sale")
        #expect(event.attributes?.primaryLocale == "en-US")
        #expect(event.attributes?.priority == "HIGH")
        #expect(event.attributes?.territorySchedules?.count == 1)
        #expect(event.relationships?.localizations?.data?.map(\.id) == ["evtl-1"])
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

    @Test func appEventIncludedUnknownIsForwardCompatible() throws {
        let json = """
        {"type":"unknownType","id":"x","attributes":{}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCAppEventIncludedResource.self, from: json)
        if case .unknown = included {
            #expect(Bool(true))
        } else {
            Issue.record("Expected unknown included resource")
        }
    }

    @Test func createAppEventRequest() throws {
        let request = CreateAppEventRequest(data: .init(
            attributes: .init(
                referenceName: "New Event",
                badge: nil,
                deepLink: nil,
                purchaseRequirement: nil,
                primaryLocale: .value("en-US"),
                priority: .value("NORMAL"),
                purpose: nil,
                territorySchedules: nil
            ),
            relationships: .init(app: .init(data: ASCResourceIdentifier(type: "apps", id: "app-1")))
        ))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateAppEventRequest.self, from: data)
        #expect(decoded.data.attributes.referenceName == "New Event")
    }

    @Test func nullableAppEventAttributesEncodeExplicitNull() throws {
        let request = UpdateAppEventRequest(data: .init(
            id: "evt-1",
            attributes: .init(
                referenceName: .null,
                badge: nil,
                deepLink: .null,
                purchaseRequirement: nil,
                primaryLocale: nil,
                priority: nil,
                purpose: nil,
                territorySchedules: .value([])
            )
        ))
        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let resource = try #require(object["data"] as? [String: Any])
        let attributes = try #require(resource["attributes"] as? [String: Any])

        #expect(attributes["referenceName"] is NSNull)
        #expect(attributes["deepLink"] is NSNull)
        #expect((attributes["territorySchedules"] as? [Any])?.isEmpty == true)
    }
}
