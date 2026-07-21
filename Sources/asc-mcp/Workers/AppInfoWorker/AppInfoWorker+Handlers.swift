//
//  AppInfoWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of app info handlers
//

import Foundation
import MCP

// MARK: - Tool Handlers
extension AppInfoWorker {
    private func validateAppInfoLocalizationArguments(
        _ arguments: [String: Value],
        locale: String? = nil
    ) -> [ASCMetadataValidator.FieldError] {
        var errors: [ASCMetadataValidator.FieldError] = []
        if let locale {
            errors += ASCMetadataValidator.validateLocale(locale)
        }

        var textFields: [String: String] = [:]
        for key in ["name", "subtitle", "privacy_policy_text"] {
            if let value = arguments[key]?.stringValue {
                textFields[key] = value
            }
        }

        errors += ASCMetadataValidator.validateTextFields(
            textFields,
            limits: [
                "name": 30,
                "subtitle": 30
            ]
        )

        for key in ["privacy_policy_url", "privacy_choices_url"] {
            if let value = arguments[key]?.stringValue, !value.isEmpty {
                errors += ASCMetadataValidator.validateHTTPURL(value, field: key)
            }
        }

        return errors
    }


    /// Lists app info objects for an app
    /// - Returns: JSON array of app infos with attributes and relationship data
    func listAppInfos(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let path = "/v1/apps/\(try ASCPathSegment.encode(appId))/appInfos"
            var query = [
                "limit": String(
                    try boundedLimit(arguments["limit"], field: "limit", maximum: 200, defaultValue: 25)
                )
            ]
            if let includes = try stringList(
                arguments["include"],
                field: "include",
                allowedValues: allowedAppInfoIncludes
            ) {
                query["include"] = includes.joined(separator: ",")
            }
            if arguments["localizations_limit"] != nil {
                query["limit[appInfoLocalizations]"] = String(
                    try boundedLimit(
                        arguments["localizations_limit"],
                        field: "localizations_limit",
                        maximum: 50,
                        defaultValue: 50
                    )
                )
            }

            let response: ASCAppInfosResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: path, query: query),
                    as: ASCAppInfosResponse.self
                )
            } else {
                response = try await httpClient.get(path, parameters: query, as: ASCAppInfosResponse.self)
            }

            let infos = response.data.map { formatAppInfo($0) }

            var result: [String: Any] = [
                "success": true,
                "app_infos": infos,
                "count": infos.count
            ]

            if let next = response.links?.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            appendIncludedAppInfoResources(response.included, to: &result)

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list app infos: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets app info details with optional included resources
    /// - Returns: JSON with app info details and included categories/localizations
    func getAppInfo(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let infoIdValue = arguments["info_id"],
              let infoId = infoIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'info_id' is missing")],
                isError: true
            )
        }

        do {
            var queryParams: [String: String] = [:]

            if let includes = try stringList(
                arguments["include"],
                field: "include",
                allowedValues: allowedAppInfoIncludes
            ) {
                queryParams["include"] = includes.joined(separator: ",")
            }
            if arguments["localizations_limit"] != nil {
                queryParams["limit[appInfoLocalizations]"] = String(
                    try boundedLimit(
                        arguments["localizations_limit"],
                        field: "localizations_limit",
                        maximum: 50,
                        defaultValue: 50
                    )
                )
            }

            let response: ASCAppInfoResponse = try await httpClient.get(
                "/v1/appInfos/\(try ASCPathSegment.encode(infoId))",
                parameters: queryParams,
                as: ASCAppInfoResponse.self
            )

            var result: [String: Any] = [
                "success": true,
                "app_info": formatAppInfo(response.data)
            ]

            if let included = response.included {
                var apps: [[String: Any]] = []
                var ageRatingDeclarations: [[String: Any]] = []
                var categories: [[String: Any]] = []
                var localizations: [[String: Any]] = []
                var unknown: [Any] = []

                for resource in included {
                    switch resource {
                    case .app(let app):
                        apps.append(formatIncludedApp(app))
                    case .ageRatingDeclaration(let declaration):
                        ageRatingDeclarations.append(formatAgeRatingDeclaration(declaration))
                    case .appCategory(let category):
                        categories.append(formatAppCategory(category))
                    case .appInfoLocalization(let localization):
                        localizations.append(formatAppInfoLocalization(localization))
                    case .unknown(let value):
                        unknown.append(value.asAny)
                    }
                }

                if !apps.isEmpty {
                    result["included_apps"] = apps
                }
                if !ageRatingDeclarations.isEmpty {
                    result["included_age_rating_declarations"] = ageRatingDeclarations
                }
                if !categories.isEmpty {
                    result["included_categories"] = categories
                }
                if !localizations.isEmpty {
                    result["included_localizations"] = localizations
                }
                if !unknown.isEmpty {
                    result["included_unknown"] = unknown
                }
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get app info: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates app info categories
    /// - Returns: JSON with updated app info details
    func updateAppInfo(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let infoIdValue = arguments["info_id"],
              let infoId = infoIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'info_id' is missing")],
                isError: true
            )
        }

        do {
            func makeCategoryRelationship(_ field: String) throws -> UpdateAppInfoRequest.CategoryRelationship? {
                guard let value = arguments[field] else { return nil }
                guard let id = value.stringValue,
                      !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AppInfoArgumentError("'\(field)' must be a non-empty string")
                }
                return UpdateAppInfoRequest.CategoryRelationship(
                    data: ASCResourceIdentifier(type: "appCategories", id: id)
                )
            }

            let relationships = UpdateAppInfoRequest.UpdateAppInfoRelationships(
                primaryCategory: try makeCategoryRelationship("primary_category_id"),
                primarySubcategoryOne: try makeCategoryRelationship("primary_subcategory_one_id"),
                primarySubcategoryTwo: try makeCategoryRelationship("primary_subcategory_two_id"),
                secondaryCategory: try makeCategoryRelationship("secondary_category_id"),
                secondarySubcategoryOne: try makeCategoryRelationship("secondary_subcategory_one_id"),
                secondarySubcategoryTwo: try makeCategoryRelationship("secondary_subcategory_two_id")
            )

            guard relationships.hasChanges else {
                return MCPResult.error("At least one category field is required")
            }

            let request = UpdateAppInfoRequest(
                data: UpdateAppInfoRequest.UpdateAppInfoData(
                    id: infoId,
                    relationships: relationships
                )
            )

            let response: ASCAppInfoResponse = try await httpClient.patch(
                "/v1/appInfos/\(try ASCPathSegment.encode(infoId))",
                body: request,
                as: ASCAppInfoResponse.self
            )
            try validateAcceptedAppInfoMutationResource(
                type: response.data.type,
                id: response.data.id,
                expectedType: "appInfos",
                expectedID: infoId,
                method: "PATCH",
                statusCode: 200,
                context: "Apple app info update response"
            )

            let result = [
                "success": true,
                "app_info": formatAppInfo(response.data)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update app info")
        }
    }

    /// Lists app info localizations
    /// - Returns: JSON array of localizations with subtitle, privacy URL, etc.
    func listAppInfoLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let infoIdValue = arguments["info_id"],
              let infoId = infoIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'info_id' is missing")],
                isError: true
            )
        }

        do {
            let path = "/v1/appInfos/\(try ASCPathSegment.encode(infoId))/appInfoLocalizations"
            var query = [
                "limit": String(
                    try boundedLimit(arguments["limit"], field: "limit", maximum: 200, defaultValue: 25)
                )
            ]
            if let locales = try stringList(arguments["locale"], field: "locale") {
                query["filter[locale]"] = locales.joined(separator: ",")
            }
            if let includes = try stringList(
                arguments["include"],
                field: "include",
                allowedValues: ["appInfo"]
            ) {
                query["include"] = includes.joined(separator: ",")
            }

            let response: ASCAppInfoLocalizationsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: path, query: query),
                    as: ASCAppInfoLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCAppInfoLocalizationsResponse.self
                )
            }

            let localizations = response.data.map { formatAppInfoLocalization($0) }

            var result: [String: Any] = [
                "success": true,
                "localizations": localizations,
                "count": localizations.count
            ]

            if let next = response.links?.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let included = response.included, !included.isEmpty {
                result["included_app_infos"] = included.map(formatAppInfo)
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list app info localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates an app info localization
    /// - Returns: JSON with updated localization details
    func updateAppInfoLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return MCPResult.error("Required parameter 'localization_id' is missing")
        }

        let validationErrors = validateAppInfoLocalizationArguments(arguments)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        do {
            let name = try nullableString(arguments["name"], field: "name")
            let subtitle = try nullableString(arguments["subtitle"], field: "subtitle")
            let privacyPolicyURL = try nullableString(arguments["privacy_policy_url"], field: "privacy_policy_url")
            let privacyChoicesURL = try nullableString(arguments["privacy_choices_url"], field: "privacy_choices_url")
            let privacyPolicyText = try nullableString(arguments["privacy_policy_text"], field: "privacy_policy_text")
            guard [
                "name",
                "subtitle",
                "privacy_policy_url",
                "privacy_choices_url",
                "privacy_policy_text"
            ].contains(where: { arguments[$0] != nil }) else {
                return MCPResult.error("At least one localization field is required")
            }

            let request = UpdateAppInfoLocalizationRequest(
                data: UpdateAppInfoLocalizationRequest.UpdateAppInfoLocalizationData(
                    id: localizationId,
                    attributes: UpdateAppInfoLocalizationRequest.UpdateAppInfoLocalizationAttributes(
                        name: name,
                        subtitle: subtitle,
                        privacyPolicyUrl: privacyPolicyURL,
                        privacyChoicesUrl: privacyChoicesURL,
                        privacyPolicyText: privacyPolicyText
                    )
                )
            )

            let response: ASCAppInfoLocalizationResponse = try await httpClient.patch(
                "/v1/appInfoLocalizations/\(try ASCPathSegment.encode(localizationId))",
                body: request,
                as: ASCAppInfoLocalizationResponse.self
            )
            try validateAcceptedAppInfoMutationResource(
                type: response.data.type,
                id: response.data.id,
                expectedType: "appInfoLocalizations",
                expectedID: localizationId,
                method: "PATCH",
                statusCode: 200,
                context: "Apple app info localization update response"
            )

            let localization = formatAppInfoLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update app info localization")
        }
    }

    /// Creates a new app info localization for a locale
    /// - Returns: JSON with created localization details
    func createAppInfoLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let infoIdValue = arguments["info_id"],
              let infoId = infoIdValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue,
              let name = arguments["name"]?.stringValue,
              !infoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return MCPResult.error("Required parameters: info_id, locale, name")
        }

        let validationErrors = validateAppInfoLocalizationArguments(arguments, locale: locale)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        do {
            let subtitle = try nullableString(arguments["subtitle"], field: "subtitle")
            let privacyPolicyURL = try nullableString(arguments["privacy_policy_url"], field: "privacy_policy_url")
            let privacyChoicesURL = try nullableString(arguments["privacy_choices_url"], field: "privacy_choices_url")
            let privacyPolicyText = try nullableString(arguments["privacy_policy_text"], field: "privacy_policy_text")
            let request = CreateAppInfoLocalizationRequest(
                data: CreateAppInfoLocalizationRequest.CreateAppInfoLocalizationData(
                    attributes: CreateAppInfoLocalizationRequest.CreateAppInfoLocalizationAttributes(
                        locale: locale,
                        name: name,
                        subtitle: subtitle,
                        privacyPolicyUrl: privacyPolicyURL,
                        privacyChoicesUrl: privacyChoicesURL,
                        privacyPolicyText: privacyPolicyText
                    ),
                    relationships: CreateAppInfoLocalizationRequest.CreateAppInfoLocalizationRelationships(
                        appInfo: CreateAppInfoLocalizationRequest.AppInfoRelationshipData(
                            data: ASCResourceIdentifier(type: "appInfos", id: infoId)
                        )
                    )
                )
            )

            let response: ASCAppInfoLocalizationResponse = try await httpClient.post(
                "/v1/appInfoLocalizations",
                body: request,
                as: ASCAppInfoLocalizationResponse.self
            )
            try validateAcceptedAppInfoMutationResource(
                type: response.data.type,
                id: response.data.id,
                expectedType: "appInfoLocalizations",
                method: "POST",
                statusCode: 201,
                context: "Apple app info localization create response"
            )

            let localization = formatAppInfoLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create app info localization")
        }
    }

    /// Deletes an app info localization
    /// - Returns: JSON confirmation
    /// - Throws: On network errors
    func deleteAppInfoLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appInfoLocalizations/\(try ASCPathSegment.encode(localizationId))")

            let result = [
                "success": true,
                "message": "App info localization '\(localizationId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete app info localization")
        }
    }

    // MARK: - EULA Handlers

    /// Gets the current EULA for an app
    /// - Returns: JSON with EULA details or message if none exists
    func getEula(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let responseData = try await httpClient.get(
                "/v1/apps/\(try ASCPathSegment.encode(appId))/endUserLicenseAgreement",
                parameters: [:]
            )

            let response = try JSONDecoder().decode(ASCEULAResponse.self, from: responseData)

            let result: [String: Any] = [
                "success": true,
                "eula": formatEula(response.data)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get EULA (app may not have a EULA configured): \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a EULA for an app
    /// - Returns: JSON with created EULA details
    func createEula(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let textValue = arguments["agreement_text"],
              let agreementText = textValue.stringValue,
              let territoryIdsValue = arguments["territory_ids"],
              let territoryIdsArray = territoryIdsValue.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: app_id, agreement_text, territory_ids")],
                isError: true
            )
        }

        let territoryIds = territoryIdsArray.compactMap(\.stringValue)
        guard territoryIds.count == territoryIdsArray.count,
              territoryIds.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              !territoryIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("'territory_ids' must contain at least one non-empty string territory ID")],
                isError: true
            )
        }
        guard Set(territoryIds).count == territoryIds.count else {
            return MCPResult.error("'territory_ids' must not contain duplicate values")
        }

        do {
            let request = CreateEULARequest(
                data: CreateEULARequest.CreateEULAData(
                    attributes: CreateEULARequest.CreateEULAAttributes(
                        agreementText: agreementText
                    ),
                    relationships: CreateEULARequest.CreateEULARelationships(
                        app: CreateEULARequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        ),
                        territories: CreateEULARequest.TerritoriesRelationship(
                            data: territoryIds.map { ASCResourceIdentifier(type: "territories", id: $0) }
                        )
                    )
                )
            )

            let bodyData = try JSONEncoder().encode(request)
            let responseData = try await httpClient.post(
                "/v1/endUserLicenseAgreements",
                body: bodyData
            )
            let response: ASCEULAResponse
            do {
                response = try JSONDecoder().decode(ASCEULAResponse.self, from: responseData)
                try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                    type: response.data.type,
                    id: response.data.id,
                    expectedType: "endUserLicenseAgreements",
                    context: "Apple EULA create response"
                )
            } catch {
                throw committedUnverifiedAppInfoMutation(error, method: "POST", statusCode: 201)
            }

            let result: [String: Any] = [
                "success": true,
                "eula": formatEula(response.data),
                "message": "EULA created successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create EULA")
        }
    }

    /// Updates an existing EULA
    /// - Returns: JSON with updated EULA details
    func updateEula(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let eulaIdValue = arguments["eula_id"],
              let eulaId = eulaIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'eula_id' is missing")],
                isError: true
            )
        }

        do {
            let agreementText = try nullableString(arguments["agreement_text"], field: "agreement_text")
            let territoryIds: [String]?
            if let value = arguments["territory_ids"] {
                guard let values = value.arrayValue else {
                    return MCPResult.error("'territory_ids' must be an array of strings")
                }
                let parsed = values.compactMap(\.stringValue)
                guard parsed.count == values.count,
                      parsed.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    return MCPResult.error("'territory_ids' must contain only non-empty strings")
                }
                guard Set(parsed).count == parsed.count else {
                    return MCPResult.error("'territory_ids' must not contain duplicate values")
                }
                territoryIds = parsed
            } else {
                territoryIds = nil
            }
            guard arguments["agreement_text"] != nil || arguments["territory_ids"] != nil else {
                return MCPResult.error("At least one update field is required: agreement_text or territory_ids")
            }

            let request = UpdateEULARequest(
                data: UpdateEULARequest.UpdateEULAData(
                    id: eulaId,
                    attributes: agreementText.map {
                        UpdateEULARequest.UpdateEULAAttributes(agreementText: $0)
                    },
                    relationships: territoryIds.map {
                        UpdateEULARequest.UpdateEULARelationships(
                            territories: UpdateEULARequest.TerritoriesRelationship(
                                data: $0.map { ASCResourceIdentifier(type: "territories", id: $0) }
                            )
                        )
                    }
                )
            )

            let bodyData = try JSONEncoder().encode(request)
            let responseData = try await httpClient.patch(
                "/v1/endUserLicenseAgreements/\(try ASCPathSegment.encode(eulaId))",
                body: bodyData
            )
            let response: ASCEULAResponse
            do {
                response = try JSONDecoder().decode(ASCEULAResponse.self, from: responseData)
                try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                    type: response.data.type,
                    id: response.data.id,
                    expectedType: "endUserLicenseAgreements",
                    expectedID: eulaId,
                    context: "Apple EULA update response"
                )
            } catch {
                throw committedUnverifiedAppInfoMutation(error, method: "PATCH", statusCode: 200)
            }

            let result: [String: Any] = [
                "success": true,
                "eula": formatEula(response.data),
                "message": "EULA updated successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update EULA")
        }
    }

    // MARK: - Formatting

    private func formatAppInfo(_ info: ASCAppInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "id": info.id,
            "type": info.type,
            "appStoreState": (info.attributes?.appStoreState).jsonSafe,
            "appStoreAgeRating": (info.attributes?.appStoreAgeRating).jsonSafe,
            "australiaAgeRating": (info.attributes?.australiaAgeRating).jsonSafe,
            "brazilAgeRating": (info.attributes?.brazilAgeRating).jsonSafe,
            "brazilAgeRatingV2": (info.attributes?.brazilAgeRatingV2).jsonSafe,
            "franceAgeRating": (info.attributes?.franceAgeRating).jsonSafe,
            "koreaAgeRating": (info.attributes?.koreaAgeRating).jsonSafe,
            "kidsAgeBand": (info.attributes?.kidsAgeBand).jsonSafe,
            "state": (info.attributes?.state).jsonSafe
        ]

        // Include relationship IDs if available
        if let relationships = info.relationships {
            if let app = relationships.app?.data {
                dict["appId"] = app.id
            }
            if let declaration = relationships.ageRatingDeclaration?.data {
                dict["ageRatingDeclarationId"] = declaration.id
            }
            if let primaryCategory = relationships.primaryCategory?.data {
                dict["primaryCategoryId"] = primaryCategory.id
            }
            if let primarySubOne = relationships.primarySubcategoryOne?.data {
                dict["primarySubcategoryOneId"] = primarySubOne.id
            }
            if let primarySubTwo = relationships.primarySubcategoryTwo?.data {
                dict["primarySubcategoryTwoId"] = primarySubTwo.id
            }
            if let secondaryCategory = relationships.secondaryCategory?.data {
                dict["secondaryCategoryId"] = secondaryCategory.id
            }
            if let secondarySubOne = relationships.secondarySubcategoryOne?.data {
                dict["secondarySubcategoryOneId"] = secondarySubOne.id
            }
            if let secondarySubTwo = relationships.secondarySubcategoryTwo?.data {
                dict["secondarySubcategoryTwoId"] = secondarySubTwo.id
            }
            if let localizations = relationships.appInfoLocalizations?.data {
                dict["localizationIds"] = localizations.map(\.id)
            }
            if let territoryAgeRatings = relationships.territoryAgeRatings?.data {
                dict["territoryAgeRatingIds"] = territoryAgeRatings.map(\.id)
            }
            if let relatedURL = relationships.territoryAgeRatings?.links?.related {
                dict["territoryAgeRatingsUrl"] = relatedURL
            }
        }

        return dict
    }

    private func formatAppInfoLocalization(_ loc: ASCAppInfoLocalization) -> [String: Any] {
        var result: [String: Any] = [
            "id": loc.id,
            "type": loc.type,
            "locale": (loc.attributes?.locale).jsonSafe,
            "name": (loc.attributes?.name).jsonSafe,
            "subtitle": (loc.attributes?.subtitle).jsonSafe,
            "privacyPolicyUrl": (loc.attributes?.privacyPolicyUrl).jsonSafe,
            "privacyChoicesUrl": (loc.attributes?.privacyChoicesUrl).jsonSafe,
            "privacyPolicyText": (loc.attributes?.privacyPolicyText).jsonSafe
        ]
        if let appInfoID = loc.relationships?.appInfo?.data?.id {
            result["appInfoId"] = appInfoID
        }
        return result
    }

    private func formatEula(_ eula: ASCEULA) -> [String: Any] {
        var result: [String: Any] = [
            "id": eula.id,
            "type": eula.type,
            "agreementText": (eula.attributes?.agreementText).jsonSafe
        ]
        if let appID = eula.relationships?.app?.data?.id {
            result["appId"] = appID
        }
        if let territories = eula.relationships?.territories?.data {
            result["territoryIds"] = territories.map(\.id)
        }
        return result
    }

    private func formatAppCategory(_ category: ASCAppCategory) -> [String: Any] {
        var result: [String: Any] = [
            "id": category.id,
            "type": category.type,
            "platforms": (category.attributes?.platforms).jsonSafe
        ]
        if let relationships = category.relationships {
            result["relationships"] = relationships.mapValues(\.asAny)
        }
        if let links = category.links {
            result["links"] = links.mapValues(\.asAny)
        }
        return result
    }

    private var allowedAppInfoIncludes: Set<String> {
        [
            "app",
            "ageRatingDeclaration",
            "appInfoLocalizations",
            "primaryCategory",
            "primarySubcategoryOne",
            "primarySubcategoryTwo",
            "secondaryCategory",
            "secondarySubcategoryOne",
            "secondarySubcategoryTwo"
        ]
    }

    private func stringList(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> [String]? {
        guard let value else { return nil }
        let values: [String]
        if let string = value.stringValue {
            values = string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else if let array = value.arrayValue {
            let parsed = array.compactMap(\.stringValue)
            guard parsed.count == array.count else {
                throw AppInfoArgumentError("'\(field)' must contain only strings")
            }
            values = parsed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            throw AppInfoArgumentError("'\(field)' must be a string or array of strings")
        }

        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw AppInfoArgumentError("'\(field)' must contain at least one non-empty value")
        }
        guard Set(values).count == values.count else {
            throw AppInfoArgumentError("'\(field)' must not contain duplicate values")
        }
        if let allowedValues,
           let invalid = values.first(where: { !allowedValues.contains($0) }) {
            throw AppInfoArgumentError(
                "Unsupported \(field) value '\(invalid)'. Valid values: \(allowedValues.sorted().joined(separator: ", "))"
            )
        }
        return values
    }

    private func boundedLimit(
        _ value: Value?,
        field: String,
        maximum: Int,
        defaultValue: Int
    ) throws -> Int {
        guard let value else { return defaultValue }
        guard let limit = value.intValue, (1...maximum).contains(limit) else {
            throw AppInfoArgumentError("'\(field)' must be an integer between 1 and \(maximum)")
        }
        return limit
    }

    private func validateAcceptedAppInfoMutationResource(
        type: String,
        id: String,
        expectedType: String,
        expectedID: String? = nil,
        method: String,
        statusCode: Int,
        context: String
    ) throws {
        do {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: type,
                id: id,
                expectedType: expectedType,
                expectedID: expectedID,
                context: context
            )
        } catch {
            throw committedUnverifiedAppInfoMutation(error, method: method, statusCode: statusCode)
        }
    }

    private func committedUnverifiedAppInfoMutation(
        _ error: Error,
        method: String,
        statusCode: Int
    ) -> ASCError {
        let cause = error as? ASCError ?? .parsing(Redactor.redact(error.localizedDescription))
        return .mutationCommittedUnverified(
            method: method,
            expectedStatusCode: statusCode,
            actualStatusCode: statusCode,
            cause: cause
        )
    }

    private func nullableString(_ value: Value?, field: String) throws -> JSONValue? {
        guard let value else { return nil }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue else {
            throw AppInfoArgumentError("'\(field)' must be a string or null")
        }
        return .string(string)
    }

    private func appendIncludedAppInfoResources(
        _ included: [ASCAppInfoIncludedResource]?,
        to result: inout [String: Any]
    ) {
        guard let included else { return }
        var apps: [[String: Any]] = []
        var declarations: [[String: Any]] = []
        var categories: [[String: Any]] = []
        var localizations: [[String: Any]] = []
        var unknown: [Any] = []
        for resource in included {
            switch resource {
            case .app(let app): apps.append(formatIncludedApp(app))
            case .ageRatingDeclaration(let declaration):
                declarations.append(formatAgeRatingDeclaration(declaration))
            case .appCategory(let category): categories.append(formatAppCategory(category))
            case .appInfoLocalization(let localization):
                localizations.append(formatAppInfoLocalization(localization))
            case .unknown(let value): unknown.append(value.asAny)
            }
        }
        if !apps.isEmpty { result["included_apps"] = apps }
        if !declarations.isEmpty { result["included_age_rating_declarations"] = declarations }
        if !categories.isEmpty { result["included_categories"] = categories }
        if !localizations.isEmpty { result["included_localizations"] = localizations }
        if !unknown.isEmpty { result["included_unknown"] = unknown }
    }

    private func formatIncludedApp(_ app: ASCAppInfoIncludedApp) -> [String: Any] {
        var result: [String: Any] = [
            "id": app.id,
            "type": app.type
        ]
        if let attributes = app.attributes {
            result["attributes"] = attributes.mapValues(\.asAny)
        }
        if let relationships = app.relationships {
            result["relationships"] = relationships.mapValues(\.asAny)
        }
        if let links = app.links {
            result["links"] = links.mapValues(\.asAny)
        }
        return result
    }

    private func formatAgeRatingDeclaration(_ declaration: ASCAgeRatingDeclaration) -> [String: Any] {
        var result: [String: Any] = [
            "id": declaration.id,
            "type": declaration.type
        ]
        if let attributes = declaration.attributes {
            result["attributes"] = attributes.mapValues(\.asAny)
        }
        if let links = declaration.links {
            result["links"] = links.mapValues(\.asAny)
        }
        return result
    }
}

private struct AppInfoArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
