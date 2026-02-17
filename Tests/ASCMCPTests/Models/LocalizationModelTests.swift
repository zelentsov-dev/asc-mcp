import Testing
import Foundation
@testable import asc_mcp

@Suite("Localization Model Tests")
struct LocalizationModelTests {
    @Test func decodeLocalization() throws {
        let json = """
        {"id":"loc-1","type":"appStoreVersionLocalizations","attributes":{"locale":"en-US","description":"Test desc","keywords":"a,b","whatsNew":"Fixes","promotionalText":"Promo","supportUrl":"https://s.com","marketingUrl":"https://m.com"}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCAppStoreVersionLocalization.self, from: json)
        #expect(loc.id == "loc-1")
        #expect(loc.type == "appStoreVersionLocalizations")
        #expect(loc.attributes?.locale == "en-US")
        #expect(loc.attributes?.description == "Test desc")
        #expect(loc.attributes?.keywords == "a,b")
        #expect(loc.attributes?.whatsNew == "Fixes")
        #expect(loc.attributes?.promotionalText == "Promo")
        #expect(loc.attributes?.supportUrl == "https://s.com")
        #expect(loc.attributes?.marketingUrl == "https://m.com")
    }

    @Test func localeConvenience() throws {
        let json = """
        {"id":"l","type":"appStoreVersionLocalizations","attributes":{"locale":"ru-RU","whatsNew":"Update","description":"Desc"}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCAppStoreVersionLocalization.self, from: json)
        #expect(loc.locale == "ru-RU")
        #expect(loc.hasWhatsNew == true)
        #expect(loc.hasDescription == true)
    }

    @Test func emptyWhatsNew() throws {
        let json = """
        {"id":"l","type":"appStoreVersionLocalizations","attributes":{"locale":"en-US","whatsNew":"","description":""}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCAppStoreVersionLocalization.self, from: json)
        #expect(loc.hasWhatsNew == false)
        #expect(loc.hasDescription == false)
    }

    @Test func nullWhatsNew() throws {
        let json = """
        {"id":"l","type":"appStoreVersionLocalizations","attributes":{"locale":"en-US"}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCAppStoreVersionLocalization.self, from: json)
        #expect(loc.hasWhatsNew == false)
        #expect(loc.hasDescription == false)
    }

    @Test func noAttributes() throws {
        let json = """
        {"id":"l","type":"appStoreVersionLocalizations"}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCAppStoreVersionLocalization.self, from: json)
        #expect(loc.locale == "Unknown")
        #expect(loc.hasWhatsNew == false)
        #expect(loc.hasDescription == false)
    }

    @Test func updateRequest() throws {
        let request = ASCAppStoreVersionLocalizationUpdateRequest(
            id: "loc-1",
            attributes: .init(description: "New desc", whatsNew: "New features", keywords: nil, promotionalText: nil, supportUrl: nil, marketingUrl: nil)
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let reqData = json?["data"] as? [String: Any]
        #expect(reqData?["id"] as? String == "loc-1")
        #expect(reqData?["type"] as? String == "appStoreVersionLocalizations")
        let attrs = reqData?["attributes"] as? [String: Any]
        #expect(attrs?["description"] as? String == "New desc")
        #expect(attrs?["whatsNew"] as? String == "New features")
    }

    @Test func updateRequestRoundtrip() throws {
        let request = ASCAppStoreVersionLocalizationUpdateRequest(
            id: "loc-1",
            attributes: .init(description: "Desc", whatsNew: "What's new", keywords: "key1,key2", promotionalText: "Promo", supportUrl: "https://support.com", marketingUrl: "https://marketing.com")
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ASCAppStoreVersionLocalizationUpdateRequest.self, from: data)
        #expect(decoded.data.id == "loc-1")
        #expect(decoded.data.attributes.whatsNew == "What's new")
        #expect(decoded.data.attributes.keywords == "key1,key2")
    }

    @Test func createRequest() throws {
        let request = CreateAppStoreVersionLocalizationRequest(
            versionId: "ver-1",
            attributes: .init(locale: "de-DE", description: "German", whatsNew: nil, keywords: nil, promotionalText: nil, supportUrl: nil, marketingUrl: nil)
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateAppStoreVersionLocalizationRequest.self, from: data)
        #expect(decoded.data.attributes.locale == "de-DE")
        #expect(decoded.data.attributes.description == "German")
        #expect(decoded.data.relationships.appStoreVersion.data.id == "ver-1")
    }

    @Test func localizationsResponseDecode() throws {
        let json = """
        {"data":[{"id":"l1","type":"appStoreVersionLocalizations","attributes":{"locale":"en-US"}},{"id":"l2","type":"appStoreVersionLocalizations","attributes":{"locale":"ru-RU"}}],"links":{"self":"https://api.example.com/locs"}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppStoreVersionLocalizationsResponse.self, from: json)
        #expect(response.data.count == 2)
        #expect(response.data[0].locale == "en-US")
        #expect(response.data[1].locale == "ru-RU")
    }

    @Test func localizationResponseSingle() throws {
        let json = """
        {"data":{"id":"l1","type":"appStoreVersionLocalizations","attributes":{"locale":"en-US","whatsNew":"Bug fixes"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppStoreVersionLocalizationResponse.self, from: json)
        #expect(response.data.id == "l1")
        #expect(response.data.attributes?.whatsNew == "Bug fixes")
    }
}
