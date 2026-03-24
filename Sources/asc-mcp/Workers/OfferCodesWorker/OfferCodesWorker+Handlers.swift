import Foundation
import MCP

// MARK: - Tool Handlers
extension OfferCodesWorker {

    /// Lists offer codes for a subscription
    /// - Returns: JSON array of offer codes with attributes
    func listOfferCodes(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCOfferCodesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCOfferCodesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptions/\(subscriptionId)/offerCodes",
                    parameters: queryParams,
                    as: ASCOfferCodesResponse.self
                )
            }

            let offerCodes = response.data.map { formatOfferCode($0) }

            var result: [String: Any] = [
                "success": true,
                "offer_codes": offerCodes,
                "count": offerCodes.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list offer codes: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new offer code for a subscription
    /// - Returns: JSON with created offer code details
    func createOfferCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let name = arguments["name"]?.stringValue,
              let offerEligibility = arguments["offer_eligibility"]?.stringValue,
              let offerMode = arguments["offer_mode"]?.stringValue,
              let duration = arguments["duration"]?.stringValue,
              let numberOfPeriods = arguments["number_of_periods"]?.intValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: subscription_id, name, offer_eligibility, offer_mode, duration, number_of_periods")],
                isError: true
            )
        }

        do {
            // Parse customer_eligibilities from arguments
            var customerEligibilities: [String] = []
            if let eligArray = arguments["customer_eligibilities"]?.arrayValue {
                customerEligibilities = eligArray.compactMap { $0.stringValue }
            } else {
                customerEligibilities = [offerEligibility]
            }

            // Parse territory_ids
            let territoryIds = arguments["territory_ids"]?.arrayValue?.compactMap { $0.stringValue } ?? []

            // Build prices relationship and included based on offerMode
            var pricesRelationship: CreateOfferCodeRequest.PricesRelationship?
            var included: [OfferCodePriceInlineCreate]?

            if offerMode == "FREE_TRIAL" {
                // FREE_TRIAL: inline prices contain ONLY territory (no subscriptionPricePoint)
                if !territoryIds.isEmpty {
                    var priceRefs: [ASCResourceIdentifier] = []
                    var priceInlines: [OfferCodePriceInlineCreate] = []

                    for (index, territoryId) in territoryIds.enumerated() {
                        let tempId = "${price-\(index)}"
                        priceRefs.append(ASCResourceIdentifier(type: "subscriptionOfferCodePrices", id: tempId))
                        priceInlines.append(OfferCodePriceInlineCreate(
                            id: tempId,
                            relationships: OfferCodePriceInlineCreate.Relationships(
                                subscriptionPricePoint: nil,
                                territory: OfferCodePriceInlineCreate.TerritoryRelationship(
                                    data: ASCResourceIdentifier(type: "territories", id: territoryId)
                                )
                            )
                        ))
                    }

                    pricesRelationship = CreateOfferCodeRequest.PricesRelationship(data: priceRefs)
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
                        var priceInlines: [OfferCodePriceInlineCreate] = []

                        for (index, pricePointId) in ids.enumerated() {
                            let tempId = "${price-\(index)}"
                            priceRefs.append(ASCResourceIdentifier(type: "subscriptionOfferCodePrices", id: tempId))
                            priceInlines.append(OfferCodePriceInlineCreate(
                                id: tempId,
                                relationships: OfferCodePriceInlineCreate.Relationships(
                                    subscriptionPricePoint: OfferCodePriceInlineCreate.PricePointRelationship(
                                        data: ASCResourceIdentifier(type: "subscriptionPricePoints", id: pricePointId)
                                    ),
                                    territory: OfferCodePriceInlineCreate.TerritoryRelationship(
                                        data: ASCResourceIdentifier(type: "territories", id: territoryIds[index])
                                    )
                                )
                            ))
                        }

                        pricesRelationship = CreateOfferCodeRequest.PricesRelationship(data: priceRefs)
                        included = priceInlines
                    }
                }
            }

            let request = CreateOfferCodeRequest(
                data: CreateOfferCodeRequest.CreateData(
                    attributes: CreateOfferCodeRequest.Attributes(
                        name: name,
                        offerEligibility: offerEligibility,
                        offerMode: offerMode,
                        duration: duration,
                        numberOfPeriods: numberOfPeriods,
                        customerEligibilities: customerEligibilities
                    ),
                    relationships: CreateOfferCodeRequest.Relationships(
                        subscription: CreateOfferCodeRequest.SubscriptionRelationship(
                            data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                        ),
                        prices: pricesRelationship
                    )
                ),
                included: included
            )

            let response: ASCOfferCodeResponse = try await httpClient.post(
                "/v1/subscriptionOfferCodes",
                body: request,
                as: ASCOfferCodeResponse.self
            )

            let offerCode = formatOfferCode(response.data)

            let result = [
                "success": true,
                "offer_code": offerCode
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create offer code: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates an offer code
    /// - Returns: JSON with updated offer code details
    func updateOfferCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'offer_code_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateOfferCodeRequest(
                data: UpdateOfferCodeRequest.UpdateData(
                    id: offerCodeId,
                    attributes: UpdateOfferCodeRequest.Attributes(
                        active: arguments["active"]?.boolValue
                    )
                )
            )

            let response: ASCOfferCodeResponse = try await httpClient.patch(
                "/v1/subscriptionOfferCodes/\(offerCodeId)",
                body: request,
                as: ASCOfferCodeResponse.self
            )

            let offerCode = formatOfferCode(response.data)

            let result = [
                "success": true,
                "offer_code": offerCode
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update offer code: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deactivates an offer code
    /// - Returns: JSON with deactivated offer code details
    func deactivateOfferCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'offer_code_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateOfferCodeRequest(
                data: UpdateOfferCodeRequest.UpdateData(
                    id: offerCodeId,
                    attributes: UpdateOfferCodeRequest.Attributes(
                        active: false
                    )
                )
            )

            let response: ASCOfferCodeResponse = try await httpClient.patch(
                "/v1/subscriptionOfferCodes/\(offerCodeId)",
                body: request,
                as: ASCOfferCodeResponse.self
            )

            let offerCode = formatOfferCode(response.data)

            let result = [
                "success": true,
                "offer_code": offerCode,
                "message": "Offer code '\(offerCodeId)' deactivated"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to deactivate offer code: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists prices for an offer code
    /// - Returns: JSON array of offer code prices
    func listOfferCodePrices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'offer_code_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCOfferCodePricesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCOfferCodePricesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptionOfferCodes/\(offerCodeId)/prices",
                    parameters: queryParams,
                    as: ASCOfferCodePricesResponse.self
                )
            }

            let prices = response.data.map { formatOfferCodePrice($0) }

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
                content: [.text("Error: Failed to list offer code prices: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Generates one-time use codes for an offer code
    /// - Returns: JSON confirmation with generated codes details
    func generateOneTimeCodes(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue,
              let numberOfCodes = arguments["number_of_codes"]?.intValue,
              let expirationDate = arguments["expiration_date"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: offer_code_id, number_of_codes, expiration_date")],
                isError: true
            )
        }

        do {
            let request = GenerateOneTimeCodesRequest(
                data: GenerateOneTimeCodesRequest.CreateData(
                    attributes: GenerateOneTimeCodesRequest.Attributes(
                        numberOfCodes: numberOfCodes,
                        expirationDate: expirationDate
                    ),
                    relationships: GenerateOneTimeCodesRequest.Relationships(
                        offerCode: GenerateOneTimeCodesRequest.OfferCodeRelationship(
                            data: ASCResourceIdentifier(type: "subscriptionOfferCodes", id: offerCodeId)
                        )
                    )
                )
            )

            let response: ASCOneTimeUseCodeResponse = try await httpClient.post(
                "/v1/subscriptionOfferCodes/\(offerCodeId)/oneTimeUseCodes",
                body: request,
                as: ASCOneTimeUseCodeResponse.self
            )

            let code = formatOneTimeUseCode(response.data)

            let result = [
                "success": true,
                "one_time_code": code,
                "message": "Generated \(numberOfCodes) one-time use codes"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to generate one-time codes: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists one-time use codes for an offer code
    /// - Returns: JSON array of one-time use codes
    func listOneTimeCodes(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'offer_code_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCOneTimeUseCodesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCOneTimeUseCodesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptionOfferCodes/\(offerCodeId)/oneTimeUseCodes",
                    parameters: queryParams,
                    as: ASCOneTimeUseCodesResponse.self
                )
            }

            let codes = response.data.map { formatOneTimeUseCode($0) }

            var result: [String: Any] = [
                "success": true,
                "one_time_codes": codes,
                "count": codes.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list one-time codes: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Custom Codes

    /// Creates a custom (reusable) code for an offer code
    /// - Returns: JSON with created custom code details
    func createCustomCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let offerCodeId = arguments["offer_code_id"]?.stringValue,
              let customCode = arguments["custom_code"]?.stringValue,
              let numberOfCodes = arguments["number_of_codes"]?.intValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: offer_code_id, custom_code, number_of_codes")],
                isError: true
            )
        }

        do {
            let request = CreateOfferCodeCustomCodeRequest(
                data: CreateOfferCodeCustomCodeRequest.CreateData(
                    attributes: CreateOfferCodeCustomCodeRequest.Attributes(
                        customCode: customCode,
                        numberOfCodes: numberOfCodes,
                        expirationDate: arguments["expiration_date"]?.stringValue
                    ),
                    relationships: CreateOfferCodeCustomCodeRequest.Relationships(
                        offerCode: CreateOfferCodeCustomCodeRequest.OfferCodeRelationship(
                            data: ASCResourceIdentifier(type: "subscriptionOfferCodes", id: offerCodeId)
                        )
                    )
                )
            )

            let response: ASCOfferCodeCustomCodeResponse = try await httpClient.post(
                "/v1/subscriptionOfferCodeCustomCodes",
                body: request,
                as: ASCOfferCodeCustomCodeResponse.self
            )

            let code = formatCustomCode(response.data)

            let result = [
                "success": true,
                "custom_code": code
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create custom code: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a custom code
    /// - Returns: JSON with custom code details
    func getCustomCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let customCodeId = arguments["custom_code_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'custom_code_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCOfferCodeCustomCodeResponse = try await httpClient.get(
                "/v1/subscriptionOfferCodeCustomCodes/\(customCodeId)",
                as: ASCOfferCodeCustomCodeResponse.self
            )

            let code = formatCustomCode(response.data)

            let result = [
                "success": true,
                "custom_code": code
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get custom code: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deactivates a custom code
    /// - Returns: JSON with deactivated custom code details
    func deactivateCustomCode(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let customCodeId = arguments["custom_code_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'custom_code_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateOfferCodeCustomCodeRequest(
                data: UpdateOfferCodeCustomCodeRequest.UpdateData(
                    id: customCodeId,
                    attributes: UpdateOfferCodeCustomCodeRequest.Attributes(
                        active: false
                    )
                )
            )

            let response: ASCOfferCodeCustomCodeResponse = try await httpClient.patch(
                "/v1/subscriptionOfferCodeCustomCodes/\(customCodeId)",
                body: request,
                as: ASCOfferCodeCustomCodeResponse.self
            )

            let code = formatCustomCode(response.data)

            let result = [
                "success": true,
                "custom_code": code,
                "message": "Custom code '\(customCodeId)' deactivated"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to deactivate custom code: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatOfferCode(_ code: ASCOfferCode) -> [String: Any] {
        return [
            "id": code.id,
            "type": code.type,
            "name": code.attributes.name.jsonSafe,
            "active": code.attributes.active.jsonSafe,
            "offerEligibility": code.attributes.offerEligibility.jsonSafe,
            "offerMode": code.attributes.offerMode.jsonSafe,
            "duration": code.attributes.duration.jsonSafe,
            "numberOfPeriods": code.attributes.numberOfPeriods.jsonSafe,
            "totalNumberOfCodes": code.attributes.totalNumberOfCodes.jsonSafe,
            "customerEligibilities": code.attributes.customerEligibilities.jsonSafe
        ]
    }

    private func formatOfferCodePrice(_ price: ASCOfferCodePrice) -> [String: Any] {
        return [
            "id": price.id,
            "type": price.type
        ]
    }

    private func formatCustomCode(_ code: ASCOfferCodeCustomCode) -> [String: Any] {
        return [
            "id": code.id,
            "type": code.type,
            "customCode": code.attributes?.customCode.jsonSafe ?? NSNull(),
            "numberOfCodes": code.attributes?.numberOfCodes.jsonSafe ?? NSNull(),
            "totalNumberOfCodes": code.attributes?.totalNumberOfCodes.jsonSafe ?? NSNull(),
            "active": code.attributes?.active.jsonSafe ?? NSNull(),
            "expirationDate": code.attributes?.expirationDate.jsonSafe ?? NSNull(),
            "createdDate": code.attributes?.createdDate.jsonSafe ?? NSNull()
        ]
    }

    private func formatOneTimeUseCode(_ code: ASCOneTimeUseCode) -> [String: Any] {
        return [
            "id": code.id,
            "type": code.type,
            "numberOfCodes": code.attributes?.numberOfCodes.jsonSafe ?? NSNull(),
            "createdDate": code.attributes?.createdDate.jsonSafe ?? NSNull(),
            "expirationDate": code.attributes?.expirationDate.jsonSafe ?? NSNull(),
            "active": code.attributes?.active.jsonSafe ?? NSNull()
        ]
    }
}
