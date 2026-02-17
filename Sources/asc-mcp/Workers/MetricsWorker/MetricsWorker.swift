//
//  MetricsWorker.swift
//  asc-mcp
//
//  Performance metrics, diagnostics, and power metrics for App Store Connect
//

import Foundation
import MCP

/// Worker for managing performance metrics and diagnostics in App Store Connect
public final class MetricsWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get all available tools for metrics and diagnostics management
    public func getTools() async -> [Tool] {
        return [
            appPerfMetricsTool(),
            buildPerfMetricsTool(),
            buildDiagnosticsTool(),
            getDiagnosticLogsTool()
        ]
    }

    /// Handle tool call for metrics and diagnostics operations
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "metrics_app_perf":
            return try await getAppPerfMetrics(params)
        case "metrics_build_perf":
            return try await getBuildPerfMetrics(params)
        case "metrics_build_diagnostics":
            return try await getBuildDiagnostics(params)
        case "metrics_get_diagnostic_logs":
            return try await getDiagnosticLogs(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
