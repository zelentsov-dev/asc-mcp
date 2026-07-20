//
//  MetricsWorker+ToolDefinitions.swift
//  asc-mcp
//
//  Tool definitions for performance metrics and diagnostics operations
//

import Foundation
import MCP

extension MetricsWorker {
    static let supportedMetricTypes = [
        "DISK",
        "HANG",
        "BATTERY",
        "LAUNCH",
        "MEMORY",
        "ANIMATION",
        "TERMINATION",
        "STORAGE"
    ]
    static let supportedDiagnosticTypes = ["DISK_WRITES", "HANGS", "LAUNCHES"]

    /// Creates tool definition for getting app performance/power metrics
    func appPerfMetricsTool() -> Tool {
        return Tool(
            name: "metrics_app_perf",
            description: "Get performance and power metrics for an app. Returns disk, hang, battery, launch, memory, animation, termination, and storage metrics across device types and app versions.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "metric_type": enumListSchema(
                        "Optional performance metric type filter",
                        values: MetricsWorker.supportedMetricTypes
                    ),
                    "device_type": stringListSchema(
                        "Optional device type filter, such as iPhone15,2; Apple also supports all_iphones and all_ipads"
                    )
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    /// Creates tool definition for getting build performance/power metrics
    func buildPerfMetricsTool() -> Tool {
        return Tool(
            name: "metrics_build_perf",
            description: "Get performance and power metrics for a specific build. Returns metrics broken down by device type and percentile. Available only for App Store builds. Pre-release/TestFlight builds return 404.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID from App Store Connect")
                    ]),
                    "metric_type": enumListSchema(
                        "Optional performance metric type filter",
                        values: MetricsWorker.supportedMetricTypes
                    ),
                    "device_type": stringListSchema(
                        "Optional device type filter, such as iPhone15,2; Apple also supports all_iphones and all_ipads"
                    )
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }

    /// Creates tool definition for listing diagnostic signatures for a build
    func buildDiagnosticsTool() -> Tool {
        return Tool(
            name: "metrics_build_diagnostics",
            description: "List diagnostic signatures for a specific build. Shows launch, hang, and disk-write signatures with their weight and insights. Available only for App Store builds. Pre-release/TestFlight builds return 404.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID from App Store Connect")
                    ]),
                    "diagnostic_type": enumListSchema(
                        "Optional diagnostic type filter",
                        values: MetricsWorker.supportedDiagnosticTypes
                    ),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of results to return (1-200, default: 25)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL for next page of results (from previous response)")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }

    /// Creates tool definition for getting diagnostic logs for a signature
    func getDiagnosticLogsTool() -> Tool {
        return Tool(
            name: "metrics_get_diagnostic_logs",
            description: "Get diagnostic logs for a specific diagnostic signature. Returns diagnostic insights, metadata, and call stack trees with complete frame details.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "signature_id": .object([
                        "type": .string("string"),
                        "description": .string("Diagnostic signature ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of diagnostic logs to return (1-200)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ])
                ]),
                "required": .array([.string("signature_id")])
            ])
        )
    }

    private func stringListSchema(_ description: String) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("string")]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func enumListSchema(_ description: String, values: [String]) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": .array(values.map(Value.string))
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(values.map(Value.string))
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }
}
