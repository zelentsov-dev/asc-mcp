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
                        "description": .string("Maximum number of apps (default 25)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort order: name, -name, bundleId, -bundleId")
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by Bundle ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Filter by app name")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Next page URL from previous response (next_url field)")
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
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Next page URL from previous response (next_url field)")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func searchAppsTool() -> Tool {
        return Tool(
            name: "apps_search",
            description: "Search apps by name or Bundle ID",
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
                - Without version_id: auto-selects version (priority: PREPARE_FOR_SUBMISSION > READY_FOR_SALE)
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
                        "description": .string("Version state filter: PREPARE_FOR_SUBMISSION (editable) or READY_FOR_SALE (published)")
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
            description: "Update ALL app metadata for a locale in one call: name, subtitle (from appInfo) + keywords, description, whatsNew (from version). Version must be editable (PREPARE_FOR_SUBMISSION or DEVELOPER_REJECTED).",
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
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("App name/title for this locale (max 30 characters). Stored in appInfoLocalizations.")
                    ]),
                    "subtitle": .object([
                        "type": .string("string"),
                        "description": .string("App subtitle for this locale (max 30 characters). Stored in appInfoLocalizations.")
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
                "required": .array([.string("app_id"), .string("version_id"), .string("locale")])
            ])
        )
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
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Next page URL from previous response (next_url field)")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("version_id")])
            ]
        )
    }
}