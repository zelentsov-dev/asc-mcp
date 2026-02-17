//
//  AnalyticsWorker.swift
//  asc-mcp
//
//  Sales reports, financial reports, and analytics in App Store Connect
//

import Foundation
import MCP

/// Worker for managing sales reports, financial reports, and analytics in App Store Connect
public final class AnalyticsWorker: Sendable {
    let httpClient: HTTPClient
    let companiesManager: CompaniesManager?

    public init(httpClient: HTTPClient, companiesManager: CompaniesManager? = nil) {
        self.httpClient = httpClient
        self.companiesManager = companiesManager
    }

    /// Get all available tools for analytics and reports management
    public func getTools() async -> [Tool] {
        return [
            getSalesReportTool(),
            getFinancialReportTool(),
            listAnalyticsReportRequestsTool(),
            createAnalyticsReportRequestTool(),
            listAnalyticsReportsTool(),
            getAnalyticsReportTool(),
            listAnalyticsReportInstancesTool(),
            getAnalyticsReportInstanceTool(),
            listAnalyticsReportSegmentsTool(),
            checkSnapshotStatusTool()
        ]
    }

    /// Handle tool call for analytics and reports operations
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "analytics_sales_report":
            return try await getSalesReport(params)
        case "analytics_financial_report":
            return try await getFinancialReport(params)
        case "analytics_list_report_requests":
            return try await listAnalyticsReportRequests(params)
        case "analytics_create_report_request":
            return try await createAnalyticsReportRequest(params)
        case "analytics_list_reports":
            return try await listAnalyticsReports(params)
        case "analytics_get_report":
            return try await getAnalyticsReport(params)
        case "analytics_list_instances":
            return try await listAnalyticsReportInstances(params)
        case "analytics_get_instance":
            return try await getAnalyticsReportInstance(params)
        case "analytics_list_segments":
            return try await listAnalyticsReportSegments(params)
        case "analytics_check_snapshot_status":
            return try await checkSnapshotStatus(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
