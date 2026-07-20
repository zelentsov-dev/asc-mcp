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
                    ]),
                    "include": stringOrArrayEnumSchema(
                        "Related resources to include",
                        values: appInfoIncludeValues
                    ),
                    "limit": boundedIntegerSchema("Max results (default: 25, max: 200)", maximum: 200),
                    "localizations_limit": boundedIntegerSchema(
                        "Max included app info localizations (max: 50)",
                        maximum: 50
                    ),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
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
                    "include": stringOrArrayEnumSchema(
                        "Related resources to include",
                        values: appInfoIncludeValues
                    ),
                    "localizations_limit": boundedIntegerSchema(
                        "Max included app info localizations (max: 50)",
                        maximum: 50
                    )
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
                    ]),
                    "locale": stringOrArraySchema("Filter by one or more locale codes"),
                    "include": stringOrArrayEnumSchema(
                        "Related resources to include",
                        values: ["appInfo"]
                    ),
                    "limit": boundedIntegerSchema("Max results (default: 25, max: 200)", maximum: 200),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
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
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("App name for this locale")
                    ]),
                    "subtitle": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("App subtitle for this locale (max 30 characters)")
                    ]),
                    "privacy_policy_url": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Privacy policy URL")
                    ]),
                    "privacy_choices_url": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Privacy choices URL")
                    ]),
                    "privacy_policy_text": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Privacy policy text (for China mainland)")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    /// Creates tool definition for deleting app info localization
    func deleteAppInfoLocalizationTool() -> Tool {
        return Tool(
            name: "app_info_delete_localization",
            description: "Delete an app info localization for a specific locale",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App info localization ID to delete")
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
                        "description": .string("Locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans)")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("App name for this locale")
                    ]),
                    "subtitle": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("App subtitle for this locale (max 30 characters)")
                    ]),
                    "privacy_policy_url": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Privacy policy URL")
                    ]),
                    "privacy_choices_url": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Privacy choices URL")
                    ]),
                    "privacy_policy_text": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Privacy policy text (for China mainland)")
                    ])
                ]),
                "required": .array([.string("info_id"), .string("locale"), .string("name")])
            ])
        )
    }

    /// Creates tool definition for getting EULA
    func getEulaTool() -> Tool {
        return Tool(
            name: "app_info_get_eula",
            description: "Get the current End User License Agreement (EULA) for an app",
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

    /// Creates tool definition for creating EULA
    func createEulaTool() -> Tool {
        return Tool(
            name: "app_info_create_eula",
            description: "Create an End User License Agreement (EULA) for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "agreement_text": .object([
                        "type": .string("string"),
                        "description": .string("EULA agreement text")
                    ]),
                    "territory_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of territory IDs where EULA applies (e.g. [\"USA\", \"GBR\", \"RUS\"])"),
                        "items": .object([
                            "type": .string("string")
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ])
                ]),
                "required": .array([.string("app_id"), .string("agreement_text"), .string("territory_ids")])
            ])
        )
    }

    /// Creates tool definition for updating EULA
    func updateEulaTool() -> Tool {
        return Tool(
            name: "app_info_update_eula",
            description: "Update an existing End User License Agreement (EULA)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "eula_id": .object([
                        "type": .string("string"),
                        "description": .string("EULA resource ID")
                    ]),
                    "agreement_text": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Updated EULA agreement text")
                    ]),
                    "territory_ids": .object([
                        "type": .string("array"),
                        "description": .string("Replacement territory IDs where the EULA applies; pass an empty array to clear the relationship"),
                        "items": .object(["type": .string("string")]),
                        "uniqueItems": .bool(true)
                    ])
                ]),
                "required": .array([.string("eula_id")])
            ])
        )
    }

    private var appInfoIncludeValues: [String] {
        [
            "app",
            "ageRatingDeclaration",
            "appInfoLocalizations",
            "primaryCategory",
            "primarySubcategoryOne",
            "primarySubcategoryTwo",
            "secondaryCategory",
            "secondarySubcategoryOne",
            "secondarySubcategoryTwo"
        ]
    }

    private func boundedIntegerSchema(_ description: String, maximum: Int) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(1),
            "maximum": .int(maximum)
        ])
    }

    private func stringOrArraySchema(_ description: String) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("string")]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func stringOrArrayEnumSchema(_ description: String, values: [String]) -> Value {
        let enumValues = Value.array(values.map(Value.string))
        return .object([
            "description": .string(description),
            "oneOf": .array([
                .object([
                    "type": .string("string")
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": enumValues
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }
}
