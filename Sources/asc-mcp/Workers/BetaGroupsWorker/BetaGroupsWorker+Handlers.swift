import Foundation
import MCP

// MARK: - Tool Handlers
extension BetaGroupsWorker {

    /// Lists beta groups for an app
    /// - Returns: JSON array of beta groups with attributes
    func listBetaGroups(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
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
                    "filter[app]": appId
                ]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                if let isInternalValue = arguments["is_internal"],
                   let isInternal = isInternalValue.boolValue {
                    queryParams["filter[isInternalGroup]"] = isInternal ? "true" : "false"
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
                "beta_groups": groups,
                "count": groups.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list beta groups: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new beta group
    /// - Returns: JSON with created beta group details
    func createBetaGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let nameValue = arguments["name"],
              let name = nameValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters 'app_id' and 'name' are missing")],
                isError: true
            )
        }

        do {
            let isInternalGroup = arguments["is_internal_group"]?.boolValue ?? false
            let hasAccessToAllBuilds = arguments["has_access_to_all_builds"]?.boolValue ?? false
            let publicLinkEnabled = arguments["public_link_enabled"]?.boolValue ?? false
            let feedbackEnabled = arguments["feedback_enabled"]?.boolValue ?? false

            let request = CreateBetaGroupRequest(
                data: CreateBetaGroupRequest.CreateBetaGroupData(
                    attributes: CreateBetaGroupRequest.CreateBetaGroupAttributes(
                        name: name,
                        isInternalGroup: isInternalGroup,
                        hasAccessToAllBuilds: hasAccessToAllBuilds,
                        publicLinkEnabled: publicLinkEnabled,
                        feedbackEnabled: feedbackEnabled
                    ),
                    relationships: CreateBetaGroupRequest.CreateBetaGroupRelationships(
                        app: CreateBetaGroupRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        )
                    )
                )
            )

            let response: ASCBetaGroupResponse = try await httpClient.post(
                "/v1/betaGroups",
                body: request,
                as: ASCBetaGroupResponse.self
            )

            let group = formatBetaGroup(response.data)

            let result = [
                "success": true,
                "beta_group": group
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create beta group: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a beta group's settings
    /// - Returns: JSON with updated beta group details
    func updateBetaGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupIdValue = arguments["group_id"],
              let groupId = groupIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'group_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateBetaGroupRequest(
                data: UpdateBetaGroupRequest.UpdateBetaGroupData(
                    id: groupId,
                    attributes: UpdateBetaGroupRequest.UpdateBetaGroupAttributes(
                        name: arguments["name"]?.stringValue,
                        publicLinkEnabled: arguments["public_link_enabled"]?.boolValue,
                        publicLinkLimit: arguments["public_link_limit"]?.intValue,
                        feedbackEnabled: arguments["feedback_enabled"]?.boolValue
                    )
                )
            )

            let response: ASCBetaGroupResponse = try await httpClient.patch(
                "/v1/betaGroups/\(groupId)",
                body: request,
                as: ASCBetaGroupResponse.self
            )

            let group = formatBetaGroup(response.data)

            let result = [
                "success": true,
                "beta_group": group
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update beta group: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a beta group
    /// - Returns: JSON confirmation of deletion
    func deleteBetaGroup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupIdValue = arguments["group_id"],
              let groupId = groupIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'group_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/betaGroups/\(groupId)")

            let result = [
                "success": true,
                "message": "Beta group '\(groupId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete beta group: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Adds testers to a beta group
    /// - Returns: JSON confirmation
    func addTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupIdValue = arguments["group_id"],
              let groupId = groupIdValue.stringValue,
              let testerIdsValue = arguments["tester_ids"],
              let testerIdsArray = testerIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters 'group_id' and 'tester_ids' are missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }
        guard !testerIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Error: 'tester_ids' must contain at least one tester ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: testerIds.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/betaGroups/\(groupId)/relationships/betaTesters",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Added \(testerIds.count) tester(s) to group '\(groupId)'"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to add testers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Removes testers from a beta group
    /// - Returns: JSON confirmation
    func removeTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupIdValue = arguments["group_id"],
              let groupId = groupIdValue.stringValue,
              let testerIdsValue = arguments["tester_ids"],
              let testerIdsArray = testerIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters 'group_id' and 'tester_ids' are missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }
        guard !testerIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Error: 'tester_ids' must contain at least one tester ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: testerIds.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaGroups/\(groupId)/relationships/betaTesters",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Removed \(testerIds.count) tester(s) from group '\(groupId)'"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to remove testers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists testers in a beta group
    /// - Returns: JSON array of beta testers with attributes
    func listTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupIdValue = arguments["group_id"],
              let groupId = groupIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'group_id' is missing")],
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
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/betaGroups/\(groupId)/betaTesters",
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
                content: [.text("Error: Failed to list testers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Adds builds to a beta group
    /// - Returns: JSON confirmation
    func addBuilds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupIdValue = arguments["group_id"],
              let groupId = groupIdValue.stringValue,
              let buildIdsValue = arguments["build_ids"],
              let buildIdsArray = buildIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters 'group_id' and 'build_ids' are missing")],
                isError: true
            )
        }

        let buildIds = buildIdsArray.compactMap { $0.stringValue }
        guard !buildIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Error: 'build_ids' must contain at least one build ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: buildIds.map { ASCResourceIdentifier(type: "builds", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/betaGroups/\(groupId)/relationships/builds",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Added \(buildIds.count) build(s) to group '\(groupId)'"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to add builds: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Removes builds from a beta group
    /// - Returns: JSON confirmation
    func removeBuilds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let groupIdValue = arguments["group_id"],
              let groupId = groupIdValue.stringValue,
              let buildIdsValue = arguments["build_ids"],
              let buildIdsArray = buildIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters 'group_id' and 'build_ids' are missing")],
                isError: true
            )
        }

        let buildIds = buildIdsArray.compactMap { $0.stringValue }
        guard !buildIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Error: 'build_ids' must contain at least one build ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: buildIds.map { ASCResourceIdentifier(type: "builds", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaGroups/\(groupId)/relationships/builds",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Removed \(buildIds.count) build(s) from group '\(groupId)'"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to remove builds: \(error.localizedDescription)")],
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

    private func formatBetaGroup(_ group: ASCBetaGroup) -> [String: Any] {
        return [
            "id": group.id,
            "type": group.type,
            "name": group.attributes.name.jsonSafe,
            "createdDate": group.attributes.createdDate.jsonSafe,
            "isInternalGroup": group.attributes.isInternalGroup.jsonSafe,
            "hasAccessToAllBuilds": group.attributes.hasAccessToAllBuilds.jsonSafe,
            "publicLinkEnabled": group.attributes.publicLinkEnabled.jsonSafe,
            "publicLinkLimit": group.attributes.publicLinkLimit.jsonSafe,
            "publicLink": group.attributes.publicLink.jsonSafe,
            "feedbackEnabled": group.attributes.feedbackEnabled.jsonSafe
        ]
    }
}
