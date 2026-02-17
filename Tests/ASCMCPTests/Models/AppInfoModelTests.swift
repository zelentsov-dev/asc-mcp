import Testing
import Foundation
@testable import asc_mcp

@Suite("AppInfo Model Tests")
struct AppInfoModelTests {
    @Test func decodeAppInfo() throws {
        let json = """
        {"type":"appInfos","id":"ai-1","attributes":{"appStoreState":"READY_FOR_SALE","appStoreAgeRating":"FOUR_PLUS","state":"ACCEPTED"}}
        """.data(using: .utf8)!
        let info = try JSONDecoder().decode(ASCAppInfo.self, from: json)
        #expect(info.id == "ai-1")
        #expect(info.attributes?.appStoreAgeRating == "FOUR_PLUS")
    }

    @Test func appInfoLocalization() throws {
        let json = """
        {"type":"appInfoLocalizations","id":"ail-1","attributes":{"locale":"en-US","name":"My App","subtitle":"Best app ever"}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCAppInfoLocalization.self, from: json)
        #expect(loc.attributes?.name == "My App")
        #expect(loc.attributes?.subtitle == "Best app ever")
    }

    @Test func appCategory() throws {
        let json = """
        {"type":"appCategories","id":"cat-1","attributes":{"platforms":["IOS","MAC_OS"]}}
        """.data(using: .utf8)!
        let cat = try JSONDecoder().decode(ASCAppCategory.self, from: json)
        #expect(cat.attributes?.platforms == ["IOS", "MAC_OS"])
    }

    @Test func appInfoIncludedCategory() throws {
        let json = """
        {"type":"appCategories","id":"cat-1","attributes":{"platforms":["IOS"]}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCAppInfoIncludedResource.self, from: json)
        if case .appCategory(let cat) = included {
            #expect(cat.id == "cat-1")
        } else {
            Issue.record("Expected appCategory")
        }
    }

    @Test func appInfoIncludedLocalization() throws {
        let json = """
        {"type":"appInfoLocalizations","id":"ail-1","attributes":{"locale":"en-US"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCAppInfoIncludedResource.self, from: json)
        if case .appInfoLocalization(let loc) = included {
            #expect(loc.id == "ail-1")
        } else {
            Issue.record("Expected appInfoLocalization")
        }
    }

    @Test func updateAppInfoRequest() throws {
        let request = UpdateAppInfoRequest(data: .init(
            id: "ai-1",
            relationships: .init(
                primaryCategory: .init(data: ASCResourceIdentifier(type: "appCategories", id: "cat-1")),
                primarySubcategoryOne: nil,
                primarySubcategoryTwo: nil,
                secondaryCategory: nil,
                secondarySubcategoryOne: nil,
                secondarySubcategoryTwo: nil
            )
        ))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateAppInfoRequest.self, from: data)
        #expect(decoded.data.id == "ai-1")
    }
}
