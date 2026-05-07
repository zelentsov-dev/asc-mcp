import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Tool Metadata Policy Tests")
struct ToolMetadataPolicyTests {
    @Test("all registered tools receive annotations and max result metadata")
    func allToolsReceiveAnnotationsAndMeta() async throws {
        let tools = try await TestFactory.collectAllWorkerTools().map(ToolMetadataPolicy.apply)

        #expect(tools.count == 339)
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
    }

    @Test("max result metadata follows policy")
    func maxResultSizeMetadataFollowsPolicy() {
        let analytics = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "analytics_sales_report"))
        #expect(analytics._meta?.fields["anthropic/maxResultSizeChars"] == Value.int(500_000))

        let crashLog = ToolMetadataPolicy.apply(to: Self.sampleTool(named: "beta_feedback_get_crash_log"))
        #expect(crashLog._meta?.fields["anthropic/maxResultSizeChars"] == Value.int(500_000))

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
        #expect(ToolMetadataPolicy.apply(to: Self.sampleTool(named: "builds_list")).outputSchema == nil)
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
