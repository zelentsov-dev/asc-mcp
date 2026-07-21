import Foundation
import MCP

// MARK: - Tool Definitions
extension PromotedPurchasesWorker {

    func listPromotedPurchasesTool() -> Tool {
        return Tool(
            name: "promoted_list",
            description: "List promoted in-app purchases for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": promotedCanonicalIDSchema("App Store Connect app ID"),
                    "limit": promotedLimitSchema(),
                    "next_url": promotedNextURLSchema()
                ]),
                "required": .array([.string("app_id")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    func getPromotedPurchaseTool() -> Tool {
        return Tool(
            name: "promoted_get",
            description: "Get details of a specific promoted purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promoted_purchase_id": promotedCanonicalIDSchema("Promoted purchase ID")
                ]),
                "required": .array([.string("promoted_purchase_id")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    func createPromotedPurchaseTool() -> Tool {
        return Tool(
            name: "promoted_create",
            description: "Create a promoted purchase for exactly one IAP or subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": promotedCanonicalIDSchema("App Store Connect app ID"),
                    "visible": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the promoted purchase is visible to all users")
                    ]),
                    "enabled": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the promoted purchase is enabled; null uses Apple's nullable create value")
                    ]),
                    "iap_id": promotedCanonicalIDSchema("In-app purchase ID (provide this OR subscription_id)"),
                    "subscription_id": promotedCanonicalIDSchema("Subscription ID (provide this OR iap_id)")
                ]),
                "required": .array([.string("app_id"), .string("visible")]),
                "oneOf": .array([
                    .object(["required": .array([.string("iap_id")])]),
                    .object(["required": .array([.string("subscription_id")])])
                ]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    func updatePromotedPurchaseTool() -> Tool {
        return Tool(
            name: "promoted_update",
            description: "Update a promoted purchase visibility or enabled state",
            inputSchema: .object([
                "type": .string("object"),
                "minProperties": .int(2),
                "properties": .object([
                    "promoted_purchase_id": promotedCanonicalIDSchema("Promoted purchase ID"),
                    "visible": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the promoted purchase is visible to all users, or null to clear Apple's nullable value")
                    ]),
                    "enabled": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the promoted purchase is enabled, or null to clear Apple's nullable value")
                    ])
                ]),
                "required": .array([.string("promoted_purchase_id")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    func deletePromotedPurchaseTool() -> Tool {
        return Tool(
            name: "promoted_delete",
            description: "Delete a promoted purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promoted_purchase_id": promotedCanonicalIDSchema("Promoted purchase ID to delete"),
                    "confirm_promoted_purchase_id": promotedCanonicalIDSchema("Must exactly match promoted_purchase_id to confirm irreversible deletion")
                ]),
                "required": .array([
                    .string("promoted_purchase_id"),
                    .string("confirm_promoted_purchase_id")
                ]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    func reorderPromotedPurchasesTool() -> Tool {
        return Tool(
            name: "promoted_reorder",
            description: "Replace the order of every promoted purchase for an app. The ordered JSON array must contain each current promoted purchase ID exactly once.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": promotedCanonicalIDSchema("App Store Connect app ID"),
                    "promoted_purchase_ids": .object([
                        "type": .string("array"),
                        "description": .string("Every current promoted purchase ID in the desired order"),
                        "items": promotedCanonicalIDSchema("Promoted purchase ID"),
                        "minItems": .int(1),
                        "maxItems": .int(200),
                        "uniqueItems": .bool(true)
                    ])
                ]),
                "required": .array([
                    .string("app_id"),
                    .string("promoted_purchase_ids")
                ]),
                "additionalProperties": .bool(false)
            ]),
            annotations: Tool.Annotations(
                title: nil,
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            )
        )
    }

    private func promotedCanonicalIDSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#),
            "description": .string(description)
        ])
    }

    private func promotedLimitSchema() -> Value {
        .object([
            "type": .string("integer"),
            "minimum": .int(1),
            "maximum": .int(200),
            "default": .int(25),
            "description": .string("Max results (default: 25, max: 200)")
        ])
    }

    private func promotedNextURLSchema() -> Value {
        .object([
            "type": .string("string"),
            "format": .string("uri-reference"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!.*\s).+$"#),
            "description": .string("Pagination URL from the previous response; the app, effective limit, configured origin, exact path, query, and cursor are validated")
        ])
    }

    // MARK: - Image Tools

    func uploadPromotedPurchaseImageTool() -> Tool {
        return Tool(
            name: "promoted_upload_image",
            description: "Deprecated: promoted purchase image endpoints are absent from pinned executable OpenAPI 4.4.1. Returns migration guidance for iap_*_image or subscriptions_*_image tools without calling Apple.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promoted_purchase_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase ID to upload image for")
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the image file on disk")
                    ])
                ]),
                "required": .array([.string("promoted_purchase_id"), .string("file_path")]),
                "additionalProperties": .bool(false)
            ]),
            annotations: Tool.Annotations(
                title: nil,
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        )
    }

    func getPromotedPurchaseImageTool() -> Tool {
        return Tool(
            name: "promoted_get_image",
            description: "Deprecated: promoted purchase image endpoints are absent from pinned executable OpenAPI 4.4.1. Returns migration guidance for iap_*_image or subscriptions_*_image tools without calling Apple.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase image ID")
                    ])
                ]),
                "required": .array([.string("image_id")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    func deletePromotedPurchaseImageTool() -> Tool {
        return Tool(
            name: "promoted_delete_image",
            description: "Deprecated: promoted purchase image endpoints are absent from pinned executable OpenAPI 4.4.1. Returns migration guidance for iap_*_image or subscriptions_*_image tools without calling Apple.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase image ID to delete")
                    ])
                ]),
                "required": .array([.string("image_id")]),
                "additionalProperties": .bool(false)
            ]),
            annotations: Tool.Annotations(
                title: nil,
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        )
    }

    func getPromotedPurchaseImageForPurchaseTool() -> Tool {
        return Tool(
            name: "promoted_get_image_for_purchase",
            description: "Deprecated: the promoted purchase image relationship is absent from pinned executable OpenAPI 4.4.1. Returns migration guidance for product-scoped image tools without calling Apple.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promoted_purchase_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase ID")
                    ])
                ]),
                "required": .array([.string("promoted_purchase_id")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

}
