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
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("app_id")])
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
                    "promoted_purchase_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase ID")
                    ])
                ]),
                "required": .array([.string("promoted_purchase_id")])
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
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "visible": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the promoted purchase is visible to all users")
                    ]),
                    "enabled": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the promoted purchase is enabled; null uses Apple's nullable create value")
                    ]),
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID (provide this OR subscription_id)")
                    ]),
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID (provide this OR iap_id)")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("visible")]),
                "oneOf": .array([
                    .object(["required": .array([.string("iap_id")])]),
                    .object(["required": .array([.string("subscription_id")])])
                ])
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
                    "promoted_purchase_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase ID")
                    ]),
                    "visible": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the promoted purchase is visible to all users, or null to clear Apple's nullable value")
                    ]),
                    "enabled": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the promoted purchase is enabled, or null to clear Apple's nullable value")
                    ])
                ]),
                "required": .array([.string("promoted_purchase_id")])
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
                    "promoted_purchase_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase ID to delete")
                    ])
                ]),
                "required": .array([.string("promoted_purchase_id")])
            ])
        )
    }

    // MARK: - Image Tools

    func uploadPromotedPurchaseImageTool() -> Tool {
        return Tool(
            name: "promoted_upload_image",
            description: "Deprecated: Apple removed promoted purchase image endpoints. Returns migration guidance for iap_*_image or subscriptions_*_image tools without calling Apple.",
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
                "required": .array([.string("promoted_purchase_id"), .string("file_path")])
            ])
        )
    }

    func getPromotedPurchaseImageTool() -> Tool {
        return Tool(
            name: "promoted_get_image",
            description: "Deprecated: Apple removed promoted purchase image endpoints. Returns migration guidance for iap_*_image or subscriptions_*_image tools without calling Apple.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase image ID")
                    ])
                ]),
                "required": .array([.string("image_id")])
            ])
        )
    }

    func deletePromotedPurchaseImageTool() -> Tool {
        return Tool(
            name: "promoted_delete_image",
            description: "Deprecated: Apple removed promoted purchase image endpoints. Returns migration guidance for iap_*_image or subscriptions_*_image tools without calling Apple.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase image ID to delete")
                    ])
                ]),
                "required": .array([.string("image_id")])
            ])
        )
    }

    func getPromotedPurchaseImageForPurchaseTool() -> Tool {
        return Tool(
            name: "promoted_get_image_for_purchase",
            description: "Deprecated: Apple removed the promoted purchase image relationship. Returns migration guidance for product-scoped image tools without calling Apple.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promoted_purchase_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase ID")
                    ])
                ]),
                "required": .array([.string("promoted_purchase_id")])
            ])
        )
    }

}
