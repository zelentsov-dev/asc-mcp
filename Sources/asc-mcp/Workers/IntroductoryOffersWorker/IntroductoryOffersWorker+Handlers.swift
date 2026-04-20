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
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIntroductoryOffersResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCIntroductoryOffersResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                if let territory = arguments["filter_territory"]?.stringValue {
                    queryParams["filter[territory]"] = territory
                }

                response = try await httpClient.get(
                    "/v1/subscriptions/\(subscriptionId)/introductoryOffers",
                    parameters: queryParams,
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list introductory offers: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameters: subscription_id, duration, offer_mode, number_of_periods")],
                isError: true
            )
        }

        // Validate: PAY modes require subscription_price_point_id
        let pricePointId = arguments["subscription_price_point_id"]?.stringValue
        if offerMode != "FREE_TRIAL" && pricePointId == nil {
            return CallTool.Result(
                content: [.text("Error: subscription_price_point_id is required for \(offerMode) mode (only FREE_TRIAL doesn't need it)")],
                isError: true
            )
        }

        do {
            // Build relationships
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
                        startDate: arguments["start_date"]?.stringValue,
                        endDate: arguments["end_date"]?.stringValue
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create introductory offer: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'introductory_offer_id' is missing")],
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
                "/v1/subscriptionIntroductoryOffers/\(introOfferId)",
                body: request,
                as: ASCIntroductoryOfferResponse.self
            )

            let offer = formatIntroductoryOffer(response.data)

            let result = [
                "success": true,
                "introductory_offer": offer
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update introductory offer: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'introductory_offer_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/subscriptionIntroductoryOffers/\(introOfferId)")

            let result = [
                "success": true,
                "message": "Introductory offer '\(introOfferId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete introductory offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Sets a FREE_TRIAL introductory offer for all territories in one PATCH request.
    /// Uses PATCH /v1/subscriptions/{id} with introductoryOffers relationship + included array.
    /// - Returns: JSON with subscription state and territories count
    func createIntroductoryOffersAllTerritories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let duration = arguments["duration"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: subscription_id, duration")],
                isError: true
            )
        }

        let offerMode = arguments["offer_mode"]?.stringValue ?? "FREE_TRIAL"
        let numberOfPeriods = arguments["number_of_periods"]?.intValue ?? 1

        do {
            // Step 1: Get all territories
            let territoriesResponse: ASCTerritoriesResponse = try await httpClient.get(
                "/v1/territories",
                parameters: ["limit": "200"],
                as: ASCTerritoriesResponse.self
            )
            let territories = territoriesResponse.data

            // Step 2: Build PATCH body with ${N} local IDs
            let refs = territories.enumerated().map { (i, _) in
                SetAllIntroductoryOffersRequest.OfferRef(id: "${\(i)}")
            }
            let included = territories.enumerated().map { (i, territory) in
                SetAllIntroductoryOffersRequest.InlineOffer(
                    id: "${\(i)}",
                    attributes: SetAllIntroductoryOffersRequest.OfferAttrs(
                        duration: duration,
                        offerMode: offerMode,
                        numberOfPeriods: numberOfPeriods
                    ),
                    relationships: SetAllIntroductoryOffersRequest.InlineOfferRels(
                        territory: SetAllIntroductoryOffersRequest.TerritoryRef(
                            data: ASCResourceIdentifier(type: "territories", id: territory.id)
                        )
                    )
                )
            }

            let request = SetAllIntroductoryOffersRequest(
                data: SetAllIntroductoryOffersRequest.UpdateData(
                    id: subscriptionId,
                    relationships: SetAllIntroductoryOffersRequest.Relationships(
                        introductoryOffers: SetAllIntroductoryOffersRequest.OffersData(data: refs)
                    )
                ),
                included: included
            )

            // Step 3: Single PATCH sets all territories at once
            let response: ASCSubscriptionResponse = try await httpClient.patch(
                "/v1/subscriptions/\(subscriptionId)",
                body: request,
                as: ASCSubscriptionResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "subscription": [
                    "id": response.data.id,
                    "state": response.data.attributes.state as Any,
                    "name": response.data.attributes.name as Any
                ],
                "offer_mode": offerMode,
                "duration": duration,
                "territories_set": territories.count
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to set introductory offers: \(error.localizedDescription)")],
                isError: true
            )
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
            "endDate": offer.attributes.endDate.jsonSafe
        ]
    }
}
