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
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "filter_state": .object([
                        "description": .string("Filter by one or more App Store states"),
                        "oneOf": .array([
                            .object([
                                "type": .string("string"),
                                "enum": .array(Self.iapCatalogStates.map(Value.string))
                            ]),
                            .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("string"),
                                    "enum": .array(Self.iapCatalogStates.map(Value.string))
                                ]),
                                "minItems": .int(1),
                                "uniqueItems": .bool(true)
                            ])
                        ])
                    ]),
                    "filter_type": iapEnumListSchema(
                        "Filter by one or more in-app purchase types",
                        values: Self.iapCatalogTypes
                    ),
                    "filter_name": iapStringListSchema("Filter by one or more exact reference names"),
                    "filter_product_id": iapStringListSchema("Filter by one or more exact product identifiers"),
                    "sort": iapEnumListSchema(
                        "Sort by reference name or in-app purchase type; prefix with - for descending order",
                        values: Self.iapCatalogSortValues
                    ),
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
                        "description": .string("In-app purchase type"),
                        "enum": .array([
                            .string("CONSUMABLE"),
                            .string("NON_CONSUMABLE"),
                            .string("NON_RENEWING_SUBSCRIPTION")
                        ])
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
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped localization API. No auto-migration is performed. Use iap_list_versions and iap_list_version_localizations.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID")
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
                    "filter_reference_name": iapStringListSchema("Filter by one or more exact group reference names"),
                    "filter_subscription_state": iapEnumListSchema(
                        "Filter groups by one or more related subscription states",
                        values: Self.subscriptionCatalogStates
                    ),
                    "sort": iapEnumListSchema(
                        "Sort by group reference name; prefix with - for descending order",
                        values: Self.subscriptionGroupSortValues
                    ),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func iapStringListSchema(_ description: String) -> Value {
        .object([
            "description": .string("\(description); individual values cannot contain commas"),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "minLength": .int(1),
                    "pattern": .string("^[^,]+$")
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "pattern": .string("^[^,]+$")
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    func iapEnumListSchema(_ description: String, values: [String]) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": .array(values.map(Value.string))
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(values.map(Value.string))
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    func createIAPLocalizationTool() -> Tool {
        return Tool(
            name: "iap_create_localization",
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped localization API. No auto-migration is performed. Use iap_list_versions first, iap_create_version when needed, then iap_create_version_localization.",
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
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped localization API. No auto-migration is performed. Use iap_update_version_localization.",
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
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped localization API. No auto-migration is performed. Use iap_delete_version_localization.",
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
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped submission API. No auto-migration is performed. Use iap_list_versions first, iap_create_version when needed, then review_submissions_create, review_submissions_add_item, and review_submissions_submit with the IAP version.",
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
                    "territory_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by territory ID (e.g. USA, GBR)")
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Deprecated alias for territory_id")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 50, max: 8000)")
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
                "additionalProperties": .bool(false),
                "maxProperties": .int(3),
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
                        "description": .string("Legacy comma-separated list of existing inAppPurchasePrices IDs; mutually exclusive with manual_prices")
                    ]),
                    "manual_prices": .object([
                        "type": .string("array"),
                        "description": .string("Inline manual prices; mutually exclusive with manual_price_ids"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "price_point_id": .object([
                                    "type": .string("string"),
                                    "description": .string("In-app purchase price point ID")
                                ]),
                                "start_date": .object([
                                    "type": .string("string"),
                                    "format": .string("date"),
                                    "description": .string("Optional inclusive start date in YYYY-MM-DD format")
                                ]),
                                "end_date": .object([
                                    "type": .string("string"),
                                    "format": .string("date"),
                                    "description": .string("Optional inclusive end date in YYYY-MM-DD format")
                                ])
                            ]),
                            "required": .array([.string("price_point_id")]),
                            "additionalProperties": .bool(false)
                        ])
                    ])
                ]),
                "required": .array([.string("iap_id"), .string("base_territory_id")]),
                "allOf": .array([
                    .object([
                        "not": .object([
                            "required": .array([.string("manual_price_ids"), .string("manual_prices")])
                        ])
                    ])
                ])
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
                    "iap_id": .object([
                        "type": .string("string"),
                        "description": .string("In-app purchase ID; preferred for direct availability reads")
                    ]),
                    "include_territories": .object([
                        "type": .string("boolean"),
                        "description": .string("Include the first territory projection (default: true); use iap_list_available_territories for pagination")
                    ]),
                    "territory_limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(50),
                        "description": .string("Maximum expanded territories in the projection (default: 50, Apple max: 50)")
                    ])
                ]),
                "required": .array([]),
                "oneOf": .array([
                    .object(["required": .array([.string("iap_id")])]),
                    .object(["required": .array([.string("availability_id")])])
                ])
            ])
        )
    }

    func uploadIAPImageTool() -> Tool {
        return Tool(
            name: "iap_upload_image",
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped IAP image API. No auto-migration is performed. Use iap_list_versions first, iap_create_version when needed, then iap_upload_version_image. This compatibility flow still snapshots, reserves, transfers, commits, rolls back pre-commit failures, and reconciles uncertain commits.",
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
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped IAP image API. No auto-migration is performed. Use iap_get_version_image_resource.",
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
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped IAP image API. No auto-migration is performed. Use iap_delete_version_image.",
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
            description: "Upload an IAP review screenshot from an immutable snapshot, then reserve, transfer, commit, and verify Apple processing. Pre-commit failures roll back; uncertain commits are retained and reconciled. A confirmed commit can return success with deliveryPending=true while Apple continues asynchronous processing; inspect that screenshot instead of retrying.",
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
            description: "Apple 4.4.1 release notes deprecate this legacy product-scoped IAP image API. No auto-migration is performed. Use iap_list_versions and iap_get_version_image.",
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
