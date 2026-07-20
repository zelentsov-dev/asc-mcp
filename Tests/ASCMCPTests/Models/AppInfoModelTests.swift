import Testing
import Foundation
@testable import asc_mcp

@Suite("AppInfo Model Tests")
struct AppInfoModelTests {
    @Test func decodeAppInfo() throws {
        let json = """
        {"type":"appInfos","id":"ai-1","attributes":{"appStoreState":"READY_FOR_SALE","appStoreAgeRating":"FOUR_PLUS","australiaAgeRating":"FIFTEEN","franceAgeRating":"EIGHTEEN","koreaAgeRating":"FIFTEEN","state":"ACCEPTED"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}},"ageRatingDeclaration":{"data":{"type":"ageRatingDeclarations","id":"age-1"}},"appInfoLocalizations":{"data":[{"type":"appInfoLocalizations","id":"loc-1"}]},"territoryAgeRatings":{"data":[{"type":"territoryAgeRatings","id":"rating-1"}]}}}
        """.data(using: .utf8)!
        let info = try JSONDecoder().decode(ASCAppInfo.self, from: json)
        #expect(info.id == "ai-1")
        #expect(info.attributes?.appStoreAgeRating == "FOUR_PLUS")
        #expect(info.attributes?.australiaAgeRating == "FIFTEEN")
        #expect(info.attributes?.franceAgeRating == "EIGHTEEN")
        #expect(info.attributes?.koreaAgeRating == "FIFTEEN")
        #expect(info.relationships?.app?.data?.id == "app-1")
        #expect(info.relationships?.ageRatingDeclaration?.data?.id == "age-1")
        #expect(info.relationships?.appInfoLocalizations?.data?.map(\.id) == ["loc-1"])
        #expect(info.relationships?.territoryAgeRatings?.data?.map(\.id) == ["rating-1"])
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

    @Test func appInfoIncludedCurrentResourcesAndUnknownFallback() throws {
        let json = """
        [
          {"type":"apps","id":"app-1","attributes":{"name":"Example"}},
          {"type":"ageRatingDeclarations","id":"age-1","attributes":{"gambling":true}},
          {"type":"futureResources","id":"future-1","attributes":{"enabled":true}}
        ]
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode([ASCAppInfoIncludedResource].self, from: json)

        if case .app(let app) = included[0] {
            #expect(app.id == "app-1")
        } else {
            Issue.record("Expected app")
        }
        if case .ageRatingDeclaration(let declaration) = included[1] {
            #expect(declaration.id == "age-1")
        } else {
            Issue.record("Expected age rating declaration")
        }
        if case .unknown = included[2] {
            #expect(Bool(true))
        } else {
            Issue.record("Expected forward-compatible unknown resource")
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
