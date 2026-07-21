import Foundation
import MCP

// MARK: - Tool Handlers
extension InAppPurchasesWorker {
    func validateIAPLocalizationArguments(
        _ arguments: [String: Value],
        locale: String? = nil
    ) -> [ASCMetadataValidator.FieldError] {
        var errors: [ASCMetadataValidator.FieldError] = []
        if let locale {
            errors += ASCMetadataValidator.validateLocale(locale)
        }

        var textFields: [String: String] = [:]
        for key in ["name", "description"] {
            if let value = arguments[key]?.stringValue {
                textFields[key] = value
            }
        }

        errors += ASCMetadataValidator.validateTextFields(
            textFields,
            limits: [
                "name": 30,
                "description": 45
            ]
        )
        return errors
    }


    /// Lists in-app purchases for an app
    /// - Returns: JSON array of IAPs with attributes
    func listIAP(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCInAppPurchasesV2Response

            var selection: [String: String] = [:]
            if let value = try iapCatalogQueryValue(arguments["filter_name"], field: "filter_name") {
                selection["filter[name]"] = value
            }
            if let value = try iapCatalogQueryValue(arguments["filter_product_id"], field: "filter_product_id") {
                selection["filter[productId]"] = value
            }
            if let value = try iapCatalogQueryValue(
                arguments["filter_state"],
                field: "filter_state",
                allowedValues: Set(Self.iapCatalogStates)
            ) {
                selection["filter[state]"] = value
            }
            if let value = try iapCatalogQueryValue(
                arguments["filter_type"],
                field: "filter_type",
                allowedValues: Set(Self.iapCatalogTypes)
            ) {
                selection["filter[inAppPurchaseType]"] = value
            }
            if let value = try iapCatalogQueryValue(
                arguments["sort"],
                field: "sort",
                allowedValues: Set(Self.iapCatalogSortValues)
            ) {
                selection["sort"] = value
            }

            var queryParams = selection
            queryParams["limit"] = String(try validatedCommerceLimit(arguments["limit"], defaultValue: 25, maximum: 200))
            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/inAppPurchasesV2"

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(path: endpoint, query: queryParams),
                    as: ASCInAppPurchasesV2Response.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
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
            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list IAPs: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCInAppPurchaseV2Response = try await httpClient.get(
                "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))",
                as: ASCInAppPurchaseV2Response.self
            )

            let iap = formatIAP(response.data)

            let result = [
                "success": true,
                "in_app_purchase": iap
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get IAP: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: app_id, name, product_id, iap_type")],
                isError: true
            )
        }

        guard Self.supportedIAPTypes.contains(iapType) else {
            return MCPResult.error("iap_type must be one of: \(Self.supportedIAPTypes.sorted().joined(separator: ", "))")
        }

        do {
            let reviewNote = try nullableIAPString("review_note", from: arguments)
            let familySharable = try nullableIAPBool("family_sharable", from: arguments)
            let request = CreateInAppPurchaseV2Request(
                data: CreateInAppPurchaseV2Request.CreateIAPData(
                    attributes: CreateInAppPurchaseV2Request.CreateIAPAttributes(
                        name: name,
                        productId: productId,
                        inAppPurchaseType: iapType,
                        reviewNote: reviewNote,
                        familySharable: familySharable
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

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create IAP")
        }
    }

    /// Updates an in-app purchase
    /// - Returns: JSON with updated IAP details
    func updateIAP(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        let mutableFields: Set<String> = ["name", "review_note", "family_sharable"]
        guard arguments.keys.contains(where: mutableFields.contains) else {
            return MCPResult.error("At least one mutable in-app purchase field is required")
        }

        do {
            let name = try nullableIAPString("name", from: arguments)
            let reviewNote = try nullableIAPString("review_note", from: arguments)
            let familySharable = try nullableIAPBool("family_sharable", from: arguments)
            let request = UpdateInAppPurchaseV2Request(
                data: UpdateInAppPurchaseV2Request.UpdateIAPData(
                    id: iapId,
                    attributes: UpdateInAppPurchaseV2Request.UpdateIAPAttributes(
                        name: name,
                        reviewNote: reviewNote,
                        familySharable: familySharable
                    )
                )
            )

            let response: ASCInAppPurchaseV2Response = try await httpClient.patch(
                "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))",
                body: request,
                as: ASCInAppPurchaseV2Response.self
            )

            let iap = formatIAP(response.data)

            let result = [
                "success": true,
                "in_app_purchase": iap
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update IAP")
        }
    }

    private func nullableIAPString(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> ASCNullable<String>? {
        guard let value = arguments[name] else {
            return nil
        }
        if case .null = value {
            return .null
        }
        guard let string = value.stringValue else {
            throw IAPWriteInputError("\(name) must be a string or null")
        }
        return .value(string)
    }

    private func nullableIAPBool(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> ASCNullable<Bool>? {
        guard let value = arguments[name] else {
            return nil
        }
        if case .null = value {
            return .null
        }
        guard let bool = value.boolValue else {
            throw IAPWriteInputError("\(name) must be a Boolean or null")
        }
        return .value(bool)
    }

    /// Deletes an in-app purchase
    /// - Returns: JSON confirmation
    func deleteIAP(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))")

            let result = [
                "success": true,
                "message": "IAP '\(iapId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete IAP")
        }
    }

    /// Lists localizations for an in-app purchase
    /// - Returns: JSON array of localizations
    func listIAPLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCInAppPurchaseLocalizationsResponse
            let endpoint = "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/inAppPurchaseLocalizations"
            let query = [
                "limit": String(try validatedCommerceLimit(arguments["limit"], defaultValue: 25, maximum: 200))
            ]

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(path: endpoint, query: query),
                    as: ASCInAppPurchaseLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
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
            appendLegacyIAPDeprecation(
                to: &result,
                tool: "iap_list_localizations",
                replacements: ["iap_list_versions", "iap_list_version_localizations"]
            )

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list IAP localizations: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCSubscriptionGroupsResponse

            var selection: [String: String] = [:]
            if let value = try iapCatalogQueryValue(arguments["filter_reference_name"], field: "filter_reference_name") {
                selection["filter[referenceName]"] = value
            }
            if let value = try iapCatalogQueryValue(
                arguments["filter_subscription_state"],
                field: "filter_subscription_state",
                allowedValues: Set(Self.subscriptionCatalogStates)
            ) {
                selection["filter[subscriptions.state]"] = value
            }
            if let value = try iapCatalogQueryValue(
                arguments["sort"],
                field: "sort",
                allowedValues: Set(Self.subscriptionGroupSortValues)
            ) {
                selection["sort"] = value
            }

            var queryParams = selection
            queryParams["limit"] = String(try validatedCommerceLimit(arguments["limit"], defaultValue: 25, maximum: 200))
            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/subscriptionGroups"

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(path: endpoint, query: queryParams),
                    as: ASCSubscriptionGroupsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list subscription groups: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'group_id' is missing")],
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
                "/v1/subscriptionGroups/\(try ASCPathSegment.encode(groupId))",
                parameters: queryParams,
                as: ASCSubscriptionGroupResponse.self
            )

            let group = formatSubscriptionGroup(response.data)
            let included = response.included ?? []

            let result = [
                "success": true,
                "subscription_group": group,
                "subscriptions": included
                    .filter { $0.objectValue?["type"]?.stringValue == "subscriptions" }
                    .map(\.asAny),
                "included": included.map(\.asAny)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get subscription group: \(error.localizedDescription)")],
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
            return MCPResult.error("Required parameters: iap_id, locale, name")
        }

        let validationErrors = validateIAPLocalizationArguments(arguments, locale: locale)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
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

            var result = [
                "success": true,
                "localization": localization
            ] as [String: Any]
            appendLegacyIAPDeprecation(
                to: &result,
                tool: "iap_create_localization",
                replacements: [
                    "iap_list_versions",
                    "iap_create_version",
                    "iap_create_version_localization"
                ]
            )

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create IAP localization")
        }
    }

    /// Updates a localization for an in-app purchase
    /// - Returns: JSON with updated localization details
    func updateIAPLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return MCPResult.error("Required parameter 'localization_id' is missing")
        }

        let validationErrors = validateIAPLocalizationArguments(arguments)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
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
                "/v1/inAppPurchaseLocalizations/\(try ASCPathSegment.encode(localizationId))",
                body: request,
                as: ASCInAppPurchaseLocalizationResponse.self
            )

            let localization = formatLocalization(response.data)

            var result = [
                "success": true,
                "localization": localization
            ] as [String: Any]
            appendLegacyIAPDeprecation(
                to: &result,
                tool: "iap_update_localization",
                replacements: ["iap_update_version_localization"]
            )

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update IAP localization")
        }
    }

    /// Deletes a localization for an in-app purchase
    /// - Returns: JSON confirmation
    func deleteIAPLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/inAppPurchaseLocalizations/\(try ASCPathSegment.encode(localizationId))")

            var result = [
                "success": true,
                "message": "IAP localization '\(localizationId)' deleted"
            ] as [String: Any]
            appendLegacyIAPDeprecation(
                to: &result,
                tool: "iap_delete_localization",
                replacements: ["iap_delete_version_localization"]
            )

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete IAP localization")
        }
    }

    /// Submits an in-app purchase for review
    /// - Returns: JSON confirmation with IAP ID
    func submitIAPForReview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapIdValue = arguments["iap_id"],
              let iapId = iapIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'iap_id' is missing")],
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

            var result = [
                "success": true,
                "message": "IAP '\(iapId)' submitted for review"
            ] as [String: Any]
            appendLegacyIAPDeprecation(
                to: &result,
                tool: "iap_submit_for_review",
                replacements: [
                    "iap_list_versions",
                    "iap_create_version",
                    "review_submissions_create",
                    "review_submissions_add_item",
                    "review_submissions_submit"
                ]
            )

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to submit IAP for review")
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
                content: [MCPContent.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIAPPricePointsResponse
            let endpoint = "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/pricePoints"
            var query = [
                "limit": String(try validatedCommerceLimit(arguments["limit"], defaultValue: 50, maximum: 8000))
            ]
            if let territory = arguments["territory"]?.stringValue {
                query["filter[territory]"] = territory
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(path: endpoint, query: query),
                    as: ASCIAPPricePointsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list IAP price points: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIAPPriceScheduleResponse = try await httpClient.get(
                "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/iapPriceSchedule",
                as: ASCIAPPriceScheduleResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "price_schedule": [
                    "id": response.data.id,
                    "type": response.data.type
                ]
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get IAP price schedule: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: iap_id, base_territory_id")],
                isError: true
            )
        }

        let legacyManualPrices = arguments["manual_price_ids"]
        let inlineManualPrices = arguments["manual_prices"]
        guard legacyManualPrices == nil || inlineManualPrices == nil else {
            return MCPResult.error("manual_price_ids and manual_prices are mutually exclusive")
        }

        let manualPriceIdentifiers: [ASCResourceIdentifier]
        let includedManualPrices: [CreateIAPPriceScheduleRequest.ManualPriceInlineCreate]?

        if let inlineManualPrices {
            guard let values = inlineManualPrices.arrayValue else {
                return MCPResult.error("manual_prices must be an array of objects")
            }

            var identifiers: [ASCResourceIdentifier] = []
            var included: [CreateIAPPriceScheduleRequest.ManualPriceInlineCreate] = []
            for (index, value) in values.enumerated() {
                guard let object = value.objectValue,
                      let pricePointId = object["price_point_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !pricePointId.isEmpty else {
                    return MCPResult.error("manual_prices[\(index)].price_point_id is required")
                }

                let allowedKeys: Set<String> = ["price_point_id", "start_date", "end_date"]
                if let unsupportedKey = object.keys.first(where: { !allowedKeys.contains($0) }) {
                    return MCPResult.error("manual_prices[\(index)] contains unsupported field '\(unsupportedKey)'")
                }

                if object["start_date"] != nil, object["start_date"]?.stringValue == nil {
                    return MCPResult.error("manual_prices[\(index)].start_date must be a string")
                }
                if object["end_date"] != nil, object["end_date"]?.stringValue == nil {
                    return MCPResult.error("manual_prices[\(index)].end_date must be a string")
                }
                let startDate = object["start_date"]?.stringValue
                let endDate = object["end_date"]?.stringValue
                if let startDate, !isValidIAPPriceDate(startDate) {
                    return MCPResult.error("manual_prices[\(index)].start_date must use YYYY-MM-DD")
                }
                if let endDate, !isValidIAPPriceDate(endDate) {
                    return MCPResult.error("manual_prices[\(index)].end_date must use YYYY-MM-DD")
                }
                if let startDate, let endDate, startDate > endDate {
                    return MCPResult.error("manual_prices[\(index)].start_date must not be after end_date")
                }

                let inlineId = "${price-\(index)}"
                identifiers.append(ASCResourceIdentifier(type: "inAppPurchasePrices", id: inlineId))
                included.append(CreateIAPPriceScheduleRequest.ManualPriceInlineCreate(
                    id: inlineId,
                    attributes: startDate == nil && endDate == nil
                        ? nil
                        : .init(startDate: startDate, endDate: endDate),
                    relationships: .init(
                        inAppPurchaseV2: .init(
                            data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                        ),
                        inAppPurchasePricePoint: .init(
                            data: ASCResourceIdentifier(type: "inAppPurchasePricePoints", id: pricePointId)
                        )
                    )
                ))
            }
            manualPriceIdentifiers = identifiers
            includedManualPrices = included
        } else if let legacyManualPrices {
            guard let csv = legacyManualPrices.stringValue else {
                return MCPResult.error("manual_price_ids must be a comma-separated string")
            }
            let ids = csv
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !ids.isEmpty, ids.allSatisfy({ !$0.isEmpty }) else {
                return MCPResult.error("manual_price_ids must contain only non-empty IDs")
            }
            manualPriceIdentifiers = ids.map {
                ASCResourceIdentifier(type: "inAppPurchasePrices", id: $0)
            }
            includedManualPrices = nil
        } else {
            manualPriceIdentifiers = []
            includedManualPrices = nil
        }

        do {
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
                ),
                included: includedManualPrices
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

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to set IAP price schedule")
        }
    }

    private func isValidIAPPriceDate(_ value: String) -> Bool {
        guard value.count == 10,
              value[value.index(value.startIndex, offsetBy: 4)] == "-",
              value[value.index(value.startIndex, offsetBy: 7)] == "-" else {
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    // MARK: - Availability

    /// Sets territorial availability for an in-app purchase
    /// - Returns: JSON with availability details
    func setIAPAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue,
              let availableInNewTerritories = arguments["available_in_new_territories"]?.boolValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: iap_id, available_in_new_territories")],
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

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to set IAP availability")
        }
    }

    /// Gets availability details for an in-app purchase
    /// - Returns: JSON with availability details and territories
    func getIAPAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let availabilityId = arguments["availability_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'availability_id' is missing")],
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
                "/v1/inAppPurchaseAvailabilities/\(try ASCPathSegment.encode(availabilityId))",
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
                    "currency": ($0.attributes?.currency).jsonSafe
                ] as [String: Any] }
                resultDict["territories"] = territories
                resultDict["territory_count"] = territories.count
            }

            return MCPResult.jsonObject(resultDict)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get IAP availability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func formatAvailability(_ availability: ASCIAPAvailability) -> [String: Any] {
        return [
            "id": availability.id,
            "type": availability.type,
            "availableInNewTerritories": (availability.attributes?.availableInNewTerritories).jsonSafe
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
                content: [MCPContent.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIAPReviewScreenshotResponse = try await httpClient.get(
                "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/appStoreReviewScreenshot",
                as: ASCIAPReviewScreenshotResponse.self
            )

            let screenshot = formatReviewScreenshot(response.data)

            let result: [String: Any] = [
                "success": true,
                "review_screenshot": screenshot
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get IAP review screenshot: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Uploads and verifies a review screenshot for an in-app purchase
    /// - Returns: JSON with terminal or accepted processing-pending screenshot info
    /// - Throws: On file read, upload, or API errors
    func uploadIAPReviewScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: iap_id, file_path")],
                isError: true
            )
        }

        let outcome: UploadTransactionOutcome<ASCIAPReviewScreenshot> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "IAP review screenshot",
            expectedType: "inAppPurchaseAppStoreReviewScreenshots",
            reservationEndpoint: "/v1/inAppPurchaseAppStoreReviewScreenshots",
            httpClient: httpClient,
            uploadService: uploadService,
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { fileSize, fileName in
                try JSONEncoder().encode(
                    CreateIAPReviewScreenshotRequest(
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
                )
            },
            decodeResource: {
                try JSONDecoder().decode(ASCIAPReviewScreenshotResponse.self, from: $0).data
            },
            makeCommitBody: { screenshotId, checksum in
                try JSONEncoder().encode(
                    CommitIAPReviewScreenshotRequest(
                        data: CommitIAPReviewScreenshotRequest.CommitData(
                            id: screenshotId,
                            attributes: CommitIAPReviewScreenshotRequest.Attributes(
                                sourceFileChecksum: checksum,
                                uploaded: true
                            )
                        )
                    )
                )
            },
            resourceEndpoint: { "/v1/inAppPurchaseAppStoreReviewScreenshots/\(try ASCPathSegment.encode($0))" }
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "IAP review screenshot",
                successKey: "review_screenshot",
                idArgument: "screenshot_id",
                getTool: "iap_get_review_screenshot",
                getIDArgument: nil,
                deleteTool: "iap_delete_review_screenshot",
                inspectionTool: "iap_get_review_screenshot",
                inspectionArguments: ["iap_id": iapId]
            ),
            format: formatReviewScreenshot
        )
    }

    /// Deletes an IAP review screenshot
    /// - Returns: JSON confirmation
    /// - Throws: On network errors
    func deleteIAPReviewScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let screenshotId = arguments["screenshot_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'screenshot_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/inAppPurchaseAppStoreReviewScreenshots/\(try ASCPathSegment.encode(screenshotId))")

            let result = [
                "success": true,
                "message": "IAP review screenshot '\(screenshotId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete IAP review screenshot")
        }
    }

    // MARK: - IAP Images

    /// Uploads an IAP image and reconciles its asynchronous processing state
    /// - Returns: JSON with terminal or accepted processing-pending image info
    func uploadIAPImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: iap_id, file_path")],
                isError: true
            )
        }

        let outcome: UploadTransactionOutcome<ASCIAPImage> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "IAP image",
            expectedType: "inAppPurchaseImages",
            reservationEndpoint: "/v1/inAppPurchaseImages",
            httpClient: httpClient,
            uploadService: uploadService,
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { fileSize, fileName in
                try JSONEncoder().encode(
                    CreateIAPImageRequest(
                        data: CreateIAPImageRequest.CreateData(
                            attributes: CreateIAPImageRequest.Attributes(
                                fileSize: fileSize,
                                fileName: fileName
                            ),
                            relationships: CreateIAPImageRequest.Relationships(
                                inAppPurchase: CreateIAPImageRequest.IAPImageRelationship(
                                    data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                                )
                            )
                        )
                    )
                )
            },
            decodeResource: {
                try JSONDecoder().decode(ASCIAPImageResponse.self, from: $0).data
            },
            makeCommitBody: { imageId, checksum in
                try JSONEncoder().encode(
                    CommitIAPImageRequest(
                        data: CommitIAPImageRequest.CommitData(
                            id: imageId,
                            attributes: CommitIAPImageRequest.Attributes(
                                sourceFileChecksum: checksum,
                                uploaded: true
                            )
                        )
                    )
                )
            },
            resourceEndpoint: { "/v1/inAppPurchaseImages/\(try ASCPathSegment.encode($0))" }
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "IAP image",
                successKey: "image",
                idArgument: "image_id",
                getTool: "iap_get_image",
                getIDArgument: "image_id",
                deleteTool: "iap_delete_image",
                inspectionTool: "iap_list_images",
                inspectionArguments: ["iap_id": iapId]
            ),
            additionalSuccessFields: legacyIAPDeprecationFields(
                tool: "iap_upload_image",
                replacements: [
                    "iap_list_versions",
                    "iap_create_version",
                    "iap_upload_version_image"
                ]
            ),
            format: formatIAPImage
        )
    }

    /// Gets details of an IAP image
    /// - Returns: JSON with image details
    func getIAPImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let imageId = arguments["image_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'image_id' is missing")],
                isError: true
            )
        }

        do {
            let data = try await httpClient.get("/v1/inAppPurchaseImages/\(try ASCPathSegment.encode(imageId))")
            let response = try JSONDecoder().decode(ASCIAPImageResponse.self, from: data)

            var result = [
                "success": true,
                "image": formatIAPImage(response.data)
            ] as [String: Any]
            appendLegacyIAPDeprecation(
                to: &result,
                tool: "iap_get_image",
                replacements: ["iap_get_version_image_resource"]
            )

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get IAP image: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an IAP image
    /// - Returns: JSON confirmation
    func deleteIAPImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let imageId = arguments["image_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'image_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/inAppPurchaseImages/\(try ASCPathSegment.encode(imageId))")

            var result = [
                "success": true,
                "message": "IAP image '\(imageId)' deleted"
            ] as [String: Any]
            appendLegacyIAPDeprecation(
                to: &result,
                tool: "iap_delete_image",
                replacements: ["iap_delete_version_image"]
            )

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete IAP image")
        }
    }

    /// Lists images for an in-app purchase
    /// - Returns: JSON array of IAP images
    /// - Throws: On network or decoding errors
    func listIAPImages(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapId = arguments["iap_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'iap_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCIAPImagesResponse
            let endpoint = "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapId))/images"
            let query = [
                "limit": String(try validatedCommerceLimit(arguments["limit"], defaultValue: 25, maximum: 200))
            ]

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: iapCommercePaginationScope(path: endpoint, query: query),
                    as: ASCIAPImagesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCIAPImagesResponse.self
                )
            }

            let images = response.data.map { formatIAPImage($0) }

            var result: [String: Any] = [
                "success": true,
                "images": images,
                "count": images.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }
            appendLegacyIAPDeprecation(
                to: &result,
                tool: "iap_list_images",
                replacements: ["iap_list_versions", "iap_get_version_image"]
            )

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list IAP images: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func formatIAPImage(_ image: ASCIAPImage) -> [String: Any] {
        var result: [String: Any] = [
            "id": image.id,
            "type": image.type,
            "fileName": (image.attributes?.fileName).jsonSafe,
            "fileSize": (image.attributes?.fileSize).jsonSafe,
            "sourceFileChecksum": (image.attributes?.sourceFileChecksum).jsonSafe,
            "state": (image.attributes?.state).jsonSafe
        ]

        if let imageAsset = image.attributes?.imageAsset {
            result["imageAsset"] = [
                "templateUrl": imageAsset.templateUrl.jsonSafe,
                "width": imageAsset.width.jsonSafe,
                "height": imageAsset.height.jsonSafe
            ]
        }

        return result
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

    func iapCatalogQueryValue(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> String? {
        guard let value else {
            return nil
        }

        let values: [String]
        if let string = value.stringValue {
            values = [string]
        } else if let array = value.arrayValue {
            let strings = array.compactMap(\.stringValue)
            guard strings.count == array.count else {
                throw ASCError.parsing("'\(field)' must be a string or an array of strings")
            }
            values = strings
        } else {
            throw ASCError.parsing("'\(field)' must be a string or an array of strings")
        }

        guard !values.isEmpty else {
            throw ASCError.parsing("'\(field)' must contain at least one value")
        }
        guard values.allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed == value
        }) else {
            throw ASCError.parsing("'\(field)' must contain only non-empty strings without surrounding whitespace")
        }
        guard values.allSatisfy({ !$0.contains(",") }) else {
            throw ASCError.parsing("'\(field)' values must not contain commas")
        }
        guard Set(values).count == values.count else {
            throw ASCError.parsing("'\(field)' must not contain duplicate values")
        }
        if let allowedValues {
            let unsupported = values.filter { !allowedValues.contains($0) }
            guard unsupported.isEmpty else {
                throw ASCError.parsing("Unsupported value(s) for '\(field)': \(unsupported.joined(separator: ", "))")
            }
        }

        return values.joined(separator: ",")
    }

    func iapCommercePaginationScope(path: String, query: [String: String]) -> PaginationScope {
        PaginationScope(
            path: path,
            requiredParameters: query,
            allowedParameters: Set(query.keys).union(["cursor"]),
            requiredNonEmptyParameters: ["cursor"]
        )
    }

    private func appendLegacyIAPDeprecation(
        to result: inout [String: Any],
        tool: String,
        replacements: [String]
    ) {
        for (key, value) in legacyIAPDeprecationFields(tool: tool, replacements: replacements) {
            result[key] = value
        }
    }

    private func legacyIAPDeprecationFields(tool: String, replacements: [String]) -> [String: Any] {
        [
            "deprecated": true,
            "deprecated_since": "App Store Connect API 4.4.1",
            "warnings": [
                "\(tool) uses an Apple-deprecated product-scoped commerce API and remains available only for backward compatibility. It does not create or select a version automatically."
            ],
            "replacement_tools": replacements
        ]
    }

    private static let supportedIAPTypes: Set<String> = [
        "CONSUMABLE",
        "NON_CONSUMABLE",
        "NON_RENEWING_SUBSCRIPTION"
    ]

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
            "customerPrice": (pricePoint.attributes?.customerPrice).jsonSafe as Any,
            "proceeds": (pricePoint.attributes?.proceeds).jsonSafe as Any,
            "priceTier": (pricePoint.attributes?.priceTier).jsonSafe as Any
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

private struct IAPWriteInputError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
