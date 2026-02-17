//
//  MetricsWorker+ToolDefinitions.swift
//  asc-mcp
//
//  Tool definitions for performance metrics and diagnostics operations
//

import Foundation
import MCP

extension MetricsWorker {

    /// Creates tool definition for getting app performance/power metrics
    func appPerfMetricsTool() -> Tool {
        return Tool(
            name: "metrics_app_perf",
            description: "Get performance and power metrics for an app. Returns disk, hang, battery, launch, memory, animation, and termination metrics across device types and app versions.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "metric_type": .object([
                        "type": .string("string"),
                        "description": .string("Type of performance metric to retrieve"),
                        "enum": .array([
                            .string("DISK"),
                            .string("HANG"),
                            .string("BATTERY"),
                            .string("LAUNCH"),
                            .string("MEMORY"),
                            .string("ANIMATION"),
                            .string("TERMINATION")
                        ])
                    ])
                ]),
                "required": .array([.string("app_id"), .string("metric_type")])
            ])
        )
    }

    /// Creates tool definition for getting build performance/power metrics
    func buildPerfMetricsTool() -> Tool {
        return Tool(
            name: "metrics_build_perf",
            description: "Get performance and power metrics for a specific build. Returns metrics broken down by device type and percentile.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID from App Store Connect")
                    ]),
                    "metric_type": .object([
                        "type": .string("string"),
                        "description": .string("Type of performance metric to retrieve"),
                        "enum": .array([
                            .string("DISK"),
                            .string("HANG"),
                            .string("BATTERY"),
                            .string("LAUNCH"),
                            .string("MEMORY"),
                            .string("ANIMATION"),
                            .string("TERMINATION")
                        ])
                    ])
                ]),
                "required": .array([.string("build_id"), .string("metric_type")])
            ])
        )
    }

    /// Creates tool definition for listing diagnostic signatures for an app
    func listDiagnosticsTool() -> Tool {
        return Tool(
            name: "metrics_list_diagnostics",
            description: "List diagnostic signatures for an app. Shows top crash/hang/disk-write signatures with their weight and insights.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "diagnostic_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by diagnostic type"),
                        "enum": .array([
                            .string("DISK_WRITES"),
                            .string("HANGS")
                        ])
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of results to return (1-200, default: 25)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL for next page of results (from previous response)")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    /// Creates tool definition for listing diagnostic signatures for a build
    func buildDiagnosticsTool() -> Tool {
        return Tool(
            name: "metrics_build_diagnostics",
            description: "List diagnostic signatures for a specific build. Shows crash/hang/disk-write signatures with their weight and insights.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID from App Store Connect")
                    ]),
                    "diagnostic_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by diagnostic type"),
                        "enum": .array([
                            .string("DISK_WRITES"),
                            .string("HANGS")
                        ])
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of results to return (1-200, default: 25)")
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
            description: "Get diagnostic logs for a specific diagnostic signature. Returns call stack trees with frame details for debugging.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "signature_id": .object([
                        "type": .string("string"),
                        "description": .string("Diagnostic signature ID")
                    ])
                ]),
                "required": .array([.string("signature_id")])
            ])
        )
    }
}
