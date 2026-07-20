import Foundation
import MCP

// MARK: - Tool Definitions
extension AppsWorker {
    
    func listAppsTool() -> Tool {
        return Tool(
            name: "apps_list",
            description: "List all apps from App Store Connect",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of apps (default 25)"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort order"),
                        "enum": .array([
                            .string("name"), .string("-name"),
                            .string("bundleId"), .string("-bundleId"),
                            .string("sku"), .string("-sku")
                        ])
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by Bundle ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Filter by app name")
                    ]),
                    "app_ids": stringArrayProperty("Filter by App Store Connect app IDs"),
                    "skus": stringArrayProperty("Filter by SKU values"),
                    "app_store_version_ids": stringArrayProperty("Filter by related App Store version IDs"),
                    "app_store_states": stringArrayProperty(
                        "Filter by legacy App Store version states",
                        allowedValues: [
                            "ACCEPTED", "DEVELOPER_REMOVED_FROM_SALE", "DEVELOPER_REJECTED", "IN_REVIEW",
                            "INVALID_BINARY", "METADATA_REJECTED", "PENDING_APPLE_RELEASE", "PENDING_CONTRACT",
                            "PENDING_DEVELOPER_RELEASE", "PREPARE_FOR_SUBMISSION", "PREORDER_READY_FOR_SALE",
                            "PROCESSING_FOR_APP_STORE", "READY_FOR_REVIEW", "READY_FOR_SALE", "REJECTED",
                            "REMOVED_FROM_SALE", "WAITING_FOR_EXPORT_COMPLIANCE", "WAITING_FOR_REVIEW",
                            "REPLACED_WITH_NEW_VERSION", "NOT_APPLICABLE"
                        ],
                        deprecated: true
                    ),
                    "platforms": stringArrayProperty(
                        "Filter by related App Store version platforms",
                        allowedValues: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
                    ),
                    "app_version_states": stringArrayProperty(
                        "Filter by current App Store version states",
                        allowedValues: [
                            "ACCEPTED", "DEVELOPER_REJECTED", "IN_REVIEW", "INVALID_BINARY",
                            "METADATA_REJECTED", "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE",
                            "PREPARE_FOR_SUBMISSION", "PROCESSING_FOR_DISTRIBUTION", "READY_FOR_DISTRIBUTION",
                            "READY_FOR_REVIEW", "REJECTED", "REPLACED_WITH_NEW_VERSION",
                            "WAITING_FOR_EXPORT_COMPLIANCE", "WAITING_FOR_REVIEW"
                        ]
                    ),
                    "review_submission_states": stringArrayProperty(
                        "Filter by review submission states",
                        allowedValues: [
                            "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES",
                            "CANCELING", "COMPLETING", "COMPLETE"
                        ]
                    ),
                    "review_submission_platforms": stringArrayProperty(
                        "Filter by review submission platforms",
                        allowedValues: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
                    ),
                    "has_game_center_enabled_versions": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter by whether the app has Game Center-enabled versions"),
                        "deprecated": .bool(true)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat the originating filters, sort, and effective limit with next_url; the full query and cursor are validated.")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func getAppDetailsTool() -> Tool {
        return Tool(
            name: "apps_get_details",
            description: "Get detailed information about a specific app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "include": .object([
                        "type": .string("string"),
                        "description": .string("Additional related data to include")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }
    
    func listVersionsTool() -> Tool {
        return Tool(
            name: "apps_list_versions",
            description: "List all app versions with their IDs and states",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "version_ids": stringArrayProperty("Filter by App Store version IDs"),
                    "version_strings": stringArrayProperty("Filter by version strings"),
                    "app_store_states": stringArrayProperty(
                        "Filter by legacy App Store version states",
                        allowedValues: [
                            "ACCEPTED", "DEVELOPER_REMOVED_FROM_SALE", "DEVELOPER_REJECTED", "IN_REVIEW",
                            "INVALID_BINARY", "METADATA_REJECTED", "PENDING_APPLE_RELEASE", "PENDING_CONTRACT",
                            "PENDING_DEVELOPER_RELEASE", "PREPARE_FOR_SUBMISSION", "PREORDER_READY_FOR_SALE",
                            "PROCESSING_FOR_APP_STORE", "READY_FOR_REVIEW", "READY_FOR_SALE", "REJECTED",
                            "REMOVED_FROM_SALE", "WAITING_FOR_EXPORT_COMPLIANCE", "WAITING_FOR_REVIEW",
                            "REPLACED_WITH_NEW_VERSION", "NOT_APPLICABLE"
                        ],
                        deprecated: true
                    ),
                    "app_version_states": stringArrayProperty(
                        "Filter by current App Store version states",
                        allowedValues: [
                            "ACCEPTED", "DEVELOPER_REJECTED", "IN_REVIEW", "INVALID_BINARY",
                            "METADATA_REJECTED", "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE",
                            "PREPARE_FOR_SUBMISSION", "PROCESSING_FOR_DISTRIBUTION", "READY_FOR_DISTRIBUTION",
                            "READY_FOR_REVIEW", "REJECTED", "REPLACED_WITH_NEW_VERSION",
                            "WAITING_FOR_EXPORT_COMPLIANCE", "WAITING_FOR_REVIEW"
                        ]
                    ),
                    "platforms": stringArrayProperty(
                        "Filter by platform",
                        allowedValues: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
                    ),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat the originating version filters with next_url; the full query and cursor are validated.")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func searchAppsTool() -> Tool {
        return Tool(
            name: "apps_search",
            description: "Search apps by exact name or Bundle ID. Follows every Apple result page for both filters, de-duplicates by app ID, and returns deterministic name, bundle ID, SKU, and ID order.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search query (app name or Bundle ID)")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }
    
    func getAppMetadataTool() -> Tool {
        return Tool(
            name: "apps_get_metadata",
            description: """
                Get app metadata (description, whatsNew, keywords, etc.) for a version and localization.

                Behavior:
                - Without locale: returns ALL locales in one request
                - Without version_id: auto-selects version by appVersionState, then platform (priority: PREPARE_FOR_SUBMISSION > REJECTED > METADATA_REJECTED > READY_FOR_DISTRIBUTION; legacy READY_FOR_SALE remains supported)
                - include_media: false by default, media loaded only on request
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans). If omitted — returns all locales")
                    ]),
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("App version ID. If omitted — auto-selects suitable version")
                    ]),
                    "version_state": .object([
                        "type": .string("string"),
                        "description": .string("appVersionState filter. Legacy appStoreState is used only when Apple omits appVersionState")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Optional platform used to select or validate the version"),
                        "enum": .array([.string("IOS"), .string("MAC_OS"), .string("TV_OS"), .string("VISION_OS")])
                    ]),
                    "include_media": .object([
                        "type": .string("boolean"),
                        "description": .string("Include screenshots and videos in response (default: false)")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func updateMetadataTool() -> Tool {
        return Tool(
            name: "apps_update_metadata",
            description: "Update app version metadata for a specific localization. App Store Connect validates whether the current version state is editable; rejected metadata can be edited for resubmission.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("App version ID (get via apps_list_versions)")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. 'en-US', 'ru-RU', 'de-DE', 'fr-FR', 'ja', 'zh-Hans')")
                    ]),
                    "description": nullableMetadataProperty("App description (up to 4000 characters)"),
                    "whats_new": nullableMetadataProperty("What's New in This Version (up to 4000 characters)"),
                    "keywords": nullableMetadataProperty("Keywords separated by commas (up to 100 characters)"),
                    "promotional_text": nullableMetadataProperty("Promotional text (up to 170 characters)"),
                    "support_url": nullableMetadataProperty("Support URL"),
                    "marketing_url": nullableMetadataProperty("Marketing URL")
                ]),
                "required": .array([.string("app_id"), .string("version_id"), .string("locale")])
            ])
        )
    }

    private func nullableMetadataProperty(_ description: String) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "description": .string("\(description). Pass null to clear the value.")
        ])
    }
    
    func createLocalizationTool() -> Tool {
        return Tool(
            name: "apps_create_localization",
            description: "Create a new localization for an app version. Locale format depends on language: ru, ja (language only) vs en-US, de-DE (with region). Use apps_list_localizations to see existing locales.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("App version ID (get via apps_list_versions)")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. 'en-US', 'ru-RU', 'de-DE', 'fr-FR', 'ja', 'zh-Hans')")
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("App description (up to 4000 characters)")
                    ]),
                    "whats_new": .object([
                        "type": .string("string"),
                        "description": .string("What's New in This Version (up to 4000 characters)")
                    ]),
                    "keywords": .object([
                        "type": .string("string"),
                        "description": .string("Keywords separated by commas (up to 100 characters)")
                    ]),
                    "promotional_text": .object([
                        "type": .string("string"),
                        "description": .string("Promotional text (up to 170 characters)")
                    ]),
                    "support_url": .object([
                        "type": .string("string"),
                        "description": .string("Support URL")
                    ]),
                    "marketing_url": .object([
                        "type": .string("string"),
                        "description": .string("Marketing URL")
                    ])
                ]),
                "required": .array([.string("version_id"), .string("locale")])
            ])
        )
    }

    func deleteLocalizationTool() -> Tool {
        return Tool(
            name: "apps_delete_localization",
            description: "Delete an app version localization",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Localization ID to delete (get via apps_list_localizations)")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func listLocalizationsTool() -> Tool {
        return Tool(
            name: "apps_list_localizations",
            description: "List all localizations for an app version",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("App version ID")
                    ]),
                    "locales": stringArrayProperty("Filter by locale codes"),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of localizations (default 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(200)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat the originating locales and effective limit with next_url; the full query and cursor are validated.")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("version_id")])
            ]
        )
    }

    private func stringArrayProperty(
        _ description: String,
        allowedValues: [String]? = nil,
        deprecated: Bool = false
    ) -> Value {
        var itemSchema: [String: Value] = ["type": .string("string")]
        if let allowedValues {
            itemSchema["enum"] = .array(allowedValues.map(Value.string))
        }
        var schema: [String: Value] = [
            "type": .string("array"),
            "items": .object(itemSchema),
            "description": .string(description),
            "minItems": .int(1),
            "uniqueItems": .bool(true)
        ]
        if deprecated {
            schema["deprecated"] = .bool(true)
        }
        return .object(schema)
    }
}
