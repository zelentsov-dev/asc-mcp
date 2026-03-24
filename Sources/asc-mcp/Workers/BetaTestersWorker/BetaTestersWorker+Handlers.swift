import Foundation
import MCP

// MARK: - Tool Handlers
extension BetaTestersWorker {

    /// Lists beta testers, optionally filtered by app
    /// - Returns: JSON array of beta testers with attributes and pagination
    func listBetaTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]

        do {
            let response: ASCBetaTestersResponse

            // Check for pagination URL
            if let nextUrlValue = arguments["next_url"],
               let nextUrl = nextUrlValue.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBetaTestersResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let appIdValue = arguments["app_id"],
                   let appId = appIdValue.stringValue {
                    queryParams["filter[apps]"] = appId
                }

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/betaTesters",
                    parameters: queryParams,
                    as: ASCBetaTestersResponse.self
                )
            }

            let testers = response.data.map { formatBetaTester($0) }

            var result: [String: Any] = [
                "success": true,
                "beta_testers": testers,
                "count": testers.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list beta testers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Searches beta testers by email address
    /// - Returns: JSON array of matching beta testers
    func searchBetaTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let emailValue = arguments["email"],
              let email = emailValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'email' is missing")],
                isError: true
            )
        }

        do {
            var queryParams: [String: String] = [
                "filter[email]": email
            ]

            if let appIdValue = arguments["app_id"],
               let appId = appIdValue.stringValue {
                queryParams["filter[apps]"] = appId
            }

            let response: ASCBetaTestersResponse = try await httpClient.get(
                "/v1/betaTesters",
                parameters: queryParams,
                as: ASCBetaTestersResponse.self
            )

            let testers = response.data.map { formatBetaTester($0) }

            let result: [String: Any] = [
                "success": true,
                "beta_testers": testers,
                "count": testers.count
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to search beta testers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets detailed information about a specific beta tester
    /// - Returns: JSON with tester details and optionally included resources
    func getBetaTester(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let testerIdValue = arguments["tester_id"],
              let testerId = testerIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'tester_id' is missing")],
                isError: true
            )
        }

        do {
            var queryParams: [String: String] = [:]

            if let includeValue = arguments["include"],
               let include = includeValue.stringValue {
                queryParams["include"] = include
            }

            let response: ASCBetaTesterResponse = try await httpClient.get(
                "/v1/betaTesters/\(testerId)",
                parameters: queryParams,
                as: ASCBetaTesterResponse.self
            )

            var testerDict = formatBetaTester(response.data)

            // Add included resources if present
            if let included = response.included {
                var includedApps: [[String: Any]] = []
                var includedGroups: [[String: Any]] = []

                for resource in included {
                    switch resource {
                    case .app(let app):
                        includedApps.append([
                            "id": app.id,
                            "name": app.attributes?.name.jsonSafe ?? NSNull()
                        ])
                    case .betaGroup(let group):
                        includedGroups.append([
                            "id": group.id,
                            "name": group.attributes.name.jsonSafe
                        ])
                    }
                }

                if !includedApps.isEmpty {
                    testerDict["apps"] = includedApps
                }
                if !includedGroups.isEmpty {
                    testerDict["betaGroups"] = includedGroups
                }
            }

            let result: [String: Any] = [
                "success": true,
                "beta_tester": testerDict
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get beta tester: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates/invites a new beta tester and assigns to beta groups
    /// - Returns: JSON with created tester details
    func createBetaTester(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let emailValue = arguments["email"],
              let email = emailValue.stringValue,
              let groupIdsValue = arguments["group_ids"],
              let groupIdsArray = groupIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'email' and 'group_ids' are missing")],
                isError: true
            )
        }

        let groupIds = groupIdsArray.compactMap { $0.stringValue }
        guard !groupIds.isEmpty else {
            return CallTool.Result(
                content: [.text("'group_ids' must contain at least one beta group ID")],
                isError: true
            )
        }

        do {
            let firstName = arguments["first_name"]?.stringValue
            let lastName = arguments["last_name"]?.stringValue

            let request = CreateBetaTesterRequest(
                data: CreateBetaTesterRequest.CreateBetaTesterData(
                    attributes: CreateBetaTesterRequest.CreateBetaTesterAttributes(
                        email: email,
                        firstName: firstName,
                        lastName: lastName
                    ),
                    relationships: CreateBetaTesterRequest.CreateBetaTesterRelationships(
                        betaGroups: CreateBetaTesterRequest.BetaGroupsRelationship(
                            data: groupIds.map { ASCResourceIdentifier(type: "betaGroups", id: $0) }
                        ),
                        builds: nil
                    )
                )
            )

            let response: ASCBetaTesterResponse = try await httpClient.post(
                "/v1/betaTesters",
                body: request,
                as: ASCBetaTesterResponse.self
            )

            let tester = formatBetaTester(response.data)

            let result: [String: Any] = [
                "success": true,
                "beta_tester": tester
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create beta tester: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a beta tester and removes from all groups
    /// - Returns: JSON confirmation of deletion
    func deleteBetaTester(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let testerIdValue = arguments["tester_id"],
              let testerId = testerIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'tester_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/betaTesters/\(testerId)")

            let result: [String: Any] = [
                "success": true,
                "message": "Beta tester '\(testerId)' deleted"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to delete beta tester: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists apps that a beta tester has access to
    /// - Returns: JSON array of apps with pagination
    func listBetaTesterApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let testerIdValue = arguments["tester_id"],
              let testerId = testerIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'tester_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppsResponse

            // Check for pagination URL
            if let nextUrlValue = arguments["next_url"],
               let nextUrl = nextUrlValue.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAppsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/betaTesters/\(testerId)/apps",
                    parameters: queryParams,
                    as: ASCAppsResponse.self
                )
            }

            let apps = response.data.map { formatApp($0) }

            var result: [String: Any] = [
                "success": true,
                "apps": apps,
                "count": apps.count
            ]

            if let nextUrl = response.links.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list beta tester apps: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Sends or resends a TestFlight invitation to a beta tester
    /// - Returns: JSON confirmation of invitation sent
    func sendInvitation(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let betaTesterIdValue = arguments["beta_tester_id"],
              let betaTesterId = betaTesterIdValue.stringValue,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'beta_tester_id' and 'app_id' are missing")],
                isError: true
            )
        }

        do {
            let body: [String: Any] = [
                "data": [
                    "type": "betaTesterInvitations",
                    "relationships": [
                        "betaTester": [
                            "data": [
                                "type": "betaTesters",
                                "id": betaTesterId
                            ]
                        ],
                        "app": [
                            "data": [
                                "type": "apps",
                                "id": appId
                            ]
                        ]
                    ]
                ]
            ]

            let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
            _ = try await httpClient.post(
                "/v1/betaTesterInvitations",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Invitation sent to beta tester '\(betaTesterId)' for app '\(appId)'"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to send invitation: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Adds a beta tester to one or more beta groups
    /// - Returns: JSON confirmation of the operation
    func addToGroups(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let betaTesterIdValue = arguments["beta_tester_id"],
              let betaTesterId = betaTesterIdValue.stringValue,
              let groupIdsValue = arguments["group_ids"],
              let groupIdsArray = groupIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'beta_tester_id' and 'group_ids' are missing")],
                isError: true
            )
        }

        let groupIds = groupIdsArray.compactMap { $0.stringValue }
        guard !groupIds.isEmpty else {
            return CallTool.Result(
                content: [.text("'group_ids' must contain at least one group ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: groupIds.map { ASCResourceIdentifier(type: "betaGroups", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/betaTesters/\(betaTesterId)/relationships/betaGroups",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Added tester '\(betaTesterId)' to \(groupIds.count) group(s)"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to add tester to groups: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Removes a beta tester from one or more beta groups
    /// - Returns: JSON confirmation of the operation
    func removeFromGroups(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let betaTesterIdValue = arguments["beta_tester_id"],
              let betaTesterId = betaTesterIdValue.stringValue,
              let groupIdsValue = arguments["group_ids"],
              let groupIdsArray = groupIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'beta_tester_id' and 'group_ids' are missing")],
                isError: true
            )
        }

        let groupIds = groupIdsArray.compactMap { $0.stringValue }
        guard !groupIds.isEmpty else {
            return CallTool.Result(
                content: [.text("'group_ids' must contain at least one group ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: groupIds.map { ASCResourceIdentifier(type: "betaGroups", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaTesters/\(betaTesterId)/relationships/betaGroups",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Removed tester '\(betaTesterId)' from \(groupIds.count) group(s)"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to remove tester from groups: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Assigns builds to a beta tester for individual testing
    /// - Returns: JSON confirmation of the operation
    func addToBuilds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let betaTesterIdValue = arguments["beta_tester_id"],
              let betaTesterId = betaTesterIdValue.stringValue,
              let buildIdsValue = arguments["build_ids"],
              let buildIdsArray = buildIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'beta_tester_id' and 'build_ids' are missing")],
                isError: true
            )
        }

        let buildIds = buildIdsArray.compactMap { $0.stringValue }
        guard !buildIds.isEmpty else {
            return CallTool.Result(
                content: [.text("'build_ids' must contain at least one build ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: buildIds.map { ASCResourceIdentifier(type: "builds", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/betaTesters/\(betaTesterId)/relationships/builds",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Added \(buildIds.count) build(s) to tester '\(betaTesterId)'"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to add builds to tester: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Removes build access from a beta tester
    /// - Returns: JSON confirmation of the operation
    func removeFromBuilds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let betaTesterIdValue = arguments["beta_tester_id"],
              let betaTesterId = betaTesterIdValue.stringValue,
              let buildIdsValue = arguments["build_ids"],
              let buildIdsArray = buildIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'beta_tester_id' and 'build_ids' are missing")],
                isError: true
            )
        }

        let buildIds = buildIdsArray.compactMap { $0.stringValue }
        guard !buildIds.isEmpty else {
            return CallTool.Result(
                content: [.text("'build_ids' must contain at least one build ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: buildIds.map { ASCResourceIdentifier(type: "builds", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaTesters/\(betaTesterId)/relationships/builds",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Removed \(buildIds.count) build(s) from tester '\(betaTesterId)'"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to remove builds from tester: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Removes a beta tester's access to an app entirely
    /// - Returns: JSON confirmation of the operation
    func removeFromApp(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let betaTesterIdValue = arguments["beta_tester_id"],
              let betaTesterId = betaTesterIdValue.stringValue,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'beta_tester_id' and 'app_id' are missing")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: [ASCResourceIdentifier(type: "apps", id: appId)]
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaTesters/\(betaTesterId)/relationships/apps",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Removed tester '\(betaTesterId)' from app '\(appId)'"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to remove tester from app: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatBetaTester(_ tester: ASCBetaTester) -> [String: Any] {
        return [
            "id": tester.id,
            "type": tester.type,
            "email": tester.attributes.email.jsonSafe,
            "firstName": tester.attributes.firstName.jsonSafe,
            "lastName": tester.attributes.lastName.jsonSafe,
            "inviteType": tester.attributes.inviteType.jsonSafe,
            "state": tester.attributes.state.jsonSafe
        ]
    }

    private func formatApp(_ app: ASCApp) -> [String: Any] {
        return [
            "id": app.id,
            "name": app.attributes?.name.jsonSafe ?? NSNull(),
            "bundleId": app.attributes?.bundleId.jsonSafe ?? NSNull()
        ]
    }
}
