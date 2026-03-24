//
//  PricingWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of pricing, territories, and availability handlers
//

import Foundation
import MCP

// MARK: - Tool Handlers
extension PricingWorker {

    // MARK: - List Territories

    /// Lists all available App Store territories
    /// - Returns: JSON array of territories with currency info and pagination
    func listTerritories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCTerritoriesResponse

            if let nextUrl = arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCTerritoriesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments?["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "200"
                }

                response = try await httpClient.get(
                    "/v1/territories",
                    parameters: queryParams,
                    as: ASCTerritoriesResponse.self
                )
            }

            let territories = response.data.map { formatTerritory($0) }

            var result: [String: Any] = [
                "success": true,
                "territories": territories,
                "count": territories.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list territories: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Get App Availability

    /// Gets app availability configuration
    /// - Returns: JSON with availability info (whether available in new territories)
    func getAppAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppAvailabilityV2Response = try await httpClient.get(
                "/v1/apps/\(appId)/appAvailabilityV2",
                as: ASCAppAvailabilityV2Response.self
            )

            let result: [String: Any] = [
                "success": true,
                "availability": [
                    "id": response.data.id,
                    "type": response.data.type,
                    "availableInNewTerritories": response.data.attributes?.availableInNewTerritories.jsonSafe
                ] as [String: Any]
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get app availability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - List Price Points

    /// Lists available price points for an app
    /// - Returns: JSON array of price points with customer price and proceeds
    func listPricePoints(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppPricePointsV3Response

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAppPricePointsV3Response.self)
            } else {
                var queryParams: [String: String] = [
                    "include": "territory"
                ]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "50"
                }

                if let territoryId = arguments["territory_id"]?.stringValue {
                    queryParams["filter[territory]"] = territoryId
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/appPricePoints",
                    parameters: queryParams,
                    as: ASCAppPricePointsV3Response.self
                )
            }

            // Build territory lookup from included resources
            var territoryMap: [String: ASCTerritory] = [:]
            if let included = response.included {
                for resource in included {
                    if case .territory(let territory) = resource {
                        territoryMap[territory.id] = territory
                    }
                }
            }

            let pricePoints = response.data.map { formatPricePoint($0, territoryMap: territoryMap) }

            var result: [String: Any] = [
                "success": true,
                "price_points": pricePoints,
                "count": pricePoints.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list price points: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Get Price Schedule

    /// Gets current price schedule for an app
    /// - Returns: JSON with price schedule including manual/automatic prices and base territory
    func getAppPriceSchedule(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppPriceScheduleResponse = try await httpClient.get(
                "/v1/apps/\(appId)/appPriceSchedule",
                parameters: [
                    "include": "manualPrices,automaticPrices,baseTerritory"
                ],
                as: ASCAppPriceScheduleResponse.self
            )

            // Parse included resources
            var territories: [[String: Any]] = []
            var manualPrices: [[String: Any]] = []
            var automaticPrices: [[String: Any]] = []

            if let included = response.included {
                for resource in included {
                    switch resource {
                    case .territory(let territory):
                        territories.append(formatTerritory(territory))
                    case .appPrice(let price):
                        let formatted = formatAppPrice(price)
                        if price.attributes?.manual == true {
                            manualPrices.append(formatted)
                        } else {
                            automaticPrices.append(formatted)
                        }
                    case .appPricePoint:
                        break
                    }
                }
            }

            var schedule: [String: Any] = [
                "id": response.data.id,
                "type": response.data.type
            ]

            if let baseTerritoryData = response.data.relationships?.baseTerritory?.data {
                schedule["base_territory_id"] = baseTerritoryData.id
            }

            if !manualPrices.isEmpty {
                schedule["manual_prices"] = manualPrices
            }
            if !automaticPrices.isEmpty {
                schedule["automatic_prices"] = automaticPrices
            }
            if !territories.isEmpty {
                schedule["territories"] = territories
            }

            let result: [String: Any] = [
                "success": true,
                "price_schedule": schedule
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get price schedule: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Set Price Schedule

    /// Sets or updates the price schedule for an app
    /// - Returns: JSON with created price schedule details
    func setAppPriceSchedule(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let baseTerritoryValue = arguments["base_territory_id"],
              let baseTerritoryId = baseTerritoryValue.stringValue,
              let pricePointIdValue = arguments["price_point_id"],
              let pricePointId = pricePointIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters: app_id, base_territory_id, price_point_id")],
                isError: true
            )
        }

        do {
            let inlinePriceId = "${price1}"

            let request = CreateAppPriceScheduleRequest(
                data: CreateAppPriceScheduleRequest.CreateAppPriceScheduleData(
                    relationships: CreateAppPriceScheduleRequest.CreateAppPriceScheduleRelationships(
                        app: CreateAppPriceScheduleRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        ),
                        baseTerritory: CreateAppPriceScheduleRequest.BaseTerritoryRelationship(
                            data: ASCResourceIdentifier(type: "territories", id: baseTerritoryId)
                        ),
                        manualPrices: CreateAppPriceScheduleRequest.ManualPricesRelationship(
                            data: [ASCResourceIdentifier(type: "appPrices", id: inlinePriceId)]
                        )
                    )
                ),
                included: [
                    CreateAppPriceInlineRequest(
                        id: inlinePriceId,
                        relationships: CreateAppPriceInlineRequest.CreateAppPriceInlineRelationships(
                            appPricePoint: CreateAppPriceInlineRequest.AppPricePointRelationship(
                                data: ASCResourceIdentifier(type: "appPricePoints", id: pricePointId)
                            )
                        )
                    )
                ]
            )

            let response: ASCAppPriceScheduleResponse = try await httpClient.post(
                "/v1/appPriceSchedules",
                body: request,
                as: ASCAppPriceScheduleResponse.self
            )

            var schedule: [String: Any] = [
                "id": response.data.id,
                "type": response.data.type
            ]

            if let baseTerritoryData = response.data.relationships?.baseTerritory?.data {
                schedule["base_territory_id"] = baseTerritoryData.id
            }

            let result: [String: Any] = [
                "success": true,
                "price_schedule": schedule
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to set price schedule: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - List Territory Availability

    /// Lists per-territory availability for an app via appAvailabilityV2 endpoint
    /// - Returns: JSON array of territory availabilities with pagination
    func listTerritoryAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            // Use appAvailabilityV2 with included territoryAvailabilities
            let queryParams: [String: String] = [
                "include": "territoryAvailabilities",
                "fields[territoryAvailabilities]": "available,releaseDate,preOrderEnabled,territory",
                "limit[territoryAvailabilities]": "50"
            ]

            let data = try await httpClient.get(
                "/v1/apps/\(appId)/appAvailabilityV2",
                parameters: queryParams
            )

            // Parse response with included territory availabilities
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

            var availabilities: [[String: Any]] = []
            if let included = json?["included"] as? [[String: Any]] {
                for item in included {
                    guard let type = item["type"] as? String, type == "territoryAvailabilities" else { continue }
                    var availability: [String: Any] = [
                        "id": item["id"] as? String ?? "",
                        "type": type
                    ]
                    if let attrs = item["attributes"] as? [String: Any] {
                        availability["available"] = attrs["available"]
                        availability["releaseDate"] = attrs["releaseDate"]
                        availability["preOrderEnabled"] = attrs["preOrderEnabled"]
                    }
                    if let rels = item["relationships"] as? [String: Any],
                       let territory = rels["territory"] as? [String: Any],
                       let territoryData = territory["data"] as? [String: Any] {
                        availability["territory_id"] = territoryData["id"]
                    }
                    availabilities.append(availability)
                }
            }

            let result: [String: Any] = [
                "success": true,
                "territory_availabilities": availabilities,
                "count": availabilities.count
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list territory availability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - App Availability v2

    /// Creates app availability configuration via v2 endpoint
    /// - Returns: JSON with created availability details
    /// - Throws: On network or encoding errors
    func createAvailabilityV2(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue,
              let availableInNew = arguments["available_in_new_territories"]?.boolValue else {
            return CallTool.Result(
                content: [.text("Required parameters: app_id, available_in_new_territories, territory_ids")],
                isError: true
            )
        }

        // Parse territory_ids array
        guard let territoryIdsValue = arguments["territory_ids"],
              case .array(let territoryArray) = territoryIdsValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'territory_ids' must be an array of strings")],
                isError: true
            )
        }

        let territoryIds = territoryArray.compactMap { value -> String? in
            if case .string(let s) = value { return s }
            return nil
        }

        guard !territoryIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Required parameter 'territory_ids' must contain at least one territory ID")],
                isError: true
            )
        }

        do {
            let request = CreateAppAvailabilityV2Request(
                data: CreateAppAvailabilityV2Request.CreateData(
                    attributes: CreateAppAvailabilityV2Request.Attributes(
                        availableInNewTerritories: availableInNew
                    ),
                    relationships: CreateAppAvailabilityV2Request.Relationships(
                        app: CreateAppAvailabilityV2Request.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        ),
                        territoryAvailabilities: CreateAppAvailabilityV2Request.TerritoryAvailabilitiesRelationship(
                            data: territoryIds.map { ASCResourceIdentifier(type: "territoryAvailabilities", id: $0) }
                        )
                    )
                )
            )

            let response: ASCAppAvailabilityV2Response = try await httpClient.post(
                "/v2/appAvailabilities",
                body: request,
                as: ASCAppAvailabilityV2Response.self
            )

            let result: [String: Any] = [
                "success": true,
                "availability": [
                    "id": response.data.id,
                    "type": response.data.type,
                    "availableInNewTerritories": response.data.attributes?.availableInNewTerritories.jsonSafe
                ] as [String: Any]
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create app availability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets app availability by availability ID via v2 endpoint
    /// - Returns: JSON with availability details
    /// - Throws: On network or decoding errors
    func getAvailabilityV2(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let availabilityId = arguments["availability_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'availability_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppAvailabilityV2Response = try await httpClient.get(
                "/v2/appAvailabilities/\(availabilityId)",
                as: ASCAppAvailabilityV2Response.self
            )

            let result: [String: Any] = [
                "success": true,
                "availability": [
                    "id": response.data.id,
                    "type": response.data.type,
                    "availableInNewTerritories": response.data.attributes?.availableInNewTerritories.jsonSafe
                ] as [String: Any]
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get app availability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists territory availabilities for an app availability via v2 endpoint
    /// - Returns: JSON array of territory availabilities with pagination
    /// - Throws: On network or decoding errors
    func listTerritoryAvailabilitiesV2(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let availabilityId = arguments["availability_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'availability_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCTerritoryAvailabilitiesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCTerritoryAvailabilitiesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "50"
                }

                response = try await httpClient.get(
                    "/v2/appAvailabilities/\(availabilityId)/territoryAvailabilities",
                    parameters: queryParams,
                    as: ASCTerritoryAvailabilitiesResponse.self
                )
            }

            let availabilities = response.data.map { formatTerritoryAvailability($0) }

            var result: [String: Any] = [
                "success": true,
                "territory_availabilities": availabilities,
                "count": availabilities.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list territory availabilities: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    /// Format territory as a dictionary for JSON output
    private func formatTerritory(_ territory: ASCTerritory) -> [String: Any] {
        return [
            "id": territory.id,
            "type": territory.type,
            "currency": territory.attributes?.currency.jsonSafe
        ]
    }

    /// Format price point as a dictionary for JSON output
    private func formatPricePoint(_ pricePoint: ASCAppPricePointV3, territoryMap: [String: ASCTerritory]) -> [String: Any] {
        var result: [String: Any] = [
            "id": pricePoint.id,
            "type": pricePoint.type,
            "customerPrice": pricePoint.attributes?.customerPrice.jsonSafe,
            "proceeds": pricePoint.attributes?.proceeds.jsonSafe
        ]

        if let territoryData = pricePoint.relationships?.territory?.data,
           let territory = territoryMap[territoryData.id] {
            result["territory_id"] = territory.id
            result["currency"] = territory.attributes?.currency.jsonSafe
        } else if let territoryData = pricePoint.relationships?.territory?.data {
            result["territory_id"] = territoryData.id
        }

        return result
    }

    /// Format app price as a dictionary for JSON output
    private func formatAppPrice(_ price: ASCAppPrice) -> [String: Any] {
        var result: [String: Any] = [
            "id": price.id,
            "type": price.type,
            "startDate": price.attributes?.startDate.jsonSafe,
            "endDate": price.attributes?.endDate.jsonSafe,
            "manual": price.attributes?.manual.jsonSafe
        ]

        if let pricePointData = price.relationships?.appPricePoint?.data {
            result["price_point_id"] = pricePointData.id
        }
        if let territoryData = price.relationships?.territory?.data {
            result["territory_id"] = territoryData.id
        }

        return result
    }

    /// Format territory availability as a dictionary for JSON output
    private func formatTerritoryAvailability(_ availability: ASCTerritoryAvailability) -> [String: Any] {
        var result: [String: Any] = [
            "id": availability.id,
            "type": availability.type,
            "available": availability.attributes?.available.jsonSafe,
            "releaseDate": availability.attributes?.releaseDate.jsonSafe,
            "preOrderEnabled": availability.attributes?.preOrderEnabled.jsonSafe
        ]

        if let contentStatuses = availability.attributes?.contentStatuses {
            result["contentStatuses"] = contentStatuses
        }

        if let territoryData = availability.relationships?.territory?.data {
            result["territory_id"] = territoryData.id
        }

        return result
    }
}
