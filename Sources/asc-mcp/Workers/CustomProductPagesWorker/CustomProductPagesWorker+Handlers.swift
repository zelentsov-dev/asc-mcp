import Foundation
import MCP

// MARK: - Tool Handlers
extension CustomProductPagesWorker {

    /// Lists custom product pages for an app
    /// - Returns: JSON array of custom product pages
    func listCustomPages(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCustomProductPagesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCustomProductPagesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/appCustomProductPages",
                    parameters: queryParams,
                    as: ASCCustomProductPagesResponse.self
                )
            }

            let pages = response.data.map { formatCustomPage($0) }

            var result: [String: Any] = [
                "success": true,
                "custom_product_pages": pages,
                "count": pages.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list custom product pages: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific custom product page
    /// - Returns: JSON with custom product page details
    func getCustomPage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let pageIdValue = arguments["page_id"],
              let pageId = pageIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCustomProductPageResponse = try await httpClient.get(
                "/v1/appCustomProductPages/\(pageId)",
                as: ASCCustomProductPageResponse.self
            )

            let page = formatCustomPage(response.data)

            let result = [
                "success": true,
                "custom_product_page": page
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get custom product page: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new custom product page with initial version and localization
    /// - Returns: JSON with created custom product page details
    func createCustomPage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let nameValue = arguments["name"],
              let name = nameValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: app_id, name, locale")],
                isError: true
            )
        }

        do {
            // Apple API requires inline includes with ${local-id} format IDs
            // Chain: data → version (included) → localization (included)
            let versionId = "${version-0}"
            let localizationId = "${localization-0}"

            var localizationAttributes: [String: Any] = [
                "locale": locale
            ]
            if let promotionalText = arguments["promotional_text"]?.stringValue {
                localizationAttributes["promotionalText"] = promotionalText
            }

            let requestDict: [String: Any] = [
                "data": [
                    "type": "appCustomProductPages",
                    "attributes": [
                        "name": name
                    ],
                    "relationships": [
                        "app": [
                            "data": ["type": "apps", "id": appId]
                        ],
                        "appCustomProductPageVersions": [
                            "data": [
                                ["type": "appCustomProductPageVersions", "id": versionId]
                            ]
                        ]
                    ]
                ],
                "included": [
                    [
                        "type": "appCustomProductPageVersions",
                        "id": versionId,
                        "relationships": [
                            "appCustomProductPageLocalizations": [
                                "data": [
                                    ["type": "appCustomProductPageLocalizations", "id": localizationId]
                                ]
                            ]
                        ]
                    ],
                    [
                        "type": "appCustomProductPageLocalizations",
                        "id": localizationId,
                        "attributes": localizationAttributes
                    ]
                ]
            ]

            let body = try JSONSerialization.data(withJSONObject: requestDict)
            let data = try await httpClient.post("/v1/appCustomProductPages", body: body)
            let response = try JSONDecoder().decode(ASCCustomProductPageResponse.self, from: data)

            let page = formatCustomPage(response.data)

            let result = [
                "success": true,
                "custom_product_page": page
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create custom product page: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a custom product page
    /// - Returns: JSON with updated custom product page details
    func updateCustomPage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let pageIdValue = arguments["page_id"],
              let pageId = pageIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateCustomProductPageRequest(
                data: UpdateCustomProductPageRequest.UpdateData(
                    id: pageId,
                    attributes: UpdateCustomProductPageRequest.Attributes(
                        name: arguments["name"]?.stringValue,
                        visible: arguments["visible"]?.boolValue
                    )
                )
            )

            let response: ASCCustomProductPageResponse = try await httpClient.patch(
                "/v1/appCustomProductPages/\(pageId)",
                body: request,
                as: ASCCustomProductPageResponse.self
            )

            let page = formatCustomPage(response.data)

            let result = [
                "success": true,
                "custom_product_page": page
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update custom product page: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a custom product page
    /// - Returns: JSON confirmation
    func deleteCustomPage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let pageIdValue = arguments["page_id"],
              let pageId = pageIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appCustomProductPages/\(pageId)")

            let result = [
                "success": true,
                "message": "Custom product page '\(pageId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete custom product page: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists versions for a custom product page
    /// - Returns: JSON array of custom product page versions
    func listVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let pageIdValue = arguments["page_id"],
              let pageId = pageIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCustomProductPageVersionsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCustomProductPageVersionsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/appCustomProductPages/\(pageId)/appCustomProductPageVersions",
                    parameters: queryParams,
                    as: ASCCustomProductPageVersionsResponse.self
                )
            }

            let versions = response.data.map { formatVersion($0) }

            var result: [String: Any] = [
                "success": true,
                "versions": versions,
                "count": versions.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list custom product page versions: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new version for a custom product page
    /// - Returns: JSON with created version details
    func createVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let pageIdValue = arguments["page_id"],
              let pageId = pageIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            let request = CreateCustomProductPageVersionRequest(
                data: CreateCustomProductPageVersionRequest.CreateData(
                    relationships: CreateCustomProductPageVersionRequest.Relationships(
                        appCustomProductPage: CreateCustomProductPageVersionRequest.PageRelationship(
                            data: ASCResourceIdentifier(type: "appCustomProductPages", id: pageId)
                        )
                    )
                )
            )

            let response: ASCCustomProductPageVersionResponse = try await httpClient.post(
                "/v1/appCustomProductPageVersions",
                body: request,
                as: ASCCustomProductPageVersionResponse.self
            )

            let version = formatVersion(response.data)

            let result = [
                "success": true,
                "version": version
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create custom product page version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists localizations for a custom product page version
    /// - Returns: JSON array of localizations
    func listLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionIdValue = arguments["version_id"],
              let versionId = versionIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCustomProductPageLocalizationsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCustomProductPageLocalizationsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/appCustomProductPageVersions/\(versionId)/appCustomProductPageLocalizations",
                    parameters: queryParams,
                    as: ASCCustomProductPageLocalizationsResponse.self
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
                content: [.text("Error: Failed to list custom product page localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a localization for a custom product page version
    /// - Returns: JSON with created localization details
    func createLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionIdValue = arguments["version_id"],
              let versionId = versionIdValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: version_id, locale")],
                isError: true
            )
        }

        do {
            let request = CreateCustomProductPageLocalizationRequest(
                data: CreateCustomProductPageLocalizationRequest.CreateData(
                    attributes: CreateCustomProductPageLocalizationRequest.Attributes(
                        locale: locale,
                        promotionalText: arguments["promotional_text"]?.stringValue
                    ),
                    relationships: CreateCustomProductPageLocalizationRequest.Relationships(
                        appCustomProductPageVersion: CreateCustomProductPageLocalizationRequest.VersionRelationship(
                            data: ASCResourceIdentifier(type: "appCustomProductPageVersions", id: versionId)
                        )
                    )
                )
            )

            let response: ASCCustomProductPageLocalizationResponse = try await httpClient.post(
                "/v1/appCustomProductPageLocalizations",
                body: request,
                as: ASCCustomProductPageLocalizationResponse.self
            )

            let localization = formatLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create custom product page localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a localization for a custom product page
    /// - Returns: JSON with updated localization details
    func updateLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateCustomProductPageLocalizationRequest(
                data: UpdateCustomProductPageLocalizationRequest.UpdateData(
                    id: localizationId,
                    attributes: UpdateCustomProductPageLocalizationRequest.Attributes(
                        promotionalText: arguments["promotional_text"]?.stringValue
                    )
                )
            )

            let response: ASCCustomProductPageLocalizationResponse = try await httpClient.patch(
                "/v1/appCustomProductPageLocalizations/\(localizationId)",
                body: request,
                as: ASCCustomProductPageLocalizationResponse.self
            )

            let localization = formatLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update custom product page localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatCustomPage(_ page: ASCCustomProductPage) -> [String: Any] {
        return [
            "id": page.id,
            "type": page.type,
            "name": page.attributes?.name.jsonSafe,
            "url": page.attributes?.url.jsonSafe,
            "visible": page.attributes?.visible.jsonSafe,
            "state": page.attributes?.state.jsonSafe
        ]
    }

    private func formatVersion(_ version: ASCCustomProductPageVersion) -> [String: Any] {
        return [
            "id": version.id,
            "type": version.type,
            "version": version.attributes?.version.jsonSafe,
            "state": version.attributes?.state.jsonSafe,
            "deepLink": version.attributes?.deepLink.jsonSafe
        ]
    }

    private func formatLocalization(_ loc: ASCCustomProductPageLocalization) -> [String: Any] {
        return [
            "id": loc.id,
            "type": loc.type,
            "locale": loc.attributes?.locale.jsonSafe,
            "promotionalText": loc.attributes?.promotionalText.jsonSafe
        ]
    }
}
