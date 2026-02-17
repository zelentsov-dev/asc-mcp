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
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCWinBackOffersResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCWinBackOffersResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptions/\(subscriptionId)/winBackOffers",
                    parameters: queryParams,
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list win-back offers: \(error.localizedDescription)")],
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
              let priority = arguments["priority"]?.stringValue,
              let startDate = arguments["start_date"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: subscription_id, reference_name, offer_id, duration, offer_mode, priority, start_date")],
                isError: true
            )
        }

        do {
            let request = CreateWinBackOfferRequest(
                data: CreateWinBackOfferRequest.CreateData(
                    attributes: CreateWinBackOfferRequest.Attributes(
                        referenceName: referenceName,
                        offerId: offerId,
                        duration: duration,
                        offerMode: offerMode,
                        periodCount: arguments["period_count"]?.intValue,
                        priority: priority,
                        customerEligibilityPaidSubscriptionDurationInMonths: arguments["eligibility_duration_months"]?.intValue,
                        customerEligibilityTimeSinceLastSubscribedInMonths: arguments["eligibility_time_since_last_months"]?.intValue,
                        customerEligibilityWaitBetweenOffersInMonths: arguments["eligibility_wait_between_months"]?.intValue,
                        startDate: startDate,
                        endDate: arguments["end_date"]?.stringValue
                    ),
                    relationships: CreateWinBackOfferRequest.Relationships(
                        subscription: CreateWinBackOfferRequest.SubscriptionRelationship(
                            data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                        )
                    )
                )
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create win-back offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a win-back offer
    /// - Returns: JSON with updated win-back offer details
    func updateWinBackOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let winbackOfferId = arguments["winback_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'winback_offer_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateWinBackOfferRequest(
                data: UpdateWinBackOfferRequest.UpdateData(
                    id: winbackOfferId,
                    attributes: UpdateWinBackOfferRequest.Attributes(
                        priority: arguments["priority"]?.stringValue,
                        startDate: arguments["start_date"]?.stringValue,
                        endDate: arguments["end_date"]?.stringValue
                    )
                )
            )

            let response: ASCWinBackOfferResponse = try await httpClient.patch(
                "/v1/winBackOffers/\(winbackOfferId)",
                body: request,
                as: ASCWinBackOfferResponse.self
            )

            let offer = formatWinBackOffer(response.data)

            let result = [
                "success": true,
                "win_back_offer": offer
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update win-back offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a win-back offer
    /// - Returns: JSON confirmation
    func deleteWinBackOffer(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let winbackOfferId = arguments["winback_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'winback_offer_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/winBackOffers/\(winbackOfferId)")

            let result = [
                "success": true,
                "message": "Win-back offer '\(winbackOfferId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete win-back offer: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists prices for a win-back offer
    /// - Returns: JSON array of win-back offer prices
    func listWinBackOfferPrices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let winbackOfferId = arguments["winback_offer_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'winback_offer_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCWinBackOfferPricesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCWinBackOfferPricesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/winBackOffers/\(winbackOfferId)/prices",
                    parameters: queryParams,
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list win-back offer prices: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatWinBackOffer(_ offer: ASCWinBackOffer) -> [String: Any] {
        return [
            "id": offer.id,
            "type": offer.type,
            "referenceName": offer.attributes.referenceName.jsonSafe,
            "offerId": offer.attributes.offerId.jsonSafe,
            "duration": offer.attributes.duration.jsonSafe,
            "offerMode": offer.attributes.offerMode.jsonSafe,
            "periodCount": offer.attributes.periodCount.jsonSafe,
            "priority": offer.attributes.priority.jsonSafe,
            "eligibilityDurationMonths": offer.attributes.customerEligibilityPaidSubscriptionDurationInMonths.jsonSafe,
            "eligibilityTimeSinceLastMonths": offer.attributes.customerEligibilityTimeSinceLastSubscribedInMonths.jsonSafe,
            "eligibilityWaitBetweenMonths": offer.attributes.customerEligibilityWaitBetweenOffersInMonths.jsonSafe,
            "startDate": offer.attributes.startDate.jsonSafe,
            "endDate": offer.attributes.endDate.jsonSafe
        ]
    }

    private func formatWinBackOfferPrice(_ price: ASCWinBackOfferPrice) -> [String: Any] {
        return [
            "id": price.id,
            "type": price.type
        ]
    }
}
