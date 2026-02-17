import Foundation
import MCP

// MARK: - Tool Handlers
extension SubscriptionsWorker {

    /// Lists subscriptions in a subscription group
    /// - Returns: JSON array of subscriptions with attributes
    func listSubscriptions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupId = arguments["group_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'group_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCSubscriptionsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCSubscriptionsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptionGroups/\(groupId)/subscriptions",
                    parameters: queryParams,
                    as: ASCSubscriptionsResponse.self
                )
            }

            let subscriptions = response.data.map { formatSubscription($0) }

            var result: [String: Any] = [
                "success": true,
                "subscriptions": subscriptions,
                "count": subscriptions.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list subscriptions: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific subscription
    /// - Returns: JSON with subscription details
    func getSubscription(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCSubscriptionResponse = try await httpClient.get(
                "/v1/subscriptions/\(subscriptionId)",
                as: ASCSubscriptionResponse.self
            )

            let subscription = formatSubscription(response.data)

            let result = [
                "success": true,
                "subscription": subscription
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get subscription: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new subscription in a subscription group
    /// - Returns: JSON with created subscription details
    func createSubscription(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupId = arguments["group_id"]?.stringValue,
              let name = arguments["name"]?.stringValue,
              let productId = arguments["product_id"]?.stringValue,
              let subscriptionPeriod = arguments["subscription_period"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: group_id, name, product_id, subscription_period")],
                isError: true
            )
        }

        do {
            let request = CreateSubscriptionRequest(
                data: CreateSubscriptionRequest.CreateData(
                    attributes: CreateSubscriptionRequest.Attributes(
                        name: name,
                        productId: productId,
                        subscriptionPeriod: subscriptionPeriod,
                        familySharable: arguments["family_sharable"]?.boolValue,
                        groupLevel: arguments["group_level"]?.intValue,
                        reviewNote: arguments["review_note"]?.stringValue
                    ),
                    relationships: CreateSubscriptionRequest.Relationships(
                        group: CreateSubscriptionRequest.GroupRelationship(
                            data: ASCResourceIdentifier(type: "subscriptionGroups", id: groupId)
                        )
                    )
                )
            )

            let response: ASCSubscriptionResponse = try await httpClient.post(
                "/v1/subscriptions",
                body: request,
                as: ASCSubscriptionResponse.self
            )

            let subscription = formatSubscription(response.data)

            let result = [
                "success": true,
                "subscription": subscription
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create subscription: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates an existing subscription
    /// - Returns: JSON with updated subscription details
    func updateSubscription(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateSubscriptionRequest(
                data: UpdateSubscriptionRequest.UpdateData(
                    id: subscriptionId,
                    attributes: UpdateSubscriptionRequest.Attributes(
                        name: arguments["name"]?.stringValue,
                        familySharable: arguments["family_sharable"]?.boolValue,
                        groupLevel: arguments["group_level"]?.intValue,
                        reviewNote: arguments["review_note"]?.stringValue
                    )
                )
            )

            let response: ASCSubscriptionResponse = try await httpClient.patch(
                "/v1/subscriptions/\(subscriptionId)",
                body: request,
                as: ASCSubscriptionResponse.self
            )

            let subscription = formatSubscription(response.data)

            let result = [
                "success": true,
                "subscription": subscription
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update subscription: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a subscription
    /// - Returns: JSON confirmation
    func deleteSubscription(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/subscriptions/\(subscriptionId)")

            let result = [
                "success": true,
                "message": "Subscription '\(subscriptionId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete subscription: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists localizations for a subscription
    /// - Returns: JSON array of localizations
    func listSubscriptionLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCSubscriptionLocalizationsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCSubscriptionLocalizationsResponse.self)
            } else {
                response = try await httpClient.get(
                    "/v1/subscriptions/\(subscriptionId)/subscriptionLocalizations",
                    parameters: [:],
                    as: ASCSubscriptionLocalizationsResponse.self
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
                content: [.text("Error: Failed to list subscription localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a localization for a subscription
    /// - Returns: JSON with created localization details
    func createSubscriptionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue,
              let locale = arguments["locale"]?.stringValue,
              let name = arguments["name"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: subscription_id, locale, name")],
                isError: true
            )
        }

        do {
            let request = CreateSubscriptionLocalizationRequest(
                data: CreateSubscriptionLocalizationRequest.CreateData(
                    attributes: CreateSubscriptionLocalizationRequest.Attributes(
                        locale: locale,
                        name: name,
                        description: arguments["description"]?.stringValue
                    ),
                    relationships: CreateSubscriptionLocalizationRequest.Relationships(
                        subscription: CreateSubscriptionLocalizationRequest.SubscriptionRelationship(
                            data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                        )
                    )
                )
            )

            let response: ASCSubscriptionLocalizationResponse = try await httpClient.post(
                "/v1/subscriptionLocalizations",
                body: request,
                as: ASCSubscriptionLocalizationResponse.self
            )

            let localization = formatLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create subscription localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a localization for a subscription
    /// - Returns: JSON with updated localization details
    func updateSubscriptionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateSubscriptionLocalizationRequest(
                data: UpdateSubscriptionLocalizationRequest.UpdateData(
                    id: localizationId,
                    attributes: UpdateSubscriptionLocalizationRequest.Attributes(
                        name: arguments["name"]?.stringValue,
                        description: arguments["description"]?.stringValue
                    )
                )
            )

            let response: ASCSubscriptionLocalizationResponse = try await httpClient.patch(
                "/v1/subscriptionLocalizations/\(localizationId)",
                body: request,
                as: ASCSubscriptionLocalizationResponse.self
            )

            let localization = formatLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update subscription localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a localization for a subscription
    /// - Returns: JSON confirmation
    func deleteSubscriptionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/subscriptionLocalizations/\(localizationId)")

            let result = [
                "success": true,
                "message": "Subscription localization '\(localizationId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete subscription localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists prices for a subscription
    /// - Returns: JSON array of prices
    func listSubscriptionPrices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCSubscriptionPricesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCSubscriptionPricesResponse.self)
            } else {
                var queryParams: [String: String] = [
                    "include": "subscriptionPricePoint",
                    "fields[subscriptionPricePoints]": "customerPrice,proceeds"
                ]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptions/\(subscriptionId)/prices",
                    parameters: queryParams,
                    as: ASCSubscriptionPricesResponse.self
                )
            }

            // Build price point lookup from included resources
            var pricePointMap: [String: ASCSubscriptionPricePoint] = [:]
            if let included = response.included {
                for point in included {
                    pricePointMap[point.id] = point
                }
            }

            let prices = response.data.map { formatPrice($0, pricePointMap: pricePointMap) }

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
                content: [.text("Error: Failed to list subscription prices: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists available price points for a subscription
    /// - Returns: JSON array of price points with customer price and proceeds
    func listSubscriptionPricePoints(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCSubscriptionPricePointsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCSubscriptionPricePointsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/subscriptions/\(subscriptionId)/pricePoints",
                    parameters: queryParams,
                    as: ASCSubscriptionPricePointsResponse.self
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
                content: [.text("Error: Failed to list subscription price points: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new subscription group for an app
    /// - Returns: JSON with created subscription group details
    func createSubscriptionGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue,
              let referenceName = arguments["reference_name"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: app_id, reference_name")],
                isError: true
            )
        }

        do {
            let request = CreateSubscriptionGroupRequest(
                data: CreateSubscriptionGroupRequest.CreateData(
                    attributes: CreateSubscriptionGroupRequest.Attributes(
                        referenceName: referenceName
                    ),
                    relationships: CreateSubscriptionGroupRequest.Relationships(
                        app: CreateSubscriptionGroupRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        )
                    )
                )
            )

            let response: ASCSubscriptionGroupResponse = try await httpClient.post(
                "/v1/subscriptionGroups",
                body: request,
                as: ASCSubscriptionGroupResponse.self
            )

            let group = formatGroup(response.data)

            let result = [
                "success": true,
                "subscription_group": group
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create subscription group: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a subscription group
    /// - Returns: JSON with updated subscription group details
    func updateSubscriptionGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupId = arguments["group_id"]?.stringValue,
              let referenceName = arguments["reference_name"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: group_id, reference_name")],
                isError: true
            )
        }

        do {
            let request = UpdateSubscriptionGroupRequest(
                data: UpdateSubscriptionGroupRequest.UpdateData(
                    id: groupId,
                    attributes: UpdateSubscriptionGroupRequest.Attributes(
                        referenceName: referenceName
                    )
                )
            )

            let response: ASCSubscriptionGroupResponse = try await httpClient.patch(
                "/v1/subscriptionGroups/\(groupId)",
                body: request,
                as: ASCSubscriptionGroupResponse.self
            )

            let group = formatGroup(response.data)

            let result = [
                "success": true,
                "subscription_group": group
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update subscription group: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a subscription group
    /// - Returns: JSON confirmation
    func deleteSubscriptionGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupId = arguments["group_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'group_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/subscriptionGroups/\(groupId)")

            let result = [
                "success": true,
                "message": "Subscription group '\(groupId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete subscription group: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Submits a subscription for App Review
    /// - Returns: JSON confirmation with subscription ID
    func submitSubscription(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let subscriptionId = arguments["subscription_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'subscription_id' is missing")],
                isError: true
            )
        }

        do {
            let request = CreateSubscriptionSubmissionRequest(
                data: CreateSubscriptionSubmissionRequest.CreateData(
                    relationships: CreateSubscriptionSubmissionRequest.Relationships(
                        subscription: CreateSubscriptionSubmissionRequest.SubscriptionRelationship(
                            data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                        )
                    )
                )
            )

            let encoder = JSONEncoder()
            let bodyData = try encoder.encode(request)
            _ = try await httpClient.post("/v1/subscriptionSubmissions", body: bodyData)

            let result = [
                "success": true,
                "message": "Subscription '\(subscriptionId)' submitted for review"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to submit subscription for review: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatSubscription(_ sub: ASCSubscription) -> [String: Any] {
        return [
            "id": sub.id,
            "type": sub.type,
            "name": sub.attributes.name.jsonSafe,
            "productId": sub.attributes.productId.jsonSafe,
            "familySharable": sub.attributes.familySharable.jsonSafe,
            "state": sub.attributes.state.jsonSafe,
            "subscriptionPeriod": sub.attributes.subscriptionPeriod.jsonSafe,
            "groupLevel": sub.attributes.groupLevel.jsonSafe,
            "reviewNote": sub.attributes.reviewNote.jsonSafe
        ]
    }

    private func formatLocalization(_ loc: ASCSubscriptionLocalization) -> [String: Any] {
        return [
            "id": loc.id,
            "type": loc.type,
            "locale": loc.attributes.locale.jsonSafe,
            "name": loc.attributes.name.jsonSafe,
            "description": loc.attributes.description.jsonSafe
        ]
    }

    private func formatPrice(_ price: ASCSubscriptionPrice, pricePointMap: [String: ASCSubscriptionPricePoint] = [:]) -> [String: Any] {
        var result: [String: Any] = [
            "id": price.id,
            "type": price.type,
            "startDate": price.attributes?.startDate.jsonSafe ?? NSNull(),
            "preserved": price.attributes?.preserved.jsonSafe ?? NSNull()
        ]

        // Enrich with price point data if available
        if let pricePointId = price.relationships?.subscriptionPricePoint?.data?.id,
           let pricePoint = pricePointMap[pricePointId] {
            result["customerPrice"] = pricePoint.attributes?.customerPrice.jsonSafe ?? NSNull()
            result["proceeds"] = pricePoint.attributes?.proceeds.jsonSafe ?? NSNull()
        }

        return result
    }

    private func formatPricePoint(_ point: ASCSubscriptionPricePoint) -> [String: Any] {
        return [
            "id": point.id,
            "type": point.type,
            "customerPrice": point.attributes?.customerPrice.jsonSafe ?? NSNull(),
            "proceeds": point.attributes?.proceeds.jsonSafe ?? NSNull(),
            "proceedsYear2": point.attributes?.proceedsYear2.jsonSafe ?? NSNull()
        ]
    }

    private func formatGroup(_ group: ASCSubscriptionGroup) -> [String: Any] {
        return [
            "id": group.id,
            "type": group.type,
            "referenceName": group.attributes.referenceName.jsonSafe
        ]
    }
}
