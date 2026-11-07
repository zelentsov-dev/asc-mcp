import Foundation
import MCP

// MARK: - Retention Messaging Tool Definitions (ASC OpenAPI 4.6)
extension SubscriptionsWorker {

    /// Returns the 23 Retention Messaging tools for App Store Connect API 4.6.
    /// - Returns: Array of MCP tool definitions.
    func retentionMessagingTools() -> [Tool] {
        [
            listRetentionMessagesTool(),
            getRetentionMessageTool(),
            createRetentionMessageTool(),
            deleteRetentionMessageTool(),
            listRetentionMessageVersionsTool(),
            getRetentionMessageVersionTool(),
            createRetentionMessageVersionTool(),
            listRetentionMessageLocalizationsTool(),
            getRetentionMessageLocalizationTool(),
            createRetentionMessageLocalizationTool(),
            updateRetentionMessageLocalizationTool(),
            deleteRetentionMessageLocalizationTool(),
            listRetentionMessageSubscriptionsTool(),
            listRetentionOffersTool(),
            getRetentionOfferTool(),
            createRetentionOfferTool(),
            updateRetentionOfferTool(),
            deleteRetentionOfferTool(),
            listRetentionOfferPricesTool(),
            getRetentionMessageForSubscriptionTool(),
            setRetentionMessageTool(),
            addRetentionMessageOffersTool(),
            removeRetentionMessageOffersTool()
        ]
    }

    // MARK: - Retention Messages

    private func listRetentionMessagesTool() -> Tool {
        Tool(
            name: "subscriptions_list_retention_messages",
            description: "List retention messages configured for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
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

    private func getRetentionMessageTool() -> Tool {
        Tool(
            name: "subscriptions_get_retention_message",
            description: "Get details of a specific retention message by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "retention_message_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message ID")
                    ])
                ]),
                "required": .array([.string("retention_message_id")])
            ])
        )
    }

    private func createRetentionMessageTool() -> Tool {
        Tool(
            name: "subscriptions_create_retention_message",
            description: "Create a new retention message for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "reference_name": .object([
                        "type": .string("string"),
                        "description": .string("Internal reference name for the retention message (max 64 characters)"),
                        "maxLength": .int(64)
                    ])
                ]),
                "required": .array([.string("app_id"), .string("reference_name")])
            ])
        )
    }

    private func deleteRetentionMessageTool() -> Tool {
        Tool(
            name: "subscriptions_delete_retention_message",
            description: "Delete a retention message by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "retention_message_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message ID")
                    ])
                ]),
                "required": .array([.string("retention_message_id")])
            ])
        )
    }

    // MARK: - Retention Message Versions

    private func listRetentionMessageVersionsTool() -> Tool {
        Tool(
            name: "subscriptions_list_retention_message_versions",
            description: "List versions for a retention message",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "retention_message_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("retention_message_id")])
            ])
        )
    }

    private func getRetentionMessageVersionTool() -> Tool {
        Tool(
            name: "subscriptions_get_retention_message_version",
            description: "Get details of a retention message version by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message version ID")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }

    private func createRetentionMessageVersionTool() -> Tool {
        Tool(
            name: "subscriptions_create_retention_message_version",
            description: "Create a new version for a retention message",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "retention_message_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message ID")
                    ])
                ]),
                "required": .array([.string("retention_message_id")])
            ])
        )
    }

    // MARK: - Retention Message Localizations

    private func listRetentionMessageLocalizationsTool() -> Tool {
        Tool(
            name: "subscriptions_list_retention_message_localizations",
            description: "List localizations for a retention message version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message version ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }

    private func getRetentionMessageLocalizationTool() -> Tool {
        Tool(
            name: "subscriptions_get_retention_message_localization",
            description: "Get details of a retention message localization by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message localization ID")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    private func createRetentionMessageLocalizationTool() -> Tool {
        Tool(
            name: "subscriptions_create_retention_message_localization",
            description: "Create a localization for a retention message version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message version ID")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. en-US, ru, de-DE)")
                    ]),
                    "header": .object([
                        "type": .string("string"),
                        "description": .string("Retention message header text (max 66 characters, no emoji or price mentions)"),
                        "maxLength": .int(66)
                    ]),
                    "body": .object([
                        "type": .string("string"),
                        "description": .string("Retention message body text (max 144 characters, no emoji or price mentions)"),
                        "maxLength": .int(144)
                    ]),
                    "allow_price_mentions": .object([
                        "type": .string("boolean"),
                        "description": .string("Bypass App Review price/discount mention lint check when explicitly set to true")
                    ])
                ]),
                "required": .array([
                    .string("version_id"),
                    .string("locale"),
                    .string("header"),
                    .string("body")
                ])
            ])
        )
    }

    private func updateRetentionMessageLocalizationTool() -> Tool {
        Tool(
            name: "subscriptions_update_retention_message_localization",
            description: "Update header and/or body for a retention message localization",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message localization ID")
                    ]),
                    "header": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Updated retention message header text (max 66 characters)"),
                        "maxLength": .int(66)
                    ]),
                    "body": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Updated retention message body text (max 144 characters)"),
                        "maxLength": .int(144)
                    ]),
                    "allow_price_mentions": .object([
                        "type": .string("boolean"),
                        "description": .string("Bypass App Review price/discount mention lint check when explicitly set to true")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    private func deleteRetentionMessageLocalizationTool() -> Tool {
        Tool(
            name: "subscriptions_delete_retention_message_localization",
            description: "Delete a retention message localization by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message localization ID")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    // MARK: - Retention Message Subscriptions

    private func listRetentionMessageSubscriptionsTool() -> Tool {
        Tool(
            name: "subscriptions_list_retention_message_subscriptions",
            description: "List subscriptions associated with a retention message",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "retention_message_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention message ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("retention_message_id")])
            ])
        )
    }

    // MARK: - Retention Offers

    private func listRetentionOffersTool() -> Tool {
        Tool(
            name: "subscriptions_list_retention_offers",
            description: "List retention offers for a subscription (all offers or active retention message offers only)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "message_offers_only": .object([
                        "type": .string("boolean"),
                        "description": .string("When true, list only offers linked to the subscription's retention message")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
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

    private func getRetentionOfferTool() -> Tool {
        Tool(
            name: "subscriptions_get_retention_offer",
            description: "Get details of a retention offer by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention offer ID")
                    ])
                ]),
                "required": .array([.string("offer_id")])
            ])
        )
    }

    private func createRetentionOfferTool() -> Tool {
        Tool(
            name: "subscriptions_create_retention_offer",
            description: "Create a retention offer for a subscription with inline territory prices",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "reference_name": .object([
                        "type": .string("string"),
                        "description": .string("Internal reference name for the retention offer (max 64 characters)"),
                        "maxLength": .int(64)
                    ]),
                    "offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Unique offer identifier")
                    ]),
                    "duration": .object([
                        "type": .string("string"),
                        "description": .string("Duration of each offer period"),
                        "enum": .array([
                            .string("THREE_DAYS"),
                            .string("ONE_WEEK"),
                            .string("TWO_WEEKS"),
                            .string("ONE_MONTH"),
                            .string("TWO_MONTHS"),
                            .string("THREE_MONTHS"),
                            .string("SIX_MONTHS"),
                            .string("ONE_YEAR")
                        ])
                    ]),
                    "offer_mode": .object([
                        "type": .string("string"),
                        "description": .string("Offer payment mode"),
                        "enum": .array([
                            .string("PAY_AS_YOU_GO"),
                            .string("PAY_UP_FRONT"),
                            .string("FREE_TRIAL")
                        ])
                    ]),
                    "period_count": .object([
                        "type": .string("integer"),
                        "description": .string("Number of billing periods for the offer (minimum 1)"),
                        "minimum": .int(1)
                    ]),
                    "eligibility_duration_months": .object([
                        "type": .string("integer"),
                        "description": .string("Paid subscription duration in months required for eligibility (1-24, 36, 48, or 60)"),
                        "minimum": .int(1)
                    ]),
                    "wait_between_offers_months": .object([
                        "type": .string("integer"),
                        "description": .string("Optional months a subscriber must wait between retention offers (2-24)"),
                        "minimum": .int(2),
                        "maximum": .int(24)
                    ]),
                    "target_subscription_plan_type": .object([
                        "type": .string("string"),
                        "description": .string("Optional target subscription plan type (MONTHLY or UPFRONT)"),
                        "enum": .array([
                            .string("MONTHLY"),
                            .string("UPFRONT")
                        ])
                    ]),
                    "territory_ids": .object([
                        "type": .string("array"),
                        "description": .string("Territory codes matching price_point_ids 1:1 (e.g. USA, GBR)"),
                        "minItems": .int(1),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "price_point_ids": .object([
                        "type": .string("array"),
                        "description": .string("Subscription price point IDs for the retention offer"),
                        "minItems": .int(1),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([
                    .string("subscription_id"),
                    .string("reference_name"),
                    .string("offer_id"),
                    .string("duration"),
                    .string("offer_mode"),
                    .string("period_count"),
                    .string("eligibility_duration_months"),
                    .string("territory_ids"),
                    .string("price_point_ids")
                ])
            ])
        )
    }

    private func updateRetentionOfferTool() -> Tool {
        Tool(
            name: "subscriptions_update_retention_offer",
            description: "Update eligibility duration or wait between offers for a retention offer",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention offer ID")
                    ]),
                    "eligibility_duration_months": .object([
                        "type": .array([.string("integer"), .string("null")]),
                        "description": .string("Updated paid subscription duration in months (1-24, 36, 48, 60, or null to clear)"),
                        "minimum": .int(1)
                    ]),
                    "wait_between_offers_months": .object([
                        "type": .array([.string("integer"), .string("null")]),
                        "description": .string("Updated wait between offers in months (2-24 or null to clear)"),
                        "minimum": .int(2),
                        "maximum": .int(24)
                    ])
                ]),
                "required": .array([.string("offer_id")])
            ])
        )
    }

    private func deleteRetentionOfferTool() -> Tool {
        Tool(
            name: "subscriptions_delete_retention_offer",
            description: "Delete a retention offer by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention offer ID")
                    ])
                ]),
                "required": .array([.string("offer_id")])
            ])
        )
    }

    private func listRetentionOfferPricesTool() -> Tool {
        Tool(
            name: "subscriptions_list_retention_offer_prices",
            description: "List territory prices for a retention offer",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Retention offer ID")
                    ]),
                    "territory": .object([
                        "type": .array([.string("string"), .string("array")]),
                        "description": .string("Optional territory code or array of territory codes for filter[territory]"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("offer_id")])
            ])
        )
    }

    // MARK: - Subscription Retention Message & Offer Relationships

    private func getRetentionMessageForSubscriptionTool() -> Tool {
        Tool(
            name: "subscriptions_get_retention_message_for_subscription",
            description: "Get the retention message currently assigned to a subscription",
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

    private func setRetentionMessageTool() -> Tool {
        Tool(
            name: "subscriptions_set_retention_message",
            description: "Assign or clear the retention message for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "retention_message_id": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Retention message ID to assign, or null when clearing")
                    ]),
                    "clear": .object([
                        "type": .string("boolean"),
                        "description": .string("Set to true to clear the assigned retention message from the subscription")
                    ])
                ]),
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    private func addRetentionMessageOffersTool() -> Tool {
        Tool(
            name: "subscriptions_add_retention_message_offers",
            description: "Attach retention offers to a subscription's retention message configuration",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "offer_ids": .object([
                        "type": .string("array"),
                        "description": .string("Retention offer IDs to attach"),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("subscription_id"), .string("offer_ids")])
            ])
        )
    }

    private func removeRetentionMessageOffersTool() -> Tool {
        Tool(
            name: "subscriptions_remove_retention_message_offers",
            description: "Remove retention offers from a subscription's retention message configuration",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "offer_ids": .object([
                        "type": .string("array"),
                        "description": .string("Retention offer IDs to remove"),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("subscription_id"), .string("offer_ids")])
            ])
        )
    }
}
