import Foundation
import MCP

extension SubscriptionsWorker {
    func listSubscriptionPricesV3(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'subscription_id' is missing")
        }

        do {
            let response: PassthroughAPIResponse
            let endpoint = "/v1/subscriptions/\(subscriptionId)/prices"
            var query = subscriptionPriceQuery(arguments: arguments, maxLimit: 200)
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }
            if let pricePointId = arguments["price_point_id"]?.stringValue {
                query["filter[subscriptionPricePoint]"] = pricePointId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: paginationFilters(from: query)),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: PassthroughAPIResponse.self
                )
            }

            let included = IncludedIndex(response.included)
            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                "prices": data.map { formatSubscriptionPrice($0, included: included) },
                "count": data.count
            ]
            appendNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list subscription prices: \(error.localizedDescription)")
        }
    }

    func listSubscriptionPricePointsV3(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'subscription_id' is missing")
        }

        do {
            let response: PassthroughAPIResponse
            let endpoint = "/v1/subscriptions/\(subscriptionId)/pricePoints"
            var query: [String: String] = [
                "include": "territory",
                "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations",
                "fields[territories]": "currency",
                "limit": String(clampedLimit(arguments["limit"]?.intValue, defaultValue: 25, max: 8000))
            ]
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: paginationFilters(from: query)),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: PassthroughAPIResponse.self
                )
            }

            let included = IncludedIndex(response.included)
            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                "price_points": data.map { formatSubscriptionPricePoint($0, included: included) },
                "count": data.count
            ]
            appendNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list subscription price points: \(error.localizedDescription)")
        }
    }

    func listSubscriptionGroups(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }
        return try await listResources(
            params,
            endpoint: "/v1/apps/\(appId)/subscriptionGroups",
            key: "groups",
            defaultQuery: ["include": "subscriptions,subscriptionGroupLocalizations"]
        )
    }

    func getSubscriptionGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let groupId = params.arguments?["group_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'group_id' is missing")
        }
        return try await getResource(endpoint: "/v1/subscriptionGroups/\(groupId)", key: "group", query: ["include": "subscriptions,subscriptionGroupLocalizations"])
    }

    func submitSubscriptionGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let groupId = params.arguments?["group_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'group_id' is missing")
        }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionGroupSubmissions",
                "relationships": ["subscriptionGroup": ["data": ["type": "subscriptionGroups", "id": groupId]]]
            ]
        ]
        return try await postResource(endpoint: "/v1/subscriptionGroupSubmissions", body: body, key: "submission")
    }

    func getSubscriptionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let localizationId = params.arguments?["localization_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'localization_id' is missing")
        }
        return try await getResource(endpoint: "/v1/subscriptionLocalizations/\(localizationId)", key: "localization", query: ["include": "subscription"])
    }

    func createSubscriptionPrice(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let territoryId = arguments["territory_id"]?.stringValue,
              let pricePointId = arguments["price_point_id"]?.stringValue else {
            return MCPResult.error("Required parameters: subscription_id, territory_id, price_point_id")
        }

        var attributes: [String: Any] = [:]
        if let startDate = arguments["start_date"]?.stringValue {
            attributes["startDate"] = startDate
        }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionPrices",
                "attributes": attributes,
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionId]],
                    "territory": ["data": ["type": "territories", "id": territoryId]],
                    "subscriptionPricePoint": ["data": ["type": "subscriptionPricePoints", "id": pricePointId]]
                ]
            ]
        ]
        return try await postResource(endpoint: "/v1/subscriptionPrices", body: body, key: "price")
    }

    func getSubscriptionPricePoint(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let pricePointId = params.arguments?["price_point_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'price_point_id' is missing")
        }
        do {
            let response = try await httpClient.get(
                "/v1/subscriptionPricePoints/\(pricePointId)",
                parameters: pricePointQuery(limit: nil),
                as: PassthroughAPIResponse.self
            )
            let point = formatSubscriptionPricePoint(response.data, included: IncludedIndex(response.included))
            return MCPResult.jsonObject(["success": true, "price_point": point])
        } catch {
            return MCPResult.error("Failed to get subscription price point: \(error.localizedDescription)")
        }
    }

    func listSubscriptionPricePointEqualizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let pricePointId = arguments["price_point_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'price_point_id' is missing")
        }

        do {
            let response: PassthroughAPIResponse
            let endpoint = "/v1/subscriptionPricePoints/\(pricePointId)/equalizations"
            var query = pricePointQuery(limit: clampedLimit(arguments["limit"]?.intValue, defaultValue: 25, max: 8000))
            if let subscriptionId = arguments["subscription_id"]?.stringValue {
                query["filter[subscription]"] = subscriptionId
            }
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: paginationFilters(from: query)),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: PassthroughAPIResponse.self
                )
            }

            let included = IncludedIndex(response.included)
            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                "price_points": data.map { formatSubscriptionPricePoint($0, included: included) },
                "count": data.count
            ]
            appendNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list subscription price point equalizations: \(error.localizedDescription)")
        }
    }

    func getSubscriptionAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let subscriptionId = params.arguments?["subscription_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'subscription_id' is missing")
        }
        do {
            let response = try await httpClient.get(
                "/v1/subscriptions/\(subscriptionId)/subscriptionAvailability",
                parameters: availabilityQuery(),
                as: PassthroughAPIResponse.self
            )
            let availability = formatAvailability(response.data, included: IncludedIndex(response.included))
            return MCPResult.jsonObject(["success": true, "availability": availability])
        } catch {
            return MCPResult.error("Failed to get subscription availability: \(error.localizedDescription)")
        }
    }

    func setSubscriptionAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let availableInNewTerritories = arguments["available_in_new_territories"]?.boolValue,
              let territoryIds = arguments["territory_ids"]?.arrayValue?.compactMap(\.stringValue) else {
            return MCPResult.error("Required parameters: subscription_id, available_in_new_territories, territory_ids")
        }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionAvailabilities",
                "attributes": ["availableInNewTerritories": availableInNewTerritories],
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionId]],
                    "availableTerritories": ["data": territoryIds.map { ["type": "territories", "id": $0] }]
                ]
            ]
        ]
        return try await postResource(endpoint: "/v1/subscriptionAvailabilities", body: body, key: "availability")
    }

    func listSubscriptionAvailableTerritories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let availabilityId = arguments["availability_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'availability_id' is missing")
        }
        return try await listResources(
            params,
            endpoint: "/v1/subscriptionAvailabilities/\(availabilityId)/availableTerritories",
            key: "territories",
            defaultQuery: ["fields[territories]": "currency"]
        )
    }

    func getSubscriptionPromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let subscriptionId = params.arguments?["subscription_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'subscription_id' is missing")
        }
        return try await getResource(endpoint: "/v1/subscriptions/\(subscriptionId)/promotedPurchase", key: "promoted_purchase", query: ["include": "subscription"])
    }

    func getSubscriptionsInventory(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }
        do {
            let groups: PassthroughAPIResponse = try await httpClient.get(
                "/v1/apps/\(appId)/subscriptionGroups",
                parameters: [
                    "include": "subscriptions",
                    "limit": String(clampedLimit(arguments["limit"]?.intValue, defaultValue: 200, max: 200))
                ],
                as: PassthroughAPIResponse.self
            )
            let included = IncludedIndex(groups.included)
            let territoryId = arguments["territory_id"]?.stringValue
            var subscriptions: [[String: Any]] = []
            for resource in included.resources(ofType: "subscriptions") {
                subscriptions.append(try await subscriptionInventoryEntry(resource, territoryId: territoryId))
            }
            return MCPResult.jsonObject([
                "success": true,
                "app_id": appId,
                "groups": (groups.data.arrayValue ?? []).map { formatGenericResource($0) },
                "subscriptions": subscriptions,
                "subscription_count": subscriptions.count
            ])
        } catch {
            return MCPResult.error("Failed to build subscription inventory: \(error.localizedDescription)")
        }
    }

    private func subscriptionInventoryEntry(_ resource: JSONValue, territoryId: String?) async throws -> [String: Any] {
        var entry = formatGenericResource(resource)
        guard let subscriptionId = resource.id else {
            return entry
        }

        do {
            let availability: PassthroughAPIResponse = try await httpClient.get(
                "/v1/subscriptions/\(subscriptionId)/subscriptionAvailability",
                parameters: availabilityQuery(),
                as: PassthroughAPIResponse.self
            )
            entry["availability"] = formatAvailability(availability.data, included: IncludedIndex(availability.included))
        } catch {
            entry["availability_error"] = error.localizedDescription
        }

        if let territoryId {
            do {
                let prices: PassthroughAPIResponse = try await httpClient.get(
                    "/v1/subscriptions/\(subscriptionId)/prices",
                    parameters: subscriptionPriceQuery(arguments: ["territory_id": .string(territoryId)], maxLimit: 200).merging(["filter[territory]": territoryId]) { _, new in new },
                    as: PassthroughAPIResponse.self
                )
                let formatted = (prices.data.arrayValue ?? []).map {
                    formatSubscriptionPrice($0, included: IncludedIndex(prices.included))
                }
                let split = splitCurrentAndScheduledSubscriptionPrices(formatted)
                entry["current_price"] = split.current ?? NSNull()
                entry["scheduled_prices"] = split.scheduled
            } catch {
                entry["pricing_error"] = error.localizedDescription
            }
        }

        return entry
    }

    func getSubscriptionPricingSummary(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let territoryId = arguments["territory_id"]?.stringValue else {
            return MCPResult.error("Required parameters: subscription_id, territory_id")
        }
        do {
            let prices: PassthroughAPIResponse = try await httpClient.get(
                "/v1/subscriptions/\(subscriptionId)/prices",
                parameters: subscriptionPriceQuery(arguments: ["territory_id": .string(territoryId)], maxLimit: 200).merging(["filter[territory]": territoryId]) { _, new in new },
                as: PassthroughAPIResponse.self
            )
            let included = IncludedIndex(prices.included)
            let formatted = (prices.data.arrayValue ?? []).map { formatSubscriptionPrice($0, included: included) }
            let split = splitCurrentAndScheduledSubscriptionPrices(formatted)
            return MCPResult.jsonObject([
                "success": true,
                "subscription_id": subscriptionId,
                "territory_id": territoryId,
                "current_price": split.current ?? NSNull(),
                "scheduled_prices": split.scheduled,
                "price_count": formatted.count
            ])
        } catch {
            return MCPResult.error("Failed to summarize subscription pricing: \(error.localizedDescription)")
        }
    }

    private func splitCurrentAndScheduledSubscriptionPrices(_ prices: [[String: Any]]) -> (current: [String: Any]?, scheduled: [[String: Any]]) {
        let today = Self.utcDayFormatter.string(from: Date())
        let current = prices
            .filter { ($0["start_date"] as? String ?? "") <= today }
            .sorted { ($0["start_date"] as? String ?? "") > ($1["start_date"] as? String ?? "") }
            .first
        let scheduled = prices
            .filter { ($0["start_date"] as? String ?? "") > today }
            .sorted { ($0["start_date"] as? String ?? "") < ($1["start_date"] as? String ?? "") }
        return (current, scheduled)
    }

    func prepareSubscriptionOfferPrices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let territoryId = arguments["territory_id"]?.stringValue,
              let mode = arguments["mode"]?.stringValue else {
            return MCPResult.error("Required parameters: subscription_id, territory_id, mode")
        }
        do {
            let points: PassthroughAPIResponse = try await httpClient.get(
                "/v1/subscriptions/\(subscriptionId)/pricePoints",
                parameters: [
                    "filter[territory]": territoryId,
                    "include": "territory",
                    "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations",
                    "fields[territories]": "currency",
                    "limit": "8000"
                ],
                as: PassthroughAPIResponse.self
            )
            let included = IncludedIndex(points.included)
            var candidates = (points.data.arrayValue ?? []).map { formatSubscriptionPricePoint($0, included: included) }
            if let customerPrice = arguments["customer_price"]?.stringValue {
                candidates = candidates.filter { ($0["customer_price"] as? String) == customerPrice }
            }
            return MCPResult.jsonObject([
                "success": true,
                "subscription_id": subscriptionId,
                "territory_id": territoryId,
                "mode": mode,
                "requires_price_point": mode != "FREE_TRIAL",
                "candidates": candidates,
                "count": candidates.count
            ])
        } catch {
            return MCPResult.error("Failed to prepare offer prices: \(error.localizedDescription)")
        }
    }

    func forwardSubscriptionCommerceTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "subscriptions_list_intro_offers":
            return try await listSubscriptionCommerceResources(
                params,
                endpointSuffix: "introductoryOffers",
                key: "introductory_offers",
                defaultQuery: [
                    "include": "territory,subscriptionPricePoint",
                    "fields[subscriptionIntroductoryOffers]": "startDate,endDate,duration,offerMode,numberOfPeriods,territory,subscriptionPricePoint",
                    "fields[territories]": "currency",
                    "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations"
                ]
            )
        case "subscriptions_list_promotional_offers":
            return try await listSubscriptionCommerceResources(
                params,
                endpointSuffix: "promotionalOffers",
                key: "promotional_offers",
                defaultQuery: [
                    "include": "prices",
                    "fields[subscriptionPromotionalOffers]": "duration,name,numberOfPeriods,offerCode,offerMode,prices",
                    "limit[prices]": "50"
                ]
            )
        case "subscriptions_list_offer_codes":
            return try await listSubscriptionCommerceResources(
                params,
                endpointSuffix: "offerCodes",
                key: "offer_codes",
                defaultQuery: [
                    "include": "oneTimeUseCodes,customCodes,prices",
                    "fields[subscriptionOfferCodes]": "name,customerEligibilities,offerEligibility,duration,offerMode,numberOfPeriods,totalNumberOfCodes,productionCodeCount,sandboxCodeCount,active,autoRenewEnabled,oneTimeUseCodes,customCodes,prices",
                    "limit[oneTimeUseCodes]": "50",
                    "limit[customCodes]": "50",
                    "limit[prices]": "50"
                ]
            )
        case "subscriptions_get_offer_code":
            return try await getSubscriptionOfferCode(params)
        case "subscriptions_list_offer_code_prices":
            return try await listSubscriptionOfferPrices(params, idKey: "offer_code_id", endpointPrefix: "/v1/subscriptionOfferCodes", fieldsKey: "subscriptionOfferCodePrices")
        case "subscriptions_list_promotional_offer_prices":
            return try await listSubscriptionOfferPrices(params, idKey: "promotional_offer_id", endpointPrefix: "/v1/subscriptionPromotionalOffers", fieldsKey: "subscriptionPromotionalOfferPrices")
        case "subscriptions_list_winback_offer_prices":
            return try await listSubscriptionOfferPrices(params, idKey: "winback_offer_id", endpointPrefix: "/v1/winBackOffers", fieldsKey: "winBackOfferPrices")
        case "subscriptions_get_one_time_code":
            return try await getSubscriptionOneTimeCode(params)
        case "subscriptions_get_one_time_code_values":
            return try await getSubscriptionOneTimeCodeValues(params)
        case "subscriptions_update_custom_code":
            return try await updateSubscriptionCustomCode(params)
        case "subscriptions_get_winback_offer":
            return try await getSubscriptionWinBackOffer(params)
        default:
            break
        }

        guard let oldName = oldToolName(for: params.name) else {
            return MCPResult.error("Unknown tool: \(params.name)")
        }
        let remapped = remapArgumentsForLegacyCommerceTool(params.name, params.arguments ?? [:])
        return try await legacyWorker(for: oldName).handleTool(CallTool.Parameters(name: oldName, arguments: remapped))
    }

    private func listSubscriptionCommerceResources(
        _ params: CallTool.Parameters,
        endpointSuffix: String,
        key: String,
        defaultQuery: [String: String]
    ) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'subscription_id' is missing")
        }

        do {
            let response: PassthroughAPIResponse
            let endpoint = "/v1/subscriptions/\(subscriptionId)/\(endpointSuffix)"
            var query = defaultQuery
            query["limit"] = String(clampedLimit(arguments["limit"]?.intValue, defaultValue: 25, max: 200))
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: paginationFilters(from: query)),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: PassthroughAPIResponse.self
                )
            }

            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                key: data.map { formatGenericResource($0) },
                "count": data.count
            ]
            appendNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list \(key): \(error.localizedDescription)")
        }
    }

    private func getSubscriptionOfferCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let offerCodeId = params.arguments?["offer_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'offer_code_id' is missing")
        }
        return try await getResource(endpoint: "/v1/subscriptionOfferCodes/\(offerCodeId)", key: "offer_code")
    }

    private func listSubscriptionOfferPrices(
        _ params: CallTool.Parameters,
        idKey: String,
        endpointPrefix: String,
        fieldsKey: String
    ) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let ownerId = arguments[idKey]?.stringValue else {
            return MCPResult.error("Required parameter '\(idKey)' is missing")
        }

        do {
            let response: PassthroughAPIResponse
            let endpoint = "\(endpointPrefix)/\(ownerId)/prices"
            var query = subscriptionOfferPriceQuery(arguments: arguments, fieldsKey: fieldsKey)
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: paginationFilters(from: query)),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: PassthroughAPIResponse.self
                )
            }

            let included = IncludedIndex(response.included)
            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                "prices": data.map { formatSubscriptionOfferPrice($0, included: included) },
                "count": data.count
            ]
            appendNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list subscription offer prices: \(error.localizedDescription)")
        }
    }

    private func getSubscriptionOneTimeCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let oneTimeCodeId = params.arguments?["one_time_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'one_time_code_id' is missing")
        }
        return try await getResource(endpoint: "/v1/subscriptionOfferCodeOneTimeUseCodes/\(oneTimeCodeId)", key: "one_time_code")
    }

    private func getSubscriptionOneTimeCodeValues(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let oneTimeCodeId = params.arguments?["one_time_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'one_time_code_id' is missing")
        }
        return try await listResources(
            params,
            endpoint: "/v1/subscriptionOfferCodeOneTimeUseCodes/\(oneTimeCodeId)/values",
            key: "values",
            defaultQuery: [:]
        )
    }

    private func updateSubscriptionCustomCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let customCodeId = params.arguments?["custom_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'custom_code_id' is missing")
        }
        var data: [String: Any] = [
            "type": "subscriptionOfferCodeCustomCodes",
            "id": customCodeId
        ]
        if let active = params.arguments?["active"]?.boolValue {
            data["attributes"] = ["active": active]
        }
        let body: [String: Any] = ["data": data]
        return try await patchResource(endpoint: "/v1/subscriptionOfferCodeCustomCodes/\(customCodeId)", body: body, key: "custom_code")
    }

    private func getSubscriptionWinBackOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let winbackOfferId = params.arguments?["winback_offer_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'winback_offer_id' is missing")
        }
        return try await getResource(endpoint: "/v1/winBackOffers/\(winbackOfferId)", key: "win_back_offer")
    }

    private func listResources(_ params: CallTool.Parameters, endpoint: String, key: String, defaultQuery: [String: String]) async throws -> CallTool.Result {
        do {
            let response: PassthroughAPIResponse
            var query = defaultQuery
            query["limit"] = String(clampedLimit(params.arguments?["limit"]?.intValue, defaultValue: 25, max: 200))

            if let nextUrl = try paginationURL(from: params.arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: endpoint, requiredParameters: paginationFilters(from: query)),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: PassthroughAPIResponse.self)
            }
            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                key: data.map { formatGenericResource($0) },
                "count": data.count
            ]
            appendNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list \(key): \(error.localizedDescription)")
        }
    }

    private func getResource(endpoint: String, key: String, query: [String: String] = [:]) async throws -> CallTool.Result {
        do {
            let response = try await httpClient.get(endpoint, parameters: query, as: PassthroughAPIResponse.self)
            return MCPResult.jsonObject(["success": true, key: formatGenericResource(response.data)])
        } catch {
            return MCPResult.error("Failed to get \(key): \(error.localizedDescription)")
        }
    }

    private func postResource(endpoint: String, body: [String: Any], key: String) async throws -> CallTool.Result {
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let responseData = try await httpClient.post(endpoint, body: data)
            let response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
            return MCPResult.jsonObject(["success": true, key: formatGenericResource(response.data)])
        } catch {
            return MCPResult.error("Failed to create \(key): \(error.localizedDescription)")
        }
    }

    private func patchResource(endpoint: String, body: [String: Any], key: String) async throws -> CallTool.Result {
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let responseData = try await httpClient.patch(endpoint, body: data)
            let response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
            return MCPResult.jsonObject(["success": true, key: formatGenericResource(response.data)])
        } catch {
            return MCPResult.error("Failed to update \(key): \(error.localizedDescription)")
        }
    }

    private func subscriptionPriceQuery(arguments: [String: Value], maxLimit: Int) -> [String: String] {
        [
            "include": "territory,subscriptionPricePoint",
            "fields[subscriptionPrices]": "startDate,preserved,territory,subscriptionPricePoint",
            "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations",
            "fields[territories]": "currency",
            "limit": String(clampedLimit(arguments["limit"]?.intValue, defaultValue: 25, max: maxLimit))
        ]
    }

    private func pricePointQuery(limit: Int?) -> [String: String] {
        var query = [
            "include": "territory",
            "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations",
            "fields[territories]": "currency"
        ]
        if let limit {
            query["limit"] = String(limit)
        }
        return query
    }

    private func availabilityQuery() -> [String: String] {
        [
            "include": "availableTerritories",
            "fields[subscriptionAvailabilities]": "availableInNewTerritories,availableTerritories",
            "fields[territories]": "currency",
            "limit[availableTerritories]": "50"
        ]
    }

    private func subscriptionOfferPriceQuery(arguments: [String: Value], fieldsKey: String) -> [String: String] {
        [
            "include": "territory,subscriptionPricePoint",
            "fields[\(fieldsKey)]": "territory,subscriptionPricePoint",
            "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations",
            "fields[territories]": "currency",
            "limit": String(clampedLimit(arguments["limit"]?.intValue, defaultValue: 25, max: 200))
        ]
    }

    private func paginationFilters(from query: [String: String]) -> [String: String] {
        var filters: [String: String] = [:]
        for (name, value) in query where name.hasPrefix("filter[") && name.hasSuffix("]") {
            filters[name] = value
        }
        return filters
    }

    private func clampedLimit(_ value: Int?, defaultValue: Int, max: Int) -> Int {
        min(Swift.max(value ?? defaultValue, 1), max)
    }

    private func appendNext(_ links: JSONValue?, to result: inout [String: Any]) {
        if let next = links?.objectValue?["next"]?.stringValue {
            result["next_url"] = next
        }
    }

    private func formatSubscriptionPrice(_ resource: JSONValue, included: IncludedIndex) -> [String: Any] {
        let pricePointId = resource.relationshipId("subscriptionPricePoint")
        let territoryId = resource.relationshipId("territory")
        let point = pricePointId.flatMap { included.resource(type: "subscriptionPricePoints", id: $0) }
        let territory = territoryId.flatMap { included.resource(type: "territories", id: $0) }
        return [
            "id": resource.id ?? "",
            "type": resource.type ?? "",
            "territory_id": territoryId.jsonSafe,
            "currency": territory?.attributes["currency"]?.stringValue.jsonSafe ?? NSNull(),
            "price_point_id": pricePointId.jsonSafe,
            "customer_price": point?.attributes["customerPrice"]?.scalarAny ?? NSNull(),
            "proceeds": point?.attributes["proceeds"]?.scalarAny ?? NSNull(),
            "proceeds_year2": point?.attributes["proceedsYear2"]?.scalarAny ?? NSNull(),
            "start_date": resource.attributes["startDate"]?.stringValue.jsonSafe ?? NSNull(),
            "preserved": resource.attributes["preserved"]?.boolValue.jsonSafe ?? NSNull()
        ]
    }

    private func formatSubscriptionPricePoint(_ resource: JSONValue, included: IncludedIndex) -> [String: Any] {
        let territoryId = resource.relationshipId("territory")
        let territory = territoryId.flatMap { included.resource(type: "territories", id: $0) }
        return [
            "id": resource.id ?? "",
            "type": resource.type ?? "",
            "territory_id": territoryId.jsonSafe,
            "currency": territory?.attributes["currency"]?.stringValue.jsonSafe ?? NSNull(),
            "price_point_id": resource.id ?? "",
            "customer_price": resource.attributes["customerPrice"]?.scalarAny ?? NSNull(),
            "proceeds": resource.attributes["proceeds"]?.scalarAny ?? NSNull(),
            "proceeds_year2": resource.attributes["proceedsYear2"]?.scalarAny ?? NSNull()
        ]
    }

    private func formatAvailability(_ resource: JSONValue, included: IncludedIndex) -> [String: Any] {
        let territoryIds = resource.relationshipIds("availableTerritories")
        return [
            "id": resource.id ?? "",
            "type": resource.type ?? "",
            "available_in_new_territories": resource.attributes["availableInNewTerritories"]?.boolValue.jsonSafe ?? NSNull(),
            "available_territories": territoryIds.map { id in
                [
                    "id": id,
                    "type": "territories",
                    "currency": included.resource(type: "territories", id: id)?.attributes["currency"]?.stringValue.jsonSafe ?? NSNull()
                ] as [String: Any]
            }
        ]
    }

    private func formatSubscriptionOfferPrice(_ resource: JSONValue, included: IncludedIndex) -> [String: Any] {
        let pricePointId = resource.relationshipId("subscriptionPricePoint")
        let territoryId = resource.relationshipId("territory")
        let point = pricePointId.flatMap { included.resource(type: "subscriptionPricePoints", id: $0) }
        let territory = territoryId.flatMap { included.resource(type: "territories", id: $0) }
        return [
            "id": resource.id ?? "",
            "type": resource.type ?? "",
            "territory_id": territoryId.jsonSafe,
            "currency": territory?.attributes["currency"]?.stringValue.jsonSafe ?? NSNull(),
            "price_point_id": pricePointId.jsonSafe,
            "customer_price": point?.attributes["customerPrice"]?.scalarAny ?? NSNull(),
            "proceeds": point?.attributes["proceeds"]?.scalarAny ?? NSNull(),
            "proceeds_year2": point?.attributes["proceedsYear2"]?.scalarAny ?? NSNull()
        ]
    }

    private func formatGenericResource(_ resource: JSONValue) -> [String: Any] {
        var result: [String: Any] = [
            "id": resource.id ?? "",
            "type": resource.type ?? ""
        ]
        for (key, value) in resource.attributes {
            result[Self.snakeCase(key)] = value.asAny
        }
        for (key, relationship) in resource.relationships {
            if let id = relationship.objectValue?["data"]?.objectValue?["id"]?.stringValue {
                result["\(Self.snakeCase(key))_id"] = id
            } else if let ids = relationship.objectValue?["data"]?.arrayValue?.compactMap({ $0.objectValue?["id"]?.stringValue }), !ids.isEmpty {
                result["\(Self.snakeCase(key))_ids"] = ids
            }
        }
        return result
    }

    private func oldToolName(for name: String) -> String? {
        [
            "subscriptions_list_intro_offers": "intro_offers_list",
            "subscriptions_create_intro_offer": "intro_offers_create",
            "subscriptions_update_intro_offer": "intro_offers_update",
            "subscriptions_delete_intro_offer": "intro_offers_delete",
            "subscriptions_list_promotional_offers": "promo_offers_list",
            "subscriptions_get_promotional_offer": "promo_offers_get",
            "subscriptions_create_promotional_offer": "promo_offers_create",
            "subscriptions_update_promotional_offer": "promo_offers_update",
            "subscriptions_delete_promotional_offer": "promo_offers_delete",
            "subscriptions_list_promotional_offer_prices": "promo_offers_list_prices",
            "subscriptions_list_offer_codes": "offer_codes_list",
            "subscriptions_get_offer_code": "offer_codes_get",
            "subscriptions_create_offer_code": "offer_codes_create",
            "subscriptions_update_offer_code": "offer_codes_update",
            "subscriptions_deactivate_offer_code": "offer_codes_deactivate",
            "subscriptions_list_offer_code_prices": "offer_codes_list_prices",
            "subscriptions_generate_one_time_codes": "offer_codes_generate_one_time",
            "subscriptions_list_one_time_codes": "offer_codes_list_one_time",
            "subscriptions_get_one_time_code": "offer_codes_get_one_time",
            "subscriptions_get_one_time_code_values": "offer_codes_get_one_time_values",
            "subscriptions_create_custom_code": "offer_codes_create_custom_code",
            "subscriptions_get_custom_code": "offer_codes_get_custom_code",
            "subscriptions_update_custom_code": "offer_codes_update_custom_code",
            "subscriptions_deactivate_custom_code": "offer_codes_deactivate_custom_code",
            "subscriptions_list_winback_offers": "winback_list",
            "subscriptions_get_winback_offer": "winback_get",
            "subscriptions_create_winback_offer": "winback_create",
            "subscriptions_update_winback_offer": "winback_update",
            "subscriptions_delete_winback_offer": "winback_delete",
            "subscriptions_list_winback_offer_prices": "winback_list_prices"
        ][name]
    }

    private func legacyWorker(for oldName: String) -> any LegacySubscriptionCommerceWorker {
        if oldName.hasPrefix("intro_offers_") {
            return IntroductoryOffersWorker(httpClient: httpClient)
        }
        if oldName.hasPrefix("promo_offers_") {
            return PromotionalOffersWorker(httpClient: httpClient)
        }
        if oldName.hasPrefix("winback_") {
            return WinBackOffersWorker(httpClient: httpClient)
        }
        return OfferCodesWorker(httpClient: httpClient)
    }

    private func remapArgumentsForLegacyCommerceTool(_ newName: String, _ arguments: [String: Value]) -> [String: Value] {
        var remapped = arguments
        if let pricePoint = remapped.removeValue(forKey: "price_point_id") {
            remapped["subscription_price_point_id"] = pricePoint
        }
        if let intro = remapped.removeValue(forKey: "intro_offer_id") {
            remapped["introductory_offer_id"] = intro
        }
        return remapped
    }

    private static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func snakeCase(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            let character = Character(scalar)
            if CharacterSet.uppercaseLetters.contains(scalar) {
                if !result.isEmpty { result.append("_") }
                result.append(String(character).lowercased())
            } else {
                result.append(character)
            }
        }
        return result
    }
}

private protocol LegacySubscriptionCommerceWorker {
    func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result
}

extension OfferCodesWorker: LegacySubscriptionCommerceWorker {}
extension IntroductoryOffersWorker: LegacySubscriptionCommerceWorker {}
extension PromotionalOffersWorker: LegacySubscriptionCommerceWorker {}
extension WinBackOffersWorker: LegacySubscriptionCommerceWorker {}

private struct IncludedIndex {
    private let resources: [String: JSONValue]

    init(_ included: [JSONValue]?) {
        self.resources = Dictionary(uniqueKeysWithValues: (included ?? []).compactMap { resource in
            guard let type = resource.type, let id = resource.id else { return nil }
            return ("\(type):\(id)", resource)
        })
    }

    func resource(type: String, id: String) -> JSONValue? {
        resources["\(type):\(id)"]
    }

    func resources(ofType type: String) -> [JSONValue] {
        resources.compactMap { key, value in key.hasPrefix("\(type):") ? value : nil }
    }
}

private extension JSONValue {
    var scalarAny: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .object, .array: return asAny
        }
    }

    var id: String? {
        objectValue?["id"]?.stringValue
    }

    var type: String? {
        objectValue?["type"]?.stringValue
    }

    var attributes: [String: JSONValue] {
        objectValue?["attributes"]?.objectValue ?? [:]
    }

    var relationships: [String: JSONValue] {
        objectValue?["relationships"]?.objectValue ?? [:]
    }

    func relationshipId(_ name: String) -> String? {
        relationships[name]?.objectValue?["data"]?.objectValue?["id"]?.stringValue
    }

    func relationshipIds(_ name: String) -> [String] {
        relationships[name]?.objectValue?["data"]?.arrayValue?.compactMap { $0.objectValue?["id"]?.stringValue } ?? []
    }
}

private extension Optional where Wrapped == String {
    var jsonSafe: Any {
        switch self {
        case .some(let value): value
        case .none: NSNull()
        }
    }
}

private extension Optional where Wrapped == Bool {
    var jsonSafe: Any {
        switch self {
        case .some(let value): value
        case .none: NSNull()
        }
    }
}
