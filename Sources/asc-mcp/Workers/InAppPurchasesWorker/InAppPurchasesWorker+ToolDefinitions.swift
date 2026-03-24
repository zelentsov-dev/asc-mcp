import Foundation
import MCP

// MARK: - Tool Definitions
extension InAppPurchasesWorker {

    func listIAPTool() -> Tool {
        return Tool(
            name: "iap_list",
            description: "List in-app purchases for an app",
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
                    "filter_state": .object([
                        "type": .string("string"),
                        "description": .string("Filter by state (e.g. APPROVED, DEVELOPER_ACTION_NEEDED)")
                    ]),
                    "filter_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by type: CONSUMABLE, NON_CONSUMABLE, AUTO_RENEWABLE, NON_RENEWING")
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

    func getIAPTool() -> Tool {
        return Tool(
            name: "iap_get",
            description: "Get details of a specific in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ])
                ]),
                "required": .array([.string("iap_id")])
            ])
        )
    }

    func createIAPTool() -> Tool {
        return Tool(
            name: "iap_create",
            description: "Create a new in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Reference name (internal only)")
                    ]),
                    "product_id": .object([
                        "type": .string("string"),
                        "description": .string("Unique product identifier")
                    ]),
                    "iap_type": .object([
                        "type": .string("string"),
                        "description": .string("CONSUMABLE, NON_CONSUMABLE, AUTO_RENEWABLE, NON_RENEWING")
                    ]),
                    "review_note": .object([
                        "type": .string("string"),
                        "description": .string("Notes for App Review")
                    ]),
                    "family_sharable": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable Family Sharing")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("name"), .string("product_id"), .string("iap_type")])
            ])
        )
    }

    func updateIAPTool() -> Tool {
        return Tool(
            name: "iap_update",
            description: "Update an existing in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("New reference name")
                    ]),
                    "review_note": .object([
                        "type": .string("string"),
                        "description": .string("Notes for App Review")
                    ]),
                    "family_sharable": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable Family Sharing")
                    ])
                ]),
                "required": .array([.string("iap_id")])
            ])
        )
    }

    func deleteIAPTool() -> Tool {
        return Tool(
            name: "iap_delete",
            description: "Delete an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID to delete")
                    ])
                ]),
                "required": .array([.string("iap_id")])
            ])
        )
    }

    func listIAPLocalizationsTool() -> Tool {
        return Tool(
            name: "iap_list_localizations",
            description: "List localizations for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("iap_id")])
            ])
        )
    }

    func listSubscriptionGroupsTool() -> Tool {
        return Tool(
            name: "iap_list_subscriptions",
            description: "List subscription groups for an app",
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

    func createIAPLocalizationTool() -> Tool {
        return Tool(
            name: "iap_create_localization",
            description: "Create a localization for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans)")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Display name for the locale")
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("Description for the locale")
                    ])
                ]),
                "required": .array([.string("iap_id"), .string("locale"), .string("name")])
            ])
        )
    }

    func updateIAPLocalizationTool() -> Tool {
        return Tool(
            name: "iap_update_localization",
            description: "Update a localization for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("IAP localization ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("New display name")
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("New description")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func deleteIAPLocalizationTool() -> Tool {
        return Tool(
            name: "iap_delete_localization",
            description: "Delete a localization for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("IAP localization ID to delete")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func submitIAPForReviewTool() -> Tool {
        return Tool(
            name: "iap_submit_for_review",
            description: "Submit an in-app purchase for App Review",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID to submit")
                    ])
                ]),
                "required": .array([.string("iap_id")])
            ])
        )
    }

    func getSubscriptionGroupTool() -> Tool {
        return Tool(
            name: "iap_get_subscription_group",
            description: "Get details of a subscription group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group ID")
                    ]),
                    "include_subscriptions": .object([
                        "type": .string("boolean"),
                        "description": .string("Include subscriptions (default: true)")
                    ])
                ]),
                "required": .array([.string("group_id")])
            ])
        )
    }

    func listIAPPricePointsTool() -> Tool {
        return Tool(
            name: "iap_list_price_points",
            description: "List price points for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Filter by territory code (e.g. USA, GBR)")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 50, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("iap_id")])
            ])
        )
    }

    func getIAPPriceScheduleTool() -> Tool {
        return Tool(
            name: "iap_get_price_schedule",
            description: "Get price schedule for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ])
                ]),
                "required": .array([.string("iap_id")])
            ])
        )
    }

    func setIAPPriceScheduleTool() -> Tool {
        return Tool(
            name: "iap_set_price_schedule",
            description: "Set price schedule for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ]),
                    "base_territory_id": .object([
                        "type": .string("string"),
                        "description": .string("Base territory ID (e.g. USA)")
                    ]),
                    "manual_price_ids": .object([
                        "type": .string("string"),
                        "description": .string("Comma-separated list of manual price IDs")
                    ])
                ]),
                "required": .array([.string("iap_id"), .string("base_territory_id")])
            ])
        )
    }

    func getIAPReviewScreenshotTool() -> Tool {
        return Tool(
            name: "iap_get_review_screenshot",
            description: "Get App Store Review screenshot for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ])
                ]),
                "required": .array([.string("iap_id")])
            ])
        )
    }

    func setIAPAvailabilityTool() -> Tool {
        return Tool(
            name: "iap_set_availability",
            description: "Set territorial availability for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ]),
                    "available_in_new_territories": .object([
                        "type": .string("boolean"),
                        "description": .string("Automatically available in new territories")
                    ]),
                    "territory_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of territory IDs (e.g. [\"USA\", \"GBR\", \"DEU\"])"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("iap_id"), .string("available_in_new_territories"), .string("territory_ids")])
            ])
        )
    }

    func getIAPAvailabilityTool() -> Tool {
        return Tool(
            name: "iap_get_availability",
            description: "Get availability details for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "availability_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase availability ID")
                    ]),
                    "include_territories": .object([
                        "type": .string("boolean"),
                        "description": .string("Include available territories (default: true)")
                    ])
                ]),
                "required": .array([.string("availability_id")])
            ])
        )
    }

    func uploadIAPImageTool() -> Tool {
        return Tool(
            name: "iap_upload_image",
            description: "Upload an image for an in-app purchase (full cycle: reserve, upload, commit). Used for promotional images displayed on the App Store.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the image file on disk")
                    ])
                ]),
                "required": .array([.string("iap_id"), .string("file_path")])
            ])
        )
    }

    func getIAPImageTool() -> Tool {
        return Tool(
            name: "iap_get_image",
            description: "Get details of an in-app purchase image",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase image ID")
                    ])
                ]),
                "required": .array([.string("image_id")])
            ])
        )
    }

    func deleteIAPImageTool() -> Tool {
        return Tool(
            name: "iap_delete_image",
            description: "Delete an in-app purchase image",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase image ID to delete")
                    ])
                ]),
                "required": .array([.string("image_id")])
            ])
        )
    }

    func uploadIAPReviewScreenshotTool() -> Tool {
        return Tool(
            name: "iap_upload_review_screenshot",
            description: "Upload a screenshot for App Store Review of an in-app purchase (full cycle: reserve, upload, commit)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the screenshot file on disk")
                    ])
                ]),
                "required": .array([.string("iap_id"), .string("file_path")])
            ])
        )
    }

    func deleteIAPReviewScreenshotTool() -> Tool {
        return Tool(
            name: "iap_delete_review_screenshot",
            description: "Delete an App Store Review screenshot for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "screenshot_id": .object([
                        "type": .string("string"),
                        "description": .string("IAP review screenshot ID to delete")
                    ])
                ]),
                "required": .array([.string("screenshot_id")])
            ])
        )
    }

    func listIAPImagesTool() -> Tool {
        return Tool(
            name: "iap_list_images",
            description: "List images for an in-app purchase",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
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
                "required": .array([.string("iap_id")])
            ])
        )
    }
}
