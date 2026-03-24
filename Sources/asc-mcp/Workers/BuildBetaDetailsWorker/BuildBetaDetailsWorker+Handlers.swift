import Foundation
import MCP

// MARK: - Tool Handlers
extension BuildBetaDetailsWorker {
    
    /// Gets TestFlight beta details for a specific build
    /// - Returns: JSON with beta detail including auto-notify settings and build states
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func getBetaDetail(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }
        
        do {
            // First get build to find beta detail relationship
            let buildResponse: ASCBuildResponse = try await httpClient.get(
                "/v1/builds/\(buildId)",
                parameters: ["include": "buildBetaDetail"],
                as: ASCBuildResponse.self
            )
            
            guard let betaDetailId = buildResponse.data.relationships?.buildBetaDetail?.data?.id else {
                return CallTool.Result(
                    content: [.text("Error: No beta detail found for this build")],
                    isError: true
                )
            }
            
            // Get full beta detail (only "build" is a valid include value)
            let response: ASCBuildBetaDetailResponse = try await httpClient.get(
                "/v1/buildBetaDetails/\(betaDetailId)",
                parameters: ["include": "build"],
                as: ASCBuildBetaDetailResponse.self
            )

            let betaDetailInfo = formatBetaDetail(response.data)

            let result = [
                "success": true,
                "betaDetail": betaDetailInfo,
                "note": "Use builds_list_beta_localizations to get localizations for this build"
            ] as [String: Any]
            
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get beta detail: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'beta_detail_id' is missing")],
                isError: true
            )
        }
        
        do {
            var attributes: [String: Any] = [:]
            
            if let autoNotifyValue = arguments["auto_notify"],
               let autoNotify = autoNotifyValue.boolValue {
                attributes["autoNotifyEnabled"] = autoNotify
            }
            
            if let internalStateValue = arguments["internal_build_state"],
               let internalState = internalStateValue.stringValue {
                attributes["internalBuildState"] = internalState
            }
            
            if let externalStateValue = arguments["external_build_state"],
               let externalState = externalStateValue.stringValue {
                attributes["externalBuildState"] = externalState
            }
            
            if attributes.isEmpty {
                return CallTool.Result(
                    content: [.text("Warning: No updates provided")],
                    isError: false
                )
            }
            
            let body = [
                "data": [
                    "type": "buildBetaDetails",
                    "id": betaDetailId,
                    "attributes": attributes
                ]
            ] as [String: Any]
            
            let updateRequest = UpdateBuildBetaDetailRequest(
                data: UpdateBuildBetaDetailRequest.UpdateBuildBetaDetailData(
                    id: betaDetailId,
                    attributes: UpdateBuildBetaDetailRequest.BuildBetaDetailUpdateAttributes(
                        autoNotifyEnabled: attributes["autoNotifyEnabled"] as? Bool,
                        internalBuildState: attributes["internalBuildState"] as? String,
                        externalBuildState: attributes["externalBuildState"] as? String
                    )
                )
            )
            
            let response: ASCBuildBetaDetailResponse = try await httpClient.patch(
                "/v1/buildBetaDetails/\(betaDetailId)",
                body: updateRequest,
                as: ASCBuildBetaDetailResponse.self
            )
            
            let betaDetail = formatBetaDetail(response.data)
            
            let result = [
                "success": true,
                "betaDetail": betaDetail
            ] as [String: Any]
            
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update beta detail: \(error.localizedDescription)")],
                isError: true
            )
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
            return CallTool.Result(
                content: [.text("Error: Required parameters 'build_id' and 'locale' are missing")],
                isError: true
            )
        }
        
        do {
            // Check if localization exists - get all and filter locally
            let existingResponse: ASCBetaBuildLocalizationsResponse = try await httpClient.get(
                "/v1/builds/\(buildId)/betaBuildLocalizations",
                parameters: [:],
                as: ASCBetaBuildLocalizationsResponse.self
            )
            
            // Filter by locale locally
            let existingData = existingResponse.data.filter { $0.attributes.locale == locale }
            
            if existingData.isEmpty {
                // Create new localization
                let createRequest = CreateBetaBuildLocalizationRequest(
                    data: CreateBetaBuildLocalizationRequest.CreateBetaBuildLocalizationData(
                        attributes: BetaBuildLocalizationAttributes(
                            locale: locale,
                            whatsNew: arguments["whats_new"]?.stringValue,
                            feedbackEmail: arguments["feedback_email"]?.stringValue,
                            marketingUrl: arguments["marketing_url"]?.stringValue,
                            privacyPolicyUrl: arguments["privacy_policy_url"]?.stringValue,
                            tvOsPrivacyPolicy: arguments["tv_os_privacy_policy"]?.stringValue
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
                
                return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
                
            } else {
                // Update existing localization
                guard let localizationData = existingData.first else {
                    return CallTool.Result(
                        content: [.text("Error: Failed to get localization")],
                        isError: true
                    )
                }
                
                let localizationId = localizationData.id
                
                let updateAttributes = UpdateBetaBuildLocalizationRequest.BetaBuildLocalizationUpdateAttributes(
                    whatsNew: arguments["whats_new"]?.stringValue,
                    feedbackEmail: arguments["feedback_email"]?.stringValue,
                    marketingUrl: arguments["marketing_url"]?.stringValue,
                    privacyPolicyUrl: arguments["privacy_policy_url"]?.stringValue,
                    tvOsPrivacyPolicy: arguments["tv_os_privacy_policy"]?.stringValue
                )
                
                // Check if any attributes were provided
                let hasUpdates = updateAttributes.whatsNew != nil ||
                                updateAttributes.feedbackEmail != nil ||
                                updateAttributes.marketingUrl != nil ||
                                updateAttributes.privacyPolicyUrl != nil ||
                                updateAttributes.tvOsPrivacyPolicy != nil
                
                if !hasUpdates {
                    return CallTool.Result(
                        content: [.text("Warning: No updates provided")],
                        isError: false
                    )
                }
                
                let updateRequest = UpdateBetaBuildLocalizationRequest(
                    data: UpdateBetaBuildLocalizationRequest.UpdateBetaBuildLocalizationData(
                        id: localizationId,
                        attributes: updateAttributes
                    )
                )
                
                let response: ASCBetaBuildLocalizationResponse = try await httpClient.patch(
                    "/v1/betaBuildLocalizations/\(localizationId)",
                    body: updateRequest,
                    as: ASCBetaBuildLocalizationResponse.self
                )
                
                let localization = formatBetaBuildLocalization(response.data)
                
                let result = [
                    "success": true,
                    "action": "updated",
                    "localization": localization
                ] as [String: Any]
                
                return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            }
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to set beta localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Lists all TestFlight localizations for a build
    /// - Returns: JSON array of localizations with What's New text and URLs
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func listBetaLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaBuildLocalizationsResponse

            // Check for pagination URL
            if let nextUrlValue = arguments["next_url"],
               let nextUrl = nextUrlValue.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBetaBuildLocalizationsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "50"
                }

                response = try await httpClient.get(
                    "/v1/builds/\(buildId)/betaBuildLocalizations",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list beta localizations: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaGroupsResponse

            // Check for pagination URL
            if let nextUrlValue = arguments["next_url"],
               let nextUrl = nextUrlValue.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBetaGroupsResponse.self)
            } else {
                var queryParams: [String: String] = [
                    "filter[builds]": buildId
                ]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "50"
                }

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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get beta groups: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaTestersResponse

            // Check for pagination URL
            if let nextUrlValue = arguments["next_url"],
               let nextUrl = nextUrlValue.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBetaTestersResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "50"
                }

                response = try await httpClient.get(
                    "/v1/builds/\(buildId)/individualTesters",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get beta testers: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameters 'build_id' and 'group_ids' are missing")],
                isError: true
            )
        }

        let groupIds = groupIdsArray.compactMap { $0.stringValue }
        guard !groupIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Error: 'group_ids' must contain at least one group ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: groupIds.map { ASCResourceIdentifier(type: "betaGroups", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/builds/\(buildId)/relationships/betaGroups",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Added build '\(buildId)' to \(groupIds.count) beta group(s)"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to add build to beta groups: \(error.localizedDescription)")],
                isError: true
            )
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
                content: [.text("Error: Required parameters 'build_id' and 'beta_tester_ids' are missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }
        guard !testerIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Error: 'beta_tester_ids' must contain at least one tester ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: testerIds.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/builds/\(buildId)/relationships/individualTesters",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Added \(testerIds.count) individual tester(s) to build '\(buildId)'"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to add individual testers: \(error.localizedDescription)")],
                isError: true
            )
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
                content: [.text("Error: Required parameters 'build_id' and 'beta_tester_ids' are missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }
        guard !testerIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Error: 'beta_tester_ids' must contain at least one tester ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: testerIds.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/builds/\(buildId)/relationships/individualTesters",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Removed \(testerIds.count) individual tester(s) from build '\(buildId)'"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to remove individual testers: \(error.localizedDescription)")],
                isError: true
            )
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
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaTestersResponse

            // Check for pagination URL
            if let nextUrlValue = arguments["next_url"],
               let nextUrl = nextUrlValue.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBetaTestersResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "50"
                }

                response = try await httpClient.get(
                    "/v1/builds/\(buildId)/individualTesters",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list individual testers: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let body: [String: Any] = [
                "data": [
                    "type": "betaBuildNotifications",
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
                "/v1/betaBuildNotifications",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Beta notification sent to all testers for build \(buildId)"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to send beta notification: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
}
