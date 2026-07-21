import Foundation
import MCP

extension MetricsWorker {
    func appBetaTesterUsageTool() -> Tool {
        Tool(
            name: "metrics_app_beta_tester_usage",
            description: "Get TestFlight crash, session, and feedback usage metrics for an app, optionally grouped or filtered by beta tester",
            inputSchema: betaTesterUsageSchema(parentField: "app_id", parentDescription: "App Store Connect app ID")
        )
    }

    func groupBetaTesterUsageTool() -> Tool {
        Tool(
            name: "metrics_group_beta_tester_usage",
            description: "Get TestFlight crash, session, and feedback usage metrics for a beta group, optionally grouped or filtered by beta tester",
            inputSchema: betaTesterUsageSchema(parentField: "group_id", parentDescription: "Beta group ID")
        )
    }

    func groupPublicLinkUsageTool() -> Tool {
        Tool(
            name: "metrics_group_public_link_usage",
            description: "Get TestFlight public-link views, acceptance outcomes, criteria failures, and survey ratios for a beta group",
            inputSchema: simplePagedMetricSchema(parentField: "group_id", parentDescription: "Beta group ID")
        )
    }

    func testerUsageTool() -> Tool {
        var properties = pagedMetricProperties()
        properties["tester_id"] = metricIdentifierSchema("Beta tester ID")
        properties["app_id"] = metricIdentifierSchema("Required app relationship filter")
        properties["period"] = periodSchema()
        return Tool(
            name: "metrics_tester_usage",
            description: "Get TestFlight crash, session, and feedback usage metrics for one beta tester within one app",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object(properties),
                "required": .array([.string("tester_id"), .string("app_id")])
            ])
        )
    }

    func buildBetaUsageTool() -> Tool {
        Tool(
            name: "metrics_build_beta_usage",
            description: "Get TestFlight crash, install, session, feedback, and invitation usage metrics for a build",
            inputSchema: simplePagedMetricSchema(parentField: "build_id", parentDescription: "Build ID")
        )
    }

    private func betaTesterUsageSchema(parentField: String, parentDescription: String) -> Value {
        var properties = pagedMetricProperties()
        properties[parentField] = metricIdentifierSchema(parentDescription)
        properties["period"] = periodSchema()
        properties["group_by"] = .object([
            "description": .string("Apple metric grouping dimension; betaTesters is the only supported value"),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": .array([.string("betaTesters")])
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array([.string("betaTesters")])
                    ]),
                    "minItems": .int(1),
                    "maxItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
        properties["beta_tester_id"] = metricIdentifierSchema("Optional beta tester relationship filter")
        return .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object(properties),
            "required": .array([.string(parentField)])
        ])
    }

    private func simplePagedMetricSchema(parentField: String, parentDescription: String) -> Value {
        var properties = pagedMetricProperties()
        properties[parentField] = metricIdentifierSchema(parentDescription)
        return .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object(properties),
            "required": .array([.string(parentField)])
        ])
    }

    private func pagedMetricProperties() -> [String: Value] {
        [
            "limit": .object([
                "type": .string("integer"),
                "description": .string("Maximum metric groups per page"),
                "minimum": .int(1),
                "maximum": .int(200),
                "default": .int(25)
            ]),
            "next_url": .object([
                "type": .string("string"),
                "format": .string("uri-reference"),
                "minLength": .int(1),
                "description": .string("Apple continuation URL from the previous response. Repeat the effective limit and every period, grouping, and filter control; exact origin, path, query, and a non-empty cursor are validated.")
            ])
        ]
    }

    private func metricIdentifierSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(1)
        ])
    }

    private func periodSchema() -> Value {
        .object([
            "type": .string("string"),
            "description": .string("Reporting period"),
            "enum": .array(["P7D", "P30D", "P90D", "P365D"].map(Value.string))
        ])
    }
}
