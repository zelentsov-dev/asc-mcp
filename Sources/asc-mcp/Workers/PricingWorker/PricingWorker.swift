//
//  PricingWorker.swift
//  asc-mcp
//
//  App pricing, territories, and availability management for App Store Connect
//

import Foundation
import MCP

/// Worker for managing app pricing, territories, and availability in App Store Connect
public final class PricingWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get all available tools for pricing management
    public func getTools() async -> [Tool] {
        return [
            listTerritoriesToolDef(),
            getAppAvailabilityTool(),
            listPricePointsTool(),
            getAppPriceScheduleTool(),
            setAppPriceScheduleTool(),
            listTerritoryAvailabilityTool(),
            createAvailabilityV2Tool(),
            getAvailabilityV2Tool(),
            listTerritoryAvailabilitiesV2Tool()
        ]
    }

    /// Handle tool call for pricing operations
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "pricing_list_territories":
            return try await listTerritories(params)
        case "pricing_get_availability":
            return try await getAppAvailability(params)
        case "pricing_list_price_points":
            return try await listPricePoints(params)
        case "pricing_get_price_schedule":
            return try await getAppPriceSchedule(params)
        case "pricing_set_price_schedule":
            return try await setAppPriceSchedule(params)
        case "pricing_list_territory_availability":
            return try await listTerritoryAvailability(params)
        case "pricing_create_availability":
            return try await createAvailabilityV2(params)
        case "pricing_get_availability_v2":
            return try await getAvailabilityV2(params)
        case "pricing_list_territory_availabilities":
            return try await listTerritoryAvailabilitiesV2(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
