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
}
