import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Analytics Sales Report Hardening Tests")
struct AnalyticsSalesReportHardeningTests {
    @Test("sales report schema matches OpenAPI report enums")
    func salesReportSchemaMatchesOpenAPIEnums() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeAnalyticsWorker(transport: transport)
        let tool = try #require(await worker.getTools().first { $0.name == "analytics_sales_report" })
        let properties = try analyticsProperties(tool)
        let reportTypes = try analyticsEnum(properties["report_type"])
        let reportSubTypes = try analyticsEnum(properties["report_sub_type"])

        #expect(reportTypes == Set([
            "SALES", "PRE_ORDER", "NEWSSTAND", "SUBSCRIPTION", "SUBSCRIPTION_EVENT",
            "SUBSCRIBER", "SUBSCRIPTION_OFFER_CODE_REDEMPTION", "INSTALLS",
            "FIRST_ANNUAL", "WIN_BACK_ELIGIBILITY"
        ]))
        #expect(reportSubTypes == Set([
            "SUMMARY", "DETAILED", "SUMMARY_INSTALL_TYPE", "SUMMARY_TERRITORY", "SUMMARY_CHANNEL"
        ]))

        guard case .object(let schema) = tool.inputSchema,
              case .array(let required)? = schema["required"] else {
            throw AnalyticsSalesReportHardeningFailure.expectedSchema
        }
        #expect(!required.compactMap(\.stringValue).contains("report_date"))
    }

    @Test("raw sales rows reuse the summary download")
    func rawRowsUseOneDownload() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: Self.salesTSV)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_type": .string("SALES"),
                "report_sub_type": .string("SUMMARY"),
                "frequency": .string("DAILY"),
                "report_date": .string("2026-07-18"),
                "summary_only": .bool(false),
                "limit": .int(1)
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
        let request = try #require(await transport.recordedRequests().first)
        let query = analyticsQueryItems(request)
        #expect(request.url?.path == "/v1/salesReports")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/a-gzip")
        #expect(query["filter[reportType]"] == "SALES")
        #expect(query["filter[reportSubType]"] == "SUMMARY")
        #expect(query["filter[frequency]"] == "DAILY")
        #expect(query["filter[version]"] == "1_0")

        let root = try analyticsObject(result.structuredContent)
        #expect(root["total_rows"] == .int(2))
        #expect(root["filtered_rows"] == .int(2))
        #expect(root["showing_rows"] == .int(1))
        let rows = try analyticsArray(root["rows"])
        #expect(rows.count == 1)
    }

    @Test("financial raw row limit is advertised and clamped to 1 through 200")
    func financialRawRowLimitIsBounded() async throws {
        let header = "Quantity\tPartner Share\tPartner Share Currency\tCountry Of Sale (Region)"
        let body = header + "\n" + Array(
            repeating: "1\t1.00\tUSD\tUS",
            count: 205
        ).joined(separator: "\n")
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 200, body: body)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)
        let tool = try #require(await worker.getTools().first { $0.name == "analytics_financial_report" })
        let properties = try analyticsProperties(tool)
        let limitSchema = try analyticsObject(properties["limit"])

        #expect(limitSchema["minimum"] == .int(1))
        #expect(limitSchema["maximum"] == .int(200))

        let minimumResult = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_financial_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "region_code": .string("US"),
                "report_date": .string("2026-06"),
                "report_type": .string("FINANCIAL"),
                "summary_only": .bool(false),
                "limit": .int(0)
            ]
        ))
        let maximumResult = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_financial_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "region_code": .string("US"),
                "report_date": .string("2026-06"),
                "report_type": .string("FINANCIAL"),
                "summary_only": .bool(false),
                "limit": .int(Int.max)
            ]
        ))

        let minimumRoot = try analyticsObject(minimumResult.structuredContent)
        let maximumRoot = try analyticsObject(maximumResult.structuredContent)
        #expect(minimumRoot["showing_rows"] == .int(1))
        #expect(maximumRoot["showing_rows"] == .int(200))
        #expect(await transport.requestCount() == 2)
    }

    @Test("daily sales report can request the latest available date")
    func dailyReportDateIsOptional() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: Self.salesTSV)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_type": .string("SALES"),
                "report_sub_type": .string("SUMMARY"),
                "frequency": .string("DAILY")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(analyticsQueryItems(request)["filter[reportDate]"] == nil)
    }

    @Test("report combinations and versions are validated before network")
    func invalidCombinationAndVersionAreRejected() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let invalidCombination = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_type": .string("SALES"),
                "report_sub_type": .string("DETAILED"),
                "frequency": .string("DAILY")
            ]
        ))
        let invalidVersion = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_type": .string("SUBSCRIPTION_EVENT"),
                "report_sub_type": .string("SUMMARY"),
                "frequency": .string("DAILY"),
                "version": .string("1_4")
            ]
        ))

        #expect(invalidCombination.isError == true)
        #expect(invalidVersion.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("app summary uses supported report versions")
    func appSummaryUsesSupportedVersions() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: Self.salesTSV),
            .init(statusCode: 200, body: Self.salesTSV),
            .init(statusCode: 200, body: Self.salesTSV),
            .init(statusCode: 200, body: Self.salesTSV)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_app_summary",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_date": .string("2026-07-18")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 4)
        let versions = Dictionary(uniqueKeysWithValues: requests.map { request in
            let query = analyticsQueryItems(request)
            return (query["filter[reportType]"] ?? "", query["filter[version]"] ?? "")
        })
        #expect(versions["SALES"] == "1_0")
        #expect(versions["SUBSCRIPTION"] == "1_3")
        #expect(versions["SUBSCRIPTION_EVENT"] == "1_3")
        #expect(versions["SUBSCRIBER"] == "1_3")
    }

    @Test("app summary reports an error when every section fails")
    func appSummaryFailsWhenEverySectionFails() async throws {
        let failure = #"{"errors":[{"status":"404","detail":"report unavailable"}]}"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 404, body: failure),
            .init(statusCode: 404, body: failure),
            .init(statusCode: 404, body: failure),
            .init(statusCode: 404, body: failure)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_app_summary",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_date": .string("2026-07-18")
            ]
        ))

        #expect(result.isError == true)
        let root = try analyticsObject(result.structuredContent)
        #expect(root["success"] == .bool(false))
        #expect(root["partial_success"] == .bool(false))
        #expect(root["sections_succeeded"] == .int(0))
        #expect(root["sections_failed"] == .int(4))
    }

    @Test("installs report defaults to the newest supported version")
    func installsDefaultsToNewestSupportedVersion() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: Self.installsTSV)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_type": .string("INSTALLS"),
                "report_sub_type": .string("SUMMARY_CHANNEL"),
                "frequency": .string("YEARLY"),
                "report_date": .string("2025-12-31"),
                "app_id": .string("111")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(analyticsQueryItems(request)["filter[version]"] == "1_1")
        let root = try analyticsObject(result.structuredContent)
        #expect(root["filtered_rows"] == .int(1))
        let summary = try analyticsObject(root["summary"])
        #expect(summary["row_count"] == .int(1))
    }

    @Test("pre-order report uses the API-supported version")
    func preOrderUsesAPISupportedVersion() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: Self.salesTSV)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_type": .string("PRE_ORDER"),
                "report_sub_type": .string("SUMMARY"),
                "frequency": .string("DAILY")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(analyticsQueryItems(request)["filter[version]"] == "1_0")
    }

    @Test("sales report decodes a real gzip response")
    func salesReportDecodesGzipResponse() async throws {
        let compressed = try #require(Data(base64Encoded: Self.gzipSalesTSV))
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, data: compressed)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: [
                "vendor_number": .string(" 12345678 "),
                "report_type": .string("SALES"),
                "report_sub_type": .string("SUMMARY"),
                "frequency": .string("DAILY"),
                "report_date": .string(" 2026-07-18 ")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(analyticsQueryItems(request)["filter[vendorNumber]"] == "12345678")
        #expect(analyticsQueryItems(request)["filter[reportDate]"] == "2026-07-18")
        let root = try analyticsObject(result.structuredContent)
        let summary = try analyticsObject(root["summary"])
        #expect(summary["total_units"] == .int(100))
        let proceeds = try analyticsObject(summary["proceeds_by_currency"])
        #expect(proceeds["USD"] == .double(70))
        let exactProceeds = try analyticsObject(summary["proceeds_by_currency_exact"])
        #expect(exactProceeds["USD"] == .string("70"))
    }

    @Test("sales report rejects a gzip response with a corrupt checksum")
    func salesReportRejectsCorruptGzipChecksum() async throws {
        var compressed = try #require(Data(base64Encoded: Self.gzipSalesTSV))
        compressed[compressed.count - 8] ^= 0xFF
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, data: compressed)
        ])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_type": .string("SALES"),
                "report_sub_type": .string("SUMMARY"),
                "frequency": .string("DAILY")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("sales report rejects empty identifiers and invalid dates before network")
    func salesReportRejectsInvalidLocalInputs() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeAnalyticsWorker(transport: transport)
        let common: [String: Value] = [
            "vendor_number": .string("12345678"),
            "report_type": .string("SALES"),
            "report_sub_type": .string("SUMMARY"),
            "frequency": .string("DAILY")
        ]

        var emptyVendorArguments = common
        emptyVendorArguments["vendor_number"] = .string(" \n ")
        let emptyVendor = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: emptyVendorArguments
        ))

        var emptyAppArguments = common
        emptyAppArguments["app_id"] = .string("   ")
        let emptyApp = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: emptyAppArguments
        ))

        var emptyDateArguments = common
        emptyDateArguments["report_date"] = .string("   ")
        let emptyDate = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: emptyDateArguments
        ))

        var impossibleDateArguments = common
        impossibleDateArguments["report_date"] = .string("2026-02-30")
        let impossibleDate = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: impossibleDateArguments
        ))

        var monthlyArguments = common
        monthlyArguments["frequency"] = .string("MONTHLY")
        monthlyArguments["report_date"] = .string("2026-07")
        let wrongMonthlyFormat = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_sales_report",
            arguments: monthlyArguments
        ))

        #expect(emptyVendor.isError == true)
        #expect(emptyApp.isError == true)
        #expect(emptyDate.isError == true)
        #expect(impossibleDate.isError == true)
        #expect(wrongMonthlyFormat.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("app summary rejects empty identifiers and invalid dates before network")
    func appSummaryRejectsInvalidLocalInputs() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeAnalyticsWorker(transport: transport)

        let invalidDate = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_app_summary",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_date": .string("2025-02-29")
            ]
        ))
        let emptyVendor = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_app_summary",
            arguments: [
                "vendor_number": .string(" "),
                "report_date": .string("2026-07-18")
            ]
        ))
        let emptyApp = try await worker.handleTool(CallTool.Parameters(
            name: "analytics_app_summary",
            arguments: [
                "vendor_number": .string("12345678"),
                "report_date": .string("2026-07-18"),
                "app_id": .string("\t")
            ]
        ))

        #expect(invalidDate.isError == true)
        #expect(emptyVendor.isError == true)
        #expect(emptyApp.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    private static let salesTSV = """
    Provider\tApple Identifier\tTitle\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tProduct Type Identifier
    APPLE\t111\tExample\t2\t1.50\tUSD\tUS\t1
    APPLE\t222\tSecond\t1\t0.75\tUSD\tGB\t1
    """

    private static let installsTSV = """
    Developer\tApp ID\tApp Name\tFirst Annual Installs
    Example Developer\t111\tExample\t100
    Example Developer\t222\tSecond\t50
    """

    private static let gzipSalesTSV = "H4sIAAAAAAAAA03OMQrEIBQE0PrnFJ5g0WrrkKRY2ELY5ABLnIBg/PLVsN5+LVNM8xiGscKXdxAaUwpQL4dY/OE7rL4E0BZ9yTTjQuAEUVZ4B1ymqYog7k3xcUOusUhTEztQV1f3otaW7sPDaO17IWNMr59JkDOcWn7fsx8gozXpx1PT9pl7yAx/6SIB0KIAAAA="
}

private extension TestHTTPTransport.Response {
    init(statusCode: Int, headers: [String: String] = [:], data: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }
}

private func makeAnalyticsWorker(transport: TestHTTPTransport) async throws -> AnalyticsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AnalyticsWorker(httpClient: client)
}

private func analyticsQueryItems(_ request: URLRequest) -> [String: String] {
    guard let url = request.url else { return [:] }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func analyticsObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw AnalyticsSalesReportHardeningFailure.expectedObject
    }
    return object
}

private func analyticsArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw AnalyticsSalesReportHardeningFailure.expectedArray
    }
    return array
}

private func analyticsProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw AnalyticsSalesReportHardeningFailure.expectedSchema
    }
    return properties
}

private func analyticsEnum(_ value: Value?) throws -> Set<String> {
    guard case .object(let schema)? = value,
          case .array(let values)? = schema["enum"] else {
        throw AnalyticsSalesReportHardeningFailure.expectedSchema
    }
    return Set(values.compactMap(\.stringValue))
}

private enum AnalyticsSalesReportHardeningFailure: Error {
    case expectedObject
    case expectedArray
    case expectedSchema
}
