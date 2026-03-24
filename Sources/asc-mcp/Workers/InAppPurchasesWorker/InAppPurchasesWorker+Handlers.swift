import Foundation
import MCP

// MARK: - Tool Handlers
extension InAppPurchasesWorker {

    /// Lists in-app purchases for an app
    /// - Returns: JSON array of IAPs with attributes
    func listIAP(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCInAppPurchasesV2Response

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCInAppPurchasesV2Response.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                if let stateValue = arguments["filter_state"],
                   let state = stateValue.stringValue {
                    queryParams["filter[state]"] = state
                }

                if let typeValue = arguments["filter_type"],
                   let type = typeValue.stringValue {
                    queryParams["filter[inAppPurchaseType]"] = type
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/inAppPurchasesV2",
                    parameters: queryParams,
                    as: ASCInAppPurchasesV2Response.self
                )
            }

            let iaps = response.data.map { formatIAP($0) }

            var result: [String: Any] = [
                "success": true,
                "in_app_purchases": iaps,
                "count": iaps.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list IAPs: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific IAP
    /// - Returns: JSON with IAP details
    func getIAP(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCInAppPurchaseV2Response = try await httpClient.get(
                "/v2/inAppPurchases/\(iapId)",
                as: ASCInAppPurchaseV2Response.self
            )

            let iap = formatIAP(response.data)

            let result = [
                "success": true,
                "in_app_purchase": iap
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get IAP: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new in-app purchase
    /// - Returns: JSON with created IAP details
    func createIAP(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let nameValue = arguments["name"],
              let name = nameValue.stringValue,
              let productIdValue = arguments["product_id"],
              let productId = productIdValue.stringValue,
              let iapTypeValue = arguments["iap_type"],
              let iapType = iapTypeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: app_id, name, product_id, iap_type")],
                isError: true
            )
        }

        do {
            let request = CreateInAppPurchaseV2Request(
                data: CreateInAppPurchaseV2Request.CreateIAPData(
                    attributes: CreateInAppPurchaseV2Request.CreateIAPAttributes(
                        name: name,
                        productId: productId,
                        inAppPurchaseType: iapType,
                        reviewNote: arguments["review_note"]?.stringValue,
                        familySharable: arguments["family_sharable"]?.boolValue
                    ),
                    relationships: CreateInAppPurchaseV2Request.CreateIAPRelationships(
                        app: CreateInAppPurchaseV2Request.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        )
                    )
                )
            )

            let response: ASCInAppPurchaseV2Response = try await httpClient.post(
                "/v2/inAppPurchases",
                body: request,
                as: ASCInAppPurchaseV2Response.self
            )

            let iap = formatIAP(response.data)

            let result = [
                "success": true,
                "in_app_purchase": iap
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create IAP: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates an in-app purchase
    /// - Returns: JSON with updated IAP details
    func updateIAP(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateInAppPurchaseV2Request(
                data: UpdateInAppPurchaseV2Request.UpdateIAPData(
                    id: iapId,
                    attributes: UpdateInAppPurchaseV2Request.UpdateIAPAttributes(
                        name: arguments["name"]?.stringValue,
                        reviewNote: arguments["review_note"]?.stringValue,
                        familySharable: arguments["family_sharable"]?.boolValue
                    )
                )
            )

            let response: ASCInAppPurchaseV2Response = try await httpClient.patch(
                "/v2/inAppPurchases/\(iapId)",
                body: request,
                as: ASCInAppPurchaseV2Response.self
            )

            let iap = formatIAP(response.data)

            let result = [
                "success": true,
                "in_app_purchase": iap
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update IAP: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an in-app purchase
    /// - Returns: JSON confirmation
    func deleteIAP(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v2/inAppPurchases/\(iapId)")

            let result = [
                "success": true,
                "message": "IAP '\(iapId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete IAP: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists localizations for an in-app purchase
    /// - Returns: JSON array of localizations
    func listIAPLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCInAppPurchaseLocalizationsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCInAppPurchaseLocalizationsResponse.self)
            } else {
                response = try await httpClient.get(
                    "/v2/inAppPurchases/\(iapId)/inAppPurchaseLocalizations",
                    parameters: [:],
                    as: ASCInAppPurchaseLocalizationsResponse.self
                )
            }

            let localizations = response.data.map { formatLocalization($0) }

            var result: [String: Any] = [
                "success": true,
                "localizations": localizations,
                "count": localizations.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list IAP localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists subscription groups for an app
    /// - Returns: JSON array of subscription groups
    func listSubscriptionGroups(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCSubscriptionGroupsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCSubscriptionGroupsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/subscriptionGroups",
                    parameters: queryParams,
                    as: ASCSubscriptionGroupsResponse.self
                )
            }

            let groups = response.data.map { formatSubscriptionGroup($0) }

            var result: [String: Any] = [
                "success": true,
                "subscription_groups": groups,
                "count": groups.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list subscription groups: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a subscription group
    /// - Returns: JSON with subscription group details
    func getSubscriptionGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupIdValue = arguments["group_id"],
              let groupId = groupIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'group_id' is missing")],
                isError: true
            )
        }

        do {
            let includeSubscriptions = arguments["include_subscriptions"]?.boolValue ?? true

            var queryParams: [String: String] = [:]
            if includeSubscriptions {
                queryParams["include"] = "subscriptions"
            }

            let response: ASCSubscriptionGroupResponse = try await httpClient.get(
                "/v1/subscriptionGroups/\(groupId)",
                parameters: queryParams,
                as: ASCSubscriptionGroupResponse.self
            )

            let group = formatSubscriptionGroup(response.data)

            let result = [
                "success": true,
                "subscription_group": group
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get subscription group: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a localization for an in-app purchase
    /// - Returns: JSON with created localization details
    func createIAPLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue,
              let nameValue = arguments["name"],
              let name = nameValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters: iap_id, locale, name")],
                isError: true
            )
        }

        do {
            let request = CreateInAppPurchaseLocalizationRequest(
                data: CreateInAppPurchaseLocalizationRequest.CreateData(
                    attributes: CreateInAppPurchaseLocalizationRequest.Attributes(
                        locale: locale,
                        name: name,
                        description: arguments["description"]?.stringValue
                    ),
                    relationships: CreateInAppPurchaseLocalizationRequest.Relationships(
                        inAppPurchaseV2: CreateInAppPurchaseLocalizationRequest.InAppPurchaseRelationship(
                            data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                        )
                    )
                )
            )

            let response: ASCInAppPurchaseLocalizationResponse = try await httpClient.post(
                "/v1/inAppPurchaseLocalizations",
                body: request,
                as: ASCInAppPurchaseLocalizationResponse.self
            )

            let localization = formatLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create IAP localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a localization for an in-app purchase
    /// - Returns: JSON with updated localization details
    func updateIAPLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateInAppPurchaseLocalizationRequest(
                data: UpdateInAppPurchaseLocalizationRequest.UpdateData(
                    id: localizationId,
                    attributes: UpdateInAppPurchaseLocalizationRequest.Attributes(
                        name: arguments["name"]?.stringValue,
                        description: arguments["description"]?.stringValue
                    )
                )
            )

            let response: ASCInAppPurchaseLocalizationResponse = try await httpClient.patch(
                "/v1/inAppPurchaseLocalizations/\(localizationId)",
                body: request,
                as: ASCInAppPurchaseLocalizationResponse.self
            )

            let localization = formatLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to update IAP localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a localization for an in-app purchase
    /// - Returns: JSON confirmation
    func deleteIAPLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/inAppPurchaseLocalizations/\(localizationId)")

            let result = [
                "success": true,
                "message": "IAP localization '\(localizationId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to delete IAP localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Submits an in-app purchase for review
    /// - Returns: JSON confirmation with IAP ID
    func submitIAPForReview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let request = CreateInAppPurchaseSubmissionRequest(
                data: CreateInAppPurchaseSubmissionRequest.CreateData(
                    relationships: CreateInAppPurchaseSubmissionRequest.Relationships(
                        inAppPurchaseV2: CreateInAppPurchaseSubmissionRequest.InAppPurchaseRelationship(
                            data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                        )
                    )
                )
            )

            let encoder = JSONEncoder()
            let bodyData = try encoder.encode(request)
            _ = try await httpClient.post("/v1/inAppPurchaseSubmissions", body: bodyData)

            let result = [
                "success": true,
                "message": "IAP '\(iapId)' submitted for review"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to submit IAP for review: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Price Points & Schedule

    /// Lists price points for an in-app purchase
    /// - Returns: JSON array of price points with customer price, proceeds, and tier
    func listIAPPricePoints(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIAPPricePointsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCIAPPricePointsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "50"
                }

                if let territory = arguments["territory"]?.stringValue {
                    queryParams["filter[territory]"] = territory
                }

                response = try await httpClient.get(
                    "/v2/inAppPurchases/\(iapId)/pricePoints",
                    parameters: queryParams,
                    as: ASCIAPPricePointsResponse.self
                )
            }

            let pricePoints = response.data.map { formatPricePoint($0) }

            var result: [String: Any] = [
                "success": true,
                "price_points": pricePoints,
                "count": pricePoints.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list IAP price points: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets the price schedule for an in-app purchase
    /// - Returns: JSON with price schedule ID
    func getIAPPriceSchedule(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIAPPriceScheduleResponse = try await httpClient.get(
                "/v2/inAppPurchases/\(iapId)/iapPriceSchedule",
                as: ASCIAPPriceScheduleResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "price_schedule": [
                    "id": response.data.id,
                    "type": response.data.type
                ]
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get IAP price schedule: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Sets the price schedule for an in-app purchase
    /// - Returns: JSON with created price schedule
    /// - Throws: Error if IAP ID or base territory ID is missing
    func setIAPPriceSchedule(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue,
              let baseTerritoryIdValue = arguments["base_territory_id"],
              let baseTerritoryId = baseTerritoryIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: iap_id, base_territory_id")],
                isError: true
            )
        }

        do {
            var manualPriceIdentifiers: [ASCResourceIdentifier] = []
            if let manualPriceIds = arguments["manual_price_ids"]?.stringValue {
                manualPriceIdentifiers = manualPriceIds
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .map { ASCResourceIdentifier(type: "inAppPurchasePrices", id: $0) }
            }

            let request = CreateIAPPriceScheduleRequest(
                data: CreateIAPPriceScheduleRequest.CreateData(
                    relationships: CreateIAPPriceScheduleRequest.Relationships(
                        inAppPurchase: CreateIAPPriceScheduleRequest.InAppPurchaseRelationship(
                            data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                        ),
                        manualPrices: CreateIAPPriceScheduleRequest.ManualPricesRelationship(
                            data: manualPriceIdentifiers
                        ),
                        baseTerritory: CreateIAPPriceScheduleRequest.BaseTerritoryRelationship(
                            data: ASCResourceIdentifier(type: "territories", id: baseTerritoryId)
                        )
                    )
                )
            )

            let response: ASCIAPPriceScheduleResponse = try await httpClient.post(
                "/v1/inAppPurchasePriceSchedules",
                body: request,
                as: ASCIAPPriceScheduleResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "price_schedule": [
                    "id": response.data.id,
                    "type": response.data.type
                ]
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to set IAP price schedule: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Availability

    /// Sets territorial availability for an in-app purchase
    /// - Returns: JSON with availability details
    func setIAPAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue,
              let availableInNewTerritories = arguments["available_in_new_territories"]?.boolValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: iap_id, available_in_new_territories")],
                isError: true
            )
        }

        let territoryIds = arguments["territory_ids"]?.arrayValue?.compactMap { $0.stringValue } ?? []

        do {
            let territories = territoryIds.map { ASCResourceIdentifier(type: "territories", id: $0) }

            let request = CreateIAPAvailabilityRequest(
                data: CreateIAPAvailabilityRequest.CreateData(
                    attributes: CreateIAPAvailabilityRequest.Attributes(
                        availableInNewTerritories: availableInNewTerritories
                    ),
                    relationships: CreateIAPAvailabilityRequest.Relationships(
                        inAppPurchase: CreateIAPAvailabilityRequest.InAppPurchaseRelationship(
                            data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                        ),
                        availableTerritories: CreateIAPAvailabilityRequest.TerritoriesRelationship(
                            data: territories
                        )
                    )
                )
            )

            let response: ASCIAPAvailabilityResponse = try await httpClient.post(
                "/v1/inAppPurchaseAvailabilities",
                body: request,
                as: ASCIAPAvailabilityResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "availability": formatAvailability(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to set IAP availability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets availability details for an in-app purchase
    /// - Returns: JSON with availability details and territories
    func getIAPAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let availabilityId = arguments["availability_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'availability_id' is missing")],
                isError: true
            )
        }

        do {
            let includeTerritories = arguments["include_territories"]?.boolValue ?? true

            var queryParams: [String: String] = [:]
            if includeTerritories {
                queryParams["include"] = "availableTerritories"
            }

            let response: ASCIAPAvailabilityResponse = try await httpClient.get(
                "/v1/inAppPurchaseAvailabilities/\(availabilityId)",
                parameters: queryParams,
                as: ASCIAPAvailabilityResponse.self
            )

            var resultDict: [String: Any] = [
                "success": true,
                "availability": formatAvailability(response.data)
            ]

            if let included = response.included {
                let territories = included.map { [
                    "id": $0.id,
                    "type": $0.type,
                    "currency": $0.attributes?.currency.jsonSafe ?? NSNull()
                ] as [String: Any] }
                resultDict["territories"] = territories
                resultDict["territory_count"] = territories.count
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(resultDict))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get IAP availability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func formatAvailability(_ availability: ASCIAPAvailability) -> [String: Any] {
        return [
            "id": availability.id,
            "type": availability.type,
            "availableInNewTerritories": availability.attributes?.availableInNewTerritories.jsonSafe ?? NSNull()
        ]
    }

    // MARK: - Review Screenshots

    /// Gets the App Store Review screenshot for an in-app purchase
    /// - Returns: JSON with screenshot details including file info and delivery state
    func getIAPReviewScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIAPReviewScreenshotResponse = try await httpClient.get(
                "/v2/inAppPurchases/\(iapId)/appStoreReviewScreenshot",
                as: ASCIAPReviewScreenshotResponse.self
            )

            let screenshot = formatReviewScreenshot(response.data)

            let result: [String: Any] = [
                "success": true,
                "review_screenshot": screenshot
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get IAP review screenshot: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Reserves a screenshot for App Store Review of an in-app purchase
    /// - Returns: JSON with screenshot reservation details and upload operations
    /// - Throws: Error if required parameters are missing
    func createIAPReviewScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue,
              let fileNameValue = arguments["file_name"],
              let fileName = fileNameValue.stringValue,
              let fileSizeValue = arguments["file_size"],
              let fileSize = fileSizeValue.intValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: iap_id, file_name, file_size")],
                isError: true
            )
        }

        do {
            let request = CreateIAPReviewScreenshotRequest(
                data: CreateIAPReviewScreenshotRequest.CreateData(
                    attributes: CreateIAPReviewScreenshotRequest.Attributes(
                        fileName: fileName,
                        fileSize: fileSize
                    ),
                    relationships: CreateIAPReviewScreenshotRequest.Relationships(
                        inAppPurchaseV2: CreateIAPReviewScreenshotRequest.InAppPurchaseRelationship(
                            data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                        )
                    )
                )
            )

            let response: ASCIAPReviewScreenshotResponse = try await httpClient.post(
                "/v1/inAppPurchaseAppStoreReviewScreenshots",
                body: request,
                as: ASCIAPReviewScreenshotResponse.self
            )

            let screenshot = formatReviewScreenshot(response.data)

            let result: [String: Any] = [
                "success": true,
                "review_screenshot": screenshot
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create IAP review screenshot: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatIAP(_ iap: ASCInAppPurchaseV2) -> [String: Any] {
        return [
            "id": iap.id,
            "type": iap.type,
            "name": iap.attributes.name.jsonSafe,
            "productId": iap.attributes.productId.jsonSafe,
            "inAppPurchaseType": iap.attributes.inAppPurchaseType.jsonSafe,
            "state": iap.attributes.state.jsonSafe,
            "reviewNote": iap.attributes.reviewNote.jsonSafe,
            "familySharable": iap.attributes.familySharable.jsonSafe,
            "contentHosting": iap.attributes.contentHosting.jsonSafe
        ]
    }

    private func formatLocalization(_ loc: ASCInAppPurchaseLocalization) -> [String: Any] {
        return [
            "id": loc.id,
            "type": loc.type,
            "locale": loc.attributes.locale.jsonSafe,
            "name": loc.attributes.name.jsonSafe,
            "description": loc.attributes.description.jsonSafe
        ]
    }

    private func formatSubscriptionGroup(_ group: ASCSubscriptionGroup) -> [String: Any] {
        return [
            "id": group.id,
            "type": group.type,
            "referenceName": group.attributes.referenceName.jsonSafe
        ]
    }

    private func formatPricePoint(_ pricePoint: ASCIAPPricePoint) -> [String: Any] {
        return [
            "id": pricePoint.id,
            "type": pricePoint.type,
            "customerPrice": pricePoint.attributes?.customerPrice.jsonSafe as Any,
            "proceeds": pricePoint.attributes?.proceeds.jsonSafe as Any,
            "priceTier": pricePoint.attributes?.priceTier.jsonSafe as Any
        ]
    }

    private func formatReviewScreenshot(_ screenshot: ASCIAPReviewScreenshot) -> [String: Any] {
        var result: [String: Any] = [
            "id": screenshot.id,
            "type": screenshot.type
        ]
        if let attrs = screenshot.attributes {
            result["fileSize"] = attrs.fileSize.jsonSafe
            result["fileName"] = attrs.fileName.jsonSafe
            result["assetToken"] = attrs.assetToken.jsonSafe
            result["sourceFileChecksum"] = attrs.sourceFileChecksum.jsonSafe
            if let imageAsset = attrs.imageAsset {
                result["imageAsset"] = [
                    "templateUrl": imageAsset.templateUrl.jsonSafe,
                    "width": imageAsset.width.jsonSafe,
                    "height": imageAsset.height.jsonSafe
                ] as [String: Any]
            }
            if let deliveryState = attrs.assetDeliveryState {
                var stateDict: [String: Any] = [
                    "state": deliveryState.state.jsonSafe
                ]
                if let errors = deliveryState.errors {
                    stateDict["errors"] = errors.map { [
                        "code": $0.code.jsonSafe,
                        "description": $0.description.jsonSafe
                    ] as [String: Any] }
                }
                result["assetDeliveryState"] = stateDict
            }
        }
        return result
    }
}
