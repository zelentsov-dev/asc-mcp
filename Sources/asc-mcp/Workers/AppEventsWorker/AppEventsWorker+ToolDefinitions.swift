import Foundation
import MCP

// MARK: - Tool Definitions
extension AppEventsWorker {

    func listAppEventsTool() -> Tool {
        return Tool(
            name: "app_events_list",
            description: "List in-app events for an app. Returns event names, badges, states, and schedules",
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
                    "event_states": stringOrArrayEnumSchema(
                        "Filter by one or more event states",
                        values: appEventStates
                    ),
                    "event_ids": stringOrArraySchema("Filter by one or more app event IDs"),
                    "include": stringOrArrayEnumSchema(
                        "Related resources to include",
                        values: ["localizations"]
                    ),
                    "localizations_limit": boundedIntegerSchema(
                        "Max included localizations (max: 50)",
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

    func getAppEventTool() -> Tool {
        return Tool(
            name: "app_events_get",
            description: "Get details of a specific in-app event, optionally including localizations",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "event_id": .object([
                        "type": .string("string"),
                        "description": .string("App event ID")
                    ]),
                    "include": stringOrArrayEnumSchema(
                        "Related resources to include",
                        values: ["localizations"]
                    ),
                    "localizations_limit": boundedIntegerSchema(
                        "Max included localizations (max: 50)",
                        maximum: 50
                    )
                ]),
                "required": .array([.string("event_id")])
            ])
        )
    }

    func createAppEventTool() -> Tool {
        return Tool(
            name: "app_events_create",
            description: "Create a new in-app event for App Store featuring",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "reference_name": .object([
                        "type": .string("string"),
                        "description": .string("Internal reference name for the event")
                    ]),
                    "badge": nullableEnumSchema("Event badge", values: appEventBadges),
                    "deep_link": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "format": .string("uri"),
                        "description": .string("Absolute deep-link URI to open the event in the app; null clears it")
                    ]),
                    "purchase_requirement": nullableEnumSchema(
                        "Purchase requirement",
                        values: purchaseRequirements
                    ),
                    "primary_locale": nullableStringSchema("Primary locale code for the event"),
                    "priority": nullableEnumSchema("Event priority", values: ["HIGH", "NORMAL"]),
                    "purpose": nullableEnumSchema("Event purpose", values: appEventPurposes),
                    "territory_schedules": territorySchedulesSchema()
                ]),
                "required": .array([.string("app_id"), .string("reference_name")])
            ])
        )
    }

    func updateAppEventTool() -> Tool {
        return Tool(
            name: "app_events_update",
            description: "Update an existing in-app event including territory schedules",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "event_id": .object([
                        "type": .string("string"),
                        "description": .string("App event ID")
                    ]),
                    "reference_name": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("New reference name")
                    ]),
                    "badge": nullableEnumSchema("Event badge", values: appEventBadges),
                    "deep_link": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "format": .string("uri"),
                        "description": .string("Absolute deep-link URI to open the event in the app; null clears it")
                    ]),
                    "purchase_requirement": nullableEnumSchema(
                        "Purchase requirement",
                        values: purchaseRequirements
                    ),
                    "primary_locale": nullableStringSchema("Primary locale code for the event"),
                    "priority": nullableEnumSchema("Event priority", values: ["HIGH", "NORMAL"]),
                    "purpose": nullableEnumSchema("Event purpose", values: appEventPurposes),
                    "territory_schedules": territorySchedulesSchema()
                ]),
                "required": .array([.string("event_id")])
            ])
        )
    }

    func deleteAppEventTool() -> Tool {
        return Tool(
            name: "app_events_delete",
            description: "Delete an in-app event",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "event_id": .object([
                        "type": .string("string"),
                        "description": .string("App event ID to delete")
                    ])
                ]),
                "required": .array([.string("event_id")])
            ])
        )
    }

    func listAppEventLocalizationsTool() -> Tool {
        return Tool(
            name: "app_events_list_localizations",
            description: "List localizations for an in-app event. Returns locale, name, short/long descriptions",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "event_id": .object([
                        "type": .string("string"),
                        "description": .string("App event ID")
                    ]),
                    "include": stringOrArrayEnumSchema(
                        "Related resources to include",
                        values: ["appEvent", "appEventScreenshots", "appEventVideoClips"]
                    ),
                    "limit": boundedIntegerSchema("Max results (default: 25, max: 200)", maximum: 200),
                    "screenshots_limit": boundedIntegerSchema(
                        "Max included screenshots (max: 50)",
                        maximum: 50
                    ),
                    "video_clips_limit": boundedIntegerSchema(
                        "Max included video clips (max: 50)",
                        maximum: 50
                    ),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([.string("event_id")])
            ])
        )
    }

    /// Creates tool definition for creating an app event localization
    func createAppEventLocalizationTool() -> Tool {
        return Tool(
            name: "app_events_create_localization",
            description: "Create a localization for an in-app event. Sets name, short and long descriptions for a specific locale.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "event_id": .object([
                        "type": .string("string"),
                        "description": .string("App event ID")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans)")
                    ]),
                    "name": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Localized event name (max 30 characters)")
                    ]),
                    "short_description": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Localized short description (max 120 characters)")
                    ]),
                    "long_description": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Localized long description (max 500 characters)")
                    ])
                ]),
                "required": .array([.string("event_id"), .string("locale")])
            ])
        )
    }

    /// Creates tool definition for updating an app event localization
    func updateAppEventLocalizationTool() -> Tool {
        return Tool(
            name: "app_events_update_localization",
            description: "Update a localization for an in-app event. Modify name, short and/or long descriptions.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App event localization ID")
                    ]),
                    "name": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Localized event name (max 30 characters)")
                    ]),
                    "short_description": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Localized short description (max 120 characters)")
                    ]),
                    "long_description": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Localized long description (max 500 characters)")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    /// Creates tool definition for deleting an app event localization
    func deleteAppEventLocalizationTool() -> Tool {
        return Tool(
            name: "app_events_delete_localization",
            description: "Delete a localization for an in-app event",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App event localization ID to delete")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    private var appEventStates: [String] {
        [
            "DRAFT",
            "READY_FOR_REVIEW",
            "WAITING_FOR_REVIEW",
            "IN_REVIEW",
            "REJECTED",
            "ACCEPTED",
            "APPROVED",
            "PUBLISHED",
            "PAST",
            "ARCHIVED"
        ]
    }

    private var appEventBadges: [String] {
        ["LIVE_EVENT", "PREMIERE", "CHALLENGE", "COMPETITION", "NEW_SEASON", "MAJOR_UPDATE", "SPECIAL_EVENT"]
    }

    private var appEventPurposes: [String] {
        ["APPROPRIATE_FOR_ALL_USERS", "ATTRACT_NEW_USERS", "KEEP_ACTIVE_USERS_INFORMED", "BRING_BACK_LAPSED_USERS"]
    }

    private var purchaseRequirements: [String] {
        ["NO_COST_ASSOCIATED", "IN_APP_PURCHASE"]
    }

    private func boundedIntegerSchema(_ description: String, maximum: Int) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(1),
            "maximum": .int(maximum)
        ])
    }

    private func nullableStringSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "description": .string(description)
        ])
    }

    private func nullableEnumSchema(_ description: String, values: [String]) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "description": .string(description),
            "enum": .array(values.map(Value.string) + [.null])
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
            "description": .string(description + ": " + values.joined(separator: ", ")),
            "oneOf": .array([
                .object(["type": .string("string")]),
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

    private func territorySchedulesSchema() -> Value {
        let schedule = Value.object([
            "type": .string("object"),
            "properties": .object([
                "territories": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "publishStart": .object(["type": .string("string"), "format": .string("date-time")]),
                "eventStart": .object(["type": .string("string"), "format": .string("date-time")]),
                "eventEnd": .object(["type": .string("string"), "format": .string("date-time")])
            ]),
            "additionalProperties": .bool(false)
        ])
        return .object([
            "description": .string("Territory schedule array. A JSON-encoded array string remains accepted for backward compatibility."),
            "oneOf": .array([
                .object([
                    "type": .string("array"),
                    "items": schedule
                ]),
                .object(["type": .string("string")]),
                .object(["type": .string("null")])
            ])
        ])
    }
}
