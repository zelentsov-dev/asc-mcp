//
//  MetricsWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of performance metrics and diagnostics handlers
//

import Foundation
import MCP

extension MetricsWorker {

    /// Gets performance/power metrics for an app
    /// - Returns: JSON with metric categories, datasets, and data points
    /// - Throws: Error if required parameters are missing or API call fails
    func getAppPerfMetrics(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue,
              let metricType = arguments["metric_type"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters: app_id, metric_type")],
                isError: true
            )
        }

        do {
            let queryParams: [String: String] = [
                "filter[metricType]": metricType
            ]

            let data = try await httpClient.get("/v1/apps/\(appId)/perfPowerMetrics", parameters: queryParams)
            let response = try JSONDecoder().decode(ASCPerfPowerMetricsResponse.self, from: data)

            let result: [String: Any] = [
                "success": true,
                "metric_type": metricType,
                "product_data": (response.productData ?? []).map { formatProductData($0) }
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get app performance metrics: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets performance/power metrics for a specific build
    /// - Returns: JSON with metric categories, datasets, and data points
    /// - Throws: Error if required parameters are missing or API call fails
    func getBuildPerfMetrics(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildId = arguments["build_id"]?.stringValue,
              let metricType = arguments["metric_type"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters: build_id, metric_type")],
                isError: true
            )
        }

        do {
            let queryParams: [String: String] = [
                "filter[metricType]": metricType
            ]

            let data = try await httpClient.get("/v1/builds/\(buildId)/perfPowerMetrics", parameters: queryParams)
            let response = try JSONDecoder().decode(ASCPerfPowerMetricsResponse.self, from: data)

            let result: [String: Any] = [
                "success": true,
                "metric_type": metricType,
                "product_data": (response.productData ?? []).map { formatProductData($0) }
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get build performance metrics: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists diagnostic signatures for an app
    /// - Returns: JSON array of diagnostic signatures with weight and insights
    /// - Throws: Error if required parameters are missing or API call fails
    func listDiagnostics(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCDiagnosticSignaturesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCDiagnosticSignaturesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let diagnosticType = arguments["diagnostic_type"]?.stringValue {
                    queryParams["filter[diagnosticType]"] = diagnosticType
                }

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/diagnosticSignatures",
                    parameters: queryParams,
                    as: ASCDiagnosticSignaturesResponse.self
                )
            }

            let signatures = response.data.map { formatDiagnosticSignature($0) }

            var result: [String: Any] = [
                "success": true,
                "diagnostic_signatures": signatures,
                "count": signatures.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list diagnostic signatures: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists diagnostic signatures for a specific build
    /// - Returns: JSON array of diagnostic signatures with weight and insights
    /// - Throws: Error if required parameters are missing or API call fails
    func getBuildDiagnostics(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildId = arguments["build_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCDiagnosticSignaturesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCDiagnosticSignaturesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let diagnosticType = arguments["diagnostic_type"]?.stringValue {
                    queryParams["filter[diagnosticType]"] = diagnosticType
                }

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/builds/\(buildId)/diagnosticSignatures",
                    parameters: queryParams,
                    as: ASCDiagnosticSignaturesResponse.self
                )
            }

            let signatures = response.data.map { formatDiagnosticSignature($0) }

            var result: [String: Any] = [
                "success": true,
                "diagnostic_signatures": signatures,
                "count": signatures.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list build diagnostic signatures: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets diagnostic logs for a specific diagnostic signature
    /// - Returns: JSON with call stack trees and frame details
    /// - Throws: Error if required parameters are missing or API call fails
    func getDiagnosticLogs(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let signatureId = arguments["signature_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'signature_id' is missing")],
                isError: true
            )
        }

        do {
            let data = try await httpClient.get("/v1/diagnosticSignatures/\(signatureId)/logs")
            let response = try JSONDecoder().decode(ASCDiagnosticLogsResponse.self, from: data)

            let logs = (response.productData ?? []).map { formatDiagnosticLogProductData($0) }

            let result: [String: Any] = [
                "success": true,
                "signature_id": signatureId,
                "diagnostic_logs": logs
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get diagnostic logs: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    /// Formats product data from perfPowerMetrics response
    private func formatProductData(_ productData: ASCProductData) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["platform"] = productData.platform.jsonSafe
        dict["metric_categories"] = (productData.metricCategories ?? []).map { formatMetricCategory($0) }
        return dict
    }

    /// Formats a metric category
    private func formatMetricCategory(_ category: ASCMetricCategory) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["identifier"] = category.identifier.jsonSafe
        dict["metrics"] = (category.metrics ?? []).map { formatMetric($0) }
        return dict
    }

    /// Formats an individual metric
    private func formatMetric(_ metric: ASCMetric) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["identifier"] = metric.identifier.jsonSafe
        if let unit = metric.unit {
            dict["unit"] = [
                "identifier": unit.identifier.jsonSafe,
                "display_name": unit.displayName.jsonSafe
            ]
        }
        dict["datasets"] = (metric.datasets ?? []).map { formatDataset($0) }
        return dict
    }

    /// Formats a metric dataset
    private func formatDataset(_ dataset: ASCMetricDataset) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let criteria = dataset.filterCriteria {
            dict["filter_criteria"] = [
                "device": criteria.device.jsonSafe,
                "device_marketing_name": criteria.deviceMarketingName.jsonSafe,
                "percentile": criteria.percentile.jsonSafe
            ]
        }
        dict["points"] = (dataset.points ?? []).map { formatPoint($0) }
        return dict
    }

    /// Formats a metric data point
    private func formatPoint(_ point: ASCMetricPoint) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["version"] = point.version.jsonSafe
        dict["value"] = point.value.jsonSafe
        dict["goal"] = point.goal.jsonSafe
        if let breakdown = point.percentageBreakdown {
            dict["percentage_breakdown"] = [
                "value": breakdown.value.jsonSafe,
                "sub_system_label": breakdown.subSystemLabel.jsonSafe
            ]
        }
        return dict
    }

    /// Formats a diagnostic signature for JSON output
    private func formatDiagnosticSignature(_ signature: ASCDiagnosticSignature) -> [String: Any] {
        var dict: [String: Any] = [
            "id": signature.id,
            "type": signature.type
        ]
        if let attrs = signature.attributes {
            dict["diagnostic_type"] = attrs.diagnosticType.jsonSafe
            dict["signature"] = attrs.signature.jsonSafe
            dict["weight"] = attrs.weight.jsonSafe
            if let insight = attrs.insight {
                dict["insight"] = [
                    "insight_type": insight.insightType.jsonSafe,
                    "reference_url": insight.referenceURL.jsonSafe
                ]
            }
        }
        return dict
    }

    /// Formats diagnostic log product data
    private func formatDiagnosticLogProductData(_ productData: ASCDiagnosticLogProductData) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["signature_id"] = productData.signatureId.jsonSafe
        dict["logs"] = (productData.diagnosticLogs ?? []).map { formatDiagnosticLog($0) }
        return dict
    }

    /// Formats a diagnostic log entry
    private func formatDiagnosticLog(_ log: ASCDiagnosticLog) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let tree = log.callStackTree {
            dict["call_stack_per_thread"] = tree.callStackPerThread.jsonSafe
            dict["call_stacks"] = (tree.callStacks ?? []).map { formatCallStack($0) }
        }
        return dict
    }

    /// Formats a call stack
    private func formatCallStack(_ stack: ASCCallStack) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["thread_attributed"] = stack.threadAttributed.jsonSafe
        dict["root_frames"] = (stack.callStackRootFrames ?? []).map { formatCallStackFrame($0) }
        return dict
    }

    /// Formats a call stack frame (recursive for subframes)
    private func formatCallStackFrame(_ frame: ASCCallStackFrame) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["binary_name"] = frame.binaryName.jsonSafe
        dict["address"] = frame.address.jsonSafe
        dict["offset"] = frame.offsetIntoBinaryTextSegment.jsonSafe
        dict["raw_frame"] = frame.rawFrame.jsonSafe
        if let subFrames = frame.subFrames, !subFrames.isEmpty {
            dict["sub_frames"] = subFrames.map { formatCallStackFrame($0) }
        }
        return dict
    }
}
