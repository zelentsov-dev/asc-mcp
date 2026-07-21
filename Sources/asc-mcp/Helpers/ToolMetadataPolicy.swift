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
        if largeResultTools.contains(toolName) {
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
        if explicitMutationTools.contains(toolName) {
            return false
        }
        if explicitReadOnlyTools.contains(toolName) {
            return true
        }
        if toolName.hasPrefix("auth_") {
            return true
        }
        if toolName == "analytics_sales_report" ||
            toolName == "analytics_financial_report" ||
            toolName == "analytics_app_summary" ||
            toolName == "reviews_summarizations" ||
            toolName.hasPrefix("metrics_") {
            return true
        }
        return readOnlyMarkers.contains { toolName.contains($0) }
    }

    static func isDestructiveOrHighRisk(_ toolName: String) -> Bool {
        explicitMutationTools.contains(toolName) || destructiveMarkers.contains { toolName.contains($0) }
    }

    private static let analyticsHeavyTools: Set<String> = [
        "analytics_sales_report",
        "analytics_financial_report",
        "analytics_get_report",
        "analytics_app_summary"
    ]

    private static let largeResultTools: Set<String> = [
        "subscriptions_get_one_time_code_values",
        "build_uploads_upload",
        "build_uploads_upload_file",
        "metrics_app_beta_tester_usage",
        "metrics_group_beta_tester_usage",
        "metrics_group_public_link_usage",
        "metrics_tester_usage",
        "metrics_build_beta_usage"
    ]

    private static let explicitMutationTools: Set<String> = [
        "build_uploads_reserve_file",
        "build_uploads_commit_file",
        "custom_pages_add_search_keywords",
        "custom_pages_remove_search_keywords"
    ]

    private static let explicitReadOnlyTools: Set<String> = [
        "promoted_delete_image",
        "promoted_upload_image"
    ]

    private static let explicitClosedWorldTools: Set<String> = [
        "auth_generate_token",
        "auth_refresh_token",
        "auth_token_status",
        "auth_validate_token",
        "company_current",
        "company_list",
        "company_switch",
        "promoted_delete_image",
        "promoted_get_image",
        "promoted_get_image_for_purchase",
        "promoted_upload_image",
        "webhooks_parse_payload",
        "webhooks_triage_event",
        "webhooks_verify_signature"
    ]

    private static let readOnlyMarkers = [
        "_list",
        "_get",
        "_search",
        "_find",
        "_stats",
        "_summary",
        "_inventory",
        "_prepare",
        "_inspect",
        "_status",
        "_check",
        "_current",
        "_verify",
        "_parse",
        "_triage"
    ]

    private static let destructiveMarkers = [
        "_create",
        "_update",
        "_set",
        "_upload",
        "_generate",
        "_deactivate",
        "_disable",
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
        let openWorld = explicitClosedWorldTools.contains(toolName)
            ? false
            : (existing.openWorldHint ?? true)

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
        guard case .object(var schema) = tool.inputSchema else {
            return tool.inputSchema
        }

        // The Anthropic API rejects top-level oneOf/anyOf/allOf in a tool
        // input_schema, even when `type: object` is present. Strip them here as a
        // safety net so a single malformed tool definition can never again break
        // every sub-agent request; the real "either/or" constraints are enforced
        // at runtime inside the tool handlers.
        schema["anyOf"] = nil
        schema["oneOf"] = nil
        schema["allOf"] = nil

        if case .object(let properties)? = schema["properties"], properties.isEmpty,
           schema["additionalProperties"] == nil {
            schema["additionalProperties"] = .bool(false)
        }
        return normalizeNullableTypeMarkers(in: .object(schema))
    }

    private static func normalizeNullableTypeMarkers(in value: Value) -> Value {
        switch value {
        case .object(let object):
            var normalized: [String: Value] = [:]
            normalized.reserveCapacity(object.count)
            for (key, nestedValue) in object {
                if key == "type", case .array(let types) = nestedValue {
                    normalized[key] = .array(types.map { type in
                        type == .null ? .string("null") : type
                    })
                } else {
                    normalized[key] = normalizeNullableTypeMarkers(in: nestedValue)
                }
            }
            return .object(normalized)
        case .array(let values):
            return .array(values.map(normalizeNullableTypeMarkers))
        default:
            return value
        }
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
        case "webhooks_verify_signature":
            return webhookSignatureSchema
        case "webhooks_parse_payload":
            return genericSuccessSchema(description: "Parsed App Store Connect webhook payload")
        case "webhooks_triage_event":
            return genericSuccessSchema(description: "Webhook event triage result")
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
            "error": .object(["type": .string("string")]),
            "details": .object([:]),
            "apps": .object(["type": .string("array"), "items": appSummarySchema]),
            "count": .object(["type": .string("integer")]),
            "totalCount": .object([
                "type": .array([.string("integer"), .string("null")])
            ]),
            "hasNextPage": .object(["type": .string("boolean")]),
            "next_url": .object(["type": .string("string")])
        ]),
        "required": .array([.string("success")])
    ])

    private static let appsSearchSchema: Value = .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
        "properties": .object([
            "success": .object(["type": .string("boolean")]),
            "error": .object(["type": .string("string")]),
            "details": .object([:]),
            "query": .object(["type": .string("string")]),
            "count": .object(["type": .string("integer")]),
            "pagesFetched": .object(["type": .string("integer")]),
            "apps": .object(["type": .string("array"), "items": appSummarySchema]),
            "searchedIn": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
        ]),
        "required": .array([.string("success")])
    ])

    private static let appsDetailsSchema: Value = .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
        "properties": .object([
            "success": .object(["type": .string("boolean")]),
            "error": .object(["type": .string("string")]),
            "details": .object([:]),
            "app": appSummarySchema
        ]),
        "required": .array([.string("success")])
    ])

    private static let webhookSignatureSchema: Value = .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
        "properties": .object([
            "success": .object(["type": .string("boolean")]),
            "error": .object(["type": .string("string")]),
            "details": .object([:]),
            "valid": .object(["type": .string("boolean")]),
            "algorithm": .object(["type": .string("string")]),
            "providedSignature": .object(["type": .array([.string("string"), .string("null")])]),
            "computedSignature": .object(["type": .string("string")]),
            "reason": .object(["type": .array([.string("string"), .string("null")])]),
            "rawPayloadRequired": .object(["type": .string("boolean")])
        ]),
        "required": .array([.string("success")])
    ])
}
