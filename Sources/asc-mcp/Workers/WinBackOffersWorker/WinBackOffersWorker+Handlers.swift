import Foundation
import MCP

// MARK: - Tool Handlers
extension WinBackOffersWorker {

    /// Lists win-back offers for a subscription
    /// - Returns: JSON array of win-back offers with attributes
    func listWinBackOffers(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCWinBackOffersResponse
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/winBackOffers"
            let query = [
                "limit": String(try validatedCommerceLimit(arguments["limit"], defaultValue: 25, maximum: 200))
            ]

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: endpoint,
                        requiredParameters: query,
                        allowedParameters: Set(query.keys).union(["cursor"]),
                        requiredNonEmptyParameters: ["cursor"]
                    ),
                    as: ASCWinBackOffersResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCWinBackOffersResponse.self
                )
            }

            let offers = response.data.map { formatWinBackOffer($0) }

            var result: [String: Any] = [
                "success": true,
                "win_back_offers": offers,
                "count": offers.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list win-back offers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new win-back offer for a subscription
    /// - Returns: JSON with created win-back offer details
    func createWinBackOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let referenceName = arguments["reference_name"]?.stringValue,
              let offerId = arguments["offer_id"]?.stringValue,
              let duration = arguments["duration"]?.stringValue,
              let offerMode = arguments["offer_mode"]?.stringValue,
              let periodCount = arguments["period_count"]?.intValue,
              let priority = arguments["priority"]?.stringValue,
              let eligibilityDurationMonths = arguments["eligibility_duration_months"]?.intValue,
              let startDate = arguments["start_date"]?.stringValue,
              let pricePointValues = arguments["price_point_ids"]?.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: subscription_id, reference_name, offer_id, duration, offer_mode, period_count, priority, eligibility_duration_months, start_date, price_point_ids")],
                isError: true
            )
        }

        let promotionIntent = arguments["promotion_intent"]?.stringValue
        let eligibilityWaitBetweenMonths = arguments["eligibility_wait_between_months"]?.intValue
        let territoryValues = arguments["territory_ids"]?.arrayValue ?? []
        let territoryIds = territoryValues.compactMap(\.stringValue)
        let pricePointIds = pricePointValues.compactMap(\.stringValue)
        let eligibilityTimeSinceLastMin = arguments["eligibility_time_since_last_months_min"]?.intValue
        let eligibilityTimeSinceLastMax = arguments["eligibility_time_since_last_months_max"]?.intValue

        guard Set(["PAY_AS_YOU_GO", "PAY_UP_FRONT", "FREE_TRIAL"]).contains(offerMode) else {
            return MCPResult.error("offer_mode must be PAY_AS_YOU_GO, PAY_UP_FRONT, or FREE_TRIAL")
        }
        guard Set(["THREE_DAYS", "ONE_WEEK", "TWO_WEEKS", "ONE_MONTH", "TWO_MONTHS", "THREE_MONTHS", "SIX_MONTHS", "ONE_YEAR"]).contains(duration),
              periodCount > 0 else {
            return MCPResult.error("duration must be a supported Apple duration and period_count must be positive")
        }
        guard Set(["HIGH", "NORMAL"]).contains(priority) else {
            return MCPResult.error("priority must be HIGH or NORMAL")
        }
        if let promotionIntent,
           !Set(["NOT_PROMOTED", "USE_AUTO_GENERATED_ASSETS"]).contains(promotionIntent) {
            return MCPResult.error("promotion_intent must be NOT_PROMOTED or USE_AUTO_GENERATED_ASSETS")
        }
        guard isAllowedEligibilityDuration(eligibilityDurationMonths) else {
            return MCPResult.error("eligibility_duration_months must be 1 through 24, 36, 48, or 60")
        }
        if let value = arguments["eligibility_time_since_last_months_min"],
           value.intValue == nil {
            return MCPResult.error("eligibility_time_since_last_months_min must be a non-negative integer")
        }
        if let value = arguments["eligibility_time_since_last_months_max"],
           value.intValue == nil {
            return MCPResult.error("eligibility_time_since_last_months_max must be a non-negative integer")
        }
        if let eligibilityTimeSinceLastMin, eligibilityTimeSinceLastMin < 0 {
            return MCPResult.error("eligibility_time_since_last_months_min must be a non-negative integer")
        }
        if let eligibilityTimeSinceLastMax, eligibilityTimeSinceLastMax < 0 {
            return MCPResult.error("eligibility_time_since_last_months_max must be a non-negative integer")
        }
        if let eligibilityTimeSinceLastMin,
           let eligibilityTimeSinceLastMax,
           eligibilityTimeSinceLastMax < eligibilityTimeSinceLastMin {
            return MCPResult.error("eligibility_time_since_last_months_max must be at least the minimum")
        }
        if let eligibilityWaitBetweenMonths,
           !(2...24).contains(eligibilityWaitBetweenMonths) {
            return MCPResult.error("eligibility_wait_between_months must be between 2 and 24")
        }
        if let targetPlan = arguments["target_subscription_plan_type"]?.stringValue,
           !Set(["MONTHLY", "UPFRONT"]).contains(targetPlan) {
            return MCPResult.error("target_subscription_plan_type must be MONTHLY or UPFRONT")
        }
        guard isValidDate(startDate) else {
            return MCPResult.error("start_date must be a valid date in YYYY-MM-DD format")
        }
        if let endDate = arguments["end_date"]?.stringValue, !isValidDate(endDate) {
            return MCPResult.error("end_date must be a valid date in YYYY-MM-DD format")
        }
        if arguments.keys.contains("territory_ids") {
            guard territoryIds.count == territoryValues.count,
                  !territoryIds.isEmpty,
                  territoryIds.allSatisfy({ !$0.isEmpty }),
                  territoryIds.count == pricePointIds.count else {
                return MCPResult.error("territory_ids, when supplied, must contain one non-empty label per price_point_id")
            }
        }
        guard pricePointIds.count == pricePointValues.count,
              !pricePointIds.isEmpty,
              pricePointIds.allSatisfy({ !$0.isEmpty }) else {
            return MCPResult.error("price_point_ids must contain at least one subscription price point ID")
        }

        do {
            var priceRefs: [ASCResourceIdentifier] = []
            var included: [WinBackOfferPriceInlineCreate] = []
            for (index, pricePointId) in pricePointIds.enumerated() {
                let tempId = "${price-\(index)}"
                priceRefs.append(ASCResourceIdentifier(type: "winBackOfferPrices", id: tempId))
                included.append(WinBackOfferPriceInlineCreate(
                    id: tempId,
                    relationships: WinBackOfferPriceInlineCreate.Relationships(
                        subscriptionPricePoint: WinBackOfferPriceInlineCreate.PricePointRelationship(
                            data: ASCResourceIdentifier(type: "subscriptionPricePoints", id: pricePointId)
                        )
                    )
                ))
            }
            let pricesRelationship = CreateWinBackOfferRequest.PricesRelationship(data: priceRefs)

            let request = CreateWinBackOfferRequest(
                data: CreateWinBackOfferRequest.CreateData(
                    attributes: CreateWinBackOfferRequest.Attributes(
                        referenceName: referenceName,
                        offerId: offerId,
                        duration: duration,
                        offerMode: offerMode,
                        periodCount: periodCount,
                        priority: priority,
                        promotionIntent: promotionIntent,
                        customerEligibilityPaidSubscriptionDurationInMonths: eligibilityDurationMonths,
                        customerEligibilityTimeSinceLastSubscribedInMonths: EligibilityRange(
                            minimum: eligibilityTimeSinceLastMin,
                            maximum: eligibilityTimeSinceLastMax
                        ),
                        customerEligibilityWaitBetweenOffersInMonths: eligibilityWaitBetweenMonths,
                        startDate: startDate,
                        endDate: arguments["end_date"]?.stringValue,
                        targetSubscriptionPlanType: arguments["target_subscription_plan_type"]?.stringValue
                    ),
                    relationships: CreateWinBackOfferRequest.Relationships(
                        subscription: CreateWinBackOfferRequest.SubscriptionRelationship(
                            data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                        ),
                        prices: pricesRelationship
                    )
                ),
                included: included
            )

            let response: ASCWinBackOfferResponse = try await httpClient.post(
                "/v1/winBackOffers",
                body: request,
                as: ASCWinBackOfferResponse.self
            )

            let offer = formatWinBackOffer(response.data)

            let result = [
                "success": true,
                "win_back_offer": offer
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create win-back offer")
        }
    }

    /// Updates a win-back offer
    /// - Returns: JSON with updated win-back offer details
    func updateWinBackOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let winbackOfferId = arguments["winback_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'winback_offer_id' is missing")],
                isError: true
            )
        }

        var attributes: [String: JSONValue] = [:]

        if let value = arguments["eligibility_duration_months"] {
            if value.isNull {
                attributes["customerEligibilityPaidSubscriptionDurationInMonths"] = .null
            } else if let months = value.intValue, isAllowedEligibilityDuration(months) {
                attributes["customerEligibilityPaidSubscriptionDurationInMonths"] = .int(months)
            } else {
                return MCPResult.error("eligibility_duration_months must be null or one of 1 through 24, 36, 48, or 60")
            }
        }

        let minimumValue = arguments["eligibility_time_since_last_months_min"]
        let maximumValue = arguments["eligibility_time_since_last_months_max"]
        if minimumValue != nil || maximumValue != nil {
            if minimumValue?.isNull == true || maximumValue?.isNull == true {
                guard minimumValue?.isNull ?? true, maximumValue?.isNull ?? true else {
                    return MCPResult.error("Use null without an integer eligibility range bound to clear the whole range")
                }
                attributes["customerEligibilityTimeSinceLastSubscribedInMonths"] = .null
            } else {
                var range: [String: JSONValue] = [:]
                if let minimumValue {
                    guard let minimum = minimumValue.intValue, minimum >= 0 else {
                        return MCPResult.error("eligibility_time_since_last_months_min must be a non-negative integer or null")
                    }
                    range["minimum"] = .int(minimum)
                }
                if let maximumValue {
                    guard let maximum = maximumValue.intValue, maximum >= 0 else {
                        return MCPResult.error("eligibility_time_since_last_months_max must be a non-negative integer or null")
                    }
                    range["maximum"] = .int(maximum)
                }
                if let minimum = minimumValue?.intValue,
                   let maximum = maximumValue?.intValue,
                   maximum < minimum {
                    return MCPResult.error("eligibility_time_since_last_months_max must be at least the minimum")
                }
                attributes["customerEligibilityTimeSinceLastSubscribedInMonths"] = .object(range)
            }
        }

        if let value = arguments["eligibility_wait_between_months"] {
            if value.isNull {
                attributes["customerEligibilityWaitBetweenOffersInMonths"] = .null
            } else if let months = value.intValue, (2...24).contains(months) {
                attributes["customerEligibilityWaitBetweenOffersInMonths"] = .int(months)
            } else {
                return MCPResult.error("eligibility_wait_between_months must be null or between 2 and 24")
            }
        }

        if let error = setNullableEnumAttribute(
            from: arguments["priority"],
            toolField: "priority",
            attribute: "priority",
            allowedValues: ["HIGH", "NORMAL"],
            attributes: &attributes
        ) {
            return MCPResult.error(error)
        }
        if let error = setNullableEnumAttribute(
            from: arguments["promotion_intent"],
            toolField: "promotion_intent",
            attribute: "promotionIntent",
            allowedValues: ["NOT_PROMOTED", "USE_AUTO_GENERATED_ASSETS"],
            attributes: &attributes
        ) {
            return MCPResult.error(error)
        }
        if let error = setNullableStringAttribute(
            from: arguments["start_date"],
            toolField: "start_date",
            attribute: "startDate",
            attributes: &attributes
        ) {
            return MCPResult.error(error)
        }
        if let error = setNullableStringAttribute(
            from: arguments["end_date"],
            toolField: "end_date",
            attribute: "endDate",
            attributes: &attributes
        ) {
            return MCPResult.error(error)
        }

        guard !attributes.isEmpty else {
            return MCPResult.error("At least one mutable win-back offer field is required")
        }

        do {
            let request = UpdateWinBackOfferRequest(
                data: UpdateWinBackOfferRequest.UpdateData(
                    id: winbackOfferId,
                    attributes: attributes
                )
            )

            let response: ASCWinBackOfferResponse = try await httpClient.patch(
                "/v1/winBackOffers/\(try ASCPathSegment.encode(winbackOfferId))",
                body: request,
                as: ASCWinBackOfferResponse.self
            )

            let offer = formatWinBackOffer(response.data)

            let result = [
                "success": true,
                "win_back_offer": offer
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update win-back offer")
        }
    }

    /// Deletes a win-back offer
    /// - Returns: JSON confirmation
    func deleteWinBackOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let winbackOfferId = arguments["winback_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'winback_offer_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/winBackOffers/\(try ASCPathSegment.encode(winbackOfferId))")

            let result = [
                "success": true,
                "message": "Win-back offer '\(winbackOfferId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete win-back offer")
        }
    }

    /// Lists prices for a win-back offer
    /// - Returns: JSON array of win-back offer prices
    func listWinBackOfferPrices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let winbackOfferId = arguments["winback_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'winback_offer_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCWinBackOfferPricesResponse
            let endpoint = "/v1/winBackOffers/\(try ASCPathSegment.encode(winbackOfferId))/prices"
            let query = [
                "limit": String(try validatedCommerceLimit(arguments["limit"], defaultValue: 25, maximum: 200))
            ]

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: endpoint,
                        requiredParameters: query,
                        allowedParameters: Set(query.keys).union(["cursor"]),
                        requiredNonEmptyParameters: ["cursor"]
                    ),
                    as: ASCWinBackOfferPricesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCWinBackOfferPricesResponse.self
                )
            }

            let prices = response.data.map { formatWinBackOfferPrice($0) }

            var result: [String: Any] = [
                "success": true,
                "prices": prices,
                "count": prices.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list win-back offer prices: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func isAllowedEligibilityDuration(_ months: Int) -> Bool {
        (1...24).contains(months) || [36, 48, 60].contains(months)
    }

    private func setNullableEnumAttribute(
        from value: Value?,
        toolField: String,
        attribute: String,
        allowedValues: Set<String>,
        attributes: inout [String: JSONValue]
    ) -> String? {
        guard let value else { return nil }
        if value.isNull {
            attributes[attribute] = .null
            return nil
        }
        guard let string = value.stringValue, allowedValues.contains(string) else {
            return "\(toolField) must be null or one of: \(allowedValues.sorted().joined(separator: ", "))"
        }
        attributes[attribute] = .string(string)
        return nil
    }

    private func setNullableStringAttribute(
        from value: Value?,
        toolField: String,
        attribute: String,
        attributes: inout [String: JSONValue]
    ) -> String? {
        guard let value else { return nil }
        if value.isNull {
            attributes[attribute] = .null
            return nil
        }
        guard let string = value.stringValue, isValidDate(string) else {
            return "\(toolField) must be null or a valid date in YYYY-MM-DD format"
        }
        attributes[attribute] = .string(string)
        return nil
    }

    private func isValidDate(_ string: String) -> Bool {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return false
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.date,
              let resolved = components.calendar?.dateComponents([.year, .month, .day], from: date) else {
            return false
        }
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    // MARK: - Formatting

    private func formatWinBackOffer(_ offer: ASCWinBackOffer) -> [String: Any] {
        var result: [String: Any] = [
            "id": offer.id,
            "type": offer.type,
            "referenceName": offer.attributes.referenceName.jsonSafe,
            "offerId": offer.attributes.offerId.jsonSafe,
            "duration": offer.attributes.duration.jsonSafe,
            "offerMode": offer.attributes.offerMode.jsonSafe,
            "periodCount": offer.attributes.periodCount.jsonSafe,
            "priority": offer.attributes.priority.jsonSafe,
            "promotionIntent": offer.attributes.promotionIntent.jsonSafe,
            "eligibilityDurationMonths": offer.attributes.customerEligibilityPaidSubscriptionDurationInMonths.jsonSafe,
            "eligibilityWaitBetweenMonths": offer.attributes.customerEligibilityWaitBetweenOffersInMonths.jsonSafe,
            "startDate": offer.attributes.startDate.jsonSafe,
            "endDate": offer.attributes.endDate.jsonSafe,
            "targetSubscriptionPlanType": offer.attributes.targetSubscriptionPlanType.jsonSafe
        ]
        if let range = offer.attributes.customerEligibilityTimeSinceLastSubscribedInMonths {
            var eligibilityRange: [String: Any] = [:]
            if let minimum = range.minimum {
                eligibilityRange["minimum"] = minimum
            }
            if let maximum = range.maximum {
                eligibilityRange["maximum"] = maximum
            }
            result["eligibilityTimeSinceLastMonths"] = eligibilityRange
        } else {
            result["eligibilityTimeSinceLastMonths"] = NSNull()
        }
        return result
    }

    private func formatWinBackOfferPrice(_ price: ASCWinBackOfferPrice) -> [String: Any] {
        return [
            "id": price.id,
            "type": price.type
        ]
    }
}
