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
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/prices"
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
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
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
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/pricePoints"
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
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
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
        do {
            var query = ["include": "subscriptions,subscriptionGroupLocalizations"]
            if let value = try subscriptionCatalogQueryValue(arguments["filter_reference_name"], field: "filter_reference_name") {
                query["filter[referenceName]"] = value
            }
            if let value = try subscriptionCatalogQueryValue(
                arguments["filter_subscription_state"],
                field: "filter_subscription_state",
                allowedValues: Set(Self.subscriptionCatalogStates)
            ) {
                query["filter[subscriptions.state]"] = value
            }
            if let value = try subscriptionCatalogQueryValue(
                arguments["sort"],
                field: "sort",
                allowedValues: Set(Self.subscriptionGroupSortValues)
            ) {
                query["sort"] = value
            }
            return try await listResources(
                params,
                endpoint: "/v1/apps/\(try ASCPathSegment.encode(appId))/subscriptionGroups",
                key: "groups",
                defaultQuery: query
            )
        } catch {
            return MCPResult.error("Failed to list groups: \(error.localizedDescription)")
        }
    }

    func getSubscriptionGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let groupId = params.arguments?["group_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'group_id' is missing")
        }
        return try await getResource(endpoint: "/v1/subscriptionGroups/\(try ASCPathSegment.encode(groupId))", key: "group", query: ["include": "subscriptions,subscriptionGroupLocalizations"])
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
        return try await getResource(endpoint: "/v1/subscriptionLocalizations/\(try ASCPathSegment.encode(localizationId))", key: "localization", query: ["include": "subscription"])
    }

    func createSubscriptionPrice(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let territoryId = arguments["territory_id"]?.stringValue,
              let pricePointId = arguments["price_point_id"]?.stringValue else {
            return MCPResult.error("Required parameters: subscription_id, territory_id, price_point_id")
        }

        var attributes: [String: Any] = [:]
        if let error = setNullableSubscriptionPriceDate(
            arguments["start_date"],
            attribute: "startDate",
            attributes: &attributes
        ) {
            return MCPResult.error(error)
        }
        if let error = setNullableSubscriptionPricePlanType(
            arguments["plan_type"],
            attributes: &attributes
        ) {
            return MCPResult.error(error)
        }
        if let error = setNullableSubscriptionPricePreservation(
            arguments["preserve_current_price"],
            attributes: &attributes
        ) {
            return MCPResult.error(error)
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

    private func setNullableSubscriptionPriceDate(
        _ value: Value?,
        attribute: String,
        attributes: inout [String: Any]
    ) -> String? {
        guard let value else {
            return nil
        }
        if value.isNull {
            attributes[attribute] = NSNull()
            return nil
        }
        guard let string = value.stringValue, isValidSubscriptionPriceDate(string) else {
            return "start_date must be a valid date in YYYY-MM-DD format or null"
        }
        attributes[attribute] = string
        return nil
    }

    private func setNullableSubscriptionPricePlanType(
        _ value: Value?,
        attributes: inout [String: Any]
    ) -> String? {
        guard let value else {
            return nil
        }
        if value.isNull {
            attributes["planType"] = NSNull()
            return nil
        }
        let allowedValues: Set<String> = ["MONTHLY", "UPFRONT"]
        guard let string = value.stringValue, allowedValues.contains(string) else {
            return "plan_type must be null or one of: MONTHLY, UPFRONT"
        }
        attributes["planType"] = string
        return nil
    }

    private func setNullableSubscriptionPricePreservation(
        _ value: Value?,
        attributes: inout [String: Any]
    ) -> String? {
        guard let value else {
            return nil
        }
        if value.isNull {
            attributes["preserveCurrentPrice"] = NSNull()
            return nil
        }
        guard let bool = value.boolValue else {
            return "preserve_current_price must be a boolean or null"
        }
        attributes["preserveCurrentPrice"] = bool
        return nil
    }

    private func isValidSubscriptionPriceDate(_ value: String) -> Bool {
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
        guard let date = calendar.date(from: components) else {
            return false
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    func getSubscriptionPricePoint(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let pricePointId = params.arguments?["price_point_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'price_point_id' is missing")
        }
        do {
            let response = try await httpClient.get(
                "/v1/subscriptionPricePoints/\(try ASCPathSegment.encode(pricePointId))",
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
            let endpoint = "/v1/subscriptionPricePoints/\(try ASCPathSegment.encode(pricePointId))/equalizations"
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
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
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
                "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/subscriptionAvailability",
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
            endpoint: "/v1/subscriptionAvailabilities/\(try ASCPathSegment.encode(availabilityId))/availableTerritories",
            key: "territories",
            defaultQuery: ["fields[territories]": "currency"]
        )
    }

    func getSubscriptionPromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let subscriptionId = params.arguments?["subscription_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'subscription_id' is missing")
        }
        return try await getResource(endpoint: "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/promotedPurchase", key: "promoted_purchase", query: ["include": "subscription"])
    }

    func getSubscriptionsInventory(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }
        do {
            let groups: PassthroughAPIResponse = try await httpClient.get(
                "/v1/apps/\(try ASCPathSegment.encode(appId))/subscriptionGroups",
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
                "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/subscriptionAvailability",
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
                    "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/prices",
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
        do {
            let options = try subscriptionPricingSummaryOptions(params.arguments)
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(options.subscriptionId))/prices"
            let query = subscriptionPricingSummaryQuery(options)
            let scope = PaginationScope(
                path: endpoint,
                requiredParameters: query,
                allowedParameters: Set(query.keys).union(["cursor"]),
                requiredNonEmptyParameters: ["cursor"]
            )

            var records: [SubscriptionPricingRecord] = []
            var recordsByPriceId: [String: SubscriptionPricingRecord] = [:]
            var duplicatesSkipped = 0
            var pagesFetched = 0
            var pageURL = options.nextURL
            var seenPageURLs: Set<String> = []
            if let pageURL {
                seenPageURLs.insert(pageURL)
            }
            var remainingNextURL: String?

            while true {
                let response: PassthroughAPIResponse
                if let pageURL {
                    response = try await httpClient.getPage(pageURL, scope: scope, as: PassthroughAPIResponse.self)
                } else {
                    response = try await httpClient.get(endpoint, parameters: query, as: PassthroughAPIResponse.self)
                }

                guard let resources = response.data.arrayValue else {
                    throw ASCError.parsing("Subscription pricing response data must be an array")
                }
                pagesFetched += 1
                let included = IncludedIndex(response.included)
                for resource in resources {
                    let record = try subscriptionPricingRecord(
                        resource,
                        included: included,
                        territoryId: options.territoryId,
                        requestedPlanType: options.planType
                    )
                    if let existingRecord = recordsByPriceId[record.id] {
                        guard existingRecord == record else {
                            throw ASCError.parsing("Subscription pricing pagination returned conflicting resources for ID '\(record.id)'")
                        }
                        duplicatesSkipped += 1
                        continue
                    }
                    recordsByPriceId[record.id] = record
                    records.append(record)
                }

                guard let nextURL = try subscriptionPricingNextURL(response.links) else {
                    remainingNextURL = nil
                    break
                }
                guard seenPageURLs.insert(nextURL).inserted else {
                    throw ASCError.parsing("Subscription pricing pagination returned a repeated next URL")
                }
                if let maxPages = options.maxPages, pagesFetched >= maxPages {
                    remainingNextURL = nextURL
                    break
                }
                pageURL = nextURL
            }

            let today = Self.currentUTCSubscriptionPricingDay()
            let startedFromContinuation = options.nextURL != nil
            let collectionComplete = !startedFromContinuation && remainingNextURL == nil
            let planKeys = subscriptionPricingPlanKeys(records, requestedPlanType: options.planType)
            let planSummaries = planKeys.map { key in
                subscriptionPricingPlanSummary(
                    records.filter { ($0.planType ?? "") == key },
                    planType: key.isEmpty ? nil : key,
                    asOfDate: today,
                    complete: collectionComplete
                )
            }
            let legacyUnambiguous = collectionComplete && planKeys.count <= 1
            let legacyRecords = legacyUnambiguous ? records : []
            let legacySplit = splitSubscriptionPricingRecords(legacyRecords, asOfDate: today)

            return MCPResult.jsonObject([
                "success": true,
                "subscription_id": options.subscriptionId,
                "territory_id": options.territoryId,
                "plan_type": subscriptionPricingJSONSafe(options.planType),
                "available_plan_types": Array(Set(records.compactMap(\.planType))).sorted(),
                "plan_summaries": planSummaries,
                "legacy_summary_unambiguous": legacyUnambiguous,
                "current_price": subscriptionPricingJSONSafe(legacySplit.current?.jsonObject),
                "effective_prices": legacySplit.effective.map(\.jsonObject),
                "scheduled_prices": legacySplit.scheduled.map(\.jsonObject),
                "undated_prices": legacySplit.undated.map(\.jsonObject),
                "as_of_date": today,
                "price_count": records.count,
                "duplicates_skipped": duplicatesSkipped,
                "pages_fetched": pagesFetched,
                "limit": options.pageLimit,
                "max_pages": subscriptionPricingJSONSafe(options.maxPages),
                "started_from_continuation": startedFromContinuation,
                "continuation_exhausted": remainingNextURL == nil,
                "complete": collectionComplete,
                "truncated": remainingNextURL != nil,
                "next_url": subscriptionPricingJSONSafe(remainingNextURL)
            ])
        } catch {
            return MCPResult.error("Failed to summarize subscription pricing: \(error.localizedDescription)")
        }
    }

    private func subscriptionPricingSummaryOptions(_ arguments: [String: Value]?) throws -> SubscriptionPricingSummaryOptions {
        guard let arguments else {
            throw ASCError.parsing("Required parameters: subscription_id, territory_id")
        }
        let allowedArguments: Set<String> = ["subscription_id", "territory_id", "plan_type", "limit", "max_pages", "next_url"]
        let unexpectedArguments = Set(arguments.keys).subtracting(allowedArguments).sorted()
        guard unexpectedArguments.isEmpty else {
            throw ASCError.parsing("Unsupported parameter(s): \(unexpectedArguments.joined(separator: ", "))")
        }

        guard let rawSubscriptionId = arguments["subscription_id"]?.stringValue else {
            throw ASCError.parsing("subscription_id must be a non-empty string")
        }
        let subscriptionId = rawSubscriptionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subscriptionId.isEmpty else {
            throw ASCError.parsing("subscription_id must be a non-empty string")
        }

        guard let rawTerritoryId = arguments["territory_id"]?.stringValue else {
            throw ASCError.parsing("territory_id must be a three-letter ISO 3166-1 alpha-3 code")
        }
        let territoryId = rawTerritoryId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard territoryId.utf8.count == 3,
              territoryId.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw ASCError.parsing("territory_id must be a three-letter ISO 3166-1 alpha-3 code")
        }

        let planType: String?
        if let value = arguments["plan_type"] {
            guard let rawPlanType = value.stringValue else {
                throw ASCError.parsing("plan_type must be MONTHLY or UPFRONT")
            }
            let normalizedPlanType = rawPlanType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard ["MONTHLY", "UPFRONT"].contains(normalizedPlanType) else {
                throw ASCError.parsing("plan_type must be MONTHLY or UPFRONT")
            }
            planType = normalizedPlanType
        } else {
            planType = nil
        }

        let pageLimit: Int
        if let value = arguments["limit"] {
            guard let limit = value.intValue, (1...200).contains(limit) else {
                throw ASCError.parsing("limit must be an integer from 1 through 200")
            }
            pageLimit = limit
        } else {
            pageLimit = 200
        }

        let maxPages: Int?
        if let value = arguments["max_pages"] {
            guard let limit = value.intValue, (1...100).contains(limit) else {
                throw ASCError.parsing("max_pages must be an integer from 1 through 100")
            }
            maxPages = limit
        } else {
            maxPages = nil
        }

        return SubscriptionPricingSummaryOptions(
            subscriptionId: subscriptionId,
            territoryId: territoryId,
            planType: planType,
            pageLimit: pageLimit,
            maxPages: maxPages,
            nextURL: try paginationURL(from: arguments["next_url"])
        )
    }

    private func subscriptionPricingSummaryQuery(_ options: SubscriptionPricingSummaryOptions) -> [String: String] {
        var query: [String: String] = [
            "filter[territory]": options.territoryId,
            "include": "territory,subscriptionPricePoint",
            "fields[subscriptionPrices]": "startDate,preserved,planType,territory,subscriptionPricePoint",
            "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,equalizations",
            "fields[territories]": "currency",
            "limit": String(options.pageLimit)
        ]
        if let planType = options.planType {
            query["filter[planType]"] = planType
        }
        return query
    }

    private func subscriptionPricingNextURL(_ links: JSONValue?) throws -> String? {
        guard let links, let object = links.objectValue else {
            throw ASCError.parsing("Subscription pricing response is missing the required links object")
        }
        guard let value = object["next"] else {
            return nil
        }
        if value.isNull {
            return nil
        }
        guard let nextURL = value.stringValue,
              !nextURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ASCError.parsing("Subscription pricing links.next must be a non-empty string or null")
        }
        return nextURL
    }

    private func subscriptionPricingRecord(
        _ resource: JSONValue,
        included: IncludedIndex,
        territoryId: String,
        requestedPlanType: String?
    ) throws -> SubscriptionPricingRecord {
        guard resource.type == "subscriptionPrices",
              let id = resource.id,
              !id.isEmpty else {
            throw ASCError.parsing("Subscription pricing response contains an invalid subscriptionPrices resource")
        }
        let resourceTerritoryId = try requiredSubscriptionPricingRelationshipId(
            resource,
            name: "territory",
            expectedType: "territories",
            resourceId: id
        )
        guard resourceTerritoryId == territoryId else {
            throw ASCError.parsing("Subscription price '\(id)' does not belong to requested territory '\(territoryId)'")
        }
        let pricePointId = try requiredSubscriptionPricingRelationshipId(
            resource,
            name: "subscriptionPricePoint",
            expectedType: "subscriptionPricePoints",
            resourceId: id
        )
        guard let pricePoint = included.resource(type: "subscriptionPricePoints", id: pricePointId) else {
            throw ASCError.parsing("Subscription price '\(id)' is missing its included subscription price point")
        }
        guard let territory = included.resource(type: "territories", id: territoryId) else {
            throw ASCError.parsing("Subscription price '\(id)' is missing its included territory")
        }

        let planType: String?
        if let value = resource.attributes["planType"], !value.isNull {
            guard let rawPlanType = value.stringValue,
                  ["MONTHLY", "UPFRONT"].contains(rawPlanType) else {
                throw ASCError.parsing("Subscription price '\(id)' has an unsupported planType")
            }
            planType = rawPlanType
        } else {
            planType = nil
        }
        if let requestedPlanType, planType != requestedPlanType {
            throw ASCError.parsing("Subscription price '\(id)' does not match requested plan_type '\(requestedPlanType)'")
        }

        let startDate: String?
        if let value = resource.attributes["startDate"], !value.isNull {
            guard let rawStartDate = value.stringValue, Self.isValidSubscriptionPricingDate(rawStartDate) else {
                throw ASCError.parsing("Subscription price '\(id)' has an invalid startDate")
            }
            startDate = rawStartDate
        } else {
            startDate = nil
        }

        let preserved: Bool?
        if let value = resource.attributes["preserved"], !value.isNull {
            guard let rawPreserved = value.boolValue else {
                throw ASCError.parsing("Subscription price '\(id)' has an invalid preserved value")
            }
            preserved = rawPreserved
        } else {
            preserved = nil
        }

        return SubscriptionPricingRecord(
            id: id,
            territoryId: territoryId,
            currency: try optionalSubscriptionPricingString(territory.attributes["currency"], field: "currency", resourceId: id),
            pricePointId: pricePointId,
            customerPrice: try optionalSubscriptionPricingString(pricePoint.attributes["customerPrice"], field: "customerPrice", resourceId: id),
            proceeds: try optionalSubscriptionPricingString(pricePoint.attributes["proceeds"], field: "proceeds", resourceId: id),
            proceedsYear2: try optionalSubscriptionPricingString(pricePoint.attributes["proceedsYear2"], field: "proceedsYear2", resourceId: id),
            startDate: startDate,
            preserved: preserved,
            planType: planType
        )
    }

    private func requiredSubscriptionPricingRelationshipId(
        _ resource: JSONValue,
        name: String,
        expectedType: String,
        resourceId: String
    ) throws -> String {
        guard let linkage = resource.relationships[name]?.objectValue?["data"]?.objectValue,
              linkage["type"]?.stringValue == expectedType,
              let id = linkage["id"]?.stringValue,
              !id.isEmpty else {
            throw ASCError.parsing("Subscription price '\(resourceId)' has an invalid \(name) relationship")
        }
        return id
    }

    private func optionalSubscriptionPricingString(_ value: JSONValue?, field: String, resourceId: String) throws -> String? {
        guard let value, !value.isNull else {
            return nil
        }
        guard let string = value.stringValue else {
            throw ASCError.parsing("Subscription price '\(resourceId)' has an invalid \(field) value")
        }
        return string
    }

    private func subscriptionPricingPlanKeys(_ records: [SubscriptionPricingRecord], requestedPlanType: String?) -> [String] {
        var keys = Set(records.map { $0.planType ?? "" })
        if let requestedPlanType {
            keys.insert(requestedPlanType)
        }
        return keys.sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs < rhs
        }
    }

    private func subscriptionPricingPlanSummary(
        _ records: [SubscriptionPricingRecord],
        planType: String?,
        asOfDate: String,
        complete: Bool
    ) -> [String: Any] {
        let split = splitSubscriptionPricingRecords(records, asOfDate: asOfDate)
        return [
            "plan_type": subscriptionPricingJSONSafe(planType),
            "current_price": subscriptionPricingJSONSafe(complete ? split.current?.jsonObject : nil),
            "effective_prices": split.effective.map(\.jsonObject),
            "scheduled_prices": split.scheduled.map(\.jsonObject),
            "undated_prices": split.undated.map(\.jsonObject),
            "price_count": records.count,
            "complete": complete
        ]
    }

    private func splitSubscriptionPricingRecords(
        _ records: [SubscriptionPricingRecord],
        asOfDate: String
    ) -> SubscriptionPricingSplit {
        let past = records
            .filter { ($0.startDate ?? "") <= asOfDate && $0.startDate != nil }
            .sorted {
                if $0.startDate == $1.startDate { return $0.id < $1.id }
                return ($0.startDate ?? "") > ($1.startDate ?? "")
            }
        let scheduled = records
            .filter { ($0.startDate ?? "") > asOfDate }
            .sorted {
                if $0.startDate == $1.startDate { return $0.id < $1.id }
                return ($0.startDate ?? "") < ($1.startDate ?? "")
            }
        let undated = records.filter { $0.startDate == nil }.sorted { $0.id < $1.id }
        return SubscriptionPricingSplit(
            current: past.first ?? undated.first,
            effective: past,
            scheduled: scheduled,
            undated: undated
        )
    }

    private func splitCurrentAndScheduledSubscriptionPrices(_ prices: [[String: Any]]) -> (current: [String: Any]?, scheduled: [[String: Any]]) {
        let today = Self.currentUTCSubscriptionPricingDay()
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
                "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/pricePoints",
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
                    "fields[subscriptionIntroductoryOffers]": "startDate,endDate,targetSubscriptionPlanType,duration,offerMode,numberOfPeriods,territory,subscriptionPricePoint",
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
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/\(try ASCPathSegment.encode(endpointSuffix))"
            var query = defaultQuery
            query["limit"] = String(clampedLimit(arguments["limit"]?.intValue, defaultValue: 25, max: 200))
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
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
        return try await getResource(endpoint: "/v1/subscriptionOfferCodes/\(try ASCPathSegment.encode(offerCodeId))", key: "offer_code")
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
            let endpoint: String
            switch endpointPrefix {
            case "/v1/subscriptionOfferCodes":
                endpoint = "/v1/subscriptionOfferCodes/\(try ASCPathSegment.encode(ownerId))/prices"
            case "/v1/subscriptionPromotionalOffers":
                endpoint = "/v1/subscriptionPromotionalOffers/\(try ASCPathSegment.encode(ownerId))/prices"
            case "/v1/winBackOffers":
                endpoint = "/v1/winBackOffers/\(try ASCPathSegment.encode(ownerId))/prices"
            default:
                return MCPResult.error("Unsupported subscription offer price endpoint")
            }
            var query = subscriptionOfferPriceQuery(arguments: arguments, fieldsKey: fieldsKey)
            if let territoryId = arguments["territory_id"]?.stringValue {
                query["filter[territory]"] = territoryId
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
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
        return try await getResource(endpoint: "/v1/subscriptionOfferCodeOneTimeUseCodes/\(try ASCPathSegment.encode(oneTimeCodeId))", key: "one_time_code")
    }

    private func getSubscriptionOneTimeCodeValues(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let oneTimeCodeId = params.arguments?["one_time_code_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'one_time_code_id' is missing")
        }
        do {
            let data = try await httpClient.getRaw(
                "/v1/subscriptionOfferCodeOneTimeUseCodes/\(try ASCPathSegment.encode(oneTimeCodeId))/values",
                accept: "text/csv"
            )
            guard let csv = String(data: data, encoding: .utf8) else {
                return MCPResult.error("Apple returned one-time code values that are not valid UTF-8 CSV")
            }
            return MCPResult.jsonObject([
                "success": true,
                "one_time_code_id": oneTimeCodeId,
                "media_type": "text/csv",
                "values_csv": csv,
                "byte_count": data.count
            ])
        } catch {
            return MCPResult.error("Failed to get one-time code values: \(error.localizedDescription)")
        }
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
        return try await patchResource(endpoint: "/v1/subscriptionOfferCodeCustomCodes/\(try ASCPathSegment.encode(customCodeId))", body: body, key: "custom_code")
    }

    private func getSubscriptionWinBackOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let winbackOfferId = params.arguments?["winback_offer_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'winback_offer_id' is missing")
        }
        return try await getResource(endpoint: "/v1/winBackOffers/\(try ASCPathSegment.encode(winbackOfferId))", key: "win_back_offer")
    }

    private func listResources(
        _ params: CallTool.Parameters,
        endpoint: String,
        key: String,
        defaultQuery: [String: String]
    ) async throws -> CallTool.Result {
        do {
            let response: PassthroughAPIResponse
            var query = defaultQuery
            query["limit"] = String(clampedLimit(params.arguments?["limit"]?.intValue, defaultValue: 25, max: 200))

            if let nextUrl = try paginationURL(from: params.arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
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
            "fields[subscriptionPrices]": "startDate,preserved,planType,territory,subscriptionPricePoint",
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
            "preserved": resource.attributes["preserved"]?.boolValue.jsonSafe ?? NSNull(),
            "plan_type": resource.attributes["planType"]?.stringValue.jsonSafe ?? NSNull()
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

    private static func currentUTCSubscriptionPricingDay(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func isValidSubscriptionPricingDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        let digitIndexes = [0, 1, 2, 3, 5, 6, 8, 9]
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              digitIndexes.allSatisfy({ (48...57).contains(bytes[$0]) }) else {
            return false
        }
        let year = Int(String(value.prefix(4)))
        let month = Int(String(value.dropFirst(5).prefix(2)))
        let day = Int(String(value.suffix(2)))
        guard let year, let month, let day else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var requestedComponents = DateComponents()
        requestedComponents.year = year
        requestedComponents.month = month
        requestedComponents.day = day
        guard let date = calendar.date(from: requestedComponents) else {
            return false
        }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == year && components.month == month && components.day == day
    }

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

private func subscriptionPricingJSONSafe<T>(_ value: T?) -> Any {
    switch value {
    case .some(let value): return value
    case .none: return NSNull()
    }
}

private struct SubscriptionPricingSummaryOptions: Sendable {
    let subscriptionId: String
    let territoryId: String
    let planType: String?
    let pageLimit: Int
    let maxPages: Int?
    let nextURL: String?
}

private struct SubscriptionPricingRecord: Sendable, Equatable {
    let id: String
    let territoryId: String
    let currency: String?
    let pricePointId: String
    let customerPrice: String?
    let proceeds: String?
    let proceedsYear2: String?
    let startDate: String?
    let preserved: Bool?
    let planType: String?

    var jsonObject: [String: Any] {
        [
            "id": id,
            "type": "subscriptionPrices",
            "territory_id": territoryId,
            "currency": subscriptionPricingJSONSafe(currency),
            "price_point_id": pricePointId,
            "customer_price": subscriptionPricingJSONSafe(customerPrice),
            "proceeds": subscriptionPricingJSONSafe(proceeds),
            "proceeds_year2": subscriptionPricingJSONSafe(proceedsYear2),
            "start_date": subscriptionPricingJSONSafe(startDate),
            "preserved": subscriptionPricingJSONSafe(preserved),
            "plan_type": subscriptionPricingJSONSafe(planType)
        ]
    }
}

private struct SubscriptionPricingSplit: Sendable {
    let current: SubscriptionPricingRecord?
    let effective: [SubscriptionPricingRecord]
    let scheduled: [SubscriptionPricingRecord]
    let undated: [SubscriptionPricingRecord]
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
        var resources: [String: JSONValue] = [:]
        for resource in included ?? [] {
            guard let type = resource.type, let id = resource.id else { continue }
            resources["\(type):\(id)"] = resource
        }
        self.resources = resources
    }

    func resource(type: String, id: String) -> JSONValue? {
        resources["\(type):\(id)"]
    }

    func resources(ofType type: String) -> [JSONValue] {
        resources.compactMap { key, value in key.hasPrefix("\(type):") ? value : nil }
    }
}

private extension JSONValue {
    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

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
