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
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCustomProductPagesResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/apps/\(try ASCPathSegment.encode(appId))/appCustomProductPages"),
                    as: ASCCustomProductPagesResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }
                if let visible = try commaSeparatedBooleans(arguments["visible"], field: "visible") {
                    queryParams["filter[visible]"] = visible
                }

                response = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appId))/appCustomProductPages",
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list custom product pages: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCustomProductPageResponse = try await httpClient.get(
                "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageId))",
                as: ASCCustomProductPageResponse.self
            )

            let page = formatCustomPage(response.data)

            let result = [
                "success": true,
                "custom_product_page": page
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get custom product page: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: app_id, name, locale")],
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

            var pageRelationships: [String: Any] = [
                "app": [
                    "data": ["type": "apps", "id": appId]
                ],
                "appCustomProductPageVersions": [
                    "data": [
                        ["type": "appCustomProductPageVersions", "id": versionId]
                    ]
                ]
            ]
            if let templateVersionId = arguments["template_version_id"]?.stringValue {
                pageRelationships["appStoreVersionTemplate"] = [
                    "data": ["type": "appStoreVersions", "id": templateVersionId]
                ]
            }
            if let templatePageValue = arguments["template_page_id"] {
                guard let templatePageId = templatePageValue.stringValue,
                      !templatePageId.isEmpty else {
                    throw CustomProductPageInputError("'template_page_id' must be a non-empty string")
                }
                pageRelationships["customProductPageTemplate"] = [
                    "data": ["type": "appCustomProductPages", "id": templatePageId]
                ]
            }

            let requestDict: [String: Any] = [
                "data": [
                    "type": "appCustomProductPages",
                    "attributes": [
                        "name": name
                    ],
                    "relationships": pageRelationships
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create custom product page: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'page_id' is missing")],
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
                "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageId))",
                body: request,
                as: ASCCustomProductPageResponse.self
            )

            let page = formatCustomPage(response.data)

            let result = [
                "success": true,
                "custom_product_page": page
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update custom product page: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageId))")

            let result = [
                "success": true,
                "message": "Custom product page '\(pageId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete custom product page: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCustomProductPageVersionsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageId))/appCustomProductPageVersions"),
                    as: ASCCustomProductPageVersionsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }
                if let states = try commaSeparatedStrings(
                    arguments["state"],
                    field: "state",
                    allowedValues: [
                        "PREPARE_FOR_SUBMISSION",
                        "READY_FOR_REVIEW",
                        "WAITING_FOR_REVIEW",
                        "IN_REVIEW",
                        "ACCEPTED",
                        "APPROVED",
                        "REPLACED_WITH_NEW_VERSION",
                        "REJECTED"
                    ]
                ) {
                    queryParams["filter[state]"] = states
                }

                response = try await httpClient.get(
                    "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageId))/appCustomProductPageVersions",
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list custom product page versions: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'page_id' is missing")],
                isError: true
            )
        }

        do {
            let deepLink = try nullableAbsoluteURI(arguments["deep_link"], field: "deep_link")
            let request = CreateCustomProductPageVersionRequest(
                data: CreateCustomProductPageVersionRequest.CreateData(
                    attributes: deepLink.map {
                        CreateCustomProductPageVersionRequest.Attributes(deepLink: $0)
                    },
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create custom product page version: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCustomProductPageLocalizationsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/appCustomProductPageVersions/\(try ASCPathSegment.encode(versionId))/appCustomProductPageLocalizations"),
                    as: ASCCustomProductPageLocalizationsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }
                if let locales = try commaSeparatedStrings(arguments["locale"], field: "locale") {
                    queryParams["filter[locale]"] = locales
                }

                response = try await httpClient.get(
                    "/v1/appCustomProductPageVersions/\(try ASCPathSegment.encode(versionId))/appCustomProductPageLocalizations",
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list custom product page localizations: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: version_id, locale")],
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create custom product page localization: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'localization_id' is missing")],
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
                "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(localizationId))",
                body: request,
                as: ASCCustomProductPageLocalizationResponse.self
            )

            let localization = formatLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update custom product page localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatCustomPage(_ page: ASCCustomProductPage) -> [String: Any] {
        return [
            "id": page.id,
            "type": page.type,
            "name": (page.attributes?.name).jsonSafe,
            "url": (page.attributes?.url).jsonSafe,
            "visible": (page.attributes?.visible).jsonSafe,
            "state": NSNull()
        ]
    }

    private func formatVersion(_ version: ASCCustomProductPageVersion) -> [String: Any] {
        return [
            "id": version.id,
            "type": version.type,
            "version": (version.attributes?.version).jsonSafe,
            "state": (version.attributes?.state).jsonSafe,
            "deepLink": (version.attributes?.deepLink).jsonSafe
        ]
    }

    private func formatLocalization(_ loc: ASCCustomProductPageLocalization) -> [String: Any] {
        return [
            "id": loc.id,
            "type": loc.type,
            "locale": (loc.attributes?.locale).jsonSafe,
            "promotionalText": (loc.attributes?.promotionalText).jsonSafe
        ]
    }

    private func commaSeparatedStrings(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> String? {
        guard let value else { return nil }

        let values: [String]
        if let string = value.stringValue {
            values = string.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let array = value.arrayValue {
            let strings = array.compactMap(\.stringValue)
            guard strings.count == array.count else {
                throw CustomProductPageInputError("'\(field)' must contain only strings")
            }
            values = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            throw CustomProductPageInputError("'\(field)' must be a string or an array of strings")
        }

        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw CustomProductPageInputError("'\(field)' must contain at least one non-empty value")
        }
        guard Set(values).count == values.count else {
            throw CustomProductPageInputError("'\(field)' must not contain duplicate values")
        }
        if let allowedValues,
           let unsupported = values.first(where: { !allowedValues.contains($0) }) {
            throw CustomProductPageInputError(
                "Unsupported value '\(unsupported)' for '\(field)'. Valid values: \(allowedValues.sorted().joined(separator: ", "))"
            )
        }
        return values.joined(separator: ",")
    }

    private func commaSeparatedBooleans(_ value: Value?, field: String) throws -> String? {
        guard let value else { return nil }

        let values: [Bool]
        if let boolean = value.boolValue {
            values = [boolean]
        } else if let array = value.arrayValue {
            let booleans = array.compactMap(\.boolValue)
            guard !array.isEmpty, booleans.count == array.count else {
                throw CustomProductPageInputError("'\(field)' must contain one or more booleans")
            }
            values = booleans
        } else {
            throw CustomProductPageInputError("'\(field)' must be a boolean or an array of booleans")
        }

        guard Set(values).count == values.count else {
            throw CustomProductPageInputError("'\(field)' must not contain duplicate values")
        }
        return values.map(String.init).joined(separator: ",")
    }

    private func nullableAbsoluteURI(
        _ value: Value?,
        field: String
    ) throws -> ASCCustomProductPageNullable<String>? {
        guard let value else { return nil }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue else {
            throw CustomProductPageInputError("'\(field)' must be an absolute URI or null")
        }
        let schemePattern = "^[A-Za-z][A-Za-z0-9+.-]*$"
        guard !string.isEmpty,
              string.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: string),
              let scheme = components.scheme,
              scheme.range(of: schemePattern, options: .regularExpression) != nil,
              URL(string: string)?.scheme == scheme else {
            throw CustomProductPageInputError("'\(field)' must be an absolute URI or null")
        }
        return .value(string)
    }
}

private struct CustomProductPageInputError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
