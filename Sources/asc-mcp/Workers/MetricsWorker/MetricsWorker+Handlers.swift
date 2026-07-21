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
              let appId = arguments["app_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let metricTypes = try filterSelection(
                arguments["metric_type"],
                name: "metric_type",
                allowedValues: Set(MetricsWorker.supportedMetricTypes)
            )
            let deviceTypes = try filterSelection(
                arguments["device_type"],
                name: "device_type"
            )
            let queryParams = perfPowerQuery(metricTypes: metricTypes, deviceTypes: deviceTypes)

            let data = try await httpClient.getRaw("/v1/apps/\(try ASCPathSegment.encode(appId))/perfPowerMetrics", parameters: queryParams, accept: "application/vnd.apple.xcode-metrics+json")
            let response = try JSONDecoder().decode(ASCPerfPowerMetricsResponse.self, from: data)
            let result = formatPerfPowerResponse(
                response,
                metricTypes: metricTypes,
                deviceTypes: deviceTypes
            )

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get app performance metrics: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets performance/power metrics for a specific build
    /// - Returns: JSON with metric categories, datasets, and data points
    /// - Throws: Error if required parameters are missing or API call fails
    func getBuildPerfMetrics(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildId = arguments["build_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let metricTypes = try filterSelection(
                arguments["metric_type"],
                name: "metric_type",
                allowedValues: Set(MetricsWorker.supportedMetricTypes)
            )
            let deviceTypes = try filterSelection(
                arguments["device_type"],
                name: "device_type"
            )
            let queryParams = perfPowerQuery(metricTypes: metricTypes, deviceTypes: deviceTypes)

            let data = try await httpClient.getRaw("/v1/builds/\(try ASCPathSegment.encode(buildId))/perfPowerMetrics", parameters: queryParams, accept: "application/vnd.apple.xcode-metrics+json")
            let response = try JSONDecoder().decode(ASCPerfPowerMetricsResponse.self, from: data)
            let result = formatPerfPowerResponse(
                response,
                metricTypes: metricTypes,
                deviceTypes: deviceTypes
            )

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get build performance metrics: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCDiagnosticSignaturesResponse
            var queryParams: [String: String] = [:]

            let diagnosticTypes = try filterSelection(
                arguments["diagnostic_type"],
                name: "diagnostic_type",
                allowedValues: Set(MetricsWorker.supportedDiagnosticTypes)
            )
            if let diagnosticTypes {
                queryParams["filter[diagnosticType]"] = diagnosticTypes.queryValue
            }

            queryParams["limit"] = String(try metricsLimit(arguments["limit"], defaultValue: 25))

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/builds/\(try ASCPathSegment.encode(buildId))/diagnosticSignatures",
                        query: queryParams
                    ),
                    as: ASCDiagnosticSignaturesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/builds/\(try ASCPathSegment.encode(buildId))/diagnosticSignatures",
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
            if let diagnosticTypes {
                result["diagnostic_type"] = diagnosticTypes.echo.asAny
            }

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to list build diagnostic signatures")
        }
    }

    /// Gets diagnostic logs for a specific diagnostic signature
    /// - Returns: JSON with call stack trees and frame details
    /// - Throws: Error if required parameters are missing or API call fails
    func getDiagnosticLogs(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let signatureId = arguments["signature_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'signature_id' is missing")],
                isError: true
            )
        }

        do {
            var queryParams: [String: String] = [:]
            if arguments["limit"] != nil {
                queryParams["limit"] = String(try metricsLimit(arguments["limit"], defaultValue: 25))
            }

            let data = try await httpClient.getRaw(
                "/v1/diagnosticSignatures/\(try ASCPathSegment.encode(signatureId))/logs",
                parameters: queryParams,
                accept: "application/vnd.apple.diagnostic-logs+json"
            )
            let response = try JSONDecoder().decode(ASCDiagnosticLogsResponse.self, from: data)

            let result: [String: Any] = [
                "success": true,
                "signature_id": signatureId,
                "version": response.version.jsonSafe,
                "diagnostic_logs": (response.productData ?? []).map { formatDiagnosticLogProductData($0) }
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to get diagnostic logs")
        }
    }

    private func metricsLimit(_ value: Value?, defaultValue: Int) throws -> Int {
        guard let value else { return defaultValue }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw ASCError.parsing("limit must be an integer from 1 through 200")
        }
        return limit
    }

    // MARK: - Formatting

    private func perfPowerQuery(
        metricTypes: MetricsFilterSelection?,
        deviceTypes: MetricsFilterSelection?
    ) -> [String: String] {
        var query: [String: String] = [:]
        if let metricTypes {
            query["filter[metricType]"] = metricTypes.queryValue
        }
        if let deviceTypes {
            query["filter[deviceType]"] = deviceTypes.queryValue
        }
        return query
    }

    private func formatPerfPowerResponse(
        _ response: ASCPerfPowerMetricsResponse,
        metricTypes: MetricsFilterSelection?,
        deviceTypes: MetricsFilterSelection?
    ) -> [String: Any] {
        var result: [String: Any] = [
            "success": true,
            "product_data": (response.productData ?? []).map { formatProductData($0) }
        ]
        if let metricTypes {
            result["metric_type"] = metricTypes.echo.asAny
        }
        if let deviceTypes {
            result["device_type"] = deviceTypes.echo.asAny
        }
        if let version = response.version {
            result["version"] = version
        }
        if let insights = response.insights {
            result["insights"] = formatMetricsInsights(insights)
        }
        return result
    }

    private func filterSelection(
        _ value: Value?,
        name: String,
        allowedValues: Set<String>? = nil
    ) throws -> MetricsFilterSelection? {
        guard let value else {
            return nil
        }

        let values: [String]
        let echo: MetricsFilterEcho
        if let string = value.stringValue {
            values = [string]
            echo = .scalar(string)
        } else if let array = value.arrayValue {
            let strings = array.compactMap(\.stringValue)
            guard strings.count == array.count else {
                throw ASCError.parsing("'\(name)' must be a string or an array of strings")
            }
            values = strings
            echo = .array(strings)
        } else {
            throw ASCError.parsing("'\(name)' must be a string or an array of strings")
        }

        guard !values.isEmpty else {
            throw ASCError.parsing("'\(name)' must contain at least one value")
        }
        guard values.allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed == value
        }) else {
            throw ASCError.parsing("'\(name)' must contain only non-empty strings without surrounding whitespace")
        }
        guard Set(values).count == values.count else {
            throw ASCError.parsing("'\(name)' must not contain duplicate values")
        }
        if let allowedValues {
            let unsupported = values.filter { !allowedValues.contains($0) }
            guard unsupported.isEmpty else {
                throw ASCError.parsing("Unsupported value(s) for '\(name)': \(unsupported.joined(separator: ", "))")
            }
        }

        return MetricsFilterSelection(
            queryValue: values.joined(separator: ","),
            echo: echo
        )
    }

    private func formatMetricsInsights(_ insights: ASCMetricsInsights) -> [String: Any] {
        [
            "trending_up": (insights.trendingUp ?? []).map { formatMetricsInsight($0) },
            "regressions": (insights.regressions ?? []).map { formatMetricsInsight($0) }
        ]
    }

    private func formatMetricsInsight(_ insight: ASCMetricsInsight) -> [String: Any] {
        [
            "metric_category": insight.metricCategory.jsonSafe,
            "latest_version": insight.latestVersion.jsonSafe,
            "metric": insight.metric.jsonSafe,
            "summary": insight.summaryString.jsonSafe,
            "reference_versions": insight.referenceVersions.jsonSafe,
            "max_latest_version_value": insight.maxLatestVersionValue.jsonSafe,
            "sub_system_label": insight.subSystemLabel.jsonSafe,
            "high_impact": insight.highImpact.jsonSafe,
            "populations": (insight.populations ?? []).map { formatMetricsInsightPopulation($0) }
        ]
    }

    private func formatMetricsInsightPopulation(_ population: ASCMetricsInsightPopulation) -> [String: Any] {
        [
            "delta_percentage": population.deltaPercentage.jsonSafe,
            "percentile": population.percentile.jsonSafe,
            "summary": population.summaryString.jsonSafe,
            "reference_average_value": population.referenceAverageValue.jsonSafe,
            "latest_version_value": population.latestVersionValue.jsonSafe,
            "device": population.device.jsonSafe
        ]
    }

    private func formatProductData(_ productData: ASCProductData) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["platform"] = productData.platform.jsonSafe
        dict["metric_categories"] = (productData.metricCategories ?? []).map { formatMetricCategory($0) }
        return dict
    }

    private func formatMetricCategory(_ category: ASCMetricCategory) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["identifier"] = category.identifier.jsonSafe
        dict["metrics"] = (category.metrics ?? []).map { formatMetric($0) }
        return dict
    }

    private func formatMetric(_ metric: ASCMetric) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["identifier"] = metric.identifier.jsonSafe
        dict["goal_keys"] = (metric.goalKeys ?? []).map { goalKey in
            [
                "goal_key": goalKey.goalKey.jsonSafe,
                "lower_bound": goalKey.lowerBound.jsonSafe,
                "upper_bound": goalKey.upperBound.jsonSafe
            ]
        }
        if let unit = metric.unit {
            dict["unit"] = [
                "identifier": unit.identifier.jsonSafe,
                "display_name": unit.displayName.jsonSafe
            ]
        }
        dict["datasets"] = (metric.datasets ?? []).map { formatDataset($0) }
        return dict
    }

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
        if let goal = dataset.recommendedMetricGoal {
            dict["recommended_metric_goal"] = [
                "value": goal.value.jsonSafe,
                "detail": goal.detail.jsonSafe
            ]
        }
        return dict
    }

    private func formatPoint(_ point: ASCMetricPoint) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["version"] = point.version.jsonSafe
        dict["value"] = point.value.jsonSafe
        dict["error_margin"] = point.errorMargin.jsonSafe
        dict["goal"] = point.goal.jsonSafe
        if let breakdown = point.percentageBreakdown {
            dict["percentage_breakdown"] = [
                "value": breakdown.value.jsonSafe,
                "sub_system_label": breakdown.subSystemLabel.jsonSafe
            ]
        }
        return dict
    }

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
                    "direction": insight.direction.jsonSafe,
                    "reference_versions": (insight.referenceVersions ?? []).map {
                        [
                            "version": $0.version.jsonSafe,
                            "value": $0.value.jsonSafe
                        ]
                    }
                ]
            }
        }
        return dict
    }

    private func formatDiagnosticLogProductData(_ productData: ASCDiagnosticLogProductData) -> [String: Any] {
        [
            "signature_id": productData.signatureId.jsonSafe,
            "diagnostic_insights": (productData.diagnosticInsights ?? []).map { formatDiagnosticLogInsight($0) },
            "logs": (productData.diagnosticLogs ?? []).map { formatDiagnosticLog($0) }
        ]
    }

    private func formatDiagnosticLogInsight(_ insight: ASCDiagnosticLogInsight) -> [String: Any] {
        [
            "insights_url": insight.insightsURL.jsonSafe,
            "insights_category": insight.insightsCategory.jsonSafe,
            "insights_string": insight.insightsString.jsonSafe
        ]
    }

    private func formatDiagnosticLog(_ log: ASCDiagnosticLog) -> [String: Any] {
        var dict: [String: Any] = [
            "call_stack_trees": (log.callStackTree ?? []).map { formatCallStackTree($0) }
        ]
        if let metadata = log.diagnosticMetaData {
            dict["diagnostic_metadata"] = formatDiagnosticMetaData(metadata)
        }
        return dict
    }

    private func formatDiagnosticMetaData(_ metadata: ASCDiagnosticMetaData) -> [String: Any] {
        [
            "bundle_id": metadata.bundleId.jsonSafe,
            "event": metadata.event.jsonSafe,
            "os_version": metadata.osVersion.jsonSafe,
            "app_version": metadata.appVersion.jsonSafe,
            "writes_caused": metadata.writesCaused.jsonSafe,
            "device_type": metadata.deviceType.jsonSafe,
            "platform_architecture": metadata.platformArchitecture.jsonSafe,
            "event_detail": metadata.eventDetail.jsonSafe,
            "build_version": metadata.buildVersion.jsonSafe
        ]
    }

    private func formatCallStackTree(_ tree: ASCCallStackTree) -> [String: Any] {
        [
            "call_stack_per_thread": tree.callStackPerThread.jsonSafe,
            "call_stacks": (tree.callStacks ?? []).map { formatCallStack($0) }
        ]
    }

    private func formatCallStack(_ stack: ASCCallStack) -> [String: Any] {
        ["root_frames": (stack.callStackRootFrames ?? []).map { formatCallStackFrame($0) }]
    }

    private func formatCallStackFrame(_ frame: ASCCallStackFrame) -> [String: Any] {
        [
            "sample_count": frame.sampleCount.jsonSafe,
            "is_blame_frame": frame.isBlameFrame.jsonSafe,
            "symbol_name": frame.symbolName.jsonSafe,
            "insights_category": frame.insightsCategory.jsonSafe,
            "offset_into_symbol": frame.offsetIntoSymbol.jsonSafe,
            "binary_name": frame.binaryName.jsonSafe,
            "file_name": frame.fileName.jsonSafe,
            "binary_uuid": frame.binaryUUID.jsonSafe,
            "line_number": frame.lineNumber.jsonSafe,
            "address": frame.address.jsonSafe,
            "offset_into_binary_text_segment": frame.offsetIntoBinaryTextSegment.jsonSafe,
            "raw_frame": frame.rawFrame.jsonSafe,
            "sub_frames": (frame.subFrames ?? []).map { formatCallStackFrame($0) }
        ]
    }
}

private struct MetricsFilterSelection: Sendable {
    let queryValue: String
    let echo: MetricsFilterEcho
}

private enum MetricsFilterEcho: Sendable {
    case scalar(String)
    case array([String])

    var asAny: Any {
        switch self {
        case .scalar(let value):
            return value
        case .array(let values):
            return values
        }
    }
}
