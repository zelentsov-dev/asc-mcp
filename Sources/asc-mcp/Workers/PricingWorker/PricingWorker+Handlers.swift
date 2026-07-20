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
            let endpoint = "/v1/territories"
            let limit = arguments?["limit"]?.intValue ?? 200
            let queryParams = ["limit": String(min(max(limit, 1), 200))]
            let response: ASCTerritoriesResponse

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(path: endpoint, query: queryParams),
                    as: ASCTerritoriesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list territories: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Get App Availability

    /// Gets app availability configuration
    /// - Returns: JSON with availability info and optional territory availability resources
    func getAppAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let query = try appAvailabilityQuery(arguments)
            let response: ASCAppAvailabilityV2Response = try await httpClient.get(
                "/v1/apps/\(try ASCPathSegment.encode(appId))/appAvailabilityV2",
                parameters: query,
                as: ASCAppAvailabilityV2Response.self
            )

            let result: [String: Any] = [
                "success": true,
                "availability": formatAppAvailability(response)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get app availability: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppPricePointsV3Response

            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/appPricePoints"
            var requiredParameters: [String: String] = [
                "include": "territory"
            ]
            if let territoryId = arguments["territory_id"]?.stringValue {
                requiredParameters["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: requiredParameters),
                    as: ASCAppPricePointsV3Response.self
                )
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
                    endpoint,
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list price points: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let manualPricesLimit = min(max(arguments["manual_prices_limit"]?.intValue ?? 50, 1), 50)
            let automaticPricesLimit = min(max(arguments["automatic_prices_limit"]?.intValue ?? 50, 1), 50)
            let response: ASCAppPriceScheduleResponse = try await httpClient.get(
                "/v1/apps/\(try ASCPathSegment.encode(appId))/appPriceSchedule",
                parameters: [
                    "include": "manualPrices,automaticPrices,baseTerritory",
                    "limit[manualPrices]": String(manualPricesLimit),
                    "limit[automaticPrices]": String(automaticPricesLimit)
                ],
                as: ASCAppPriceScheduleResponse.self
            )

            let relationships = response.data.relationships
            let manualPriceIds = relationships?.manualPrices?.data?.map(\.id) ?? []
            let automaticPriceIds = relationships?.automaticPrices?.data?.map(\.id) ?? []

            var territories: [[String: Any]] = []
            var includedPrices: [ASCAppPrice] = []

            if let included = response.included {
                for resource in included {
                    switch resource {
                    case .territory(let territory):
                        territories.append(formatTerritory(territory))
                    case .appPrice(let price):
                        includedPrices.append(price)
                    case .app, .appPricePoint:
                        break
                    }
                }
            }

            var includedPriceMap: [String: ASCAppPrice] = [:]
            for price in includedPrices {
                includedPriceMap[price.id] = price
            }
            let linkedIds = Set(manualPriceIds + automaticPriceIds)
            var manualPrices = manualPriceIds.compactMap { id in
                includedPriceMap[id].map { formatAppPrice($0) }
            }
            var automaticPrices = automaticPriceIds.compactMap { id in
                includedPriceMap[id].map { formatAppPrice($0) }
            }
            for price in includedPrices where !linkedIds.contains(price.id) {
                if price.attributes?.manual == true {
                    manualPrices.append(formatAppPrice(price))
                } else {
                    automaticPrices.append(formatAppPrice(price))
                }
            }

            var schedule: [String: Any] = [
                "id": response.data.id,
                "type": response.data.type,
                "manual_prices": manualPrices,
                "automatic_prices": automaticPrices,
                "territories": territories,
                "manual_price_ids": manualPriceIds,
                "automatic_price_ids": automaticPriceIds,
                "manual_prices_included_count": manualPrices.count,
                "automatic_prices_included_count": automaticPrices.count
            ]

            if let baseTerritoryData = relationships?.baseTerritory?.data {
                schedule["base_territory_id"] = baseTerritoryData.id
                if let baseTerritory = territories.first(where: { $0["id"] as? String == baseTerritoryData.id }) {
                    schedule["base_territory"] = baseTerritory
                }
            }

            appendRelationshipPaging(
                prefix: "manual_prices",
                relationship: relationships?.manualPrices,
                meta: relationships?.manualPricesMeta,
                includedCount: manualPrices.count,
                requestedLimit: manualPricesLimit,
                to: &schedule
            )
            appendRelationshipPaging(
                prefix: "automatic_prices",
                relationship: relationships?.automaticPrices,
                meta: relationships?.automaticPricesMeta,
                includedCount: automaticPrices.count,
                requestedLimit: automaticPricesLimit,
                to: &schedule
            )

            let result: [String: Any] = [
                "success": true,
                "price_schedule": schedule
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get price schedule: \(error.localizedDescription)")],
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
              let baseTerritoryId = baseTerritoryValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: app_id, base_territory_id, and exactly one of price_point_id or manual_prices")],
                isError: true
            )
        }

        let manualPriceInputs: [PriceScheduleInput]
        do {
            manualPriceInputs = try priceScheduleInputs(arguments)
        } catch {
            return CallTool.Result(
                content: [MCPContent.text(error.localizedDescription)],
                isError: true
            )
        }

        do {
            let inlinePrices = manualPriceInputs.enumerated().map { index, input in
                CreateAppPriceInlineRequest(
                    id: "${price-\(index)}",
                    attributes: CreateAppPriceInlineRequest.Attributes(
                        startDate: input.startDate,
                        endDate: input.endDate
                    ),
                    relationships: CreateAppPriceInlineRequest.CreateAppPriceInlineRelationships(
                        appPricePoint: CreateAppPriceInlineRequest.AppPricePointRelationship(
                            data: ASCResourceIdentifier(type: "appPricePoints", id: input.pricePointId)
                        )
                    )
                )
            }

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
                            data: inlinePrices.map {
                                ASCResourceIdentifier(type: "appPrices", id: $0.id)
                            }
                        )
                    )
                ),
                included: inlinePrices
            )

            let response: ASCAppPriceScheduleResponse = try await httpClient.post(
                "/v1/appPriceSchedules",
                body: request,
                as: ASCAppPriceScheduleResponse.self
            )

            var schedule: [String: Any] = [
                "id": response.data.id,
                "type": response.data.type,
                "submitted_manual_prices_count": manualPriceInputs.count
            ]

            if let baseTerritoryData = response.data.relationships?.baseTerritory?.data {
                schedule["base_territory_id"] = baseTerritoryData.id
            }

            let result: [String: Any] = [
                "success": true,
                "price_schedule": schedule
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to set price schedule: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCTerritoryAvailabilitiesResponse
            let availability: ASCAppAvailabilityV2Response = try await httpClient.get(
                "/v1/apps/\(try ASCPathSegment.encode(appId))/appAvailabilityV2",
                as: ASCAppAvailabilityV2Response.self
            )
            let endpoint = "/v2/appAvailabilities/\(try ASCPathSegment.encode(availability.data.id))/territoryAvailabilities"

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: endpoint,
                        requiredParameters: ["include": "territory"]
                    ),
                    as: ASCTerritoryAvailabilitiesResponse.self
                )
            } else {
                let limit = min(max(arguments["limit"]?.intValue ?? 50, 1), 200)

                response = try await httpClient.get(
                    endpoint,
                    parameters: [
                        "include": "territory",
                        "limit": String(limit)
                    ],
                    as: ASCTerritoryAvailabilitiesResponse.self
                )
            }

            var territoryMap: [String: ASCTerritory] = [:]
            for territory in response.included ?? [] {
                territoryMap[territory.id] = territory
            }
            let availabilities = response.data.map {
                formatTerritoryAvailability($0, territoryMap: territoryMap)
            }
            var result: [String: Any] = [
                "success": true,
                "territory_availabilities": availabilities,
                "count": availabilities.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list territory availability: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameters: app_id, available_in_new_territories, and territory_ids or territory_availabilities")],
                isError: true
            )
        }

        let territoryIds: [String]
        let inlineTerritories: [TerritoryAvailabilityInput]
        do {
            territoryIds = try existingTerritoryAvailabilityIds(arguments["territory_ids"])
            inlineTerritories = try territoryAvailabilityInputs(arguments["territory_availabilities"])
            guard !territoryIds.isEmpty || !inlineTerritories.isEmpty else {
                throw PricingArgumentError(
                    "Provide at least one existing 'territory_ids' relationship or one inline 'territory_availabilities' entry"
                )
            }
        } catch {
            return CallTool.Result(
                content: [MCPContent.text(error.localizedDescription)],
                isError: true
            )
        }

        do {
            let inlineResources = inlineTerritories.enumerated().map { index, input in
                TerritoryAvailabilityInlineCreate(
                    id: "${territoryAvailability-\(index)}",
                    attributes: TerritoryAvailabilityInlineCreate.Attributes(
                        available: input.available,
                        releaseDate: input.releaseDate,
                        preOrderEnabled: input.preOrderEnabled
                    ),
                    relationships: TerritoryAvailabilityInlineCreate.Relationships(
                        territory: TerritoryAvailabilityInlineCreate.TerritoryRelationship(
                            data: ASCResourceIdentifier(type: "territories", id: input.territoryId)
                        )
                    )
                )
            }
            let relationshipIds = territoryIds + inlineResources.map(\.id)
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
                            data: relationshipIds.map {
                                ASCResourceIdentifier(type: "territoryAvailabilities", id: $0)
                            }
                        )
                    )
                ),
                included: inlineResources.isEmpty ? nil : inlineResources
            )

            let response: ASCAppAvailabilityV2Response = try await httpClient.post(
                "/v2/appAvailabilities",
                body: request,
                as: ASCAppAvailabilityV2Response.self
            )

            let result: [String: Any] = [
                "success": true,
                "availability": formatAppAvailability(response),
                "submitted_existing_territory_availability_count": territoryIds.count,
                "submitted_inline_territory_availability_count": inlineTerritories.count
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to create app availability: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameter 'availability_id' is missing")],
                isError: true
            )
        }

        do {
            let query = try appAvailabilityQuery(arguments)
            let response: ASCAppAvailabilityV2Response = try await httpClient.get(
                "/v2/appAvailabilities/\(try ASCPathSegment.encode(availabilityId))",
                parameters: query,
                as: ASCAppAvailabilityV2Response.self
            )

            let result: [String: Any] = [
                "success": true,
                "availability": formatAppAvailability(response)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get app availability: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameter 'availability_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCTerritoryAvailabilitiesResponse

            let endpoint = "/v2/appAvailabilities/\(try ASCPathSegment.encode(availabilityId))/territoryAvailabilities"

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: endpoint,
                        requiredParameters: ["include": "territory"]
                    ),
                    as: ASCTerritoryAvailabilitiesResponse.self
                )
            } else {
                var queryParams: [String: String] = [
                    "include": "territory"
                ]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "50"
                }

                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCTerritoryAvailabilitiesResponse.self
                )
            }

            var territoryMap: [String: ASCTerritory] = [:]
            for territory in response.included ?? [] {
                territoryMap[territory.id] = territory
            }
            let availabilities = response.data.map {
                formatTerritoryAvailability($0, territoryMap: territoryMap)
            }

            var result: [String: Any] = [
                "success": true,
                "territory_availabilities": availabilities,
                "count": availabilities.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list territory availabilities: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatTerritory(_ territory: ASCTerritory) -> [String: Any] {
        return [
            "id": territory.id,
            "type": territory.type,
            "currency": (territory.attributes?.currency).jsonSafe
        ]
    }

    private func formatPricePoint(_ pricePoint: ASCAppPricePointV3, territoryMap: [String: ASCTerritory]) -> [String: Any] {
        var result: [String: Any] = [
            "id": pricePoint.id,
            "type": pricePoint.type,
            "customerPrice": (pricePoint.attributes?.customerPrice).jsonSafe,
            "proceeds": (pricePoint.attributes?.proceeds).jsonSafe
        ]

        if let territoryData = pricePoint.relationships?.territory?.data,
           let territory = territoryMap[territoryData.id] {
            result["territory_id"] = territory.id
            result["currency"] = (territory.attributes?.currency).jsonSafe
        } else if let territoryData = pricePoint.relationships?.territory?.data {
            result["territory_id"] = territoryData.id
        }

        return result
    }

    private func formatAppPrice(_ price: ASCAppPrice) -> [String: Any] {
        var result: [String: Any] = [
            "id": price.id,
            "type": price.type,
            "startDate": (price.attributes?.startDate).jsonSafe,
            "endDate": (price.attributes?.endDate).jsonSafe,
            "manual": (price.attributes?.manual).jsonSafe
        ]

        if let pricePointData = price.relationships?.appPricePoint?.data {
            result["price_point_id"] = pricePointData.id
        }
        if let territoryData = price.relationships?.territory?.data {
            result["territory_id"] = territoryData.id
        }

        return result
    }

    private func formatAppAvailability(_ response: ASCAppAvailabilityV2Response) -> [String: Any] {
        let relationship = response.data.relationships?.territoryAvailabilities
        let included = response.included?.map { formatTerritoryAvailability($0, territoryMap: [:]) } ?? []
        var result: [String: Any] = [
            "id": response.data.id,
            "type": response.data.type,
            "availableInNewTerritories": (response.data.attributes?.availableInNewTerritories).jsonSafe,
            "territory_availability_ids": relationship?.data?.map(\.id) ?? [],
            "territory_availabilities": included,
            "territory_availabilities_included_count": included.count
        ]

        if let total = relationship?.meta?.paging?.total {
            result["territory_availabilities_total"] = total
            result["territory_availabilities_truncated"] = total > included.count
        } else {
            result["territory_availabilities_truncated"] = NSNull()
        }
        if let limit = relationship?.meta?.paging?.limit {
            result["territory_availabilities_limit"] = limit
        }
        if let related = relationship?.links?.related {
            result["territory_availabilities_related_url"] = related
        }
        if let relationshipURL = relationship?.links?.`self` {
            result["territory_availabilities_relationship_url"] = relationshipURL
        }

        return result
    }

    private func appAvailabilityQuery(_ arguments: [String: Value]) throws -> [String: String] {
        let include = arguments["include_territory_availabilities"]?.boolValue
        let hasNestedLimit = arguments["territory_availabilities_limit"] != nil

        if include == false && hasNestedLimit {
            throw PricingArgumentError(
                "'territory_availabilities_limit' requires 'include_territory_availabilities' to be true or omitted"
            )
        }

        guard include == true || hasNestedLimit else {
            return [:]
        }

        let limit = min(max(arguments["territory_availabilities_limit"]?.intValue ?? 50, 1), 50)
        return [
            "include": "territoryAvailabilities",
            "limit[territoryAvailabilities]": String(limit)
        ]
    }

    private func existingTerritoryAvailabilityIds(_ value: Value?) throws -> [String] {
        guard let value, !value.isNull else { return [] }
        guard let values = value.arrayValue else {
            throw PricingArgumentError("'territory_ids' must be an array of strings")
        }
        let ids = values.compactMap(\.stringValue).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard ids.count == values.count, ids.allSatisfy({ !$0.isEmpty }) else {
            throw PricingArgumentError("'territory_ids' must contain only non-empty strings")
        }
        guard Set(ids).count == ids.count else {
            throw PricingArgumentError("'territory_ids' must not contain duplicate IDs")
        }
        return ids
    }

    private func territoryAvailabilityInputs(_ value: Value?) throws -> [TerritoryAvailabilityInput] {
        guard let value, !value.isNull else { return [] }
        guard let values = value.arrayValue, !values.isEmpty else {
            throw PricingArgumentError("'territory_availabilities' must be a non-empty array of objects")
        }

        let inputs = try values.enumerated().map { index, value in
            guard let object = value.objectValue else {
                throw PricingArgumentError("territory_availabilities[\(index)] must be an object")
            }
            let allowedKeys: Set<String> = [
                "territory_id", "available", "release_date", "pre_order_enabled"
            ]
            if let unsupported = object.keys.first(where: { !allowedKeys.contains($0) }) {
                throw PricingArgumentError(
                    "territory_availabilities[\(index)] contains unsupported field '\(unsupported)'"
                )
            }
            guard let rawTerritoryId = object["territory_id"]?.stringValue else {
                throw PricingArgumentError("territory_availabilities[\(index)].territory_id is required")
            }
            let territoryId = rawTerritoryId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !territoryId.isEmpty else {
                throw PricingArgumentError("territory_availabilities[\(index)].territory_id must be non-empty")
            }

            return TerritoryAvailabilityInput(
                territoryId: territoryId,
                available: try nullablePricingBool(
                    object["available"],
                    field: "territory_availabilities[\(index)].available"
                ),
                releaseDate: try pricingDate(
                    object["release_date"],
                    field: "territory_availabilities[\(index)].release_date"
                ),
                preOrderEnabled: try nullablePricingBool(
                    object["pre_order_enabled"],
                    field: "territory_availabilities[\(index)].pre_order_enabled"
                )
            )
        }

        guard Set(inputs.map(\.territoryId)).count == inputs.count else {
            throw PricingArgumentError("'territory_availabilities' must not contain duplicate territory_id values")
        }
        return inputs
    }

    private func nullablePricingBool(_ value: Value?, field: String) throws -> Bool? {
        guard let value, !value.isNull else { return nil }
        guard let boolean = value.boolValue else {
            throw PricingArgumentError("'\(field)' must be a boolean or null")
        }
        return boolean
    }

    private func priceScheduleInputs(_ arguments: [String: Value]) throws -> [PriceScheduleInput] {
        let legacyPricePointId = arguments["price_point_id"]?.stringValue
        let manualPricesValue = arguments["manual_prices"]

        guard (legacyPricePointId == nil) != (manualPricesValue == nil) else {
            throw PricingArgumentError("Provide exactly one of 'price_point_id' or 'manual_prices'")
        }

        if let legacyPricePointId {
            let pricePointId = legacyPricePointId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pricePointId.isEmpty else {
                throw PricingArgumentError("'price_point_id' must be a non-empty string")
            }
            return [
                try PriceScheduleInput(
                    pricePointId: pricePointId,
                    startDate: try pricingDate(arguments["start_date"], field: "start_date"),
                    endDate: try pricingDate(arguments["end_date"], field: "end_date")
                ).validated()
            ]
        }

        guard arguments["start_date"] == nil, arguments["end_date"] == nil else {
            throw PricingArgumentError("Top-level 'start_date' and 'end_date' can only be used with legacy 'price_point_id'")
        }
        guard let values = manualPricesValue?.arrayValue, !values.isEmpty else {
            throw PricingArgumentError("'manual_prices' must be a non-empty array of price objects")
        }

        return try values.enumerated().map { index, value in
            guard let object = value.objectValue else {
                throw PricingArgumentError("manual_prices[\(index)] must be an object")
            }
            let allowedKeys: Set<String> = ["price_point_id", "start_date", "end_date"]
            if let unsupported = object.keys.first(where: { !allowedKeys.contains($0) }) {
                throw PricingArgumentError("manual_prices[\(index)] contains unsupported field '\(unsupported)'")
            }
            guard let rawPricePointId = object["price_point_id"]?.stringValue else {
                throw PricingArgumentError("manual_prices[\(index)].price_point_id is required")
            }
            let pricePointId = rawPricePointId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pricePointId.isEmpty else {
                throw PricingArgumentError("manual_prices[\(index)].price_point_id must be non-empty")
            }
            return try PriceScheduleInput(
                pricePointId: pricePointId,
                startDate: pricingDate(object["start_date"], field: "manual_prices[\(index)].start_date"),
                endDate: pricingDate(object["end_date"], field: "manual_prices[\(index)].end_date")
            ).validated()
        }
    }

    private func pricingDate(_ value: Value?, field: String) throws -> String? {
        guard let value, !value.isNull else { return nil }
        guard let string = value.stringValue, isValidPricingDate(string) else {
            throw PricingArgumentError("'\(field)' must be a valid date in YYYY-MM-DD format or null")
        }
        return string
    }

    private func isValidPricingDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]),
              year >= 1,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    private func appendRelationshipPaging(
        prefix: String,
        relationship: ASCRelationshipMultiple?,
        meta: ASCPagingInformation?,
        includedCount: Int,
        requestedLimit: Int,
        to result: inout [String: Any]
    ) {
        result["\(prefix)_requested_limit"] = requestedLimit
        if let total = meta?.paging?.total {
            result["\(prefix)_total"] = total
            result["\(prefix)_truncated"] = total > includedCount
        } else {
            result["\(prefix)_truncated"] = NSNull()
        }
        if let limit = meta?.paging?.limit {
            result["\(prefix)_relationship_limit"] = limit
        }
        if let related = relationship?.links?.related {
            result["\(prefix)_related_url"] = related
        }
        if let relationshipURL = relationship?.links?.`self` {
            result["\(prefix)_relationship_url"] = relationshipURL
        }
    }

    private func formatTerritoryAvailability(
        _ availability: ASCTerritoryAvailability,
        territoryMap: [String: ASCTerritory]
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": availability.id,
            "type": availability.type,
            "available": (availability.attributes?.available).jsonSafe,
            "releaseDate": (availability.attributes?.releaseDate).jsonSafe,
            "preOrderEnabled": (availability.attributes?.preOrderEnabled).jsonSafe,
            "preOrderPublishDate": (availability.attributes?.preOrderPublishDate).jsonSafe
        ]

        if let contentStatuses = availability.attributes?.contentStatuses {
            result["contentStatuses"] = contentStatuses
        }

        if let territoryData = availability.relationships?.territory?.data {
            result["territory_id"] = territoryData.id
            if let territory = territoryMap[territoryData.id] {
                result["currency"] = (territory.attributes?.currency).jsonSafe
            }
        }

        return result
    }

}

private struct PriceScheduleInput {
    let pricePointId: String
    let startDate: String?
    let endDate: String?

    func validated() throws -> PriceScheduleInput {
        if let startDate, let endDate, startDate > endDate {
            throw PricingArgumentError("Price schedule start_date must not be later than end_date")
        }
        return self
    }
}

private struct TerritoryAvailabilityInput {
    let territoryId: String
    let available: Bool?
    let releaseDate: String?
    let preOrderEnabled: Bool?
}

private struct PricingArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
