import Testing
import Foundation
@testable import asc_mcp

@Suite("PaginationHelper Tests")
struct PaginationHelperTests {
    @Test func parseValidURL() {
        let result = parsePaginationUrl("https://api.appstoreconnect.apple.com/v1/apps?limit=10&cursor=abc")
        #expect(result != nil)
        #expect(result?.path == "/v1/apps")
        #expect(result?.parameters["limit"] == "10")
        #expect(result?.parameters["cursor"] == "abc")
    }

    @Test func parseURLWithoutQuery() {
        let result = parsePaginationUrl("https://api.appstoreconnect.apple.com/v1/apps")
        #expect(result != nil)
        #expect(result?.path == "/v1/apps")
        #expect(result?.parameters.isEmpty == true)
    }

    @Test func parseURLWithMultipleParams() {
        let result = parsePaginationUrl("https://api.appstoreconnect.apple.com/v1/builds?limit=20&offset=40&sort=version")
        #expect(result?.parameters.count == 3)
        #expect(result?.parameters["sort"] == "version")
    }

    @Test func parseInvalidURL() {
        let result = parsePaginationUrl("")
        // Empty string has no host, so it should be rejected
        #expect(result == nil)
    }

    @Test func parseURLWithEncodedChars() {
        let result = parsePaginationUrl("https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=com.test")
        #expect(result != nil)
        #expect(result?.path == "/v1/apps")
    }

    @Test func parseRelativePath() {
        // Relative paths have no host, should be rejected by SSRF protection
        let result = parsePaginationUrl("/v1/apps?limit=10")
        #expect(result == nil)
    }

    @Test func parseLongURL() {
        let url = "https://api.appstoreconnect.apple.com/v1/apps/12345/appStoreVersions?limit=200&include=appStoreVersionLocalizations"
        let result = parsePaginationUrl(url)
        #expect(result != nil)
        #expect(result?.parameters["include"] == "appStoreVersionLocalizations")
    }

    @Test func rejectsDisallowedHost() {
        let result = parsePaginationUrl("https://evil.example.com/v1/apps?limit=10")
        #expect(result == nil)
    }
}
