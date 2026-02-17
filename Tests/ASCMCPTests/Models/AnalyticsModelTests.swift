import Testing
import Foundation
@testable import asc_mcp

@Suite("Analytics Model Tests")
struct AnalyticsModelTests {
    @Test func decodeReportRequest() throws {
        let json = """
        {"type":"analyticsReportRequests","id":"ar-1","attributes":{"accessType":"ONGOING","stoppedDueToInactivity":false}}
        """.data(using: .utf8)!
        let request = try JSONDecoder().decode(ASCAnalyticsReportRequest.self, from: json)
        #expect(request.id == "ar-1")
        #expect(request.attributes?.accessType == "ONGOING")
    }

    @Test func reportRequestResponse() throws {
        let json = """
        {"data":{"type":"analyticsReportRequests","id":"ar-1","attributes":{"accessType":"ONE_TIME_SNAPSHOT"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAnalyticsReportRequestResponse.self, from: json)
        #expect(response.data.attributes?.accessType == "ONE_TIME_SNAPSHOT")
    }

    @Test func reportRequestsResponse() throws {
        let json = """
        {"data":[{"type":"analyticsReportRequests","id":"ar-1","attributes":{"accessType":"ONGOING"}},{"type":"analyticsReportRequests","id":"ar-2","attributes":{"accessType":"ONE_TIME_SNAPSHOT"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAnalyticsReportRequestsResponse.self, from: json)
        #expect(response.data.count == 2)
    }
}
