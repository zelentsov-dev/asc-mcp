import Foundation
import MCP

extension InAppPurchasesWorker {
    func listIAPPricePointsV3(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'iap_id' is missing")
        }

        do {
            let response: PassthroughAPIResponse
            var query = iapPricePointQuery(limit: try validatedCommerceLimit(arguments["limit"], defaultValue: 50, maximum: 8000))
            if let territoryId = arguments["territory_id"]?.stringValue ?? arguments["territory"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(
                        path: "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/pricePoints",
                        query: query
                    ),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/pricePoints",
                    parameters: query,
                    as: PassthroughAPIResponse.self
                )
            }

            let included = IAPIncludedIndex(response.included)
            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                "price_points": data.map { formatIAPPricePoint($0, included: included) },
                "count": data.count
            ]
            appendIAPNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list IAP price points: \(error.localizedDescription)")
        }
    }

    func listIAPPricePointEqualizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let pricePointId = arguments["price_point_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'price_point_id' is missing")
        }

        do {
            let response: PassthroughAPIResponse
            var query = iapPricePointQuery(limit: try validatedCommerceLimit(arguments["limit"], defaultValue: 25, maximum: 8000))
            if let iapId = arguments["iap_id"]?.stringValue {
                query["filter[inAppPurchaseV2]"] = iapId
            }
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(
                        path: "/v1/inAppPurchasePricePoints/\(try ASCPathSegment.encode(pricePointId))/equalizations",
                        query: query
                    ),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/inAppPurchasePricePoints/\(try ASCPathSegment.encode(pricePointId))/equalizations",
                    parameters: query,
                    as: PassthroughAPIResponse.self
                )
            }

            let included = IAPIncludedIndex(response.included)
            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                "price_points": data.map { formatIAPPricePoint($0, included: included) },
                "count": data.count
            ]
            appendIAPNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list IAP price point equalizations: \(error.localizedDescription)")
        }
    }

    func getIAPAvailabilityV3(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'iap_id' or 'availability_id' is missing")
        }

        let iapId = arguments["iap_id"]?.stringValue
        let availabilityId = arguments["availability_id"]?.stringValue
        guard (iapId == nil) != (availabilityId == nil) else {
            return MCPResult.error("Exactly one of iap_id or availability_id is required")
        }

        if arguments["include_territories"] != nil,
           arguments["include_territories"]?.boolValue == nil {
            return MCPResult.error("include_territories must be a boolean")
        }
        let includeTerritories = arguments["include_territories"]?.boolValue ?? true
        if !includeTerritories, arguments["territory_limit"] != nil {
            return MCPResult.error("territory_limit requires include_territories=true")
        }
        if arguments["territory_limit"] != nil,
           arguments["territory_limit"]?.intValue == nil {
            return MCPResult.error("territory_limit must be an integer")
        }
        let territoryLimit = arguments["territory_limit"]?.intValue ?? 50
        guard (1...50).contains(territoryLimit) else {
            return MCPResult.error("territory_limit must be between 1 and 50")
        }

        let endpoint: String
        if let iapId {
            endpoint = "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/inAppPurchaseAvailability"
        } else if let availabilityId {
            endpoint = "/v1/inAppPurchaseAvailabilities/\(try ASCPathSegment.encode(availabilityId))"
        } else {
            return MCPResult.error("Required parameter 'iap_id' or 'availability_id' is missing")
        }

        do {
            let response = try await httpClient.get(
                endpoint,
                parameters: iapAvailabilityQuery(
                    includeTerritories: includeTerritories,
                    territoryLimit: territoryLimit
                ),
                as: PassthroughAPIResponse.self
            )
            return MCPResult.jsonObject([
                "success": true,
                "availability": formatIAPAvailability(
                    response.data,
                    included: IAPIncludedIndex(response.included),
                    includeTerritories: includeTerritories
                )
            ])
        } catch {
            return MCPResult.error("Failed to get IAP availability: \(error.localizedDescription)")
        }
    }

    func listIAPAvailableTerritories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let availabilityId = params.arguments?["availability_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'availability_id' is missing")
        }
        return try await listIAPPassthroughResources(
            params,
            endpoint: "/v1/inAppPurchaseAvailabilities/\(try ASCPathSegment.encode(availabilityId))/availableTerritories",
            key: "territories",
            defaultQuery: ["fields[territories]": "currency"],
            includePaginationState: true
        )
    }

    func getIAPPricingSummary(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue,
              let territoryId = arguments["territory_id"]?.stringValue else {
            return MCPResult.error("Required parameters: iap_id, territory_id")
        }

        do {
            let schedule: PassthroughAPIResponse = try await httpClient.get(
                "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/iapPriceSchedule",
                parameters: ["fields[inAppPurchasePriceSchedules]": "baseTerritory,manualPrices,automaticPrices"],
                as: PassthroughAPIResponse.self
            )
            guard let scheduleId = schedule.data.iapResourceId else {
                return MCPResult.error("IAP price schedule response did not include an id")
            }

            let query = iapPriceQuery(territoryId: territoryId)
            let manualResult = try await fetchAllIAPPricingPages(
                endpoint: "/v1/inAppPurchasePriceSchedules/\(try ASCPathSegment.encode(scheduleId))/manualPrices",
                query: query
            )
            let automaticResult = try await fetchAllIAPPricingPages(
                endpoint: "/v1/inAppPurchasePriceSchedules/\(try ASCPathSegment.encode(scheduleId))/automaticPrices",
                query: query
            )

            let manualPrices = manualResult.prices
            let automaticPrices = automaticResult.prices
            let prices = (manualPrices + automaticPrices).sorted {
                ($0["start_date"] as? String ?? "") < ($1["start_date"] as? String ?? "")
            }
            let today = Self.iapUTCDateFormatter.string(from: Date())
            let current = prices
                .filter {
                    let start = $0["start_date"] as? String ?? ""
                    let end = $0["end_date"] as? String
                    return start <= today && (end == nil || end! >= today)
                }
                .sorted { ($0["start_date"] as? String ?? "") > ($1["start_date"] as? String ?? "") }
                .first
            let scheduled = prices
                .filter { ($0["start_date"] as? String ?? "") > today }
                .sorted { ($0["start_date"] as? String ?? "") < ($1["start_date"] as? String ?? "") }

            return MCPResult.jsonObject([
                "success": true,
                "iap_id": iapId,
                "territory_id": territoryId,
                "price_schedule_id": scheduleId,
                "current_price": current ?? NSNull(),
                "scheduled_prices": scheduled,
                "manual_prices": manualPrices,
                "automatic_prices": automaticPrices,
                "manual_pages_fetched": manualResult.pagesFetched,
                "automatic_pages_fetched": automaticResult.pagesFetched,
                "complete": true,
                "truncated": false
            ])
        } catch {
            return MCPResult.error("Failed to summarize IAP pricing: \(error.localizedDescription)")
        }
    }

    private func fetchAllIAPPricingPages(
        endpoint: String,
        query: [String: String]
    ) async throws -> (prices: [[String: Any]], pagesFetched: Int) {
        let scope = iapCommercePaginationScope(path: endpoint, query: query)
        var response = try await httpClient.get(
            endpoint,
            parameters: query,
            as: PassthroughAPIResponse.self
        )
        var prices: [[String: Any]] = []
        var pagesFetched = 0
        var seenNextURLs: Set<String> = []

        while true {
            guard let resources = response.data.arrayValue else {
                throw ASCError.parsing("IAP pricing response data must be an array")
            }
            let included = IAPIncludedIndex(response.included)
            prices.append(contentsOf: resources.map { formatIAPPrice($0, included: included) })
            pagesFetched += 1

            guard let nextURL = try iapPricingNextURL(response.links) else {
                break
            }
            guard seenNextURLs.insert(nextURL).inserted else {
                throw ASCError.parsing("IAP pricing pagination returned a repeated next URL")
            }
            response = try await httpClient.getPage(
                nextURL,
                scope: scope,
                as: PassthroughAPIResponse.self
            )
        }

        return (prices, pagesFetched)
    }

    private func iapPricingNextURL(_ links: JSONValue?) throws -> String? {
        guard let value = links?.objectValue?["next"] else {
            return nil
        }
        if case .null = value {
            return nil
        }
        guard let nextURL = value.stringValue,
              !nextURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ASCError.parsing("IAP pricing links.next must be a non-empty string or null")
        }
        return nextURL
    }

    func prepareIAPOfferPrices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue,
              let territoryId = arguments["territory_id"]?.stringValue else {
            return MCPResult.error("Required parameters: iap_id, territory_id")
        }

        do {
            let response: PassthroughAPIResponse = try await httpClient.get(
                "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/pricePoints",
                parameters: iapPricePointQuery(limit: 8000).merging(["filter[territory]": territoryId]) { _, new in new },
                as: PassthroughAPIResponse.self
            )
            let included = IAPIncludedIndex(response.included)
            var candidates = (response.data.arrayValue ?? []).map { formatIAPPricePoint($0, included: included) }
            if let customerPrice = arguments["customer_price"]?.stringValue {
                candidates = candidates.filter { ($0["customer_price"] as? String) == customerPrice }
            }
            return MCPResult.jsonObject([
                "success": true,
                "iap_id": iapId,
                "territory_id": territoryId,
                "candidates": candidates,
                "count": candidates.count
            ])
        } catch {
            return MCPResult.error("Failed to prepare IAP offer prices: \(error.localizedDescription)")
        }
    }

    func getIAPInventory(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }
        do {
            var query = [
                "include": "inAppPurchaseLocalizations,iapPriceSchedule,inAppPurchaseAvailability,promotedPurchase,offerCodes",
                "fields[inAppPurchases]": "name,productId,inAppPurchaseType,state,reviewNote,familySharable,contentHosting,inAppPurchaseLocalizations,promotedPurchase,iapPriceSchedule,inAppPurchaseAvailability,offerCodes",
                "fields[inAppPurchaseLocalizations]": "name,locale,description,state",
                "fields[inAppPurchasePriceSchedules]": "baseTerritory,manualPrices,automaticPrices",
                "fields[inAppPurchaseAvailabilities]": "availableInNewTerritories,availableTerritories",
                "fields[promotedPurchases]": "visibleForAllUsers,enabled,state"
            ]
            if let value = try iapCatalogQueryValue(arguments["filter_name"], field: "filter_name") {
                query["filter[name]"] = value
            }
            if let value = try iapCatalogQueryValue(arguments["filter_product_id"], field: "filter_product_id") {
                query["filter[productId]"] = value
            }
            if let value = try iapCatalogQueryValue(
                arguments["filter_state"],
                field: "filter_state",
                allowedValues: Set(Self.iapCatalogStates)
            ) {
                query["filter[state]"] = value
            }
            if let value = try iapCatalogQueryValue(
                arguments["filter_type"],
                field: "filter_type",
                allowedValues: Set(Self.iapCatalogTypes)
            ) {
                query["filter[inAppPurchaseType]"] = value
            }
            if let value = try iapCatalogQueryValue(
                arguments["sort"],
                field: "sort",
                allowedValues: Set(Self.iapCatalogSortValues)
            ) {
                query["sort"] = value
            }
            return try await listIAPPassthroughResources(
                params,
                endpoint: "/v1/apps/\(try ASCPathSegment.encode(appId))/inAppPurchasesV2",
                key: "in_app_purchases",
                defaultQuery: query,
                extraResult: ["app_id": appId],
                preserveIncluded: true
            )
        } catch {
            return MCPResult.error("Failed to list in_app_purchases: \(error.localizedDescription)")
        }
    }

    func getIAPPromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let iapId = params.arguments?["iap_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'iap_id' is missing")
        }
        return try await getIAPPassthroughResource(endpoint: "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/promotedPurchase", key: "promoted_purchase")
    }

    func listIAPOfferCodes(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let iapId = params.arguments?["iap_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'iap_id' is missing")
        }
        return try await listIAPPassthroughResources(
            params,
            endpoint: "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/offerCodes",
            key: "offer_codes",
            defaultQuery: [
                "include": "oneTimeUseCodes,customCodes,prices",
                "fields[inAppPurchaseOfferCodes]": "name,customerEligibilities,productionCodeCount,sandboxCodeCount,active,oneTimeUseCodes,customCodes,prices",
                "limit[oneTimeUseCodes]": "50",
                "limit[customCodes]": "50",
                "limit[prices]": "50"
            ]
        )
    }

    func getIAPOfferCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let offerCodeId = params.arguments?["offer_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'offer_code_id' is missing")
        }
        return try await getIAPPassthroughResource(endpoint: "/v1/inAppPurchaseOfferCodes/\(try ASCPathSegment.encode(offerCodeId))", key: "offer_code")
    }

    func createIAPOfferCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue,
              let name = arguments["name"]?.stringValue,
              let eligibilityValues = arguments["customer_eligibilities"]?.arrayValue,
              let territoryValues = arguments["territory_ids"]?.arrayValue,
              let pricePointValues = arguments["price_point_ids"]?.arrayValue else {
            return MCPResult.error("Required parameters: iap_id, name, customer_eligibilities, territory_ids, price_point_ids")
        }
        let eligibilities = eligibilityValues.compactMap(\.stringValue)
        let territoryIds = territoryValues.compactMap(\.stringValue)
        let pricePointIds = pricePointValues.compactMap(\.stringValue)
        guard eligibilities.count == eligibilityValues.count,
              territoryIds.count == territoryValues.count,
              pricePointIds.count == pricePointValues.count else {
            return MCPResult.error("customer_eligibilities, territory_ids, and price_point_ids must contain only strings")
        }
        let allowedEligibilities: Set<String> = ["NON_SPENDER", "ACTIVE_SPENDER", "CHURNED_SPENDER"]
        guard !eligibilities.isEmpty,
              Set(eligibilities).count == eligibilities.count,
              eligibilities.allSatisfy(allowedEligibilities.contains) else {
            return MCPResult.error("customer_eligibilities must contain unique values from: ACTIVE_SPENDER, CHURNED_SPENDER, NON_SPENDER")
        }
        guard territoryIds.count == pricePointIds.count else {
            return MCPResult.error("price_point_ids and territory_ids must have the same count (got \(pricePointIds.count) vs \(territoryIds.count))")
        }
        guard !territoryIds.isEmpty else {
            return MCPResult.error("At least one territory_id and price_point_id are required")
        }

        let priceRefs = territoryIds.indices.map { index in
            ["type": "inAppPurchaseOfferPrices", "id": "${price-\(index)}"]
        }
        let included = territoryIds.indices.map { index in
            [
                "type": "inAppPurchaseOfferPrices",
                "id": "${price-\(index)}",
                "relationships": [
                    "territory": ["data": ["type": "territories", "id": territoryIds[index]]],
                    "pricePoint": ["data": ["type": "inAppPurchasePricePoints", "id": pricePointIds[index]]]
                ]
            ] as [String: Any]
        }
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchaseOfferCodes",
                "attributes": [
                    "name": name,
                    "customerEligibilities": eligibilities
                ],
                "relationships": [
                    "inAppPurchase": ["data": ["type": "inAppPurchases", "id": iapId]],
                    "prices": ["data": priceRefs]
                ]
            ],
            "included": included
        ]
        return try await postIAPPassthroughResource(endpoint: "/v1/inAppPurchaseOfferCodes", body: body, key: "offer_code")
    }

    func updateIAPOfferCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let offerCodeId = params.arguments?["offer_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'offer_code_id' is missing")
        }
        guard let active = iapNullableActive(params.arguments?["active"]) else {
            return MCPResult.error("Required parameter 'active' must be a Boolean or null")
        }
        return try await patchIAPActiveResource(
            endpoint: "/v1/inAppPurchaseOfferCodes/\(try ASCPathSegment.encode(offerCodeId))",
            type: "inAppPurchaseOfferCodes",
            id: offerCodeId,
            active: active,
            key: "offer_code"
        )
    }

    func deactivateIAPOfferCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let offerCodeId = params.arguments?["offer_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'offer_code_id' is missing")
        }
        return try await patchIAPActiveResource(
            endpoint: "/v1/inAppPurchaseOfferCodes/\(try ASCPathSegment.encode(offerCodeId))",
            type: "inAppPurchaseOfferCodes",
            id: offerCodeId,
            active: .value(false),
            key: "offer_code"
        )
    }

    func listIAPOfferCodePrices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'offer_code_id' is missing")
        }

        do {
            let response: PassthroughAPIResponse
            var query = iapOfferPriceQuery(limit: try validatedCommerceLimit(arguments["limit"], defaultValue: 25, maximum: 200))
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(
                        path: "/v1/inAppPurchaseOfferCodes/\(try ASCPathSegment.encode(offerCodeId))/prices",
                        query: query
                    ),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/inAppPurchaseOfferCodes/\(try ASCPathSegment.encode(offerCodeId))/prices",
                    parameters: query,
                    as: PassthroughAPIResponse.self
                )
            }

            let included = IAPIncludedIndex(response.included)
            let data = response.data.arrayValue ?? []
            var result: [String: Any] = [
                "success": true,
                "prices": data.map { formatIAPOfferPrice($0, included: included) },
                "count": data.count
            ]
            appendIAPNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list IAP offer code prices: \(error.localizedDescription)")
        }
    }

    func generateIAPOneTimeCodes(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue,
              let numberOfCodes = arguments["number_of_codes"]?.intValue,
              let expirationDate = arguments["expiration_date"]?.stringValue else {
            return MCPResult.error("Required parameters: offer_code_id, number_of_codes, expiration_date")
        }
        var attributes: [String: Any] = [
            "numberOfCodes": numberOfCodes,
            "expirationDate": expirationDate
        ]
        if let environmentValue = arguments["environment"] {
            if case .null = environmentValue {
                attributes["environment"] = NSNull()
            } else if let environment = environmentValue.stringValue,
                      ["PRODUCTION", "SANDBOX"].contains(environment) {
                attributes["environment"] = environment
            } else {
                return MCPResult.error("environment must be PRODUCTION, SANDBOX, or null")
            }
        }
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchaseOfferCodeOneTimeUseCodes",
                "attributes": attributes,
                "relationships": ["offerCode": ["data": ["type": "inAppPurchaseOfferCodes", "id": offerCodeId]]]
            ]
        ]
        return try await postIAPPassthroughResource(endpoint: "/v1/inAppPurchaseOfferCodeOneTimeUseCodes", body: body, key: "one_time_code")
    }

    func listIAPOneTimeCodes(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let offerCodeId = params.arguments?["offer_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'offer_code_id' is missing")
        }
        return try await listIAPPassthroughResources(
            params,
            endpoint: "/v1/inAppPurchaseOfferCodes/\(try ASCPathSegment.encode(offerCodeId))/oneTimeUseCodes",
            key: "one_time_codes",
            defaultQuery: [:]
        )
    }

    func getIAPOneTimeCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let oneTimeCodeId = params.arguments?["one_time_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'one_time_code_id' is missing")
        }
        return try await getIAPPassthroughResource(endpoint: "/v1/inAppPurchaseOfferCodeOneTimeUseCodes/\(try ASCPathSegment.encode(oneTimeCodeId))", key: "one_time_code")
    }

    func updateIAPOneTimeCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let oneTimeCodeId = params.arguments?["one_time_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'one_time_code_id' is missing")
        }
        guard let active = iapNullableActive(params.arguments?["active"]) else {
            return MCPResult.error("Required parameter 'active' must be a Boolean or null")
        }
        return try await patchIAPActiveResource(
            endpoint: "/v1/inAppPurchaseOfferCodeOneTimeUseCodes/\(try ASCPathSegment.encode(oneTimeCodeId))",
            type: "inAppPurchaseOfferCodeOneTimeUseCodes",
            id: oneTimeCodeId,
            active: active,
            key: "one_time_code"
        )
    }

    func deactivateIAPOneTimeCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let oneTimeCodeId = params.arguments?["one_time_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'one_time_code_id' is missing")
        }
        return try await patchIAPActiveResource(
            endpoint: "/v1/inAppPurchaseOfferCodeOneTimeUseCodes/\(try ASCPathSegment.encode(oneTimeCodeId))",
            type: "inAppPurchaseOfferCodeOneTimeUseCodes",
            id: oneTimeCodeId,
            active: .value(false),
            key: "one_time_code"
        )
    }

    func getIAPOneTimeCodeValues(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let oneTimeCodeId = params.arguments?["one_time_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'one_time_code_id' is missing")
        }
        do {
            let data = try await httpClient.getRaw(
                "/v1/inAppPurchaseOfferCodeOneTimeUseCodes/\(try ASCPathSegment.encode(oneTimeCodeId))/values",
                accept: "text/csv"
            )
            return MCPResult.jsonObject([
                "success": true,
                "one_time_code_id": oneTimeCodeId,
                "media_type": "text/csv",
                "values_csv": String(data: data, encoding: .utf8) ?? NSNull(),
                "values_base64": data.base64EncodedString(),
                "byte_count": data.count
            ])
        } catch {
            return MCPResult.error("Failed to get one-time code values: \(error.localizedDescription)")
        }
    }

    func createIAPCustomCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue,
              let customCode = arguments["custom_code"]?.stringValue,
              let numberOfCodes = arguments["number_of_codes"]?.intValue else {
            return MCPResult.error("Required parameters: offer_code_id, custom_code, number_of_codes")
        }
        var attributes: [String: Any] = [
            "customCode": customCode,
            "numberOfCodes": numberOfCodes
        ]
        if let expirationDate = arguments["expiration_date"]?.stringValue {
            attributes["expirationDate"] = expirationDate
        }
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchaseOfferCodeCustomCodes",
                "attributes": attributes,
                "relationships": ["offerCode": ["data": ["type": "inAppPurchaseOfferCodes", "id": offerCodeId]]]
            ]
        ]
        return try await postIAPPassthroughResource(endpoint: "/v1/inAppPurchaseOfferCodeCustomCodes", body: body, key: "custom_code")
    }

    func getIAPCustomCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let customCodeId = params.arguments?["custom_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'custom_code_id' is missing")
        }
        return try await getIAPPassthroughResource(endpoint: "/v1/inAppPurchaseOfferCodeCustomCodes/\(try ASCPathSegment.encode(customCodeId))", key: "custom_code")
    }

    func updateIAPCustomCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let customCodeId = params.arguments?["custom_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'custom_code_id' is missing")
        }
        guard let active = iapNullableActive(params.arguments?["active"]) else {
            return MCPResult.error("Required parameter 'active' must be a Boolean or null")
        }
        return try await patchIAPActiveResource(
            endpoint: "/v1/inAppPurchaseOfferCodeCustomCodes/\(try ASCPathSegment.encode(customCodeId))",
            type: "inAppPurchaseOfferCodeCustomCodes",
            id: customCodeId,
            active: active,
            key: "custom_code"
        )
    }

    func deactivateIAPCustomCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let customCodeId = params.arguments?["custom_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'custom_code_id' is missing")
        }
        return try await patchIAPActiveResource(
            endpoint: "/v1/inAppPurchaseOfferCodeCustomCodes/\(try ASCPathSegment.encode(customCodeId))",
            type: "inAppPurchaseOfferCodeCustomCodes",
            id: customCodeId,
            active: .value(false),
            key: "custom_code"
        )
    }

    private func listIAPPassthroughResources(
        _ params: CallTool.Parameters,
        endpoint: String,
        key: String,
        defaultQuery: [String: String],
        extraResult: [String: Any] = [:],
        preserveIncluded: Bool = false,
        includePaginationState: Bool = false
    ) async throws -> CallTool.Result {
        do {
            let response: PassthroughAPIResponse
            var query = defaultQuery
            query["limit"] = String(try validatedCommerceLimit(params.arguments?["limit"], defaultValue: 25, maximum: 200))
            if let nextUrl = try paginationURL(from: params.arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(path: endpoint, query: query),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: PassthroughAPIResponse.self)
            }
            let data = response.data.arrayValue ?? []
            var result = extraResult
            result["success"] = true
            result[key] = data.map { formatIAPGenericResource($0) }
            result["count"] = data.count
            if preserveIncluded {
                let included = response.included ?? []
                result["included"] = included.map(\.asAny)
                result["included_count"] = included.count
            }
            if includePaginationState {
                result["page_is_last"] = response.links?.objectValue?["next"]?.stringValue == nil
            }
            appendIAPNext(response.links, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list \(key): \(error.localizedDescription)")
        }
    }

    private func getIAPPassthroughResource(endpoint: String, key: String, query: [String: String] = [:]) async throws -> CallTool.Result {
        do {
            let response = try await httpClient.get(endpoint, parameters: query, as: PassthroughAPIResponse.self)
            return MCPResult.jsonObject(["success": true, key: formatIAPGenericResource(response.data)])
        } catch {
            return MCPResult.error("Failed to get \(key): \(error.localizedDescription)")
        }
    }

    private func postIAPPassthroughResource(endpoint: String, body: [String: Any], key: String) async throws -> CallTool.Result {
        guard let requestData = body["data"] as? [String: Any],
              let expectedType = requestData["type"] as? String else {
            return MCPResult.error("Failed to create \(key): request resource type is missing")
        }

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode \(key)")
        }

        let responseData: Data
        do {
            responseData = try await httpClient.post(endpoint, body: data)
        } catch {
            return MCPResult.error(error, prefix: "Failed to create \(key)")
        }

        do {
            let response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
            guard let responseType = response.data.iapResourceType,
                  let responseID = response.data.iapResourceId else {
                throw ASCError.parsing("POST response resource identity does not match the request contract")
            }
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: responseType,
                id: responseID,
                expectedType: expectedType,
                context: "IAP commerce POST response"
            )
            return MCPResult.jsonObject(["success": true, key: formatIAPGenericResource(response.data)])
        } catch {
            return MCPResult.error(
                iapCommittedUnverifiedMutation(method: "POST", statusCode: 201, error: error),
                prefix: "Failed to verify created \(key)"
            )
        }
    }

    private func patchIAPActiveResource(endpoint: String, type: String, id: String, active: ASCNullable<Bool>, key: String) async throws -> CallTool.Result {
        let encodedActive: Any
        switch active {
        case .value(let value): encodedActive = value
        case .null: encodedActive = NSNull()
        }
        let data: [String: Any] = [
            "type": type,
            "id": id,
            "attributes": ["active": encodedActive]
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: ["data": data])
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode \(key)")
        }

        let responseData: Data
        do {
            responseData = try await httpClient.patch(endpoint, body: body)
        } catch {
            return MCPResult.error(error, prefix: "Failed to update \(key)")
        }

        do {
            let response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
            guard let responseType = response.data.iapResourceType,
                  let responseID = response.data.iapResourceId else {
                throw ASCError.parsing("PATCH response resource identity does not match the request contract")
            }
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: responseType,
                id: responseID,
                expectedType: type,
                expectedID: id,
                context: "IAP commerce PATCH response"
            )
            return MCPResult.jsonObject(["success": true, key: formatIAPGenericResource(response.data)])
        } catch {
            return MCPResult.error(
                iapCommittedUnverifiedMutation(method: "PATCH", statusCode: 200, error: error),
                prefix: "Failed to verify updated \(key)"
            )
        }
    }

    private func iapCommittedUnverifiedMutation(method: String, statusCode: Int, error: Error) -> ASCError {
        let cause = error as? ASCError ?? .parsing(error.localizedDescription)
        return .mutationCommittedUnverified(
            method: method,
            expectedStatusCode: statusCode,
            actualStatusCode: statusCode,
            cause: cause
        )
    }

    private func iapNullableActive(_ value: Value?) -> ASCNullable<Bool>? {
        guard let value else {
            return nil
        }
        if case .null = value {
            return .null
        }
        guard let bool = value.boolValue else {
            return nil
        }
        return .value(bool)
    }

    private func iapPricePointQuery(limit: Int) -> [String: String] {
        [
            "include": "territory",
            "fields[inAppPurchasePricePoints]": "customerPrice,proceeds,territory,equalizations",
            "fields[territories]": "currency",
            "limit": String(limit)
        ]
    }

    private func iapPriceQuery(territoryId: String) -> [String: String] {
        [
            "filter[territory]": territoryId,
            "include": "inAppPurchasePricePoint,territory",
            "fields[inAppPurchasePrices]": "startDate,endDate,manual,inAppPurchasePricePoint,territory",
            "fields[inAppPurchasePricePoints]": "customerPrice,proceeds,territory,equalizations",
            "fields[territories]": "currency",
            "limit": "200"
        ]
    }

    private func iapOfferPriceQuery(limit: Int) -> [String: String] {
        [
            "include": "territory,pricePoint",
            "fields[inAppPurchaseOfferPrices]": "territory,pricePoint",
            "fields[inAppPurchasePricePoints]": "customerPrice,proceeds,territory,equalizations",
            "fields[territories]": "currency",
            "limit": String(limit)
        ]
    }

    private func iapAvailabilityQuery(includeTerritories: Bool, territoryLimit: Int) -> [String: String] {
        guard includeTerritories else {
            return ["fields[inAppPurchaseAvailabilities]": "availableInNewTerritories,availableTerritories"]
        }
        return [
            "include": "availableTerritories",
            "fields[inAppPurchaseAvailabilities]": "availableInNewTerritories,availableTerritories",
            "fields[territories]": "currency",
            "limit[availableTerritories]": String(territoryLimit)
        ]
    }

    private func appendIAPNext(_ links: JSONValue?, to result: inout [String: Any]) {
        if let next = links?.objectValue?["next"]?.stringValue {
            result["next_url"] = next
        }
    }

    private func formatIAPPricePoint(_ resource: JSONValue, included: IAPIncludedIndex) -> [String: Any] {
        let territoryId = resource.iapRelationshipId("territory")
        let territory = territoryId.flatMap { included.resource(type: "territories", id: $0) }
        return [
            "id": resource.iapResourceId ?? "",
            "type": resource.iapResourceType ?? "",
            "territory_id": territoryId.iapJSONSafe,
            "currency": territory?.iapAttributes["currency"]?.stringValue.iapJSONSafe ?? NSNull(),
            "price_point_id": resource.iapResourceId ?? "",
            "customer_price": resource.iapAttributes["customerPrice"]?.iapScalarAny ?? NSNull(),
            "proceeds": resource.iapAttributes["proceeds"]?.iapScalarAny ?? NSNull()
        ]
    }

    private func formatIAPPrice(_ resource: JSONValue, included: IAPIncludedIndex) -> [String: Any] {
        let pricePointId = resource.iapRelationshipId("inAppPurchasePricePoint")
        let territoryId = resource.iapRelationshipId("territory")
        let point = pricePointId.flatMap { included.resource(type: "inAppPurchasePricePoints", id: $0) }
        let territory = territoryId.flatMap { included.resource(type: "territories", id: $0) }
        return [
            "id": resource.iapResourceId ?? "",
            "type": resource.iapResourceType ?? "",
            "territory_id": territoryId.iapJSONSafe,
            "currency": territory?.iapAttributes["currency"]?.stringValue.iapJSONSafe ?? NSNull(),
            "price_point_id": pricePointId.iapJSONSafe,
            "customer_price": point?.iapAttributes["customerPrice"]?.iapScalarAny ?? NSNull(),
            "proceeds": point?.iapAttributes["proceeds"]?.iapScalarAny ?? NSNull(),
            "start_date": resource.iapAttributes["startDate"]?.stringValue.iapJSONSafe ?? NSNull(),
            "end_date": resource.iapAttributes["endDate"]?.stringValue.iapJSONSafe ?? NSNull(),
            "manual": resource.iapAttributes["manual"]?.boolValue.iapJSONSafe ?? NSNull()
        ]
    }

    private func formatIAPOfferPrice(_ resource: JSONValue, included: IAPIncludedIndex) -> [String: Any] {
        let pricePointId = resource.iapRelationshipId("pricePoint")
        let territoryId = resource.iapRelationshipId("territory")
        let point = pricePointId.flatMap { included.resource(type: "inAppPurchasePricePoints", id: $0) }
        let territory = territoryId.flatMap { included.resource(type: "territories", id: $0) }
        return [
            "id": resource.iapResourceId ?? "",
            "type": resource.iapResourceType ?? "",
            "territory_id": territoryId.iapJSONSafe,
            "currency": territory?.iapAttributes["currency"]?.stringValue.iapJSONSafe ?? NSNull(),
            "price_point_id": pricePointId.iapJSONSafe,
            "customer_price": point?.iapAttributes["customerPrice"]?.iapScalarAny ?? NSNull(),
            "proceeds": point?.iapAttributes["proceeds"]?.iapScalarAny ?? NSNull()
        ]
    }

    private func formatIAPAvailability(
        _ resource: JSONValue,
        included: IAPIncludedIndex,
        includeTerritories: Bool
    ) -> [String: Any] {
        let territoryIds = resource.iapRelationshipIds("availableTerritories")
        let expandedTerritories = includeTerritories ? territoryIds.compactMap { id -> [String: Any]? in
            guard let territory = included.resource(type: "territories", id: id) else { return nil }
            return [
                "id": id,
                "type": "territories",
                "currency": territory.iapAttributes["currency"]?.stringValue.iapJSONSafe ?? NSNull()
            ]
        } : []
        let relationship = resource.iapRelationships["availableTerritories"]
        let paging = relationship?.objectValue?["meta"]?.objectValue?["paging"]?.objectValue
        let total = paging?["total"]?.iapIntValue
        let limit = paging?["limit"]?.iapIntValue
        let nextCursor = paging?["nextCursor"]?.stringValue
        let projectionComplete = includeTerritories
            && paging != nil
            && nextCursor == nil
            && (total.map { expandedTerritories.count >= $0 } ?? true)
        let hasMore: Any
        if includeTerritories {
            hasMore = !projectionComplete
        } else {
            hasMore = NSNull()
        }
        let continuationTool: Any
        let continuationArguments: Any
        if projectionComplete {
            continuationTool = NSNull()
            continuationArguments = NSNull()
        } else {
            continuationTool = "iap_list_available_territories"
            continuationArguments = ["availability_id": resource.iapResourceId ?? ""]
        }

        var result: [String: Any] = [
            "id": resource.iapResourceId ?? "",
            "type": resource.iapResourceType ?? "",
            "available_in_new_territories": resource.iapAttributes["availableInNewTerritories"]?.boolValue.iapJSONSafe ?? NSNull(),
            "territory_projection": [
                "requested": includeTerritories,
                "returned": expandedTerritories.count,
                "total": total.iapJSONSafe,
                "limit": limit.iapJSONSafe,
                "has_more": hasMore,
                "complete": projectionComplete,
                "continuation_tool": continuationTool,
                "continuation_arguments": continuationArguments
            ] as [String: Any]
        ]
        if includeTerritories {
            result["available_territories"] = expandedTerritories
        }
        return result
    }

    private func formatIAPGenericResource(_ resource: JSONValue) -> [String: Any] {
        var result: [String: Any] = [
            "id": resource.iapResourceId ?? "",
            "type": resource.iapResourceType ?? ""
        ]
        for (key, value) in resource.iapAttributes {
            result[Self.iapSnakeCase(key)] = value.asAny
        }
        for (key, relationship) in resource.iapRelationships {
            if let id = relationship.objectValue?["data"]?.objectValue?["id"]?.stringValue {
                result["\(Self.iapSnakeCase(key))_id"] = id
            } else if let ids = relationship.objectValue?["data"]?.arrayValue?.compactMap({ $0.objectValue?["id"]?.stringValue }), !ids.isEmpty {
                result["\(Self.iapSnakeCase(key))_ids"] = ids
            }
        }
        return result
    }

    private static let iapUTCDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func iapSnakeCase(_ string: String) -> String {
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

private struct IAPIncludedIndex {
    private let resources: [String: JSONValue]

    init(_ included: [JSONValue]?) {
        self.resources = Dictionary(uniqueKeysWithValues: (included ?? []).compactMap { resource in
            guard let type = resource.iapResourceType, let id = resource.iapResourceId else { return nil }
            return ("\(type):\(id)", resource)
        })
    }

    func resource(type: String, id: String) -> JSONValue? {
        resources["\(type):\(id)"]
    }
}

private extension JSONValue {
    var iapIntValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    var iapScalarAny: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .object, .array: return asAny
        }
    }

    var iapResourceId: String? {
        objectValue?["id"]?.stringValue
    }

    var iapResourceType: String? {
        objectValue?["type"]?.stringValue
    }

    var iapAttributes: [String: JSONValue] {
        objectValue?["attributes"]?.objectValue ?? [:]
    }

    var iapRelationships: [String: JSONValue] {
        objectValue?["relationships"]?.objectValue ?? [:]
    }

    func iapRelationshipId(_ name: String) -> String? {
        iapRelationships[name]?.objectValue?["data"]?.objectValue?["id"]?.stringValue
    }

    func iapRelationshipIds(_ name: String) -> [String] {
        iapRelationships[name]?.objectValue?["data"]?.arrayValue?.compactMap { $0.objectValue?["id"]?.stringValue } ?? []
    }
}

private extension Optional where Wrapped == String {
    var iapJSONSafe: Any {
        switch self {
        case .some(let value): value
        case .none: NSNull()
        }
    }
}

private extension Optional where Wrapped == Bool {
    var iapJSONSafe: Any {
        switch self {
        case .some(let value): value
        case .none: NSNull()
        }
    }
}

private extension Optional where Wrapped == Int {
    var iapJSONSafe: Any {
        switch self {
        case .some(let value): value
        case .none: NSNull()
        }
    }
}
