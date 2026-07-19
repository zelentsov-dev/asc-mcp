import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Analytics Pagination Security Tests")
struct AnalyticsPaginationSecurityTests {
    @Test("snapshot status rejects a same-origin internal next link for another collection")
    func snapshotRejectsCrossRouteNextLink() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "analyticsReports",
                  "id": "report-1",
                  "attributes": {"category": "COMMERCE", "name": "Sales"}
                }
              ],
              "links": {
                "next": "https://api.example.test/v1/users?cursor=next-page"
              }
            }
            """)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = AnalyticsWorker(httpClient: client)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_check_snapshot_status",
            arguments: ["request_id": .string("request-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }
}
