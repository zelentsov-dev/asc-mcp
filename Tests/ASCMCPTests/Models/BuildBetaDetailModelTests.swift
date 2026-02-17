import Testing
import Foundation
@testable import asc_mcp

@Suite("BuildBetaDetail Model Tests")
struct BuildBetaDetailModelTests {
    @Test func decodeBetaDetail() throws {
        let json = """
        {"type":"buildBetaDetails","id":"bbd-1","attributes":{"autoNotifyEnabled":true,"internalBuildState":"PROCESSING","externalBuildState":"IN_BETA_TESTING"}}
        """.data(using: .utf8)!
        let detail = try JSONDecoder().decode(ASCBuildBetaDetail.self, from: json)
        #expect(detail.id == "bbd-1")
        #expect(detail.type == "buildBetaDetails")
        #expect(detail.attributes.autoNotifyEnabled == true)
        #expect(detail.attributes.internalBuildState == "PROCESSING")
        #expect(detail.attributes.externalBuildState == "IN_BETA_TESTING")
    }

    @Test func decodeBetaDetailMinimal() throws {
        let json = """
        {"type":"buildBetaDetails","id":"bbd-2","attributes":{}}
        """.data(using: .utf8)!
        let detail = try JSONDecoder().decode(ASCBuildBetaDetail.self, from: json)
        #expect(detail.id == "bbd-2")
        #expect(detail.attributes.autoNotifyEnabled == nil)
        #expect(detail.attributes.internalBuildState == nil)
        #expect(detail.attributes.externalBuildState == nil)
    }

    @Test func betaBuildLocalization() throws {
        let json = """
        {"type":"betaBuildLocalizations","id":"bbl-1","attributes":{"locale":"en-US","whatsNew":"Beta fixes"}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCBetaBuildLocalization.self, from: json)
        #expect(loc.id == "bbl-1")
        #expect(loc.type == "betaBuildLocalizations")
        #expect(loc.attributes.locale == "en-US")
        #expect(loc.attributes.whatsNew == "Beta fixes")
    }

    @Test func betaBuildLocalizationFullAttributes() throws {
        let json = """
        {"type":"betaBuildLocalizations","id":"bbl-2","attributes":{"locale":"de-DE","whatsNew":"Neue Features","feedbackEmail":"fb@test.com","marketingUrl":"https://marketing.com","privacyPolicyUrl":"https://privacy.com"}}
        """.data(using: .utf8)!
        let loc = try JSONDecoder().decode(ASCBetaBuildLocalization.self, from: json)
        #expect(loc.attributes.locale == "de-DE")
        #expect(loc.attributes.feedbackEmail == "fb@test.com")
        #expect(loc.attributes.marketingUrl == "https://marketing.com")
        #expect(loc.attributes.privacyPolicyUrl == "https://privacy.com")
    }

    @Test func betaGroup() throws {
        let json = """
        {"type":"betaGroups","id":"bg-1","attributes":{"name":"Internal Testers","isInternalGroup":true,"publicLinkEnabled":false}}
        """.data(using: .utf8)!
        let group = try JSONDecoder().decode(ASCBetaGroup.self, from: json)
        #expect(group.id == "bg-1")
        #expect(group.type == "betaGroups")
        #expect(group.attributes.name == "Internal Testers")
        #expect(group.attributes.isInternalGroup == true)
        #expect(group.attributes.publicLinkEnabled == false)
    }

    @Test func betaGroupFullAttributes() throws {
        let json = """
        {"type":"betaGroups","id":"bg-2","attributes":{"name":"External","isInternalGroup":false,"hasAccessToAllBuilds":true,"publicLinkEnabled":true,"publicLinkLimit":100,"publicLinkLimitEnabled":true,"feedbackEnabled":true}}
        """.data(using: .utf8)!
        let group = try JSONDecoder().decode(ASCBetaGroup.self, from: json)
        #expect(group.attributes.hasAccessToAllBuilds == true)
        #expect(group.attributes.publicLinkLimit == 100)
        #expect(group.attributes.publicLinkLimitEnabled == true)
        #expect(group.attributes.feedbackEnabled == true)
    }

    @Test func betaTester() throws {
        let json = """
        {"type":"betaTesters","id":"bt-1","attributes":{"email":"test@test.com","firstName":"John","lastName":"Doe","state":"ACCEPTED"}}
        """.data(using: .utf8)!
        let tester = try JSONDecoder().decode(ASCBetaTester.self, from: json)
        #expect(tester.id == "bt-1")
        #expect(tester.type == "betaTesters")
        #expect(tester.attributes.email == "test@test.com")
        #expect(tester.attributes.firstName == "John")
        #expect(tester.attributes.lastName == "Doe")
        #expect(tester.attributes.state == "ACCEPTED")
    }

    @Test func betaTesterMinimalAttributes() throws {
        let json = """
        {"type":"betaTesters","id":"bt-2","attributes":{}}
        """.data(using: .utf8)!
        let tester = try JSONDecoder().decode(ASCBetaTester.self, from: json)
        #expect(tester.attributes.email == nil)
        #expect(tester.attributes.firstName == nil)
        #expect(tester.attributes.state == nil)
    }

    @Test func betaIncludedResourceBuild() throws {
        let json = """
        {"type":"builds","id":"b-1","attributes":{"version":"1"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCBetaIncludedResource.self, from: json)
        if case .build(let b) = included {
            #expect(b.id == "b-1")
            #expect(b.attributes.version == "1")
        } else {
            Issue.record("Expected build")
        }
    }

    @Test func betaIncludedResourceLocalization() throws {
        let json = """
        {"type":"betaBuildLocalizations","id":"bbl-1","attributes":{"locale":"en-US","whatsNew":"Test"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCBetaIncludedResource.self, from: json)
        if case .betaBuildLocalization(let loc) = included {
            #expect(loc.id == "bbl-1")
            #expect(loc.attributes.locale == "en-US")
        } else {
            Issue.record("Expected localization")
        }
    }

    @Test func betaIncludedResourceApp() throws {
        let json = """
        {"type":"apps","id":"app-1","attributes":{"name":"TestApp"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCBetaIncludedResource.self, from: json)
        if case .app(let app) = included {
            #expect(app.id == "app-1")
            #expect(app.attributes?.name == "TestApp")
        } else {
            Issue.record("Expected app")
        }
    }

    @Test func betaIncludedResourceUnknownType() {
        let json = """
        {"type":"unknownType","id":"u-1","attributes":{}}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ASCBetaIncludedResource.self, from: json)
        }
    }

    @Test func betaGroupsResponse() throws {
        let json = """
        {"data":[{"type":"betaGroups","id":"bg-1","attributes":{"name":"G1"}},{"type":"betaGroups","id":"bg-2","attributes":{"name":"G2"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCBetaGroupsResponse.self, from: json)
        #expect(response.data.count == 2)
        #expect(response.data[0].attributes.name == "G1")
    }

    @Test func betaTestersResponse() throws {
        let json = """
        {"data":[{"type":"betaTesters","id":"bt-1","attributes":{"email":"a@b.com"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCBetaTestersResponse.self, from: json)
        #expect(response.data.count == 1)
        #expect(response.data[0].attributes.email == "a@b.com")
    }

    @Test func buildBetaDetailResponse() throws {
        let json = """
        {"data":{"type":"buildBetaDetails","id":"bbd-1","attributes":{"autoNotifyEnabled":false}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCBuildBetaDetailResponse.self, from: json)
        #expect(response.data.id == "bbd-1")
        #expect(response.data.attributes.autoNotifyEnabled == false)
    }
}
