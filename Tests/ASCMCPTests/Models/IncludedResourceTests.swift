import Testing
import Foundation
@testable import asc_mcp

@Suite("IncludedResource Tests")
struct IncludedResourceTests {
    @Test func decodeLocalization() throws {
        let json = """
        {"id":"loc-1","type":"appStoreVersionLocalizations","attributes":{"locale":"en-US"}}
        """.data(using: .utf8)!
        let resource = try JSONDecoder().decode(IncludedResource.self, from: json)
        if case .appStoreVersionLocalization(let loc) = resource {
            #expect(loc.id == "loc-1")
        } else {
            Issue.record("Expected localization")
        }
    }

    @Test func decodeScreenshotSet() throws {
        let json = """
        {"id":"ss-1","type":"appScreenshotSets","attributes":{"screenshotDisplayType":"APP_IPHONE_67"}}
        """.data(using: .utf8)!
        let resource = try JSONDecoder().decode(IncludedResource.self, from: json)
        if case .appScreenshotSet(let set) = resource {
            #expect(set.id == "ss-1")
        } else {
            Issue.record("Expected screenshot set")
        }
    }

    @Test func decodeScreenshot() throws {
        let json = """
        {"id":"s-1","type":"appScreenshots","attributes":{"fileSize":1024,"fileName":"screenshot.png"}}
        """.data(using: .utf8)!
        let resource = try JSONDecoder().decode(IncludedResource.self, from: json)
        if case .appScreenshot(let s) = resource {
            #expect(s.attributes?.fileSize == 1024)
        } else {
            Issue.record("Expected screenshot")
        }
    }

    @Test func decodePreviewSet() throws {
        let json = """
        {"id":"ps-1","type":"appPreviewSets","attributes":{"previewType":"IPHONE_67"}}
        """.data(using: .utf8)!
        let resource = try JSONDecoder().decode(IncludedResource.self, from: json)
        if case .appPreviewSet(let ps) = resource {
            #expect(ps.id == "ps-1")
        } else {
            Issue.record("Expected preview set")
        }
    }

    @Test func decodeUnknown() throws {
        let json = """
        {"id":"x","type":"somethingNew","attributes":{}}
        """.data(using: .utf8)!
        let resource = try JSONDecoder().decode(IncludedResource.self, from: json)
        if case .unknown = resource {
            // expected
        } else {
            Issue.record("Expected unknown")
        }
    }

    @Test func encodeLocalization() throws {
        let loc = ASCAppStoreVersionLocalization(id: "l1", type: "appStoreVersionLocalizations", attributes: nil, relationships: nil)
        let resource = IncludedResource.appStoreVersionLocalization(loc)
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(IncludedResource.self, from: data)
        if case .appStoreVersionLocalization(let decodedLoc) = decoded {
            #expect(decodedLoc.id == "l1")
        } else {
            Issue.record("Roundtrip failed")
        }
    }
}
