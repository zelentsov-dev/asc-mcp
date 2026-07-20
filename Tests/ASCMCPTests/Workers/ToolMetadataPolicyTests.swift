import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Tool Metadata Policy Tests")
struct ToolMetadataPolicyTests {
    @Test("all registered tools receive annotations and max result metadata")
    func allToolsReceiveAnnotationsAndMeta() async throws {
        let tools = try await TestFactory.collectAllWorkerTools().map(ToolMetadataPolicy.apply)

        #expect(tools.count == 461)
        for tool in tools {
            #expect(tool.annotations.isEmpty == false)
            #expect(tool.annotations.openWorldHint == true)
            #expect(tool._meta?.fields["anthropic/maxResultSizeChars"] != nil)
        }

        let promotedDeleteImage = try #require(
            tools.first { $0.name == "promoted_delete_image" }
        )
        #expect(promotedDeleteImage.annotations.readOnlyHint == true)
        #expect(promotedDeleteImage.annotations.destructiveHint == false)
        #expect(promotedDeleteImage.annotations.idempotentHint == true)
    }

    @Test("IAP version image collection remains read-only metadata")
    func iapVersionImageCollectionRemainsReadOnly() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client, uploadService: UploadService())
        let tools = await worker.getTools()
        let rawTool = try #require(tools.first { $0.name == "iap_list_version_images" })
        let tool = ToolMetadataPolicy.apply(to: rawTool)

        #expect(tool.annotations.readOnlyHint == true)
        #expect(tool.annotations.destructiveHint == false)
        #expect(tool.annotations.idempotentHint == true)
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

        let reviewSubmissionList = ToolMetadataPolicy.apply(
            to: Self.sampleTool(named: "review_submissions_list")
        )
        #expect(reviewSubmissionList.annotations.readOnlyHint == true)
        #expect(reviewSubmissionList.annotations.destructiveHint == false)

        let reviewSubmissionSubmit = ToolMetadataPolicy.apply(
            to: Self.sampleTool(named: "review_submissions_submit")
        )
        #expect(reviewSubmissionSubmit.annotations.readOnlyHint == false)
        #expect(reviewSubmissionSubmit.annotations.destructiveHint == true)

        let newDestructiveTools = [
            "iap_delete_version_image",
            "iap_delete_version_localization",
            "review_submissions_cancel",
            "review_submissions_remove_item",
            "review_submissions_submit",
            "subscriptions_delete_group_version_localization",
            "subscriptions_delete_version_image",
            "subscriptions_delete_version_localization"
        ]
        for toolName in newDestructiveTools {
            let tool = ToolMetadataPolicy.apply(to: Self.sampleTool(named: toolName))
            #expect(tool.annotations.readOnlyHint == false, "Expected destructive metadata for \(toolName)")
            #expect(tool.annotations.destructiveHint == true, "Expected destructive metadata for \(toolName)")
            #expect(tool.annotations.idempotentHint == false, "Expected non-idempotent metadata for \(toolName)")
        }

        let newReadOnlyTools = [
            "iap_get_version",
            "iap_get_version_image",
            "iap_get_version_image_resource",
            "iap_get_version_localization",
            "iap_list_version_images",
            "iap_list_version_localizations",
            "iap_list_versions",
            "review_submissions_get",
            "review_submissions_list",
            "review_submissions_list_items",
            "subscriptions_get_group_version",
            "subscriptions_get_group_version_localization",
            "subscriptions_get_plan_availability",
            "subscriptions_get_version",
            "subscriptions_get_version_image",
            "subscriptions_get_version_localization",
            "subscriptions_list_group_version_localizations",
            "subscriptions_list_group_versions",
            "subscriptions_list_plan_availabilities",
            "subscriptions_list_plan_availability_territories",
            "subscriptions_list_price_point_adjusted_equalizations",
            "subscriptions_list_version_images",
            "subscriptions_list_version_localizations",
            "subscriptions_list_versions"
        ]
        for toolName in newReadOnlyTools {
            let tool = ToolMetadataPolicy.apply(to: Self.sampleTool(named: toolName))
            #expect(tool.annotations.readOnlyHint == true, "Expected read-only metadata for \(toolName)")
            #expect(tool.annotations.destructiveHint == false, "Expected non-destructive metadata for \(toolName)")
            #expect(tool.annotations.idempotentHint == true, "Expected idempotent metadata for \(toolName)")
        }
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
