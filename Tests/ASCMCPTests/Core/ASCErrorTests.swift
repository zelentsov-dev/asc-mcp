import Testing
import Foundation
@testable import asc_mcp

@Suite("ASCError Tests")
struct ASCErrorTests {
    @Test func configurationError() {
        let error = ASCError.configuration("bad config")
        #expect(error.errorDescription?.contains("Configuration error") == true)
        #expect(error.errorDescription?.contains("bad config") == true)
    }

    @Test func apiError() {
        let error = ASCError.api("not found", 404)
        #expect(error.errorDescription?.contains("API error") == true)
        #expect(error.errorDescription?.contains("404") == true)
        #expect(error.errorDescription?.contains("not found") == true)
    }

    @Test func apiErrorFormat() {
        let error = ASCError.api("forbidden", 403)
        // Format: "API error (403): forbidden"
        #expect(error.errorDescription == "API error (403): forbidden")
    }

    @Test func networkError() {
        let error = ASCError.network("timeout")
        #expect(error.errorDescription?.contains("Network error") == true)
        #expect(error.errorDescription?.contains("timeout") == true)
    }

    @Test func authenticationError() {
        let error = ASCError.authentication("expired")
        #expect(error.errorDescription?.contains("Authentication error") == true)
        #expect(error.errorDescription?.contains("expired") == true)
    }

    @Test func parsingError() {
        let error = ASCError.parsing("invalid json")
        #expect(error.errorDescription?.contains("Parsing error") == true)
        #expect(error.errorDescription?.contains("invalid json") == true)
    }

    @Test func errorConformsToLocalizedError() {
        let error: any LocalizedError = ASCError.configuration("test")
        #expect(error.errorDescription != nil)
    }

    @Test func errorIsSendable() {
        let error: any Sendable = ASCError.network("test")
        _ = error // Compiles means Sendable conformance works
    }
}
