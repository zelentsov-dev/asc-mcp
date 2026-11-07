import Foundation
import MCP

// MARK: - Retention Messaging Tool Handlers (ASC OpenAPI 4.6)
extension SubscriptionsWorker {

    private struct RetentionPaginationParams: Sendable {
        let limit: Int?
        let nextURL: String?
        let scope: PaginationScope
    }

    private static let retentionOfferPricesQueryParameters: [String: String] = [
        "include": "territory,subscriptionPricePoint",
        "fields[retentionOfferPrices]": "territory,subscriptionPricePoint",
        "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory",
        "fields[territories]": "currency"
    ]

    private static let allowedRetentionOfferModes: Set<String> = [
        "PAY_AS_YOU_GO",
        "PAY_UP_FRONT",
        "FREE_TRIAL"
    ]

    private static let allowedRetentionOfferDurations: Set<String> = [
        "THREE_DAYS",
        "ONE_WEEK",
        "TWO_WEEKS",
        "ONE_MONTH",
        "TWO_MONTHS",
        "THREE_MONTHS",
        "SIX_MONTHS",
        "ONE_YEAR"
    ]

    private static let allowedRetentionTargetSubscriptionPlanTypes: Set<String> = [
        "MONTHLY",
        "UPFRONT"
    ]

    private func isAllowedRetentionEligibilityDuration(_ months: Int) -> Bool {
        (1...24).contains(months) || [36, 48, 60].contains(months)
    }

    private func isAllowedRetentionWaitBetweenOffers(_ months: Int) -> Bool {
        (2...24).contains(months)
    }

    // MARK: - 1. List Retention Messages

    /// Lists retention messages configured for an app (`GET /v1/apps/{id}/retentionMessages`).
    /// - Returns: JSON array of retention messages and optional pagination `next_url`.
    func listRetentionMessages(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "app_id", "limit", "next_url"
            ])
            let encodedAppId = try validateRetentionRequiredResourceID(params.arguments, key: "app_id")
            let endpointPath = "/v1/apps/\(try ASCPathSegment.encode(encodedAppId, field: "app_id"))/retentionMessages"
            let pagination = try parseRetentionPagination(
                params.arguments,
                endpointPath: endpointPath
            )

            let response: ASCRetentionMessagesResponse
            if let nextURL = pagination.nextURL {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: pagination.scope,
                    as: ASCRetentionMessagesResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]
                if let limit = pagination.limit {
                    queryParams["limit"] = String(limit)
                }
                response = try await httpClient.get(
                    endpointPath,
                    parameters: queryParams,
                    as: ASCRetentionMessagesResponse.self
                )
            }

            let messages = response.data.map { formatRetentionMessage($0) }
            var result: [String: Any] = [
                "success": true,
                "data": messages,
                "retention_messages": messages,
                "count": messages.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list retention messages: \(error.localizedDescription)")
        }
    }

    // MARK: - 2. Get Retention Message

    /// Gets details of a retention message by ID (`GET /v1/retentionMessages/{id}`).
    /// - Returns: JSON object with retention message details.
    func getRetentionMessage(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "retention_message_id"
            ])
            let encodedMessageId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "retention_message_id"
            )

            let response: ASCRetentionMessageResponse = try await httpClient.get(
                "/v1/retentionMessages/\(try ASCPathSegment.encode(encodedMessageId, field: "retention_message_id"))",
                as: ASCRetentionMessageResponse.self
            )

            let formatted = formatRetentionMessage(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "retention_message": formatted
            ])
        } catch {
            return MCPResult.error("Failed to get retention message: \(error.localizedDescription)")
        }
    }

    // MARK: - 3. Create Retention Message

    /// Creates a retention message for an app (`POST /v1/retentionMessages`).
    /// - Returns: JSON object with the created retention message.
    func createRetentionMessage(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "app_id", "reference_name"
            ])
            let appId = try validateRetentionRequiredResourceID(params.arguments, key: "app_id")
            let referenceName = try validateRetentionReferenceName(params.arguments, key: "reference_name")

            let request = RetentionMessageCreateRequest(
                appId: appId,
                referenceName: referenceName
            )

            let response: ASCRetentionMessageResponse = try await httpClient.post(
                "/v1/retentionMessages",
                body: request,
                as: ASCRetentionMessageResponse.self
            )

            let formatted = formatRetentionMessage(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "retention_message": formatted
            ])
        } catch {
            return MCPResult.error("Failed to create retention message: \(error.localizedDescription)")
        }
    }

    // MARK: - 4. Delete Retention Message

    /// Deletes a retention message by ID (`DELETE /v1/retentionMessages/{id}`).
    /// - Returns: JSON confirmation of deletion.
    func deleteRetentionMessage(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "retention_message_id"
            ])
            let encodedMessageId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "retention_message_id"
            )

            _ = try await httpClient.delete("/v1/retentionMessages/\(try ASCPathSegment.encode(encodedMessageId, field: "retention_message_id"))")

            return MCPResult.jsonObject([
                "success": true,
                "deleted_id": encodedMessageId,
                "message": "Retention message '\(encodedMessageId)' deleted"
            ])
        } catch {
            return MCPResult.error("Failed to delete retention message: \(error.localizedDescription)")
        }
    }

    // MARK: - 5. List Retention Message Versions

    /// Lists versions for a retention message (`GET /v1/retentionMessages/{id}/versions`).
    /// - Returns: JSON array of retention message versions.
    func listRetentionMessageVersions(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "retention_message_id", "limit", "next_url"
            ])
            let encodedMessageId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "retention_message_id"
            )
            let endpointPath = "/v1/retentionMessages/\(try ASCPathSegment.encode(encodedMessageId, field: "retention_message_id"))/versions"
            let pagination = try parseRetentionPagination(
                params.arguments,
                endpointPath: endpointPath
            )

            let response: ASCRetentionMessageVersionsResponse
            if let nextURL = pagination.nextURL {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: pagination.scope,
                    as: ASCRetentionMessageVersionsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]
                if let limit = pagination.limit {
                    queryParams["limit"] = String(limit)
                }
                response = try await httpClient.get(
                    endpointPath,
                    parameters: queryParams,
                    as: ASCRetentionMessageVersionsResponse.self
                )
            }

            let versions = response.data.map { formatRetentionMessageVersion($0) }
            var result: [String: Any] = [
                "success": true,
                "data": versions,
                "versions": versions,
                "count": versions.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list retention message versions: \(error.localizedDescription)")
        }
    }

    // MARK: - 6. Get Retention Message Version

    /// Gets details of a retention message version by ID (`GET /v1/retentionMessageVersions/{id}`).
    /// - Returns: JSON object with retention message version details.
    func getRetentionMessageVersion(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "version_id"
            ])
            let encodedVersionId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "version_id"
            )

            let response: ASCRetentionMessageVersionResponse = try await httpClient.get(
                "/v1/retentionMessageVersions/\(try ASCPathSegment.encode(encodedVersionId, field: "version_id"))",
                as: ASCRetentionMessageVersionResponse.self
            )

            let formatted = formatRetentionMessageVersion(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "version": formatted
            ])
        } catch {
            return MCPResult.error("Failed to get retention message version: \(error.localizedDescription)")
        }
    }

    // MARK: - 7. Create Retention Message Version

    /// Creates a new version for a retention message (`POST /v1/retentionMessageVersions`).
    /// - Returns: JSON object with the created retention message version.
    func createRetentionMessageVersion(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "retention_message_id"
            ])
            let retentionMessageId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "retention_message_id"
            )

            let request = RetentionMessageVersionCreateRequest(
                retentionMessageId: retentionMessageId
            )

            let response: ASCRetentionMessageVersionResponse = try await httpClient.post(
                "/v1/retentionMessageVersions",
                body: request,
                as: ASCRetentionMessageVersionResponse.self
            )

            let formatted = formatRetentionMessageVersion(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "version": formatted
            ])
        } catch {
            return MCPResult.error("Failed to create retention message version: \(error.localizedDescription)")
        }
    }

    // MARK: - 8. List Retention Message Localizations

    /// Lists localizations for a retention message version (`GET /v1/retentionMessageVersions/{id}/localizations`).
    /// - Returns: JSON array of retention message localizations.
    func listRetentionMessageLocalizations(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "version_id", "limit", "next_url"
            ])
            let encodedVersionId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "version_id"
            )
            let endpointPath = "/v1/retentionMessageVersions/\(try ASCPathSegment.encode(encodedVersionId, field: "version_id"))/localizations"
            let pagination = try parseRetentionPagination(
                params.arguments,
                endpointPath: endpointPath
            )

            let response: ASCRetentionMessageLocalizationsResponse
            if let nextURL = pagination.nextURL {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: pagination.scope,
                    as: ASCRetentionMessageLocalizationsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]
                if let limit = pagination.limit {
                    queryParams["limit"] = String(limit)
                }
                response = try await httpClient.get(
                    endpointPath,
                    parameters: queryParams,
                    as: ASCRetentionMessageLocalizationsResponse.self
                )
            }

            let localizations = response.data.map { formatRetentionMessageLocalization($0) }
            var result: [String: Any] = [
                "success": true,
                "data": localizations,
                "localizations": localizations,
                "count": localizations.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list retention message localizations: \(error.localizedDescription)")
        }
    }

    // MARK: - 9. Get Retention Message Localization

    /// Gets details of a retention message localization by ID (`GET /v1/retentionMessageLocalizations/{id}`).
    /// - Returns: JSON object with retention message localization details.
    func getRetentionMessageLocalization(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "localization_id"
            ])
            let encodedLocalizationId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "localization_id"
            )

            let response: ASCRetentionMessageLocalizationResponse = try await httpClient.get(
                "/v1/retentionMessageLocalizations/\(try ASCPathSegment.encode(encodedLocalizationId, field: "localization_id"))",
                as: ASCRetentionMessageLocalizationResponse.self
            )

            let formatted = formatRetentionMessageLocalization(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "localization": formatted
            ])
        } catch {
            return MCPResult.error("Failed to get retention message localization: \(error.localizedDescription)")
        }
    }

    // MARK: - 10. Create Retention Message Localization

    /// Creates a localization for a retention message version (`POST /v1/retentionMessageLocalizations`).
    /// - Returns: JSON object with the created retention message localization.
    func createRetentionMessageLocalization(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "version_id", "locale", "header", "body", "allow_price_mentions"
            ])
            let versionId = try validateRetentionRequiredResourceID(params.arguments, key: "version_id")
            let locale = try validateRetentionRequiredLocale(params.arguments, key: "locale")
            let allowPriceMentions = try parseOptionalBooleanArgument(
                params.arguments,
                key: "allow_price_mentions"
            ) ?? false

            let header = try validateRequiredRetentionCopyField(
                params.arguments,
                key: "header",
                maxLength: 66,
                allowPriceMentions: allowPriceMentions
            )
            let body = try validateRequiredRetentionCopyField(
                params.arguments,
                key: "body",
                maxLength: 144,
                allowPriceMentions: allowPriceMentions
            )

            let request = RetentionMessageLocalizationCreateRequest(
                versionId: versionId,
                locale: locale,
                header: header,
                body: body
            )

            let response: ASCRetentionMessageLocalizationResponse = try await httpClient.post(
                "/v1/retentionMessageLocalizations",
                body: request,
                as: ASCRetentionMessageLocalizationResponse.self
            )

            let formatted = formatRetentionMessageLocalization(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "localization": formatted
            ])
        } catch {
            return MCPResult.error("Failed to create retention message localization: \(error.localizedDescription)")
        }
    }

    // MARK: - 11. Update Retention Message Localization

    /// Updates a retention message localization (`PATCH /v1/retentionMessageLocalizations/{id}`).
    /// - Returns: JSON object with the updated retention message localization.
    func updateRetentionMessageLocalization(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "localization_id", "header", "body", "allow_price_mentions"
            ])
            let encodedLocalizationId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "localization_id"
            )
            let allowPriceMentions = try parseOptionalBooleanArgument(
                params.arguments,
                key: "allow_price_mentions"
            ) ?? false

            let headerPatch = try validateOptionalRetentionCopyPatchField(
                params.arguments,
                key: "header",
                maxLength: 66,
                allowPriceMentions: allowPriceMentions
            )
            let bodyPatch = try validateOptionalRetentionCopyPatchField(
                params.arguments,
                key: "body",
                maxLength: 144,
                allowPriceMentions: allowPriceMentions
            )

            guard headerPatch != nil || bodyPatch != nil else {
                return MCPResult.error(
                    "At least one of 'header' or 'body' must be provided when updating a retention message localization"
                )
            }

            let request = RetentionMessageLocalizationUpdateRequest(
                localizationId: encodedLocalizationId,
                header: headerPatch,
                body: bodyPatch
            )

            let response: ASCRetentionMessageLocalizationResponse = try await httpClient.patch(
                "/v1/retentionMessageLocalizations/\(try ASCPathSegment.encode(encodedLocalizationId, field: "localization_id"))",
                body: request,
                as: ASCRetentionMessageLocalizationResponse.self
            )

            let formatted = formatRetentionMessageLocalization(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "localization": formatted
            ])
        } catch {
            return MCPResult.error("Failed to update retention message localization: \(error.localizedDescription)")
        }
    }

    // MARK: - 12. Delete Retention Message Localization

    /// Deletes a retention message localization by ID (`DELETE /v1/retentionMessageLocalizations/{id}`).
    /// - Returns: JSON confirmation of deletion.
    func deleteRetentionMessageLocalization(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "localization_id"
            ])
            let encodedLocalizationId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "localization_id"
            )

            _ = try await httpClient.delete("/v1/retentionMessageLocalizations/\(try ASCPathSegment.encode(encodedLocalizationId, field: "localization_id"))")

            return MCPResult.jsonObject([
                "success": true,
                "deleted_id": encodedLocalizationId,
                "message": "Retention message localization '\(encodedLocalizationId)' deleted"
            ])
        } catch {
            return MCPResult.error("Failed to delete retention message localization: \(error.localizedDescription)")
        }
    }

    // MARK: - 13. List Retention Message Subscriptions

    /// Lists subscriptions associated with a retention message (`GET /v1/retentionMessages/{id}/subscriptions`).
    /// - Returns: JSON array of subscriptions linked to the retention message.
    func listRetentionMessageSubscriptions(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "retention_message_id", "limit", "next_url"
            ])
            let encodedMessageId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "retention_message_id"
            )
            let endpointPath = "/v1/retentionMessages/\(try ASCPathSegment.encode(encodedMessageId, field: "retention_message_id"))/subscriptions"
            let pagination = try parseRetentionPagination(
                params.arguments,
                endpointPath: endpointPath
            )

            let response: ASCRetentionMessageSubscriptionsResponse
            if let nextURL = pagination.nextURL {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: pagination.scope,
                    as: ASCRetentionMessageSubscriptionsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]
                if let limit = pagination.limit {
                    queryParams["limit"] = String(limit)
                }
                response = try await httpClient.get(
                    endpointPath,
                    parameters: queryParams,
                    as: ASCRetentionMessageSubscriptionsResponse.self
                )
            }

            let subscriptions = response.data.map { sub -> [String: Any] in
                var item: [String: Any] = [
                    "id": sub.id,
                    "type": sub.type
                ]
                if let name = sub.attributes?.name { item["name"] = name }
                if let productId = sub.attributes?.productId { item["productId"] = productId }
                if let state = sub.attributes?.state { item["state"] = state }
                if let period = sub.attributes?.subscriptionPeriod { item["subscriptionPeriod"] = period }
                return item
            }

            var result: [String: Any] = [
                "success": true,
                "data": subscriptions,
                "subscriptions": subscriptions,
                "count": subscriptions.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list retention message subscriptions: \(error.localizedDescription)")
        }
    }

    // MARK: - 14. List Retention Offers

    /// Lists retention offers for a subscription (`GET /v1/subscriptions/{id}/retentionOffers` or `/retentionMessageOffers`).
    /// - Returns: JSON array of retention offers.
    func listRetentionOffers(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "subscription_id", "message_offers_only", "limit", "next_url"
            ])
            let encodedSubId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "subscription_id"
            )
            let messageOffersOnly = try parseOptionalBooleanArgument(
                params.arguments,
                key: "message_offers_only"
            ) ?? false

            let endpointPath = messageOffersOnly
                ? "/v1/subscriptions/\(try ASCPathSegment.encode(encodedSubId, field: "subscription_id"))/retentionMessageOffers"
                : "/v1/subscriptions/\(try ASCPathSegment.encode(encodedSubId, field: "subscription_id"))/retentionOffers"

            let pagination = try parseRetentionPagination(
                params.arguments,
                endpointPath: endpointPath
            )

            let response: ASCRetentionOffersResponse
            if let nextURL = pagination.nextURL {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: pagination.scope,
                    as: ASCRetentionOffersResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]
                if let limit = pagination.limit {
                    queryParams["limit"] = String(limit)
                }
                response = try await httpClient.get(
                    endpointPath,
                    parameters: queryParams,
                    as: ASCRetentionOffersResponse.self
                )
            }

            let offers = response.data.map { formatRetentionOffer($0) }
            var result: [String: Any] = [
                "success": true,
                "data": offers,
                "offers": offers,
                "message_offers_only": messageOffersOnly,
                "count": offers.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list retention offers: \(error.localizedDescription)")
        }
    }

    // MARK: - 15. Get Retention Offer

    /// Gets details of a retention offer by ID (`GET /v1/retentionOffers/{id}`).
    /// - Returns: JSON object with retention offer details.
    func getRetentionOffer(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "offer_id"
            ])
            let encodedOfferId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "offer_id"
            )

            let response: ASCRetentionOfferResponse = try await httpClient.get(
                "/v1/retentionOffers/\(try ASCPathSegment.encode(encodedOfferId, field: "offer_id"))",
                as: ASCRetentionOfferResponse.self
            )

            let formatted = formatRetentionOffer(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "offer": formatted
            ])
        } catch {
            return MCPResult.error("Failed to get retention offer: \(error.localizedDescription)")
        }
    }

    // MARK: - 16. Create Retention Offer

    /// Creates a retention offer with inline prices (`POST /v1/retentionOffers`).
    /// - Returns: JSON object with the created retention offer.
    func createRetentionOffer(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "subscription_id",
                "reference_name",
                "offer_id",
                "duration",
                "offer_mode",
                "period_count",
                "eligibility_duration_months",
                "wait_between_offers_months",
                "target_subscription_plan_type",
                "territory_ids",
                "price_point_ids"
            ])

            let subscriptionId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "subscription_id"
            )
            let referenceName = try validateRetentionReferenceName(
                params.arguments,
                key: "reference_name"
            )
            let offerId = try validateRetentionOfferIdentifier(
                params.arguments,
                key: "offer_id"
            )
            let duration = try validateRequiredEnumString(
                params.arguments,
                key: "duration",
                allowed: Self.allowedRetentionOfferDurations
            )
            let offerMode = try validateRequiredEnumString(
                params.arguments,
                key: "offer_mode",
                allowed: Self.allowedRetentionOfferModes
            )
            let periodCount = try parseRequiredStrictPositiveInt(
                params.arguments,
                key: "period_count"
            )
            let eligibilityDurationMonths = try parseRequiredRetentionEligibilityDurationMonths(
                params.arguments,
                key: "eligibility_duration_months"
            )
            let waitBetweenOffersMonths = try parseOptionalRetentionWaitMonths(
                params.arguments,
                key: "wait_between_offers_months"
            )
            let targetSubscriptionPlanType = try validateOptionalEnumString(
                params.arguments,
                key: "target_subscription_plan_type",
                allowed: Self.allowedRetentionTargetSubscriptionPlanTypes
            )

            let territoryIds = try parseRequiredUniqueCanonicalIDArray(
                params.arguments,
                key: "territory_ids"
            )
            let pricePointIds = try parseRequiredCanonicalIDArray(
                params.arguments,
                key: "price_point_ids"
            )

            if territoryIds.count != pricePointIds.count {
                return MCPResult.error(
                    "'territory_ids' count (\(territoryIds.count)) must match 'price_point_ids' count (\(pricePointIds.count))"
                )
            }

            var priceIdentifiers: [ASCResourceIdentifier] = []
            var inlinePrices: [RetentionOfferPriceInlineCreate] = []

            for (index, pricePointId) in pricePointIds.enumerated() {
                let inlineId = "${price-\(index)}"
                priceIdentifiers.append(
                    ASCResourceIdentifier(type: "retentionOfferPrices", id: inlineId)
                )
                let territoryRel = RetentionOfferPriceInlineCreate.TerritoryRelationship(
                    data: ASCResourceIdentifier(type: "territories", id: territoryIds[index])
                )

                inlinePrices.append(
                    RetentionOfferPriceInlineCreate(
                        id: inlineId,
                        relationships: RetentionOfferPriceInlineCreate.Relationships(
                            subscriptionPricePoint: RetentionOfferPriceInlineCreate.PricePointRelationship(
                                data: ASCResourceIdentifier(type: "subscriptionPricePoints", id: pricePointId)
                            ),
                            territory: territoryRel
                        )
                    )
                )
            }

            let request = RetentionOfferCreateRequest(
                data: RetentionOfferCreateRequest.CreateData(
                    attributes: RetentionOfferCreateRequest.Attributes(
                        referenceName: referenceName,
                        offerId: offerId,
                        duration: duration,
                        offerMode: offerMode,
                        periodCount: periodCount,
                        customerEligibilityPaidSubscriptionDurationInMonths: eligibilityDurationMonths,
                        customerEligibilityWaitBetweenOffersInMonths: waitBetweenOffersMonths,
                        targetSubscriptionPlanType: targetSubscriptionPlanType
                    ),
                    relationships: RetentionOfferCreateRequest.Relationships(
                        subscription: RetentionOfferCreateRequest.SubscriptionRelationship(
                            data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                        ),
                        prices: RetentionOfferCreateRequest.PricesRelationship(
                            data: priceIdentifiers
                        )
                    )
                ),
                included: inlinePrices
            )

            let response: ASCRetentionOfferResponse = try await httpClient.post(
                "/v1/retentionOffers",
                body: request,
                as: ASCRetentionOfferResponse.self
            )

            let formatted = formatRetentionOffer(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "offer": formatted
            ])
        } catch {
            return MCPResult.error("Failed to create retention offer: \(error.localizedDescription)")
        }
    }

    // MARK: - 17. Update Retention Offer

    /// Updates a retention offer (`PATCH /v1/retentionOffers/{id}`).
    /// - Returns: JSON object with the updated retention offer.
    func updateRetentionOffer(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "offer_id",
                "eligibility_duration_months",
                "wait_between_offers_months"
            ])

            let encodedOfferId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "offer_id"
            )

            let eligibilityDurationPatch = try parseNullableRetentionEligibilityDurationMonths(
                params.arguments,
                key: "eligibility_duration_months"
            )
            let waitPatch = try parseNullableRetentionWaitMonths(
                params.arguments,
                key: "wait_between_offers_months"
            )

            guard eligibilityDurationPatch != nil || waitPatch != nil else {
                return MCPResult.error(
                    "At least one of 'eligibility_duration_months' or 'wait_between_offers_months' must be provided"
                )
            }

            let request = RetentionOfferUpdateRequest(
                offerId: encodedOfferId,
                customerEligibilityPaidSubscriptionDurationInMonths: eligibilityDurationPatch,
                customerEligibilityWaitBetweenOffersInMonths: waitPatch
            )

            let response: ASCRetentionOfferResponse = try await httpClient.patch(
                "/v1/retentionOffers/\(try ASCPathSegment.encode(encodedOfferId, field: "offer_id"))",
                body: request,
                as: ASCRetentionOfferResponse.self
            )

            let formatted = formatRetentionOffer(response.data)
            return MCPResult.jsonObject([
                "success": true,
                "data": formatted,
                "offer": formatted
            ])
        } catch {
            return MCPResult.error("Failed to update retention offer: \(error.localizedDescription)")
        }
    }

    // MARK: - 18. Delete Retention Offer

    /// Deletes a retention offer by ID (`DELETE /v1/retentionOffers/{id}`).
    /// - Returns: JSON confirmation of deletion.
    func deleteRetentionOffer(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "offer_id"
            ])
            let encodedOfferId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "offer_id"
            )

            _ = try await httpClient.delete("/v1/retentionOffers/\(try ASCPathSegment.encode(encodedOfferId, field: "offer_id"))")

            return MCPResult.jsonObject([
                "success": true,
                "deleted_id": encodedOfferId,
                "message": "Retention offer '\(encodedOfferId)' deleted"
            ])
        } catch {
            return MCPResult.error("Failed to delete retention offer: \(error.localizedDescription)")
        }
    }

    // MARK: - 19. List Retention Offer Prices

    /// Lists territory prices for a retention offer (`GET /v1/retentionOffers/{id}/prices`).
    /// - Returns: JSON array of retention offer prices.
    func listRetentionOfferPrices(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "offer_id", "territory", "limit", "next_url"
            ])
            let encodedOfferId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "offer_id"
            )
            let territories = try parseOptionalTerritoryFilter(params.arguments, key: "territory")
            let endpointPath = "/v1/retentionOffers/\(try ASCPathSegment.encode(encodedOfferId, field: "offer_id"))/prices"

            var requiredPaginationParams: [String: String] = [:]
            if let territories, !territories.isEmpty {
                requiredPaginationParams["filter[territory]"] = territories.joined(separator: ",")
            }

            let pagination = try parseRetentionPagination(
                params.arguments,
                endpointPath: endpointPath,
                requiredParameters: requiredPaginationParams,
                optionalFixedParameters: Self.retentionOfferPricesQueryParameters
            )

            let response: ASCRetentionOfferPricesResponse
            if let nextURL = pagination.nextURL {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: pagination.scope,
                    as: ASCRetentionOfferPricesResponse.self
                )
            } else {
                var queryParams = Self.retentionOfferPricesQueryParameters
                if let limit = pagination.limit {
                    queryParams["limit"] = String(limit)
                }
                if let territories, !territories.isEmpty {
                    queryParams["filter[territory]"] = territories.joined(separator: ",")
                }
                response = try await httpClient.get(
                    endpointPath,
                    parameters: queryParams,
                    as: ASCRetentionOfferPricesResponse.self
                )
            }

            let prices = response.data.map { formatRetentionOfferPrice($0, included: response.included) }
            var result: [String: Any] = [
                "success": true,
                "data": prices,
                "prices": prices,
                "count": prices.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list retention offer prices: \(error.localizedDescription)")
        }
    }

    // MARK: - 20. Get Retention Message For Subscription

    /// Gets the retention message assigned to a subscription (`GET /v1/subscriptions/{id}/retentionMessage`).
    /// Handles `{"data": null}` when no retention message is currently assigned.
    /// - Returns: JSON object with the assigned retention message or `null`.
    func getRetentionMessageForSubscription(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "subscription_id"
            ])
            let encodedSubId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "subscription_id"
            )

            let response: ASCRetentionMessageOptionalResponse = try await httpClient.get(
                "/v1/subscriptions/\(try ASCPathSegment.encode(encodedSubId, field: "subscription_id"))/retentionMessage",
                as: ASCRetentionMessageOptionalResponse.self
            )

            if let message = response.data {
                let formatted = formatRetentionMessage(message)
                return MCPResult.jsonObject([
                    "success": true,
                    "subscription_id": encodedSubId,
                    "has_retention_message": true,
                    "data": formatted,
                    "retention_message": formatted
                ])
            } else {
                return MCPResult.jsonObject([
                    "success": true,
                    "subscription_id": encodedSubId,
                    "has_retention_message": false,
                    "data": NSNull(),
                    "retention_message": NSNull()
                ])
            }
        } catch {
            return MCPResult.error("Failed to get retention message for subscription: \(error.localizedDescription)")
        }
    }

    // MARK: - 21. Set Retention Message For Subscription

    /// Assigns or clears the retention message for a subscription (`PATCH /v1/subscriptions/{id}/relationships/retentionMessage`).
    /// - Returns: JSON confirmation of assignment or clearing.
    func setRetentionMessage(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "subscription_id", "retention_message_id", "clear"
            ])
            let encodedSubId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "subscription_id"
            )

            let targetMessageId = try resolveRetentionMessageAssignmentTarget(params.arguments)
            let request = SubscriptionRetentionMessageLinkageRequest(
                retentionMessageId: targetMessageId
            )
            let bodyData = try JSONEncoder().encode(request)

            let receipt = try await httpClient.patchReceipt(
                "/v1/subscriptions/\(try ASCPathSegment.encode(encodedSubId, field: "subscription_id"))/relationships/retentionMessage",
                body: bodyData
            )
            guard [200, 204].contains(receipt.statusCode) else {
                throw ASCError.network("Unexpected HTTP status \(receipt.statusCode)")
            }

            if let targetMessageId {
                return MCPResult.jsonObject([
                    "success": true,
                    "subscription_id": encodedSubId,
                    "retention_message_id": targetMessageId,
                    "cleared": false
                ])
            } else {
                return MCPResult.jsonObject([
                    "success": true,
                    "subscription_id": encodedSubId,
                    "retention_message_id": NSNull(),
                    "cleared": true
                ])
            }
        } catch {
            return MCPResult.error("Failed to set retention message for subscription: \(error.localizedDescription)")
        }
    }

    // MARK: - 22. Add Retention Message Offers

    /// Attaches retention offers to a subscription (`POST /v1/subscriptions/{id}/relationships/retentionMessageOffers`).
    /// - Returns: JSON confirmation of attached offer IDs.
    func addRetentionMessageOffers(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "subscription_id", "offer_ids"
            ])
            let encodedSubId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "subscription_id"
            )
            let offerIds = try parseRequiredUniqueCanonicalIDArray(
                params.arguments,
                key: "offer_ids"
            )

            let request = SubscriptionRetentionMessageOffersLinkagesRequest(offerIds: offerIds)
            let bodyData = try JSONEncoder().encode(request)

            let receipt = try await httpClient.postReceipt(
                "/v1/subscriptions/\(try ASCPathSegment.encode(encodedSubId, field: "subscription_id"))/relationships/retentionMessageOffers",
                body: bodyData
            )
            guard [200, 201, 204].contains(receipt.statusCode) else {
                throw ASCError.network("Unexpected HTTP status \(receipt.statusCode)")
            }

            return MCPResult.jsonObject([
                "success": true,
                "subscription_id": encodedSubId,
                "added_offer_ids": offerIds,
                "count": offerIds.count
            ])
        } catch {
            return MCPResult.error("Failed to add retention message offers: \(error.localizedDescription)")
        }
    }

    // MARK: - 23. Remove Retention Message Offers

    /// Removes retention offers from a subscription (`DELETE /v1/subscriptions/{id}/relationships/retentionMessageOffers`).
    /// - Returns: JSON confirmation of removed offer IDs.
    func removeRetentionMessageOffers(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            try validateRetentionAllowedArguments(params.arguments, allowedKeys: [
                "subscription_id", "offer_ids"
            ])
            let encodedSubId = try validateRetentionRequiredResourceID(
                params.arguments,
                key: "subscription_id"
            )
            let offerIds = try parseRequiredUniqueCanonicalIDArray(
                params.arguments,
                key: "offer_ids"
            )

            let request = SubscriptionRetentionMessageOffersLinkagesRequest(offerIds: offerIds)
            _ = try await httpClient.delete(
                "/v1/subscriptions/\(try ASCPathSegment.encode(encodedSubId, field: "subscription_id"))/relationships/retentionMessageOffers",
                body: request
            )

            return MCPResult.jsonObject([
                "success": true,
                "subscription_id": encodedSubId,
                "removed_offer_ids": offerIds,
                "count": offerIds.count
            ])
        } catch {
            return MCPResult.error("Failed to remove retention message offers: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation Helpers

    private func validateRetentionAllowedArguments(
        _ arguments: [String: Value]?,
        allowedKeys: Set<String>
    ) throws {
        guard let arguments else { return }
        let unknown = Set(arguments.keys).subtracting(allowedKeys).sorted()
        guard unknown.isEmpty else {
            throw ASCError.parsing("Unsupported parameter(s): \(unknown.joined(separator: ", "))")
        }
    }

    private func validateRetentionRequiredResourceID(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> String {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .string(let value) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be a string")
        }
        return try validateCanonicalIDString(value, field: key)
    }

    private func validateRetentionRequiredLocale(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> String {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .string(let value) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be a string")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, value == trimmed else {
            throw ASCError.parsing("Parameter '\(key)' must be a non-empty locale code without surrounding whitespace")
        }
        let localeErrors = ASCMetadataValidator.validateLocale(value, field: key)
        if let firstError = localeErrors.first {
            throw ASCError.parsing(firstError.message)
        }
        return value
    }

    private func parseRetentionPagination(
        _ arguments: [String: Value]?,
        endpointPath: String,
        requiredParameters: [String: String] = [:],
        optionalFixedParameters: [String: String] = [:]
    ) throws -> RetentionPaginationParams {
        var parsedLimit: Int?
        if let rawLimit = arguments?["limit"], rawLimit != .null {
            guard case .int(let intLimit) = rawLimit, (1...200).contains(intLimit) else {
                throw ASCError.parsing("Parameter 'limit' must be an integer between 1 and 200")
            }
            parsedLimit = intLimit
        }

        var effectiveRequired = requiredParameters
        if let parsedLimit {
            effectiveRequired["limit"] = String(parsedLimit)
        }

        var allowedKeys: Set<String> = ["cursor", "limit"]
        allowedKeys.formUnion(effectiveRequired.keys)
        allowedKeys.formUnion(optionalFixedParameters.keys)

        var parsedNextURL: String?
        if let rawNext = arguments?["next_url"], rawNext != .null {
            guard case .string(let nextString) = rawNext else {
                throw ASCError.parsing("Parameter 'next_url' must be a string")
            }
            let trimmed = nextString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, nextString == trimmed else {
                throw ASCError.parsing("Parameter 'next_url' must be a non-empty URL without surrounding whitespace")
            }
            guard let components = URLComponents(string: nextString),
                  components.user == nil,
                  components.password == nil,
                  components.fragment == nil else {
                throw ASCError.parsing("Invalid 'next_url' format")
            }

            if let queryItems = components.queryItems {
                for item in queryItems {
                    guard allowedKeys.contains(item.name) else {
                        throw ASCError.parsing(
                            "Unsupported query parameter '\(item.name)' in 'next_url'"
                        )
                    }
                    if item.name == "limit" {
                        guard let val = item.value,
                              let intLimit = Int(val),
                              (1...200).contains(intLimit) else {
                            throw ASCError.parsing(
                                "Invalid 'limit' in 'next_url': must be between 1 and 200"
                            )
                        }
                    }
                    if let expectedFixedValue = optionalFixedParameters[item.name] {
                        effectiveRequired[item.name] = expectedFixedValue
                    }
                }
            }

            parsedNextURL = nextString
        }

        let scope = PaginationScope(
            path: endpointPath,
            requiredParameters: effectiveRequired,
            allowedParameters: allowedKeys,
            requiredNonEmptyParameters: ["cursor"]
        )

        return RetentionPaginationParams(limit: parsedLimit, nextURL: parsedNextURL, scope: scope)
    }

    private func validateRetentionReferenceName(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> String {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .string(let value) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be a string")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ASCError.parsing("Parameter '\(key)' cannot be empty")
        }
        guard value.count <= 64 else {
            throw ASCError.parsing("Parameter '\(key)' must be at most 64 characters (got \(value.count))")
        }
        try validateNoEmoji(in: value, field: key)
        return value
    }

    private func validateRequiredRetentionCopyField(
        _ arguments: [String: Value]?,
        key: String,
        maxLength: Int,
        allowPriceMentions: Bool
    ) throws -> String {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .string(let value) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be a string")
        }
        return try validateRetentionCopyString(
            value,
            field: key,
            maxLength: maxLength,
            allowPriceMentions: allowPriceMentions
        )
    }

    private func validateOptionalRetentionCopyPatchField(
        _ arguments: [String: Value]?,
        key: String,
        maxLength: Int,
        allowPriceMentions: Bool
    ) throws -> ASCNullable<String>? {
        guard let rawValue = arguments?[key] else {
            return nil
        }
        switch rawValue {
        case .null:
            return .null
        case .string(let value):
            let validated = try validateRetentionCopyString(
                value,
                field: key,
                maxLength: maxLength,
                allowPriceMentions: allowPriceMentions
            )
            return .value(validated)
        default:
            throw ASCError.parsing("Parameter '\(key)' must be a string or null")
        }
    }

    private func validateRetentionCopyString(
        _ value: String,
        field: String,
        maxLength: Int,
        allowPriceMentions: Bool
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ASCError.parsing("Parameter '\(field)' cannot be empty")
        }
        guard value.count <= maxLength else {
            throw ASCError.parsing(
                "Parameter '\(field)' exceeds maximum length of \(maxLength) characters (got \(value.count))"
            )
        }
        try validateNoEmoji(in: value, field: field)

        if !allowPriceMentions {
            try validateNoPriceOrDiscountMentions(in: value, field: field)
        }
        return value
    }

    private func validateNoEmoji(in text: String, field: String) throws {
        if ASCMetadataValidator.containsEmoji(text) {
            throw ASCError.parsing("Parameter '\(field)' must not contain emoji characters")
        }
    }

    private func validateNoPriceOrDiscountMentions(in text: String, field: String) throws {
        let forbiddenSymbols: Set<Character> = ["$", "€", "£", "¥", "₽", "%"]
        if text.contains(where: { forbiddenSymbols.contains($0) }) {
            throw ASCError.parsing(
                "Parameter '\(field)' contains a currency or percentage symbol. Apple forbids price or discount references in Retention Message localizations because the message is shown to all cancelling subscribers regardless of offer eligibility. Pass 'allow_price_mentions: true' only if intentional."
            )
        }

        let pricePattern = #"\d+[.,]\d{2}"#
        if text.range(of: pricePattern, options: .regularExpression) != nil {
            throw ASCError.parsing(
                "Parameter '\(field)' contains a numeric price pattern. Apple forbids price or discount references in Retention Message localizations because the message is shown to all cancelling subscribers regardless of offer eligibility. Pass 'allow_price_mentions: true' only if intentional."
            )
        }
    }

    private func parseOptionalBooleanArgument(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> Bool? {
        guard let rawValue = arguments?[key], rawValue != .null else {
            return nil
        }
        guard case .bool(let boolValue) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be a boolean")
        }
        return boolValue
    }

    private func validateRequiredEnumString(
        _ arguments: [String: Value]?,
        key: String,
        allowed: Set<String>
    ) throws -> String {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .string(let value) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be a string")
        }
        guard allowed.contains(value) else {
            let sorted = allowed.sorted().joined(separator: ", ")
            throw ASCError.parsing("Invalid '\(key)' value '\(value)'. Allowed values: \(sorted)")
        }
        return value
    }

    private func validateRetentionOfferIdentifier(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> String {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .string(let value) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be a string")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, value == trimmed else {
            throw ASCError.parsing("Parameter '\(key)' must be a non-empty identifier without surrounding whitespace")
        }
        try validateNoEmoji(in: value, field: key)
        return value
    }

    private func validateOptionalEnumString(
        _ arguments: [String: Value]?,
        key: String,
        allowed: Set<String>
    ) throws -> String? {
        guard let rawValue = arguments?[key], rawValue != .null else {
            return nil
        }
        guard case .string(let value) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be a string")
        }
        guard allowed.contains(value) else {
            let sorted = allowed.sorted().joined(separator: ", ")
            throw ASCError.parsing("Invalid '\(key)' value '\(value)'. Allowed values: \(sorted)")
        }
        return value
    }

    private func parseRequiredStrictPositiveInt(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> Int {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .int(let intValue) = rawValue, intValue >= 1 else {
            throw ASCError.parsing("Parameter '\(key)' must be an integer >= 1")
        }
        return intValue
    }

    private func parseRequiredRetentionEligibilityDurationMonths(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> Int {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .int(let intValue) = rawValue,
              isAllowedRetentionEligibilityDuration(intValue) else {
            throw ASCError.parsing(
                "Parameter '\(key)' must be 1 through 24, 36, 48, or 60"
            )
        }
        return intValue
    }

    private func parseNullableRetentionEligibilityDurationMonths(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> ASCNullable<Int>? {
        guard let rawValue = arguments?[key] else {
            return nil
        }
        switch rawValue {
        case .null:
            return .null
        case .int(let intValue) where isAllowedRetentionEligibilityDuration(intValue):
            return .value(intValue)
        default:
            throw ASCError.parsing(
                "Parameter '\(key)' must be 1 through 24, 36, 48, 60, or null"
            )
        }
    }

    private func parseOptionalRetentionWaitMonths(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> Int? {
        guard let rawValue = arguments?[key], rawValue != .null else {
            return nil
        }
        guard case .int(let intValue) = rawValue,
              isAllowedRetentionWaitBetweenOffers(intValue) else {
            throw ASCError.parsing(
                "Parameter '\(key)' must be an integer between 2 and 24"
            )
        }
        return intValue
    }

    private func parseNullableRetentionWaitMonths(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> ASCNullable<Int>? {
        guard let rawValue = arguments?[key] else {
            return nil
        }
        switch rawValue {
        case .null:
            return .null
        case .int(let intValue) where isAllowedRetentionWaitBetweenOffers(intValue):
            return .value(intValue)
        default:
            throw ASCError.parsing(
                "Parameter '\(key)' must be an integer between 2 and 24 or null"
            )
        }
    }

    private func parseRequiredCanonicalIDArray(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> [String] {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .array(let arrayValues) = rawValue, !arrayValues.isEmpty else {
            throw ASCError.parsing("Parameter '\(key)' must be a non-empty array of strings")
        }

        var result: [String] = []
        for (index, element) in arrayValues.enumerated() {
            guard case .string(let rawId) = element else {
                throw ASCError.parsing("Parameter '\(key)[\(index)]' must be a string")
            }
            let validatedId = try validateCanonicalIDString(rawId, field: "\(key)[\(index)]")
            result.append(validatedId)
        }
        return result
    }

    private func parseRequiredUniqueCanonicalIDArray(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> [String] {
        guard let rawValue = arguments?[key] else {
            throw ASCError.parsing("Required parameter '\(key)' is missing")
        }
        guard case .array(let arrayValues) = rawValue, !arrayValues.isEmpty else {
            throw ASCError.parsing("Parameter '\(key)' must be a non-empty array of strings")
        }

        var result: [String] = []
        var seen: Set<String> = []
        for (index, element) in arrayValues.enumerated() {
            guard case .string(let rawId) = element else {
                throw ASCError.parsing("Parameter '\(key)[\(index)]' must be a string")
            }
            let validatedId = try validateCanonicalIDString(rawId, field: "\(key)[\(index)]")
            guard seen.insert(validatedId).inserted else {
                throw ASCError.parsing("Duplicate ID '\(validatedId)' in '\(key)'")
            }
            result.append(validatedId)
        }
        return result
    }

    private func parseOptionalCanonicalIDArray(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> [String]? {
        guard let rawValue = arguments?[key], rawValue != .null else {
            return nil
        }
        guard case .array(let arrayValues) = rawValue else {
            throw ASCError.parsing("Parameter '\(key)' must be an array of strings")
        }

        var result: [String] = []
        for (index, element) in arrayValues.enumerated() {
            guard case .string(let rawId) = element else {
                throw ASCError.parsing("Parameter '\(key)[\(index)]' must be a string")
            }
            let validatedId = try validateCanonicalIDString(rawId, field: "\(key)[\(index)]")
            result.append(validatedId)
        }
        return result
    }

    private func parseOptionalTerritoryFilter(
        _ arguments: [String: Value]?,
        key: String
    ) throws -> [String]? {
        guard let rawValue = arguments?[key], rawValue != .null else {
            return nil
        }
        switch rawValue {
        case .string(let rawString):
            let parts = rawString
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else {
                throw ASCError.parsing("Parameter '\(key)' must not be empty")
            }
            return try parts.enumerated().map { idx, part in
                try validateCanonicalIDString(part, field: "\(key)[\(idx)]")
            }
        case .array(let items):
            guard !items.isEmpty else {
                throw ASCError.parsing("Parameter '\(key)' must not be an empty array")
            }
            return try items.enumerated().map { idx, element in
                guard case .string(let str) = element else {
                    throw ASCError.parsing("Parameter '\(key)[\(idx)]' must be a string")
                }
                return try validateCanonicalIDString(str, field: "\(key)[\(idx)]")
            }
        default:
            throw ASCError.parsing("Parameter '\(key)' must be a string or array of strings")
        }
    }

    private func validateCanonicalIDString(_ rawValue: String, field: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, rawValue == trimmed else {
            throw ASCError.parsing("Parameter '\(field)' must be a non-empty canonical ID without surrounding whitespace")
        }
        let encoded = try ASCPathSegment.encode(rawValue, field: field)
        guard encoded == rawValue else {
            throw ASCError.parsing("Parameter '\(field)' contains invalid characters")
        }
        return rawValue
    }

    private func resolveRetentionMessageAssignmentTarget(
        _ arguments: [String: Value]?
    ) throws -> String? {
        let rawMessageId = arguments?["retention_message_id"]
        let clearFlag = try parseOptionalBooleanArgument(arguments, key: "clear")

        switch rawMessageId {
        case .some(.string(let messageId)):
            if clearFlag == true {
                throw ASCError.parsing(
                    "Ambiguous parameters: cannot provide a non-null 'retention_message_id' together with 'clear: true'"
                )
            }
            return try validateCanonicalIDString(messageId, field: "retention_message_id")

        case .some(.null):
            if clearFlag == false {
                throw ASCError.parsing(
                    "Ambiguous parameters: cannot provide 'retention_message_id: null' together with 'clear: false'"
                )
            }
            return nil

        case .none:
            guard clearFlag == true else {
                throw ASCError.parsing(
                    "Provide either a non-empty 'retention_message_id' to assign a message, or 'clear: true' (or 'retention_message_id: null') to clear it"
                )
            }
            return nil

        case .some:
            throw ASCError.parsing("Parameter 'retention_message_id' must be a string or null")
        }
    }

    // MARK: - Formatting Helpers

    private func formatRetentionMessage(_ message: ASCRetentionMessage) -> [String: Any] {
        var result: [String: Any] = [
            "id": message.id,
            "type": message.type
        ]
        if let referenceName = message.attributes?.referenceName {
            result["referenceName"] = referenceName
        }
        if let appId = message.relationships?.app?.data?.id {
            result["appId"] = appId
        }
        return result
    }

    private func formatRetentionMessageVersion(_ version: ASCRetentionMessageVersion) -> [String: Any] {
        var result: [String: Any] = [
            "id": version.id,
            "type": version.type
        ]
        if let state = version.attributes?.state {
            result["state"] = state
        }
        if let versionNumber = version.attributes?.version {
            result["version"] = versionNumber
        }
        if let retentionMessageId = version.relationships?.retentionMessage?.data?.id {
            result["retentionMessageId"] = retentionMessageId
        }
        if let placementId = version.relationships?.placement?.data?.id {
            result["placementId"] = placementId
        }
        return result
    }

    private func formatRetentionMessageLocalization(_ localization: ASCRetentionMessageLocalization) -> [String: Any] {
        var result: [String: Any] = [
            "id": localization.id,
            "type": localization.type
        ]
        if let locale = localization.attributes?.locale {
            result["locale"] = locale
        }
        if let header = localization.attributes?.header {
            result["header"] = header
        }
        if let body = localization.attributes?.body {
            result["body"] = body
        }
        if let versionId = localization.relationships?.retentionMessageVersion?.data?.id
            ?? localization.relationships?.version?.data?.id {
            result["versionId"] = versionId
        }
        return result
    }

    private func formatRetentionOffer(_ offer: ASCRetentionOffer) -> [String: Any] {
        var result: [String: Any] = [
            "id": offer.id,
            "type": offer.type
        ]
        if let attributes = offer.attributes {
            if let referenceName = attributes.referenceName {
                result["referenceName"] = referenceName
                result["reference_name"] = referenceName
            }
            if let offerId = attributes.offerId {
                result["offerId"] = offerId
                result["offer_id"] = offerId
            }
            if let duration = attributes.duration {
                result["duration"] = duration
            }
            if let offerMode = attributes.offerMode {
                result["offerMode"] = offerMode
                result["offer_mode"] = offerMode
            }
            if let periodCount = attributes.periodCount {
                result["periodCount"] = periodCount
                result["period_count"] = periodCount
            }
            if let eligibilityDuration = attributes.customerEligibilityPaidSubscriptionDurationInMonths {
                result["customerEligibilityPaidSubscriptionDurationInMonths"] = eligibilityDuration
                result["customer_eligibility_paid_subscription_duration_in_months"] = eligibilityDuration
                result["eligibilityDurationMonths"] = eligibilityDuration
                result["eligibility_duration_months"] = eligibilityDuration
            }
            if let waitMonths = attributes.customerEligibilityWaitBetweenOffersInMonths {
                result["customerEligibilityWaitBetweenOffersInMonths"] = waitMonths
                result["customer_eligibility_wait_between_offers_months"] = waitMonths
                result["waitBetweenOffersMonths"] = waitMonths
                result["wait_between_offers_months"] = waitMonths
            }
            if let targetPlanType = attributes.targetSubscriptionPlanType {
                result["targetSubscriptionPlanType"] = targetPlanType
                result["target_subscription_plan_type"] = targetPlanType
            }
        }
        if let subscriptionId = offer.relationships?.subscription?.data?.id {
            result["subscriptionId"] = subscriptionId
            result["subscription_id"] = subscriptionId
        }
        return result
    }

    private func formatRetentionOfferPrice(
        _ price: ASCRetentionOfferPrice,
        included: [ASCWinBackOfferPriceIncludedResource]? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": price.id,
            "type": price.type
        ]
        let pricePointId = price.relationships?.subscriptionPricePoint?.data?.id
        let pricePoint = pricePointId.flatMap { id in
            included?.first(where: { $0.type == "subscriptionPricePoints" && $0.id == id })
        }
        let territoryId = price.relationships?.territory?.data?.id
            ?? pricePoint?.relationships?["territory"]?.objectValue?["data"]?.objectValue?["id"]?.stringValue
        let territory = territoryId.flatMap { id in
            included?.first(where: { $0.type == "territories" && $0.id == id })
        }

        if let territoryId {
            result["territoryId"] = territoryId
            result["territory_id"] = territoryId
        }
        if let pricePointId {
            result["subscriptionPricePointId"] = pricePointId
            result["subscription_price_point_id"] = pricePointId
            result["price_point_id"] = pricePointId
        }
        if let currency = territory?.attributes?["currency"]?.stringValue {
            result["currency"] = currency
        }
        if let customerPrice = pricePoint?.attributes?["customerPrice"]?.stringValue {
            result["customerPrice"] = customerPrice
            result["customer_price"] = customerPrice
        }
        if let proceeds = pricePoint?.attributes?["proceeds"]?.stringValue {
            result["proceeds"] = proceeds
        }
        if let proceedsYear2 = pricePoint?.attributes?["proceedsYear2"]?.stringValue {
            result["proceedsYear2"] = proceedsYear2
            result["proceeds_year2"] = proceedsYear2
        }
        return result
    }
}
