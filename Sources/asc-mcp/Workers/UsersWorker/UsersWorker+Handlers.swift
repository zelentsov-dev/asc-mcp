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
            let limit = try boundedInteger(
                arguments?["limit"],
                name: "limit",
                range: 1...200,
                defaultValue: 25
            ) ?? 25
            var queryParams: [String: String] = [
                "limit": String(limit)
            ]
            queryParams["filter[username]"] = try commaSeparated(
                arguments?["filter_username"],
                name: "filter_username"
            )
            queryParams["filter[roles]"] = try commaSeparated(
                arguments?["filter_roles"],
                name: "filter_roles",
                allowedValues: Set(UsersWorker.assignableRoles)
            )
            queryParams["filter[visibleApps]"] = try commaSeparated(
                arguments?["filter_visible_apps"],
                name: "filter_visible_apps"
            )
            queryParams["sort"] = try commaSeparated(
                arguments?["sort"],
                name: "sort",
                allowedValues: Set(UsersWorker.userSortValues)
            )
            queryParams["include"] = try commaSeparated(
                arguments?["include"],
                name: "include",
                allowedValues: Set(UsersWorker.includeValues)
            )
            if let includedLimit = try boundedInteger(
                arguments?["limit_visible_apps"],
                name: "limit_visible_apps",
                range: 1...50
            ) {
                queryParams["limit[visibleApps]"] = String(includedLimit)
            }

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/users",
                        query: queryParams
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            appendIncluded(response.included, to: &result)

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
            queryParams["include"] = try commaSeparated(
                arguments["include"],
                name: "include",
                allowedValues: Set(UsersWorker.includeValues)
            )
            if let includedLimit = try boundedInteger(
                arguments["limit_visible_apps"],
                name: "limit_visible_apps",
                range: 1...50
            ) {
                queryParams["limit[visibleApps]"] = String(includedLimit)
            }

            let response: ASCUserResponse = try await httpClient.get(
                "/v1/users/\(try ASCPathSegment.encode(userId))",
                parameters: queryParams,
                as: ASCUserResponse.self
            )

            let user = formatUser(response.data)

            var result = [
                "success": true,
                "user": user
            ] as [String: Any]
            appendIncluded(response.included, to: &result)

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

        let roles: ASCNullable<[String]>?
        if let rolesValue = arguments["roles"] {
            if rolesValue.isNull {
                roles = .null
            } else {
                do {
                    roles = .value(try validatedStringArray(
                        rolesValue,
                        name: "roles",
                        allowEmpty: false,
                        allowedValues: Set(UsersWorker.assignableRoles)
                    ))
                } catch {
                    return MCPResult.error(error.localizedDescription)
                }
            }
        } else {
            roles = nil
        }

        let allAppsVisible: ASCNullable<Bool>?
        let provisioningAllowed: ASCNullable<Bool>?
        do {
            allAppsVisible = try nullableBool(
                arguments["all_apps_visible"],
                name: "all_apps_visible"
            )
            provisioningAllowed = try nullableBool(
                arguments["provisioning_allowed"],
                name: "provisioning_allowed"
            )
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        let visibleAppIds: [String]?
        if let value = arguments["visible_app_ids"] {
            do {
                visibleAppIds = try validatedStringArray(
                    value,
                    name: "visible_app_ids",
                    allowEmpty: true
                )
            } catch {
                return MCPResult.error(error.localizedDescription)
            }
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
                        nullableRoles: roles,
                        nullableAllAppsVisible: allAppsVisible,
                        nullableProvisioningAllowed: provisioningAllowed
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
            if case .value(let roleValues)? = roles,
               !UsersWorker.deprecatedRoles.isDisjoint(with: roleValues) {
                result["warnings"] = [
                    "ACCESS_TO_REPORTS is deprecated by Apple and remains accepted only for backward compatibility."
                ]
            }
            appendIncluded(response.included, to: &result)

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update user")
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
            return MCPResult.error(error, prefix: "Failed to remove user")
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
              let rolesValue = arguments["roles"] else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: email, first_name, last_name, roles")],
                isError: true
            )
        }
        guard isValidEmail(email) else {
            return MCPResult.error("'email' must be a valid email address")
        }

        let roles: [String]
        let allAppsVisible: ASCNullable<Bool>?
        let provisioningAllowed: ASCNullable<Bool>?
        let visibleAppIds: [String]?
        do {
            roles = try validatedStringArray(
                rolesValue,
                name: "roles",
                allowEmpty: false,
                allowedValues: Set(UsersWorker.assignableRoles)
            )
            allAppsVisible = try nullableBool(
                arguments["all_apps_visible"],
                name: "all_apps_visible"
            )
            provisioningAllowed = try nullableBool(
                arguments["provisioning_allowed"],
                name: "provisioning_allowed"
            )
            if let value = arguments["visible_app_ids"] {
                visibleAppIds = try validatedStringArray(
                    value,
                    name: "visible_app_ids",
                    allowEmpty: true
                )
            } else {
                visibleAppIds = nil
            }
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        do {
            let relationships = visibleAppIds.map { appIds in
                CreateUserInvitationRequest.CreateUserInvitationRelationships(
                    visibleApps: CreateUserInvitationRequest.VisibleAppsRelationship(
                        data: appIds.map { ASCResourceIdentifier(type: "apps", id: $0) }
                    )
                )
            }

            let request = CreateUserInvitationRequest(
                data: CreateUserInvitationRequest.CreateUserInvitationData(
                    attributes: CreateUserInvitationRequest.CreateUserInvitationAttributes(
                        email: email,
                        firstName: firstName,
                        lastName: lastName,
                        roles: roles,
                        nullableAllAppsVisible: allAppsVisible,
                        nullableProvisioningAllowed: provisioningAllowed
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

            var result = [
                "success": true,
                "invitation": invitation
            ] as [String: Any]
            if !UsersWorker.deprecatedRoles.isDisjoint(with: roles) {
                result["warnings"] = [
                    "ACCESS_TO_REPORTS is deprecated by Apple and remains accepted only for backward compatibility."
                ]
            }
            appendIncluded(response.included, to: &result)

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to invite user")
        }
    }

    /// Lists pending user invitations
    /// - Returns: JSON array of invitations with attributes
    func listInvitations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCUserInvitationsResponse
            let limit = try boundedInteger(
                arguments?["limit"],
                name: "limit",
                range: 1...200,
                defaultValue: 25
            ) ?? 25
            var queryParams: [String: String] = [
                "limit": String(limit)
            ]
            queryParams["filter[email]"] = try commaSeparated(
                arguments?["filter_email"],
                name: "filter_email"
            )
            queryParams["filter[roles]"] = try commaSeparated(
                arguments?["filter_roles"],
                name: "filter_roles",
                allowedValues: Set(UsersWorker.assignableRoles)
            )
            queryParams["filter[visibleApps]"] = try commaSeparated(
                arguments?["filter_visible_apps"],
                name: "filter_visible_apps"
            )
            queryParams["sort"] = try commaSeparated(
                arguments?["sort"],
                name: "sort",
                allowedValues: Set(UsersWorker.invitationSortValues)
            )
            queryParams["include"] = try commaSeparated(
                arguments?["include"],
                name: "include",
                allowedValues: Set(UsersWorker.includeValues)
            )
            if let includedLimit = try boundedInteger(
                arguments?["limit_visible_apps"],
                name: "limit_visible_apps",
                range: 1...50
            ) {
                queryParams["limit[visibleApps]"] = String(includedLimit)
            }

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/userInvitations",
                        query: queryParams
                    ),
                    as: ASCUserInvitationsResponse.self
                )
            } else {
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            appendIncluded(response.included, to: &result)

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
            return MCPResult.error(error, prefix: "Failed to cancel invitation")
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
            let endpoint = "/v1/users/\(try ASCPathSegment.encode(userId))/visibleApps"
            let limit = try boundedInteger(
                arguments["limit"],
                name: "limit",
                range: 1...200,
                defaultValue: 25
            ) ?? 25
            let queryParams = ["limit": String(limit)]
            let response: ASCAppsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(path: endpoint, query: queryParams),
                    as: ASCAppsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
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
            if let total = response.meta?.paging.total {
                result["total"] = total
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
              let appIdsValue = arguments["app_ids"] else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: user_id, app_ids")],
                isError: true
            )
        }

        let appIds: [String]
        do {
            appIds = try validatedStringArray(
                appIdsValue,
                name: "app_ids",
                allowEmpty: false
            )
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        let bodyData: Data
        do {
            let request = BetaGroupRelationshipRequest(
                data: appIds.map { ASCResourceIdentifier(type: "apps", id: $0) }
            )
            bodyData = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode visible apps relationship request")
        }

        do {
            _ = try await httpClient.post(
                "/v1/users/\(try ASCPathSegment.encode(userId))/relationships/visibleApps",
                body: bodyData,
                expectedStatusCode: 204
            )

            let result = [
                "success": true,
                "message": "Added \(appIds.count) app(s) to user '\(userId)' visible apps"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to add visible apps")
        }
    }

    /// Removes user's access to specific apps
    /// - Returns: JSON confirmation
    func removeVisibleApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["user_id"],
              let userId = idValue.stringValue,
              let appIdsValue = arguments["app_ids"] else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: user_id, app_ids")],
                isError: true
            )
        }

        let appIds: [String]
        do {
            appIds = try validatedStringArray(
                appIdsValue,
                name: "app_ids",
                allowEmpty: false
            )
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        let bodyData: Data
        do {
            let request = BetaGroupRelationshipRequest(
                data: appIds.map { ASCResourceIdentifier(type: "apps", id: $0) }
            )
            bodyData = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode visible apps relationship request")
        }

        do {
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
            return MCPResult.error(error, prefix: "Failed to remove visible apps")
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
            "visibleAppIds": (user.relationships?.visibleApps?.data?.map(\.id)).jsonSafe
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
            "provisioningAllowed": (invitation.attributes?.provisioningAllowed).jsonSafe,
            "expirationDate": (invitation.attributes?.expirationDate).jsonSafe,
            "visibleAppIds": (invitation.relationships?.visibleApps?.data?.map(\.id)).jsonSafe
        ]
    }

    private func appendIncluded(_ included: [JSONValue]?, to result: inout [String: Any]) {
        if let included, !included.isEmpty {
            result["included"] = included.map(\.asAny)
        }
    }

    private func boundedInteger(
        _ value: Value?,
        name: String,
        range: ClosedRange<Int>,
        defaultValue: Int? = nil
    ) throws -> Int? {
        guard let value else {
            return defaultValue
        }
        guard let integer = value.intValue, range.contains(integer) else {
            throw UsersInputValidationError("'\(name)' must be an integer from \(range.lowerBound) through \(range.upperBound)")
        }
        return integer
    }

    private func nullableBool(_ value: Value?, name: String) throws -> ASCNullable<Bool>? {
        guard let value else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let boolean = value.boolValue else {
            throw UsersInputValidationError("'\(name)' must be a boolean or null")
        }
        return .value(boolean)
    }

    private func isValidEmail(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let regex = try? NSRegularExpression(pattern: #"^[^@\s]+@[^@\s]+$"#)
        guard let match = regex?.firstMatch(in: value, range: range) else {
            return false
        }
        return match.range == range
    }

    private func commaSeparated(
        _ value: Value?,
        name: String,
        allowedValues: Set<String>? = nil
    ) throws -> String? {
        guard let value else {
            return nil
        }

        let values: [String]
        if let string = value.stringValue {
            values = string.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let array = value.arrayValue {
            let strings = array.compactMap(\.stringValue)
            guard strings.count == array.count else {
                throw UsersInputValidationError("'\(name)' must be a string or an array of strings")
            }
            values = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            throw UsersInputValidationError("'\(name)' must be a string or an array of strings")
        }

        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw UsersInputValidationError("'\(name)' must contain at least one non-empty value")
        }
        guard Set(values).count == values.count else {
            throw UsersInputValidationError("'\(name)' must not contain duplicate values")
        }
        if let allowedValues {
            let unsupported = values.filter { !allowedValues.contains($0) }
            guard unsupported.isEmpty else {
                throw UsersInputValidationError("Unsupported value(s) for '\(name)': \(unsupported.joined(separator: ", "))")
            }
        }

        return values.joined(separator: ",")
    }

    private func validatedStringArray(
        _ value: Value,
        name: String,
        allowEmpty: Bool,
        allowedValues: Set<String>? = nil
    ) throws -> [String] {
        guard let array = value.arrayValue else {
            throw UsersInputValidationError("'\(name)' must be an array of strings")
        }
        let values = array.compactMap(\.stringValue)
        guard values.count == array.count else {
            throw UsersInputValidationError("'\(name)' must contain only strings")
        }
        guard allowEmpty || !values.isEmpty else {
            throw UsersInputValidationError("'\(name)' must contain at least one value")
        }
        guard values.allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed == value
        }) else {
            throw UsersInputValidationError("'\(name)' must contain only non-empty strings without surrounding whitespace")
        }
        guard Set(values).count == values.count else {
            throw UsersInputValidationError("'\(name)' must not contain duplicate values")
        }
        if let allowedValues {
            let unsupported = values.filter { !allowedValues.contains($0) }
            guard unsupported.isEmpty else {
                if name == "roles" {
                    throw UsersInputValidationError(
                        "Unsupported role(s): \(unsupported.joined(separator: ", ")). Valid roles: \(allowedValues.sorted().joined(separator: ", "))"
                    )
                }
                throw UsersInputValidationError("Unsupported value(s) for '\(name)': \(unsupported.joined(separator: ", "))")
            }
        }
        return values
    }
}

private struct UsersInputValidationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
