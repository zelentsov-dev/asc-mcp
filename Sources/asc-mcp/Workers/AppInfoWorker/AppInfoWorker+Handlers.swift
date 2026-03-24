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

    /// Lists app info objects for an app
    /// - Returns: JSON array of app infos with attributes and relationship data
    func listAppInfos(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppInfosResponse = try await httpClient.get(
                "/v1/apps/\(appId)/appInfos",
                as: ASCAppInfosResponse.self
            )

            let infos = response.data.map { formatAppInfo($0) }

            var result: [String: Any] = [
                "success": true,
                "app_infos": infos,
                "count": infos.count
            ]

            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list app infos: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'info_id' is missing")],
                isError: true
            )
        }

        do {
            var queryParams: [String: String] = [:]

            if let includeValue = arguments["include"],
               let include = includeValue.stringValue {
                queryParams["include"] = include
            }

            let response: ASCAppInfoResponse = try await httpClient.get(
                "/v1/appInfos/\(infoId)",
                parameters: queryParams,
                as: ASCAppInfoResponse.self
            )

            var result: [String: Any] = [
                "success": true,
                "app_info": formatAppInfo(response.data)
            ]

            if let included = response.included {
                var categories: [[String: Any]] = []
                var localizations: [[String: Any]] = []

                for resource in included {
                    switch resource {
                    case .appCategory(let category):
                        categories.append(formatAppCategory(category))
                    case .appInfoLocalization(let localization):
                        localizations.append(formatAppInfoLocalization(localization))
                    }
                }

                if !categories.isEmpty {
                    result["included_categories"] = categories
                }
                if !localizations.isEmpty {
                    result["included_localizations"] = localizations
                }
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get app info: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'info_id' is missing")],
                isError: true
            )
        }

        do {
            let primaryCategoryId = arguments["primary_category_id"]?.stringValue
            let secondaryCategoryId = arguments["secondary_category_id"]?.stringValue
            let primarySubcategoryOneId = arguments["primary_subcategory_one_id"]?.stringValue
            let primarySubcategoryTwoId = arguments["primary_subcategory_two_id"]?.stringValue
            let secondarySubcategoryOneId = arguments["secondary_subcategory_one_id"]?.stringValue
            let secondarySubcategoryTwoId = arguments["secondary_subcategory_two_id"]?.stringValue

            func makeCategoryRelationship(_ id: String?) -> UpdateAppInfoRequest.CategoryRelationship? {
                guard let id = id else { return nil }
                return UpdateAppInfoRequest.CategoryRelationship(
                    data: ASCResourceIdentifier(type: "appCategories", id: id)
                )
            }

            let relationships = UpdateAppInfoRequest.UpdateAppInfoRelationships(
                primaryCategory: makeCategoryRelationship(primaryCategoryId),
                primarySubcategoryOne: makeCategoryRelationship(primarySubcategoryOneId),
                primarySubcategoryTwo: makeCategoryRelationship(primarySubcategoryTwoId),
                secondaryCategory: makeCategoryRelationship(secondaryCategoryId),
                secondarySubcategoryOne: makeCategoryRelationship(secondarySubcategoryOneId),
                secondarySubcategoryTwo: makeCategoryRelationship(secondarySubcategoryTwoId)
            )

            let request = UpdateAppInfoRequest(
                data: UpdateAppInfoRequest.UpdateAppInfoData(
                    id: infoId,
                    relationships: relationships
                )
            )

            let response: ASCAppInfoResponse = try await httpClient.patch(
                "/v1/appInfos/\(infoId)",
                body: request,
                as: ASCAppInfoResponse.self
            )

            let result = [
                "success": true,
                "app_info": formatAppInfo(response.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to update app info: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists app info localizations
    /// - Returns: JSON array of localizations with subtitle, privacy URL, etc.
    func listAppInfoLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let infoIdValue = arguments["info_id"],
              let infoId = infoIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'info_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppInfoLocalizationsResponse = try await httpClient.get(
                "/v1/appInfos/\(infoId)/appInfoLocalizations",
                parameters: [:],
                as: ASCAppInfoLocalizationsResponse.self
            )

            let localizations = response.data.map { formatAppInfoLocalization($0) }

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
                content: [.text("Failed to list app info localizations: \(error.localizedDescription)")],
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
            return CallTool.Result(
                content: [.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateAppInfoLocalizationRequest(
                data: UpdateAppInfoLocalizationRequest.UpdateAppInfoLocalizationData(
                    id: localizationId,
                    attributes: UpdateAppInfoLocalizationRequest.UpdateAppInfoLocalizationAttributes(
                        name: arguments["name"]?.stringValue,
                        subtitle: arguments["subtitle"]?.stringValue,
                        privacyPolicyUrl: arguments["privacy_policy_url"]?.stringValue,
                        privacyChoicesUrl: arguments["privacy_choices_url"]?.stringValue,
                        privacyPolicyText: arguments["privacy_policy_text"]?.stringValue
                    )
                )
            )

            let response: ASCAppInfoLocalizationResponse = try await httpClient.patch(
                "/v1/appInfoLocalizations/\(localizationId)",
                body: request,
                as: ASCAppInfoLocalizationResponse.self
            )

            let localization = formatAppInfoLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to update app info localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new app info localization for a locale
    /// - Returns: JSON with created localization details
    func createAppInfoLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let infoIdValue = arguments["info_id"],
              let infoId = infoIdValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters: info_id, locale")],
                isError: true
            )
        }

        do {
            let request = CreateAppInfoLocalizationRequest(
                data: CreateAppInfoLocalizationRequest.CreateAppInfoLocalizationData(
                    attributes: CreateAppInfoLocalizationRequest.CreateAppInfoLocalizationAttributes(
                        locale: locale,
                        name: arguments["name"]?.stringValue,
                        subtitle: arguments["subtitle"]?.stringValue,
                        privacyPolicyUrl: arguments["privacy_policy_url"]?.stringValue,
                        privacyChoicesUrl: arguments["privacy_choices_url"]?.stringValue,
                        privacyPolicyText: arguments["privacy_policy_text"]?.stringValue
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

            let localization = formatAppInfoLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create app info localization: \(error.localizedDescription)")],
                isError: true
            )
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
                content: [.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appInfoLocalizations/\(localizationId)")

            let result = [
                "success": true,
                "message": "App info localization '\(localizationId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to delete app info localization: \(error.localizedDescription)")],
                isError: true
            )
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
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let responseData = try await httpClient.get(
                "/v1/apps/\(appId)/endUserLicenseAgreement",
                parameters: [:]
            )

            let response = try JSONDecoder().decode(ASCEULAResponse.self, from: responseData)

            let result: [String: Any] = [
                "success": true,
                "eula": formatEula(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get EULA (app may not have a EULA configured): \(error.localizedDescription)")],
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
                content: [.text("Required parameters: app_id, agreement_text, territory_ids")],
                isError: true
            )
        }

        let territoryIds = territoryIdsArray.compactMap { $0.stringValue }
        guard !territoryIds.isEmpty else {
            return CallTool.Result(
                content: [.text("'territory_ids' must contain at least one territory ID")],
                isError: true
            )
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
            let response = try JSONDecoder().decode(ASCEULAResponse.self, from: responseData)

            let result: [String: Any] = [
                "success": true,
                "eula": formatEula(response.data),
                "message": "EULA created successfully"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create EULA: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates an existing EULA
    /// - Returns: JSON with updated EULA details
    func updateEula(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let eulaIdValue = arguments["eula_id"],
              let eulaId = eulaIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'eula_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateEULARequest(
                data: UpdateEULARequest.UpdateEULAData(
                    id: eulaId,
                    attributes: UpdateEULARequest.UpdateEULAAttributes(
                        agreementText: arguments["agreement_text"]?.stringValue
                    )
                )
            )

            let bodyData = try JSONEncoder().encode(request)
            let responseData = try await httpClient.patch(
                "/v1/endUserLicenseAgreements/\(eulaId)",
                body: bodyData
            )
            let response = try JSONDecoder().decode(ASCEULAResponse.self, from: responseData)

            let result: [String: Any] = [
                "success": true,
                "eula": formatEula(response.data),
                "message": "EULA updated successfully"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to update EULA: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatAppInfo(_ info: ASCAppInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "id": info.id,
            "type": info.type,
            "appStoreState": info.attributes?.appStoreState.jsonSafe,
            "appStoreAgeRating": info.attributes?.appStoreAgeRating.jsonSafe,
            "brazilAgeRating": info.attributes?.brazilAgeRating.jsonSafe,
            "brazilAgeRatingV2": info.attributes?.brazilAgeRatingV2.jsonSafe,
            "kidsAgeBand": info.attributes?.kidsAgeBand.jsonSafe,
            "state": info.attributes?.state.jsonSafe
        ]

        // Include relationship IDs if available
        if let relationships = info.relationships {
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
        }

        return dict
    }

    private func formatAppInfoLocalization(_ loc: ASCAppInfoLocalization) -> [String: Any] {
        return [
            "id": loc.id,
            "type": loc.type,
            "locale": loc.attributes?.locale.jsonSafe,
            "name": loc.attributes?.name.jsonSafe,
            "subtitle": loc.attributes?.subtitle.jsonSafe,
            "privacyPolicyUrl": loc.attributes?.privacyPolicyUrl.jsonSafe,
            "privacyChoicesUrl": loc.attributes?.privacyChoicesUrl.jsonSafe,
            "privacyPolicyText": loc.attributes?.privacyPolicyText.jsonSafe
        ]
    }

    private func formatEula(_ eula: ASCEULA) -> [String: Any] {
        return [
            "id": eula.id,
            "type": eula.type,
            "agreementText": eula.attributes?.agreementText.jsonSafe ?? NSNull()
        ]
    }

    private func formatAppCategory(_ category: ASCAppCategory) -> [String: Any] {
        return [
            "id": category.id,
            "type": category.type,
            "platforms": category.attributes?.platforms.jsonSafe
        ]
    }
}
