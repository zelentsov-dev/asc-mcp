import Foundation
import MCP

enum ToolMetadataPolicy {
    static func apply(to tool: Tool) -> Tool {
        Tool(
            name: tool.name,
            title: tool.title,
            description: tool.description,
            inputSchema: normalizedInputSchema(for: tool),
            annotations: annotations(for: tool.name, existing: tool.annotations),
            outputSchema: outputSchema(for: tool.name) ?? tool.outputSchema,
            icons: tool.icons,
            _meta: metadata(for: tool)
        )
    }

    static func maxResultSizeChars(for toolName: String) -> Int {
        if analyticsHeavyTools.contains(toolName) {
            return 500_000
        }
        if toolName.contains("crash_log") {
            return 500_000
        }
        if toolName.contains("_list") || toolName.contains("_search") {
            return 200_000
        }
        return 100_000
    }

    static func isReadOnly(_ toolName: String) -> Bool {
        if toolName == "company_switch" {
            return false
        }
        if toolName.hasPrefix("auth_") {
            return true
        }
        if toolName == "analytics_sales_report" ||
            toolName == "analytics_financial_report" ||
            toolName == "analytics_app_summary" ||
            toolName.hasPrefix("metrics_") {
            return true
        }
        return readOnlyMarkers.contains { toolName.contains($0) }
    }

    static func isDestructiveOrHighRisk(_ toolName: String) -> Bool {
        destructiveMarkers.contains { toolName.contains($0) }
    }

    private static let analyticsHeavyTools: Set<String> = [
        "analytics_sales_report",
        "analytics_financial_report",
        "analytics_get_report",
        "analytics_app_summary"
    ]

    private static let readOnlyMarkers = [
        "_list",
        "_get",
        "_search",
        "_find",
        "_stats",
        "_status",
        "_check",
        "_current"
    ]

    private static let destructiveMarkers = [
        "_delete",
        "_remove",
        "_revoke",
        "_clear",
        "_cancel",
        "_release",
        "_submit"
    ]

    private static func annotations(for toolName: String, existing: Tool.Annotations) -> Tool.Annotations {
        let readOnly = existing.readOnlyHint ?? isReadOnly(toolName)
        let destructive = existing.destructiveHint ?? (readOnly ? false : isDestructiveOrHighRisk(toolName))
        let idempotent = existing.idempotentHint ?? readOnly
        let openWorld = existing.openWorldHint ?? true

        return Tool.Annotations(
            title: existing.title,
            readOnlyHint: readOnly,
            destructiveHint: destructive,
            idempotentHint: idempotent,
            openWorldHint: openWorld
        )
    }

    private static func metadata(for tool: Tool) -> Metadata {
        var fields = tool._meta?.fields ?? [:]
        fields["anthropic/maxResultSizeChars"] = .int(maxResultSizeChars(for: tool.name))
        return Metadata(additionalFields: fields)
    }

    private static func normalizedInputSchema(for tool: Tool) -> Value {
        guard case .object(var schema) = tool.inputSchema,
              case .object(let properties)? = schema["properties"],
              properties.isEmpty else {
            return tool.inputSchema
        }

        if schema["additionalProperties"] == nil {
            schema["additionalProperties"] = .bool(false)
        }
        return .object(schema)
    }

    private static func outputSchema(for toolName: String) -> Value? {
        switch toolName {
        case let name where name.hasPrefix("auth_"):
            return genericSuccessSchema(description: "Authentication tool result")
        case let name where name.hasPrefix("company_"):
            return genericSuccessSchema(description: "Company tool result")
        case "apps_list":
            return appsListSchema
        case "apps_search":
            return appsSearchSchema
        case "apps_get_details":
            return appsDetailsSchema
        case "analytics_sales_report", "analytics_financial_report", "analytics_app_summary":
            return genericSuccessSchema(description: "Analytics report result")
        default:
            return nil
        }
    }

    private static func genericSuccessSchema(description: String) -> Value {
        .object([
            "type": .string("object"),
            "description": .string(description),
            "additionalProperties": .bool(true)
        ])
    }

    private static let appSummarySchema: Value = .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
        "properties": .object([
            "id": .object(["type": .string("string")]),
            "name": .object(["type": .string("string")]),
            "bundleId": .object(["type": .string("string")]),
            "sku": .object(["type": .string("string")]),
            "primaryLocale": .object(["type": .string("string")]),
            "type": .object(["type": .string("string")])
        ])
    ])

    private static let appsListSchema: Value = .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
        "properties": .object([
            "success": .object(["type": .string("boolean")]),
            "apps": .object(["type": .string("array"), "items": appSummarySchema]),
            "count": .object(["type": .string("integer")]),
            "totalCount": .object(["type": .string("integer")]),
            "hasNextPage": .object(["type": .string("boolean")]),
            "next_url": .object(["type": .string("string")])
        ]),
        "required": .array([.string("success"), .string("apps"), .string("count")])
    ])

    private static let appsSearchSchema: Value = .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
        "properties": .object([
            "success": .object(["type": .string("boolean")]),
            "query": .object(["type": .string("string")]),
            "count": .object(["type": .string("integer")]),
            "apps": .object(["type": .string("array"), "items": appSummarySchema]),
            "searchedIn": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
        ]),
        "required": .array([.string("success"), .string("query"), .string("apps"), .string("count")])
    ])

    private static let appsDetailsSchema: Value = .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
        "properties": .object([
            "success": .object(["type": .string("boolean")]),
            "app": appSummarySchema
        ]),
        "required": .array([.string("success"), .string("app")])
    ])
}
