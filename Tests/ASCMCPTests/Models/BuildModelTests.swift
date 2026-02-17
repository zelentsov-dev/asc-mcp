import Testing
import Foundation
@testable import asc_mcp

@Suite("Build Model Tests")
struct BuildModelTests {
    @Test func decodeBuild() throws {
        let json = """
        {"type":"builds","id":"b1","attributes":{"version":"42","uploadedDate":"2025-01-10T08:00:00Z","processingState":"VALID","buildAudienceType":"APP_STORE_ELIGIBLE","usesNonExemptEncryption":false}}
        """.data(using: .utf8)!
        let build = try JSONDecoder().decode(ASCBuild.self, from: json)
        #expect(build.id == "b1")
        #expect(build.type == "builds")
        #expect(build.attributes.version == "42")
        #expect(build.attributes.uploadedDate == "2025-01-10T08:00:00Z")
        #expect(build.attributes.processingState == "VALID")
        #expect(build.attributes.buildAudienceType == "APP_STORE_ELIGIBLE")
        #expect(build.attributes.usesNonExemptEncryption == false)
    }

    @Test func buildAttributesOptional() throws {
        let json = """
        {"type":"builds","id":"b1","attributes":{"version":"1","expired":true,"minOsVersion":"17.0","buildAudienceType":"INTERNAL_ONLY"}}
        """.data(using: .utf8)!
        let build = try JSONDecoder().decode(ASCBuild.self, from: json)
        #expect(build.attributes.expired == true)
        #expect(build.attributes.minOsVersion == "17.0")
        #expect(build.attributes.buildAudienceType == "INTERNAL_ONLY")
        #expect(build.attributes.uploadedDate == nil)
    }

    @Test func buildMinimalAttributes() throws {
        let json = """
        {"type":"builds","id":"b1","attributes":{}}
        """.data(using: .utf8)!
        let build = try JSONDecoder().decode(ASCBuild.self, from: json)
        #expect(build.id == "b1")
        #expect(build.attributes.version == nil)
        #expect(build.attributes.expired == nil)
        #expect(build.attributes.processingState == nil)
    }

    @Test func buildResponse() throws {
        let json = """
        {"data":{"type":"builds","id":"b1","attributes":{"version":"1"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCBuildResponse.self, from: json)
        #expect(response.data.id == "b1")
        #expect(response.data.attributes.version == "1")
    }

    @Test func buildsResponse() throws {
        let json = """
        {"data":[{"type":"builds","id":"b1","attributes":{"version":"1"}},{"type":"builds","id":"b2","attributes":{"version":"2"}}],"links":{"self":"https://api.example.com/builds","next":"https://api.example.com/builds?page=2"}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCBuildsResponse.self, from: json)
        #expect(response.data.count == 2)
        #expect(response.data[0].id == "b1")
        #expect(response.data[1].id == "b2")
        #expect(response.links?.next != nil)
    }

    @Test func buildsResponseNoNextPage() throws {
        let json = """
        {"data":[{"type":"builds","id":"b1","attributes":{"version":"1"}}],"links":{"self":"https://api.example.com/builds"}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCBuildsResponse.self, from: json)
        #expect(response.data.count == 1)
        #expect(response.links?.next == nil)
    }

    @Test func pagedDocumentLinks() throws {
        let json = """
        {"self":"https://api.example.com/resource","first":"https://api.example.com/resource?page=1","next":"https://api.example.com/resource?page=2"}
        """.data(using: .utf8)!
        let links = try JSONDecoder().decode(ASCPagedDocumentLinks.self, from: json)
        #expect(links.first != nil)
        #expect(links.next != nil)
        #expect(links.`self` == "https://api.example.com/resource")
    }

    @Test func pagedDocumentLinksMinimal() throws {
        let json = """
        {"self":"https://api.example.com/resource"}
        """.data(using: .utf8)!
        let links = try JSONDecoder().decode(ASCPagedDocumentLinks.self, from: json)
        #expect(links.first == nil)
        #expect(links.next == nil)
    }

    @Test func resourceIdentifier() throws {
        let json = """
        {"type":"builds","id":"b-123"}
        """.data(using: .utf8)!
        let id = try JSONDecoder().decode(ASCResourceIdentifier.self, from: json)
        #expect(id.type == "builds")
        #expect(id.id == "b-123")
    }

    @Test func buildIncludedApp() throws {
        let json = """
        {"type":"apps","id":"app-1","attributes":{"name":"Test","bundleId":"com.test","sku":"SK","primaryLocale":"en-US"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCBuildIncludedResource.self, from: json)
        if case .app(let app) = included {
            #expect(app.id == "app-1")
            #expect(app.attributes?.name == "Test")
            #expect(app.attributes?.bundleId == "com.test")
        } else {
            Issue.record("Expected app included resource")
        }
    }

    @Test func buildIncludedPreReleaseVersion() throws {
        let json = """
        {"type":"preReleaseVersions","id":"prv-1","attributes":{"version":"1.0","platform":"IOS"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCBuildIncludedResource.self, from: json)
        if case .preReleaseVersion(let v) = included {
            #expect(v.id == "prv-1")
            #expect(v.attributes.version == "1.0")
            #expect(v.attributes.platform == "IOS")
        } else {
            Issue.record("Expected preReleaseVersion")
        }
    }

    @Test func buildIncludedBuildBetaDetail() throws {
        let json = """
        {"type":"buildBetaDetails","id":"bbd-1","attributes":{"autoNotifyEnabled":true,"internalBuildState":"PROCESSING"}}
        """.data(using: .utf8)!
        let included = try JSONDecoder().decode(ASCBuildIncludedResource.self, from: json)
        if case .buildBetaDetail(let detail) = included {
            #expect(detail.id == "bbd-1")
            #expect(detail.attributes.autoNotifyEnabled == true)
        } else {
            Issue.record("Expected buildBetaDetail")
        }
    }

    @Test func buildIncludedUnknownType() {
        let json = """
        {"type":"unknownType","id":"u-1","attributes":{}}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ASCBuildIncludedResource.self, from: json)
        }
    }

    @Test func buildWithRelationships() throws {
        let json = """
        {"type":"builds","id":"b1","attributes":{"version":"1"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}},"preReleaseVersion":{"data":{"type":"preReleaseVersions","id":"prv-1"}}}}
        """.data(using: .utf8)!
        let build = try JSONDecoder().decode(ASCBuild.self, from: json)
        #expect(build.relationships?.app?.data?.id == "app-1")
        #expect(build.relationships?.preReleaseVersion?.data?.id == "prv-1")
    }
}
