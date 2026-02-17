//
//  AppInfoWorker+ToolDefinitions.swift
//  asc-mcp
//
//  Tool definitions for app info operations
//

import Foundation
import MCP

// MARK: - Tool Definitions
extension AppInfoWorker {

    /// Creates tool definition for listing app infos
    func listAppInfosTool() -> Tool {
        return Tool(
            name: "app_info_list",
            description: "List app info objects for an app (each version has its own app info with categories and age rating)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    /// Creates tool definition for getting app info details
    func getAppInfoTool() -> Tool {
        return Tool(
            name: "app_info_get",
            description: "Get app info details including categories, age rating, and optionally included resources",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "info_id": .object([
                        "type": .string("string"),
                        "description": .string("App info ID")
                    ]),
                    "include": .object([
                        "type": .string("string"),
                        "description": .string("Comma-separated list of related resources to include: primaryCategory, primarySubcategoryOne, primarySubcategoryTwo, secondaryCategory, secondarySubcategoryOne, secondarySubcategoryTwo, appInfoLocalizations")
                    ])
                ]),
                "required": .array([.string("info_id")])
            ])
        )
    }

    /// Creates tool definition for updating app info (categories)
    func updateAppInfoTool() -> Tool {
        return Tool(
            name: "app_info_update",
            description: "Update app info categories (primary/secondary category and subcategories)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "info_id": .object([
                        "type": .string("string"),
                        "description": .string("App info ID")
                    ]),
                    "primary_category_id": .object([
                        "type": .string("string"),
                        "description": .string("Primary category ID (e.g., GAMES, PRODUCTIVITY)")
                    ]),
                    "secondary_category_id": .object([
                        "type": .string("string"),
                        "description": .string("Secondary category ID")
                    ]),
                    "primary_subcategory_one_id": .object([
                        "type": .string("string"),
                        "description": .string("Primary subcategory one ID")
                    ]),
                    "primary_subcategory_two_id": .object([
                        "type": .string("string"),
                        "description": .string("Primary subcategory two ID")
                    ]),
                    "secondary_subcategory_one_id": .object([
                        "type": .string("string"),
                        "description": .string("Secondary subcategory one ID")
                    ]),
                    "secondary_subcategory_two_id": .object([
                        "type": .string("string"),
                        "description": .string("Secondary subcategory two ID")
                    ])
                ]),
                "required": .array([.string("info_id")])
            ])
        )
    }

    /// Creates tool definition for listing app info localizations
    func listAppInfoLocalizationsTool() -> Tool {
        return Tool(
            name: "app_info_list_localizations",
            description: "List app info localizations (subtitle, privacy URL, privacy text for each locale)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "info_id": .object([
                        "type": .string("string"),
                        "description": .string("App info ID")
                    ])
                ]),
                "required": .array([.string("info_id")])
            ])
        )
    }

    /// Creates tool definition for updating app info localization
    func updateAppInfoLocalizationTool() -> Tool {
        return Tool(
            name: "app_info_update_localization",
            description: "Update app info localization (name, subtitle, privacy policy URL/text)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App info localization ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("App name for this locale")
                    ]),
                    "subtitle": .object([
                        "type": .string("string"),
                        "description": .string("App subtitle for this locale (max 30 characters)")
                    ]),
                    "privacy_policy_url": .object([
                        "type": .string("string"),
                        "description": .string("Privacy policy URL")
                    ]),
                    "privacy_choices_url": .object([
                        "type": .string("string"),
                        "description": .string("Privacy choices URL")
                    ]),
                    "privacy_policy_text": .object([
                        "type": .string("string"),
                        "description": .string("Privacy policy text (for China mainland)")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    /// Creates tool definition for creating app info localization
    func createAppInfoLocalizationTool() -> Tool {
        return Tool(
            name: "app_info_create_localization",
            description: "Create app info localization for a new locale (subtitle, privacy policy URL/text)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "info_id": .object([
                        "type": .string("string"),
                        "description": .string("App info ID to create localization for")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g., en-US, ru, de-DE)")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("App name for this locale")
                    ]),
                    "subtitle": .object([
                        "type": .string("string"),
                        "description": .string("App subtitle for this locale (max 30 characters)")
                    ]),
                    "privacy_policy_url": .object([
                        "type": .string("string"),
                        "description": .string("Privacy policy URL")
                    ]),
                    "privacy_choices_url": .object([
                        "type": .string("string"),
                        "description": .string("Privacy choices URL")
                    ]),
                    "privacy_policy_text": .object([
                        "type": .string("string"),
                        "description": .string("Privacy policy text (for China mainland)")
                    ])
                ]),
                "required": .array([.string("info_id"), .string("locale")])
            ])
        )
    }
}
