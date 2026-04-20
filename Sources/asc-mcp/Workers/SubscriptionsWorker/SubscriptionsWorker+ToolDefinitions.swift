import Foundation
import MCP

// MARK: - Tool Definitions
extension SubscriptionsWorker {

    func listSubscriptionsTool() -> Tool {
        return Tool(
            name: "subscriptions_list",
            description: "List subscriptions in a subscription group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group ID")
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
                "required": .array([.string("group_id")])
            ])
        )
    }

    func getSubscriptionTool() -> Tool {
        return Tool(
            name: "subscriptions_get",
            description: "Get details of a specific subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ])
                ]),
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func createSubscriptionTool() -> Tool {
        return Tool(
            name: "subscriptions_create",
            description: "Create a new subscription in a subscription group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Reference name (internal only)")
                    ]),
                    "product_id": .object([
                        "type": .string("string"),
                        "description": .string("Unique product identifier")
                    ]),
                    "subscription_period": .object([
                        "type": .string("string"),
                        "description": .string("Period: ONE_WEEK, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR")
                    ]),
                    "family_sharable": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable Family Sharing")
                    ]),
                    "group_level": .object([
                        "type": .string("integer"),
                        "description": .string("Level within the subscription group (1 = highest)")
                    ]),
                    "review_note": .object([
                        "type": .string("string"),
                        "description": .string("Notes for App Review")
                    ])
                ]),
                "required": .array([.string("group_id"), .string("name"), .string("product_id"), .string("subscription_period")])
            ])
        )
    }

    func updateSubscriptionTool() -> Tool {
        return Tool(
            name: "subscriptions_update",
            description: "Update an existing subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("New reference name")
                    ]),
                    "family_sharable": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable Family Sharing")
                    ]),
                    "group_level": .object([
                        "type": .string("integer"),
                        "description": .string("Level within the subscription group")
                    ]),
                    "review_note": .object([
                        "type": .string("string"),
                        "description": .string("Notes for App Review")
                    ])
                ]),
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func deleteSubscriptionTool() -> Tool {
        return Tool(
            name: "subscriptions_delete",
            description: "Delete a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID to delete")
                    ])
                ]),
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func listSubscriptionLocalizationsTool() -> Tool {
        return Tool(
            name: "subscriptions_list_localizations",
            description: "List localizations for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func createSubscriptionLocalizationTool() -> Tool {
        return Tool(
            name: "subscriptions_create_localization",
            description: "Create a localization for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
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
                "required": .array([.string("subscription_id"), .string("locale"), .string("name")])
            ])
        )
    }

    func updateSubscriptionLocalizationTool() -> Tool {
        return Tool(
            name: "subscriptions_update_localization",
            description: "Update a localization for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription localization ID")
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

    func deleteSubscriptionLocalizationTool() -> Tool {
        return Tool(
            name: "subscriptions_delete_localization",
            description: "Delete a localization for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription localization ID to delete")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func listSubscriptionPricesTool() -> Tool {
        return Tool(
            name: "subscriptions_list_prices",
            description: "List prices for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
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
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func listSubscriptionPricePointsTool() -> Tool {
        return Tool(
            name: "subscriptions_list_price_points",
            description: "List available price points for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Filter by territory code (e.g. USA, GBR, DEU). Returns price points for that territory only.")
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
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func createSubscriptionGroupTool() -> Tool {
        return Tool(
            name: "subscriptions_create_group",
            description: "Create a new subscription group for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "reference_name": .object([
                        "type": .string("string"),
                        "description": .string("Reference name for the subscription group")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("reference_name")])
            ])
        )
    }

    func updateSubscriptionGroupTool() -> Tool {
        return Tool(
            name: "subscriptions_update_group",
            description: "Update a subscription group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group ID")
                    ]),
                    "reference_name": .object([
                        "type": .string("string"),
                        "description": .string("New reference name")
                    ])
                ]),
                "required": .array([.string("group_id"), .string("reference_name")])
            ])
        )
    }

    func deleteSubscriptionGroupTool() -> Tool {
        return Tool(
            name: "subscriptions_delete_group",
            description: "Delete a subscription group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group ID to delete")
                    ])
                ]),
                "required": .array([.string("group_id")])
            ])
        )
    }

    func listSubscriptionGroupLocalizationsTool() -> Tool {
        return Tool(
            name: "subscriptions_list_group_localizations",
            description: "List localizations for a subscription group (display name, custom app name per locale)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_group_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group ID")
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
                "required": .array([.string("subscription_group_id")])
            ])
        )
    }

    func createSubscriptionGroupLocalizationTool() -> Tool {
        return Tool(
            name: "subscriptions_create_group_localization",
            description: "Create a localization for a subscription group (display name and optional custom app name for a locale)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_group_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Display name of the subscription group for this locale")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans)")
                    ]),
                    "custom_app_name": .object([
                        "type": .string("string"),
                        "description": .string("Custom app name for this locale (optional)")
                    ])
                ]),
                "required": .array([.string("subscription_group_id"), .string("name"), .string("locale")])
            ])
        )
    }

    func getSubscriptionGroupLocalizationTool() -> Tool {
        return Tool(
            name: "subscriptions_get_group_localization",
            description: "Get details of a specific subscription group localization",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group localization ID")
                    ])
                ]),
                "required": .array([.string("group_localization_id")])
            ])
        )
    }

    func updateSubscriptionGroupLocalizationTool() -> Tool {
        return Tool(
            name: "subscriptions_update_group_localization",
            description: "Update a subscription group localization (name and/or custom app name)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group localization ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("New display name")
                    ]),
                    "custom_app_name": .object([
                        "type": .string("string"),
                        "description": .string("New custom app name")
                    ])
                ]),
                "required": .array([.string("group_localization_id")])
            ])
        )
    }

    func deleteSubscriptionGroupLocalizationTool() -> Tool {
        return Tool(
            name: "subscriptions_delete_group_localization",
            description: "Delete a subscription group localization",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription group localization ID to delete")
                    ])
                ]),
                "required": .array([.string("group_localization_id")])
            ])
        )
    }

    func deleteSubscriptionPriceTool() -> Tool {
        return Tool(
            name: "subscriptions_delete_price",
            description: "Delete a scheduled price change for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_price_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription price ID to delete")
                    ])
                ]),
                "required": .array([.string("subscription_price_id")])
            ])
        )
    }

    func submitSubscriptionTool() -> Tool {
        return Tool(
            name: "subscriptions_submit",
            description: "Submit a subscription for App Review",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID to submit for review")
                    ])
                ]),
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    // MARK: - Subscription Image Tools

    func uploadSubscriptionImageTool() -> Tool {
        return Tool(
            name: "subscriptions_upload_image",
            description: "Upload a promotional image for a subscription (full cycle: reserve, upload, commit)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the image file on disk")
                    ])
                ]),
                "required": .array([.string("subscription_id"), .string("file_path")])
            ])
        )
    }

    func getSubscriptionImageTool() -> Tool {
        return Tool(
            name: "subscriptions_get_image",
            description: "Get details of a subscription image",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription image ID")
                    ])
                ]),
                "required": .array([.string("image_id")])
            ])
        )
    }

    func deleteSubscriptionImageTool() -> Tool {
        return Tool(
            name: "subscriptions_delete_image",
            description: "Delete a subscription image",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "image_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription image ID to delete")
                    ])
                ]),
                "required": .array([.string("image_id")])
            ])
        )
    }

    // MARK: - Subscription Review Screenshot Tools

    func uploadSubscriptionReviewScreenshotTool() -> Tool {
        return Tool(
            name: "subscriptions_upload_review_screenshot",
            description: "Upload a review screenshot for a subscription (full cycle: reserve, upload, commit). Used for App Store review.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the image file on disk")
                    ])
                ]),
                "required": .array([.string("subscription_id"), .string("file_path")])
            ])
        )
    }

    func getSubscriptionReviewScreenshotTool() -> Tool {
        return Tool(
            name: "subscriptions_get_review_screenshot",
            description: "Get details of a subscription review screenshot",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "screenshot_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription review screenshot ID")
                    ])
                ]),
                "required": .array([.string("screenshot_id")])
            ])
        )
    }

    func deleteSubscriptionReviewScreenshotTool() -> Tool {
        return Tool(
            name: "subscriptions_delete_review_screenshot",
            description: "Delete a subscription review screenshot",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "screenshot_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription review screenshot ID to delete")
                    ])
                ]),
                "required": .array([.string("screenshot_id")])
            ])
        )
    }

    // MARK: - List Tools

    func listSubscriptionImagesTool() -> Tool {
        return Tool(
            name: "subscriptions_list_images",
            description: "List promotional images for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
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
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func getSubscriptionReviewScreenshotForSubscriptionTool() -> Tool {
        return Tool(
            name: "subscriptions_get_review_screenshot_for_subscription",
            description: "Get the review screenshot for a subscription by subscription ID (singular resource — one per subscription)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ])
                ]),
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func setSubscriptionAvailabilityTool() -> Tool {
        return Tool(
            name: "subscriptions_set_availability",
            description: "Enable a subscription in all 175 App Store territories. Must be called before subscriptions_set_price. Creates the subscriptionAvailability resource with availableInNewTerritories=true.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ])
                ]),
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func setSubscriptionPriceScheduleTool() -> Tool {
        return Tool(
            name: "subscriptions_set_price",
            description: "Set price for a subscription in all territories at once. Gets equalized price points for all ~175 territories from the base USD price point, then updates subscription in a single PATCH request. Use subscriptions_list_price_points with territory=USA to find price_point_id. Prerequisite: call subscriptions_set_availability first.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "price_point_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription price point ID from subscriptions_list_price_points (use territory=USA filter)")
                    ]),
                    "base_territory_id": .object([
                        "type": .string("string"),
                        "description": .string("Base territory ISO code for price calculation (default: USA). Apple propagates prices to all other territories from this base.")
                    ])
                ]),
                "required": .array([.string("subscription_id"), .string("price_point_id")])
            ])
        )
    }
}
