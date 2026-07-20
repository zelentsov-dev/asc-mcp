import Foundation
import MCP

// MARK: - Tool Handlers
extension IntroductoryOffersWorker {

    /// Lists introductory offers for a subscription
    /// - Returns: JSON array of introductory offers with attributes
    func listIntroductoryOffers(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIntroductoryOffersResponse
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/introductoryOffers"
            var query = [
                "limit": String(min(max(arguments["limit"]?.intValue ?? 25, 1), 200))
            ]
            if let territory = arguments["filter_territory"]?.stringValue {
                query["filter[territory]"] = territory
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: endpoint,
                        requiredParameters: query,
                        allowedParameters: Set(query.keys).union(["cursor"]),
                        requiredNonEmptyParameters: ["cursor"]
                    ),
                    as: ASCIntroductoryOffersResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCIntroductoryOffersResponse.self
                )
            }

            let offers = response.data.map { formatIntroductoryOffer($0) }

            var result: [String: Any] = [
                "success": true,
                "introductory_offers": offers,
                "count": offers.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list introductory offers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates an introductory offer for a subscription
    /// - Returns: JSON with created introductory offer details
    func createIntroductoryOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let duration = arguments["duration"]?.stringValue,
              let offerMode = arguments["offer_mode"]?.stringValue,
              let numberOfPeriods = arguments["number_of_periods"]?.intValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: subscription_id, duration, offer_mode, number_of_periods")],
                isError: true
            )
        }

        // Validate: PAY modes require subscription_price_point_id
        let pricePointId = arguments["subscription_price_point_id"]?.stringValue
        if offerMode != "FREE_TRIAL" && pricePointId == nil {
            return CallTool.Result(
                content: [MCPContent.text("Error: subscription_price_point_id is required for \(offerMode) mode (only FREE_TRIAL doesn't need it)")],
                isError: true
            )
        }

        do {
            let startDate = try nullableIntroductoryOfferDate("start_date", from: arguments)
            let endDate = try nullableIntroductoryOfferDate("end_date", from: arguments)
            let targetSubscriptionPlanType = try nullableIntroductoryOfferPlanType(from: arguments)
            if case .string(let start)? = startDate,
               case .string(let end)? = endDate,
               start > end {
                throw IntroductoryOfferInputError("start_date must be earlier than or equal to end_date")
            }

            let subscriptionRel = CreateIntroductoryOfferRequest.SubscriptionRelationship(
                data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
            )

            var pricePointRel: CreateIntroductoryOfferRequest.PricePointRelationship?
            if let ppId = pricePointId {
                pricePointRel = CreateIntroductoryOfferRequest.PricePointRelationship(
                    data: ASCResourceIdentifier(type: "subscriptionPricePoints", id: ppId)
                )
            }

            var territoryRel: CreateIntroductoryOfferRequest.TerritoryRelationship?
            if let territoryId = arguments["territory_id"]?.stringValue {
                territoryRel = CreateIntroductoryOfferRequest.TerritoryRelationship(
                    data: ASCResourceIdentifier(type: "territories", id: territoryId)
                )
            }

            let request = CreateIntroductoryOfferRequest(
                data: CreateIntroductoryOfferRequest.CreateData(
                    attributes: CreateIntroductoryOfferRequest.Attributes(
                        duration: duration,
                        offerMode: offerMode,
                        numberOfPeriods: numberOfPeriods,
                        startDate: startDate,
                        endDate: endDate,
                        targetSubscriptionPlanType: targetSubscriptionPlanType
                    ),
                    relationships: CreateIntroductoryOfferRequest.Relationships(
                        subscription: subscriptionRel,
                        subscriptionPricePoint: pricePointRel,
                        territory: territoryRel
                    )
                )
            )

            let response: ASCIntroductoryOfferResponse = try await httpClient.post(
                "/v1/subscriptionIntroductoryOffers",
                body: request,
                as: ASCIntroductoryOfferResponse.self
            )

            let offer = formatIntroductoryOffer(response.data)

            let result = [
                "success": true,
                "introductory_offer": offer
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create introductory offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates an introductory offer (only endDate can be changed)
    /// - Returns: JSON with updated introductory offer details
    func updateIntroductoryOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let introOfferId = arguments["introductory_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'introductory_offer_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateIntroductoryOfferRequest(
                data: UpdateIntroductoryOfferRequest.UpdateData(
                    id: introOfferId,
                    attributes: UpdateIntroductoryOfferRequest.Attributes(
                        endDate: arguments["end_date"]?.stringValue
                    )
                )
            )

            let response: ASCIntroductoryOfferResponse = try await httpClient.patch(
                "/v1/subscriptionIntroductoryOffers/\(try ASCPathSegment.encode(introOfferId))",
                body: request,
                as: ASCIntroductoryOfferResponse.self
            )

            let offer = formatIntroductoryOffer(response.data)

            let result = [
                "success": true,
                "introductory_offer": offer
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update introductory offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an introductory offer
    /// - Returns: JSON confirmation
    func deleteIntroductoryOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let introOfferId = arguments["introductory_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'introductory_offer_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/subscriptionIntroductoryOffers/\(try ASCPathSegment.encode(introOfferId))")

            let result = [
                "success": true,
                "message": "Introductory offer '\(introOfferId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete introductory offer")
        }
    }

    // MARK: - Formatting

    private func formatIntroductoryOffer(_ offer: ASCIntroductoryOffer) -> [String: Any] {
        return [
            "id": offer.id,
            "type": offer.type,
            "duration": offer.attributes.duration.jsonSafe,
            "offerMode": offer.attributes.offerMode.jsonSafe,
            "numberOfPeriods": offer.attributes.numberOfPeriods.jsonSafe,
            "startDate": offer.attributes.startDate.jsonSafe,
            "endDate": offer.attributes.endDate.jsonSafe,
            "targetSubscriptionPlanType": offer.attributes.targetSubscriptionPlanType.jsonSafe
        ]
    }

    private func nullableIntroductoryOfferDate(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> NullableAttributeValue? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue, isValidIntroductoryOfferDate(string) else {
            throw IntroductoryOfferInputError("\(name) must be a valid date in YYYY-MM-DD format or null")
        }
        return .string(string)
    }

    private func nullableIntroductoryOfferPlanType(
        from arguments: [String: Value]
    ) throws -> NullableAttributeValue? {
        guard let value = arguments["target_subscription_plan_type"] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        let allowedValues: Set<String> = ["MONTHLY", "UPFRONT"]
        guard let string = value.stringValue, allowedValues.contains(string) else {
            throw IntroductoryOfferInputError("target_subscription_plan_type must be null or one of: MONTHLY, UPFRONT")
        }
        return .string(string)
    }

    private func isValidIntroductoryOfferDate(_ value: String) -> Bool {
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
}

private struct IntroductoryOfferInputError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
