import Foundation
import MCP

// MARK: - Tool Handlers
extension CustomProductPagesWorker {
    func listCustomPages(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateCustomPageArguments(arguments, allowed: ["app_id", "visible", "limit", "next_url"])
            let appID = try customPageIdentifier("app_id", from: arguments)
            let limit = try customPageLimit(arguments["limit"])
            let path = "/v1/apps/\(try ASCPathSegment.encode(appID, field: "app_id"))/appCustomProductPages"
            var query = ["limit": String(limit)]
            if let visible = try commaSeparatedBooleans(arguments["visible"], field: "visible") {
                query["filter[visible]"] = visible
            }
            let paginationScope = PaginationScope.strict(path: path, query: query)

            let response: ASCCustomProductPagesResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: paginationScope,
                    as: ASCCustomProductPagesResponse.self
                )
            } else {
                response = try await httpClient.get(path, parameters: query, as: ASCCustomProductPagesResponse.self)
            }
            try validatePages(
                response.data,
                expectedAppID: appID,
                context: "custom product page list"
            )
            try validateCustomPageCollection(
                links: response.links,
                meta: response.meta,
                count: response.data.count,
                requestedLimit: limit,
                expectedPath: path,
                paginationScope: paginationScope,
                context: "custom product page list"
            )

            var result: [String: Any] = [
                "success": true,
                "appId": appID,
                "custom_product_pages": response.data.map(formatCustomPage),
                "count": response.data.count,
                "limit": limit
            ]
            if let next = response.links.next { result["next_url"] = next }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list custom product pages")
        }
    }

    func getCustomPage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateCustomPageArguments(arguments, allowed: ["page_id"])
            let pageID = try customPageIdentifier("page_id", from: arguments)
            let path = "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageID, field: "page_id"))"
            let response: ASCCustomProductPageResponse = try await httpClient.get(
                path,
                as: ASCCustomProductPageResponse.self
            )
            try validatePage(response.data, expectedID: pageID, context: "custom product page get")
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: path,
                context: "custom product page get"
            )
            return MCPResult.jsonObject([
                "success": true,
                "custom_product_page": formatCustomPage(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get custom product page")
        }
    }

    func createCustomPage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let appID: String
        let name: String
        let locale: String
        let promotionalText: ASCCustomProductPageNullable<String>?
        let templateVersionID: String?
        let templatePageID: String?
        do {
            try validateCustomPageArguments(
                arguments,
                allowed: ["app_id", "name", "locale", "promotional_text", "template_version_id", "template_page_id"]
            )
            appID = try customPageIdentifier("app_id", from: arguments)
            name = try requiredCustomPageString("name", from: arguments)
            locale = try requiredCustomPageString("locale", from: arguments)
            promotionalText = try nullableCustomPageString(arguments["promotional_text"], field: "promotional_text")
            templateVersionID = try optionalCustomPageIdentifier("template_version_id", from: arguments)
            templatePageID = try optionalCustomPageIdentifier("template_page_id", from: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page creation")
        }

        let localVersionID = "${version-0}"
        let localLocalizationID = "${localization-0}"
        var localizationAttributes: [String: Any] = ["locale": locale]
        applyNullable(promotionalText, key: "promotionalText", to: &localizationAttributes)
        var pageRelationships: [String: Any] = [
            "app": ["data": ["type": "apps", "id": appID]],
            "appCustomProductPageVersions": [
                "data": [["type": "appCustomProductPageVersions", "id": localVersionID]]
            ]
        ]
        if let templateVersionID {
            pageRelationships["appStoreVersionTemplate"] = [
                "data": ["type": "appStoreVersions", "id": templateVersionID]
            ]
        }
        if let templatePageID {
            pageRelationships["customProductPageTemplate"] = [
                "data": ["type": "appCustomProductPages", "id": templatePageID]
            ]
        }
        let request: [String: Any] = [
            "data": [
                "type": "appCustomProductPages",
                "attributes": ["name": name],
                "relationships": pageRelationships
            ],
            "included": [
                [
                    "type": "appCustomProductPageVersions",
                    "id": localVersionID,
                    "relationships": [
                        "appCustomProductPageLocalizations": [
                            "data": [["type": "appCustomProductPageLocalizations", "id": localLocalizationID]]
                        ]
                    ]
                ],
                [
                    "type": "appCustomProductPageLocalizations",
                    "id": localLocalizationID,
                    "attributes": localizationAttributes
                ]
            ]
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode custom product page creation")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/appCustomProductPages", body: body)
        } catch {
            return customPageMutationFailure(
                operation: "create_page",
                phase: .request,
                error: error,
                identifiers: createPageRecoveryIdentifiers(
                    appID: appID,
                    name: name,
                    locale: locale,
                    promotionalText: promotionalText,
                    templateVersionID: templateVersionID,
                    templatePageID: templatePageID
                ),
                inspection: listInspection(
                    tool: "custom_pages_list",
                    arguments: ["app_id": appID],
                    instruction: "List every page for the exact app and match the requested name before retrying."
                )
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Custom product page create"
            )
            let response = try JSONDecoder().decode(ASCCustomProductPageResponse.self, from: receipt.data)
            try validatePage(
                response.data,
                expectedID: nil,
                expectedAppID: appID,
                context: "custom product page create"
            )
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/appCustomProductPages/\(try ASCPathSegment.encode(response.data.id, field: "custom product page response ID"))",
                context: "custom product page create"
            )
            guard response.data.attributes?.hasName == true,
                  response.data.attributes?.name == name else {
                throw CustomProductPageInputError("Apple create response did not preserve the requested page name")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "create_page",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "changed": true,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "custom_product_page": formatCustomPage(response.data)
            ])
        } catch {
            return customPageMutationFailure(
                operation: "create_page",
                phase: .acceptedResponse,
                error: customPageAcceptedMutationError(
                    error,
                    method: "POST",
                    expectedStatusCode: 201,
                    actualStatusCode: receipt.statusCode
                ),
                identifiers: createPageRecoveryIdentifiers(
                    appID: appID,
                    name: name,
                    locale: locale,
                    promotionalText: promotionalText,
                    templateVersionID: templateVersionID,
                    templatePageID: templatePageID
                ),
                inspection: listInspection(
                    tool: "custom_pages_list",
                    arguments: ["app_id": appID],
                    instruction: "Apple accepted the request. List every page for the exact app and inspect candidates before retrying."
                )
            )
        }
    }

    func updateCustomPage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let pageID: String
        let name: ASCCustomProductPageNullable<String>?
        let visible: ASCCustomProductPageNullable<Bool>?
        do {
            try validateCustomPageArguments(arguments, allowed: ["page_id", "name", "visible"])
            pageID = try customPageIdentifier("page_id", from: arguments)
            name = try nullableCustomPageString(arguments["name"], field: "name")
            visible = try nullableCustomPageBoolean(arguments["visible"], field: "visible")
            guard name != nil || visible != nil else {
                throw CustomProductPageInputError("At least one mutable parameter is required: name or visible")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page update")
        }

        let request = UpdateCustomProductPageRequest(
            data: .init(id: pageID, attributes: .init(name: name, visible: visible))
        )
        let body: Data
        do { body = try JSONEncoder().encode(request) } catch {
            return MCPResult.error(error, prefix: "Failed to encode custom product page update")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(
                "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageID, field: "page_id"))",
                body: body
            )
        } catch {
            return customPageMutationFailure(
                operation: "update_page",
                phase: .request,
                error: error,
                identifiers: updatePageRecoveryIdentifiers(pageID: pageID, name: name, visible: visible),
                inspection: getInspection(
                    tool: "custom_pages_get",
                    arguments: ["page_id": pageID],
                    instruction: "Inspect the exact page before retrying the update."
                )
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Custom product page update"
            )
            let response = try JSONDecoder().decode(ASCCustomProductPageResponse.self, from: receipt.data)
            try validatePage(response.data, expectedID: pageID, context: "custom product page update")
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageID, field: "page_id"))",
                context: "custom product page update"
            )
            guard pageUpdateMatches(response.data, name: name, visible: visible) else {
                throw CustomProductPageInputError("Apple update response did not preserve every requested nullable attribute state")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "update_page",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "changed": NSNull(),
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "custom_product_page": formatCustomPage(response.data)
            ])
        } catch {
            return customPageMutationFailure(
                operation: "update_page",
                phase: .acceptedResponse,
                error: customPageAcceptedMutationError(
                    error,
                    method: "PATCH",
                    expectedStatusCode: 200,
                    actualStatusCode: receipt.statusCode
                ),
                identifiers: updatePageRecoveryIdentifiers(pageID: pageID, name: name, visible: visible),
                inspection: getInspection(
                    tool: "custom_pages_get",
                    arguments: ["page_id": pageID],
                    instruction: "Apple accepted the request, but its exact result was not verified. Inspect the page before retrying."
                )
            )
        }
    }

    func deleteCustomPage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let pageID: String
        do {
            try validateCustomPageArguments(arguments, allowed: ["page_id", "confirm_page_id"])
            pageID = try customPageIdentifier("page_id", from: arguments)
            let confirmation = try customPageIdentifier("confirm_page_id", from: arguments)
            guard confirmation == pageID else {
                throw CustomProductPageInputError("confirm_page_id must exactly match page_id")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page deletion")
        }

        let receipt: ASCDeleteReceipt
        do {
            receipt = try await httpClient.deleteReceipt(
                "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageID, field: "page_id"))"
            )
        } catch {
            return customPageMutationFailure(
                operation: "delete_page",
                phase: .request,
                error: error,
                identifiers: ["pageId": pageID],
                inspection: getInspection(
                    tool: "custom_pages_get",
                    arguments: ["page_id": pageID],
                    instruction: "Inspect the exact page before any delete retry."
                )
            )
        }
        guard receipt.statusCode == 204 else {
            return customPageMutationFailure(
                operation: "delete_page",
                phase: .acceptedResponse,
                error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode),
                identifiers: ["pageId": pageID],
                inspection: getInspection(
                    tool: "custom_pages_get",
                    arguments: ["page_id": pageID],
                    instruction: "Apple returned an unexpected successful status. Inspect the exact page before any retry."
                )
            )
        }
        return MCPResult.jsonObject([
            "success": true,
            "operation": "delete_page",
            "operationCommitted": true,
            "operationCommitState": "committed",
            "changed": true,
            "retrySafe": false,
            "pageId": pageID,
            "statusCode": receipt.statusCode,
            "message": "Custom product page deleted"
        ])
    }

    func listVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateCustomPageArguments(arguments, allowed: ["page_id", "state", "limit", "next_url"])
            let pageID = try customPageIdentifier("page_id", from: arguments)
            let limit = try customPageLimit(arguments["limit"])
            let path = "/v1/appCustomProductPages/\(try ASCPathSegment.encode(pageID, field: "page_id"))/appCustomProductPageVersions"
            var query = ["limit": String(limit)]
            if let states = try commaSeparatedStrings(
                arguments["state"],
                field: "state",
                allowedValues: customProductPageVersionStates
            ) {
                query["filter[state]"] = states
            }
            let paginationScope = PaginationScope.strict(path: path, query: query)
            let response: ASCCustomProductPageVersionsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: paginationScope,
                    as: ASCCustomProductPageVersionsResponse.self
                )
            } else {
                response = try await httpClient.get(path, parameters: query, as: ASCCustomProductPageVersionsResponse.self)
            }
            try validateVersions(
                response.data,
                expectedPageID: pageID,
                context: "custom product page version list"
            )
            try validateCustomPageCollection(
                links: response.links,
                meta: response.meta,
                count: response.data.count,
                requestedLimit: limit,
                expectedPath: path,
                paginationScope: paginationScope,
                context: "custom product page version list"
            )
            var result: [String: Any] = [
                "success": true,
                "pageId": pageID,
                "versions": response.data.map(formatVersion),
                "count": response.data.count,
                "limit": limit
            ]
            if let next = response.links.next { result["next_url"] = next }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list custom product page versions")
        }
    }

    func getVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateCustomPageArguments(arguments, allowed: ["version_id"])
            let versionID = try customPageIdentifier("version_id", from: arguments)
            let path = "/v1/appCustomProductPageVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))"
            let response: ASCCustomProductPageVersionResponse = try await httpClient.get(
                path,
                as: ASCCustomProductPageVersionResponse.self
            )
            try validateVersion(response.data, expectedID: versionID, context: "custom product page version get")
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: path,
                context: "custom product page version get"
            )
            return MCPResult.jsonObject(["success": true, "version": formatVersion(response.data)])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get custom product page version")
        }
    }

    func createVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let pageID: String
        let deepLink: ASCCustomProductPageNullable<String>?
        do {
            try validateCustomPageArguments(arguments, allowed: ["page_id", "deep_link"])
            pageID = try customPageIdentifier("page_id", from: arguments)
            deepLink = try nullableAbsoluteURI(arguments["deep_link"], field: "deep_link")
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page version creation")
        }
        let request = CreateCustomProductPageVersionRequest(
            data: .init(
                attributes: deepLink.map { .init(deepLink: $0) },
                relationships: .init(
                    appCustomProductPage: .init(
                        data: ASCResourceIdentifier(type: "appCustomProductPages", id: pageID)
                    )
                )
            )
        )
        let body: Data
        do { body = try JSONEncoder().encode(request) } catch {
            return MCPResult.error(error, prefix: "Failed to encode custom product page version creation")
        }
        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/appCustomProductPageVersions", body: body)
        } catch {
            return customPageMutationFailure(
                operation: "create_version",
                phase: .request,
                error: error,
                identifiers: createVersionRecoveryIdentifiers(pageID: pageID, deepLink: deepLink),
                inspection: listInspection(
                    tool: "custom_pages_list_versions",
                    arguments: ["page_id": pageID],
                    instruction: "List every version for the exact page and inspect deep-link candidates before retrying."
                )
            )
        }
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Custom product page version create"
            )
            let response = try JSONDecoder().decode(ASCCustomProductPageVersionResponse.self, from: receipt.data)
            try validateVersion(
                response.data,
                expectedID: nil,
                expectedPageID: pageID,
                context: "custom product page version create"
            )
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/appCustomProductPageVersions/\(try ASCPathSegment.encode(response.data.id, field: "custom product page version response ID"))",
                context: "custom product page version create"
            )
            guard nullableStringMatches(
                presence: response.data.attributes?.hasDeepLink == true,
                value: response.data.attributes?.deepLink,
                expected: deepLink
            ) else {
                throw CustomProductPageInputError("Apple create response did not preserve the requested deep-link state")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "create_version",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "changed": true,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "version": formatVersion(response.data)
            ])
        } catch {
            return customPageMutationFailure(
                operation: "create_version",
                phase: .acceptedResponse,
                error: customPageAcceptedMutationError(
                    error,
                    method: "POST",
                    expectedStatusCode: 201,
                    actualStatusCode: receipt.statusCode
                ),
                identifiers: createVersionRecoveryIdentifiers(pageID: pageID, deepLink: deepLink),
                inspection: listInspection(
                    tool: "custom_pages_list_versions",
                    arguments: ["page_id": pageID],
                    instruction: "Apple accepted the request. List every version for the exact page before retrying."
                )
            )
        }
    }

    func updateVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let versionID: String
        let deepLink: ASCCustomProductPageNullable<String>
        do {
            try validateCustomPageArguments(arguments, allowed: ["version_id", "deep_link"])
            versionID = try customPageIdentifier("version_id", from: arguments)
            guard let parsed = try nullableAbsoluteURI(arguments["deep_link"], field: "deep_link") else {
                throw CustomProductPageInputError("deep_link is required and must be an absolute URI or null")
            }
            deepLink = parsed
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page version update")
        }
        let request = UpdateCustomProductPageVersionRequest(
            data: .init(id: versionID, attributes: .init(deepLink: deepLink))
        )
        let body: Data
        do { body = try JSONEncoder().encode(request) } catch {
            return MCPResult.error(error, prefix: "Failed to encode custom product page version update")
        }
        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(
                "/v1/appCustomProductPageVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))",
                body: body
            )
        } catch {
            return customPageMutationFailure(
                operation: "update_version",
                phase: .request,
                error: error,
                identifiers: updateVersionRecoveryIdentifiers(versionID: versionID, deepLink: deepLink),
                inspection: getInspection(
                    tool: "custom_pages_get_version",
                    arguments: ["version_id": versionID],
                    instruction: "Inspect the exact version before retrying the update."
                )
            )
        }
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Custom product page version update"
            )
            let response = try JSONDecoder().decode(ASCCustomProductPageVersionResponse.self, from: receipt.data)
            try validateVersion(response.data, expectedID: versionID, context: "custom product page version update")
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/appCustomProductPageVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))",
                context: "custom product page version update"
            )
            guard nullableStringMatches(
                presence: response.data.attributes?.hasDeepLink == true,
                value: response.data.attributes?.deepLink,
                expected: deepLink
            ) else {
                throw CustomProductPageInputError("Apple update response did not preserve the requested deep-link state")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "update_version",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "changed": NSNull(),
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "version": formatVersion(response.data)
            ])
        } catch {
            return customPageMutationFailure(
                operation: "update_version",
                phase: .acceptedResponse,
                error: customPageAcceptedMutationError(
                    error,
                    method: "PATCH",
                    expectedStatusCode: 200,
                    actualStatusCode: receipt.statusCode
                ),
                identifiers: updateVersionRecoveryIdentifiers(versionID: versionID, deepLink: deepLink),
                inspection: getInspection(
                    tool: "custom_pages_get_version",
                    arguments: ["version_id": versionID],
                    instruction: "Apple accepted the request, but its exact result was not verified. Inspect the version before retrying."
                )
            )
        }
    }

    func listLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateCustomPageArguments(arguments, allowed: ["version_id", "locale", "limit", "next_url"])
            let versionID = try customPageIdentifier("version_id", from: arguments)
            let limit = try customPageLimit(arguments["limit"])
            let path = "/v1/appCustomProductPageVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))/appCustomProductPageLocalizations"
            var query = ["limit": String(limit)]
            if let locales = try commaSeparatedStrings(arguments["locale"], field: "locale") {
                query["filter[locale]"] = locales
            }
            let paginationScope = PaginationScope.strict(path: path, query: query)
            let response: ASCCustomProductPageLocalizationsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: paginationScope,
                    as: ASCCustomProductPageLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCCustomProductPageLocalizationsResponse.self
                )
            }
            try validateLocalizations(
                response.data,
                expectedVersionID: versionID,
                context: "custom product page localization list"
            )
            try validateCustomPageCollection(
                links: response.links,
                meta: response.meta,
                count: response.data.count,
                requestedLimit: limit,
                expectedPath: path,
                paginationScope: paginationScope,
                context: "custom product page localization list"
            )
            var result: [String: Any] = [
                "success": true,
                "versionId": versionID,
                "localizations": response.data.map(formatLocalization),
                "count": response.data.count,
                "limit": limit
            ]
            if let next = response.links.next { result["next_url"] = next }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list custom product page localizations")
        }
    }

    func getLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateCustomPageArguments(arguments, allowed: ["localization_id"])
            let localizationID = try customPageIdentifier("localization_id", from: arguments)
            let path = "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            let response: ASCCustomProductPageLocalizationResponse = try await httpClient.get(
                path,
                as: ASCCustomProductPageLocalizationResponse.self
            )
            try validateLocalization(
                response.data,
                expectedID: localizationID,
                context: "custom product page localization get"
            )
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: path,
                context: "custom product page localization get"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatLocalization(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get custom product page localization")
        }
    }

    func createLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let versionID: String
        let locale: String
        let promotionalText: ASCCustomProductPageNullable<String>?
        do {
            try validateCustomPageArguments(arguments, allowed: ["version_id", "locale", "promotional_text"])
            versionID = try customPageIdentifier("version_id", from: arguments)
            locale = try requiredCustomPageString("locale", from: arguments)
            promotionalText = try nullableCustomPageString(arguments["promotional_text"], field: "promotional_text")
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page localization creation")
        }
        let request = CreateCustomProductPageLocalizationRequest(
            data: .init(
                attributes: .init(locale: locale, promotionalText: promotionalText),
                relationships: .init(
                    appCustomProductPageVersion: .init(
                        data: ASCResourceIdentifier(type: "appCustomProductPageVersions", id: versionID)
                    )
                )
            )
        )
        let body: Data
        do { body = try JSONEncoder().encode(request) } catch {
            return MCPResult.error(error, prefix: "Failed to encode custom product page localization creation")
        }
        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/appCustomProductPageLocalizations", body: body)
        } catch {
            return customPageMutationFailure(
                operation: "create_localization",
                phase: .request,
                error: error,
                identifiers: createLocalizationRecoveryIdentifiers(
                    versionID: versionID,
                    locale: locale,
                    promotionalText: promotionalText
                ),
                inspection: listInspection(
                    tool: "custom_pages_list_localizations",
                    arguments: ["version_id": versionID, "locale": locale],
                    instruction: "List every matching locale for the exact version before retrying."
                )
            )
        }
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Custom product page localization create"
            )
            let response = try JSONDecoder().decode(ASCCustomProductPageLocalizationResponse.self, from: receipt.data)
            try validateLocalization(
                response.data,
                expectedID: nil,
                expectedVersionID: versionID,
                context: "custom product page localization create"
            )
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(response.data.id, field: "custom product page localization response ID"))",
                context: "custom product page localization create"
            )
            guard response.data.attributes?.hasLocale == true,
                  response.data.attributes?.locale == locale,
                  nullableStringMatches(
                      presence: response.data.attributes?.hasPromotionalText == true,
                      value: response.data.attributes?.promotionalText,
                      expected: promotionalText
                  ) else {
                throw CustomProductPageInputError("Apple create response did not preserve the requested localization attributes")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "create_localization",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "changed": true,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "localization": formatLocalization(response.data)
            ])
        } catch {
            return customPageMutationFailure(
                operation: "create_localization",
                phase: .acceptedResponse,
                error: customPageAcceptedMutationError(
                    error,
                    method: "POST",
                    expectedStatusCode: 201,
                    actualStatusCode: receipt.statusCode
                ),
                identifiers: createLocalizationRecoveryIdentifiers(
                    versionID: versionID,
                    locale: locale,
                    promotionalText: promotionalText
                ),
                inspection: listInspection(
                    tool: "custom_pages_list_localizations",
                    arguments: ["version_id": versionID, "locale": locale],
                    instruction: "Apple accepted the request. Inspect every matching localization before retrying."
                )
            )
        }
    }

    func updateLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let localizationID: String
        let promotionalText: ASCCustomProductPageNullable<String>
        do {
            try validateCustomPageArguments(arguments, allowed: ["localization_id", "promotional_text"])
            localizationID = try customPageIdentifier("localization_id", from: arguments)
            guard let parsed = try nullableCustomPageString(arguments["promotional_text"], field: "promotional_text") else {
                throw CustomProductPageInputError("promotional_text is required and must be a string or null")
            }
            promotionalText = parsed
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page localization update")
        }
        let request = UpdateCustomProductPageLocalizationRequest(
            data: .init(id: localizationID, attributes: .init(promotionalText: promotionalText))
        )
        let body: Data
        do { body = try JSONEncoder().encode(request) } catch {
            return MCPResult.error(error, prefix: "Failed to encode custom product page localization update")
        }
        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(
                "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))",
                body: body
            )
        } catch {
            return customPageMutationFailure(
                operation: "update_localization",
                phase: .request,
                error: error,
                identifiers: updateLocalizationRecoveryIdentifiers(
                    localizationID: localizationID,
                    promotionalText: promotionalText
                ),
                inspection: getInspection(
                    tool: "custom_pages_get_localization",
                    arguments: ["localization_id": localizationID],
                    instruction: "Inspect the exact localization before retrying the update."
                )
            )
        }
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Custom product page localization update"
            )
            let response = try JSONDecoder().decode(ASCCustomProductPageLocalizationResponse.self, from: receipt.data)
            try validateLocalization(
                response.data,
                expectedID: localizationID,
                context: "custom product page localization update"
            )
            try validateCustomPageDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))",
                context: "custom product page localization update"
            )
            guard nullableStringMatches(
                presence: response.data.attributes?.hasPromotionalText == true,
                value: response.data.attributes?.promotionalText,
                expected: promotionalText
            ) else {
                throw CustomProductPageInputError("Apple update response did not preserve the requested promotional-text state")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "update_localization",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "changed": NSNull(),
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "localization": formatLocalization(response.data)
            ])
        } catch {
            return customPageMutationFailure(
                operation: "update_localization",
                phase: .acceptedResponse,
                error: customPageAcceptedMutationError(
                    error,
                    method: "PATCH",
                    expectedStatusCode: 200,
                    actualStatusCode: receipt.statusCode
                ),
                identifiers: updateLocalizationRecoveryIdentifiers(
                    localizationID: localizationID,
                    promotionalText: promotionalText
                ),
                inspection: getInspection(
                    tool: "custom_pages_get_localization",
                    arguments: ["localization_id": localizationID],
                    instruction: "Apple accepted the request, but its exact result was not verified. Inspect the localization before retrying."
                )
            )
        }
    }

    func deleteLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let localizationID: String
        do {
            try validateCustomPageArguments(
                arguments,
                allowed: ["localization_id", "confirm_localization_id"]
            )
            localizationID = try customPageIdentifier("localization_id", from: arguments)
            let confirmation = try customPageIdentifier("confirm_localization_id", from: arguments)
            guard confirmation == localizationID else {
                throw CustomProductPageInputError("confirm_localization_id must exactly match localization_id")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page localization deletion")
        }
        let receipt: ASCDeleteReceipt
        do {
            receipt = try await httpClient.deleteReceipt(
                "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            )
        } catch {
            return customPageMutationFailure(
                operation: "delete_localization",
                phase: .request,
                error: error,
                identifiers: ["localizationId": localizationID],
                inspection: getInspection(
                    tool: "custom_pages_get_localization",
                    arguments: ["localization_id": localizationID],
                    instruction: "Inspect the exact localization before any delete retry."
                )
            )
        }
        guard receipt.statusCode == 204 else {
            return customPageMutationFailure(
                operation: "delete_localization",
                phase: .acceptedResponse,
                error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode),
                identifiers: ["localizationId": localizationID],
                inspection: getInspection(
                    tool: "custom_pages_get_localization",
                    arguments: ["localization_id": localizationID],
                    instruction: "Apple returned an unexpected successful status. Inspect the exact localization before any retry."
                )
            )
        }
        return MCPResult.jsonObject([
            "success": true,
            "operation": "delete_localization",
            "operationCommitted": true,
            "operationCommitState": "committed",
            "changed": true,
            "retrySafe": false,
            "localizationId": localizationID,
            "statusCode": receipt.statusCode,
            "message": "Custom product page localization deleted"
        ])
    }

    func listSearchKeywords(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateCustomPageArguments(
                arguments,
                allowed: ["localization_id", "platform", "locale", "limit", "next_url"]
            )
            let localizationID = try customPageIdentifier("localization_id", from: arguments)
            let limit = try customPageLimit(arguments["limit"])
            let path = "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))/searchKeywords"
            var query = ["limit": String(limit)]
            if let platforms = try commaSeparatedStrings(arguments["platform"], field: "platform") {
                query["filter[platform]"] = platforms
            }
            if let locales = try commaSeparatedStrings(arguments["locale"], field: "locale") {
                query["filter[locale]"] = locales
            }
            let paginationScope = PaginationScope.strict(path: path, query: query)
            let response: ASCAppKeywordsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: paginationScope,
                    as: ASCAppKeywordsResponse.self
                )
            } else {
                response = try await httpClient.get(path, parameters: query, as: ASCAppKeywordsResponse.self)
            }
            try validateSearchKeywords(
                response,
                expectedPath: path,
                requestedLimit: limit,
                paginationScope: paginationScope
            )
            var result: [String: Any] = [
                "success": true,
                "localizationId": localizationID,
                "search_keywords": response.data.map(formatSearchKeyword),
                "count": response.data.count,
                "limit": limit
            ]
            if let next = response.links.next { result["next_url"] = next }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list custom product page search keywords")
        }
    }

    func addSearchKeywords(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await mutateSearchKeywords(params, operation: "add_search_keywords", method: "POST")
    }

    func removeSearchKeywords(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await mutateSearchKeywords(params, operation: "remove_search_keywords", method: "DELETE")
    }
}

// MARK: - Validation and Recovery
private extension CustomProductPagesWorker {
    var customProductPageVersionStates: Set<String> {
        [
            "PREPARE_FOR_SUBMISSION",
            "READY_FOR_REVIEW",
            "WAITING_FOR_REVIEW",
            "IN_REVIEW",
            "ACCEPTED",
            "APPROVED",
            "REPLACED_WITH_NEW_VERSION",
            "REJECTED"
        ]
    }

    func mutateSearchKeywords(
        _ params: CallTool.Parameters,
        operation: String,
        method: String
    ) async -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let localizationID: String
        let keywordIDs: [String]
        let confirmationMatched: Bool
        do {
            let isRemoval = method == "DELETE"
            let allowed: Set<String> = isRemoval
                ? ["localization_id", "keyword_ids", "confirm_localization_id"]
                : ["localization_id", "keyword_ids"]
            try validateCustomPageArguments(arguments, allowed: allowed)
            localizationID = try customPageIdentifier("localization_id", from: arguments)
            keywordIDs = try customPageIdentifierList("keyword_ids", from: arguments)
            if isRemoval {
                let confirmation = try customPageIdentifier("confirm_localization_id", from: arguments)
                guard confirmation == localizationID else {
                    throw CustomProductPageInputError(
                        "confirm_localization_id must exactly match localization_id"
                    )
                }
                confirmationMatched = true
            } else {
                confirmationMatched = false
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page search keyword mutation")
        }
        let request = ASCCustomProductPageSearchKeywordLinkagesRequest(
            data: keywordIDs.map { ASCResourceIdentifier(type: "appKeywords", id: $0) }
        )
        let body: Data
        do { body = try JSONEncoder().encode(request) } catch {
            return MCPResult.error(error, prefix: "Failed to encode custom product page search keyword mutation")
        }
        let path: String
        do {
            path = "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))/relationships/searchKeywords"
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate custom product page search keyword mutation")
        }
        let inspection = listInspection(
            tool: "custom_pages_list_search_keywords",
            arguments: ["localization_id": localizationID],
            instruction: "Inspect every attached keyword ID for the exact localization before retrying this relationship mutation."
        )
        if method == "POST" {
            let receipt: ASCMutationReceipt
            do {
                receipt = try await httpClient.postReceipt(path, body: body)
            } catch {
                return customPageMutationFailure(
                    operation: operation,
                    phase: .request,
                    error: error,
                    identifiers: ["localizationId": localizationID, "keywordIds": keywordIDs],
                    inspection: inspection
                )
            }
            guard receipt.statusCode == 204 else {
                return customPageMutationFailure(
                    operation: operation,
                    phase: .acceptedResponse,
                    error: customPageAcceptedMutationError(
                        ASCError.api("Search keyword relationship POST expected HTTP 204", receipt.statusCode),
                        method: "POST",
                        expectedStatusCode: 204,
                        actualStatusCode: receipt.statusCode
                    ),
                    identifiers: ["localizationId": localizationID, "keywordIds": keywordIDs],
                    inspection: inspection
                )
            }
            return searchKeywordMutationSuccess(
                operation: operation,
                localizationID: localizationID,
                keywordIDs: keywordIDs,
                statusCode: receipt.statusCode,
                confirmationMatched: confirmationMatched
            )
        }

        let receipt: ASCDeleteReceipt
        do {
            receipt = try await httpClient.deleteReceipt(path, body: body)
        } catch {
            return customPageMutationFailure(
                operation: operation,
                phase: .request,
                error: error,
                identifiers: ["localizationId": localizationID, "keywordIds": keywordIDs],
                inspection: inspection
            )
        }
        guard receipt.statusCode == 204 else {
            return customPageMutationFailure(
                operation: operation,
                phase: .acceptedResponse,
                error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode),
                identifiers: ["localizationId": localizationID, "keywordIds": keywordIDs],
                inspection: inspection
            )
        }
        return searchKeywordMutationSuccess(
            operation: operation,
            localizationID: localizationID,
            keywordIDs: keywordIDs,
            statusCode: receipt.statusCode,
            confirmationMatched: confirmationMatched
        )
    }

    func searchKeywordMutationSuccess(
        operation: String,
        localizationID: String,
        keywordIDs: [String],
        statusCode: Int,
        confirmationMatched: Bool
    ) -> CallTool.Result {
        var result: [String: Any] = [
            "success": true,
            "operation": operation,
            "operationCommitted": true,
            "operationCommitState": "committed",
            "changed": NSNull(),
            "retrySafe": false,
            "localizationId": localizationID,
            "keywordIds": keywordIDs,
            "statusCode": statusCode
        ]
        if confirmationMatched {
            result["confirmationMatched"] = true
        }
        return MCPResult.jsonObject(result)
    }

    func validateCustomPageArguments(_ arguments: [String: Value], allowed: Set<String>) throws {
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw CustomProductPageInputError("Unsupported parameter(s): \(unsupported.joined(separator: ", "))")
        }
    }

    func customPageIdentifier(_ name: String, from arguments: [String: Value]) throws -> String {
        guard let value = arguments[name]?.stringValue else {
            throw CustomProductPageInputError("\(name) must be a string")
        }
        let encoded = try ASCPathSegment.encode(value, field: name)
        guard encoded == value else {
            throw CustomProductPageInputError("\(name) must be a canonical App Store Connect resource ID")
        }
        return value
    }

    func optionalCustomPageIdentifier(_ name: String, from arguments: [String: Value]) throws -> String? {
        guard arguments[name] != nil else { return nil }
        return try customPageIdentifier(name, from: arguments)
    }

    func customPageIdentifierList(_ name: String, from arguments: [String: Value]) throws -> [String] {
        guard let values = arguments[name]?.arrayValue, !values.isEmpty else {
            throw CustomProductPageInputError("\(name) must be a non-empty array of canonical resource IDs")
        }
        var seen: Set<String> = []
        return try values.enumerated().map { index, value in
            guard let identifier = value.stringValue else {
                throw CustomProductPageInputError("\(name)[\(index)] must be a string")
            }
            let encoded = try ASCPathSegment.encode(identifier, field: "\(name)[\(index)]")
            guard encoded == identifier else {
                throw CustomProductPageInputError("\(name)[\(index)] must be a canonical resource ID")
            }
            guard seen.insert(identifier).inserted else {
                throw CustomProductPageInputError("\(name) must not contain duplicate IDs")
            }
            return identifier
        }
    }

    func requiredCustomPageString(_ name: String, from arguments: [String: Value]) throws -> String {
        guard let string = arguments[name]?.stringValue,
              !string.isEmpty,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CustomProductPageInputError("\(name) must be a non-empty string without surrounding whitespace or controls")
        }
        return string
    }

    func nullableCustomPageString(
        _ value: Value?,
        field: String
    ) throws -> ASCCustomProductPageNullable<String>? {
        guard let value else { return nil }
        if value.isNull { return .null }
        guard let string = value.stringValue else {
            throw CustomProductPageInputError("\(field) must be a string or null")
        }
        return .value(string)
    }

    func nullableCustomPageBoolean(
        _ value: Value?,
        field: String
    ) throws -> ASCCustomProductPageNullable<Bool>? {
        guard let value else { return nil }
        if value.isNull { return .null }
        guard let boolean = value.boolValue else {
            throw CustomProductPageInputError("\(field) must be a boolean or null")
        }
        return .value(boolean)
    }

    func customPageLimit(_ value: Value?) throws -> Int {
        guard let value else { return 25 }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw CustomProductPageInputError("limit must be an integer between 1 and 200")
        }
        return limit
    }

    func commaSeparatedStrings(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> String? {
        guard let value else { return nil }
        let values: [String]
        if let string = value.stringValue {
            values = [string]
        } else if let array = value.arrayValue {
            let strings = array.compactMap(\.stringValue)
            guard strings.count == array.count else {
                throw CustomProductPageInputError("\(field) must contain only strings")
            }
            values = strings
        } else {
            throw CustomProductPageInputError("\(field) must be a string or an array of strings")
        }
        guard !values.isEmpty,
              values.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
            throw CustomProductPageInputError("\(field) must contain non-empty strings without surrounding whitespace")
        }
        guard values.allSatisfy({ !$0.contains(",") }) else {
            throw CustomProductPageInputError("\(field) values must not contain commas")
        }
        guard Set(values).count == values.count else {
            throw CustomProductPageInputError("\(field) must not contain duplicate values")
        }
        if let allowedValues,
           let unsupported = values.first(where: { !allowedValues.contains($0) }) {
            throw CustomProductPageInputError("Unsupported value '\(unsupported)' for \(field)")
        }
        return values.joined(separator: ",")
    }

    func commaSeparatedBooleans(_ value: Value?, field: String) throws -> String? {
        guard let value else { return nil }
        let values: [Bool]
        if let boolean = value.boolValue {
            values = [boolean]
        } else if let array = value.arrayValue {
            let booleans = array.compactMap(\.boolValue)
            guard !array.isEmpty, booleans.count == array.count else {
                throw CustomProductPageInputError("\(field) must contain one or more booleans")
            }
            values = booleans
        } else {
            throw CustomProductPageInputError("\(field) must be a boolean or an array of booleans")
        }
        guard Set(values).count == values.count else {
            throw CustomProductPageInputError("\(field) must not contain duplicate values")
        }
        return values.map(String.init).joined(separator: ",")
    }

    func nullableAbsoluteURI(
        _ value: Value?,
        field: String
    ) throws -> ASCCustomProductPageNullable<String>? {
        guard let value else { return nil }
        if value.isNull { return .null }
        guard let string = value.stringValue, isAbsoluteURI(string) else {
            throw CustomProductPageInputError("\(field) must be an absolute URI or null")
        }
        return .value(string)
    }

    func isAbsoluteURI(_ value: String) -> Bool {
        let schemePattern = "^[A-Za-z][A-Za-z0-9+.-]*$"
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: value),
              let scheme = components.scheme,
              scheme.range(of: schemePattern, options: .regularExpression) != nil,
              URL(string: value)?.scheme == scheme else {
            return false
        }
        return true
    }

    func applyNullable<T: Codable & Sendable>(
        _ value: ASCCustomProductPageNullable<T>?,
        key: String,
        to object: inout [String: Any]
    ) {
        guard let value else { return }
        switch value {
        case .value(let concrete): object[key] = concrete
        case .null: object[key] = NSNull()
        }
    }

    func validatePage(
        _ page: ASCCustomProductPage,
        expectedID: String?,
        expectedAppID: String? = nil,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: page.type,
            id: page.id,
            expectedType: "appCustomProductPages",
            expectedID: expectedID,
            context: context
        )
        if let url = page.attributes?.url, !isAbsoluteURI(url) {
            throw CustomProductPageInputError("\(context) returned a non-absolute page URL")
        }
        if let resourceSelf = page.links?.`self` {
            try validateCustomPageDocumentSelf(
                resourceSelf,
                expectedPath: "/v1/appCustomProductPages/\(try ASCPathSegment.encode(page.id, field: "custom product page response ID"))",
                context: "\(context) resource"
            )
        }
        try validateToOneRelationship(
            page.relationships?.app,
            expectedType: "apps",
            expectedID: expectedAppID,
            context: "\(context) app relationship"
        )
        try validateToManyRelationship(
            page.relationships?.appCustomProductPageVersions,
            expectedType: "appCustomProductPageVersions",
            context: "\(context) version relationship"
        )
    }

    func validatePages(
        _ pages: [ASCCustomProductPage],
        expectedAppID: String?,
        context: String
    ) throws {
        var seen: Set<String> = []
        for page in pages {
            try validatePage(
                page,
                expectedID: nil,
                expectedAppID: expectedAppID,
                context: context
            )
            guard seen.insert(page.id).inserted else {
                throw CustomProductPageInputError("\(context) returned a duplicate resource ID")
            }
        }
    }

    func validateVersion(
        _ version: ASCCustomProductPageVersion,
        expectedID: String?,
        expectedPageID: String? = nil,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: version.type,
            id: version.id,
            expectedType: "appCustomProductPageVersions",
            expectedID: expectedID,
            context: context
        )
        if let state = version.attributes?.state,
           !customProductPageVersionStates.contains(state) {
            throw CustomProductPageInputError("\(context) returned an unsupported version state")
        }
        if let deepLink = version.attributes?.deepLink, !isAbsoluteURI(deepLink) {
            throw CustomProductPageInputError("\(context) returned a non-absolute deep link")
        }
        if let resourceSelf = version.links?.`self` {
            try validateCustomPageDocumentSelf(
                resourceSelf,
                expectedPath: "/v1/appCustomProductPageVersions/\(try ASCPathSegment.encode(version.id, field: "custom product page version response ID"))",
                context: "\(context) resource"
            )
        }
        try validateToOneRelationship(
            version.relationships?.appCustomProductPage,
            expectedType: "appCustomProductPages",
            expectedID: expectedPageID,
            context: "\(context) page relationship"
        )
        try validateToManyRelationship(
            version.relationships?.appCustomProductPageLocalizations,
            expectedType: "appCustomProductPageLocalizations",
            context: "\(context) localization relationship"
        )
    }

    func validateVersions(
        _ versions: [ASCCustomProductPageVersion],
        expectedPageID: String?,
        context: String
    ) throws {
        var seen: Set<String> = []
        for version in versions {
            try validateVersion(
                version,
                expectedID: nil,
                expectedPageID: expectedPageID,
                context: context
            )
            guard seen.insert(version.id).inserted else {
                throw CustomProductPageInputError("\(context) returned a duplicate resource ID")
            }
        }
    }

    func validateLocalization(
        _ localization: ASCCustomProductPageLocalization,
        expectedID: String?,
        expectedVersionID: String? = nil,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: localization.type,
            id: localization.id,
            expectedType: "appCustomProductPageLocalizations",
            expectedID: expectedID,
            context: context
        )
        if let locale = localization.attributes?.locale,
           locale.isEmpty || locale != locale.trimmingCharacters(in: .whitespacesAndNewlines) {
            throw CustomProductPageInputError("\(context) returned an invalid locale")
        }
        if let resourceSelf = localization.links?.`self` {
            try validateCustomPageDocumentSelf(
                resourceSelf,
                expectedPath: "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(localization.id, field: "custom product page localization response ID"))",
                context: "\(context) resource"
            )
        }
        try validateToOneRelationship(
            localization.relationships?.appCustomProductPageVersion,
            expectedType: "appCustomProductPageVersions",
            expectedID: expectedVersionID,
            context: "\(context) version relationship"
        )
        try validateToManyRelationship(
            localization.relationships?.appScreenshotSets,
            expectedType: "appScreenshotSets",
            context: "\(context) screenshot-set relationship"
        )
        try validateToManyRelationship(
            localization.relationships?.appPreviewSets,
            expectedType: "appPreviewSets",
            context: "\(context) preview-set relationship"
        )
        try validateToManyRelationship(
            localization.relationships?.searchKeywords,
            expectedType: "appKeywords",
            context: "\(context) search-keyword relationship"
        )
    }

    func validateLocalizations(
        _ localizations: [ASCCustomProductPageLocalization],
        expectedVersionID: String?,
        context: String
    ) throws {
        var seen: Set<String> = []
        for localization in localizations {
            try validateLocalization(
                localization,
                expectedID: nil,
                expectedVersionID: expectedVersionID,
                context: context
            )
            guard seen.insert(localization.id).inserted else {
                throw CustomProductPageInputError("\(context) returned a duplicate resource ID")
            }
        }
    }

    func validateSearchKeywords(
        _ response: ASCAppKeywordsResponse,
        expectedPath: String,
        requestedLimit: Int,
        paginationScope: PaginationScope
    ) throws {
        var seen: Set<String> = []
        for keyword in response.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: keyword.type,
                id: keyword.id,
                expectedType: "appKeywords",
                context: "custom product page search keyword list"
            )
            guard seen.insert(keyword.id).inserted else {
                throw CustomProductPageInputError("Apple returned a duplicate search keyword ID")
            }
        }
        try validateCustomPageCollection(
            links: response.links,
            meta: response.meta,
            count: response.data.count,
            requestedLimit: requestedLimit,
            expectedPath: expectedPath,
            paginationScope: paginationScope,
            context: "custom product page search keyword list"
        )
    }

    func validateCustomPageCollection(
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        count: Int,
        requestedLimit: Int,
        expectedPath: String,
        paginationScope: PaginationScope,
        context: String
    ) throws {
        try validateCustomPageDocumentSelf(
            links.`self`,
            expectedPath: expectedPath,
            context: context
        )
        guard count <= requestedLimit else {
            throw CustomProductPageInputError("Apple returned more \(context) resources than requested")
        }
        let nextRequest = try links.next.map {
            try httpClient.validatedScopedLink($0, scope: paginationScope)
        }
        if let meta {
            guard let paging = meta.paging,
                  paging.limit == requestedLimit,
                  count <= requestedLimit else {
                throw CustomProductPageInputError("Apple returned invalid paging metadata for \(context)")
            }
            if let total = paging.total, total < count {
                throw CustomProductPageInputError("Apple returned a paging total below the \(context) page count")
            }
            if let cursor = paging.nextCursor {
                guard !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      nextRequest?.parameters["cursor"] == cursor else {
                    throw CustomProductPageInputError("Apple returned inconsistent cursor metadata for \(context)")
                }
            }
        }
    }

    func validateCustomPageDocumentSelf(
        _ value: String,
        expectedPath: String,
        context: String
    ) throws {
        do {
            _ = try httpClient.validatedScopedLink(
                value,
                scope: PaginationScope(path: expectedPath)
            )
        } catch {
            throw CustomProductPageInputError("Apple returned an invalid required links.self for \(context)")
        }
    }

    func validateToOneRelationship(
        _ relationship: ASCCustomProductPageToOneRelationship?,
        expectedType: String,
        expectedID: String?,
        context: String
    ) throws {
        guard let identifier = relationship?.data else { return }
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: identifier.type,
            id: identifier.id,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
    }

    func validateToManyRelationship(
        _ relationship: ASCCustomProductPageToManyRelationship?,
        expectedType: String,
        context: String
    ) throws {
        guard let identifiers = relationship?.data else { return }
        var seen: Set<String> = []
        for identifier in identifiers {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: identifier.type,
                id: identifier.id,
                expectedType: expectedType,
                context: context
            )
            guard seen.insert(identifier.id).inserted else {
                throw CustomProductPageInputError("Apple returned a duplicate relationship ID for \(context)")
            }
        }
    }

    func pageUpdateMatches(
        _ page: ASCCustomProductPage,
        name: ASCCustomProductPageNullable<String>?,
        visible: ASCCustomProductPageNullable<Bool>?
    ) -> Bool {
        nullableStringMatches(
            presence: page.attributes?.hasName == true,
            value: page.attributes?.name,
            expected: name
        ) && nullableBooleanMatches(
            presence: page.attributes?.hasVisible == true,
            value: page.attributes?.visible,
            expected: visible
        )
    }

    func nullableStringMatches(
        presence: Bool,
        value: String?,
        expected: ASCCustomProductPageNullable<String>?
    ) -> Bool {
        guard let expected else { return true }
        guard presence else { return false }
        switch expected {
        case .value(let expectedValue): return value == expectedValue
        case .null: return value == nil
        }
    }

    func nullableBooleanMatches(
        presence: Bool,
        value: Bool?,
        expected: ASCCustomProductPageNullable<Bool>?
    ) -> Bool {
        guard let expected else { return true }
        guard presence else { return false }
        switch expected {
        case .value(let expectedValue): return value == expectedValue
        case .null: return value == nil
        }
    }

    func formatCustomPage(_ page: ASCCustomProductPage) -> [String: Any] {
        var result: [String: Any] = [
            "id": page.id,
            "type": page.type,
            "name": (page.attributes?.name).jsonSafe,
            "nameState": attributeState(page.attributes?.hasName == true, page.attributes?.name),
            "url": (page.attributes?.url).jsonSafe,
            "urlState": attributeState(page.attributes?.hasURL == true, page.attributes?.url),
            "visible": (page.attributes?.visible).jsonSafe,
            "visibleState": attributeState(page.attributes?.hasVisible == true, page.attributes?.visible),
            "state": NSNull()
        ]
        if let app = page.relationships?.app?.data {
            result["appId"] = app.id
        }
        return result
    }

    func formatVersion(_ version: ASCCustomProductPageVersion) -> [String: Any] {
        var result: [String: Any] = [
            "id": version.id,
            "type": version.type,
            "version": (version.attributes?.version).jsonSafe,
            "state": (version.attributes?.state).jsonSafe,
            "deepLink": (version.attributes?.deepLink).jsonSafe,
            "deepLinkState": attributeState(
                version.attributes?.hasDeepLink == true,
                version.attributes?.deepLink
            )
        ]
        if let page = version.relationships?.appCustomProductPage?.data {
            result["pageId"] = page.id
        }
        return result
    }

    func formatLocalization(_ localization: ASCCustomProductPageLocalization) -> [String: Any] {
        var result: [String: Any] = [
            "id": localization.id,
            "type": localization.type,
            "locale": (localization.attributes?.locale).jsonSafe,
            "promotionalText": (localization.attributes?.promotionalText).jsonSafe,
            "promotionalTextState": attributeState(
                localization.attributes?.hasPromotionalText == true,
                localization.attributes?.promotionalText
            )
        ]
        if let version = localization.relationships?.appCustomProductPageVersion?.data {
            result["versionId"] = version.id
        }
        return result
    }

    func formatSearchKeyword(_ keyword: ASCAppKeyword) -> [String: Any] {
        ["id": keyword.id, "type": keyword.type]
    }

    func attributeState<T>(_ present: Bool, _ value: T?) -> String {
        guard present else { return "omitted" }
        return value == nil ? "null" : "value"
    }

    func createPageRecoveryIdentifiers(
        appID: String,
        name: String,
        locale: String,
        promotionalText: ASCCustomProductPageNullable<String>?,
        templateVersionID: String?,
        templatePageID: String?
    ) -> [String: Any] {
        [
            "appId": appID,
            "requested": [
                "name": ["state": "value", "value": name],
                "locale": ["state": "value", "value": locale],
                "promotionalText": nullableStringRecoveryValue(promotionalText),
                "templateVersionId": optionalIdentifierRecoveryValue(templateVersionID),
                "templatePageId": optionalIdentifierRecoveryValue(templatePageID)
            ]
        ]
    }

    func updatePageRecoveryIdentifiers(
        pageID: String,
        name: ASCCustomProductPageNullable<String>?,
        visible: ASCCustomProductPageNullable<Bool>?
    ) -> [String: Any] {
        [
            "pageId": pageID,
            "requested": [
                "name": nullableStringRecoveryValue(name),
                "visible": nullableBooleanRecoveryValue(visible)
            ]
        ]
    }

    func createVersionRecoveryIdentifiers(
        pageID: String,
        deepLink: ASCCustomProductPageNullable<String>?
    ) -> [String: Any] {
        [
            "pageId": pageID,
            "requested": ["deepLink": nullableStringRecoveryValue(deepLink)]
        ]
    }

    func updateVersionRecoveryIdentifiers(
        versionID: String,
        deepLink: ASCCustomProductPageNullable<String>
    ) -> [String: Any] {
        [
            "versionId": versionID,
            "requested": ["deepLink": nullableStringRecoveryValue(deepLink)]
        ]
    }

    func createLocalizationRecoveryIdentifiers(
        versionID: String,
        locale: String,
        promotionalText: ASCCustomProductPageNullable<String>?
    ) -> [String: Any] {
        [
            "versionId": versionID,
            "requested": [
                "locale": ["state": "value", "value": locale],
                "promotionalText": nullableStringRecoveryValue(promotionalText)
            ]
        ]
    }

    func updateLocalizationRecoveryIdentifiers(
        localizationID: String,
        promotionalText: ASCCustomProductPageNullable<String>
    ) -> [String: Any] {
        [
            "localizationId": localizationID,
            "requested": [
                "promotionalText": nullableStringRecoveryValue(promotionalText)
            ]
        ]
    }

    func nullableStringRecoveryValue(
        _ value: ASCCustomProductPageNullable<String>?
    ) -> [String: Any] {
        guard let value else { return ["state": "omitted"] }
        switch value {
        case .value(let concrete):
            return ["state": "value", "value": concrete]
        case .null:
            return ["state": "null", "value": NSNull()]
        }
    }

    func nullableBooleanRecoveryValue(
        _ value: ASCCustomProductPageNullable<Bool>?
    ) -> [String: Any] {
        guard let value else { return ["state": "omitted"] }
        switch value {
        case .value(let concrete):
            return ["state": "value", "value": concrete]
        case .null:
            return ["state": "null", "value": NSNull()]
        }
    }

    func optionalIdentifierRecoveryValue(_ value: String?) -> [String: Any] {
        guard let value else { return ["state": "omitted"] }
        return ["state": "value", "value": value]
    }

    func customPageMutationFailure(
        operation: String,
        phase: ASCNonIdempotentWriteFailurePhase,
        error: Error,
        identifiers: [String: Any],
        inspection: [String: Any]
    ) -> CallTool.Result {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: phase)
        var payload = identifiers
        payload["success"] = false
        payload["operation"] = operation
        payload["action"] = operation
        payload["operationCommitState"] = disposition.rawValue
        payload["write_outcome"] = disposition.rawValue
        payload["mutationAttempted"] = true
        payload["retrySafe"] = disposition == .rejected
        payload["error"] = Redactor.redact(error.localizedDescription)
        payload["cause"] = customPageMutationCause(error, phase: phase)
        payload["inspection"] = inspection
        payload["recovery"] = [
            "action": disposition == .rejected ? "correct_request_before_retry" : "inspect_before_retry",
            "inspection": inspection,
            "retryOnlyAfterVerification": disposition != .rejected
        ]
        switch disposition {
        case .rejected:
            payload["operationCommitted"] = false
            payload["outcomeUnknown"] = false
        case .outcomeUnknown:
            payload["operationCommitted"] = NSNull()
            payload["outcomeUnknown"] = true
            payload["inspectionRequired"] = true
        case .committedUnverified:
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
            payload["inspectionRequired"] = true
        }
        let text: String
        switch disposition {
        case .rejected:
            text = "Error: Apple definitively rejected the custom product page mutation."
        case .outcomeUnknown:
            text = "Error: The custom product page mutation outcome is unknown. Inspect the exact target before retrying."
        case .committedUnverified:
            text = "Error: Apple accepted the custom product page mutation, but its exact result was not verified. Inspect before retrying."
        }
        return MCPResult.jsonObject(payload, text: text, isError: true)
    }

    func customPageAcceptedMutationError(
        _ error: Error,
        method: String,
        expectedStatusCode: Int,
        actualStatusCode: Int
    ) -> ASCError {
        let cause: ASCError
        if let ascError = error as? ASCError {
            if case .mutationCommittedUnverified = ascError {
                return ascError
            }
            cause = ascError
        } else {
            cause = .parsing(Redactor.redact(error.localizedDescription))
        }
        return .mutationCommittedUnverified(
            method: method,
            expectedStatusCode: expectedStatusCode,
            actualStatusCode: actualStatusCode,
            cause: cause
        )
    }

    func customPageMutationCause(
        _ error: Error,
        phase: ASCNonIdempotentWriteFailurePhase
    ) -> Value {
        if let ascError = error as? ASCError {
            return ascError.structuredValue
        }
        if error is CancellationError {
            return .object([
                "type": .string("cancellation"),
                "message": .string("The request was cancelled before its write outcome was confirmed")
            ])
        }
        return .object([
            "type": .string(phase == .request ? "request" : "response_validation"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
    }

    func getInspection(
        tool: String,
        arguments: [String: Any],
        instruction: String
    ) -> [String: Any] {
        ["tool": tool, "arguments": arguments, "instruction": instruction]
    }

    func listInspection(
        tool: String,
        arguments: [String: Any],
        instruction: String
    ) -> [String: Any] {
        [
            "tool": tool,
            "arguments": arguments,
            "continueWithNextURL": true,
            "instruction": instruction
        ]
    }
}

private struct CustomProductPageInputError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
