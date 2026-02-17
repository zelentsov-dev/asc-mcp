import Testing
import Foundation
@testable import asc_mcp

@Suite("InAppPurchase Model Tests")
struct InAppPurchaseModelTests {
    @Test func decodeIAP() throws {
        let json = """
        {"type":"inAppPurchases","id":"iap-1","attributes":{"name":"Premium","productId":"com.test.premium","inAppPurchaseType":"NON_CONSUMABLE","state":"APPROVED","familySharable":true}}
        """.data(using: .utf8)!
        let iap = try JSONDecoder().decode(ASCInAppPurchaseV2.self, from: json)
        #expect(iap.id == "iap-1")
        #expect(iap.attributes.name == "Premium")
        #expect(iap.attributes.inAppPurchaseType == "NON_CONSUMABLE")
    }

    @Test func iapLocalization() throws {
        let json = """
        {"type":"inAppPurchaseLocalizations","id":"iapl-1","attributes":{"locale":"en-US","name":"Premium Upgrade","description":"Get all features"}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCInAppPurchaseLocalization.self, from: json)
        #expect(loc.attributes.locale == "en-US")
        #expect(loc.attributes.name == "Premium Upgrade")
    }

    @Test func subscriptionGroup() throws {
        let json = """
        {"type":"subscriptionGroups","id":"sg-1","attributes":{"referenceName":"Premium Plans"}}
        """.data(using: .utf8)!
        let group = try JSONDecoder().decode(ASCSubscriptionGroup.self, from: json)
        #expect(group.attributes.referenceName == "Premium Plans")
    }

    @Test func createIAPRequest() throws {
        let request = CreateInAppPurchaseV2Request(data: .init(
            attributes: .init(name: "Test", productId: "com.test.item", inAppPurchaseType: "CONSUMABLE", reviewNote: nil, familySharable: nil),
            relationships: .init(app: .init(data: ASCResourceIdentifier(type: "apps", id: "app-1")))
        ))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateInAppPurchaseV2Request.self, from: data)
        #expect(decoded.data.attributes.productId == "com.test.item")
    }

    @Test func updateIAPRequest() throws {
        let request = UpdateInAppPurchaseV2Request(data: .init(id: "iap-1", attributes: .init(name: "Updated", reviewNote: "New note", familySharable: true)))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateInAppPurchaseV2Request.self, from: data)
        #expect(decoded.data.id == "iap-1")
        #expect(decoded.data.attributes.name == "Updated")
    }

    @Test func iapResponseSingle() throws {
        let json = """
        {"data":{"type":"inAppPurchases","id":"iap-1","attributes":{"name":"Test","productId":"com.test","inAppPurchaseType":"NON_CONSUMABLE","state":"APPROVED"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCInAppPurchaseV2Response.self, from: json)
        #expect(response.data.id == "iap-1")
    }

    @Test func iapResponseList() throws {
        let json = """
        {"data":[{"type":"inAppPurchases","id":"i1","attributes":{"name":"A","productId":"p1","inAppPurchaseType":"CONSUMABLE"}},{"type":"inAppPurchases","id":"i2","attributes":{"name":"B","productId":"p2","inAppPurchaseType":"NON_CONSUMABLE"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCInAppPurchasesV2Response.self, from: json)
        #expect(response.data.count == 2)
    }
}
