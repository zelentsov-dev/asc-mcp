import Foundation
import MCP

extension WebhooksWorker {
    func listWebhooksTool() -> Tool {
        Tool(
            name: "webhooks_list",
            description: "List webhook notification configurations for an app. Returns webhook IDs, enabled state, URL, event types, and pagination info.",
            inputSchema: baseSchema(
                properties: [
                    "app_id": stringSchema("App ID whose webhooks should be listed"),
                    "limit": integerSchema("Max results (default: 25, max: 200)"),
                    "include_app": boolSchema("Include related app resource when Apple returns it"),
                    "next_url": stringSchema("Pagination URL from a previous response")
                ],
                required: ["app_id"]
            )
        )
    }

    func getWebhookTool() -> Tool {
        Tool(
            name: "webhooks_get",
            description: "Get one webhook notification configuration by ID.",
            inputSchema: baseSchema(
                properties: [
                    "webhook_id": stringSchema("Webhook ID"),
                    "include_app": boolSchema("Include related app resource when Apple returns it")
                ],
                required: ["webhook_id"]
            )
        )
    }

    func createWebhookTool() -> Tool {
        Tool(
            name: "webhooks_create",
            description: "Create a webhook notification configuration for an app. Requires name, payload URL, secret, enabled flag, and event types.",
            inputSchema: baseSchema(
                properties: [
                    "app_id": stringSchema("App ID that owns the webhook"),
                    "name": stringSchema("Human-readable webhook name"),
                    "url": stringSchema("Absolute http/https payload URL"),
                    "secret": stringSchema("Secret used by your receiver to verify App Store Connect webhook deliveries"),
                    "event_types": eventTypesSchema("Webhook event types to subscribe to"),
                    "enabled": boolSchema("Whether the webhook should be enabled immediately (default: true)")
                ],
                required: ["app_id", "name", "url", "secret", "event_types"]
            )
        )
    }

    func updateWebhookTool() -> Tool {
        Tool(
            name: "webhooks_update",
            description: "Update webhook notification configuration fields. Omitted optional fields are left unchanged.",
            inputSchema: baseSchema(
                properties: [
                    "webhook_id": stringSchema("Webhook ID to update"),
                    "name": stringSchema("New webhook name"),
                    "url": stringSchema("New absolute http/https payload URL"),
                    "secret": stringSchema("New webhook secret"),
                    "event_types": eventTypesSchema("Replacement webhook event type list"),
                    "enabled": boolSchema("Whether the webhook should be enabled")
                ],
                required: ["webhook_id"]
            )
        )
    }

    func deleteWebhookTool() -> Tool {
        Tool(
            name: "webhooks_delete",
            description: "Delete a webhook notification configuration.",
            inputSchema: baseSchema(
                properties: [
                    "webhook_id": stringSchema("Webhook ID to delete")
                ],
                required: ["webhook_id"]
            )
        )
    }

    func listDeliveriesTool() -> Tool {
        Tool(
            name: "webhooks_list_deliveries",
            description: "List delivery attempts for a webhook, including state, error message, request URL, response status, and event relationship.",
            inputSchema: baseSchema(
                properties: [
                    "webhook_id": stringSchema("Webhook ID whose deliveries should be listed"),
                    "delivery_state": enumSchema("Delivery state filter", values: ["SUCCEEDED", "FAILED", "PENDING"]),
                    "created_after": stringSchema("Filter deliveries created at or after this ISO-8601 date-time"),
                    "created_before": stringSchema("Filter deliveries created before this ISO-8601 date-time"),
                    "include_event": boolSchema("Include related webhook event resources (default: true)"),
                    "limit": integerSchema("Max results (default: 25, max: 200)"),
                    "next_url": stringSchema("Pagination URL from a previous response")
                ],
                required: ["webhook_id"]
            )
        )
    }

    func redeliverTool() -> Tool {
        Tool(
            name: "webhooks_redeliver",
            description: "Create a redelivery attempt from an existing webhook delivery template.",
            inputSchema: baseSchema(
                properties: [
                    "delivery_id": stringSchema("Existing webhook delivery ID to redeliver")
                ],
                required: ["delivery_id"]
            )
        )
    }

    func pingTool() -> Tool {
        Tool(
            name: "webhooks_ping",
            description: "Send a test ping through an existing webhook configuration.",
            inputSchema: baseSchema(
                properties: [
                    "webhook_id": stringSchema("Webhook ID to ping")
                ],
                required: ["webhook_id"]
            )
        )
    }

    private func baseSchema(properties: [String: Value], required: [String]) -> Value {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(Value.string))
        ])
    }

    private func stringSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private func integerSchema(_ description: String) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description)
        ])
    }

    private func boolSchema(_ description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }

    private func enumSchema(_ description: String, values: [String]) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "enum": .array(values.map(Value.string))
        ])
    }

    private func eventTypesSchema(_ description: String) -> Value {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": .object([
                "type": .string("string"),
                "enum": .array(ASCWebhookEventTypes.all.map(Value.string))
            ])
        ])
    }
}
