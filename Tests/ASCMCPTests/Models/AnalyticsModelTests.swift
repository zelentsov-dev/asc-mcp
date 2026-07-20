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

    @Test func reportRequestsResponseIncludesReportsRelationshipsAndPaging() throws {
        let json = """
        {
          "data": [{
            "type": "analyticsReportRequests",
            "id": "ar-1",
            "relationships": {
              "reports": {
                "data": [
                  {"type": "analyticsReports", "id": "report-1"},
                  {"type": "analyticsReports", "id": "report-2"}
                ],
                "links": {"self": "https://api.example.test/v1/analyticsReportRequests/ar-1/relationships/reports"},
                "meta": {"paging": {"total": 3, "limit": 2}}
              }
            }
          }],
          "included": [{
            "type": "analyticsReports",
            "id": "report-1",
            "attributes": {"category": "COMMERCE", "name": "Sales"}
          }],
          "links": {"self": "https://api.example.test/v1/apps/app-1/analyticsReportRequests"},
          "meta": {"paging": {"total": 1, "limit": 25}}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ASCAnalyticsReportRequestsResponse.self, from: json)

        #expect(response.data.first?.relationships?.reports?.data?.map(\.id) == ["report-1", "report-2"])
        #expect(response.data.first?.relationships?.reports?.meta?.paging?.total == 3)
        #expect(response.included?.first?.attributes?.name == "Sales")
        #expect(response.meta?.paging?.total == 1)
    }
}
