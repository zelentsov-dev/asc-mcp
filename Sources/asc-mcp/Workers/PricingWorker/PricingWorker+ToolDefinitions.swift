//
//  PricingWorker+ToolDefinitions.swift
//  asc-mcp
//
//  Tool definitions for pricing, territories, and availability operations
//

import Foundation
import MCP

// MARK: - Tool Definitions
extension PricingWorker {

    /// Tool definition for listing all available territories
    func listTerritoriesToolDef() -> Tool {
        return Tool(
            name: "pricing_list_territories",
            description: "List all available App Store territories with currency info",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 200, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    /// Tool definition for getting app territory availability
    func getAppAvailabilityTool() -> Tool {
        return Tool(
            name: "pricing_get_availability",
            description: "Get app availability configuration and optionally include its per-territory availability resources",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "include_territory_availabilities": .object([
                        "type": .string("boolean"),
                        "description": .string("Include territory availability resources in the response (default: false)")
                    ]),
                    "territory_availabilities_limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum included territory availability resources (default: 50, max: 50). Supplying this parameter enables the include."),
                        "minimum": .int(1),
                        "maximum": .int(50)
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    /// Tool definition for listing app price points
    func listPricePointsTool() -> Tool {
        return Tool(
            name: "pricing_list_price_points",
            description: "List available price points for an app, optionally filtered by territory. Returns customer price and proceeds per territory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "territory_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by ISO 3166-1 alpha-3 territory code (e.g. USA, RUS, DEU, JPN, GBR). Get codes from pricing_list_territories.")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 50, max: 200)")
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

    /// Tool definition for getting current price schedule
    func getAppPriceScheduleTool() -> Tool {
        return Tool(
            name: "pricing_get_price_schedule",
            description: "Get current price schedule for an app including manual and automatic prices, and base territory",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "manual_prices_limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum included manual prices (default: 50, max: 50). Completeness metadata and the related collection URL are returned."),
                        "minimum": .int(1),
                        "maximum": .int(50)
                    ]),
                    "automatic_prices_limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum included automatic prices (default: 50, max: 50). Completeness metadata and the related collection URL are returned."),
                        "minimum": .int(1),
                        "maximum": .int(50)
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    /// Tool definition for setting app price schedule
    func setAppPriceScheduleTool() -> Tool {
        return Tool(
            name: "pricing_set_price_schedule",
            description: "Submit an app price schedule with one legacy price point or multiple dated manual prices. This Apple endpoint updates the app's schedule, so include every manual price change that should remain scheduled.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "base_territory_id": .object([
                        "type": .string("string"),
                        "description": .string("Base ISO 3166-1 alpha-3 territory code (e.g. USA). Get codes from pricing_list_territories.")
                    ]),
                    "price_point_id": .object([
                        "type": .string("string"),
                        "description": .string("Legacy single price point resource ID from pricing_list_price_points. Mutually exclusive with manual_prices.")
                    ]),
                    "start_date": nullablePriceDateSchema("Legacy price start date in YYYY-MM-DD format; null or omission means no lower boundary"),
                    "end_date": nullablePriceDateSchema("Legacy price end date in YYYY-MM-DD format; null or omission means no upper boundary"),
                    "manual_prices": .object([
                        "type": .string("array"),
                        "description": .string("Complete manual price schedule. Each entry links an app price point and optional date boundaries. Mutually exclusive with price_point_id."),
                        "minItems": .int(1),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "price_point_id": .object([
                                    "type": .string("string"),
                                    "description": .string("Price point resource ID from pricing_list_price_points")
                                ]),
                                "start_date": nullablePriceDateSchema("Start date in YYYY-MM-DD format; null or omission means no lower boundary"),
                                "end_date": nullablePriceDateSchema("End date in YYYY-MM-DD format; null or omission means no upper boundary")
                            ]),
                            "required": .array([.string("price_point_id")]),
                            "additionalProperties": .bool(false)
                        ])
                    ])
                ]),
                "required": .array([.string("app_id"), .string("base_territory_id")]),
                "oneOf": .array([
                    .object(["required": .array([.string("price_point_id")])]),
                    .object(["required": .array([.string("manual_prices")])])
                ])
            ])
        )
    }

    /// Tool definition for listing territory availability
    func listTerritoryAvailabilityTool() -> Tool {
        return Tool(
            name: "pricing_list_territory_availability",
            description: "List per-territory availability for an app (availability, release date, pre-order state, and pre-order publish date)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 50, max: 200)")
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

    // MARK: - App Availability v2 Tools

    /// Tool definition for creating app availability via v2 endpoint
    func createAvailabilityV2Tool() -> Tool {
        return Tool(
            name: "pricing_create_availability",
            description: "Create App Store Connect v2 app availability for an app pre-order. Link existing territory availability resources, create inline territory settings, or combine both.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "available_in_new_territories": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app should automatically be available in new territories")
                    ]),
                    "territory_ids": .object([
                        "type": .string("array"),
                        "description": .string("Non-empty array of unique territoryAvailabilities resource IDs. These are relationship IDs, not ISO territory codes."),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "territory_availabilities": .object([
                        "type": .string("array"),
                        "description": .string("Inline territory availability resources to create. Use ISO 3166-1 alpha-3 territory IDs from pricing_list_territories."),
                        "minItems": .int(1),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "territory_id": .object([
                                    "type": .string("string"),
                                    "description": .string("ISO 3166-1 alpha-3 territory resource ID, such as USA")
                                ]),
                                "available": nullablePricingBooleanSchema("Whether the app is available in this territory; null or omission encodes no value"),
                                "release_date": nullablePriceDateSchema("Release date in YYYY-MM-DD format; null or omission encodes no value"),
                                "pre_order_enabled": nullablePricingBooleanSchema("Whether pre-order is enabled in this territory; null or omission encodes no value")
                            ]),
                            "required": .array([.string("territory_id")]),
                            "additionalProperties": .bool(false)
                        ])
                    ])
                ]),
                "required": .array([.string("app_id"), .string("available_in_new_territories")]),
                "anyOf": .array([
                    .object(["required": .array([.string("territory_ids")])]),
                    .object(["required": .array([.string("territory_availabilities")])])
                ])
            ])
        )
    }

    /// Tool definition for getting app availability by ID via v2 endpoint
    func getAvailabilityV2Tool() -> Tool {
        return Tool(
            name: "pricing_get_availability_v2",
            description: "Get app availability by availability ID (v2 endpoint). Use pricing_get_availability with app_id or this with availability_id.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "availability_id": .object([
                        "type": .string("string"),
                        "description": .string("App availability resource ID")
                    ]),
                    "include_territory_availabilities": .object([
                        "type": .string("boolean"),
                        "description": .string("Include territory availability resources in the response (default: false)")
                    ]),
                    "territory_availabilities_limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum included territory availability resources (default: 50, max: 50). Supplying this parameter enables the include."),
                        "minimum": .int(1),
                        "maximum": .int(50)
                    ])
                ]),
                "required": .array([.string("availability_id")])
            ])
        )
    }

    /// Tool definition for listing territory availabilities via v2 endpoint
    func listTerritoryAvailabilitiesV2Tool() -> Tool {
        return Tool(
            name: "pricing_list_territory_availabilities",
            description: "List territory availabilities for an app availability (v2). Returns per-territory availability, release date, and pre-order status.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "availability_id": .object([
                        "type": .string("string"),
                        "description": .string("App availability resource ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 50, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("availability_id")])
            ])
        )
    }

    private func nullablePriceDateSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "format": .string("date"),
            "description": .string(description)
        ])
    }

    private func nullablePricingBooleanSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("boolean"), .string("null")]),
            "description": .string(description)
        ])
    }
}
