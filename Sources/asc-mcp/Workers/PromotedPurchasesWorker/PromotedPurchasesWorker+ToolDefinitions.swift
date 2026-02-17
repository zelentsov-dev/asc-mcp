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
            description: "Create a promoted purchase for an IAP or subscription. Provide either iap_id or subscription_id",
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
                        "type": .string("boolean"),
                        "description": .string("Whether the promoted purchase is enabled")
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
                "required": .array([.string("app_id"), .string("visible"), .string("enabled")])
            ])
        )
    }

    func updatePromotedPurchaseTool() -> Tool {
        return Tool(
            name: "promoted_update",
            description: "Update a promoted purchase visibility or enabled state",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promoted_purchase_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase ID")
                    ]),
                    "visible": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the promoted purchase is visible to all users")
                    ]),
                    "enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the promoted purchase is enabled")
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

    func listPromotionImagesTool() -> Tool {
        return Tool(
            name: "promoted_list_images",
            description: "List promotion images for a promoted purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promoted_purchase_id": .object([
                        "type": .string("string"),
                        "description": .string("Promoted purchase ID")
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
                "required": .array([.string("promoted_purchase_id")])
            ])
        )
    }
}
