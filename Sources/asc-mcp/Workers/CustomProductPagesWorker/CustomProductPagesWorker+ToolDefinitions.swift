import Foundation
import MCP

// MARK: - Tool Definitions
extension CustomProductPagesWorker {

    func listCustomPagesTool() -> Tool {
        return Tool(
            name: "custom_pages_list",
            description: "List custom product pages for an app. Custom product pages allow creating alternative App Store listings for different audiences.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "visible": booleanListSchema("Filter by one or more visibility values"),
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

    func getCustomPageTool() -> Tool {
        return Tool(
            name: "custom_pages_get",
            description: "Get details of a specific custom product page",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "page_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page ID")
                    ])
                ]),
                "required": .array([.string("page_id")])
            ])
        )
    }

    func createCustomPageTool() -> Tool {
        return Tool(
            name: "custom_pages_create",
            description: "Create a new custom product page for an app with initial version and localization",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page name (internal reference)")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Initial locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans)")
                    ]),
                    "promotional_text": .object([
                        "type": .string("string"),
                        "description": .string("Promotional text for the initial localization (optional)")
                    ]),
                    "template_version_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store version ID to use as template (optional)")
                    ]),
                    "template_page_id": .object([
                        "type": .string("string"),
                        "description": .string("Existing custom product page ID to use as template (optional)")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("name"), .string("locale")])
            ])
        )
    }

    func updateCustomPageTool() -> Tool {
        return Tool(
            name: "custom_pages_update",
            description: "Update a custom product page",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "page_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("New name for the custom product page")
                    ]),
                    "visible": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the custom product page is visible")
                    ])
                ]),
                "required": .array([.string("page_id")])
            ])
        )
    }

    func deleteCustomPageTool() -> Tool {
        return Tool(
            name: "custom_pages_delete",
            description: "Delete a custom product page",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "page_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page ID to delete")
                    ])
                ]),
                "required": .array([.string("page_id")])
            ])
        )
    }

    func listVersionsTool() -> Tool {
        return Tool(
            name: "custom_pages_list_versions",
            description: "List versions for a custom product page",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "page_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page ID")
                    ]),
                    "state": enumListSchema(
                        "Filter by one or more custom product page version states",
                        values: [
                            "PREPARE_FOR_SUBMISSION",
                            "READY_FOR_REVIEW",
                            "WAITING_FOR_REVIEW",
                            "IN_REVIEW",
                            "ACCEPTED",
                            "APPROVED",
                            "REPLACED_WITH_NEW_VERSION",
                            "REJECTED"
                        ]
                    ),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("page_id")])
            ])
        )
    }

    func createVersionTool() -> Tool {
        return Tool(
            name: "custom_pages_create_version",
            description: "Create a new version for a custom product page",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "page_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page ID")
                    ]),
                    "deep_link": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "format": .string("uri"),
                        "description": .string("Absolute deep-link URI for the version; null explicitly creates it without a deep link")
                    ])
                ]),
                "required": .array([.string("page_id")])
            ])
        )
    }

    func listLocalizationsTool() -> Tool {
        return Tool(
            name: "custom_pages_list_localizations",
            description: "List localizations for a custom product page version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page version ID")
                    ]),
                    "locale": stringListSchema("Filter by one or more locale codes"),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
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

    func createLocalizationTool() -> Tool {
        return Tool(
            name: "custom_pages_create_localization",
            description: "Create a localization for a custom product page version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page version ID")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans)")
                    ]),
                    "promotional_text": .object([
                        "type": .string("string"),
                        "description": .string("Promotional text for the locale")
                    ])
                ]),
                "required": .array([.string("version_id"), .string("locale")])
            ])
        )
    }

    func updateLocalizationTool() -> Tool {
        return Tool(
            name: "custom_pages_update_localization",
            description: "Update a localization for a custom product page",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page localization ID")
                    ]),
                    "promotional_text": .object([
                        "type": .string("string"),
                        "description": .string("New promotional text")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    private func stringListSchema(_ description: String) -> Value {
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

    private func enumListSchema(_ description: String, values: [String]) -> Value {
        let enumValues = Value.array(values.map(Value.string))
        return .object([
            "description": .string(description),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": enumValues
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

    private func booleanListSchema(_ description: String) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("boolean")]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("boolean")]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }
}
