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
