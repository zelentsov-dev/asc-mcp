import Testing
import Foundation
@testable import asc_mcp

@Suite("App Model Tests")
struct AppModelTests {
    let appJSON = """
    {"id":"app-1","type":"apps","attributes":{"name":"My App","bundleId":"com.test","sku":"SKU1","primaryLocale":"en-US","isOrEverWasMadeForKids":false,"availableInNewTerritories":true}}
    """.data(using: .utf8)!

    @Test func decodeApp() throws {
        let app = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        #expect(app.id == "app-1")
        #expect(app.type == "apps")
    }

    @Test func appAttributes() throws {
        let app = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        #expect(app.attributes?.name == "My App")
        #expect(app.attributes?.bundleId == "com.test")
        #expect(app.attributes?.sku == "SKU1")
        #expect(app.attributes?.primaryLocale == "en-US")
        #expect(app.attributes?.isOrEverWasMadeForKids == false)
        #expect(app.attributes?.availableInNewTerritories == true)
    }

    @Test func appDisplayNameExtension() throws {
        let app = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        #expect(app.displayName == "My App")
    }

    @Test func appDisplayNameFallback() throws {
        let json = """
        {"id":"x","type":"apps"}
        """.data(using: .utf8)!
        let app = try JSONDecoder().decode(ASCApp.self, from: json)
        #expect(app.displayName == "Unknown App")
    }

    @Test func bundleIdentifierExtension() throws {
        let app = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        #expect(app.bundleIdentifier == "com.test")
    }

    @Test func bundleIdentifierFallback() throws {
        let json = """
        {"id":"x","type":"apps"}
        """.data(using: .utf8)!
        let app = try JSONDecoder().decode(ASCApp.self, from: json)
        #expect(app.bundleIdentifier == "Unknown Bundle ID")
    }

    @Test func appSKUExtension() throws {
        let app = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        #expect(app.appSKU == "SKU1")
    }

    @Test func appSKUFallback() throws {
        let json = """
        {"id":"x","type":"apps"}
        """.data(using: .utf8)!
        let app = try JSONDecoder().decode(ASCApp.self, from: json)
        #expect(app.appSKU == "Unknown SKU")
    }

    @Test func localeExtension() throws {
        let app = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        #expect(app.locale == "en-US")
    }

    @Test func localeFallback() throws {
        let json = """
        {"id":"x","type":"apps"}
        """.data(using: .utf8)!
        let app = try JSONDecoder().decode(ASCApp.self, from: json)
        #expect(app.locale == "en-US")
    }

    @Test func hashableEquality() throws {
        let a = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        let b = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func hashableInequality() throws {
        let a = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        let jsonB = """
        {"id":"app-2","type":"apps","attributes":{"name":"Other App"}}
        """.data(using: .utf8)!
        let b = try JSONDecoder().decode(ASCApp.self, from: jsonB)
        #expect(a != b)
    }

    @Test func appCanBeUsedInSet() throws {
        let a = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        let b = try JSONDecoder().decode(ASCApp.self, from: appJSON)
        let set: Set<ASCApp> = [a, b]
        #expect(set.count == 1)
    }

    @Test func appsResponseDecode() throws {
        let json = """
        {"data":[{"id":"a1","type":"apps","attributes":{"name":"One"}},{"id":"a2","type":"apps","attributes":{"name":"Two"}}],"links":{"self":"https://api.example.com/apps","next":"https://api.example.com/apps?page=2"},"meta":{"paging":{"total":5,"limit":2}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppsResponse.self, from: json)
        #expect(response.data.count == 2)
        #expect(response.totalCount == 5)
        #expect(response.hasNextPage == true)
    }

    @Test func appsResponseNoNextPage() throws {
        let json = """
        {"data":[],"links":{"self":"https://api.example.com/apps"},"meta":{"paging":{"total":0,"limit":10}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppsResponse.self, from: json)
        #expect(response.hasNextPage == false)
        #expect(response.totalCount == 0)
    }

    @Test func appsResponseWithoutMeta() throws {
        let json = """
        {"data":[{"id":"a1","type":"apps"}],"links":{"self":"https://api.example.com/apps"}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppsResponse.self, from: json)
        #expect(response.totalCount == 1)
        #expect(response.meta == nil)
    }

    @Test func appResponseSingle() throws {
        let json = """
        {"data":{"id":"app-1","type":"apps"},"links":{"self":"https://api.example.com/apps/app-1"}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppResponse.self, from: json)
        #expect(response.data.id == "app-1")
    }

    @Test func appMinimalDecode() throws {
        let json = """
        {"id":"minimal","type":"apps"}
        """.data(using: .utf8)!
        let app = try JSONDecoder().decode(ASCApp.self, from: json)
        #expect(app.id == "minimal")
        #expect(app.attributes == nil)
        #expect(app.relationships == nil)
    }
}
