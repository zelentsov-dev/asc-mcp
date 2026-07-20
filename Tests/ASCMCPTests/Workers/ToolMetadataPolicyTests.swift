import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Tool Metadata Policy Tests")
struct ToolMetadataPolicyTests {
    @Test("all registered tools receive annotations and max result metadata")
    func allToolsReceiveAnnotationsAndMeta() async throws {
        let tools = try await TestFactory.collectAllWorkerTools().map(ToolMetadataPolicy.apply)

        #expect(tools.count == 401)
        for tool in tools {
            #expect(tool.annotations.isEmpty == false)
            #expect(tool.annotations.openWorldHint == true)
            #expect(tool._meta?.fields["anthropic/maxResultSizeChars"] != nil)
        }
    }

    @Test("classifies known read-only and destructive tools")
    func classifiesKnownTools() {
        let appsList = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "apps_list"))
        #expect(appsList.annotations.readOnlyHint == true)
        #expect(appsList.annotations.destructiveHint == false)
        #expect(appsList.annotations.idempotentHint == true)

        let deleteLocalization = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "apps_delete_localization"))
        #expect(deleteLocalization.annotations.readOnlyHint == false)
        #expect(deleteLocalization.annotations.destructiveHint == true)
        #expect(deleteLocalization.annotations.idempotentHint == false)

        let release = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "app_versions_release"))
        #expect(release.annotations.readOnlyHint == false)
        #expect(release.annotations.destructiveHint == true)

        let webhookList = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_list"))
        #expect(webhookList.annotations.readOnlyHint == true)
        #expect(webhookList.annotations.idempotentHint == true)

        let webhookPing = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_ping"))
        #expect(webhookPing.annotations.readOnlyHint == false)
        #expect(webhookPing.annotations.idempotentHint == false)

        let webhookVerify = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_verify_signature"))
        #expect(webhookVerify.annotations.readOnlyHint == true)
        #expect(webhookVerify.annotations.idempotentHint == true)

        let webhookParse = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_parse_payload"))
        #expect(webhookParse.annotations.readOnlyHint == true)
        #expect(webhookParse.annotations.idempotentHint == true)

        let webhookTriage = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_triage_event"))
        #expect(webhookTriage.annotations.readOnlyHint == true)
        #expect(webhookTriage.annotations.idempotentHint == true)

        let exportInspect = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "export_compliance_inspect_document"))
        #expect(exportInspect.annotations.readOnlyHint == true)
        #expect(exportInspect.annotations.destructiveHint == false)
        #expect(exportInspect.annotations.idempotentHint == true)

        let accessibilityList = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "accessibility_list"))
        #expect(accessibilityList.annotations.readOnlyHint == true)
        #expect(accessibilityList.annotations.idempotentHint == true)

        let accessibilityDelete = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "accessibility_delete"))
        #expect(accessibilityDelete.annotations.readOnlyHint == false)
        #expect(accessibilityDelete.annotations.destructiveHint == true)

        let betaFeedbackList = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "beta_feedback_list_crashes"))
        #expect(betaFeedbackList.annotations.readOnlyHint == true)
        #expect(betaFeedbackList.annotations.idempotentHint == true)

        let betaFeedbackDelete = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "beta_feedback_delete_crash"))
        #expect(betaFeedbackDelete.annotations.readOnlyHint == false)
        #expect(betaFeedbackDelete.annotations.destructiveHint == true)

        let xcodeCloudList = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "xcode_cloud_products_list"))
        #expect(xcodeCloudList.annotations.readOnlyHint == true)
        #expect(xcodeCloudList.annotations.idempotentHint == true)

        let xcodeCloudStart = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "xcode_cloud_build_runs_start"))
        #expect(xcodeCloudStart.annotations.readOnlyHint == false)
        #expect(xcodeCloudStart.annotations.destructiveHint == false)
        #expect(xcodeCloudStart.annotations.idempotentHint == false)

        let reviewSummarizations = ToolMetadataPolicy.apply(
            to: Self.sampleTool(named: "reviews_summarizations")
        )
        #expect(reviewSummarizations.annotations.readOnlyHint == true)
        #expect(reviewSummarizations.annotations.destructiveHint == false)
        #expect(reviewSummarizations.annotations.idempotentHint == true)
    }

    @Test("max result metadata follows policy")
    func maxResultSizeMetadataFollowsPolicy() {
        let analytics = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "analytics_sales_report"))
        #expect(analytics._meta?.fields["anthropic/maxResultSizeChars"] == Value.int(500_000))

        let crashLog = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "beta_feedback_get_crash_log"))
        #expect(crashLog._meta?.fields["anthropic/maxResultSizeChars"] == Value.int(500_000))

        let offerCodes = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "subscriptions_get_one_time_code_values"))
        #expect(offerCodes._meta?.fields["anthropic/maxResultSizeChars"] == Value.int(500_000))

        let list = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "apps_list"))
        #expect(list._meta?.fields["anthropic/maxResultSizeChars"] == Value.int(200_000))

        let standard = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "apps_get_details"))
        #expect(standard._meta?.fields["anthropic/maxResultSizeChars"] == Value.int(100_000))
    }

    @Test("adds output schema only to stable tool families")
    func outputSchemaPolicy() {
        #expect(ToolMetadataPolicy.apply(to: Self.sampleTool(named: "auth_token_status")).outputSchema != nil)
        #expect(ToolMetadataPolicy.apply(to: Self.sampleTool(named: "company_list")).outputSchema != nil)
        #expect(ToolMetadataPolicy.apply(to: Self.sampleTool(named: "apps_list")).outputSchema != nil)
        #expect(ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_verify_signature")).outputSchema != nil)
        #expect(ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_parse_payload")).outputSchema != nil)
        #expect(ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_triage_event")).outputSchema != nil)
        #expect(ToolMetadataPolicy.apply(to: Self.sampleTool(named: "builds_list")).outputSchema == nil)
    }

    @Test("webhook signature output schema preserves nullable result fields")
    func webhookSignatureOutputSchemaPreservesNullability() throws {
        let tool = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "webhooks_verify_signature"))
        guard case .object(let schema)? = tool.outputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let providedSignature)? = properties["providedSignature"],
              case .object(let reason)? = properties["reason"] else {
            Issue.record("Expected webhook signature output schema")
            return
        }

        #expect(providedSignature["type"] == .array([.string("string"), .string("null")]))
        #expect(reason["type"] == .array([.string("string"), .string("null")]))
    }

    @Test("typed output schemas admit canonical errors without top-level combinators")
    func typedOutputSchemasAdmitCanonicalErrors() throws {
        let toolNames = [
            "apps_list",
            "apps_search",
            "apps_get_details",
            "webhooks_verify_signature"
        ]

        for toolName in toolNames {
            let tool = ToolMetadataPolicy.apply(to: Self.sampleTool(named: toolName))
            guard case .object(let schema)? = tool.outputSchema,
                  case .object(let properties)? = schema["properties"],
                  case .object(let error)? = properties["error"],
                  case .object(let details)? = properties["details"] else {
                Issue.record("Expected typed output schema for \(toolName)")
                continue
            }

            #expect(schema["oneOf"] == nil)
            #expect(schema["anyOf"] == nil)
            #expect(schema["allOf"] == nil)
            #expect(schema["required"] == .array([.string("success")]))
            #expect(error["type"] == .string("string"))
            #expect(details.isEmpty)
        }
    }

    @Test("normalizes no-parameter schemas")
    func normalizesNoParameterSchemas() {
        let tool = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "auth_generate_token"))

        guard case .object(let schema) = tool.inputSchema else {
            Issue.record("Expected object schema")
            return
        }
        #expect(schema["additionalProperties"] == Value.bool(false))
    }

    @Test("normalizes nullable type markers without removing enum null")
    func normalizesNullableTypeMarkers() {
        let rawTool = Tool(
            name: "subscriptions_update_winback_offer",
            description: "Sample",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "eligibility_time_since_last_months_min": .object([
                        "type": .array([.string("integer"), .null]),
                        "enum": .array([.int(0), .null])
                    ])
                ])
            ])
        )

        let tool = ToolMetadataPolicy.apply(to: rawTool)
        guard case .object(let schema) = tool.inputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let property)? = properties["eligibility_time_since_last_months_min"] else {
            Issue.record("Expected nested nullable property schema")
            return
        }

        #expect(property["type"] == .array([.string("integer"), .string("null")]))
        #expect(property["enum"] == .array([.int(0), .null]))
    }

    private static func sampleTool(named name: String) -> Tool {
        Tool(
            name: name,
            description: "Sample",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
    }

}
