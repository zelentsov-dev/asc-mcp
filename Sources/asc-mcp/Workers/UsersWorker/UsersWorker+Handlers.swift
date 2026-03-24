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

            if let nextUrl = arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCUsersResponse.self)
            } else {
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list users: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'user_id' is missing")],
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
                "/v1/users/\(userId)",
                parameters: queryParams,
                as: ASCUserResponse.self
            )

            let user = formatUser(response.data)

            let result = [
                "success": true,
                "user": user
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get user: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates user roles
    /// - Returns: JSON with updated user details
    func updateUser(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let userIdValue = arguments["user_id"],
              let userId = userIdValue.stringValue,
              let rolesValue = arguments["roles"],
              let rolesArray = rolesValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Required parameters: user_id, roles")],
                isError: true
            )
        }

        let roles = rolesArray.compactMap { $0.stringValue }
        guard !roles.isEmpty else {
            return CallTool.Result(
                content: [.text("'roles' must contain at least one role")],
                isError: true
            )
        }

        do {
            let request = UpdateUserRequest(
                data: UpdateUserRequest.UpdateUserData(
                    id: userId,
                    attributes: UpdateUserRequest.UpdateUserAttributes(
                        roles: roles,
                        allAppsVisible: nil
                    )
                )
            )

            let response: ASCUserResponse = try await httpClient.patch(
                "/v1/users/\(userId)",
                body: request,
                as: ASCUserResponse.self
            )

            let user = formatUser(response.data)

            let result = [
                "success": true,
                "user": user
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to update user: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'user_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/users/\(userId)")

            let result = [
                "success": true,
                "message": "User '\(userId)' removed from team"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to remove user: \(error.localizedDescription)")],
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
                content: [.text("Required parameters: email, first_name, last_name, roles")],
                isError: true
            )
        }

        let roles = rolesArray.compactMap { $0.stringValue }
        guard !roles.isEmpty else {
            return CallTool.Result(
                content: [.text("'roles' must contain at least one role")],
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to invite user: \(error.localizedDescription)")],
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

            if let nextUrl = arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCUserInvitationsResponse.self)
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list invitations: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'invitation_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/userInvitations/\(invitationId)")

            let result = [
                "success": true,
                "message": "Invitation '\(invitationId)' cancelled"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to cancel invitation: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'user_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
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
                    "/v1/users/\(userId)/visibleApps",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list visible apps: \(error.localizedDescription)")],
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
                content: [.text("Required parameters: user_id, app_ids")],
                isError: true
            )
        }

        let appIds = appIdsArray.compactMap { $0.stringValue }
        guard !appIds.isEmpty else {
            return CallTool.Result(
                content: [.text("'app_ids' must contain at least one app ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: appIds.map { ASCResourceIdentifier(type: "apps", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/users/\(userId)/relationships/visibleApps",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Added \(appIds.count) app(s) to user '\(userId)' visible apps"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to add visible apps: \(error.localizedDescription)")],
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
                content: [.text("Required parameters: user_id, app_ids")],
                isError: true
            )
        }

        let appIds = appIdsArray.compactMap { $0.stringValue }
        guard !appIds.isEmpty else {
            return CallTool.Result(
                content: [.text("'app_ids' must contain at least one app ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: appIds.map { ASCResourceIdentifier(type: "apps", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/users/\(userId)/relationships/visibleApps",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Removed \(appIds.count) app(s) from user '\(userId)' visible apps"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to remove visible apps: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatUser(_ user: ASCUser) -> [String: Any] {
        return [
            "id": user.id,
            "type": user.type,
            "username": user.attributes?.username.jsonSafe ?? NSNull(),
            "firstName": user.attributes?.firstName.jsonSafe ?? NSNull(),
            "lastName": user.attributes?.lastName.jsonSafe ?? NSNull(),
            "roles": user.attributes?.roles.jsonSafe ?? NSNull(),
            "allAppsVisible": user.attributes?.allAppsVisible.jsonSafe ?? NSNull(),
            "provisioningAllowed": user.attributes?.provisioningAllowed.jsonSafe ?? NSNull(),
            "expirationDate": user.attributes?.expirationDate.jsonSafe ?? NSNull()
        ]
    }

    private func formatApp(_ app: ASCApp) -> [String: Any] {
        return [
            "id": app.id,
            "type": app.type,
            "name": app.attributes?.name.jsonSafe ?? NSNull(),
            "bundleId": app.attributes?.bundleId.jsonSafe ?? NSNull(),
            "sku": app.attributes?.sku.jsonSafe ?? NSNull(),
            "primaryLocale": app.attributes?.primaryLocale.jsonSafe ?? NSNull()
        ]
    }

    private func formatInvitation(_ invitation: ASCUserInvitation) -> [String: Any] {
        return [
            "id": invitation.id,
            "type": invitation.type,
            "email": invitation.attributes?.email.jsonSafe ?? NSNull(),
            "firstName": invitation.attributes?.firstName.jsonSafe ?? NSNull(),
            "lastName": invitation.attributes?.lastName.jsonSafe ?? NSNull(),
            "roles": invitation.attributes?.roles.jsonSafe ?? NSNull(),
            "allAppsVisible": invitation.attributes?.allAppsVisible.jsonSafe ?? NSNull(),
            "expirationDate": invitation.attributes?.expirationDate.jsonSafe ?? NSNull()
        ]
    }
}
