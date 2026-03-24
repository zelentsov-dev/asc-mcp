import Foundation
import MCP

// MARK: - Tool Handlers
extension PromotionalOffersWorker {

    /// Lists promotional offers for a subscription
    /// - Returns: JSON array of promotional offers with attributes
    func listPromotionalOffers(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotionalOffersResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCPromotionalOffersResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptions/\(subscriptionId)/promotionalOffers",
                    parameters: queryParams,
                    as: ASCPromotionalOffersResponse.self
                )
            }

            let offers = response.data.map { formatPromotionalOffer($0) }

            var result: [String: Any] = [
                "success": true,
                "promotional_offers": offers,
                "count": offers.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list promotional offers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a single promotional offer by ID
    /// - Returns: JSON with promotional offer details
    func getPromotionalOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotionalOfferId = arguments["promotional_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'promotional_offer_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotionalOfferResponse = try await httpClient.get(
                "/v1/subscriptionPromotionalOffers/\(promotionalOfferId)",
                parameters: [:],
                as: ASCPromotionalOfferResponse.self
            )

            let offer = formatPromotionalOffer(response.data)

            let result = [
                "success": true,
                "promotional_offer": offer
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get promotional offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new promotional offer for a subscription
    /// - Returns: JSON with created promotional offer details
    func createPromotionalOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let name = arguments["name"]?.stringValue,
              let offerCode = arguments["offer_code"]?.stringValue,
              let duration = arguments["duration"]?.stringValue,
              let offerMode = arguments["offer_mode"]?.stringValue,
              let numberOfPeriods = arguments["number_of_periods"]?.intValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: subscription_id, name, offer_code, duration, offer_mode, number_of_periods")],
                isError: true
            )
        }

        do {
            // Parse territory_ids
            let territoryIds = arguments["territory_ids"]?.arrayValue?.compactMap { $0.stringValue } ?? []

            // Build prices relationship and included if territory_ids provided
            var pricesRelationship: CreatePromotionalOfferRequest.PricesRelationship?
            var included: [PromotionalOfferPriceInlineCreate]?

            if offerMode == "FREE_TRIAL" {
                // FREE_TRIAL: inline prices contain ONLY territory (no subscriptionPricePoint)
                if !territoryIds.isEmpty {
                    var priceRefs: [ASCResourceIdentifier] = []
                    var priceInlines: [PromotionalOfferPriceInlineCreate] = []

                    for (index, territoryId) in territoryIds.enumerated() {
                        let tempId = "${price-\(index)}"
                        priceRefs.append(ASCResourceIdentifier(type: "subscriptionPromotionalOfferPrices", id: tempId))
                        priceInlines.append(PromotionalOfferPriceInlineCreate(
                            id: tempId,
                            relationships: PromotionalOfferPriceInlineCreate.Relationships(
                                subscriptionPricePoint: nil,
                                territory: PromotionalOfferPriceInlineCreate.TerritoryRelationship(
                                    data: ASCResourceIdentifier(type: "territories", id: territoryId)
                                )
                            )
                        ))
                    }

                    pricesRelationship = CreatePromotionalOfferRequest.PricesRelationship(data: priceRefs)
                    included = priceInlines
                }
            } else {
                // PAY_UP_FRONT / PAY_AS_YOU_GO: inline prices need subscriptionPricePoint + territory
                if let pricePointIds = arguments["price_point_ids"]?.arrayValue {
                    let ids = pricePointIds.compactMap { $0.stringValue }
                    if !ids.isEmpty {
                        guard ids.count == territoryIds.count else {
                            return CallTool.Result(
                                content: [.text("Error: price_point_ids and territory_ids must have the same count (got \(ids.count) vs \(territoryIds.count))")],
                                isError: true
                            )
                        }

                        var priceRefs: [ASCResourceIdentifier] = []
                        var priceInlines: [PromotionalOfferPriceInlineCreate] = []

                        for (index, pricePointId) in ids.enumerated() {
                            let tempId = "${price-\(index)}"
                            priceRefs.append(ASCResourceIdentifier(type: "subscriptionPromotionalOfferPrices", id: tempId))
                            priceInlines.append(PromotionalOfferPriceInlineCreate(
                                id: tempId,
                                relationships: PromotionalOfferPriceInlineCreate.Relationships(
                                    subscriptionPricePoint: PromotionalOfferPriceInlineCreate.PricePointRelationship(
                                        data: ASCResourceIdentifier(type: "subscriptionPricePoints", id: pricePointId)
                                    ),
                                    territory: PromotionalOfferPriceInlineCreate.TerritoryRelationship(
                                        data: ASCResourceIdentifier(type: "territories", id: territoryIds[index])
                                    )
                                )
                            ))
                        }

                        pricesRelationship = CreatePromotionalOfferRequest.PricesRelationship(data: priceRefs)
                        included = priceInlines
                    }
                }
            }

            let request = CreatePromotionalOfferRequest(
                data: CreatePromotionalOfferRequest.CreateData(
                    attributes: CreatePromotionalOfferRequest.Attributes(
                        name: name,
                        offerCode: offerCode,
                        duration: duration,
                        offerMode: offerMode,
                        numberOfPeriods: numberOfPeriods
                    ),
                    relationships: CreatePromotionalOfferRequest.Relationships(
                        subscription: CreatePromotionalOfferRequest.SubscriptionRelationship(
                            data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                        ),
                        prices: pricesRelationship
                    )
                ),
                included: included
            )

            let response: ASCPromotionalOfferResponse = try await httpClient.post(
                "/v1/subscriptionPromotionalOffers",
                body: request,
                as: ASCPromotionalOfferResponse.self
            )

            let offer = formatPromotionalOffer(response.data)

            let result = [
                "success": true,
                "promotional_offer": offer
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create promotional offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a promotional offer's prices (attributes cannot be changed via PATCH)
    /// - Returns: JSON with updated promotional offer details
    func updatePromotionalOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotionalOfferId = arguments["promotional_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'promotional_offer_id' is missing")],
                isError: true
            )
        }

        do {
            // Parse territory_ids
            let territoryIds = arguments["territory_ids"]?.arrayValue?.compactMap { $0.stringValue } ?? []

            // Build prices relationship and included
            var pricesRelationship: UpdatePromotionalOfferRequest.PricesRelationship?
            var included: [PromotionalOfferPriceInlineCreate]?

            if let pricePointIds = arguments["price_point_ids"]?.arrayValue {
                // PAY modes: both price points and territories
                let ids = pricePointIds.compactMap { $0.stringValue }
                if !ids.isEmpty {
                    guard ids.count == territoryIds.count else {
                        return CallTool.Result(
                            content: [.text("Error: price_point_ids and territory_ids must have the same count (got \(ids.count) vs \(territoryIds.count))")],
                            isError: true
                        )
                    }

                    var priceRefs: [ASCResourceIdentifier] = []
                    var priceInlines: [PromotionalOfferPriceInlineCreate] = []

                    for (index, pricePointId) in ids.enumerated() {
                        let tempId = "${price-\(index)}"
                        priceRefs.append(ASCResourceIdentifier(type: "subscriptionPromotionalOfferPrices", id: tempId))
                        priceInlines.append(PromotionalOfferPriceInlineCreate(
                            id: tempId,
                            relationships: PromotionalOfferPriceInlineCreate.Relationships(
                                subscriptionPricePoint: PromotionalOfferPriceInlineCreate.PricePointRelationship(
                                    data: ASCResourceIdentifier(type: "subscriptionPricePoints", id: pricePointId)
                                ),
                                territory: PromotionalOfferPriceInlineCreate.TerritoryRelationship(
                                    data: ASCResourceIdentifier(type: "territories", id: territoryIds[index])
                                )
                            )
                        ))
                    }

                    pricesRelationship = UpdatePromotionalOfferRequest.PricesRelationship(data: priceRefs)
                    included = priceInlines
                }
            } else if !territoryIds.isEmpty {
                // FREE_TRIAL mode: territory only
                var priceRefs: [ASCResourceIdentifier] = []
                var priceInlines: [PromotionalOfferPriceInlineCreate] = []

                for (index, territoryId) in territoryIds.enumerated() {
                    let tempId = "${price-\(index)}"
                    priceRefs.append(ASCResourceIdentifier(type: "subscriptionPromotionalOfferPrices", id: tempId))
                    priceInlines.append(PromotionalOfferPriceInlineCreate(
                        id: tempId,
                        relationships: PromotionalOfferPriceInlineCreate.Relationships(
                            subscriptionPricePoint: nil,
                            territory: PromotionalOfferPriceInlineCreate.TerritoryRelationship(
                                data: ASCResourceIdentifier(type: "territories", id: territoryId)
                            )
                        )
                    ))
                }

                pricesRelationship = UpdatePromotionalOfferRequest.PricesRelationship(data: priceRefs)
                included = priceInlines
            }

            let relationships: UpdatePromotionalOfferRequest.Relationships? =
                pricesRelationship != nil
                    ? UpdatePromotionalOfferRequest.Relationships(prices: pricesRelationship)
                    : nil

            let request = UpdatePromotionalOfferRequest(
                data: UpdatePromotionalOfferRequest.UpdateData(
                    id: promotionalOfferId,
                    relationships: relationships
                ),
                included: included
            )

            let response: ASCPromotionalOfferResponse = try await httpClient.patch(
                "/v1/subscriptionPromotionalOffers/\(promotionalOfferId)",
                body: request,
                as: ASCPromotionalOfferResponse.self
            )

            let offer = formatPromotionalOffer(response.data)

            let result = [
                "success": true,
                "promotional_offer": offer
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update promotional offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a promotional offer
    /// - Returns: JSON confirmation
    func deletePromotionalOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotionalOfferId = arguments["promotional_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'promotional_offer_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/subscriptionPromotionalOffers/\(promotionalOfferId)")

            let result = [
                "success": true,
                "message": "Promotional offer '\(promotionalOfferId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete promotional offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists prices for a promotional offer
    /// - Returns: JSON array of promotional offer prices
    func listPromotionalOfferPrices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotionalOfferId = arguments["promotional_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'promotional_offer_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotionalOfferPricesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCPromotionalOfferPricesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptionPromotionalOffers/\(promotionalOfferId)/prices",
                    parameters: queryParams,
                    as: ASCPromotionalOfferPricesResponse.self
                )
            }

            let prices = response.data.map { formatPromotionalOfferPrice($0) }

            var result: [String: Any] = [
                "success": true,
                "prices": prices,
                "count": prices.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list promotional offer prices: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatPromotionalOffer(_ offer: ASCPromotionalOffer) -> [String: Any] {
        return [
            "id": offer.id,
            "type": offer.type,
            "name": offer.attributes.name.jsonSafe,
            "offerCode": offer.attributes.offerCode.jsonSafe,
            "duration": offer.attributes.duration.jsonSafe,
            "offerMode": offer.attributes.offerMode.jsonSafe,
            "numberOfPeriods": offer.attributes.numberOfPeriods.jsonSafe
        ]
    }

    private func formatPromotionalOfferPrice(_ price: ASCPromotionalOfferPrice) -> [String: Any] {
        return [
            "id": price.id,
            "type": price.type
        ]
    }
}
