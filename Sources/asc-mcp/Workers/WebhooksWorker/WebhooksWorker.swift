import Foundation
import MCP

/// Manages App Store Connect webhook notifications and delivery diagnostics.
public final class WebhooksWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available webhook tools.
    /// - Returns: Tool definitions for webhook configuration, delivery inspection, redelivery, and ping testing.
    public func getTools() async -> [Tool] {
        [
            listWebhooksTool(),
            getWebhookTool(),
            createWebhookTool(),
            updateWebhookTool(),
            deleteWebhookTool(),
            listDeliveriesTool(),
            redeliverTool(),
            pingTool()
        ]
    }

    /// Handle webhook tool calls.
    /// - Parameter params: MCP tool call parameters.
    /// - Returns: MCP tool result with JSON text and structured content when available.
    /// - Throws: `MCPError.methodNotFound` for unknown tool names.
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "webhooks_list":
            return try await listWebhooks(params)
        case "webhooks_get":
            return try await getWebhook(params)
        case "webhooks_create":
            return try await createWebhook(params)
        case "webhooks_update":
            return try await updateWebhook(params)
        case "webhooks_delete":
            return try await deleteWebhook(params)
        case "webhooks_list_deliveries":
            return try await listDeliveries(params)
        case "webhooks_redeliver":
            return try await redeliver(params)
        case "webhooks_ping":
            return try await ping(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
