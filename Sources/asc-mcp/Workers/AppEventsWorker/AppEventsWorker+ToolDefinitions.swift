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
                    "include": .object([
                        "type": .string("string"),
                        "description": .string("Comma-separated related resources to include (e.g. 'localizations')")
                    ])
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
                    "badge": .object([
                        "type": .string("string"),
                        "description": .string("Event badge: LIVE_EVENT, PREMIERE, CHALLENGE, COMPETITION, NEW_SEASON, MAJOR_UPDATE, SPECIAL_EVENT")
                    ]),
                    "deep_link": .object([
                        "type": .string("string"),
                        "description": .string("Deep link URL to open the event in the app")
                    ]),
                    "purchase_requirement": .object([
                        "type": .string("string"),
                        "description": .string("Purchase requirement: NO_COST_ASSOCIATED, IN_APP_PURCHASE, SUBSCRIPTION, IN_APP_PURCHASE_AND_SUBSCRIPTION, IN_APP_PURCHASE_OR_SUBSCRIPTION")
                    ]),
                    "purpose": .object([
                        "type": .string("string"),
                        "description": .string("Event purpose: APPROPRIATE_FOR_ALL_USERS, ATTRACT_NEW_USERS, KEEP_ACTIVE_USERS_INFORMED, BRING_BACK_LAPSED_USERS")
                    ]),
                    "territory_schedules": .object([
                        "type": .string("string"),
                        "description": .string("JSON array of territory schedules: [{\"territories\":[\"USA\"],\"publishStart\":\"2025-01-01T00:00:00Z\",\"eventStart\":\"2025-01-01T00:00:00Z\",\"eventEnd\":\"2025-01-07T00:00:00Z\"}]")
                    ])
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
                        "type": .string("string"),
                        "description": .string("New reference name")
                    ]),
                    "badge": .object([
                        "type": .string("string"),
                        "description": .string("Event badge: LIVE_EVENT, PREMIERE, CHALLENGE, COMPETITION, NEW_SEASON, MAJOR_UPDATE, SPECIAL_EVENT")
                    ]),
                    "deep_link": .object([
                        "type": .string("string"),
                        "description": .string("Deep link URL to open the event in the app")
                    ]),
                    "purchase_requirement": .object([
                        "type": .string("string"),
                        "description": .string("Purchase requirement: NO_COST_ASSOCIATED, IN_APP_PURCHASE, SUBSCRIPTION, IN_APP_PURCHASE_AND_SUBSCRIPTION, IN_APP_PURCHASE_OR_SUBSCRIPTION")
                    ]),
                    "purpose": .object([
                        "type": .string("string"),
                        "description": .string("Event purpose: APPROPRIATE_FOR_ALL_USERS, ATTRACT_NEW_USERS, KEEP_ACTIVE_USERS_INFORMED, BRING_BACK_LAPSED_USERS")
                    ]),
                    "territory_schedules": .object([
                        "type": .string("string"),
                        "description": .string("JSON array of territory schedules: [{\"territories\":[\"USA\"],\"publishStart\":\"2025-01-01T00:00:00Z\",\"eventStart\":\"2025-01-01T00:00:00Z\",\"eventEnd\":\"2025-01-07T00:00:00Z\"}]")
                    ])
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
                        "type": .string("string"),
                        "description": .string("Localized event name (max 30 characters)")
                    ]),
                    "short_description": .object([
                        "type": .string("string"),
                        "description": .string("Localized short description (max 120 characters)")
                    ]),
                    "long_description": .object([
                        "type": .string("string"),
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
                        "type": .string("string"),
                        "description": .string("Localized event name (max 30 characters)")
                    ]),
                    "short_description": .object([
                        "type": .string("string"),
                        "description": .string("Localized short description (max 120 characters)")
                    ]),
                    "long_description": .object([
                        "type": .string("string"),
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
}
