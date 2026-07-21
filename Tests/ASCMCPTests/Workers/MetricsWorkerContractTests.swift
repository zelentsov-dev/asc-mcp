import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Metrics Worker Contract Tests")
struct MetricsWorkerContractTests {
    @Test("tool schemas expose Apple 4.4.1 metric, diagnostic, device, and limit inputs")
    func toolSchemasExposeAppleInputs() async throws {
        let worker = try await makeMetricsWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        for (toolName, idField) in [
            ("metrics_app_perf", "app_id"),
            ("metrics_build_perf", "build_id")
        ] {
            let tool = try #require(tools.first { $0.name == toolName })
            let metricType = try metricsProperty("metric_type", in: tool)
            let metricVariants = try metricsArray(metricType["oneOf"])
            #expect(metricVariants.count == 2)
            let metricScalar = try metricsObject(try #require(metricVariants.first))
            let scalarMetricTypes = try metricsArray(metricScalar["enum"])
            #expect(scalarMetricTypes.contains(.string("STORAGE")))
            let metricArray = try metricsObject(try #require(metricVariants.last))
            #expect(metricArray["type"] == .string("array"))
            #expect(metricArray["minItems"] == .int(1))
            #expect(metricArray["uniqueItems"] == .bool(true))
            let metricItems = try metricsObject(metricArray["items"])
            #expect(try metricsArray(metricItems["enum"]).contains(.string("STORAGE")))

            let deviceType = try metricsProperty("device_type", in: tool)
            let deviceVariants = try metricsArray(deviceType["oneOf"])
            #expect(deviceVariants.count == 2)
            let deviceArray = try metricsObject(try #require(deviceVariants.last))
            #expect(deviceArray["minItems"] == .int(1))
            #expect(deviceArray["uniqueItems"] == .bool(true))
            #expect(deviceType["description"]?.stringValue?.contains("all_iphones") == true)
            #expect(deviceType["description"]?.stringValue?.contains("all_ipads") == true)
            #expect(try metricsRequired(tool) == [idField])
        }

        let diagnostics = try #require(tools.first { $0.name == "metrics_build_diagnostics" })
        let diagnosticType = try metricsProperty("diagnostic_type", in: diagnostics)
        let diagnosticVariants = try metricsArray(diagnosticType["oneOf"])
        #expect(diagnosticVariants.count == 2)
        let diagnosticScalar = try metricsObject(try #require(diagnosticVariants.first))
        let diagnosticTypes = try metricsArray(diagnosticScalar["enum"])
        #expect(diagnosticTypes.contains(.string("LAUNCHES")))
        let diagnosticArray = try metricsObject(try #require(diagnosticVariants.last))
        #expect(diagnosticArray["minItems"] == .int(1))
        #expect(diagnosticArray["uniqueItems"] == .bool(true))
        let diagnosticItems = try metricsObject(diagnosticArray["items"])
        #expect(try metricsArray(diagnosticItems["enum"]).contains(.string("LAUNCHES")))
        #expect(try metricsRequired(diagnostics) == ["build_id"])

        let logs = try #require(tools.first { $0.name == "metrics_get_diagnostic_logs" })
        let limit = try metricsProperty("limit", in: logs)
        #expect(limit["type"] == .string("integer"))
        #expect(limit["minimum"] == .int(1))
        #expect(limit["maximum"] == .int(200))
    }

    @Test("app metrics forwards STORAGE and deviceType and projects the complete response")
    func appMetricsProjectsOfficialResponse() async throws {
        let body = String(decoding: try loadFixture("metrics_xcode_metrics"), as: UTF8.self)
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await makeMetricsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_app_perf",
            arguments: [
                "app_id": .string("app-1"),
                "metric_type": .string("STORAGE"),
                "device_type": .string("iPhone15,2")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/apps/app-1/perfPowerMetrics")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.apple.xcode-metrics+json")
        let query = metricsQuery(request)
        #expect(query["filter[metricType]"] == "STORAGE")
        #expect(query["filter[deviceType]"] == "iPhone15,2")

        let payload = try metricsObject(result.structuredContent)
        #expect(payload["version"] == .string("1.0"))
        #expect(payload["metric_type"] == .string("STORAGE"))
        #expect(payload["device_type"] == .string("iPhone15,2"))
        let products = try metricsArray(payload["product_data"])
        let product = try metricsObject(try #require(products.first))
        let categories = try metricsArray(product["metric_categories"])
        let category = try metricsObject(try #require(categories.first))
        let metrics = try metricsArray(category["metrics"])
        let metric = try metricsObject(try #require(metrics.first))
        let goalKeys = try metricsArray(metric["goal_keys"])
        let goalKey = try metricsObject(try #require(goalKeys.first))
        #expect(goalKey["goal_key"] == .string("storageP90"))
        #expect(goalKey["lower_bound"] == .int(0))
        #expect(goalKey["upper_bound"] == .int(200))
        let datasets = try metricsArray(metric["datasets"])
        let dataset = try metricsObject(try #require(datasets.first))
        let points = try metricsArray(dataset["points"])
        let point = try metricsObject(try #require(points.first))
        #expect(point["goal"] == .string("Less than 200 MB"))
        #expect(point["error_margin"] == .double(2.25))
        let recommendedGoal = try metricsObject(dataset["recommended_metric_goal"])
        #expect(recommendedGoal["value"] == .double(175.0))

        let insights = try metricsObject(payload["insights"])
        let trending = try metricsArray(insights["trending_up"])
        let firstInsight = try metricsObject(try #require(trending.first))
        #expect(firstInsight["metric_category"] == .string("STORAGE"))
    }

    @Test("app and build metrics omit optional filters when none are requested")
    func metricsAllowNoFilters() async throws {
        let body = String(decoding: try loadFixture("metrics_xcode_metrics"), as: UTF8.self)
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 200, body: body)
        ])
        let worker = try await makeMetricsWorker(transport: transport)

        let appResult = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_app_perf",
            arguments: ["app_id": .string("app-1")]
        ))
        let buildResult = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_build_perf",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(appResult.isError != true)
        #expect(buildResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            let query = metricsQuery(request)
            #expect(query["filter[metricType]"] == nil)
            #expect(query["filter[deviceType]"] == nil)
        }
        for result in [appResult, buildResult] {
            let payload = try metricsObject(result.structuredContent)
            #expect(payload["metric_type"] == nil)
            #expect(payload["device_type"] == nil)
        }
    }

    @Test("app metrics forwards multi-value metric and device filters")
    func appMetricsForwardsMultipleFilters() async throws {
        let body = String(decoding: try loadFixture("metrics_xcode_metrics"), as: UTF8.self)
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await makeMetricsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_app_perf",
            arguments: [
                "app_id": .string("app-1"),
                "metric_type": .array([.string("STORAGE"), .string("LAUNCH")]),
                "device_type": .array([.string("all_iphones"), .string("all_ipads")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = metricsQuery(request)
        #expect(query["filter[metricType]"] == "STORAGE,LAUNCH")
        #expect(query["filter[deviceType]"] == "all_iphones,all_ipads")
        let payload = try metricsObject(result.structuredContent)
        #expect(try metricsArray(payload["metric_type"]) == [.string("STORAGE"), .string("LAUNCH")])
        #expect(try metricsArray(payload["device_type"]) == [.string("all_iphones"), .string("all_ipads")])
    }

    @Test("build metrics forwards multi-value metric and device filters")
    func buildMetricsForwardsMultipleFilters() async throws {
        let body = String(decoding: try loadFixture("metrics_xcode_metrics"), as: UTF8.self)
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await makeMetricsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_build_perf",
            arguments: [
                "build_id": .string("build-1"),
                "metric_type": .array([.string("STORAGE"), .string("MEMORY")]),
                "device_type": .array([.string("iPhone15,2"), .string("all_ipads")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/builds/build-1/perfPowerMetrics")
        let query = metricsQuery(request)
        #expect(query["filter[metricType]"] == "STORAGE,MEMORY")
        #expect(query["filter[deviceType]"] == "iPhone15,2,all_ipads")
        let payload = try metricsObject(result.structuredContent)
        #expect(try metricsArray(payload["metric_type"]) == [.string("STORAGE"), .string("MEMORY")])
        #expect(try metricsArray(payload["device_type"]) == [.string("iPhone15,2"), .string("all_ipads")])
    }

    @Test("build metrics and diagnostics preserve scalar filter compatibility")
    func remainingMetricToolsPreserveScalarFilters() async throws {
        let body = String(decoding: try loadFixture("metrics_xcode_metrics"), as: UTF8.self)
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: body),
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = try await makeMetricsWorker(transport: transport)

        let buildResult = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_build_perf",
            arguments: [
                "build_id": .string("build-1"),
                "metric_type": .string("STORAGE"),
                "device_type": .string("all_ipads")
            ]
        ))
        let diagnosticsResult = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_build_diagnostics",
            arguments: [
                "build_id": .string("build-1"),
                "diagnostic_type": .string("LAUNCHES")
            ]
        ))

        #expect(buildResult.isError != true)
        #expect(diagnosticsResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let buildRequest = try #require(requests.first)
        let diagnosticsRequest = try #require(requests.last)
        #expect(metricsQuery(buildRequest)["filter[metricType]"] == "STORAGE")
        #expect(metricsQuery(buildRequest)["filter[deviceType]"] == "all_ipads")
        #expect(metricsQuery(diagnosticsRequest)["filter[diagnosticType]"] == "LAUNCHES")
        let buildPayload = try metricsObject(buildResult.structuredContent)
        #expect(buildPayload["metric_type"] == .string("STORAGE"))
        #expect(buildPayload["device_type"] == .string("all_ipads"))
        let diagnosticsPayload = try metricsObject(diagnosticsResult.structuredContent)
        #expect(diagnosticsPayload["diagnostic_type"] == .string("LAUNCHES"))
    }

    @Test("malformed Xcode metrics fail instead of returning empty product data")
    func malformedMetricsAreReportedAsError() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"version":"1.0","productData":{"unexpected":true}}"#)
        ])
        let worker = try await makeMetricsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_app_perf",
            arguments: [
                "app_id": .string("app-1"),
                "metric_type": .string("STORAGE")
            ]
        ))

        #expect(result.isError == true)
        #expect(metricsText(result).contains("Failed to get app performance metrics"))
    }

    @Test("build diagnostics forwards multiple types and projects official insight fields")
    func buildDiagnosticsProjectsOfficialInsight() async throws {
        let response = #"{"data":[{"type":"diagnosticSignatures","id":"signature-1","attributes":{"diagnosticType":"LAUNCHES","signature":"Slow launch","weight":0.75,"insight":{"insightType":"TREND","direction":"UP","referenceVersions":[{"version":"4.1.0","value":1.25}]}}}]}"#
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: response)])
        let worker = try await makeMetricsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_build_diagnostics",
            arguments: [
                "build_id": .string("build-1"),
                "diagnostic_type": .array([.string("LAUNCHES"), .string("HANGS")]),
                "limit": .int(50)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = metricsQuery(request)
        #expect(query["filter[diagnosticType]"] == "LAUNCHES,HANGS")
        #expect(query["limit"] == "50")

        let payload = try metricsObject(result.structuredContent)
        #expect(try metricsArray(payload["diagnostic_type"]) == [.string("LAUNCHES"), .string("HANGS")])
        let signatures = try metricsArray(payload["diagnostic_signatures"])
        let signature = try metricsObject(try #require(signatures.first))
        let insight = try metricsObject(signature["insight"])
        #expect(insight["direction"] == .string("UP"))
        let referenceVersions = try metricsArray(insight["reference_versions"])
        let reference = try metricsObject(try #require(referenceVersions.first))
        #expect(reference["version"] == .string("4.1.0"))
    }

    @Test("build diagnostics omits diagnosticType when no filter is requested")
    func buildDiagnosticsAllowNoFilter() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = try await makeMetricsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_build_diagnostics",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(metricsQuery(request)["filter[diagnosticType]"] == nil)
        let payload = try metricsObject(result.structuredContent)
        #expect(payload["diagnostic_type"] == nil)
    }

    @Test("metrics filters reject malformed arrays before the network")
    func rejectsMalformedFilterArrays() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeMetricsWorker(transport: transport)
        let invalidCalls: [CallTool.Parameters] = [
            CallTool.Parameters(
                name: "metrics_app_perf",
                arguments: [
                    "app_id": .string("app-1"),
                    "metric_type": .array([.string("STORAGE"), .int(1)])
                ]
            ),
            CallTool.Parameters(
                name: "metrics_build_perf",
                arguments: [
                    "build_id": .string("build-1"),
                    "device_type": .array([.string("all_ipads"), .string("all_ipads")])
                ]
            ),
            CallTool.Parameters(
                name: "metrics_build_diagnostics",
                arguments: [
                    "build_id": .string("build-1"),
                    "diagnostic_type": .array([.string("CRASHES")])
                ]
            )
        ]

        for call in invalidCalls {
            let result = try await worker.handleTool(call)
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("metrics manifest records Apple array bindings and optional request echoes")
    func manifestRecordsMetricFilterCardinality() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()

        for toolName in ["metrics_app_perf", "metrics_build_perf"] {
            let mapping = try #require(manifest.mapping(for: toolName))
            let metricType = try #require(mapping.fields.first { $0.toolField == "metric_type" })
            #expect(metricType.location == "query")
            #expect(metricType.appleName == "filter[metricType]")
            let deviceType = try #require(mapping.fields.first { $0.toolField == "device_type" })
            #expect(deviceType.location == "query")
            #expect(deviceType.appleName == "filter[deviceType]")
            #expect(mapping.note?.contains("scalar") == true)
            #expect(mapping.note?.contains("explode=false CSV semantics") == true)
            #expect(mapping.note?.contains("Zero filters request the complete metric set") == true)
            let metricEcho = try #require(mapping.response.fields.first { $0.outputField == "metric_type" })
            let deviceEcho = try #require(mapping.response.fields.first { $0.outputField == "device_type" })
            #expect(metricEcho.localRole?.contains("scalar-or-array") == true)
            #expect(deviceEcho.localRole?.contains("scalar-or-array") == true)
        }

        let diagnostics = try #require(manifest.mapping(for: "metrics_build_diagnostics"))
        let diagnosticType = try #require(
            diagnostics.fields.first { $0.toolField == "diagnostic_type" }
        )
        #expect(diagnosticType.location == "query")
        #expect(diagnosticType.appleName == "filter[diagnosticType]")
        #expect(diagnostics.note?.contains("scalar") == true)
        #expect(diagnostics.note?.contains("explode=false CSV semantics") == true)
        let diagnosticEcho = try #require(
            diagnostics.response.fields.first { $0.outputField == "diagnostic_type" }
        )
        #expect(diagnosticEcho.localRole?.contains("scalar-or-array") == true)
    }

    @Test("diagnostic logs forward limit and preserve arrays, metadata, insights, and frame fields")
    func diagnosticLogsProjectOfficialResponse() async throws {
        let body = String(decoding: try loadFixture("metrics_diagnostic_logs"), as: UTF8.self)
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await makeMetricsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "metrics_get_diagnostic_logs",
            arguments: [
                "signature_id": .string("signature-1"),
                "limit": .int(500)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/diagnosticSignatures/signature-1/logs")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.apple.diagnostic-logs+json")
        #expect(metricsQuery(request)["limit"] == "200")

        let payload = try metricsObject(result.structuredContent)
        #expect(payload["version"] == .string("1.0"))
        let products = try metricsArray(payload["diagnostic_logs"])
        let product = try metricsObject(try #require(products.first))
        let diagnosticInsights = try metricsArray(product["diagnostic_insights"])
        let diagnosticInsight = try metricsObject(try #require(diagnosticInsights.first))
        #expect(diagnosticInsight["insights_category"] == .string("DISK_WRITES"))

        let logs = try metricsArray(product["logs"])
        let log = try metricsObject(try #require(logs.first))
        let metadata = try metricsObject(log["diagnostic_metadata"])
        #expect(metadata["bundle_id"] == .string("com.example.app"))
        #expect(metadata["platform_architecture"] == .string("arm64"))

        let trees = try metricsArray(log["call_stack_trees"])
        let tree = try metricsObject(try #require(trees.first))
        let stacks = try metricsArray(tree["call_stacks"])
        let stack = try metricsObject(try #require(stacks.first))
        let frames = try metricsArray(stack["root_frames"])
        let frame = try metricsObject(try #require(frames.first))
        #expect(frame["sample_count"] == .int(7))
        #expect(frame["is_blame_frame"] == .bool(true))
        #expect(frame["line_number"] == .string("87"))
        #expect(frame["address"] == .string("0x0000000100001234"))
        #expect(frame["offset_into_binary_text_segment"] == .string("4660"))
    }

    @Test("diagnostic limits reject invalid present values before network access")
    func diagnosticLimitsRejectInvalidValues() async throws {
        for (tool, idField) in [
            ("metrics_build_diagnostics", "build_id"),
            ("metrics_get_diagnostic_logs", "signature_id")
        ] {
            for invalid in [Value.int(0), .int(201), .string("25")] {
                let transport = TestHTTPTransport(responses: [])
                let worker = try await makeMetricsWorker(transport: transport)
                let result = try await worker.handleTool(CallTool.Parameters(
                    name: tool,
                    arguments: [idField: .string("resource-1"), "limit": invalid]
                ))

                #expect(result.isError == true)
                #expect(metricsText(result).contains("limit must be an integer from 1 through 200"))
                #expect(await transport.requestCount() == 0)
            }
        }
    }
}

private func makeMetricsWorker(transport: TestHTTPTransport) async throws -> MetricsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return MetricsWorker(httpClient: client)
}

private func metricsQuery(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func metricsProperty(_ name: String, in tool: Tool) throws -> [String: Value] {
    guard case .object(let root) = tool.inputSchema,
          case .object(let properties)? = root["properties"],
          case .object(let property)? = properties[name] else {
        throw MetricsWorkerContractFailure.expectedProperty(name)
    }
    return property
}

private func metricsRequired(_ tool: Tool) throws -> [String] {
    guard case .object(let root) = tool.inputSchema,
          case .array(let required)? = root["required"] else {
        throw MetricsWorkerContractFailure.expectedArray
    }
    return required.compactMap(\.stringValue)
}

private func metricsObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw MetricsWorkerContractFailure.expectedObject
    }
    return object
}

private func metricsArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw MetricsWorkerContractFailure.expectedArray
    }
    return array
}

private func metricsText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private enum MetricsWorkerContractFailure: Error {
    case expectedArray
    case expectedObject
    case expectedProperty(String)
}
