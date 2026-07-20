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
            var queryParams: [String: String] = [:]

            if let appIdValue = arguments["app_id"],
               let appId = appIdValue.stringValue {
                queryParams["filter[apps]"] = appId
            }
            applyStringList(arguments["first_name"], as: "filter[firstName]", to: &queryParams)
            applyStringList(arguments["last_name"], as: "filter[lastName]", to: &queryParams)
            applyStringList(arguments["email"], as: "filter[email]", to: &queryParams)
            applyStringList(arguments["invite_type"], as: "filter[inviteType]", to: &queryParams)
            applyStringList(arguments["group_ids"], as: "filter[betaGroups]", to: &queryParams)
            applyStringList(arguments["build_ids"], as: "filter[builds]", to: &queryParams)
            applyStringList(arguments["tester_ids"], as: "filter[id]", to: &queryParams)
            if let sort = arguments["sort"]?.stringValue {
                queryParams["sort"] = sort
            }

            if let limitValue = arguments["limit"],
               let limit = limitValue.intValue {
                queryParams["limit"] = String(min(max(limit, 1), 200))
            } else {
                queryParams["limit"] = "25"
            }

            // Check for pagination URL
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/betaTesters",
                        query: queryParams
                    ),
                    as: ASCBetaTestersResponse.self
                )
            } else {
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list beta testers: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameter 'email' is missing")],
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
            queryParams["limit"] = String(min(max(arguments["limit"]?.intValue ?? 25, 1), 200))

            let response: ASCBetaTestersResponse
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(path: "/v1/betaTesters", query: queryParams),
                    as: ASCBetaTestersResponse.self
                )
            } else {
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to search beta testers: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameter 'tester_id' is missing")],
                isError: true
            )
        }

        let includes = parseStringList(arguments["include"])
        let allowedIncludes: Set<String> = ["apps", "betaGroups", "builds"]
        if let invalidInclude = includes?.first(where: { !allowedIncludes.contains($0) }) {
            return MCPResult.error("Unsupported include '\(invalidInclude)'. Valid values: apps, betaGroups, builds")
        }

        do {
            var queryParams: [String: String] = [:]
            if let includes, !includes.isEmpty {
                queryParams["include"] = includes.joined(separator: ",")
            }

            let response: ASCBetaTesterResponse = try await httpClient.get(
                "/v1/betaTesters/\(try ASCPathSegment.encode(testerId))",
                parameters: queryParams,
                as: ASCBetaTesterResponse.self
            )

            var testerDict = formatBetaTester(response.data)

            // Add included resources if present
            if let included = response.included {
                var includedApps: [[String: Any]] = []
                var includedGroups: [[String: Any]] = []
                var includedBuilds: [[String: Any]] = []

                for resource in included {
                    switch resource {
                    case .app(let app):
                        includedApps.append([
                            "id": app.id,
                            "name": (app.attributes?.name).jsonSafe
                        ])
                    case .betaGroup(let group):
                        includedGroups.append([
                            "id": group.id,
                            "name": group.attributes.name.jsonSafe
                        ])
                    case .build(let build):
                        includedBuilds.append([
                            "id": build.id,
                            "version": build.attributes.version.jsonSafe,
                            "processingState": build.attributes.processingState.jsonSafe,
                            "expired": build.attributes.expired.jsonSafe,
                            "buildAudienceType": build.attributes.buildAudienceType.jsonSafe
                        ])
                    }
                }

                if !includedApps.isEmpty {
                    testerDict["apps"] = includedApps
                }
                if !includedGroups.isEmpty {
                    testerDict["betaGroups"] = includedGroups
                }
                if !includedBuilds.isEmpty {
                    testerDict["builds"] = includedBuilds
                }
            }

            let result: [String: Any] = [
                "success": true,
                "beta_tester": testerDict
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get beta tester: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates/invites a new beta tester and assigns to beta groups
    /// - Returns: JSON with created tester details
    func createBetaTester(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let emailValue = arguments["email"],
              let email = emailValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'email' is missing")],
                isError: true
            )
        }

        let groupIds: [String]?
        if let values = arguments["group_ids"]?.arrayValue {
            let ids = values.compactMap(\.stringValue).filter { !$0.isEmpty }
            guard !ids.isEmpty, ids.count == values.count else {
                return MCPResult.error("'group_ids' must contain only non-empty beta group IDs")
            }
            groupIds = ids
        } else {
            groupIds = nil
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
                    relationships: groupIds == nil && buildIds == nil ? nil : CreateBetaTesterRequest.CreateBetaTesterRelationships(
                        betaGroups: groupIds.map {
                            CreateBetaTesterRequest.BetaGroupsRelationship(
                                data: $0.map { ASCResourceIdentifier(type: "betaGroups", id: $0) }
                            )
                        },
                        builds: buildIds.map {
                            CreateBetaTesterRequest.BuildsRelationship(
                                data: $0.map { ASCResourceIdentifier(type: "builds", id: $0) }
                            )
                        }
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to create beta tester: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a beta tester and removes from all groups
    /// - Returns: JSON with the confirmed or accepted deletion state
    func deleteBetaTester(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let testerIdValue = arguments["tester_id"],
              let testerId = testerIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'tester_id' is missing")],
                isError: true
            )
        }

        do {
            let receipt = try await httpClient.deleteReceipt(
                "/v1/betaTesters/\(try ASCPathSegment.encode(testerId))"
            )
            return betaTesterDeleteResult(
                receipt: receipt,
                target: ["tester_id": testerId],
                confirmedMessage: "Beta tester '\(testerId)' deleted",
                acceptedMessage: "Beta tester '\(testerId)' deletion accepted for processing",
                operationName: "beta tester deletion",
                inspection: [
                    "tool": "beta_testers_get",
                    "arguments": ["tester_id": testerId],
                    "instruction": "Inspect this exact tester before another delete attempt. A not-found response confirms deletion; a returned tester means processing is not complete."
                ]
            )

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete beta tester")
        }
    }

    /// Lists apps that a beta tester has access to
    /// - Returns: JSON array of apps with pagination
    func listBetaTesterApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let testerIdValue = arguments["tester_id"],
              let testerId = testerIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'tester_id' is missing")],
                isError: true
            )
        }

        do {
            let endpoint = "/v1/betaTesters/\(try ASCPathSegment.encode(testerId))/apps"
            let limit = arguments["limit"]?.intValue ?? 25
            let queryParams = ["limit": String(min(max(limit, 1), 200))]
            let response: ASCAppsResponse

            // Check for pagination URL
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

            if let nextUrl = response.links.next {
                result["next_url"] = nextUrl
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list beta tester apps: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameters 'beta_tester_id' and 'app_id' are missing")],
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to send invitation: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameters 'beta_tester_id' and 'group_ids' are missing")],
                isError: true
            )
        }

        let groupIds = groupIdsArray.compactMap { $0.stringValue }
        guard !groupIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("'group_ids' must contain at least one group ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: groupIds.map { ASCResourceIdentifier(type: "betaGroups", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/betaTesters/\(try ASCPathSegment.encode(betaTesterId))/relationships/betaGroups",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Added tester '\(betaTesterId)' to \(groupIds.count) group(s)"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to add tester to groups: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameters 'beta_tester_id' and 'group_ids' are missing")],
                isError: true
            )
        }

        let groupIds = groupIdsArray.compactMap { $0.stringValue }
        guard !groupIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("'group_ids' must contain at least one group ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: groupIds.map { ASCResourceIdentifier(type: "betaGroups", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaTesters/\(try ASCPathSegment.encode(betaTesterId))/relationships/betaGroups",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Removed tester '\(betaTesterId)' from \(groupIds.count) group(s)"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to remove tester from groups")
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
                content: [MCPContent.text("Required parameters 'beta_tester_id' and 'build_ids' are missing")],
                isError: true
            )
        }

        let buildIds = buildIdsArray.compactMap { $0.stringValue }
        guard !buildIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("'build_ids' must contain at least one build ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: buildIds.map { ASCResourceIdentifier(type: "builds", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post(
                "/v1/betaTesters/\(try ASCPathSegment.encode(betaTesterId))/relationships/builds",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Added \(buildIds.count) build(s) to tester '\(betaTesterId)'"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to add builds to tester: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Required parameters 'beta_tester_id' and 'build_ids' are missing")],
                isError: true
            )
        }

        let buildIds = buildIdsArray.compactMap { $0.stringValue }
        guard !buildIds.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("'build_ids' must contain at least one build ID")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: buildIds.map { ASCResourceIdentifier(type: "builds", id: $0) }
            )

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.delete(
                "/v1/betaTesters/\(try ASCPathSegment.encode(betaTesterId))/relationships/builds",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Removed \(buildIds.count) build(s) from tester '\(betaTesterId)'"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to remove builds from tester")
        }
    }

    /// Removes a beta tester's access to an app entirely
    /// - Returns: JSON with the confirmed or accepted relationship-deletion state
    func removeFromApp(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let betaTesterIdValue = arguments["beta_tester_id"],
              let betaTesterId = betaTesterIdValue.stringValue,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters 'beta_tester_id' and 'app_id' are missing")],
                isError: true
            )
        }

        do {
            let request = BetaGroupRelationshipRequest(
                data: [ASCResourceIdentifier(type: "apps", id: appId)]
            )

            let bodyData = try JSONEncoder().encode(request)
            let receipt = try await httpClient.deleteReceipt(
                "/v1/betaTesters/\(try ASCPathSegment.encode(betaTesterId))/relationships/apps",
                body: bodyData
            )
            return betaTesterDeleteResult(
                receipt: receipt,
                target: [
                    "beta_tester_id": betaTesterId,
                    "app_id": appId
                ],
                confirmedMessage: "Removed tester '\(betaTesterId)' from app '\(appId)'",
                acceptedMessage: "Removal of tester '\(betaTesterId)' from app '\(appId)' accepted for processing",
                operationName: "beta tester app-access removal",
                inspection: [
                    "tool": "beta_testers_list_apps",
                    "arguments": ["tester_id": betaTesterId],
                    "instruction": "Inspect this exact tester and verify that app_id '\(appId)' is absent before another delete attempt."
                ]
            )

        } catch {
            return MCPResult.error(error, prefix: "Failed to remove tester from app")
        }
    }

    // MARK: - Formatting

    private func betaTesterDeleteResult(
        receipt: ASCDeleteReceipt,
        target: [String: Any],
        confirmedMessage: String,
        acceptedMessage: String,
        operationName: String,
        inspection: [String: Any]
    ) -> CallTool.Result {
        var payload = target
        payload["statusCode"] = receipt.statusCode
        payload["retrySafe"] = false

        switch receipt.statusCode {
        case 204:
            payload["success"] = true
            payload["deletionState"] = "confirmed"
            payload["operationCommitted"] = true
            payload["processingComplete"] = true
            payload["outcomeUnknown"] = false
            payload["message"] = confirmedMessage
            return MCPResult.jsonObject(payload)
        case 202:
            payload["success"] = true
            payload["deletionState"] = "accepted"
            payload["operationCommitState"] = "accepted"
            payload["acceptedForProcessing"] = true
            payload["processingComplete"] = false
            payload["outcomeUnknown"] = false
            payload["inspectionRequired"] = true
            payload["inspection"] = inspection
            payload["message"] = acceptedMessage
            return MCPResult.jsonObject(payload)
        default:
            payload["success"] = false
            payload["deletionState"] = "committed_unverified"
            payload["operationCommitState"] = "committed_unverified"
            payload["operationCommitted"] = true
            payload["processingComplete"] = false
            payload["inspectionRequired"] = true
            payload["inspection"] = inspection
            payload["error"] = "Apple accepted the \(operationName) with unexpected HTTP \(receipt.statusCode), but completion is unverified."
            return MCPResult.jsonObject(
                payload,
                text: "Error: Apple accepted the \(operationName) with unexpected HTTP \(receipt.statusCode), but completion is unverified. Inspect the exact target before another delete attempt.",
                isError: true
            )
        }
    }

    private func formatBetaTester(_ tester: ASCBetaTester) -> [String: Any] {
        var result: [String: Any] = [
            "id": tester.id,
            "type": tester.type,
            "email": tester.attributes.email.jsonSafe,
            "firstName": tester.attributes.firstName.jsonSafe,
            "lastName": tester.attributes.lastName.jsonSafe,
            "inviteType": tester.attributes.inviteType.jsonSafe,
            "state": tester.attributes.state.jsonSafe
        ]
        if let relationships = tester.relationships {
            var relationIds: [String: Any] = [:]
            if let apps = relationships.apps?.data {
                relationIds["appIds"] = apps.map(\.id)
            }
            if let groups = relationships.betaGroups?.data {
                relationIds["betaGroupIds"] = groups.map(\.id)
            }
            if let builds = relationships.builds?.data {
                relationIds["buildIds"] = builds.map(\.id)
            }
            result["relationships"] = relationIds
        }
        return result
    }

    private func formatApp(_ app: ASCApp) -> [String: Any] {
        return [
            "id": app.id,
            "name": (app.attributes?.name).jsonSafe,
            "bundleId": (app.attributes?.bundleId).jsonSafe
        ]
    }

    private func applyStringList(_ value: Value?, as appleName: String, to query: inout [String: String]) {
        if let values = parseStringList(value), !values.isEmpty {
            query[appleName] = values.joined(separator: ",")
        }
    }

    private func parseStringList(_ value: Value?) -> [String]? {
        if let string = value?.stringValue {
            let values = string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return values.isEmpty ? nil : values
        }
        guard let rawValues = value?.arrayValue, !rawValues.isEmpty else {
            return nil
        }
        let values = rawValues.compactMap(\.stringValue).filter { !$0.isEmpty }
        return values.count == rawValues.count ? values : nil
    }
}
