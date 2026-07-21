import Foundation
import MCP

// MARK: - Tool Definitions
extension CustomProductPagesWorker {
    func listCustomPagesTool() -> Tool {
        Tool(
            name: "custom_pages_list",
            description: "List custom product pages for an app with exact visibility filters and scoped pagination",
            inputSchema: objectSchema(
                properties: [
                    "app_id": identifierSchema("App Store Connect app ID"),
                    "visible": booleanListSchema("Filter by one or more visibility values"),
                    "limit": limitSchema(),
                    "next_url": continuationSchema()
                ],
                required: ["app_id"]
            )
        )
    }

    func getCustomPageTool() -> Tool {
        Tool(
            name: "custom_pages_get",
            description: "Get one custom product page by its canonical App Store Connect ID",
            inputSchema: objectSchema(
                properties: ["page_id": identifierSchema("Custom product page ID")],
                required: ["page_id"]
            )
        )
    }

    func createCustomPageTool() -> Tool {
        Tool(
            name: "custom_pages_create",
            description: "Create a custom product page with its initial version and localization; ambiguous writes are never replayed",
            inputSchema: objectSchema(
                properties: [
                    "app_id": identifierSchema("App Store Connect app ID"),
                    "name": stringSchema("Internal custom product page name", minimumLength: 1),
                    "locale": stringSchema("Initial locale code", minimumLength: 1),
                    "promotional_text": nullableStringSchema("Initial promotional text; null is forwarded explicitly"),
                    "template_version_id": identifierSchema("Optional App Store version template ID"),
                    "template_page_id": identifierSchema("Optional custom product page template ID")
                ],
                required: ["app_id", "name", "locale"]
            )
        )
    }

    func updateCustomPageTool() -> Tool {
        Tool(
            name: "custom_pages_update",
            description: "Update a custom product page name and/or visibility while preserving omitted values and forwarding explicit null",
            inputSchema: objectSchema(
                properties: [
                    "page_id": identifierSchema("Custom product page ID"),
                    "name": nullableStringSchema("Replacement name, or null to clear Apple's nullable field"),
                    "visible": nullableBooleanSchema("Replacement visibility, or null to clear Apple's nullable field")
                ],
                required: ["page_id"],
                minimumProperties: 2,
                anyRequired: ["name", "visible"]
            )
        )
    }

    func deleteCustomPageTool() -> Tool {
        Tool(
            name: "custom_pages_delete",
            description: "Delete a custom product page after exact page-ID confirmation",
            inputSchema: objectSchema(
                properties: [
                    "page_id": identifierSchema("Custom product page ID"),
                    "confirm_page_id": identifierSchema("Exact page ID required to confirm irreversible deletion")
                ],
                required: ["page_id", "confirm_page_id"]
            )
        )
    }

    func listVersionsTool() -> Tool {
        Tool(
            name: "custom_pages_list_versions",
            description: "List versions owned by one custom product page with state filters and scoped pagination",
            inputSchema: objectSchema(
                properties: [
                    "page_id": identifierSchema("Custom product page ID"),
                    "state": enumListSchema(
                        "Filter by one or more custom product page version states",
                        values: Self.versionStates
                    ),
                    "limit": limitSchema(),
                    "next_url": continuationSchema()
                ],
                required: ["page_id"]
            )
        )
    }

    func getVersionTool() -> Tool {
        Tool(
            name: "custom_pages_get_version",
            description: "Get one custom product page version by its canonical ID",
            inputSchema: objectSchema(
                properties: ["version_id": identifierSchema("Custom product page version ID")],
                required: ["version_id"]
            )
        )
    }

    func createVersionTool() -> Tool {
        Tool(
            name: "custom_pages_create_version",
            description: "Create a version owned by one custom product page; deep_link may be omitted, set, or explicitly null",
            inputSchema: objectSchema(
                properties: [
                    "page_id": identifierSchema("Custom product page ID"),
                    "deep_link": nullableURISchema("Absolute deep-link URI, or null to create the version without one")
                ],
                required: ["page_id"]
            )
        )
    }

    func updateVersionTool() -> Tool {
        Tool(
            name: "custom_pages_update_version",
            description: "Replace or explicitly clear a custom product page version deep link",
            inputSchema: objectSchema(
                properties: [
                    "version_id": identifierSchema("Custom product page version ID"),
                    "deep_link": nullableURISchema("Absolute replacement URI, or null to clear the deep link")
                ],
                required: ["version_id", "deep_link"]
            )
        )
    }

    func listLocalizationsTool() -> Tool {
        Tool(
            name: "custom_pages_list_localizations",
            description: "List localizations owned by one custom product page version with scoped pagination",
            inputSchema: objectSchema(
                properties: [
                    "version_id": identifierSchema("Custom product page version ID"),
                    "locale": stringListSchema("Filter by one or more locale codes"),
                    "limit": limitSchema(),
                    "next_url": continuationSchema()
                ],
                required: ["version_id"]
            )
        )
    }

    func getLocalizationTool() -> Tool {
        Tool(
            name: "custom_pages_get_localization",
            description: "Get one custom product page localization by its canonical ID",
            inputSchema: objectSchema(
                properties: ["localization_id": identifierSchema("Custom product page localization ID")],
                required: ["localization_id"]
            )
        )
    }

    func createLocalizationTool() -> Tool {
        Tool(
            name: "custom_pages_create_localization",
            description: "Create a localization owned by one custom product page version",
            inputSchema: objectSchema(
                properties: [
                    "version_id": identifierSchema("Custom product page version ID"),
                    "locale": stringSchema("Locale code", minimumLength: 1),
                    "promotional_text": nullableStringSchema("Promotional text; null is forwarded explicitly")
                ],
                required: ["version_id", "locale"]
            )
        )
    }

    func updateLocalizationTool() -> Tool {
        Tool(
            name: "custom_pages_update_localization",
            description: "Replace or explicitly clear a custom product page localization's promotional text",
            inputSchema: objectSchema(
                properties: [
                    "localization_id": identifierSchema("Custom product page localization ID"),
                    "promotional_text": nullableStringSchema("Replacement promotional text, or null to clear it")
                ],
                required: ["localization_id", "promotional_text"]
            )
        )
    }

    func deleteLocalizationTool() -> Tool {
        Tool(
            name: "custom_pages_delete_localization",
            description: "Delete a custom product page localization after exact localization-ID confirmation",
            inputSchema: objectSchema(
                properties: [
                    "localization_id": identifierSchema("Custom product page localization ID"),
                    "confirm_localization_id": identifierSchema("Exact localization ID required to confirm irreversible deletion")
                ],
                required: ["localization_id", "confirm_localization_id"]
            )
        )
    }

    func listSearchKeywordsTool() -> Tool {
        Tool(
            name: "custom_pages_list_search_keywords",
            description: "List search keyword IDs attached to one custom product page localization",
            inputSchema: objectSchema(
                properties: [
                    "localization_id": identifierSchema("Custom product page localization ID"),
                    "platform": stringListSchema("Filter by one or more Apple platform values"),
                    "locale": stringListSchema("Filter by one or more locale codes"),
                    "limit": limitSchema(),
                    "next_url": continuationSchema()
                ],
                required: ["localization_id"]
            )
        )
    }

    func addSearchKeywordsTool() -> Tool {
        Tool(
            name: "custom_pages_add_search_keywords",
            description: "Attach existing app search keyword IDs to one custom product page localization",
            inputSchema: objectSchema(
                properties: [
                    "localization_id": identifierSchema("Custom product page localization ID"),
                    "keyword_ids": identifierListSchema("One or more app search keyword IDs to attach")
                ],
                required: ["localization_id", "keyword_ids"]
            )
        )
    }

    func removeSearchKeywordsTool() -> Tool {
        Tool(
            name: "custom_pages_remove_search_keywords",
            description: "Detach existing app search keyword IDs after exact localization-ID confirmation",
            inputSchema: objectSchema(
                properties: [
                    "localization_id": identifierSchema("Custom product page localization ID"),
                    "keyword_ids": identifierListSchema("One or more attached app search keyword IDs to detach"),
                    "confirm_localization_id": identifierSchema(
                        "Exact localization ID required to confirm the destructive relationship removal"
                    )
                ],
                required: ["localization_id", "keyword_ids", "confirm_localization_id"]
            )
        )
    }

    private static let versionStates: [String] = [
        "PREPARE_FOR_SUBMISSION",
        "READY_FOR_REVIEW",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "ACCEPTED",
        "APPROVED",
        "REPLACED_WITH_NEW_VERSION",
        "REJECTED"
    ]

    private func objectSchema(
        properties: [String: Value],
        required: [String] = [],
        minimumProperties: Int? = nil,
        anyRequired: [String] = []
    ) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        if let minimumProperties {
            schema["minProperties"] = .int(minimumProperties)
        }
        if !anyRequired.isEmpty {
            schema["anyOf"] = .array(anyRequired.map { field in
                .object(["required": .array([.string(field)])])
            })
        }
        return .object(schema)
    }

    private func identifierSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
        ])
    }

    private func identifierListSchema(_ description: String) -> Value {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": identifierSchema("Canonical App Store Connect resource ID"),
            "minItems": .int(1),
            "uniqueItems": .bool(true)
        ])
    }

    private func stringSchema(_ description: String, minimumLength: Int? = nil) -> Value {
        var schema: [String: Value] = [
            "type": .string("string"),
            "description": .string(description)
        ]
        if let minimumLength { schema["minLength"] = .int(minimumLength) }
        return .object(schema)
    }

    private func nullableStringSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "description": .string(description)
        ])
    }

    private func nullableBooleanSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("boolean"), .string("null")]),
            "description": .string(description)
        ])
    }

    private func nullableURISchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "format": .string("uri"),
            "description": .string(description)
        ])
    }

    private func limitSchema() -> Value {
        .object([
            "type": .string("integer"),
            "description": .string("Maximum resources per page"),
            "minimum": .int(1),
            "maximum": .int(200),
            "default": .int(25)
        ])
    }

    private func continuationSchema() -> Value {
        .object([
            "type": .string("string"),
            "format": .string("uri-reference"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!.*[\s\u0000-\u001F\u007F]).+$"#),
            "description": .string("Apple continuation URL from the previous response; origin, path, query invariants, and cursor are validated")
        ])
    }

    private func stringListSchema(_ description: String) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("string"), "minLength": .int(1)]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string"), "minLength": .int(1)]),
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
                .object(["type": .string("string"), "enum": enumValues]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string"), "enum": enumValues]),
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
