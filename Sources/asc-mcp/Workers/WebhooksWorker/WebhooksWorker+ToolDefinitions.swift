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
            description: "Create a webhook notification configuration for an app. Requires name, HTTPS callback URL, secret, and event types. The enabled flag is optional and defaults to true.",
            inputSchema: baseSchema(
                properties: [
                    "app_id": stringSchema("App ID that owns the webhook"),
                    "name": stringSchema("Human-readable webhook name"),
                    "url": stringSchema("Absolute HTTPS callback URL. URL user info (user/password) and fragments are not allowed; custom ports, paths, and query parameters are supported."),
                    "secret": webhookSecretSchema("Secret used by your receiver to verify App Store Connect webhook deliveries. Use a cryptographically random value of at least 32 characters, such as a 32-byte random value encoded as hex or Base64. The secret is never returned by this tool."),
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
                    "url": stringSchema("Absolute HTTPS callback URL to replace the current URL. URL user info (user/password) and fragments are not allowed; custom ports, paths, and query parameters are supported."),
                    "secret": webhookSecretSchema("New cryptographically random webhook secret of at least 32 characters, such as a 32-byte random value encoded as hex or Base64. The secret is never returned by this tool."),
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

    func verifySignatureTool() -> Tool {
        Tool(
            name: "webhooks_verify_signature",
            description: "Verify an App Store Connect webhook x-apple-signature HMAC against the exact raw request body. This is local and does not call Apple. Provide the body via either `payload` (raw UTF-8) or `payload_base64`.",
            inputSchema: baseSchema(
                properties: [
                    "secret": stringSchema("Webhook secret configured in App Store Connect"),
                    "signature": stringSchema("x-apple-signature header value, for example hmacsha256=<hex>"),
                    "payload": stringSchema("Exact raw UTF-8 request body received by your webhook endpoint"),
                    "payload_base64": stringSchema("Base64-encoded exact raw request body bytes; use this when byte-for-byte preservation matters")
                ],
                required: ["secret", "signature"]
            )
        )
    }

    func parsePayloadTool() -> Tool {
        Tool(
            name: "webhooks_parse_payload",
            description: "Parse and normalize a raw App Store Connect webhook payload, including nested event payload JSON when Apple sends it as a string. This is local and read-only. Provide the body via either `payload` (raw UTF-8) or `payload_base64`.",
            inputSchema: baseSchema(
                properties: [
                    "payload": stringSchema("Exact raw UTF-8 request body received by your webhook endpoint"),
                    "payload_base64": stringSchema("Base64-encoded exact raw request body bytes"),
                    "secret": stringSchema("Optional webhook secret used to verify the signature while parsing"),
                    "signature": stringSchema("Optional x-apple-signature header value used with secret")
                ],
                required: []
            )
        )
    }

    func triageEventTool() -> Tool {
        Tool(
            name: "webhooks_triage_event",
            description: "Turn a webhook event or failed delivery context into an actionable MCP triage plan with recommended read-only lookup tools. Provide at least one of: `event_type`, `payload`, or `payload_base64`.",
            inputSchema: baseSchema(
                properties: [
                    "payload": stringSchema("Optional exact raw UTF-8 webhook request body"),
                    "payload_base64": stringSchema("Optional base64-encoded exact raw request body bytes"),
                    "event_type": enumSchema("Webhook event type when raw payload is not available", values: ASCWebhookEventTypes.all),
                    "resource_type": stringSchema("Optional affected App Store Connect resource type from the webhook payload"),
                    "resource_id": stringSchema("Optional affected App Store Connect resource ID from the webhook payload"),
                    "delivery_id": stringSchema("Optional webhook delivery ID for redelivery recommendations"),
                    "webhook_id": stringSchema("Optional webhook configuration ID for ping/delivery recommendations"),
                    "delivery_state": enumSchema("Optional delivery state from webhooks_list_deliveries", values: ["SUCCEEDED", "FAILED", "PENDING"]),
                    "http_status_code": integerSchema("Optional receiver HTTP status code from the delivery response"),
                    "error_message": stringSchema("Optional delivery error message")
                ],
                required: []
            )
        )
    }

    private func baseSchema(properties: [String: Value], required: [String]) -> Value {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(Value.string)),
            "additionalProperties": .bool(false)
        ])
    }

    private func stringSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private func webhookSecretSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(Self.minimumWebhookSecretLength)
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
