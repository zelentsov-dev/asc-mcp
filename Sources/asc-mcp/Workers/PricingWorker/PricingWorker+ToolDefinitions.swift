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
                        "description": .string("Filter by territory code (e.g. USA, RUS, DEU)")
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
                        "description": .string("Base territory code (e.g. USA)")
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
}
