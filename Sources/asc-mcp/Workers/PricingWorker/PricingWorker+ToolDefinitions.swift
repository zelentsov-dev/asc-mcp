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
            description: "Get app availability configuration (whether app is available in new territories automatically)",
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
            description: "Set or update the price schedule for an app. Requires base territory and price point ID (get from pricing_list_price_points).",
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
                        "description": .string("Price point resource ID from pricing_list_price_points")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("base_territory_id"), .string("price_point_id")])
            ])
        )
    }

    /// Tool definition for listing territory availability
    func listTerritoryAvailabilityTool() -> Tool {
        return Tool(
            name: "pricing_list_territory_availability",
            description: "List per-territory availability for an app (available, release date, pre-order status)",
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
            description: "Create app availability configuration (v2). Sets which territories the app is available in and whether it auto-publishes to new territories.",
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
                        "description": .string("Array of territory availability IDs to include"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("app_id"), .string("available_in_new_territories"), .string("territory_ids")])
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
}
