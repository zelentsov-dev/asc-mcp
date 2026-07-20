import Foundation
import MCP

// MARK: - Tool Handlers
extension UsersWorker {

    /// Lists team members
    /// - Returns: JSON array of users with attributes
    func listUsers(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCUsersResponse
            var queryParams: [String: String] = [:]

            if let limitValue = arguments?["limit"],
               let limit = limitValue.intValue {
                queryParams["limit"] = String(min(max(limit, 1), 200))
            } else {
                queryParams["limit"] = "25"
            }

            if let rolesValue = arguments?["filter_roles"],
               let roles = rolesValue.stringValue {
                queryParams["filter[roles]"] = roles
            }

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                var requiredParameters = queryParams
                requiredParameters.removeValue(forKey: "limit")
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: "/v1/users",
                        requiredParameters: requiredParameters
                    ),
                    as: ASCUsersResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/users",
                    parameters: queryParams,
                    as: ASCUsersResponse.self
                )
            }

            let users = response.data.map { formatUser($0) }

            var result: [String: Any] = [
                "success": true,
                "users": users,
                "count": users.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list users: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a team member
    /// - Returns: JSON with user details
    func getUser(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["user_id"],
              let userId = idValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'user_id' is missing")],
                isError: true
            )
        }

        do {
            var queryParams: [String: String] = [:]

            if let includeValue = arguments["include"],
               let include = includeValue.stringValue {
                queryParams["include"] = include
            }

            let response: ASCUserResponse = try await httpClient.get(
                "/v1/users/\(try ASCPathSegment.encode(userId))",
                parameters: queryParams,
                as: ASCUserResponse.self
            )

            let user = formatUser(response.data)

            let result = [
                "success": true,
                "user": user
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get user: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates user roles, app visibility, or provisioning access
    /// - Returns: JSON with updated user details
    func updateUser(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let userIdValue = arguments["user_id"],
              let userId = userIdValue.stringValue else {
            return MCPResult.error("Required parameter 'user_id' is missing")
        }

        let roles: [String]?
        if let rolesValue = arguments["roles"] {
            guard let rolesArray = rolesValue.arrayValue else {
                return MCPResult.error("'roles' must be an array of strings")
            }
            let parsedRoles = rolesArray.compactMap(\.stringValue)
            guard parsedRoles.count == rolesArray.count, !parsedRoles.isEmpty else {
                return MCPResult.error("'roles' must contain at least one string role")
            }
            guard Set(parsedRoles).count == parsedRoles.count else {
                return MCPResult.error("'roles' must not contain duplicate values")
            }
            let invalidRoles = parsedRoles.filter { !UsersWorker.assignableRoles.contains($0) }
            guard invalidRoles.isEmpty else {
                return MCPResult.error(
                    "Unsupported role(s): \(invalidRoles.joined(separator: ", ")). Valid roles: \(UsersWorker.assignableRoles.joined(separator: ", "))"
                )
            }
            roles = parsedRoles
        } else {
            roles = nil
        }

        let allAppsVisible: Bool?
        if let value = arguments["all_apps_visible"] {
            guard let parsed = value.boolValue else {
                return MCPResult.error("'all_apps_visible' must be a boolean")
            }
            allAppsVisible = parsed
        } else {
            allAppsVisible = nil
        }

        let provisioningAllowed: Bool?
        if let value = arguments["provisioning_allowed"] {
            guard let parsed = value.boolValue else {
                return MCPResult.error("'provisioning_allowed' must be a boolean")
            }
            provisioningAllowed = parsed
        } else {
            provisioningAllowed = nil
        }

        let visibleAppIds: [String]?
        if let value = arguments["visible_app_ids"] {
            guard let array = value.arrayValue else {
                return MCPResult.error("'visible_app_ids' must be an array of strings")
            }
            let parsed = array.compactMap(\.stringValue)
            guard parsed.count == array.count, parsed.allSatisfy({ !$0.isEmpty }) else {
                return MCPResult.error("'visible_app_ids' must contain only non-empty string IDs")
            }
            guard Set(parsed).count == parsed.count else {
                return MCPResult.error("'visible_app_ids' must not contain duplicate values")
            }
            visibleAppIds = parsed
        } else {
            visibleAppIds = nil
        }

        guard roles != nil || allAppsVisible != nil || provisioningAllowed != nil || visibleAppIds != nil else {
            return MCPResult.error(
                "Provide at least one update field: roles, all_apps_visible, provisioning_allowed, or visible_app_ids"
            )
        }

        do {
            let relationships = visibleAppIds.map { ids in
                UpdateUserRequest.UpdateUserRelationships(
                    visibleApps: UpdateUserRequest.VisibleAppsRelationship(
                        data: ids.map { ASCResourceIdentifier(type: "apps", id: $0) }
                    )
                )
            }
            let request = UpdateUserRequest(
                data: UpdateUserRequest.UpdateUserData(
                    id: userId,
                    attributes: UpdateUserRequest.UpdateUserAttributes(
                        roles: roles,
                        allAppsVisible: allAppsVisible,
                        provisioningAllowed: provisioningAllowed
                    ),
                    relationships: relationships
                )
            )

            let response: ASCUserResponse = try await httpClient.patch(
                "/v1/users/\(try ASCPathSegment.encode(userId))",
                body: request,
                as: ASCUserResponse.self
            )

            let user = formatUser(response.data)

            var result = [
                "success": true,
                "user": user
            ] as [String: Any]
            if let roles,
               !UsersWorker.deprecatedRoles.isDisjoint(with: roles) {
                result["warnings"] = [
                    "ACCESS_TO_REPORTS is deprecated by Apple and remains accepted only for backward compatibility."
                ]
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to update user: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Removes a user from the team
    /// - Returns: JSON confirmation
    func removeUser(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["user_id"],
              let userId = idValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'user_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/users/\(try ASCPathSegment.encode(userId))")

            let result = [
                "success": true,
                "message": "User '\(userId)' removed from team"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to remove user: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Invites a new user to the team
    /// - Returns: JSON with invitation details
    func inviteUser(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let emailValue = arguments["email"],
              let email = emailValue.stringValue,
              let firstNameValue = arguments["first_name"],
              let firstName = firstNameValue.stringValue,
              let lastNameValue = arguments["last_name"],
              let lastName = lastNameValue.stringValue,
              let rolesValue = arguments["roles"],
              let rolesArray = rolesValue.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: email, first_name, last_name, roles")],
                isError: true
            )
        }

        let roles = rolesArray.compactMap { $0.stringValue }
        guard !roles.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("'roles' must contain at least one role")],
                isError: true
            )
        }

        do {
            let allAppsVisible = arguments["all_apps_visible"]?.boolValue ?? true

            var relationships: CreateUserInvitationRequest.CreateUserInvitationRelationships? = nil

            if let visibleAppIdsValue = arguments["visible_app_ids"],
               let visibleAppIdsArray = visibleAppIdsValue.arrayValue {
                let appIds = visibleAppIdsArray.compactMap { $0.stringValue }
                if !appIds.isEmpty {
                    relationships = CreateUserInvitationRequest.CreateUserInvitationRelationships(
                        visibleApps: CreateUserInvitationRequest.VisibleAppsRelationship(
                            data: appIds.map { ASCResourceIdentifier(type: "apps", id: $0) }
                        )
                    )
                }
            }

            let request = CreateUserInvitationRequest(
                data: CreateUserInvitationRequest.CreateUserInvitationData(
                    attributes: CreateUserInvitationRequest.CreateUserInvitationAttributes(
                        email: email,
                        firstName: firstName,
                        lastName: lastName,
                        roles: roles,
                        allAppsVisible: allAppsVisible,
                        provisioningAllowed: nil
                    ),
                    relationships: relationships
                )
            )

            let response: ASCUserInvitationResponse = try await httpClient.post(
                "/v1/userInvitations",
                body: request,
                as: ASCUserInvitationResponse.self
            )

            let invitation = formatInvitation(response.data)

            let result = [
                "success": true,
                "invitation": invitation
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to invite user: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists pending user invitations
    /// - Returns: JSON array of invitations with attributes
    func listInvitations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCUserInvitationsResponse

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/userInvitations"),
                    as: ASCUserInvitationsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments?["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/userInvitations",
                    parameters: queryParams,
                    as: ASCUserInvitationsResponse.self
                )
            }

            let invitations = response.data.map { formatInvitation($0) }

            var result: [String: Any] = [
                "success": true,
                "invitations": invitations,
                "count": invitations.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list invitations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Cancels a pending user invitation
    /// - Returns: JSON confirmation of cancellation
    func cancelInvitation(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["invitation_id"],
              let invitationId = idValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'invitation_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/userInvitations/\(try ASCPathSegment.encode(invitationId))")

            let result = [
                "success": true,
                "message": "Invitation '\(invitationId)' cancelled"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to cancel invitation: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists apps visible to a specific user
    /// - Returns: JSON array of app objects with pagination
    func listVisibleApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["user_id"],
              let userId = idValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'user_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/users/\(try ASCPathSegment.encode(userId))/visibleApps"),
                    as: ASCAppsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/users/\(try ASCPathSegment.encode(userId))/visibleApps",
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
            if let next = response.links.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list visible apps: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Grants user access to specific apps
    /// - Returns: JSON confirmation
    func addVisibleApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["user_id"],
              let userId = idValue.stringValue,
              let appIdsValue = arguments["app_ids"],
              let appIdsArray = appIdsValue.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: user_id, app_ids")],
                isError: true
            )
        }

        let appIds = appIdsArray.compactMap { $0.stringValue }
        guard !appIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("'app_ids' must contain at least one app ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: appIds.map { ASCResourceIdentifier(type: "apps", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/users/\(try ASCPathSegment.encode(userId))/relationships/visibleApps",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Added \(appIds.count) app(s) to user '\(userId)' visible apps"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to add visible apps: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Removes user's access to specific apps
    /// - Returns: JSON confirmation
    func removeVisibleApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["user_id"],
              let userId = idValue.stringValue,
              let appIdsValue = arguments["app_ids"],
              let appIdsArray = appIdsValue.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: user_id, app_ids")],
                isError: true
            )
        }

        let appIds = appIdsArray.compactMap { $0.stringValue }
        guard !appIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("'app_ids' must contain at least one app ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: appIds.map { ASCResourceIdentifier(type: "apps", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/users/\(try ASCPathSegment.encode(userId))/relationships/visibleApps",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Removed \(appIds.count) app(s) from user '\(userId)' visible apps"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to remove visible apps: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatUser(_ user: ASCUser) -> [String: Any] {
        return [
            "id": user.id,
            "type": user.type,
            "username": (user.attributes?.username).jsonSafe,
            "firstName": (user.attributes?.firstName).jsonSafe,
            "lastName": (user.attributes?.lastName).jsonSafe,
            "roles": (user.attributes?.roles).jsonSafe,
            "allAppsVisible": (user.attributes?.allAppsVisible).jsonSafe,
            "provisioningAllowed": (user.attributes?.provisioningAllowed).jsonSafe,
            "expirationDate": (user.attributes?.expirationDate).jsonSafe
        ]
    }

    private func formatApp(_ app: ASCApp) -> [String: Any] {
        return [
            "id": app.id,
            "type": app.type,
            "name": (app.attributes?.name).jsonSafe,
            "bundleId": (app.attributes?.bundleId).jsonSafe,
            "sku": (app.attributes?.sku).jsonSafe,
            "primaryLocale": (app.attributes?.primaryLocale).jsonSafe
        ]
    }

    private func formatInvitation(_ invitation: ASCUserInvitation) -> [String: Any] {
        return [
            "id": invitation.id,
            "type": invitation.type,
            "email": (invitation.attributes?.email).jsonSafe,
            "firstName": (invitation.attributes?.firstName).jsonSafe,
            "lastName": (invitation.attributes?.lastName).jsonSafe,
            "roles": (invitation.attributes?.roles).jsonSafe,
            "allAppsVisible": (invitation.attributes?.allAppsVisible).jsonSafe,
            "expirationDate": (invitation.attributes?.expirationDate).jsonSafe
        ]
    }
}
