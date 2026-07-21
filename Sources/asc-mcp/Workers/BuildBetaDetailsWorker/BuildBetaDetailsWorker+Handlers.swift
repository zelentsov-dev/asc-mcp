import Foundation
import MCP

// MARK: - Tool Handlers
extension BuildBetaDetailsWorker {
    private func validateBetaLocalizationArguments(
        _ arguments: [String: Value],
        locale: String
    ) -> [ASCMetadataValidator.FieldError] {
        var errors = ASCMetadataValidator.validateLocale(locale)

        if let value = arguments["whats_new"], !value.isNull {
            if let whatsNew = value.stringValue {
                errors += ASCMetadataValidator.validateTextFields(
                    ["whats_new": whatsNew],
                    limits: ["whats_new": 4_000]
                )
            } else {
                errors.append(.init(field: "whats_new", message: "Value must be a string or null"))
            }
        }

        return errors
    }

    
    /// Gets TestFlight beta details for a specific build
    /// - Returns: JSON with beta detail including auto-notify settings and build states
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func getBetaDetail(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }
        
        do {
            let response: ASCBuildBetaDetailResponse = try await httpClient.get(
                "/v1/builds/\(try ASCPathSegment.encode(buildId))/buildBetaDetail",
                parameters: [:],
                as: ASCBuildBetaDetailResponse.self
            )

            let betaDetailInfo = formatBetaDetail(response.data)

            let result = [
                "success": true,
                "buildId": buildId,
                "betaDetail": betaDetailInfo,
                "note": "Use builds_list_beta_localizations to get localizations for this build"
            ] as [String: Any]
            
            return MCPResult.jsonObject(result)
            
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get beta detail: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Updates TestFlight beta detail settings for a build
    /// - Returns: JSON with updated beta detail configuration
    /// - Throws: CallTool.Result with error if beta_detail_id missing or update fails
    func updateBetaDetail(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let betaDetailIdValue = arguments["beta_detail_id"],
              let betaDetailId = betaDetailIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'beta_detail_id' is missing")],
                isError: true
            )
        }

        let unsupportedFields = ["internal_build_state", "external_build_state"]
            .filter { arguments[$0] != nil }
        if !unsupportedFields.isEmpty {
            return MCPResult.error(
                "Unsupported read-only parameter(s): \(unsupportedFields.joined(separator: ", ")). Apple only permits auto_notify when updating a build beta detail."
            )
        }
        
        guard let autoNotifyValue = arguments["auto_notify"] else {
            return MCPResult.error("At least one updatable field is required: auto_notify")
        }

        let autoNotify: ASCNullable<Bool>
        if autoNotifyValue.isNull {
            autoNotify = .null
        } else if let bool = autoNotifyValue.boolValue {
            autoNotify = .value(bool)
        } else {
            return MCPResult.error("'auto_notify' must be a boolean or null")
        }

        do {
            
            let updateRequest = UpdateBuildBetaDetailRequest(
                data: UpdateBuildBetaDetailRequest.UpdateBuildBetaDetailData(
                    id: betaDetailId,
                    attributes: UpdateBuildBetaDetailRequest.BuildBetaDetailUpdateAttributes(
                        autoNotifyEnabled: autoNotify
                    )
                )
            )
            
            let response: ASCBuildBetaDetailResponse = try await httpClient.patch(
                "/v1/buildBetaDetails/\(try ASCPathSegment.encode(betaDetailId))",
                body: updateRequest,
                as: ASCBuildBetaDetailResponse.self
            )
            
            let betaDetail = formatBetaDetail(response.data)
            
            let result = [
                "success": true,
                "betaDetail": betaDetail
            ] as [String: Any]
            
            return MCPResult.jsonObject(result)
            
        } catch {
            return MCPResult.error(error, prefix: "Failed to update beta detail")
        }
    }
    
    /// Sets or updates TestFlight What's New text for a specific locale
    /// - Returns: JSON with localization details and action taken (created/updated)
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    func setBetaLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue else {
            return MCPResult.error("Required parameters 'build_id' and 'locale' are missing")
        }

        let unsupportedFields = [
            "feedback_email",
            "marketing_url",
            "privacy_policy_url",
            "tv_os_privacy_policy"
        ].filter { arguments[$0] != nil }
        if !unsupportedFields.isEmpty {
            return MCPResult.error(
                "Unsupported build-localization parameter(s): \(unsupportedFields.joined(separator: ", ")). Use beta_app_create_localization or beta_app_update_localization for app-level TestFlight contact and policy metadata."
            )
        }

        let validationErrors = validateBetaLocalizationArguments(arguments, locale: locale)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        let whatsNew: ASCNullable<String>?
        if let value = arguments["whats_new"] {
            if value.isNull {
                whatsNew = .null
            } else if let string = value.stringValue {
                whatsNew = .value(string)
            } else {
                return MCPResult.error("'whats_new' must be a string or null")
            }
        } else {
            whatsNew = nil
        }
        
        do {
            let existingResponse: ASCBetaBuildLocalizationsResponse = try await httpClient.get(
                "/v1/betaBuildLocalizations",
                parameters: [
                    "filter[build]": buildId,
                    "filter[locale]": locale,
                    "limit": "1"
                ],
                as: ASCBetaBuildLocalizationsResponse.self
            )
            let existingData = existingResponse.data
            
            if existingData.isEmpty {
                // Create new localization
                let createRequest = CreateBetaBuildLocalizationRequest(
                    data: CreateBetaBuildLocalizationRequest.CreateBetaBuildLocalizationData(
                        attributes: CreateBetaBuildLocalizationRequest.CreateBetaBuildLocalizationAttributes(
                            locale: locale,
                            whatsNew: whatsNew
                        ),
                        relationships: CreateBetaBuildLocalizationRequest.CreateBetaBuildLocalizationRelationships(
                            build: CreateBetaBuildLocalizationRequest.BuildRelationship(
                                data: ASCResourceIdentifier(type: "builds", id: buildId)
                            )
                        )
                    )
                )
                
                let response: ASCBetaBuildLocalizationResponse = try await httpClient.post(
                    "/v1/betaBuildLocalizations",
                    body: createRequest,
                    as: ASCBetaBuildLocalizationResponse.self
                )
                
                let localization = formatBetaBuildLocalization(response.data)
                
                let result = [
                    "success": true,
                    "action": "created",
                    "localization": localization
                ] as [String: Any]
                
                return MCPResult.jsonObject(result)
                
            } else {
                // Update existing localization
                guard let localizationData = existingData.first else {
                    return MCPResult.error("Failed to get localization")
                }
                
                let localizationId = localizationData.id
                
                let updateAttributes = UpdateBetaBuildLocalizationRequest.BetaBuildLocalizationUpdateAttributes(
                    whatsNew: whatsNew
                )
                
                if updateAttributes.whatsNew == nil {
                    return MCPResult.error("At least one updatable field is required: whats_new")
                }
                
                let updateRequest = UpdateBetaBuildLocalizationRequest(
                    data: UpdateBetaBuildLocalizationRequest.UpdateBetaBuildLocalizationData(
                        id: localizationId,
                        attributes: updateAttributes
                    )
                )
                
                let response: ASCBetaBuildLocalizationResponse = try await httpClient.patch(
                    "/v1/betaBuildLocalizations/\(try ASCPathSegment.encode(localizationId))",
                    body: updateRequest,
                    as: ASCBetaBuildLocalizationResponse.self
                )
                
                let localization = formatBetaBuildLocalization(response.data)
                
                let result = [
                    "success": true,
                    "action": "updated",
                    "localization": localization
                ] as [String: Any]
                
                return MCPResult.jsonObject(result)
            }
            
        } catch {
            return MCPResult.error(error, prefix: "Failed to set beta localization")
        }
    }
    
    /// Lists all TestFlight localizations for a build
    /// - Returns: JSON array of localizations with locale, What's New text, and build linkage
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func listBetaLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        let limit: Int
        if let value = arguments["limit"] {
            guard let parsed = value.intValue, (1...200).contains(parsed) else {
                return MCPResult.error("'limit' must be an integer from 1 through 200")
            }
            limit = parsed
        } else {
            limit = 50
        }

        do {
            let endpoint = "/v1/builds/\(try ASCPathSegment.encode(buildId))/betaBuildLocalizations"
            let queryParams = ["limit": String(limit)]
            let response: ASCBetaBuildLocalizationsResponse

            // Check for pagination URL
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(path: endpoint, query: queryParams),
                    as: ASCBetaBuildLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCBetaBuildLocalizationsResponse.self
                )
            }

            let localizations = response.data.map { formatBetaBuildLocalization($0) }

            var result: [String: Any] = [
                "success": true,
                "localizations": localizations,
                "count": localizations.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list beta localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Gets beta groups associated with a build
    /// - Returns: JSON array of beta groups with names, public links, and tester counts
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    /// - Note: Uses filter[builds] parameter as direct relationship access is not supported
    func getBetaGroups(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        let limit: Int
        if let value = arguments["limit"] {
            guard let parsed = value.intValue, (1...200).contains(parsed) else {
                return MCPResult.error("'limit' must be an integer from 1 through 200")
            }
            limit = parsed
        } else {
            limit = 50
        }

        do {
            let response: ASCBetaGroupsResponse
            var queryParams: [String: String] = [
                "filter[builds]": buildId,
                "limit": String(limit)
            ]
            applyBetaGroupStringList(arguments["group_ids"], as: "filter[id]", to: &queryParams)
            applyBetaGroupStringList(arguments["name"], as: "filter[name]", to: &queryParams)
            applyBetaGroupStringList(arguments["public_link"], as: "filter[publicLink]", to: &queryParams)
            if let value = arguments["is_internal"]?.boolValue {
                queryParams["filter[isInternalGroup]"] = value ? "true" : "false"
            }
            if let value = arguments["public_link_enabled"]?.boolValue {
                queryParams["filter[publicLinkEnabled]"] = value ? "true" : "false"
            }
            if let value = arguments["public_link_limit_enabled"]?.boolValue {
                queryParams["filter[publicLinkLimitEnabled]"] = value ? "true" : "false"
            }
            if let sort = arguments["sort"]?.stringValue {
                queryParams["sort"] = sort
            }

            // Check for pagination URL
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/betaGroups",
                        query: queryParams
                    ),
                    as: ASCBetaGroupsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/betaGroups",
                    parameters: queryParams,
                    as: ASCBetaGroupsResponse.self
                )
            }

            let groups = response.data.map { formatBetaGroup($0) }

            var result: [String: Any] = [
                "success": true,
                "betaGroups": groups,
                "count": groups.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get beta groups: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Gets individual beta testers who have access to a build
    /// - Returns: JSON array of testers with names, emails, and invitation status
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func getBetaTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        let limit: Int
        if let value = arguments["limit"] {
            guard let parsed = value.intValue, (1...200).contains(parsed) else {
                return MCPResult.error("'limit' must be an integer from 1 through 200")
            }
            limit = parsed
        } else {
            limit = 50
        }

        do {
            let endpoint = "/v1/builds/\(try ASCPathSegment.encode(buildId))/individualTesters"
            let queryParams = ["limit": String(limit)]
            let response: ASCBetaTestersResponse

            // Check for pagination URL
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(path: endpoint, query: queryParams),
                    as: ASCBetaTestersResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCBetaTestersResponse.self
                )
            }

            let testers = response.data.map { formatBetaTester($0) }

            var result: [String: Any] = [
                "success": true,
                "betaTesters": testers,
                "count": testers.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get beta testers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Adds a build to one or more beta groups
    /// - Returns: JSON confirmation of the operation
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    func addToBetaGroups(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue,
              let groupIdsValue = arguments["group_ids"],
              let groupIdsArray = groupIdsValue.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters 'build_id' and 'group_ids' are missing")],
                isError: true
            )
        }

        let groupIds = groupIdsArray.compactMap { $0.stringValue }
        guard !groupIds.isEmpty,
              groupIds.count == groupIdsArray.count,
              groupIds.allSatisfy({ !$0.isEmpty }) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: 'group_ids' must contain only non-empty group ID strings")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: groupIds.map { ASCResourceIdentifier(type: "betaGroups", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/builds/\(try ASCPathSegment.encode(buildId))/relationships/betaGroups",
                body: bodyData,
                expectedStatusCode: 204
            )

            let result = [
                "success": true,
                "message": "Added build '\(buildId)' to \(groupIds.count) beta group(s)"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to add build to beta groups")
        }
    }

    /// Adds individual beta testers to a specific build
    /// - Returns: JSON confirmation of the operation
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    func addIndividualTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue,
              let testerIdsValue = arguments["beta_tester_ids"],
              let testerIdsArray = testerIdsValue.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters 'build_id' and 'beta_tester_ids' are missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }
        guard !testerIds.isEmpty,
              testerIds.count == testerIdsArray.count,
              testerIds.allSatisfy({ !$0.isEmpty }) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: 'beta_tester_ids' must contain only non-empty tester ID strings")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: testerIds.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/builds/\(try ASCPathSegment.encode(buildId))/relationships/individualTesters",
                body: bodyData,
                expectedStatusCode: 204
            )

            let result = [
                "success": true,
                "message": "Added \(testerIds.count) individual tester(s) to build '\(buildId)'"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to add individual testers")
        }
    }

    /// Removes individual beta testers from a specific build
    /// - Returns: JSON confirmation of the operation
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    func removeIndividualTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue,
              let testerIdsValue = arguments["beta_tester_ids"],
              let testerIdsArray = testerIdsValue.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters 'build_id' and 'beta_tester_ids' are missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }
        guard !testerIds.isEmpty,
              testerIds.count == testerIdsArray.count,
              testerIds.allSatisfy({ !$0.isEmpty }) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: 'beta_tester_ids' must contain only non-empty tester ID strings")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: testerIds.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/builds/\(try ASCPathSegment.encode(buildId))/relationships/individualTesters",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Removed \(testerIds.count) individual tester(s) from build '\(buildId)'"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to remove individual testers")
        }
    }

    /// Lists individual beta testers assigned to a specific build
    /// - Returns: JSON array of individual testers with pagination
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func listIndividualTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        let limit: Int
        if let value = arguments["limit"] {
            guard let parsed = value.intValue, (1...200).contains(parsed) else {
                return MCPResult.error("'limit' must be an integer from 1 through 200")
            }
            limit = parsed
        } else {
            limit = 50
        }

        do {
            let endpoint = "/v1/builds/\(try ASCPathSegment.encode(buildId))/individualTesters"
            let queryParams = ["limit": String(limit)]
            let response: ASCBetaTestersResponse

            // Check for pagination URL
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(path: endpoint, query: queryParams),
                    as: ASCBetaTestersResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCBetaTestersResponse.self
                )
            }

            let testers = response.data.map { formatBetaTester($0) }

            var result: [String: Any] = [
                "success": true,
                "individualTesters": testers,
                "count": testers.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list individual testers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Sends TestFlight notification to all beta testers about a new build
    /// - Returns: JSON with success status and confirmation message
    /// - Throws: CallTool.Result with error if build_id missing or notification fails
    func sendBetaNotification(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let body: [String: Any] = [
                "data": [
                    "type": "buildBetaNotifications",
                    "relationships": [
                        "build": [
                            "data": [
                                "type": "builds",
                                "id": buildId
                            ]
                        ]
                    ]
                ]
            ]

            let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
            _ = try await httpClient.post(
                "/v1/buildBetaNotifications",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Beta notification sent to all testers for build \(buildId)"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to send beta notification")
        }
    }

    private func applyBetaGroupStringList(_ value: Value?, as appleName: String, to query: inout [String: String]) {
        if let string = value?.stringValue, !string.isEmpty {
            query[appleName] = string
            return
        }
        guard let values = value?.arrayValue, !values.isEmpty else {
            return
        }
        let strings = values.compactMap(\.stringValue).filter { !$0.isEmpty }
        guard strings.count == values.count else {
            return
        }
        query[appleName] = strings.joined(separator: ",")
    }
}
