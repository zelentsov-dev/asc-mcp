import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Analytics Worker Contract Tests")
struct AnalyticsWorkerContractTests {
    @Test("schemas expose Apple analytics filters, include controls, and bounds")
    func schemasExposeAnalyticsControls() async throws {
        let worker = try await analyticsContractWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        let requests = try analyticsContractProperties(
            try #require(tools.first { $0.name == "analytics_list_report_requests" })
        )
        #expect(try analyticsContractEnum(requests["access_types"]) == ["ONE_TIME_SNAPSHOT", "ONGOING"])
        #expect(requests["include_reports"]?.objectValue?["type"]?.stringValue == "boolean")
        #expect(requests["limit_reports"]?.objectValue?["minimum"]?.intValue == 1)
        #expect(requests["limit_reports"]?.objectValue?["maximum"]?.intValue == 50)
        #expect(requests["limit"]?.objectValue?["maximum"]?.intValue == 200)

        let reports = try analyticsContractProperties(
            try #require(tools.first { $0.name == "analytics_list_reports" })
        )
        #expect(reports["names"]?.objectValue?["items"]?.objectValue?["minLength"]?.intValue == 1)
        #expect(try analyticsContractEnum(reports["categories"]) == [
            "APP_USAGE", "APP_STORE_ENGAGEMENT", "COMMERCE", "FRAMEWORK_USAGE", "PERFORMANCE"
        ])

        let instances = try analyticsContractProperties(
            try #require(tools.first { $0.name == "analytics_list_instances" })
        )
        #expect(try analyticsContractEnum(instances["granularities"]) == ["DAILY", "WEEKLY", "MONTHLY"])
        #expect(
            instances["processing_dates"]?.objectValue?["items"]?.objectValue?["format"]?.stringValue == "date"
        )

        let snapshot = try analyticsContractProperties(
            try #require(tools.first { $0.name == "analytics_check_snapshot_status" })
        )
        #expect(snapshot["name"]?.objectValue?["minLength"]?.intValue == 1)

        let segments = try analyticsContractProperties(
            try #require(tools.first { $0.name == "analytics_list_segments" })
        )
        #expect(segments["limit"]?.objectValue?["minimum"]?.intValue == 1)
        #expect(segments["limit"]?.objectValue?["maximum"]?.intValue == 200)
    }

    @Test("report request list binds access, include, nested limit, and projections")
    func reportRequestListContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "analyticsReportRequests",
                "id": "request-1",
                "attributes": {"accessType": "ONGOING", "stoppedDueToInactivity": false},
                "relationships": {
                  "reports": {
                    "data": [{"type": "analyticsReports", "id": "report-1"}],
                    "meta": {"paging": {"total": 3, "limit": 1}}
                  }
                }
              }],
              "included": [{
                "type": "analyticsReports",
                "id": "report-1",
                "attributes": {"category": "COMMERCE", "name": "Sales"}
              }],
              "meta": {"paging": {"total": 1, "limit": 10}}
            }
            """)
        ])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_list_report_requests",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .int(10),
                "access_types": .array([.string("ONGOING")]),
                "include_reports": .bool(true),
                "limit_reports": .int(1)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try analyticsContractQuery(request)
        #expect(query["limit"] == "10")
        #expect(query["filter[accessType]"] == "ONGOING")
        #expect(query["include"] == "reports")
        #expect(query["limit[reports]"] == "1")

        let payload = try analyticsContractObject(result.structuredContent)
        #expect(payload["total"]?.intValue == 1)
        let reportRequest = try analyticsContractObject(
            try #require(analyticsContractArray(payload["report_requests"]).first)
        )
        #expect(try analyticsContractStrings(reportRequest["report_ids"]) == ["report-1"])
        #expect(reportRequest["reports_total"]?.intValue == 3)
        let included = try analyticsContractObject(
            try #require(analyticsContractArray(payload["included_reports"]).first)
        )
        #expect(included["name"]?.stringValue == "Sales")
    }

    @Test("report request continuation preserves access, include, and nested limit")
    func reportRequestContinuationPreservesContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"meta":{"paging":{"total":0,"limit":25}}}"#)
        ])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_list_report_requests",
            arguments: [
                "app_id": .string("app-1"),
                "access_types": .array([.string("ONGOING")]),
                "include_reports": .bool(true),
                "limit_reports": .int(2),
                "next_url": .string(
                    "https://api.example.test/v1/apps/app-1/analyticsReportRequests?cursor=next&filter%5BaccessType%5D=ONGOING&include=reports&limit=25&limit%5Breports%5D=2"
                )
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("report request continuation rejects dropped include semantics")
    func reportRequestContinuationRejectsDroppedParameter() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_list_report_requests",
            arguments: [
                "app_id": .string("app-1"),
                "access_types": .array([.string("ONGOING")]),
                "include_reports": .bool(true),
                "limit_reports": .int(2),
                "next_url": .string(
                    "https://api.example.test/v1/apps/app-1/analyticsReportRequests?cursor=next&filter%5BaccessType%5D=ONGOING&include=reports"
                )
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("nested report limit requires report inclusion")
    func reportRequestNestedLimitRequiresInclude() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_list_report_requests",
            arguments: [
                "app_id": .string("app-1"),
                "limit_reports": .int(2)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("report list binds names, categories, and paging total")
    func reportListContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "analyticsReports",
                "id": "report-1",
                "attributes": {"category": "COMMERCE", "name": "Sales"}
              }],
              "meta": {"paging": {"total": 7, "limit": 20}}
            }
            """)
        ])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_list_reports",
            arguments: [
                "request_id": .string("request-1"),
                "limit": .int(20),
                "names": .array([.string("Sales"), .string("Downloads")]),
                "categories": .array([.string("COMMERCE"), .string("APP_USAGE")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try analyticsContractQuery(request)
        #expect(query["filter[name]"] == "Sales,Downloads")
        #expect(query["filter[category]"] == "COMMERCE,APP_USAGE")
        #expect(query["limit"] == "20")
        let payload = try analyticsContractObject(result.structuredContent)
        #expect(payload["total"]?.intValue == 7)
    }

    @Test("instance list binds granularity and real processing dates")
    func instanceListContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "analyticsReportInstances",
                "id": "instance-1",
                "attributes": {"granularity": "DAILY", "processingDate": "2026-07-20"}
              }],
              "meta": {"paging": {"total": 4, "limit": 15}}
            }
            """)
        ])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_list_instances",
            arguments: [
                "report_id": .string("report-1"),
                "limit": .int(15),
                "granularities": .array([.string("DAILY"), .string("WEEKLY")]),
                "processing_dates": .array([.string("2026-07-20"), .string("2026-07-19")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try analyticsContractQuery(request)
        #expect(query["filter[granularity]"] == "DAILY,WEEKLY")
        #expect(query["filter[processingDate]"] == "2026-07-20,2026-07-19")
        #expect(query["limit"] == "15")
        let payload = try analyticsContractObject(result.structuredContent)
        #expect(payload["total"]?.intValue == 4)
    }

    @Test("invalid processing date fails before network")
    func invalidProcessingDateFailsBeforeNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_list_instances",
            arguments: [
                "report_id": .string("report-1"),
                "processing_dates": .array([.string("2026-02-30")])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("snapshot status sends and preserves category and exact name filters")
    func snapshotStatusFilterContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "analyticsReports",
                "id": "report-1",
                "attributes": {"category": "COMMERCE", "name": "Sales"}
              }],
              "links": {
                "self": "https://api.example.test/v1/analyticsReportRequests/request-1/reports",
                "next": "https://api.example.test/v1/analyticsReportRequests/request-1/reports?cursor=next&filter%5Bcategory%5D=COMMERCE&filter%5Bname%5D=Sales&limit=200"
              }
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "analyticsReports",
                "id": "report-2",
                "attributes": {"category": "COMMERCE", "name": "Sales"}
              }]
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "analyticsReportInstances",
                "id": "instance-1",
                "attributes": {"granularity": "DAILY", "processingDate": "2026-07-20"}
              }]
            }
            """),
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_check_snapshot_status",
            arguments: [
                "request_id": .string("request-1"),
                "category": .string("COMMERCE"),
                "name": .string("Sales")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 4)
        let firstQuery = try analyticsContractQuery(requests[0])
        #expect(firstQuery["limit"] == "200")
        #expect(firstQuery["filter[category]"] == "COMMERCE")
        #expect(firstQuery["filter[name]"] == "Sales")
        let continuationQuery = try analyticsContractQuery(requests[1])
        #expect(continuationQuery["filter[category]"] == "COMMERCE")
        #expect(continuationQuery["filter[name]"] == "Sales")
        #expect(continuationQuery["limit"] == "200")
        #expect(try analyticsContractQuery(requests[2])["limit"] == "1")
        #expect(try analyticsContractQuery(requests[3])["limit"] == "1")

        let payload = try analyticsContractObject(result.structuredContent)
        #expect(payload["total_reports"]?.intValue == 2)
        #expect(payload["ready"]?.intValue == 1)
        #expect(payload["pending"]?.intValue == 1)
        #expect(payload["category_filter"]?.stringValue == "COMMERCE")
        #expect(payload["name_filter"]?.stringValue == "Sales")
    }

    @Test("snapshot status rejects a repeated strict reports continuation")
    func snapshotStatusRejectsPaginationCycle() async throws {
        let next = "https://api.example.test/v1/analyticsReportRequests/request-1/reports?cursor=repeat&filter%5Bcategory%5D=COMMERCE&filter%5Bname%5D=Sales&limit=200"
        let page = """
        {
          "data": [],
          "links": {
            "self": "https://api.example.test/v1/analyticsReportRequests/request-1/reports",
            "next": "\(next)"
          }
        }
        """
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: page),
            .init(statusCode: 200, body: page)
        ])
        let worker = try await analyticsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_check_snapshot_status",
            arguments: [
                "request_id": .string("request-1"),
                "category": .string("COMMERCE"),
                "name": .string("Sales")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 2)
    }
}

private func analyticsContractWorker(transport: TestHTTPTransport) async throws -> AnalyticsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AnalyticsWorker(httpClient: client)
}

private func analyticsContractProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw AnalyticsContractTestError.expectedObject
    }
    return properties
}

private func analyticsContractEnum(_ property: Value?) throws -> [String] {
    let items = try analyticsContractObject(property)["items"]
    let enumValue = try analyticsContractObject(items)["enum"]
    return try analyticsContractStrings(enumValue)
}

private func analyticsContractQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func analyticsContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw AnalyticsContractTestError.expectedObject
    }
    return object
}

private func analyticsContractArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw AnalyticsContractTestError.expectedArray
    }
    return array
}

private func analyticsContractStrings(_ value: Value?) throws -> [String] {
    try analyticsContractArray(value).map { try #require($0.stringValue) }
}

private enum AnalyticsContractTestError: Error {
    case expectedObject
    case expectedArray
}
