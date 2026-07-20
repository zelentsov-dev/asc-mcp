//
//  AnalyticsWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of analytics and reports handlers
//

import Foundation
import MCP

extension AnalyticsWorker {

    private struct ParsedSalesReport {
        let headers: [String]
        let rows: [[String: String]]
        let totalRows: Int
        let summary: [String: Any]
    }

    /// Resolves vendor number from explicit parameter or company config
    /// - Returns: Vendor number string or nil if not available
    private func resolveVendorNumber(from arguments: [String: Value]?) async -> String? {
        if let explicit = arguments?["vendor_number"]?.stringValue {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let manager = companiesManager,
           let company = try? await manager.getCurrentCompany(),
           let vendorNumber = company.vendorNumber {
            let trimmed = vendorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func nonEmptyIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func reportDate(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(trimmed.prefix(4)),
              let month = Int(trimmed.dropFirst(5).prefix(2)),
              let day = Int(trimmed.suffix(2)),
              year > 0 else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return trimmed
    }

    private static let analyticsAccessTypes: Set<String> = ["ONE_TIME_SNAPSHOT", "ONGOING"]
    private static let analyticsCategories: Set<String> = [
        "APP_USAGE", "APP_STORE_ENGAGEMENT", "COMMERCE", "FRAMEWORK_USAGE", "PERFORMANCE"
    ]
    private static let analyticsGranularities: Set<String> = ["DAILY", "WEEKLY", "MONTHLY"]

    private static func collectionLimit(
        _ value: Value?,
        name: String = "limit",
        maximum: Int = 200,
        defaultValue: Int = 25
    ) throws -> Int {
        guard let value else {
            return defaultValue
        }
        guard let limit = value.intValue, (1...maximum).contains(limit) else {
            throw ASCError.parsing("\(name) must be an integer from 1 through \(maximum)")
        }
        return limit
    }

    private static func stringList(
        _ value: Value?,
        name: String,
        allowedValues: Set<String>? = nil
    ) throws -> [String]? {
        guard let value else {
            return nil
        }
        guard let values = value.arrayValue, !values.isEmpty else {
            throw ASCError.parsing("\(name) must be a non-empty array")
        }
        let strings = values.compactMap(\.stringValue).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard strings.count == values.count, strings.allSatisfy({ !$0.isEmpty }) else {
            throw ASCError.parsing("\(name) must contain only non-empty strings")
        }
        guard Set(strings).count == strings.count else {
            throw ASCError.parsing("\(name) must not contain duplicates")
        }
        if let allowedValues, !strings.allSatisfy({ allowedValues.contains($0) }) {
            throw ASCError.parsing(
                "\(name) contains an unsupported value; allowed values: \(allowedValues.sorted().joined(separator: ", "))"
            )
        }
        return strings
    }

    private static func processingDates(_ value: Value?) throws -> [String]? {
        guard let dates = try stringList(value, name: "processing_dates") else {
            return nil
        }
        let normalized = dates.compactMap { reportDate($0) }
        guard normalized.count == dates.count else {
            throw ASCError.parsing("processing_dates must contain only real dates in YYYY-MM-DD format")
        }
        return normalized
    }

    private static func optionalBool(_ value: Value?, name: String) throws -> Bool? {
        guard let value else {
            return nil
        }
        guard let result = value.boolValue else {
            throw ASCError.parsing("\(name) must be a boolean")
        }
        return result
    }

    private static func allowedReportVersions(
        reportType: String,
        reportSubType: String,
        frequency: String
    ) -> [String]? {
        switch (reportType, reportSubType, frequency) {
        case ("FIRST_ANNUAL", "DETAILED", "DAILY"),
             ("FIRST_ANNUAL", "SUMMARY", "YEARLY"),
             ("NEWSSTAND", "DETAILED", "DAILY"),
             ("NEWSSTAND", "DETAILED", "WEEKLY"),
             ("SUBSCRIPTION_OFFER_CODE_REDEMPTION", "SUMMARY", "DAILY"),
             ("WIN_BACK_ELIGIBILITY", "SUMMARY", "DAILY"):
            return ["1_0"]
        case ("PRE_ORDER", "SUMMARY", "DAILY"),
             ("PRE_ORDER", "SUMMARY", "WEEKLY"),
             ("PRE_ORDER", "SUMMARY", "MONTHLY"),
             ("PRE_ORDER", "SUMMARY", "YEARLY"),
             ("SALES", "SUMMARY", "DAILY"),
             ("SALES", "SUMMARY", "WEEKLY"),
             ("SALES", "SUMMARY", "MONTHLY"),
             ("SALES", "SUMMARY", "YEARLY"):
            return ["1_0"]
        case ("SUBSCRIBER", "DETAILED", "DAILY"),
             ("SUBSCRIPTION", "SUMMARY", "DAILY"),
             ("SUBSCRIPTION_EVENT", "SUMMARY", "DAILY"):
            return ["1_3"]
        case ("INSTALLS", "SUMMARY", "MONTHLY"),
             ("INSTALLS", "DETAILED", "MONTHLY"):
            return ["1_2"]
        case ("INSTALLS", "SUMMARY_CHANNEL", "YEARLY"),
             ("INSTALLS", "SUMMARY_INSTALL_TYPE", "YEARLY"),
             ("INSTALLS", "SUMMARY_TERRITORY", "YEARLY"),
             ("INSTALLS", "DETAILED", "YEARLY"):
            return ["1_0", "1_1"]
        default:
            return nil
        }
    }

    private func fetchReportSummary(
        vendorNumber: String,
        reportType: String,
        reportSubType: String,
        frequency: String,
        reportDate: String?,
        version: String,
        appIdFilter: String? = nil
    ) async throws -> ParsedSalesReport {
        var queryParams: [String: String] = [
            "filter[vendorNumber]": vendorNumber,
            "filter[reportType]": reportType,
            "filter[reportSubType]": reportSubType,
            "filter[frequency]": frequency,
            "filter[version]": version
        ]
        if let reportDate {
            queryParams["filter[reportDate]"] = reportDate
        }

        let data = try await httpClient.getRaw("/v1/salesReports", parameters: queryParams, accept: "application/a-gzip")

        let tsvString = try decompressReportData(data)
        let parsed = try TSVParser.parse(data: tsvString) { row in
            guard let appId = appIdFilter else { return true }
            return row["Apple Identifier"] == appId ||
                row["App Apple ID"] == appId ||
                row["App Identifier"] == appId ||
                row["App ID"] == appId
        }

        let summary = ReportSummary.summary(for: reportType, from: parsed.rows)
        return ParsedSalesReport(
            headers: parsed.headers,
            rows: parsed.rows,
            totalRows: parsed.totalRowCount,
            summary: summary
        )
    }

    /// Gets a sales/download report from App Store Connect
    /// - Returns: Structured JSON with summary (always) and optional raw rows
    /// - Throws: Error if required parameters are missing or API call fails
    func getSalesReport(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reportType = arguments["report_type"]?.stringValue,
              let reportSubType = arguments["report_sub_type"]?.stringValue,
              let frequency = arguments["frequency"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Missing required parameters: report_type, report_sub_type, frequency")],
                isError: true
            )
        }

        let reportDate: String?
        if let rawReportDate = arguments["report_date"]?.stringValue {
            guard let normalizedReportDate = Self.reportDate(rawReportDate) else {
                return CallTool.Result(
                    content: [MCPContent.text("Invalid report_date: use a real calendar date in YYYY-MM-DD format")],
                    isError: true
                )
            }
            reportDate = normalizedReportDate
        } else {
            reportDate = nil
        }
        if frequency != "DAILY", reportDate == nil {
            return CallTool.Result(
                content: [MCPContent.text("Missing required parameter 'report_date' for non-daily reports")],
                isError: true
            )
        }

        guard let allowedVersions = Self.allowedReportVersions(
            reportType: reportType,
            reportSubType: reportSubType,
            frequency: frequency
        ), let defaultVersion = allowedVersions.last else {
            return CallTool.Result(
                content: [MCPContent.text("Unsupported report type, sub-type, and frequency combination")],
                isError: true
            )
        }

        guard let vendorNumber = await resolveVendorNumber(from: arguments) else {
            return CallTool.Result(
                content: [MCPContent.text("Missing vendor_number: provide it as parameter or set vendor_number in company config")],
                isError: true
            )
        }

        let version = arguments["version"]?.stringValue ?? defaultVersion
        guard allowedVersions.contains(version) else {
            return CallTool.Result(
                content: [MCPContent.text("Unsupported version '\(version)' for the selected report combination. Allowed versions: \(allowedVersions.joined(separator: ", "))")],
                isError: true
            )
        }
        let summaryOnly = arguments["summary_only"]?.boolValue ?? true
        let limit = min(max(arguments["limit"]?.intValue ?? 25, 1), 200)
        let appIdFilter: String?
        if let rawAppId = arguments["app_id"]?.stringValue {
            guard let normalizedAppId = Self.nonEmptyIdentifier(rawAppId) else {
                return CallTool.Result(
                    content: [MCPContent.text("Invalid app_id: value must not be empty")],
                    isError: true
                )
            }
            appIdFilter = normalizedAppId
        } else {
            appIdFilter = nil
        }

        do {
            let report = try await fetchReportSummary(
                vendorNumber: vendorNumber,
                reportType: reportType,
                reportSubType: reportSubType,
                frequency: frequency,
                reportDate: reportDate,
                version: version,
                appIdFilter: appIdFilter
            )

            var result: [String: Any] = [
                "success": true,
                "report_type": reportType,
                "report_sub_type": reportSubType,
                "frequency": frequency,
                "version": version,
                "total_rows": report.totalRows,
                "filtered_rows": report.rows.count,
                "summary": report.summary
            ]

            if let reportDate {
                result["report_date"] = reportDate
            }

            if let appId = appIdFilter {
                result["app_id_filter"] = appId
            }

            if !summaryOnly {
                let rows = Array(report.rows.prefix(limit))
                result["showing_rows"] = rows.count
                result["columns"] = report.headers
                result["rows"] = rows
            }

            return MCPResult.jsonObject(result)
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get sales report: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a combined analytics summary for an app in a single call
    /// - Returns: JSON with downloads, subscriptions, subscription events, and revenue sections
    /// - Throws: Error if required parameters are missing
    func getAppSummary(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let rawReportDate = arguments["report_date"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Missing required parameter: report_date")],
                isError: true
            )
        }

        guard let reportDate = Self.reportDate(rawReportDate) else {
            return CallTool.Result(
                content: [MCPContent.text("Invalid report_date: use a real calendar date in YYYY-MM-DD format")],
                isError: true
            )
        }

        guard let vendorNumber = await resolveVendorNumber(from: arguments) else {
            return CallTool.Result(
                content: [MCPContent.text("Missing vendor_number: provide it as parameter or set vendor_number in company config")],
                isError: true
            )
        }

        let appIdFilter: String?
        if let rawAppId = arguments["app_id"]?.stringValue {
            guard let normalizedAppId = Self.nonEmptyIdentifier(rawAppId) else {
                return CallTool.Result(
                    content: [MCPContent.text("Invalid app_id: value must not be empty")],
                    isError: true
                )
            }
            appIdFilter = normalizedAppId
        } else {
            appIdFilter = nil
        }

        let downloads = await fetchSectionSummary(
            vendorNumber: vendorNumber, reportType: "SALES",
            reportSubType: "SUMMARY", frequency: "DAILY",
            reportDate: reportDate, version: "1_0", appIdFilter: appIdFilter
        )
        let subscriptions = await fetchSectionSummary(
            vendorNumber: vendorNumber, reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY", frequency: "DAILY",
            reportDate: reportDate, version: "1_3", appIdFilter: appIdFilter
        )
        let events = await fetchSectionSummary(
            vendorNumber: vendorNumber, reportType: "SUBSCRIPTION_EVENT",
            reportSubType: "SUMMARY", frequency: "DAILY",
            reportDate: reportDate, version: "1_3", appIdFilter: appIdFilter
        )
        let revenue = await fetchSectionSummary(
            vendorNumber: vendorNumber, reportType: "SUBSCRIBER",
            reportSubType: "DETAILED", frequency: "DAILY",
            reportDate: reportDate, version: "1_3", appIdFilter: appIdFilter
        )

        let sections: [String: [String: Any]] = [
            "downloads": downloads,
            "subscriptions": subscriptions,
            "subscription_events": events,
            "revenue": revenue
        ]

        let succeeded = sections.values.filter { ($0["status"] as? String) == "success" }.count
        let failed = sections.count - succeeded
        let success = succeeded > 0

        var result: [String: Any] = [
            "success": success,
            "partial_success": success && failed > 0,
            "report_date": reportDate,
            "sections": sections,
            "sections_succeeded": succeeded,
            "sections_failed": failed
        ]

        if let appId = appIdFilter {
            result["app_id_filter"] = appId
        }

        return MCPResult.jsonObject(result, isError: !success)
    }

    /// Fetches a single report section, returning success or error dict
    private func fetchSectionSummary(
        vendorNumber: String,
        reportType: String,
        reportSubType: String,
        frequency: String,
        reportDate: String,
        version: String,
        appIdFilter: String?
    ) async -> [String: Any] {
        do {
            let report = try await fetchReportSummary(
                vendorNumber: vendorNumber,
                reportType: reportType,
                reportSubType: reportSubType,
                frequency: frequency,
                reportDate: reportDate,
                version: version,
                appIdFilter: appIdFilter
            )
            return [
                "status": "success",
                "version": version,
                "summary": report.summary,
                "total_rows": report.totalRows,
                "filtered_rows": report.rows.count
            ]
        } catch {
            return [
                "status": "error",
                "error_message": error.localizedDescription
            ]
        }
    }

    /// Gets a financial report from App Store Connect
    /// - Returns: Structured JSON with summary (always) and optional raw rows
    /// - Throws: Error if required parameters are missing or API call fails
    func getFinancialReport(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let regionCode = arguments["region_code"]?.stringValue,
              let reportDate = arguments["report_date"]?.stringValue,
              let reportType = arguments["report_type"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Missing required parameters: region_code, report_date, report_type")],
                isError: true
            )
        }

        guard let vendorNumber = await resolveVendorNumber(from: arguments) else {
            return CallTool.Result(
                content: [MCPContent.text("Missing vendor_number: provide it as parameter or set vendor_number in company config")],
                isError: true
            )
        }

        let summaryOnly = arguments["summary_only"]?.boolValue ?? true
        let limit = min(max(arguments["limit"]?.intValue ?? 25, 1), 200)

        do {
            let queryParams: [String: String] = [
                "filter[vendorNumber]": vendorNumber,
                "filter[regionCode]": regionCode,
                "filter[reportDate]": reportDate,
                "filter[reportType]": reportType
            ]

            let data = try await httpClient.getRaw("/v1/financeReports", parameters: queryParams, accept: "application/a-gzip")
            let tsvString = try decompressReportData(data)

            let allParsed = try TSVParser.parse(data: tsvString)
            let summary = ReportSummary.financialSummary(from: allParsed.rows)

            var result: [String: Any] = [
                "success": true,
                "report_type": reportType,
                "region_code": regionCode,
                "report_date": reportDate,
                "total_rows": allParsed.totalRowCount,
                "summary": summary
            ]

            if !summaryOnly {
                let rows = Array(allParsed.rows.prefix(max(limit, 0)))
                result["showing_rows"] = rows.count
                result["columns"] = allParsed.headers
                result["rows"] = rows
            }

            return MCPResult.jsonObject(result)
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get financial report: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists analytics report requests for an app
    /// - Returns: JSON array of report requests with attributes and pagination
    func listAnalyticsReportRequests(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/analyticsReportRequests"
            let limit = try Self.collectionLimit(arguments["limit"])
            let accessTypes = try Self.stringList(
                arguments["access_types"],
                name: "access_types",
                allowedValues: Self.analyticsAccessTypes
            )
            let includeReports = try Self.optionalBool(
                arguments["include_reports"],
                name: "include_reports"
            ) ?? false
            let limitReports: Int?
            if arguments["limit_reports"] != nil {
                guard includeReports else {
                    throw ASCError.parsing("limit_reports requires include_reports=true")
                }
                limitReports = try Self.collectionLimit(
                    arguments["limit_reports"],
                    name: "limit_reports",
                    maximum: 50,
                    defaultValue: 50
                )
            } else {
                limitReports = nil
            }

            var queryParams: [String: String] = ["limit": String(limit)]
            if let accessTypes {
                queryParams["filter[accessType]"] = accessTypes.joined(separator: ",")
            }
            if includeReports {
                queryParams["include"] = "reports"
            }
            if let limitReports {
                queryParams["limit[reports]"] = String(limitReports)
            }
            var requiredParameters = queryParams
            requiredParameters.removeValue(forKey: "limit")
            let response: ASCAnalyticsReportRequestsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: requiredParameters),
                    as: ASCAnalyticsReportRequestsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCAnalyticsReportRequestsResponse.self
                )
            }

            let requests = response.data.map { formatReportRequest($0) }

            var result: [String: Any] = [
                "success": true,
                "report_requests": requests,
                "count": requests.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let included = response.included {
                result["included_reports"] = included.map { formatReport($0) }
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list analytics report requests: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates an analytics report request for an app
    /// - Returns: JSON with created report request details
    func createAnalyticsReportRequest(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let accessTypeValue = arguments["access_type"],
              let accessType = accessTypeValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters 'app_id' and 'access_type' are missing")],
                isError: true
            )
        }

        do {
            let request = CreateAnalyticsReportRequestRequest(
                data: CreateAnalyticsReportRequestRequest.CreateAnalyticsReportRequestData(
                    attributes: CreateAnalyticsReportRequestRequest.CreateAnalyticsReportRequestAttributes(
                        accessType: accessType
                    ),
                    relationships: CreateAnalyticsReportRequestRequest.CreateAnalyticsReportRequestRelationships(
                        app: CreateAnalyticsReportRequestRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        )
                    )
                )
            )

            let response: ASCAnalyticsReportRequestResponse = try await httpClient.post(
                "/v1/analyticsReportRequests",
                body: request,
                as: ASCAnalyticsReportRequestResponse.self
            )

            let reportRequest = formatReportRequest(response.data)

            let result: [String: Any] = [
                "success": true,
                "report_request": reportRequest
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to create analytics report request: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Analytics Reports

    /// Lists analytics reports for a report request
    /// - Returns: JSON array of reports with category and name
    /// - Throws: Error if required parameters are missing or API call fails
    func listAnalyticsReports(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let requestId = arguments["request_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'request_id' is missing")],
                isError: true
            )
        }

        do {
            let endpoint = "/v1/analyticsReportRequests/\(try ASCPathSegment.encode(requestId))/reports"
            let limit = try Self.collectionLimit(arguments["limit"])
            let names = try Self.stringList(arguments["names"], name: "names")
            let categories = try Self.stringList(
                arguments["categories"],
                name: "categories",
                allowedValues: Self.analyticsCategories
            )
            var queryParams: [String: String] = ["limit": String(limit)]
            if let names {
                queryParams["filter[name]"] = names.joined(separator: ",")
            }
            if let categories {
                queryParams["filter[category]"] = categories.joined(separator: ",")
            }
            var requiredParameters = queryParams
            requiredParameters.removeValue(forKey: "limit")
            let response: ASCAnalyticsReportsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: requiredParameters),
                    as: ASCAnalyticsReportsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCAnalyticsReportsResponse.self
                )
            }

            let reports = response.data.map { formatReport($0) }

            var result: [String: Any] = [
                "success": true,
                "reports": reports,
                "count": reports.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list analytics reports: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific analytics report
    /// - Returns: JSON with report details including category and name
    /// - Throws: Error if required parameters are missing or API call fails
    func getAnalyticsReport(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reportId = arguments["report_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'report_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportResponse = try await httpClient.get(
                "/v1/analyticsReports/\(try ASCPathSegment.encode(reportId))",
                parameters: [:],
                as: ASCAnalyticsReportResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "report": formatReport(response.data)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get analytics report: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists instances of an analytics report
    /// - Returns: JSON array of report instances with granularity and processing date
    /// - Throws: Error if required parameters are missing or API call fails
    func listAnalyticsReportInstances(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reportId = arguments["report_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'report_id' is missing")],
                isError: true
            )
        }

        do {
            let endpoint = "/v1/analyticsReports/\(try ASCPathSegment.encode(reportId))/instances"
            let limit = try Self.collectionLimit(arguments["limit"])
            let granularities = try Self.stringList(
                arguments["granularities"],
                name: "granularities",
                allowedValues: Self.analyticsGranularities
            )
            let processingDates = try Self.processingDates(arguments["processing_dates"])
            var queryParams: [String: String] = ["limit": String(limit)]
            if let granularities {
                queryParams["filter[granularity]"] = granularities.joined(separator: ",")
            }
            if let processingDates {
                queryParams["filter[processingDate]"] = processingDates.joined(separator: ",")
            }
            var requiredParameters = queryParams
            requiredParameters.removeValue(forKey: "limit")
            let response: ASCAnalyticsReportInstancesResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: requiredParameters),
                    as: ASCAnalyticsReportInstancesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCAnalyticsReportInstancesResponse.self
                )
            }

            let instances = response.data.map { formatReportInstance($0) }

            var result: [String: Any] = [
                "success": true,
                "instances": instances,
                "count": instances.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list analytics report instances: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a specific analytics report instance
    /// - Returns: JSON with report instance details
    /// - Throws: Error if required parameters are missing or API call fails
    func getAnalyticsReportInstance(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let instanceId = arguments["instance_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'instance_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportInstanceResponse = try await httpClient.get(
                "/v1/analyticsReportInstances/\(try ASCPathSegment.encode(instanceId))",
                parameters: [:],
                as: ASCAnalyticsReportInstanceResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "instance": formatReportInstance(response.data)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get analytics report instance: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists segments of an analytics report instance
    /// - Returns: JSON array of report segments with download URLs
    /// - Throws: Error if required parameters are missing or API call fails
    func listAnalyticsReportSegments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let instanceId = arguments["instance_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'instance_id' is missing")],
                isError: true
            )
        }

        do {
            let endpoint = "/v1/analyticsReportInstances/\(try ASCPathSegment.encode(instanceId))/segments"
            let queryParams = ["limit": String(try Self.collectionLimit(arguments["limit"]))]
            let response: ASCAnalyticsReportSegmentsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(path: endpoint, query: queryParams),
                    as: ASCAnalyticsReportSegmentsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCAnalyticsReportSegmentsResponse.self
                )
            }

            let segments = response.data.map { formatReportSegment($0) }

            var result: [String: Any] = [
                "success": true,
                "segments": segments,
                "count": segments.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list analytics report segments: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Snapshot Status

    /// Checks readiness of all reports in an analytics snapshot
    /// - Returns: JSON summary with ready/pending counts and per-report details
    /// - Throws: Error if required parameters are missing or API call fails
    func checkSnapshotStatus(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let requestId = arguments["request_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'request_id' is missing")],
                isError: true
            )
        }

        let categoryFilter: String?
        if let categoryValue = arguments["category"] {
            guard let category = categoryValue.stringValue else {
                return CallTool.Result(
                    content: [MCPContent.text("Invalid category: value must be a string")],
                    isError: true
                )
            }
            guard Self.analyticsCategories.contains(category) else {
                return CallTool.Result(
                    content: [MCPContent.text("Unsupported category '\(category)'")],
                    isError: true
                )
            }
            categoryFilter = category
        } else {
            categoryFilter = nil
        }
        let nameFilter: String?
        if let nameValue = arguments["name"] {
            guard let rawName = nameValue.stringValue,
                  let name = Self.nonEmptyIdentifier(rawName) else {
                return CallTool.Result(
                    content: [MCPContent.text("Invalid name: value must be a non-empty string")],
                    isError: true
                )
            }
            nameFilter = name
        } else {
            nameFilter = nil
        }

        do {
            var allReports: [ASCAnalyticsReport] = []
            let reportsPath = "/v1/analyticsReportRequests/\(try ASCPathSegment.encode(requestId))/reports"
            var reportsQuery: [String: String] = ["limit": "200"]
            if let categoryFilter {
                reportsQuery["filter[category]"] = categoryFilter
            }
            if let nameFilter {
                reportsQuery["filter[name]"] = nameFilter
            }
            var reportsRequiredParameters = reportsQuery
            reportsRequiredParameters.removeValue(forKey: "limit")
            let reportsScope = PaginationScope(
                path: reportsPath,
                requiredParameters: reportsRequiredParameters
            )
            var nextURL: String?
            var seenNextURLs: Set<String> = []

            while true {
                let response: ASCAnalyticsReportsResponse
                if let nextURL {
                    response = try await httpClient.getPage(
                        nextURL,
                        scope: reportsScope,
                        as: ASCAnalyticsReportsResponse.self
                    )
                } else {
                    response = try await httpClient.get(
                        reportsPath,
                        parameters: reportsQuery,
                        as: ASCAnalyticsReportsResponse.self
                    )
                }
                allReports.append(contentsOf: response.data)

                guard let next = response.links?.next else { break }
                guard seenNextURLs.insert(next).inserted else {
                    throw ASCError.parsing("Analytics reports pagination returned a repeated next URL")
                }
                nextURL = next
            }

            let filteredReports = allReports.filter { report in
                let categoryMatches = categoryFilter == nil || report.attributes?.category == categoryFilter
                let nameMatches = nameFilter == nil || report.attributes?.name == nameFilter
                return categoryMatches && nameMatches
            }

            var readyCount = 0
            var pendingCount = 0
            var reportDetails: [[String: Any]] = []

            for report in filteredReports {
                let instancesResponse: ASCAnalyticsReportInstancesResponse = try await httpClient.get(
                    "/v1/analyticsReports/\(try ASCPathSegment.encode(report.id))/instances",
                    parameters: ["limit": "1"],
                    as: ASCAnalyticsReportInstancesResponse.self
                )

                let instancesCount = instancesResponse.data.count
                let status = instancesCount > 0 ? "ready" : "pending"

                if instancesCount > 0 {
                    readyCount += 1
                } else {
                    pendingCount += 1
                }

                var detail: [String: Any] = [
                    "id": report.id,
                    "name": report.attributes?.name ?? "unknown",
                    "category": report.attributes?.category ?? "unknown",
                    "status": status,
                    "instances_count": instancesCount
                ]

                if let firstInstance = instancesResponse.data.first,
                   let processingDate = firstInstance.attributes?.processingDate {
                    detail["latest_processing_date"] = processingDate
                }

                reportDetails.append(detail)
            }

            var result: [String: Any] = [
                "success": true,
                "request_id": requestId,
                "total_reports": filteredReports.count,
                "ready": readyCount,
                "pending": pendingCount,
                "reports": reportDetails
            ]

            if let category = categoryFilter {
                result["category_filter"] = category
            }
            if let nameFilter {
                result["name_filter"] = nameFilter
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to check snapshot status: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Report Data Decompression

    /// Returns a bounded UTF-8 TSV string after validating gzip reports when present.
    /// - Throws: A parsing or gzip integrity error for oversized, malformed, or non-UTF-8 data.
    private func decompressReportData(_ data: Data) throws -> String {
        let decodedData: Data
        if data.isGzipped {
            decodedData = try data.gunzipped()
        } else {
            guard data.count <= ReportDataLimits.maximumDecompressedBytes else {
                throw ASCError.parsing(
                    "Report data exceeds the \(ReportDataLimits.maximumDecompressedBytes / (1_024 * 1_024)) MiB safety limit. Request a smaller report."
                )
            }
            decodedData = data
        }

        guard !decodedData.isEmpty else {
            throw ASCError.parsing("Report data is empty")
        }
        guard let string = String(data: decodedData, encoding: .utf8) else {
            throw ASCError.parsing("Report data is not valid UTF-8")
        }
        return string
    }

    // MARK: - Formatting

    /// Formats an analytics report request as a dictionary for JSON output
    private func formatReportRequest(_ request: ASCAnalyticsReportRequest) -> [String: Any] {
        var dict: [String: Any] = [
            "id": request.id,
            "type": request.type
        ]
        if let accessType = request.attributes?.accessType {
            dict["access_type"] = accessType
        }
        if let stoppedDueToInactivity = request.attributes?.stoppedDueToInactivity {
            dict["stopped_due_to_inactivity"] = stoppedDueToInactivity
        }
        if let reportIDs = request.relationships?.reports?.data?.map(\.id) {
            dict["report_ids"] = reportIDs
        }
        if let reportsTotal = request.relationships?.reports?.meta?.paging?.total {
            dict["reports_total"] = reportsTotal
        }
        return dict
    }

    /// Formats an analytics report as a dictionary for JSON output
    private func formatReport(_ report: ASCAnalyticsReport) -> [String: Any] {
        var dict: [String: Any] = [
            "id": report.id,
            "type": report.type
        ]
        dict["category"] = (report.attributes?.category).jsonSafe
        dict["name"] = (report.attributes?.name).jsonSafe
        return dict
    }

    /// Formats an analytics report instance as a dictionary for JSON output
    private func formatReportInstance(_ instance: ASCAnalyticsReportInstance) -> [String: Any] {
        var dict: [String: Any] = [
            "id": instance.id,
            "type": instance.type
        ]
        dict["granularity"] = (instance.attributes?.granularity).jsonSafe
        dict["processing_date"] = (instance.attributes?.processingDate).jsonSafe
        return dict
    }

    /// Formats an analytics report segment as a dictionary for JSON output
    private func formatReportSegment(_ segment: ASCAnalyticsReportSegment) -> [String: Any] {
        var dict: [String: Any] = [
            "id": segment.id,
            "type": segment.type
        ]
        dict["checksum"] = (segment.attributes?.checksum).jsonSafe
        dict["size_in_bytes"] = (segment.attributes?.sizeInBytes).jsonSafe
        dict["url"] = (segment.attributes?.url).jsonSafe
        return dict
    }
}
