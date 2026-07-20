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
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaGroupsResponse
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
            applyStringList(arguments["name"], as: "filter[name]", to: &queryParams)
            applyStringList(arguments["build_ids"], as: "filter[builds]", to: &queryParams)
            applyStringList(arguments["group_ids"], as: "filter[id]", to: &queryParams)
            applyStringList(arguments["public_link"], as: "filter[publicLink]", to: &queryParams)
            if let enabled = arguments["public_link_enabled"]?.boolValue {
                queryParams["filter[publicLinkEnabled]"] = enabled ? "true" : "false"
            }
            if let enabled = arguments["public_link_limit_enabled"]?.boolValue {
                queryParams["filter[publicLinkLimitEnabled]"] = enabled ? "true" : "false"
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
                "beta_groups": groups,
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
                content: [MCPContent.text("Error: Failed to list beta groups: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters 'app_id' and 'name' are missing")],
                isError: true
            )
        }

        let buildIds: [String]?
        if let values = arguments["build_ids"]?.arrayValue {
            let ids = values.compactMap(\.stringValue).filter { !$0.isEmpty }
            guard !ids.isEmpty, ids.count == values.count else {
                return MCPResult.error("'build_ids' must contain only non-empty build IDs")
            }
            buildIds = ids
        } else {
            buildIds = nil
        }

        let testerIds: [String]?
        if let values = arguments["tester_ids"]?.arrayValue {
            let ids = values.compactMap(\.stringValue).filter { !$0.isEmpty }
            guard !ids.isEmpty, ids.count == values.count else {
                return MCPResult.error("'tester_ids' must contain only non-empty beta tester IDs")
            }
            testerIds = ids
        } else {
            testerIds = nil
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
                        publicLinkLimitEnabled: arguments["public_link_limit_enabled"]?.boolValue,
                        publicLinkLimit: arguments["public_link_limit"]?.intValue,
                        feedbackEnabled: feedbackEnabled
                    ),
                    relationships: CreateBetaGroupRequest.CreateBetaGroupRelationships(
                        app: CreateBetaGroupRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        ),
                        builds: buildIds.map {
                            CreateBetaGroupRequest.ResourceIdentifiersRelationship(
                                data: $0.map { ASCResourceIdentifier(type: "builds", id: $0) }
                            )
                        },
                        betaTesters: testerIds.map {
                            CreateBetaGroupRequest.ResourceIdentifiersRelationship(
                                data: $0.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
                            )
                        }
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create beta group: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'group_id' is missing")],
                isError: true
            )
        }

        let updatableFields = [
            "name",
            "public_link_enabled",
            "public_link_limit_enabled",
            "public_link_limit",
            "feedback_enabled",
            "ios_builds_available_for_apple_silicon_mac",
            "ios_builds_available_for_apple_vision"
        ]
        guard updatableFields.contains(where: { arguments[$0] != nil }) else {
            return MCPResult.error("At least one updatable beta group field is required")
        }

        do {
            let request = UpdateBetaGroupRequest(
                data: UpdateBetaGroupRequest.UpdateBetaGroupData(
                    id: groupId,
                    attributes: UpdateBetaGroupRequest.UpdateBetaGroupAttributes(
                        name: arguments["name"]?.stringValue,
                        publicLinkEnabled: arguments["public_link_enabled"]?.boolValue,
                        publicLinkLimitEnabled: arguments["public_link_limit_enabled"]?.boolValue,
                        publicLinkLimit: arguments["public_link_limit"]?.intValue,
                        feedbackEnabled: arguments["feedback_enabled"]?.boolValue,
                        iosBuildsAvailableForAppleSiliconMac: arguments["ios_builds_available_for_apple_silicon_mac"]?.boolValue,
                        iosBuildsAvailableForAppleVision: arguments["ios_builds_available_for_apple_vision"]?.boolValue
                    )
                )
            )

            let response: ASCBetaGroupResponse = try await httpClient.patch(
                "/v1/betaGroups/\(try ASCPathSegment.encode(groupId))",
                body: request,
                as: ASCBetaGroupResponse.self
            )

            let group = formatBetaGroup(response.data)

            let result = [
                "success": true,
                "beta_group": group
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update beta group: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'group_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/betaGroups/\(try ASCPathSegment.encode(groupId))")

            let result = [
                "success": true,
                "message": "Beta group '\(groupId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete beta group: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters 'group_id' and 'tester_ids' are missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }
        guard !testerIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Error: 'tester_ids' must contain at least one tester ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: testerIds.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/betaGroups/\(try ASCPathSegment.encode(groupId))/relationships/betaTesters",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Added \(testerIds.count) tester(s) to group '\(groupId)'"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to add testers: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters 'group_id' and 'tester_ids' are missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }
        guard !testerIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Error: 'tester_ids' must contain at least one tester ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: testerIds.map { ASCResourceIdentifier(type: "betaTesters", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaGroups/\(try ASCPathSegment.encode(groupId))/relationships/betaTesters",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Removed \(testerIds.count) tester(s) from group '\(groupId)'"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to remove testers: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'group_id' is missing")],
                isError: true
            )
        }

        do {
            let endpoint = "/v1/betaGroups/\(try ASCPathSegment.encode(groupId))/betaTesters"
            let limit = arguments["limit"]?.intValue ?? 25
            let queryParams = ["limit": String(min(max(limit, 1), 200))]
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
                "beta_testers": testers,
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
                content: [MCPContent.text("Error: Failed to list testers: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters 'group_id' and 'build_ids' are missing")],
                isError: true
            )
        }

        let buildIds = buildIdsArray.compactMap { $0.stringValue }
        guard !buildIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Error: 'build_ids' must contain at least one build ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: buildIds.map { ASCResourceIdentifier(type: "builds", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/betaGroups/\(try ASCPathSegment.encode(groupId))/relationships/builds",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Added \(buildIds.count) build(s) to group '\(groupId)'"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to add builds: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters 'group_id' and 'build_ids' are missing")],
                isError: true
            )
        }

        let buildIds = buildIdsArray.compactMap { $0.stringValue }
        guard !buildIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Error: 'build_ids' must contain at least one build ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: buildIds.map { ASCResourceIdentifier(type: "builds", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaGroups/\(try ASCPathSegment.encode(groupId))/relationships/builds",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Removed \(buildIds.count) build(s) from group '\(groupId)'"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to remove builds: \(error.localizedDescription)")],
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
            "publicLinkLimitEnabled": group.attributes.publicLinkLimitEnabled.jsonSafe,
            "publicLink": group.attributes.publicLink.jsonSafe,
            "publicLinkId": group.attributes.publicLinkId.jsonSafe,
            "feedbackEnabled": group.attributes.feedbackEnabled.jsonSafe,
            "iosBuildsAvailableForAppleSiliconMac": group.attributes.iosBuildsAvailableForAppleSiliconMac.jsonSafe,
            "iosBuildsAvailableForAppleVision": group.attributes.iosBuildsAvailableForAppleVision.jsonSafe,
            "relationships": formatBetaGroupRelationships(group.relationships)
        ]
    }

    private func formatBetaGroupRelationships(_ relationships: BetaGroupRelationships?) -> [String: Any] {
        guard let relationships else { return [:] }
        var result: [String: Any] = [:]
        if let app = relationships.app?.data {
            result["appId"] = app.id
        }
        if let builds = relationships.builds?.data {
            result["buildIds"] = builds.map(\.id)
        }
        if let testers = relationships.betaTesters?.data {
            result["betaTesterIds"] = testers.map(\.id)
        }
        if let criteria = relationships.betaRecruitmentCriteria?.data {
            result["betaRecruitmentCriteriaId"] = criteria.id
        }
        if let compatibilityURL = relationships.betaRecruitmentCriterionCompatibleBuildCheck?.links?.related {
            result["betaRecruitmentCriterionCompatibleBuildCheckURL"] = compatibilityURL
        }
        return result
    }

    private func applyStringList(_ value: Value?, as appleName: String, to query: inout [String: String]) {
        if let encoded = commaSeparatedStringList(value) {
            query[appleName] = encoded
        }
    }

    private func commaSeparatedStringList(_ value: Value?) -> String? {
        if let string = value?.stringValue, !string.isEmpty {
            return string
        }
        guard let values = value?.arrayValue, !values.isEmpty else {
            return nil
        }
        let strings = values.compactMap(\.stringValue).filter { !$0.isEmpty }
        guard strings.count == values.count else {
            return nil
        }
        return strings.joined(separator: ",")
    }
}
