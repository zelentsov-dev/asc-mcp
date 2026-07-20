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
                content: [MCPContent.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCOfferCodesResponse
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionId))/offerCodes"
            let query = [
                "limit": String(min(max(arguments["limit"]?.intValue ?? 25, 1), 200))
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
                    as: ASCOfferCodesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list offer codes: \(error.localizedDescription)")],
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
              let numberOfPeriods = arguments["number_of_periods"]?.intValue,
              let customerEligibilityValues = arguments["customer_eligibilities"]?.arrayValue,
              let territoryValues = arguments["territory_ids"]?.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: subscription_id, name, customer_eligibilities, offer_eligibility, offer_mode, duration, number_of_periods, territory_ids")],
                isError: true
            )
        }

        do {
            let customerEligibilities = customerEligibilityValues.compactMap(\.stringValue)
            let territoryIds = territoryValues.compactMap(\.stringValue)
            let pricePointValues = arguments["price_point_ids"]?.arrayValue ?? []
            let pricePointIds = pricePointValues.compactMap(\.stringValue)

            guard customerEligibilities.count == customerEligibilityValues.count,
                  !customerEligibilities.isEmpty,
                  customerEligibilities.allSatisfy(Set(["NEW", "EXISTING", "EXPIRED"]).contains) else {
                return MCPResult.error("customer_eligibilities must contain one or more of: NEW, EXISTING, EXPIRED")
            }
            guard Set(["STACK_WITH_INTRO_OFFERS", "REPLACE_INTRO_OFFERS"]).contains(offerEligibility) else {
                return MCPResult.error("offer_eligibility must be STACK_WITH_INTRO_OFFERS or REPLACE_INTRO_OFFERS")
            }
            guard Set(["PAY_AS_YOU_GO", "PAY_UP_FRONT", "FREE_TRIAL"]).contains(offerMode) else {
                return MCPResult.error("offer_mode must be PAY_AS_YOU_GO, PAY_UP_FRONT, or FREE_TRIAL")
            }
            guard Set(["THREE_DAYS", "ONE_WEEK", "TWO_WEEKS", "ONE_MONTH", "TWO_MONTHS", "THREE_MONTHS", "SIX_MONTHS", "ONE_YEAR"]).contains(duration),
                  numberOfPeriods > 0 else {
                return MCPResult.error("duration must be a supported Apple duration and number_of_periods must be positive")
            }
            guard territoryIds.count == territoryValues.count,
                  !territoryIds.isEmpty,
                  territoryIds.allSatisfy({ !$0.isEmpty }) else {
                return MCPResult.error("territory_ids must contain at least one territory ID")
            }
            guard pricePointIds.count == pricePointValues.count,
                  pricePointIds.allSatisfy({ !$0.isEmpty }) else {
                return MCPResult.error("price_point_ids must contain only string IDs")
            }
            if let targetPlan = arguments["target_subscription_plan_type"]?.stringValue,
               !Set(["MONTHLY", "UPFRONT"]).contains(targetPlan) {
                return MCPResult.error("target_subscription_plan_type must be MONTHLY or UPFRONT")
            }
            if arguments["auto_renew_enabled"]?.boolValue == false {
                guard offerMode == "FREE_TRIAL" else {
                    return MCPResult.error("auto_renew_enabled can be false only for FREE_TRIAL offers")
                }
                guard offerEligibility == "REPLACE_INTRO_OFFERS" else {
                    return MCPResult.error("auto_renew_enabled=false requires offer_eligibility=REPLACE_INTRO_OFFERS")
                }
            }
            if offerMode == "FREE_TRIAL", !pricePointIds.isEmpty {
                return MCPResult.error("price_point_ids must be omitted for FREE_TRIAL offers")
            }
            if offerMode != "FREE_TRIAL",
               (pricePointIds.isEmpty || pricePointIds.count != territoryIds.count) {
                return MCPResult.error("paid offers require one price_point_id per territory_id")
            }

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
                                content: [MCPContent.text("Error: price_point_ids and territory_ids must have the same count (got \(ids.count) vs \(territoryIds.count))")],
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

            guard let pricesRelationship, let included else {
                return MCPResult.error("At least one valid territory price is required")
            }

            let request = CreateOfferCodeRequest(
                data: CreateOfferCodeRequest.CreateData(
                    attributes: CreateOfferCodeRequest.Attributes(
                        name: name,
                        offerEligibility: offerEligibility,
                        offerMode: offerMode,
                        duration: duration,
                        numberOfPeriods: numberOfPeriods,
                        customerEligibilities: customerEligibilities,
                        autoRenewEnabled: arguments["auto_renew_enabled"]?.boolValue,
                        targetSubscriptionPlanType: arguments["target_subscription_plan_type"]?.stringValue
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create offer code: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'offer_code_id' is missing")],
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
                "/v1/subscriptionOfferCodes/\(try ASCPathSegment.encode(offerCodeId))",
                body: request,
                as: ASCOfferCodeResponse.self
            )

            let offerCode = formatOfferCode(response.data)

            let result = [
                "success": true,
                "offer_code": offerCode
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update offer code: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'offer_code_id' is missing")],
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
                "/v1/subscriptionOfferCodes/\(try ASCPathSegment.encode(offerCodeId))",
                body: request,
                as: ASCOfferCodeResponse.self
            )

            let offerCode = formatOfferCode(response.data)

            let result = [
                "success": true,
                "offer_code": offerCode,
                "message": "Offer code '\(offerCodeId)' deactivated"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to deactivate offer code: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'offer_code_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCOfferCodePricesResponse
            let endpoint = "/v1/subscriptionOfferCodes/\(try ASCPathSegment.encode(offerCodeId))/prices"
            let query = [
                "limit": String(min(max(arguments["limit"]?.intValue ?? 25, 1), 200))
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
                    as: ASCOfferCodePricesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list offer code prices: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: offer_code_id, number_of_codes, expiration_date")],
                isError: true
            )
        }

        guard numberOfCodes > 0 else {
            return MCPResult.error("Parameter 'number_of_codes' must be at least 1")
        }
        let environment: String?
        if let environmentValue = arguments["environment"] {
            guard let parsedEnvironment = environmentValue.stringValue,
                  ["PRODUCTION", "SANDBOX"].contains(parsedEnvironment) else {
                return MCPResult.error("Parameter 'environment' must be PRODUCTION or SANDBOX")
            }
            environment = parsedEnvironment
        } else {
            environment = nil
        }

        do {
            let request = GenerateOneTimeCodesRequest(
                data: GenerateOneTimeCodesRequest.CreateData(
                    attributes: GenerateOneTimeCodesRequest.Attributes(
                        numberOfCodes: numberOfCodes,
                        expirationDate: expirationDate,
                        environment: environment
                    ),
                    relationships: GenerateOneTimeCodesRequest.Relationships(
                        offerCode: GenerateOneTimeCodesRequest.OfferCodeRelationship(
                            data: ASCResourceIdentifier(type: "subscriptionOfferCodes", id: offerCodeId)
                        )
                    )
                )
            )

            let response: ASCOneTimeUseCodeResponse = try await httpClient.post(
                "/v1/subscriptionOfferCodeOneTimeUseCodes",
                body: request,
                as: ASCOneTimeUseCodeResponse.self
            )

            let code = formatOneTimeUseCode(response.data)

            let result = [
                "success": true,
                "one_time_code": code,
                "message": "Generated \(numberOfCodes) one-time use codes"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to generate one-time codes: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'offer_code_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCOneTimeUseCodesResponse
            let endpoint = "/v1/subscriptionOfferCodes/\(try ASCPathSegment.encode(offerCodeId))/oneTimeUseCodes"
            let query = [
                "limit": String(min(max(arguments["limit"]?.intValue ?? 25, 1), 200))
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
                    as: ASCOneTimeUseCodesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list one-time codes: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: offer_code_id, custom_code, number_of_codes")],
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create custom code: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'custom_code_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCOfferCodeCustomCodeResponse = try await httpClient.get(
                "/v1/subscriptionOfferCodeCustomCodes/\(try ASCPathSegment.encode(customCodeId))",
                as: ASCOfferCodeCustomCodeResponse.self
            )

            let code = formatCustomCode(response.data)

            let result = [
                "success": true,
                "custom_code": code
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get custom code: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'custom_code_id' is missing")],
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
                "/v1/subscriptionOfferCodeCustomCodes/\(try ASCPathSegment.encode(customCodeId))",
                body: request,
                as: ASCOfferCodeCustomCodeResponse.self
            )

            let code = formatCustomCode(response.data)

            let result = [
                "success": true,
                "custom_code": code,
                "message": "Custom code '\(customCodeId)' deactivated"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to deactivate custom code: \(error.localizedDescription)")],
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
            "productionCodeCount": code.attributes.productionCodeCount.jsonSafe,
            "sandboxCodeCount": code.attributes.sandboxCodeCount.jsonSafe,
            "customerEligibilities": code.attributes.customerEligibilities.jsonSafe,
            "autoRenewEnabled": code.attributes.autoRenewEnabled.jsonSafe,
            "targetSubscriptionPlanType": code.attributes.targetSubscriptionPlanType.jsonSafe
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
            "customCode": (code.attributes?.customCode).jsonSafe,
            "numberOfCodes": (code.attributes?.numberOfCodes).jsonSafe,
            "totalNumberOfCodes": (code.attributes?.totalNumberOfCodes).jsonSafe,
            "active": (code.attributes?.active).jsonSafe,
            "expirationDate": (code.attributes?.expirationDate).jsonSafe,
            "createdDate": (code.attributes?.createdDate).jsonSafe
        ]
    }

    private func formatOneTimeUseCode(_ code: ASCOneTimeUseCode) -> [String: Any] {
        return [
            "id": code.id,
            "type": code.type,
            "numberOfCodes": (code.attributes?.numberOfCodes).jsonSafe,
            "createdDate": (code.attributes?.createdDate).jsonSafe,
            "expirationDate": (code.attributes?.expirationDate).jsonSafe,
            "active": (code.attributes?.active).jsonSafe,
            "environment": (code.attributes?.environment).jsonSafe
        ]
    }
}
