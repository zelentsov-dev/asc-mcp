//
//  AnalyticsWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of analytics and reports handlers
//

import Foundation
import MCP

extension AnalyticsWorker {

    /// Resolves vendor number from explicit parameter or company config
    /// - Returns: Vendor number string or nil if not available
    private func resolveVendorNumber(from arguments: [String: Value]?) async -> String? {
        if let explicit = arguments?["vendor_number"]?.stringValue {
            return explicit
        }
        if let manager = companiesManager,
           let company = try? await manager.getCurrentCompany(),
           let vendorNumber = company.vendorNumber {
            return vendorNumber
        }
        return nil
    }

    /// Default report version by report type (latest known as of 2026)
    private static let defaultReportVersions: [String: String] = [
        "SALES": "1_0",
        "PRE_ORDER": "1_1",
        "NEWSSTAND": "1_0",
        "SUBSCRIPTION": "1_3",
        "SUBSCRIPTION_EVENT": "1_4",
        "SUBSCRIBER": "1_3",
        "SUBSCRIPTION_OFFER_CODE_REDEMPTION": "1_0"
    ]

    /// Fetches and parses a sales report, returning summary and row counts
    /// - Returns: Tuple with summary dict, total row count, and filtered row count
    /// - Throws: Error if API call or decompression fails
    private func fetchReportSummary(
        vendorNumber: String,
        reportType: String,
        reportSubType: String,
        frequency: String,
        reportDate: String,
        version: String? = nil,
        appIdFilter: String? = nil
    ) async throws -> (summary: [String: Any], totalRows: Int, filteredRows: Int) {
        let resolvedVersion = version
            ?? Self.defaultReportVersions[reportType]
            ?? "1_0"

        let queryParams: [String: String] = [
            "filter[vendorNumber]": vendorNumber,
            "filter[reportType]": reportType,
            "filter[reportSubType]": reportSubType,
            "filter[frequency]": frequency,
            "filter[reportDate]": reportDate,
            "filter[version]": resolvedVersion
        ]

        let data = try await httpClient.getRaw("/v1/salesReports", parameters: queryParams, accept: "application/a-gzip")

        guard let tsvString = decompressReportData(data) else {
            throw ASCError.parsing("Failed to decode report data: not valid UTF-8 or gzip")
        }

        let allParsed = TSVParser.parse(data: tsvString)

        let filteredRows: [[String: String]]
        if let appId = appIdFilter {
            filteredRows = allParsed.rows.filter { row in
                row["Apple Identifier"] == appId || row["App Apple ID"] == appId
            }
        } else {
            filteredRows = allParsed.rows
        }

        let summary = ReportSummary.summary(for: reportType, from: filteredRows)
        return (summary: summary, totalRows: allParsed.totalRowCount, filteredRows: filteredRows.count)
    }

    /// Gets a sales/download report from App Store Connect
    /// - Returns: Structured JSON with summary (always) and optional raw rows
    /// - Throws: Error if required parameters are missing or API call fails
    func getSalesReport(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reportType = arguments["report_type"]?.stringValue,
              let reportSubType = arguments["report_sub_type"]?.stringValue,
              let frequency = arguments["frequency"]?.stringValue,
              let reportDate = arguments["report_date"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameters: report_type, report_sub_type, frequency, report_date")],
                isError: true
            )
        }

        guard let vendorNumber = await resolveVendorNumber(from: arguments) else {
            return CallTool.Result(
                content: [.text("Missing vendor_number: provide it as parameter or set vendor_number in company config")],
                isError: true
            )
        }

        let version = arguments["version"]?.stringValue
        let summaryOnly = arguments["summary_only"]?.boolValue ?? true
        let limit = arguments["limit"]?.intValue ?? 25
        let appIdFilter = arguments["app_id"]?.stringValue

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

            let resolvedVersion = version
                ?? Self.defaultReportVersions[reportType]
                ?? "1_0"

            var result: [String: Any] = [
                "success": true,
                "report_type": reportType,
                "report_sub_type": reportSubType,
                "frequency": frequency,
                "report_date": reportDate,
                "version": resolvedVersion,
                "total_rows": report.totalRows,
                "filtered_rows": report.filteredRows,
                "summary": report.summary
            ]

            if let appId = appIdFilter {
                result["app_id_filter"] = appId
            }

            if !summaryOnly {
                // Re-fetch raw rows for display (fetchReportSummary doesn't return them)
                let queryParams: [String: String] = [
                    "filter[vendorNumber]": vendorNumber,
                    "filter[reportType]": reportType,
                    "filter[reportSubType]": reportSubType,
                    "filter[frequency]": frequency,
                    "filter[reportDate]": reportDate,
                    "filter[version]": resolvedVersion
                ]
                let data = try await httpClient.getRaw("/v1/salesReports", parameters: queryParams, accept: "application/a-gzip")
                if let tsvString = decompressReportData(data) {
                    let allParsed = TSVParser.parse(data: tsvString)
                    let filteredRows: [[String: String]]
                    if let appId = appIdFilter {
                        filteredRows = allParsed.rows.filter { row in
                            row["Apple Identifier"] == appId || row["App Apple ID"] == appId
                        }
                    } else {
                        filteredRows = allParsed.rows
                    }
                    let rows = Array(filteredRows.prefix(limit))
                    result["showing_rows"] = rows.count
                    result["columns"] = allParsed.headers
                    result["rows"] = rows
                }
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
        } catch {
            return CallTool.Result(
                content: [.text("Failed to get sales report: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a combined analytics summary for an app in a single call
    /// - Returns: JSON with downloads, subscriptions, subscription events, and revenue sections
    /// - Throws: Error if required parameters are missing
    func getAppSummary(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reportDate = arguments["report_date"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: report_date")],
                isError: true
            )
        }

        guard let vendorNumber = await resolveVendorNumber(from: arguments) else {
            return CallTool.Result(
                content: [.text("Missing vendor_number: provide it as parameter or set vendor_number in company config")],
                isError: true
            )
        }

        let appIdFilter = arguments["app_id"]?.stringValue

        // Fetch 4 report types in parallel with partial success handling
        async let downloadsTask = fetchSectionSummary(
            vendorNumber: vendorNumber, reportType: "SALES",
            reportSubType: "SUMMARY", frequency: "DAILY",
            reportDate: reportDate, appIdFilter: appIdFilter
        )
        async let subscriptionsTask = fetchSectionSummary(
            vendorNumber: vendorNumber, reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY", frequency: "DAILY",
            reportDate: reportDate, appIdFilter: appIdFilter
        )
        async let eventsTask = fetchSectionSummary(
            vendorNumber: vendorNumber, reportType: "SUBSCRIPTION_EVENT",
            reportSubType: "SUMMARY", frequency: "DAILY",
            reportDate: reportDate, appIdFilter: appIdFilter
        )
        async let revenueTask = fetchSectionSummary(
            vendorNumber: vendorNumber, reportType: "SUBSCRIBER",
            reportSubType: "DETAILED", frequency: "DAILY",
            reportDate: reportDate, appIdFilter: appIdFilter
        )

        let downloads = await downloadsTask
        let subscriptions = await subscriptionsTask
        let events = await eventsTask
        let revenue = await revenueTask

        let sections: [String: [String: Any]] = [
            "downloads": downloads,
            "subscriptions": subscriptions,
            "subscription_events": events,
            "revenue": revenue
        ]

        let succeeded = sections.values.filter { ($0["status"] as? String) == "success" }.count
        let failed = sections.count - succeeded

        var result: [String: Any] = [
            "success": true,
            "report_date": reportDate,
            "sections": sections,
            "sections_succeeded": succeeded,
            "sections_failed": failed
        ]

        if let appId = appIdFilter {
            result["app_id_filter"] = appId
        }

        return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
    }

    /// Fetches a single report section, returning success or error dict
    private func fetchSectionSummary(
        vendorNumber: String,
        reportType: String,
        reportSubType: String,
        frequency: String,
        reportDate: String,
        appIdFilter: String?
    ) async -> [String: Any] {
        do {
            let report = try await fetchReportSummary(
                vendorNumber: vendorNumber,
                reportType: reportType,
                reportSubType: reportSubType,
                frequency: frequency,
                reportDate: reportDate,
                appIdFilter: appIdFilter
            )
            return [
                "status": "success",
                "summary": report.summary,
                "total_rows": report.totalRows,
                "filtered_rows": report.filteredRows
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
                content: [.text("Missing required parameters: region_code, report_date, report_type")],
                isError: true
            )
        }

        guard let vendorNumber = await resolveVendorNumber(from: arguments) else {
            return CallTool.Result(
                content: [.text("Missing vendor_number: provide it as parameter or set vendor_number in company config")],
                isError: true
            )
        }

        let summaryOnly = arguments["summary_only"]?.boolValue ?? true
        let limit = arguments["limit"]?.intValue ?? 25

        do {
            let queryParams: [String: String] = [
                "filter[vendorNumber]": vendorNumber,
                "filter[regionCode]": regionCode,
                "filter[reportDate]": reportDate,
                "filter[reportType]": reportType
            ]

            let data = try await httpClient.getRaw("/v1/financeReports", parameters: queryParams, accept: "application/a-gzip")
            let tsvString = decompressReportData(data)

            guard let tsvString else {
                return CallTool.Result(
                    content: [.text("Failed to decode report data: not valid UTF-8 or gzip")],
                    isError: true
                )
            }

            let allParsed = TSVParser.parse(data: tsvString)
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
                let limitedParsed = TSVParser.parse(data: tsvString, limit: limit)
                result["showing_rows"] = limitedParsed.rows.count
                result["columns"] = limitedParsed.headers
                result["rows"] = limitedParsed.rows
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
        } catch {
            return CallTool.Result(
                content: [.text("Failed to get financial report: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportRequestsResponse

            // Check for pagination URL
            if let nextUrlValue = arguments["next_url"],
               let nextUrl = nextUrlValue.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAnalyticsReportRequestsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/analyticsReportRequests",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list analytics report requests: \(error.localizedDescription)")],
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
                content: [.text("Required parameters 'app_id' and 'access_type' are missing")],
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create analytics report request: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'request_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAnalyticsReportsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/analyticsReportRequests/\(requestId)/reports",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list analytics reports: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'report_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportResponse = try await httpClient.get(
                "/v1/analyticsReports/\(reportId)",
                parameters: [:],
                as: ASCAnalyticsReportResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "report": formatReport(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get analytics report: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'report_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportInstancesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAnalyticsReportInstancesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/analyticsReports/\(reportId)/instances",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list analytics report instances: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'instance_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportInstanceResponse = try await httpClient.get(
                "/v1/analyticsReportInstances/\(instanceId)",
                parameters: [:],
                as: ASCAnalyticsReportInstanceResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "instance": formatReportInstance(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get analytics report instance: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'instance_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportSegmentsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAnalyticsReportSegmentsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/analyticsReportInstances/\(instanceId)/segments",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list analytics report segments: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'request_id' is missing")],
                isError: true
            )
        }

        let categoryFilter = arguments["category"]?.stringValue

        do {
            // Fetch all reports for this request (paginated)
            var allReports: [ASCAnalyticsReport] = []
            var nextPath: String? = "/v1/analyticsReportRequests/\(requestId)/reports"
            var nextParams: [String: String] = ["limit": "200"]

            while let path = nextPath {
                let response: ASCAnalyticsReportsResponse = try await httpClient.get(
                    path, parameters: nextParams, as: ASCAnalyticsReportsResponse.self
                )
                allReports.append(contentsOf: response.data)

                if let nextUrl = response.links?.next, let parsed = parsePaginationUrl(nextUrl) {
                    nextPath = parsed.path
                    nextParams = parsed.parameters
                } else {
                    nextPath = nil
                }
            }

            // Filter by category if specified
            let filteredReports: [ASCAnalyticsReport]
            if let category = categoryFilter {
                filteredReports = allReports.filter { $0.attributes?.category == category }
            } else {
                filteredReports = allReports
            }

            // Check instances for each report
            var readyCount = 0
            var pendingCount = 0
            var reportDetails: [[String: Any]] = []

            for report in filteredReports {
                let instancesResponse: ASCAnalyticsReportInstancesResponse = try await httpClient.get(
                    "/v1/analyticsReports/\(report.id)/instances",
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

                // Include first instance processing date if available
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to check snapshot status: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Report Data Decompression

    /// Attempts to get UTF-8 string from report data, decompressing gzip if needed
    /// - Returns: UTF-8 TSV string or nil if data cannot be decoded
    private func decompressReportData(_ data: Data) -> String? {
        // Try direct UTF-8 first (URLSession may have auto-decompressed)
        if let string = String(data: data, encoding: .utf8),
           !string.isEmpty {
            return string
        }
        // Try gzip decompression
        if let decompressed = data.gunzipped(),
           let string = String(data: decompressed, encoding: .utf8) {
            return string
        }
        return nil
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
        return dict
    }

    /// Formats an analytics report as a dictionary for JSON output
    private func formatReport(_ report: ASCAnalyticsReport) -> [String: Any] {
        var dict: [String: Any] = [
            "id": report.id,
            "type": report.type
        ]
        dict["category"] = report.attributes?.category.jsonSafe ?? NSNull()
        dict["name"] = report.attributes?.name.jsonSafe ?? NSNull()
        return dict
    }

    /// Formats an analytics report instance as a dictionary for JSON output
    private func formatReportInstance(_ instance: ASCAnalyticsReportInstance) -> [String: Any] {
        var dict: [String: Any] = [
            "id": instance.id,
            "type": instance.type
        ]
        dict["granularity"] = instance.attributes?.granularity.jsonSafe ?? NSNull()
        dict["processing_date"] = instance.attributes?.processingDate.jsonSafe ?? NSNull()
        return dict
    }

    /// Formats an analytics report segment as a dictionary for JSON output
    private func formatReportSegment(_ segment: ASCAnalyticsReportSegment) -> [String: Any] {
        var dict: [String: Any] = [
            "id": segment.id,
            "type": segment.type
        ]
        dict["checksum"] = segment.attributes?.checksum.jsonSafe ?? NSNull()
        dict["size_in_bytes"] = segment.attributes?.sizeInBytes.jsonSafe ?? NSNull()
        dict["url"] = segment.attributes?.url.jsonSafe ?? NSNull()
        return dict
    }
}
