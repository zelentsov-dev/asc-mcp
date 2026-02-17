import Testing
import Foundation
@testable import asc_mcp

@Suite("AppStoreVersion Model Tests")
struct AppStoreVersionModelTests {
    @Test func decodeVersion() throws {
        let json = """
        {"id":"v1","type":"appStoreVersions","attributes":{"platform":"IOS","versionString":"2.0","appStoreState":"PREPARE_FOR_SUBMISSION","downloadable":true,"createdDate":"2025-01-01T00:00:00Z"}}
        """.data(using: .utf8)!
        let version = try JSONDecoder().decode(ASCAppStoreVersion.self, from: json)
        #expect(version.id == "v1")
        #expect(version.attributes?.platform == "IOS")
        #expect(version.attributes?.versionString == "2.0")
        #expect(version.attributes?.appStoreState == "PREPARE_FOR_SUBMISSION")
        #expect(version.attributes?.downloadable == true)
        #expect(version.attributes?.createdDate == "2025-01-01T00:00:00Z")
    }

    @Test func versionConvenienceExtension() throws {
        let json = """
        {"id":"v1","type":"appStoreVersions","attributes":{"versionString":"3.0","appStoreState":"READY_FOR_SALE","platform":"IOS","downloadable":true}}
        """.data(using: .utf8)!
        let v = try JSONDecoder().decode(ASCAppStoreVersion.self, from: json)
        #expect(v.version == "3.0")
        #expect(v.state == "READY_FOR_SALE")
        #expect(v.platform == "IOS")
        #expect(v.isDownloadable == true)
    }

    @Test func versionConvenienceFallbacks() throws {
        let json = """
        {"id":"v1","type":"appStoreVersions"}
        """.data(using: .utf8)!
        let v = try JSONDecoder().decode(ASCAppStoreVersion.self, from: json)
        #expect(v.version == "Unknown")
        #expect(v.state == "Unknown")
        #expect(v.platform == "IOS")
        #expect(v.isDownloadable == false)
    }

    @Test func dataTypeSingle() throws {
        let json = """
        {"links":{},"data":{"id":"x","type":"builds"}}
        """.data(using: .utf8)!
        let rel = try JSONDecoder().decode(ASCAppStoreVersion.Relationship.self, from: json)
        if case .single(let res) = rel.data {
            #expect(res.id == "x")
            #expect(res.type == "builds")
        } else {
            Issue.record("Expected single data type")
        }
    }

    @Test func dataTypeMultiple() throws {
        let json = """
        {"links":{},"data":[{"id":"a","type":"localizations"},{"id":"b","type":"localizations"}]}
        """.data(using: .utf8)!
        let rel = try JSONDecoder().decode(ASCAppStoreVersion.Relationship.self, from: json)
        if case .multiple(let items) = rel.data {
            #expect(items.count == 2)
            #expect(items[0].id == "a")
            #expect(items[1].id == "b")
        } else {
            Issue.record("Expected multiple data type")
        }
    }

    @Test func dataTypeNullData() throws {
        let json = """
        {"links":{"related":"https://api.example.com/rel"}}
        """.data(using: .utf8)!
        let rel = try JSONDecoder().decode(ASCAppStoreVersion.Relationship.self, from: json)
        #expect(rel.data == nil)
        #expect(rel.links?.related == "https://api.example.com/rel")
    }

    @Test func versionsResponseDecode() throws {
        let json = """
        {"data":[{"id":"v1","type":"appStoreVersions","attributes":{"versionString":"1.0"}}],"links":{"self":"https://api.example.com/versions"},"meta":{"paging":{"total":1,"limit":10}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppStoreVersionsResponse.self, from: json)
        #expect(response.data.count == 1)
        #expect(response.data[0].version == "1.0")
    }

    @Test func singleVersionResponseDecode() throws {
        let json = """
        {"data":{"id":"v1","type":"appStoreVersions","attributes":{"versionString":"1.0"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppStoreVersionResponse.self, from: json)
        #expect(response.data.id == "v1")
    }

    @Test func dataTypeSingleRoundtrip() throws {
        let original = ASCAppStoreVersion.Relationship.DataType.single(
            ASCAppStoreVersion.ResourceIdentifier(id: "test", type: "builds")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ASCAppStoreVersion.Relationship.DataType.self, from: data)
        if case .single(let res) = decoded {
            #expect(res.id == "test")
            #expect(res.type == "builds")
        } else {
            Issue.record("Roundtrip failed for single DataType")
        }
    }

    @Test func dataTypeMultipleRoundtrip() throws {
        let items = [
            ASCAppStoreVersion.ResourceIdentifier(id: "a", type: "t"),
            ASCAppStoreVersion.ResourceIdentifier(id: "b", type: "t")
        ]
        let original = ASCAppStoreVersion.Relationship.DataType.multiple(items)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ASCAppStoreVersion.Relationship.DataType.self, from: data)
        if case .multiple(let decodedItems) = decoded {
            #expect(decodedItems.count == 2)
            #expect(decodedItems[0].id == "a")
            #expect(decodedItems[1].id == "b")
        } else {
            Issue.record("Roundtrip failed for multiple DataType")
        }
    }

    @Test func versionWithRelationships() throws {
        let json = """
        {"id":"v1","type":"appStoreVersions","attributes":{"versionString":"1.0"},"relationships":{"build":{"data":{"id":"b1","type":"builds"}}}}
        """.data(using: .utf8)!
        let version = try JSONDecoder().decode(ASCAppStoreVersion.self, from: json)
        #expect(version.relationships != nil)
        if case .single(let buildRef) = version.relationships?.build?.data {
            #expect(buildRef.id == "b1")
        } else {
            Issue.record("Expected single build relationship")
        }
    }

    @Test func versionMinimalDecode() throws {
        let json = """
        {"id":"v-min","type":"appStoreVersions"}
        """.data(using: .utf8)!
        let version = try JSONDecoder().decode(ASCAppStoreVersion.self, from: json)
        #expect(version.id == "v-min")
        #expect(version.attributes == nil)
        #expect(version.relationships == nil)
    }
}
