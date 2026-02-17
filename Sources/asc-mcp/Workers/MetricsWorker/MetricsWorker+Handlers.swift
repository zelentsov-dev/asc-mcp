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

            let data = try await httpClient.getRaw("/v1/apps/\(appId)/perfPowerMetrics", parameters: queryParams, accept: "application/vnd.apple.xcode-metrics+json")
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

            let data = try await httpClient.getRaw("/v1/builds/\(buildId)/perfPowerMetrics", parameters: queryParams, accept: "application/vnd.apple.xcode-metrics+json")
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

    /// Lists diagnostic signatures for a build
    /// - Returns: JSON array of diagnostic signatures with weight and insights
    /// - Throws: Error if required parameters are missing or API call fails
    func listDiagnostics(_ params: CallTool.Parameters) async throws -> CallTool.Result {
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
            let data = try await httpClient.getRaw("/v1/diagnosticSignatures/\(signatureId)/logs", accept: "application/vnd.apple.diagnostic-logs+json")

            // Parse raw JSON because response format (application/vnd.apple.diagnostic-logs+json)
            // is non-standard and Codable model may not match the actual response structure
            let logs: [[String: Any]]
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let productData = json["productData"] as? [[String: Any]] {
                logs = productData.map { formatDiagnosticLogProductDataRaw($0) }
            } else {
                // Fallback: try Codable decoding
                let response = try JSONDecoder().decode(ASCDiagnosticLogsResponse.self, from: data)
                logs = (response.productData ?? []).map { formatDiagnosticLogProductData($0) }
            }

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

    /// Formats diagnostic log product data from raw JSON (JSONSerialization)
    private func formatDiagnosticLogProductDataRaw(_ productData: [String: Any]) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["signature_id"] = productData["signatureId"] ?? NSNull()
        if let logs = productData["diagnosticLogs"] as? [[String: Any]] {
            dict["logs"] = logs.map { formatDiagnosticLogRaw($0) }
        } else {
            dict["logs"] = []
        }
        return dict
    }

    /// Formats a diagnostic log entry from raw JSON, handling callStackTree as string, base64, or dict
    private func formatDiagnosticLogRaw(_ log: [String: Any]) -> [String: Any] {
        var dict: [String: Any] = [:]

        if let treeDict = log["callStackTree"] as? [String: Any] {
            // callStackTree is already a JSON object
            dict["call_stack_per_thread"] = treeDict["callStackPerThread"] ?? NSNull()
            if let callStacks = treeDict["callStacks"] as? [[String: Any]] {
                dict["call_stacks"] = callStacks.map { formatCallStackRaw($0) }
            }
        } else if let treeString = log["callStackTree"] as? String {
            // callStackTree is a string — try base64 first, then raw JSON
            let jsonData: Data?
            if let base64Data = Data(base64Encoded: treeString) {
                jsonData = base64Data
            } else {
                jsonData = treeString.data(using: .utf8)
            }

            if let data = jsonData,
               let treeObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict["call_stack_per_thread"] = treeObj["callStackPerThread"] ?? NSNull()
                if let callStacks = treeObj["callStacks"] as? [[String: Any]] {
                    dict["call_stacks"] = callStacks.map { formatCallStackRaw($0) }
                }
            } else {
                dict["raw_call_stack_tree"] = treeString
            }
        }

        // If nothing was parsed, include raw callStackTree for debugging
        if dict.isEmpty, let rawTree = log["callStackTree"] {
            dict["raw_call_stack_tree"] = "\(rawTree)"
        }

        // Also include any other keys from the log besides callStackTree
        for (key, value) in log where key != "callStackTree" {
            dict[key] = value
        }

        return dict
    }

    /// Formats a call stack from raw JSON
    private func formatCallStackRaw(_ stack: [String: Any]) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["thread_attributed"] = stack["threadAttributed"] ?? NSNull()
        if let rootFrames = stack["callStackRootFrames"] as? [[String: Any]] {
            dict["root_frames"] = rootFrames.map { formatCallStackFrameRaw($0) }
        }
        return dict
    }

    /// Formats a call stack frame from raw JSON (recursive for subframes)
    private func formatCallStackFrameRaw(_ frame: [String: Any]) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["binary_name"] = frame["binaryName"] ?? NSNull()
        dict["address"] = frame["address"] ?? NSNull()
        dict["offset"] = frame["offsetIntoBinaryTextSegment"] ?? NSNull()
        dict["raw_frame"] = frame["rawFrame"] ?? NSNull()
        if let subFrames = frame["subFrames"] as? [[String: Any]], !subFrames.isEmpty {
            dict["sub_frames"] = subFrames.map { formatCallStackFrameRaw($0) }
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

    /// Formats a diagnostic log entry, decoding callStackTree from base64 or raw JSON string
    private func formatDiagnosticLog(_ log: ASCDiagnosticLog) -> [String: Any] {
        var dict: [String: Any] = [:]
        guard let treeString = log.callStackTree else { return dict }

        // Try to decode: first as base64, then as raw JSON string
        let jsonData: Data?
        if let base64Data = Data(base64Encoded: treeString) {
            jsonData = base64Data
        } else {
            jsonData = treeString.data(using: .utf8)
        }

        if let data = jsonData,
           let tree = try? JSONDecoder().decode(ASCCallStackTree.self, from: data) {
            dict["call_stack_per_thread"] = tree.callStackPerThread.jsonSafe
            dict["call_stacks"] = (tree.callStacks ?? []).map { formatCallStack($0) }
        }

        // If nothing was parsed, include raw string for debugging
        if dict.isEmpty {
            dict["raw_call_stack_tree"] = treeString
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
