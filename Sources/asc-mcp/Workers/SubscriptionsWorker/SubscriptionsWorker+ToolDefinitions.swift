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
}
